import SwiftUI
import SharedModels
import AVFoundation
import AppKit

struct AudioDevicesView: View {
    @ObservedObject private var deviceManager = AudioDeviceManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: MOPDesign.Spacing.sectionGap) {
                microphoneStatus

                deviceSection(
                    title: "Input Device",
                    subtitle: "Microphone for recording",
                    useSystemDefault: $deviceManager.useSystemDefaultInput,
                    selectedUID: $deviceManager.selectedInputDeviceUID,
                    devices: deviceManager.availableInputDevices.filter { $0.uid != "system_default" },
                    onSystemDefaultToggle: {
                        deviceManager.useSystemDefaultInput = true
                        deviceManager.savePreferences()
                    },
                    onSpecificToggle: {
                        deviceManager.useSystemDefaultInput = false
                        deviceManager.savePreferences()
                    },
                    onDeviceSelect: { uid in
                        deviceManager.selectedInputDeviceUID = uid
                        deviceManager.savePreferences()
                    }
                )

                deviceSection(
                    title: "Output Device",
                    subtitle: "Speaker for playback",
                    useSystemDefault: $deviceManager.useSystemDefaultOutput,
                    selectedUID: $deviceManager.selectedOutputDeviceUID,
                    devices: deviceManager.availableOutputDevices.filter { $0.uid != "system_default" },
                    onSystemDefaultToggle: {
                        deviceManager.useSystemDefaultOutput = true
                        deviceManager.savePreferences()
                    },
                    onSpecificToggle: {
                        deviceManager.useSystemDefaultOutput = false
                        deviceManager.savePreferences()
                    },
                    onDeviceSelect: { uid in
                        deviceManager.selectedOutputDeviceUID = uid
                        deviceManager.savePreferences()
                    }
                )
            }
            .padding(MOPDesign.Spacing.settings)
            .background(MOPDesign.Surface.content)
        }
        .navigationTitle("Audio Devices")
    }

    private var microphoneStatus: some View {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        return MOPCard {
            MOPSectionHeader(title: "Microphone access")

            HStack(spacing: MOPDesign.Spacing.output) {
                MOPStatusMarker(state: status == .authorized ? .completed : .needsInput)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status == .authorized ? "Ready" : "Allow MOP to record audio in System Settings.")
                        .font(MOPDesign.Typography.helper)
                        .foregroundStyle(MOPDesign.Text.tertiary)
                }
                Spacer()
                if status != .authorized {
                    Button("Open Settings") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func deviceSection(
        title: String,
        subtitle: String,
        useSystemDefault: Binding<Bool>,
        selectedUID: Binding<String?>,
        devices: [AudioDevice],
        onSystemDefaultToggle: @escaping () -> Void,
        onSpecificToggle: @escaping () -> Void,
        onDeviceSelect: @escaping (String) -> Void
    ) -> some View {
        MOPCard {
            MOPSectionHeader(title: title)
            Text(subtitle)
                .font(MOPDesign.Typography.helper)
                .foregroundStyle(MOPDesign.Text.tertiary)

            VStack(alignment: .leading, spacing: MOPDesign.Spacing.denseRow) {
                selectionOption(
                    title: "Follow system default",
                    description: "Automatically uses the system's selected device",
                    isSelected: useSystemDefault.wrappedValue,
                    action: onSystemDefaultToggle
                )
                selectionOption(
                    title: "Use a specific device",
                    description: "Always use a particular device",
                    isSelected: !useSystemDefault.wrappedValue,
                    action: onSpecificToggle
                )

                if !useSystemDefault.wrappedValue && !devices.isEmpty {
                    MOPSettingsRow(title: "Device") {
                        Picker("Device", selection: Binding(
                            get: { selectedUID.wrappedValue ?? devices.first?.uid ?? "" },
                            set: { onDeviceSelect($0) }
                        )) {
                            ForEach(devices, id: \.uid) { device in
                                Text(device.name).tag(device.uid)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                } else if !useSystemDefault.wrappedValue {
                    Text("No audio devices are available.")
                        .font(MOPDesign.Typography.helper)
                        .foregroundStyle(MOPDesign.Text.tertiary)
                        .padding(.vertical, MOPDesign.Spacing.settingsRow)
                }
            }
        }
    }

    private func selectionOption(
        title: String,
        description: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: MOPDesign.Spacing.output) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : MOPDesign.Text.tertiary)
                    .font(MOPDesign.Typography.controlLabel)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(MOPDesign.Typography.rowLabel)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(MOPDesign.Typography.helper)
                        .foregroundStyle(MOPDesign.Text.tertiary)
                }

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, MOPDesign.Spacing.settingsRow)
    }
}
