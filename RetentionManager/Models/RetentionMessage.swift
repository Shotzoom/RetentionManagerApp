//
//  RetentionMessage.swift
//  RetentionManager
//
//  Created by John Hawley on 3/11/26.
//

import Foundation
import SwiftData

/// Upload status for tracking API sync
enum UploadStatus: String, Codable {
    case localOnly = "Local Only"      // Not yet uploaded to API
    case uploading = "Uploading"       // Currently uploading
    case uploaded = "Uploaded"         // Successfully uploaded to API
    case failed = "Failed"             // Upload failed
}

/// Message type for retention messaging
enum MessageType: String, Codable, CaseIterable, Identifiable {
    case message = "message"                        // Standard text-based message
    case alternateProduct = "alternateProduct"      // Offer to switch to different product
    case promotionalOffer = "promotionalOffer"      // Promotional offer with promo code
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .message:
            return "Text Message"
        case .alternateProduct:
            return "Alternate Product Offer"
        case .promotionalOffer:
            return "Promotional Offer"
        }
    }
}

/// Cancellation scenario for retention messaging
enum CancellationScenario: String, Codable, CaseIterable, Identifiable {
    case defaultScenario = "Default"           // Default message (fallback for all scenarios)
    case trialCancel = "TrialCancel"           // User cancelling during trial
    case moreThan30 = "MoreThan30"             // Cancelling with more than 30 days remaining
    case lessThan30 = "LessThan30"             // Cancelling with less than 30 days remaining
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .defaultScenario:
            return "Default (Fallback)"
        case .trialCancel:
            return "Trial Cancellation"
        case .moreThan30:
            return "More Than 30 Days Remaining"
        case .lessThan30:
            return "Less Than 30 Days Remaining"
        }
    }
    
    var description: String {
        switch self {
        case .defaultScenario:
            return "Default message used when server doesn't respond or for all scenarios"
        case .trialCancel:
            return "User is cancelling during their trial period"
        case .moreThan30:
            return "User is cancelling with more than 30 days left"
        case .lessThan30:
            return "User is cancelling with less than 30 days left"
        }
    }
}

/// Represents a retention message for a subscription product
@Model
class RetentionMessage {
    @Attribute(.unique) var messageIdentifier: String
    var productID: String
    var headerText: String
    var bodyText: String
    var imageIdentifier: String?
    var messageState: String = "PENDING" // Sandbox: PENDING, APPROVED, REJECTED (from Apple)
    var uploadStatus: String = "Local Only" // Sandbox: localOnly, uploading, uploaded, failed
    var uploadError: String? = nil // Error message if upload failed
    var locale: String = "en-US" // App Store locale code (en-US, es-ES, fr-FR, de-DE)

    // Production tracking. Apple's sandbox and production are independent stores,
    // so upload status, review state, and default configuration are tracked per
    // environment. The original properties above carry the sandbox values.
    var productionUploadStatus: String = UploadStatus.localOnly.rawValue
    var productionMessageState: String = "PENDING"
    var productionIsDefault: Bool = false
    
    // Message type and related fields for server response logic
    var messageType: String = MessageType.message.rawValue // message, alternateProduct, promotionalOffer
    var alternateProductID: String? = nil // For alternateProduct type
    var promoCode: String? = nil // For promotionalOffer type
    var scenario: String = CancellationScenario.trialCancel.rawValue // TrialCancel, MoreThan30, LessThan30
    var isDefaultMessage: Bool = false // Whether this is the default message for its product/locale combo
    var isExternal: Bool = false // Created from sync as a placeholder; content unknown (Apple's API doesn't return message text)

    var createdAt: Date
    var updatedAt: Date

