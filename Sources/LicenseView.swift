import SwiftUI
import SharedModels

struct LicenseView: View {
    @State private var licenseState = LicenseStore.shared.state
    @State private var keyInput = ""
    @State private var isActivating = false
    @State private var isDeactivating = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                statusSection
                if case .expired = licenseState { buySection }
                activationSection
            }
            .padding(20)
        }
        .navigationTitle("License")
        .onAppear { licenseState = LicenseStore.shared.state }
    }

    // MARK: - Sections

    private var statusSection: some View {
        MOPCard {
            MOPSectionHeader(title: "License Status", icon: "key.fill")

            HStack(spacing: 12) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .fontWeight(.medium)
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.top, 4)

            if case .licensed = licenseState {
                Divider().padding(.leading, 52)
                Button(role: .destructive) { deactivate() } label: {
                    Label(isDeactivating ? "Deactivating…" : "Deactivate License", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(isDeactivating)
                .padding(.leading, 52)
            }
        }
    }

    private var buySection: some View {
        MOPCard {
            MOPSectionHeader(title: "Unlock MOP", icon: "star.fill")
            Text("Your trial has ended. Purchase a license to continue using MOP.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            Button {
                NSWorkspace.shared.open(URL(string: "https://mop.desgn.space/buy")!)
            } label: {
                Label("Buy MOP", systemImage: "cart.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 4)
        }
    }

    private var activationSection: some View {
        MOPCard {
            MOPSectionHeader(title: "Activate License", icon: "checkmark.seal")

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if let success = successMessage {
                Text(success)
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            TextField("License key (XXXX-XXXX-XXXX-XXXX)", text: $keyInput)
                .textFieldStyle(.roundedBorder)
                .disableAutocorrection(true)

            Button {
                activate()
            } label: {
                Label(isActivating ? "Activating…" : "Activate", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(keyInput.trimmingCharacters(in: .whitespaces).isEmpty || isActivating)

            Text("Already have a license? Paste it above. Need one?")
                .font(.caption)
                .foregroundStyle(.secondary)
            + Text(" Buy here →")
                .font(.caption)
                .foregroundStyle(Color.accentColor)
        }
        .onTapGesture {
            if case .licensed = licenseState { return }
        }
    }

    // MARK: - Actions

    private func activate() {
        errorMessage = nil
        successMessage = nil
        isActivating = true
        let key = keyInput.trimmingCharacters(in: .whitespaces)
        Task {
            defer { isActivating = false }
            do {
                let result = try await LemonSqueezyClient.shared.activate(licenseKey: key)
                LicenseStore.shared.activateLicense(
                    key: result.licenseKey,
                    instanceID: result.instanceID,
                    email: result.customerEmail
                )
                licenseState = LicenseStore.shared.state
                successMessage = "License activated! Welcome to MOP."
                keyInput = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func deactivate() {
        isDeactivating = true
        guard let key = LicenseStore.shared.activatedLicenseKey,
              let id = LicenseStore.shared.instanceID else {
            LicenseStore.shared.deactivateLicense()
            licenseState = LicenseStore.shared.state
            isDeactivating = false
            return
        }
        Task {
            defer { isDeactivating = false }
            try? await LemonSqueezyClient.shared.deactivate(licenseKey: key, instanceID: id)
            LicenseStore.shared.deactivateLicense()
            licenseState = LicenseStore.shared.state
        }
    }

    // MARK: - Display helpers

    private var statusIcon: String {
        switch licenseState {
        case .trial: return "clock.fill"
        case .licensed: return "checkmark.seal.fill"
        case .expired: return "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch licenseState {
        case .trial(let d): return d <= 3 ? .orange : .blue
        case .licensed: return .green
        case .expired: return .red
        }
    }

    private var statusTitle: String {
        switch licenseState {
        case .trial(let d): return "Trial — \(d) day\(d == 1 ? "" : "s") remaining"
        case .licensed(let email): return "Licensed"
        case .expired: return "Trial expired"
        }
    }

    private var statusSubtitle: String {
        switch licenseState {
        case .trial: return "Full access during trial."
        case .licensed(let email): return "Licensed to \(email)"
        case .expired: return "Purchase a license to continue."
        }
    }
}
