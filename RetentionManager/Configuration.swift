//
//  Configuration.swift
//  RetentionManager
//
//  Created by John Hawley on 3/11/26.
//

import Foundation

/// Runtime application configuration, stored in UserDefaults.
/// Values are entered through the configuration setup screen on first launch
/// and can be edited at any time from Settings → Edit Configuration.
struct AppConfiguration {

    private enum Keys {
        static let teamID = "config.teamID"
        static let issuerID = "config.issuerID"
        static let keyID = "config.keyID"
        static let bundleID = "config.bundleID"
        static let privateKeyPEM = "config.privateKeyPEM"
        static let productIDs = "config.productIDs"
        static let sandboxRealtimeEndpointURL = "config.sandboxRealtimeEndpointURL"
    }

    // MARK: - Stored Configuration

    /// Apple Developer Team ID (10 characters)
    /// Found at https://developer.apple.com/account -> Membership
    static var teamID: String {
        get { UserDefaults.standard.string(forKey: Keys.teamID) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.teamID) }
    }

    /// Issuer ID from the App Store Connect In-App Purchase keys page
    /// Found at https://appstoreconnect.apple.com/access/integrations/api
    static var issuerID: String {
        get { UserDefaults.standard.string(forKey: Keys.issuerID) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.issuerID) }
    }

    /// The Key ID of the In-App Purchase key used to sign API requests
    static var keyID: String {
        get { UserDefaults.standard.string(forKey: Keys.keyID) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.keyID) }
    }

    /// The app's bundle identifier
    static var bundleID: String {
        get { UserDefaults.standard.string(forKey: Keys.bundleID) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.bundleID) }
    }

    /// Contents of the .p8 private key file (PEM), imported during setup
    static var privateKeyPEM: String {
        get { UserDefaults.standard.string(forKey: Keys.privateKeyPEM) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.privateKeyPEM) }
    }

    /// The auto-renewable subscription product IDs this tool manages
    static var productIDs: [String] {
        get {
            (UserDefaults.standard.string(forKey: Keys.productIDs) ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set { UserDefaults.standard.set(newValue.joined(separator: ","), forKey: Keys.productIDs) }
    }

    /// The Get Retention Message endpoint URL for the sandbox environment.
    /// This is the URL Apple's App Store server calls to get real-time message selections.
    static var sandboxRealtimeEndpointURL: String {
        get { UserDefaults.standard.string(forKey: Keys.sandboxRealtimeEndpointURL) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.sandboxRealtimeEndpointURL) }
    }

    // MARK: - Default Settings

    /// Default API environment (sandbox or production)
    static let defaultEnvironment: APIEnvironment = .sandbox

    // MARK: - Status

    /// Whether all required configuration values are present
    static var isConfigured: Bool {
        !teamID.isEmpty &&
        !issuerID.isEmpty &&
        !keyID.isEmpty &&
        !bundleID.isEmpty &&
        !privateKeyPEM.isEmpty &&
        !productIDs.isEmpty
    }

    /// Load the P8 private key from configuration
    static func loadPrivateKey() -> String? {
        privateKeyPEM.isEmpty ? nil : privateKeyPEM
    }

    /// Validate the configuration
    static func validate() -> Bool {
        guard !teamID.isEmpty else {
            print("❌ Error: Team ID is not configured")
            return false
        }

        guard teamID.count == 10 else {
            print("❌ Error: Team ID must be exactly 10 characters")
            return false
        }

        guard !keyID.isEmpty else {
            print("❌ Error: Key ID is not configured")
            return false
        }

        guard loadPrivateKey() != nil else {
            print("❌ Error: No P8 private key is configured")
            return false
        }

        print("✅ Configuration validated successfully")
        print("   Team ID: \(teamID)")
        print("   Key ID: \(keyID)")
        print("   Bundle ID: \(bundleID)")
        print("   Products: \(productIDs.count)")
        print("   Default Environment: \(defaultEnvironment.rawValue)")

        return true
    }

    // MARK: - Bundled Defaults

    /// Shape of the gitignored DefaultConfig.json file. Place it at
    /// RetentionManager/DefaultConfig.json (next to the app sources) along with
    /// the .p8 file it names; both are bundled automatically when present and
    /// neither is committed to the repository.
    private struct BundledDefaults: Codable {
        let teamID: String
        let issuerID: String
        let keyID: String
        let p8FileName: String
        let bundleID: String
        let sandboxRealtimeEndpointURL: String?
        let productIDs: [String]
    }

    /// Apply the internal default configuration from the bundled DefaultConfig.json.
    /// Triggered by typing the defaults keyword into the Team ID field of the
    /// configuration setup screen and saving.
    /// Returns false if the config file or the .p8 key it names isn't in the bundle.
    @discardableResult
    static func applyBundledDefaults() -> Bool {
        guard let configURL = Bundle.main.url(forResource: "DefaultConfig", withExtension: "json"),
              let data = try? Data(contentsOf: configURL),
              let defaults = try? JSONDecoder().decode(BundledDefaults.self, from: data) else {
            print("❌ Error: DefaultConfig.json not found in bundle or invalid")
            return false
        }

        guard let p8URL = Bundle.main.url(forResource: defaults.p8FileName, withExtension: "p8"),
              let p8Content = try? String(contentsOf: p8URL, encoding: .utf8) else {
            print("❌ Error: Could not load bundled \(defaults.p8FileName).p8")
            return false
        }

        teamID = defaults.teamID
        issuerID = defaults.issuerID
        keyID = defaults.keyID
        bundleID = defaults.bundleID
        privateKeyPEM = p8Content
        productIDs = defaults.productIDs
        sandboxRealtimeEndpointURL = defaults.sandboxRealtimeEndpointURL ?? ""

        print("✅ Applied bundled default configuration")
        return true
    }
}
