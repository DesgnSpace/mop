import Foundation
import AVFoundation
import WhisperKit
import FluidAudio
import Speech
import AppKit
import SharedModels
import CoreAudio
import os

protocol AudioTranscriptionManagerDelegate: AnyObject {
    func recordingDidStart()
    func audioLevelDidUpdate(db: Float)
    func transcriptionDidStart()
    func transcriptionDidComplete(text: String)
    func transcriptionDidCleanUp(text: String)
    func transcriptionDidFail(error: String)
    func recordingWasCancelled()
    func recordingWasSkippedDueToSilence()
    func transcriptionDidUpdatePartial(text: String)
    func transcriptionDidEndUtterance(text: String)
}

extension AudioTranscriptionManagerDelegate {
    func transcriptionDidUpdatePartial(text: String) {}
    func transcriptionDidEndUtterance(text: String) {}
}

class AudioTranscriptionManager {
    weak var delegate: AudioTranscriptionManagerDelegate?
    
    // Audio properties
    private var audioEngine: AVAudioEngine?
    private var audioConverter: AVAudioConverter?
    private var audioBuffer: [Float] = []
    private let sampleRate: Double = 16000
    private let maxBufferSamples = 16000 * 300  // 5 minutes max to prevent memory explosion

    // Recording state
    var isRecording = false
    private var isStartingRecording = false  // Prevents race condition
    private var escapeKeyMonitor: Any?
    private var engineConfigObserver: NSObjectProtocol?

    // Transcription state
    private var isTranscribing = false
    private var activeBundleID: String?
    private var activeURLHost: String?

    // Live streaming state (Phase 1 — gated by TranscriptionPreferences.useLiveTranscription)
    private var streamingParakeet: StreamingEouAsrManager?
    private var streamingModelReady = false  // true once loadModels() or reset() completes
    private var speechBridge: AnyObject? // LiveSpeechAnalyzerBridge on macOS 26+
    private var liveSessionActive = false
    private var liveAudioFeedTask: Task<Void, Never>?
    private var liveCleanupTask: Task<Void, Never>?

    private let logger = Logger(subsystem: "com.mop.audio", category: "recording")

    init() {
        requestMicrophonePermission()
        setupEngineConfigObserver()
        preloadStreamingModelIfNeeded()
    }