    init(
        messageIdentifier: String,
        productID: String,
        headerText: String,
        bodyText: String,
        imageIdentifier: String? = nil,
        messageState: String = "PENDING",
        uploadStatus: String = UploadStatus.localOnly.rawValue,
        locale: String = "en-US",
        messageType: String = MessageType.message.rawValue,
        alternateProductID: String? = nil,
        promoCode: String? = nil,
        scenario: String = CancellationScenario.trialCancel.rawValue,
        isExternal: Bool = false
    ) {
        self.messageIdentifier = messageIdentifier
        self.productID = productID
        self.headerText = headerText
        self.bodyText = bodyText
        self.imageIdentifier = imageIdentifier
        self.messageState = messageState
        self.uploadStatus = uploadStatus
        self.uploadError = nil
        self.locale = locale
        self.messageType = messageType
        self.alternateProductID = alternateProductID
        self.promoCode = promoCode
        self.scenario = scenario
        self.isExternal = isExternal
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

// MARK: - Environment-Aware Accessors

extension RetentionMessage {
    func uploadStatus(in environment: APIEnvironment) -> String {
        environment == .production ? productionUploadStatus : uploadStatus
    }

    func setUploadStatus(_ status: String, in environment: APIEnvironment) {
        if environment == .production {
            productionUploadStatus = status
        } else {
            uploadStatus = status
        }
    }

    func messageState(in environment: APIEnvironment) -> String {
        environment == .production ? productionMessageState : messageState
    }

    func setMessageState(_ state: String, in environment: APIEnvironment) {
        if environment == .production {
            productionMessageState = state
        } else {
            messageState = state
        }
    }

    func isDefault(in environment: APIEnvironment) -> Bool {
        environment == .production ? productionIsDefault : isDefaultMessage
    }

    func setIsDefault(_ isDefault: Bool, in environment: APIEnvironment) {
        if environment == .production {
            productionIsDefault = isDefault
        } else {
            isDefaultMessage = isDefault
        }
    }

    /// Whether the message exists on Apple in any environment — content is
    /// immutable once uploaded anywhere (Apple has no update API)
    var isUploadedAnywhere: Bool {
        uploadStatus == UploadStatus.uploaded.rawValue ||
        productionUploadStatus == UploadStatus.uploaded.rawValue
    }
}

/// Represents an uploaded image for retention messaging
@Model
class RetentionImage {
    @Attribute(.unique) var imageIdentifier: String
    var imageData: Data
    var altText: String
    var imageState: String // PENDING, APPROVED, REJECTED
    var createdAt: Date
    var updatedAt: Date
    
    init(
        imageIdentifier: String,
        imageData: Data,
        altText: String,
        imageState: String = "PENDING"
    ) {
        self.imageIdentifier = imageIdentifier
        self.imageData = imageData
        self.altText = altText
        self.imageState = imageState
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}

/// Supported locales for retention messages.
/// Raw values are App Store locale codes — the same format Apple uses in the
/// realtime Get Retention Message request (userLocale) and requires for the
/// /default/{productId}/{locale} endpoint. Bare language codes like "en" are
/// rejected by Apple with InvalidLocaleError (4000164), so the full code is
/// the canonical format for storage and exports.
enum SupportedLocale: String, CaseIterable, Identifiable {
    case english = "en-US"
    case spanish = "es-ES"
    case french = "fr-FR"
    case german = "de-DE"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        }
    }

    /// Language-only prefix ("en"), used for translation mapping and
    /// normalizing legacy short codes
    var shortCode: String {
        String(rawValue.prefix(2))
    }

    /// Normalize a stored or imported locale to the App Store locale code
    /// Apple uses (e.g. legacy "en" → "en-US"). Full codes pass through
    /// unchanged; unknown values are returned as-is.
    static func normalize(_ code: String) -> String {
        let trimmed = code.trimmingCharacters(in: .whitespaces)
        if let exact = SupportedLocale(rawValue: trimmed) {
            return exact.rawValue
        }
        if let match = SupportedLocale.allCases.first(where: { $0.shortCode == trimmed.lowercased() }) {
            return match.rawValue
        }
        return trimmed
    }
}
