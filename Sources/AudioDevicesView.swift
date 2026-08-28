import SwiftUI
import SharedModels

struct AudioDevicesView: View {
    @ObservedObject private var deviceManager = AudioDeviceManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                deviceSection(
                    title: "Input Device",
                    subtitle: "Microphone for recording",
                    icon: "mic.fill",
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
                    icon: "speaker.wave.2.fill",
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

    private func deviceSection(
        title: String,
        subtitle: String,
        icon: String,
        useSystemDefault: Binding<Bool>,
        selectedUID: Binding<String?>,
        devices: [AudioDevice],
        onSystemDefaultToggle: @escaping () -> Void,
        onSpecificToggle: @escaping () -> Void,
        onDeviceSelect: @escaping (String) -> Void
    ) -> some View {
        MOPCard {
            HStack(spacing: 10) {
                ZStack {
                    Image(systemName: icon)
                        .font(MOPDesign.Typography.controlLabel)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                            .font(MOPDesign.Typography.sectionHeader)

                    Text(subtitle)
                        .font(MOPDesign.Typography.helper)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    onSystemDefaultToggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: useSystemDefault.wrappedValue ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(useSystemDefault.wrappedValue ? Color.accentColor : .secondary)
                            .font(MOPDesign.Typography.controlLabel)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Follow System Default")
                                .font(MOPDesign.Typography.rowLabel)
                                .foregroundStyle(.primary)
                            Text("Automatically uses the system's selected device")
                                .font(MOPDesign.Typography.helper)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                Button {
                    onSpecificToggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: !useSystemDefault.wrappedValue ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(!useSystemDefault.wrappedValue ? Color.accentColor : .secondary)
                            .font(MOPDesign.Typography.controlLabel)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use Specific Device")
                                .font(MOPDesign.Typography.rowLabel)
                                .foregroundStyle(.primary)
                            Text("Always use a particular device")
                                .font(MOPDesign.Typography.helper)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                }
                .buttonStyle(.plain)

                if !useSystemDefault.wrappedValue && !devices.isEmpty {
                    Picker("Device", selection: Binding(
                        get: { selectedUID.wrappedValue ?? devices.first?.uid ?? "" },
                        set: { onDeviceSelect($0) }
                    )) {
                        ForEach(devices, id: \.uid) { device in
                            Text(device.name).tag(device.uid)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.leading, 28)
                }
            }
        }
    }
}