    private func preloadStreamingModelIfNeeded() {
        guard TranscriptionPreferences.useLiveTranscription else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, ModelStateManager.shared.selectedEngine == .parakeet else { return }
            self.startLiveSession()
        }
    }

    deinit {
        if let observer = engineConfigObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupEngineConfigObserver() {
        engineConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleEngineConfigurationChange()
        }
    }

    private func handleEngineConfigurationChange() {
        logger.info("Audio engine configuration changed (route change or device disconnect)")
        guard isRecording else {
            audioEngine?.stop()
            audioEngine = nil
            audioConverter = nil
            return
        }
        logger.info("Route change while recording — rebuilding engine")
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioConverter = nil
        audioBuffer.removeAll()
        startRecording()
    }

    private func configureInputDevice() {
        let deviceManager = AudioDeviceManager.shared
        guard let engine = audioEngine else { return }

        let inputNode = engine.inputNode

        if !deviceManager.useSystemDefaultInput,
           let uid = deviceManager.selectedInputDeviceUID,
           let deviceID = deviceManager.getAudioDeviceID(for: uid) {
            do {
                try inputNode.auAudioUnit.setDeviceID(deviceID)
                let deviceName = deviceManager.availableInputDevices.first { $0.uid == uid }?.name ?? uid
                logger.info("Using custom input device: '\(deviceName)'")
            } catch {
                logger.warning("setDeviceID failed (\(error.localizedDescription)) — falling back to system default")
            }
        } else {
            logger.info("Using system default input device")
        }
    }
    
    private func requestMicrophonePermission() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if granted {
                print("Microphone permission granted")
            } else {
                print("Microphone permission denied")
                DispatchQueue.main.async {
                    self.showPermissionAlert()
                }
            }
        }
    }
    
    private func showPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Microphone Permission Required"
        alert.informativeText = "Please grant microphone access in System Settings > Privacy & Security > Microphone"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    func toggleRecording() {
        // Prevent race condition if called while starting
        if isStartingRecording {
            return
        }

        isRecording.toggle()

        if isRecording {
            startRecording()
        } else {
            stopRecording()
        }
    }

    func startRecording() {
        activeBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        activeURLHost = BrowserURLDetector.host(forBundleID: activeBundleID)
        isStartingRecording = true
        audioBuffer.removeAll()
        audioConverter = nil

        // Show HUD and register escape key immediately — before engine warms up
        delegate?.recordingDidStart()
        escapeKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.isRecording == true {
                DispatchQueue.main.async { self?.cancelRecording() }
            }
        }

        // Push all AVAudioEngine work off the main thread
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self else { return }

            self.audioEngine?.stop()
            self.audioEngine = nil
            self.audioEngine = AVAudioEngine()

            guard let audioEngine = self.audioEngine else {
                self.logger.error("Failed to create audio engine")
                self.isRecording = false
                self.isStartingRecording = false
                return
            }

            let inputNode = audioEngine.inputNode
            self.configureInputDevice()
            audioEngine.prepare()
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                self.logger.error("Degenerate input format (sampleRate=\(recordingFormat.sampleRate) channels=\(recordingFormat.channelCount)) — device not ready")
                self.isRecording = false
                self.isStartingRecording = false
                audioEngine.stop()
                self.audioEngine = nil
                DispatchQueue.main.async {
                    self.delegate?.transcriptionDidFail(error: "Audio input not ready — reconnect device or switch input in Settings")
                }
                return
            }

            let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: self.sampleRate, channels: 1, interleaved: false)!
            if recordingFormat.sampleRate != self.sampleRate || recordingFormat.channelCount != 1 {
                self.audioConverter = AVAudioConverter(from: recordingFormat, to: targetFormat)
                self.logger.info("Converter: \(recordingFormat.sampleRate) Hz / \(recordingFormat.channelCount)ch → 16000 Hz / 1ch")
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.processTapBuffer(buffer)
            }

            do {
                try audioEngine.start()
                self.logger.info("Recording started (format: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount)ch)")
                self.isStartingRecording = false
                if TranscriptionPreferences.useLiveTranscription {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        if ModelStateManager.shared.selectedEngine == .parakeet {
                            self.startLiveSession()
                        } else if #available(macOS 26.0, *) {
                            self.startSpeechAnalyzerSession()
                        }
                    }
                }
            } catch {
                self.logger.error("Failed to start audio engine: \(error.localizedDescription)")
                self.isRecording = false
                self.isStartingRecording = false
            }
        }
    }

    private func startLiveSession() {
        if streamingModelReady, streamingParakeet != nil {
            // Model already loaded — activate immediately without reloading
            liveSessionActive = true
            logger.info("Live streaming resumed (Parakeet EOU)")
            return
        }

        // Model not yet loaded (first use or after error) — load in background
        guard streamingParakeet == nil else { return }  // already loading, don't double-load

        Task {
            let manager = StreamingEouAsrManager(chunkSize: .ms160)
            await manager.setPartialTranscriptCallback { [weak self] text in
                guard !text.isEmpty else { return }
                DispatchQueue.main.async { self?.delegate?.transcriptionDidUpdatePartial(text: text) }
            }
            await manager.setEouCallback { [weak self] utterance in
                guard !utterance.isEmpty else { return }
                let previousTask = self?.liveCleanupTask
                self?.liveCleanupTask = Task { [weak self] in
                    await previousTask?.value
                    let text = await self?.cleanLiveUtterance(utterance) ?? utterance
                    DispatchQueue.main.async { self?.delegate?.transcriptionDidEndUtterance(text: text) }
                }
            }
            do {
                self.streamingParakeet = manager  // claim the slot to block double-loads
                try await manager.loadModels()
                self.streamingModelReady = true
                if self.isRecording {
                    self.liveSessionActive = true
                    self.logger.info("Live streaming session started (Parakeet EOU 160ms)")
                } else {
                    self.logger.info("Parakeet EOU model loaded and ready")
                }
            } catch {
                self.streamingParakeet = nil
                logger.warning("Streaming model load failed: \(error)")
            }
        }
    }

    @available(macOS 26.0, *)
    private func startSpeechAnalyzerSession() {
        let bridge = LiveSpeechAnalyzerBridge()
        speechBridge = bridge

        bridge.analyzeTask = Task { [weak self] in
            do {
                try await bridge.analyzer.start(inputSequence: bridge.stream)
            } catch {
                self?.logger.warning("SpeechAnalyzer start failed: \(error.localizedDescription)")
            }
        }

        bridge.resultsTask = Task { [weak self] in
            var lastText = ""
            do {
                for try await result in bridge.transcriber.results {
                    let text = result.description
                    guard !text.isEmpty else { continue }
                    lastText = text
                    await MainActor.run {
                        self?.delegate?.transcriptionDidUpdatePartial(text: text)
                    }
                }
            } catch {
                self?.logger.warning("SpeechAnalyzer results error: \(error.localizedDescription)")
            }
            return lastText
        }

        liveSessionActive = true
        logger.info("Live streaming session started (Apple Speech)")
    }

    private func processTapBuffer(_ buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        if liveSessionActive, let manager = streamingParakeet {
            let previousTask = liveAudioFeedTask
            liveAudioFeedTask = Task {
                await previousTask?.value
                do {
                    try await manager.appendAudio(buffer)
                    try await manager.processBufferedAudio()
                } catch {
                    self.logger.warning("Streaming audio feed failed: \(error.localizedDescription)")
                }
            }
        }

        if #available(macOS 26.0, *), liveSessionActive, let bridge = speechBridge as? LiveSpeechAnalyzerBridge {
            bridge.continuation.yield(AnalyzerInput(buffer: buffer))
        }

        if let converter = audioConverter {
            let outputFrameCapacity = AVAudioFrameCount(ceil(Double(frameLength) * sampleRate / buffer.format.sampleRate))
            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: outputFrameCapacity) else { return }

            var error: NSError?
            var inputProvided = false
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if inputProvided {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                outStatus.pointee = .haveData
                inputProvided = true
                return buffer
            }

            guard status != .error, error == nil else {
                logger.warning("AVAudioConverter error: \(error?.localizedDescription ?? "unknown")")
                return
            }

            if let data = outputBuffer.floatChannelData?[0] {
                appendSamples(data, count: Int(outputBuffer.frameLength))
            }
        } else if let data = buffer.floatChannelData?[0] {
            appendSamples(data, count: frameLength)
        }
    }

    private func appendSamples(_ data: UnsafePointer<Float>, count: Int) {
        audioBuffer.append(contentsOf: UnsafeBufferPointer(start: data, count: count))

        if audioBuffer.count > maxBufferSamples {
            logger.warning("Audio buffer limit reached (5 min). Auto-stopping recording.")
            DispatchQueue.main.async {
                self.isRecording = false
                self.stopRecording()
            }
            return
        }

        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        let db = 20 * log10(max(sqrt(sum / Float(count)), 0.00001))

        DispatchQueue.main.async {
            self.delegate?.audioLevelDidUpdate(db: db)
        }
    }
    
    func stopRecording() {
        let wasLive = liveSessionActive
        liveSessionActive = false
        teardownRecordingSession()
        if wasLive {
            logger.info("Recording stopped (live) — finishing streaming session")
            Task { await finishLiveSession() }
        } else {
            logger.info("Recording stopped — captured \(self.audioBuffer.count) samples")
            Task { await processRecording() }
        }
    }

    func cancelRecording() {
        liveSessionActive = false
        liveAudioFeedTask?.cancel()
        liveAudioFeedTask = nil
        liveCleanupTask?.cancel()
        liveCleanupTask = nil
        isRecording = false
        teardownRecordingSession()
        audioBuffer.removeAll()
        if let manager = streamingParakeet {
            streamingModelReady = false
            Task {
                await manager.reset()
                self.streamingModelReady = true
            }
        }
        if #available(macOS 26.0, *), let bridge = speechBridge as? LiveSpeechAnalyzerBridge {
            speechBridge = nil
            bridge.analyzeTask?.cancel()
            bridge.resultsTask?.cancel()
            bridge.continuation.finish()
        }
        logger.info("Recording cancelled")
        delegate?.recordingWasCancelled()
    }

    @MainActor
    private func finishLiveSession() async {
        if let manager = streamingParakeet {
            // Keep streamingParakeet alive — just reset it for the next session
            streamingModelReady = false
            delegate?.transcriptionDidStart()
            isTranscribing = true
            do {
                await liveAudioFeedTask?.value
                liveAudioFeedTask = nil
                let streamingText = try await manager.finish()
                await manager.reset()
                streamingModelReady = true
                isTranscribing = false
                logger.info("Streaming finish: \(streamingText.count) chars")
                await handleTranscriptionResult(streamingText)
            } catch {
                logger.error("Streaming finish failed (\(error)) — falling back to batch")
                streamingParakeet = nil  // discard on error, will reload next session
                isTranscribing = false
                await processRecording()
            }
        } else if #available(macOS 26.0, *), let bridge = speechBridge as? LiveSpeechAnalyzerBridge {
            speechBridge = nil
            delegate?.transcriptionDidStart()
            isTranscribing = true
            bridge.continuation.finish()
            do {
                try await bridge.analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                logger.warning("SpeechAnalyzer finalize failed: \(error.localizedDescription)")
            }
            let finalText = await bridge.resultsTask?.value ?? ""
            isTranscribing = false
            if finalText.isEmpty {
                logger.warning("SpeechAnalyzer produced no text — falling back to batch")
                await processRecording()
            } else {
                logger.info("Speech session finish: \(finalText.count) chars")
                await handleTranscriptionResult(finalText)
            }
        } else {
            logger.warning("Live session ended but no streaming manager — falling back to batch")
            await processRecording()
        }
    }

    private func teardownRecordingSession() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        audioConverter = nil

        if let monitor = escapeKeyMonitor {
            NSEvent.removeMonitor(monitor)
            escapeKeyMonitor = nil
        }
    }
    
    @MainActor
    private func processRecording() async {
        guard !audioBuffer.isEmpty else {
            print("No audio recorded")
            // Nothing to transcribe; ensure UI resets
            delegate?.recordingWasSkippedDueToSilence()
            return
        }

        // Skip extremely short recordings to avoid spurious transcriptions
        let durationSeconds = Double(audioBuffer.count) / sampleRate
        let minDurationSeconds: Double = 0.30
        if durationSeconds < minDurationSeconds {
            print("Recording too short (\(String(format: "%.2f", durationSeconds))s). Skipping transcription.")
            delegate?.recordingWasSkippedDueToSilence()
            return
        }

        // Calculate RMS (Root Mean Square) to detect silence
        let rms = sqrt(audioBuffer.reduce(0) { $0 + $1 * $1 } / Float(audioBuffer.count))
        let db = 20 * log10(max(rms, 0.00001))

        // Threshold for silence detection (stricter to avoid false positives)
        // Lowered to -55dB to capture quieter audio
        let silenceThreshold: Float = -55.0

        if db < silenceThreshold {
            print("Audio too quiet (RMS: \(rms), dB: \(db)). Skipping transcription.")
            // Reset the status bar icon when skipping quiet audio
            delegate?.recordingWasSkippedDueToSilence()
            return
        }

        // Start transcription
        delegate?.transcriptionDidStart()
        isTranscribing = true

        // Route to appropriate transcriber based on selected engine
        switch ModelStateManager.shared.selectedEngine {
        case .whisperKit:
            await transcribeWithWhisperKit()
        case .parakeet:
            await transcribeWithParakeet()
        case .qwen3:
            await transcribeWithQwen3()
        }
    }

    @MainActor
    private func transcribeWithWhisperKit() async {
        // Load model if not already loaded
        if ModelStateManager.shared.loadedWhisperKit == nil {
            if let selectedModel = ModelStateManager.shared.selectedModel {
                _ = await ModelStateManager.shared.loadModel(selectedModel)
            }
        }

        guard let whisperKit = ModelStateManager.shared.loadedWhisperKit else {
            print("WhisperKit not initialized - please select and download a model in Settings")
            isTranscribing = false
            delegate?.transcriptionDidFail(error: "No WhisperKit model loaded. Please select a model in Settings.")
            return
        }

        // Pad short audio with 1 second of silence to improve transcription reliability
        let paddingThresholdSeconds = 1.5
        let paddingDurationSeconds = 1.0
        let minSamplesForPadding = Int(paddingThresholdSeconds * sampleRate)
        let paddingSamples = Int(paddingDurationSeconds * sampleRate)

        var paddedBuffer = audioBuffer
        if audioBuffer.count < minSamplesForPadding {
            paddedBuffer.append(contentsOf: [Float](repeating: 0.0, count: paddingSamples))
            print("Padded short audio with \(paddingDurationSeconds)s of silence")
        }

        print("Transcribing \(audioBuffer.count) samples (\(Double(audioBuffer.count) / sampleRate) seconds) with WhisperKit...")

        do {
            let transcriptionResult = try await whisperKit.transcribe(
                audioArray: paddedBuffer,
                decodeOptions: DecodingOptions(
                    verbose: false,
                    task: .transcribe,
                    language: "en",
                    temperature: 0.0,
                    temperatureFallbackCount: 3,
                    sampleLength: 224,
                    topK: 5,
                    usePrefillPrompt: true,
                    usePrefillCache: true,
                    skipSpecialTokens: true,
                    withoutTimestamps: false,
                    clipTimestamps: [],
                    suppressBlank: true,
                    supressTokens: nil,
                    chunkingStrategy: .vad
                )
            )

            isTranscribing = false

            let transcription = combineWhisperKitResults(transcriptionResult)
            let segmentCount = transcriptionResult.reduce(0) { $0 + $1.segments.count }
            print("WhisperKit returned \(transcriptionResult.count) result(s), \(segmentCount) segment(s), \(transcription.count) chars")
            await handleTranscriptionResult(transcription)
        } catch {
            print("WhisperKit transcription error: \(error)")
            isTranscribing = false
            delegate?.transcriptionDidFail(error: "Transcription failed: \(error.localizedDescription)")
        }
    }

    private func combineWhisperKitResults(_ results: [TranscriptionResult]) -> String {
        let segments = results
            .flatMap(\.segments)
            .sorted { $0.start < $1.start }

        if !segments.isEmpty {
            return segments
                .map(\.text)
                .joined(separator: " ")
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        }

        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
    }

    @MainActor
    private func transcribeWithParakeet() async {
        // Load model if not already loaded
        if ModelStateManager.shared.loadedParakeetTranscriber == nil ||
           ModelStateManager.shared.parakeetLoadingState != .loaded {
            await ModelStateManager.shared.loadParakeetModel()
        }

        guard let transcriber = ModelStateManager.shared.loadedParakeetTranscriber,
              await transcriber.isReady else {
            print("Parakeet not initialized - please select Parakeet in Settings and wait for model to load")
            isTranscribing = false
            delegate?.transcriptionDidFail(error: "No Parakeet model loaded. Please wait for model to download in Settings.")
            return
        }

        // Pad short audio with 1 second of silence to improve transcription reliability
        let paddingThresholdSeconds = 1.5
        let paddingDurationSeconds = 1.0
        let minSamplesForPadding = Int(paddingThresholdSeconds * sampleRate)
        let paddingSamples = Int(paddingDurationSeconds * sampleRate)

        var paddedBuffer = audioBuffer
        if audioBuffer.count < minSamplesForPadding {
            paddedBuffer.append(contentsOf: [Float](repeating: 0.0, count: paddingSamples))
            print("Padded short audio with \(paddingDurationSeconds)s of silence")
        }

        print("Transcribing \(audioBuffer.count) samples (\(Double(audioBuffer.count) / sampleRate) seconds) with Parakeet...")

        do {
            let transcription = try await transcriber.transcribe(audioSamples: paddedBuffer)
            isTranscribing = false
            await handleTranscriptionResult(transcription)
        } catch {
            print("Parakeet transcription error: \(error)")
            isTranscribing = false
            delegate?.transcriptionDidFail(error: "Transcription failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func transcribeWithQwen3() async {
        guard #available(macOS 15, *) else {
            isTranscribing = false
            delegate?.transcriptionDidFail(error: "Qwen3 ASR requires macOS 15 or later.")
            return
        }

        if ModelStateManager.shared.loadedQwen3Transcriber == nil ||
           ModelStateManager.shared.qwen3LoadingState != .loaded {
            await ModelStateManager.shared.loadQwen3Model()
        }

        guard let transcriber = ModelStateManager.shared.loadedQwen3Transcriber as? Qwen3Transcriber,
              transcriber.isReady else {
            isTranscribing = false
            delegate?.transcriptionDidFail(error: "No Qwen3 model loaded. Please wait for model to download in Settings.")
            return
        }

        let paddingThresholdSeconds = 1.5
        let paddingDurationSeconds = 1.0
        let minSamplesForPadding = Int(paddingThresholdSeconds * sampleRate)
        let paddingSamples = Int(paddingDurationSeconds * sampleRate)

        var paddedBuffer = audioBuffer
        if audioBuffer.count < minSamplesForPadding {
            paddedBuffer.append(contentsOf: [Float](repeating: 0.0, count: paddingSamples))
        }

        print("Transcribing \(audioBuffer.count) samples with Qwen3...")

        do {
            let transcription = try await transcriber.transcribe(audioSamples: paddedBuffer)
            isTranscribing = false
            await handleTranscriptionResult(transcription)
        } catch {
            print("Qwen3 transcription error: \(error)")
            isTranscribing = false
            delegate?.transcriptionDidFail(error: "Transcription failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func handleTranscriptionResult(_ rawTranscription: String) async {
        let rawText = rawTranscription.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !rawText.isEmpty else {
            print("No transcription generated (possibly silence)")
            delegate?.recordingWasSkippedDueToSilence()
            return
        }

        let processedRaw = TextReplacements.shared.processText(rawText)

        delegate?.transcriptionDidComplete(text: processedRaw)

        guard TranscriptionPreferences.useTextCleanup else {
            TranscriptionHistory.shared.addEntry(processedRaw, tag: "raw")
            return
        }

        let store = CleanupProfileStore.shared
        let activeProfile = store.resolveActive(forFrontmostBundleID: activeBundleID, urlHost: activeURLHost)
        let effectiveDriver = activeProfile.driverOverride ?? CleanupConfig.selectedDriver

        let prompt = activeProfile.prompt
        do {
            var result = try await runCleanup(text: processedRaw, prompt: prompt, driver: effectiveDriver)
            result.profileName = activeProfile.name
            let finalText = usableCleanedText(result.text, rawText: processedRaw)

            print("Transcription lengths: raw=\(processedRaw.count), cleaned=\(result.text.count), final=\(finalText.count)")
            CleanupCallLog.shared.setLastProfileName(activeProfile.name)
            TranscriptionHistory.shared.addEntry(processedRaw, tag: "raw", model: result.model)
            TranscriptionHistory.shared.addEntry(finalText, tag: "cleaned", model: result.model, profileName: result.profileName)
            delegate?.transcriptionDidCleanUp(text: finalText)
        } catch {
            print("⚠️ Cleanup failed, pasting raw transcription: \(error.localizedDescription)")
            TranscriptionHistory.shared.addEntry(processedRaw, tag: "raw")
            delegate?.transcriptionDidCleanUp(text: processedRaw)
        }
    }

    private func usableCleanedText(_ cleanedText: String, rawText: String) -> String {
        let cleaned = cleanedText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return rawText }

        let minimumLength = max(20, Int(Double(rawText.count) * 0.70))
        guard cleaned.count >= minimumLength else {
            print("Cleanup output too short; using raw transcription")
            return rawText
        }

        return cleaned
    }

    @MainActor
    private func cleanLiveUtterance(_ utterance: String) async -> String {
        let rawText = TextReplacements.shared.processText(
            utterance.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        )
        guard TranscriptionPreferences.useTextCleanup,
              TranscriptionPreferences.cleanupLiveTranscription,
              !rawText.isEmpty else { return rawText }

        let store = CleanupProfileStore.shared
        let activeProfile = store.resolveActive(forFrontmostBundleID: activeBundleID, urlHost: activeURLHost)
        let effectiveDriver = activeProfile.driverOverride ?? CleanupConfig.selectedDriver
        let prompt = liveCleanupPrompt(profilePrompt: activeProfile.prompt)

        do {
            var result = try await runCleanup(text: rawText, prompt: prompt, driver: effectiveDriver)
            result.profileName = activeProfile.name
            CleanupCallLog.shared.setLastProfileName(activeProfile.name)
            return usableCleanedText(result.text, rawText: rawText)
        } catch {
            logger.warning("Live cleanup failed: \(error.localizedDescription)")
            return rawText
        }
    }

    private func liveCleanupPrompt(profilePrompt: String) -> String {
        """
        You are cleaning one finalized phrase from live dictation before it is inserted.
        Keep meaning unchanged. Remove filler words, duplicate fragments, and obvious false starts.
        If the speaker corrects themselves ("no", "scratch that", "actually"), keep the corrected intent.
        Output only the cleaned phrase. No quotes, markdown, or explanation.

        Profile rules:
        \(profilePrompt)
        """
    }

    private func runCleanup(text: String, prompt: String, driver: CleanupDriver = CleanupConfig.selectedDriver) async throws -> CleanupResult {
        try await CleanupDriverRegistry.driver(for: driver).cleanup(text, prompt: prompt)
    }
}

@available(macOS 26.0, *)
private final class LiveSpeechAnalyzerBridge {
    let continuation: AsyncStream<AnalyzerInput>.Continuation
    let stream: AsyncStream<AnalyzerInput>
    let transcriber: DictationTranscriber
    let analyzer: SpeechAnalyzer
    var analyzeTask: Task<Void, Never>?
    var resultsTask: Task<String, Never>?

    init() {
        let t = DictationTranscriber(locale: .current, preset: .progressiveLongDictation)
        var storedCont: AsyncStream<AnalyzerInput>.Continuation!
        let s = AsyncStream<AnalyzerInput> { storedCont = $0 }
        self.transcriber = t
        self.stream = s
        self.continuation = storedCont
        self.analyzer = SpeechAnalyzer(modules: [t])
    }
}
