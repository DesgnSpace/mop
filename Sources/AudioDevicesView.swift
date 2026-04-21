import SwiftUI
import SharedModels

struct AudioDevicesView: View {
    @ObservedObject private var deviceManager = AudioDeviceManager.shared

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    deviceSection(
                        title: "Input Device",
                        subtitle: "Microphone for recording",
                        icon: "mic.fill",
                        color: .blue,
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
                        color: .purple,
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
                .padding(20)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 28))
                .foregroundStyle(.linearGradient(
                    colors: [.purple, .indigo],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))

            VStack(alignment: .leading, spacing: 4) {
                Text("Audio Devices")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Configure input and output devices")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func deviceSection(
        title: String,
        subtitle: String,
        icon: String,
        color: Color,
        useSystemDefault: Binding<Bool>,
        selectedUID: Binding<String?>,
        devices: [AudioDevice],
        onSystemDefaultToggle: @escaping () -> Void,
        onSpecificToggle: @escaping () -> Void,
        onDeviceSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.12))
                        .frame(width: 32, height: 32)

                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(color)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)

                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    onSystemDefaultToggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: useSystemDefault.wrappedValue ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(useSystemDefault.wrappedValue ? color : .secondary)
                            .font(.system(size: 18))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Follow System Default")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("Automatically uses the system's selected device")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                            .foregroundColor(!useSystemDefault.wrappedValue ? color : .secondary)
                            .font(.system(size: 18))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Use Specific Device")
                                .font(.body)
                                .foregroundColor(.primary)
                            Text("Always use a particular device")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
    }
}
