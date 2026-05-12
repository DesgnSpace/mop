import Foundation
import AVFoundation
import WhisperKit
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

    private let logger = Logger(subsystem: "com.mop.audio", category: "recording")

    init() {
        requestMicrophonePermission()
        setupEngineConfigObserver()
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
        isStartingRecording = true
        audioBuffer.removeAll()
        audioConverter = nil

        // Recreate engine each start — ensures clean state after BT route changes
        audioEngine?.stop()
        audioEngine = nil
        audioEngine = AVAudioEngine()

        guard let audioEngine else {
            logger.error("Failed to create audio engine")
            isRecording = false
            isStartingRecording = false
            return
        }

        let inputNode = audioEngine.inputNode
        configureInputDevice()

        escapeKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53, self?.isRecording == true {
                DispatchQueue.main.async { self?.cancelRecording() }
            }
        }

        audioEngine.prepare()
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            logger.error("Degenerate input format (sampleRate=\(recordingFormat.sampleRate) channels=\(recordingFormat.channelCount)) — device not ready")
            isRecording = false
            isStartingRecording = false
            audioEngine.stop()
            self.audioEngine = nil
            DispatchQueue.main.async {
                self.delegate?.transcriptionDidFail(error: "Audio input not ready — reconnect device or switch input in Settings")
            }
            return
        }

        let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        if recordingFormat.sampleRate != sampleRate || recordingFormat.channelCount != 1 {
            audioConverter = AVAudioConverter(from: recordingFormat, to: targetFormat)
            logger.info("Converter: \(recordingFormat.sampleRate) Hz / \(recordingFormat.channelCount)ch → 16000 Hz / 1ch")
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.processTapBuffer(buffer)
        }

        do {
            try audioEngine.start()
            logger.info("Recording started (format: \(recordingFormat.sampleRate) Hz, \(recordingFormat.channelCount)ch)")
            isStartingRecording = false
            DispatchQueue.main.async { [weak self] in
                self?.delegate?.recordingDidStart()
            }
        } catch {
            logger.error("Failed to start audio engine: \(error.localizedDescription)")
            isRecording = false
            isStartingRecording = false
        }
    }

    private func processTapBuffer(_ buffer: AVAudioPCMBuffer) {
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

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
        teardownRecordingSession()
        logger.info("Recording stopped — captured \(self.audioBuffer.count) samples")
        Task { await processRecording() }
    }

    func cancelRecording() {
        isRecording = false
        teardownRecordingSession()
        audioBuffer.removeAll()
        logger.info("Recording cancelled")
        delegate?.recordingWasCancelled()
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

        let store = await CleanupProfileStore.shared
        let activeProfile = await store.resolveActive(forFrontmostBundleID: activeBundleID)
        let effectiveDriver = activeProfile.driverOverride ?? CleanupConfig.selectedDriver
        let prompt = activeProfile.prompt
        do {
            let cleaned = try await runCleanup(text: processedRaw, prompt: prompt, driver: effectiveDriver)
            let finalText = usableCleanedText(cleaned, rawText: processedRaw)

            print("Transcription lengths: raw=\(processedRaw.count), cleaned=\(cleaned.count), final=\(finalText.count)")
            TranscriptionHistory.shared.addEntry(processedRaw, tag: "raw")
            TranscriptionHistory.shared.addEntry(finalText, tag: "cleaned")
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

    private func runCleanup(text: String, prompt: String, driver: CleanupDriver = CleanupConfig.selectedDriver) async throws -> String {
        try await CleanupDriverRegistry.driver(for: driver).cleanup(text, prompt: prompt)
    }
}
