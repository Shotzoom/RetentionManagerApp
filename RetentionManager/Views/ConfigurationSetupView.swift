//
//  ConfigurationSetupView.swift
//  RetentionManager
//
//  First-launch configuration wizard, also reachable from Settings to edit
//  the configuration at any time.
//

import SwiftUI
import UniformTypeIdentifiers

struct ConfigurationSetupView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var teamID = AppConfiguration.teamID
    @State private var issuerID = AppConfiguration.issuerID
    @State private var keyID = AppConfiguration.keyID
    @State private var bundleID = AppConfiguration.bundleID
    @State private var privateKeyPEM = AppConfiguration.privateKeyPEM
    @State private var importedKeyFileName: String?
    @State private var productIDsText = AppConfiguration.productIDs.joined(separator: ", ")
    @State private var sandboxEndpointURL = AppConfiguration.sandboxRealtimeEndpointURL

    @State private var showingKeyImporter = false
    @State private var validationError: String?
    @State private var showingNextSteps = false

    /// Typing this into the Team ID field and saving loads the internal defaults
    private static let defaultsKeyword = "golfshot"

    var body: some View {
        NavigationStack {
            if showingNextSteps {
                nextStepsView
            } else {
                configurationForm
            }
        }
        .frame(minWidth: 560, minHeight: 620)
    }

    // MARK: - Configuration Form

    private var configurationForm: some View {
        Form {
            Section {
                Text("This tool needs your Apple Developer credentials to call the Retention Messaging API. All values are stored locally on this Mac — nothing is committed with the project.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apple Developer Account") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Team ID", text: $teamID, prompt: Text("10-character Team ID"))
                    Text("developer.apple.com/account → Membership")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Issuer ID", text: $issuerID, prompt: Text("UUID from the In-App Purchase keys page"))
                    Text("appstoreconnect.apple.com → Users and Access → Integrations → In-App Purchase")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Key ID", text: $keyID, prompt: Text("Key ID of the In-App Purchase key"))
                    Text("The ID of the key whose .p8 file you import below")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Button(privateKeyPEM.isEmpty ? "Import .p8 Private Key…" : "Replace .p8 Private Key…") {
                            showingKeyImporter = true
                        }
                        if !privateKeyPEM.isEmpty {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text(importedKeyFileName ?? "Private key configured")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("Import an In-App Purchase key (.p8). The key contents are stored locally and never committed to the repository.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("""
                            1. Sign in to App Store Connect (requires the Account Holder or Admin role)
                            2. Go to Users and Access → Integrations tab
                            3. In the sidebar under Keys, select In-App Purchase
                            4. Click Generate In-App Purchase Key (or +), name it, and click Generate
                            5. Click Download Key next to the new key
                            """)
                            .font(.caption)

                            Text("⚠️ The .p8 file can be downloaded only once — Apple keeps no copy. Store it securely (password manager or secure vault); if it's lost or compromised, revoke it and generate a new key.")
                                .font(.caption)
                                .foregroundStyle(.orange)

                            Text("This is a key type dedicated to in-app purchase APIs (App Store Server API and Retention Messaging) — an App Store Connect API key won't work. No additional permissions are needed on the key itself. The Issuer ID and Key ID fields above come from this same page.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.top, 4)
                    } label: {
                        Text("How do I create a .p8 key?")
                            .font(.caption)
                    }
                }
            }

            Section("App") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Bundle ID", text: $bundleID, prompt: Text("com.company.AppName"))
                    Text("The bundle identifier of the app whose subscriptions get retention messages")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("Product IDs", text: $productIDsText, prompt: Text("com.company.App.Sub1, com.company.App.Sub2"), axis: .vertical)
                        .lineLimit(3...6)
                    Text("Comma-separated list of the auto-renewable subscription product IDs to manage")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Server (Optional)") {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Sandbox Realtime Endpoint URL", text: $sandboxEndpointURL, prompt: Text("https://…"))
                    Text("Your Get Retention Message endpoint for sandbox. You can also set this later in Settings.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let validationError {
                Section {
                    Text(validationError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(AppConfiguration.isConfigured ? "Edit Configuration" : "Welcome — Configuration Required")
        .toolbar {
            if AppConfiguration.isConfigured {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                }
            }
        }
        .fileImporter(
            isPresented: $showingKeyImporter,
            allowedContentTypes: [UTType(filenameExtension: "p8") ?? .data, .text],
            allowsMultipleSelection: false
        ) { result in
            importPrivateKey(result)
        }
    }

    // MARK: - Next Steps

    private var nextStepsView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.title)
                    Text("Configuration Saved")
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                Text("Here's how to get retention messaging fully running:")
                    .font(.headline)

                NextStep(number: 1, title: "Register your sandbox endpoint", detail: "Open Settings (⌘,) → Realtime Endpoint. Configure your sandbox Get Retention Message URL — or use Fetch Current if it was configured previously.")
                NextStep(number: 2, title: "Create your messages", detail: "Create at least one message for your server's database (e.g. a promotional offer), and one text-only message to serve as Apple's default fallback.")
                NextStep(number: 3, title: "Upload and wait for approval", detail: "Upload the messages to Apple, then use Sync from Apple until they show as APPROVED. (Sandbox approves automatically.)")
                NextStep(number: 4, title: "Set the Apple default", detail: "Open the approved text-only message and click Set as Default. Apple shows this message if your endpoint doesn't respond in time.")
                NextStep(number: 5, title: "Export to your database", detail: "Use Export → SQL to generate insert statements for your server's database, so your endpoint can return the messages in real time.")
                NextStep(number: 6, title: "Run the performance test", detail: "In Settings → Performance Test, initiate a test with a sandbox transaction ID. A PASS is required before you can configure the production endpoint URL.")

                Spacer(minLength: 8)

                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(24)
        }
        .navigationTitle("Next Steps")
    }

    // MARK: - Actions

    private func importPrivateKey(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }

            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            let content = try String(contentsOf: url, encoding: .utf8)
            guard content.contains("PRIVATE KEY") else {
                validationError = "The selected file doesn't look like a .p8 private key (missing PRIVATE KEY header)."
                return
            }

            privateKeyPEM = content
            importedKeyFileName = url.lastPathComponent
            validationError = nil
        } catch {
            validationError = "Failed to read key file: \(error.localizedDescription)"
        }
    }

    private func save() {
        // Typing the defaults keyword into the Team ID field loads the internal
        // default configuration from the bundled (gitignored) DefaultConfig.json
        if teamID.trimmingCharacters(in: .whitespaces).lowercased() == Self.defaultsKeyword {
            guard AppConfiguration.applyBundledDefaults() else {
                validationError = "Could not load the internal default configuration. Ensure DefaultConfig.json and the .p8 key it names are present in the project (both are gitignored — obtain them via a secure channel; see README)."
                return
            }
            finishSave()
            return
        }

        // Otherwise all fields are required
        let trimmedTeamID = teamID.trimmingCharacters(in: .whitespaces)
        let products = productIDsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard trimmedTeamID.count == 10 else {
            validationError = "Team ID must be exactly 10 characters."
            return
        }
        guard !issuerID.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationError = "Issuer ID is required."
            return
        }
        guard !keyID.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationError = "Key ID is required."
            return
        }
        guard !bundleID.trimmingCharacters(in: .whitespaces).isEmpty else {
            validationError = "Bundle ID is required."
            return
        }
        guard !privateKeyPEM.isEmpty else {
            validationError = "A .p8 private key is required."
            return
        }
        guard !products.isEmpty else {
            validationError = "At least one product ID is required."
            return
        }

        AppConfiguration.teamID = trimmedTeamID
        AppConfiguration.issuerID = issuerID.trimmingCharacters(in: .whitespaces)
        AppConfiguration.keyID = keyID.trimmingCharacters(in: .whitespaces)
        AppConfiguration.bundleID = bundleID.trimmingCharacters(in: .whitespaces)
        AppConfiguration.privateKeyPEM = privateKeyPEM
        AppConfiguration.productIDs = products
        AppConfiguration.sandboxRealtimeEndpointURL = sandboxEndpointURL.trimmingCharacters(in: .whitespaces)

        finishSave()
    }

    private func finishSave() {
        validationError = nil
        RetentionMessagingAPIService.shared.reconfigure()
        showingNextSteps = true
    }
}

/// A numbered step in the post-configuration guidance
private struct NextStep: View {
    let number: Int
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.headline)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.15))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    ConfigurationSetupView()
}
