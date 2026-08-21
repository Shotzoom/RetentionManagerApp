//
//  RetentionMessagingAPIService.swift
//  RetentionManager
//
//  Created by John Hawley on 3/11/26.
//

import Foundation

/// API Environment
enum APIEnvironment: String, CaseIterable, Identifiable {
    case sandbox = "Sandbox"
    case production = "Production"
    
    var id: String { rawValue }

    /// The currently selected environment (persisted in UserDefaults)
    static var current: APIEnvironment {
        let stored = UserDefaults.standard.string(forKey: "apiEnvironment") ?? APIEnvironment.sandbox.rawValue
        return APIEnvironment(rawValue: stored) ?? .sandbox
    }

    var baseURL: String {
        switch self {
        case .sandbox:
            return "https://api.storekit-sandbox.apple.com/inApps/v1/messaging"
        case .production:
            return "https://api.storekit.apple.com/inApps/v1/messaging"
        }
    }
}

/// Service for interacting with Apple's Retention Messaging API
class RetentionMessagingAPIService {
    static let shared = RetentionMessagingAPIService()
    
    // API Configuration
    private var jwtGenerator: JWTGenerator?
    
    /// Current API environment (sandbox or production)
    var environment: APIEnvironment {
        get { APIEnvironment.current }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "apiEnvironment") }
    }
    
    private var baseURL: String {
        environment.baseURL
    }
    
    private init() {
        // Configure from stored app configuration, if present
        reconfigure()
    }

    // MARK: - Configuration

    /// (Re)configure the JWT generator from the stored app configuration.
    /// Call after the configuration is created or edited.
    func reconfigure() {
        guard AppConfiguration.isConfigured else {
            print("ℹ️ API service not configured — awaiting app configuration")
            jwtGenerator = nil
            return
        }

        guard AppConfiguration.validate(), let p8Content = AppConfiguration.loadPrivateKey() else {
            print("❌ Failed to configure API service due to invalid configuration")
            jwtGenerator = nil
            return
        }

        do {
            jwtGenerator = try JWTGenerator(
                keyID: AppConfiguration.keyID,
                issuerID: AppConfiguration.issuerID,
                bundleID: AppConfiguration.bundleID,
                privateKeyPEM: p8Content
            )
            print("✅ JWT Generator configured successfully")
        } catch {
            print("❌ Error configuring JWT generator: \(error)")
        }
    }
    
    /// Configure with custom credentials
    func configure(keyID: String, issuerID: String, bundleID: String, privateKeyPEM: String) throws {
        jwtGenerator = try JWTGenerator(
            keyID: keyID,
            issuerID: issuerID,
            bundleID: bundleID,
            privateKeyPEM: privateKeyPEM
        )
    }
    
    /// Get the authorization token for API requests
    private func getAuthorizationToken() throws -> String {
        guard let jwtGenerator = jwtGenerator else {
            throw APIError.notConfigured
        }
        return try jwtGenerator.generateToken()
    }
    
    // MARK: - Image Operations
    
    /// Upload an image to the Retention Messaging API
    func uploadImage(imageData: Data, imageIdentifier: String, altText: String) async throws -> String {
        let token = try getAuthorizationToken()
        
        let url = URL(string: "\(baseURL)/image/\(imageIdentifier)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("image/png", forHTTPHeaderField: "Content-Type")
        
        print("📤 Uploading image to: \(url)")
        print("🔑 Authorization: Bearer \(token.prefix(20))...")
        print("📋 Request headers: \(request.allHTTPHeaderFields ?? [:])")
        print("📦 Image data size: \(imageData.count) bytes")
        
        // Upload the image
        let (data, response) = try await URLSession.shared.upload(for: request, from: imageData)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.uploadFailed(statusCode: nil, message: "Invalid response")
        }
        
        print("📥 Image upload response status: \(httpResponse.statusCode)")
        
        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Image upload failed with status \(httpResponse.statusCode): \(responseBody)")
            throw APIError.uploadFailed(statusCode: httpResponse.statusCode, message: responseBody)
        }
        
        print("✅ Image uploaded successfully")
        return imageIdentifier
    }
    
    /// Get list of all uploaded images
    func getImageList() async throws -> [ImageListItem] {
        let token = try getAuthorizationToken()
        
        let url = URL(string: "\(baseURL)/image/list")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("📤 GET \(url) [\(environment.rawValue)]")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed(statusCode: nil, message: "Invalid response")
        }
        
        print("📥 Image list response status: \(httpResponse.statusCode)")
        
        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Image list fetch failed: \(responseBody)")
            throw APIError.requestFailed(statusCode: httpResponse.statusCode, message: responseBody)
        }
        
        let decoder = JSONDecoder()
        let imageListResponse = try decoder.decode(ImageListResponse.self, from: data)
        print("✅ Fetched \(imageListResponse.imageIdentifiers.count) images from Apple")
        return imageListResponse.imageIdentifiers
    }
    
    /// Delete an image
    func deleteImage(imageIdentifier: String) async throws {
        let token = try getAuthorizationToken()
        
        let url = URL(string: "\(baseURL)/image/\(imageIdentifier)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.deleteFailed(statusCode: nil, message: "Invalid response")
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            throw APIError.deleteFailed(statusCode: httpResponse.statusCode, message: responseBody)
        }
    }
    
    // MARK: - Message Operations
    
    /// Upload a message to the Retention Messaging API
    func uploadMessage(
        messageIdentifier: String,
        header: String,
        body: String,
        locale: String,
        imageIdentifier: String? = nil
    ) async throws -> String {
        let token = try getAuthorizationToken()
        
        let url = URL(string: "\(baseURL)/message/\(messageIdentifier)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var messageBody: [String: Any] = [
            "header": header,
            "body": body
        ]
        
        if let imageIdentifier = imageIdentifier {
            messageBody["image"] = [
                "imageIdentifier": imageIdentifier,
                "altText": "Retention message image"
            ]
        }
        
        let jsonData = try JSONSerialization.data(withJSONObject: messageBody)
        request.httpBody = jsonData
        
        print("📤 Uploading message to: \(url)")
        print("🔑 Authorization: Bearer \(token.prefix(20))...")
        print("📝 Message body: \(String(data: jsonData, encoding: .utf8) ?? "Unable to encode")")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.uploadFailed(statusCode: nil, message: "Invalid response")
        }
        
        print("📥 Message upload response status: \(httpResponse.statusCode)")
        
        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Message upload failed with status \(httpResponse.statusCode): \(responseBody)")
            throw APIError.uploadFailed(statusCode: httpResponse.statusCode, message: responseBody)
        }
        
        print("✅ Message uploaded successfully")
        return messageIdentifier
    }
    
    /// Get list of all uploaded messages
    func getMessageList() async throws -> [MessageListItem] {
        let token = try getAuthorizationToken()
        
        let url = URL(string: "\(baseURL)/message/list")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("📤 GET \(url) [\(environment.rawValue)]")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed(statusCode: nil, message: "Invalid response")
        }
        
        print("📥 Message list response status: \(httpResponse.statusCode)")
        
        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Message list fetch failed: \(responseBody)")
            throw APIError.requestFailed(statusCode: httpResponse.statusCode, message: responseBody)
        }
        
        let decoder = JSONDecoder()
        let messageListResponse = try decoder.decode(MessageListResponse.self, from: data)
        print("✅ Fetched \(messageListResponse.messageIdentifiers.count) messages from Apple")
        return messageListResponse.messageIdentifiers
    }
    
    /// Delete a message
    func deleteMessage(messageIdentifier: String) async throws {
        let token = try getAuthorizationToken()
        
        let url = URL(string: "\(baseURL)/message/\(messageIdentifier)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.deleteFailed(statusCode: nil, message: "Invalid response")
        }
        
        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            throw APIError.deleteFailed(statusCode: httpResponse.statusCode, message: responseBody)
        }
    }
    
    // MARK: - Realtime URL Configuration

    /// Configure the realtime URL for the Get Retention Message endpoint
    /// - Parameter realtimeURL: The URL of your Get Retention Message endpoint (max 256 characters)
    func configureRealtimeURL(_ realtimeURL: String) async throws {
        let token = try getAuthorizationToken()

        let url = URL(string: "\(baseURL)/realtime/url")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestBody = RealtimeURLRequest(realtimeURL: realtimeURL)
        request.httpBody = try JSONEncoder().encode(requestBody)

        print("📤 PUT \(url) [\(environment.rawValue)]")
        print("📝 Configuring realtime URL: \(realtimeURL)")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed(statusCode: nil, message: "Invalid response")
        }

        print("📥 Configure realtime URL response status: \(httpResponse.statusCode)")

        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Configure realtime URL failed: \(responseBody)")
            throw APIError.requestFailed(statusCode: httpResponse.statusCode, message: responseBody)
        }

        print("✅ Realtime URL configured successfully")
    }

    /// Get the currently configured realtime URL for the current environment
    /// - Returns: The configured URL, or nil if no URL is configured (HTTP 404)
    func getRealtimeURL() async throws -> String? {
        let token = try getAuthorizationToken()

        let url = URL(string: "\(baseURL)/realtime/url")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        print("📤 GET \(url) [\(environment.rawValue)]")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed(statusCode: nil, message: "Invalid response")
        }

        print("📥 Get realtime URL response status: \(httpResponse.statusCode)")

        // 404 with an error body means no URL is configured yet
        if httpResponse.statusCode == 404, !data.isEmpty {
            print("ℹ️ No realtime URL configured for this environment")
            return nil
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Get realtime URL failed: \(responseBody)")
            throw APIError.requestFailed(statusCode: httpResponse.statusCode, message: responseBody)
        }

        let realtimeResponse = try JSONDecoder().decode(RealtimeURLResponse.self, from: data)
        print("✅ Configured realtime URL: \(realtimeResponse.realtimeURL)")
        return realtimeResponse.realtimeURL
    }

    /// Delete the configured realtime URL for the current environment
    func deleteRealtimeURL() async throws {
        let token = try getAuthorizationToken()

        let url = URL(string: "\(baseURL)/realtime/url")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        print("📤 DELETE \(url) [\(environment.rawValue)]")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.deleteFailed(statusCode: nil, message: "Invalid response")
        }

        print("📥 Delete realtime URL response status: \(httpResponse.statusCode)")

        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Delete realtime URL failed: \(responseBody)")
            throw APIError.deleteFailed(statusCode: httpResponse.statusCode, message: responseBody)
        }

        print("✅ Realtime URL deleted successfully")
    }

    // MARK: - Performance Testing (Sandbox Only)

    /// Initiate a performance test of the configured Get Retention Message endpoint.
    /// Sandbox-only: passing this test is required before configuring the production
    /// realtime URL.
    /// - Parameter originalTransactionId: The original transaction ID of an active
    ///   auto-renewable subscription purchased in the sandbox environment.
    /// - Returns: The requestId used to fetch test results.
    func initiatePerformanceTest(originalTransactionId: String) async throws -> String {
        let token = try getAuthorizationToken()

        // Performance tests exist only in the sandbox environment
        let url = URL(string: "\(APIEnvironment.sandbox.baseURL)/performanceTest")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(
            PerformanceTestRequest(originalTransactionId: originalTransactionId)
        )

        print("📤 POST \(url) [Sandbox]")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed(statusCode: nil, message: "Invalid response")
        }

        print("📥 Initiate performance test response status: \(httpResponse.statusCode)")

        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Initiate performance test failed: \(responseBody)")
            throw APIError.requestFailed(statusCode: httpResponse.statusCode, message: responseBody)
        }

        let decoded = try JSONDecoder().decode(PerformanceTestInitiateResponse.self, from: data)
        print("✅ Performance test initiated, requestId: \(decoded.requestId)")
        return decoded.requestId
    }

    /// Get the results of a previously initiated performance test (sandbox only)
    func getPerformanceTestResult(requestId: String) async throws -> PerformanceTestResultResponse {
        let token = try getAuthorizationToken()

        let url = URL(string: "\(APIEnvironment.sandbox.baseURL)/performanceTest/result/\(requestId)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        print("📤 GET \(url) [Sandbox]")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed(statusCode: nil, message: "Invalid response")
        }

        print("📥 Performance test result response status: \(httpResponse.statusCode)")

        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Get performance test result failed: \(responseBody)")
            throw APIError.requestFailed(statusCode: httpResponse.statusCode, message: responseBody)
        }

        return try JSONDecoder().decode(PerformanceTestResultResponse.self, from: data)
    }

    // MARK: - Default Message Configuration
    
    /// Configure a default message for a product in a locale
    func configureDefaultMessage(
        productID: String,
        locale: String,
        messageIdentifier: String
    ) async throws {
        let token = try getAuthorizationToken()
        
        // Endpoint format: /default/{productId}/{locale}
        let url = URL(string: "\(baseURL)/default/\(productID)/\(locale)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: String] = [
            "messageIdentifier": messageIdentifier
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = jsonData
        
        print("📤 Configuring default message for \(productID)/\(locale)")
        print("📝 Message ID: \(messageIdentifier)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed(statusCode: nil, message: "Invalid response")
        }
        
        print("📥 Configure default response status: \(httpResponse.statusCode)")
        
        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Configure default failed: \(responseBody)")
            throw APIError.requestFailed(statusCode: httpResponse.statusCode, message: responseBody)
        }
        
        print("✅ Default message configured successfully")
    }
    
    /// Get the default message identifier configured for a product in a locale
    /// - Returns: The configured message identifier, or nil if no default is configured (HTTP 404)
    func getDefaultMessage(productID: String, locale: String) async throws -> String? {
        let token = try getAuthorizationToken()

        let url = URL(string: "\(baseURL)/default/\(productID)/\(locale)")!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        print("📤 GET \(url) [\(environment.rawValue)]")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.requestFailed(statusCode: nil, message: "Invalid response")
        }

        // 404 with an error body (DefaultMessageNotFoundError) means no default
        // is configured for this product/locale
        if httpResponse.statusCode == 404, !data.isEmpty {
            return nil
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Get default message failed: \(responseBody)")
            throw APIError.requestFailed(statusCode: httpResponse.statusCode, message: responseBody)
        }

        let decoded = try JSONDecoder().decode(DefaultConfigurationResponse.self, from: data)
        return decoded.messageIdentifier
    }

    /// Delete a default message for a product in a locale
    func deleteDefaultMessage(
        productID: String,
        locale: String
    ) async throws {
        let token = try getAuthorizationToken()
        
        // Endpoint format: /default/{productId}/{locale}
        let url = URL(string: "\(baseURL)/default/\(productID)/\(locale)")!
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("📤 Deleting default message for \(productID)/\(locale)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.deleteFailed(statusCode: nil, message: "Invalid response")
        }
        
        print("📥 Delete default response status: \(httpResponse.statusCode)")
        
        if !(200...299).contains(httpResponse.statusCode) {
            let responseBody = String(data: data, encoding: .utf8) ?? "No response body"
            print("❌ Delete default failed: \(responseBody)")
            throw APIError.deleteFailed(statusCode: httpResponse.statusCode, message: responseBody)
        }
        
        print("✅ Default message deleted successfully")
    }
}

// MARK: - API Limits

/// Character limits enforced by Apple's Retention Messaging API.
/// Exceeding these returns a 400 (HeaderTooLongError, BodyTooLongError, AltTextTooLongError).
enum RetentionMessageLimits {
    /// Maximum length of the message header
    static let maxHeaderLength = 66
    /// Maximum length of the message body
    static let maxBodyLength = 144
    /// Maximum length of an image's alt text
    static let maxAltTextLength = 150
    /// Maximum length of a single bullet point's text
    static let maxBulletPointLength = 66
}

// MARK: - API Models

struct ImageListResponse: Codable {
    let imageIdentifiers: [ImageListItem]
}

struct ImageListItem: Codable, Identifiable {
    let imageIdentifier: String
    let imageState: String
    
    var id: String { imageIdentifier }
}

/// Request body for Configure Realtime URL (PUT /realtime/url)
struct RealtimeURLRequest: Codable {
    let realtimeURL: String
}

/// Response body for Get Realtime URL (GET /realtime/url)
struct RealtimeURLResponse: Codable {
    let realtimeURL: String
}

/// Response body for Get Default Message (GET /default/{productId}/{locale})
struct DefaultConfigurationResponse: Codable {
    let messageIdentifier: String
}

/// Request body for Initiate Performance Test (POST /performanceTest, sandbox only)
struct PerformanceTestRequest: Codable {
    let originalTransactionId: String
}

/// Response body for Initiate Performance Test
struct PerformanceTestInitiateResponse: Codable {
    let requestId: String
}

/// Response body for Get Performance Test Result
/// (GET /performanceTest/result/{requestId}, sandbox only)
struct PerformanceTestResultResponse: Codable {
    /// Overall test status: PENDING, PASS, or FAIL
    let result: String
    /// Success rate percentage
    let successRate: Int?
    /// Number of requests still pending in the test
    let numPending: Int?
    /// The endpoint URL that was tested
    let target: String?
    /// Map of failure reasons to occurrence counts
    let failures: [String: Int]?
    /// The parameters the test runs with
    let config: PerformanceTestConfig?
    /// Response times measured during the test
    let responseTimes: PerformanceTestResponseTimes?
}

/// Test parameters for a performance test
struct PerformanceTestConfig: Codable {
    /// Maximum number of concurrent requests the test sends
    let maxConcurrentRequests: Int?
    /// Maximum time (ms) the server has to respond to each request
    let responseTimeThreshold: Int?
    /// Success rate percentage required to pass
    let successRateThreshold: Int?
    /// Total duration of the test in milliseconds
    let totalDuration: Int?
    /// Total number of requests the test makes
    let totalRequests: Int?
}

/// Response time percentiles measured during a performance test (milliseconds)
struct PerformanceTestResponseTimes: Codable {
    let average: Int?
    let p50: Int?
    let p90: Int?
    let p95: Int?
    let p99: Int?
}

struct MessageListResponse: Codable {
    let messageIdentifiers: [MessageListItem]
}

struct MessageListItem: Codable, Identifiable {
    let messageIdentifier: String
    let messageState: String
    
    var id: String { messageIdentifier }
}

// MARK: - Error Types

enum APIError: LocalizedError {
    case notConfigured
    case uploadFailed(statusCode: Int?, message: String)
    case requestFailed(statusCode: Int?, message: String)
    case deleteFailed(statusCode: Int?, message: String)
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "API service is not configured. Please set API key and team ID."
        case .uploadFailed(let statusCode, let message):
            if let code = statusCode {
                return "Upload failed (HTTP \(code)): \(message)"
            }
            return "Upload failed: \(message)"
        case .requestFailed(let statusCode, let message):
            if let code = statusCode {
                return "Request failed (HTTP \(code)): \(message)"
            }
            return "Request failed: \(message)"
        case .deleteFailed(let statusCode, let message):
            if let code = statusCode {
                return "Delete failed (HTTP \(code)): \(message)"
            }
            return "Delete failed: \(message)"
        }
    }
}
