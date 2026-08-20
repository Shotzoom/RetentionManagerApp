//
//  SyncService.swift
//  RetentionManager
//
//  Service for syncing messages and images from Apple's API
//

import Foundation
import SwiftData

@MainActor
class SyncService {
    static let shared = SyncService()
    
    private init() {}
    
    /// Syncs messages and images from Apple's API with the local database
    func syncFromApple(modelContext: ModelContext) async throws -> SyncResult {
        print("🔄 Starting sync from Apple...")
        
        var result = SyncResult()
        
        // Fetch message list from Apple
        let messageItems = try await RetentionMessagingAPIService.shared.getMessageList()
        print("📦 Fetched \(messageItems.count) messages from Apple")
        
        // Fetch image list from Apple
        let imageItems = try await RetentionMessagingAPIService.shared.getImageList()
        print("📦 Fetched \(imageItems.count) images from Apple")
        
        // Fetch all local messages
        // Note: Apple normalizes identifiers to lowercase, while UUID().uuidString is
        // uppercase — so all identifier matching must be case-insensitive.
        let messageDescriptor = FetchDescriptor<RetentionMessage>()
        let localMessages = try modelContext.fetch(messageDescriptor)
        let localMessageDict = Dictionary(uniqueKeysWithValues: localMessages.map { ($0.messageIdentifier.lowercased(), $0) })

        // Fetch all local images
        let imageDescriptor = FetchDescriptor<RetentionImage>()
        let localImages = try modelContext.fetch(imageDescriptor)
        let localImageDict = Dictionary(uniqueKeysWithValues: localImages.map { ($0.imageIdentifier.lowercased(), $0) })

        // Process each message from Apple
        for messageItem in messageItems {
            if let existingMessage = localMessageDict[messageItem.messageIdentifier.lowercased()] {
                // Update Apple's review state (PENDING/APPROVED/REJECTED) and mark as uploaded
                let oldState = existingMessage.messageState
                existingMessage.messageState = messageItem.messageState
                existingMessage.uploadStatus = UploadStatus.uploaded.rawValue
                existingMessage.uploadError = nil

                if oldState != messageItem.messageState {
                    result.updatedCount += 1
                    print("✏️ Updated message \(messageItem.messageIdentifier): \(oldState) → \(messageItem.messageState)")
                }
            } else {
                // Message exists in Apple but not locally - create a placeholder so it's
                // visible in the UI. Apple's API doesn't return message content (header/body),
                // so the placeholder only carries the identifier and state.
                let placeholder = RetentionMessage(
                    messageIdentifier: messageItem.messageIdentifier.lowercased(),
                    productID: "",
                    headerText: "External message",
                    bodyText: "This message exists on Apple but was created outside this app (or on another machine). Apple's API doesn't return message content, so the text can't be displayed. Use Export/Import to transfer full message content between machines.",
                    messageState: messageItem.messageState,
                    uploadStatus: UploadStatus.uploaded.rawValue,
                    locale: "",
                    isExternal: true
                )
                modelContext.insert(placeholder)
                result.externalCount += 1
                print("📌 Imported external message from Apple: \(messageItem.messageIdentifier) (state: \(messageItem.messageState))")
            }
        }
        
        // Process each image from Apple
        for imageItem in imageItems {
            if let existingImage = localImageDict[imageItem.imageIdentifier.lowercased()] {
                // Update existing image state
                let oldState = existingImage.imageState
                existingImage.imageState = imageItem.imageState
                
                if oldState != imageItem.imageState {
                    result.imagesUpdatedCount += 1
                    print("✏️ Updated image \(imageItem.imageIdentifier): \(oldState) → \(imageItem.imageState)")
                }
            }
        }
        
        // Check for local messages not found in Apple (possibly deleted on Apple's side)
        let appleMessageIDs = Set(messageItems.map { $0.messageIdentifier.lowercased() })
        for localMessage in localMessages {
            if !appleMessageIDs.contains(localMessage.messageIdentifier.lowercased()) {
                // Message exists locally but not in Apple
                // Update status to indicate it's not on Apple
                if localMessage.uploadStatus == UploadStatus.uploaded.rawValue {
                    localMessage.uploadStatus = UploadStatus.localOnly.rawValue
                    result.removedCount += 1
                    print("⚠️ Message \(localMessage.messageIdentifier) no longer exists on Apple")
                }
            }
        }
        
        // Reconcile Apple's default-message configuration with local flags.
        // The message list doesn't indicate defaults, so query the default
        // endpoint once per unique product/locale pair among local messages.
        var seenPairs = Set<String>()
        var pairs: [(productID: String, locale: String)] = []
        for message in localMessages where !message.isExternal && !message.productID.isEmpty && !message.locale.isEmpty {
            if seenPairs.insert("\(message.productID)|\(message.locale)").inserted {
                pairs.append((message.productID, message.locale))
            }
        }

        for pair in pairs {
            do {
                let appleLocale = SupportedLocale.appStoreLocaleCode(for: pair.locale)
                let defaultID = try await RetentionMessagingAPIService.shared.getDefaultMessage(
                    productID: pair.productID,
                    locale: appleLocale
                )?.lowercased()

                for message in localMessages where message.productID == pair.productID && message.locale == pair.locale {
                    let isDefault = defaultID != nil && message.messageIdentifier.lowercased() == defaultID
                    if message.isDefaultMessage != isDefault {
                        message.isDefaultMessage = isDefault
                        result.defaultsUpdatedCount += 1
                        print("⭐️ Default flag for \(message.messageIdentifier) (\(pair.productID)/\(pair.locale)): \(isDefault)")
                    }
                }
            } catch {
                // Non-fatal: keep existing local flags if the lookup fails
                print("⚠️ Failed to fetch default for \(pair.productID)/\(pair.locale): \(error.localizedDescription)")
            }
        }

        // Save changes
        try modelContext.save()
        
        result.totalMessages = messageItems.count
        result.totalImages = imageItems.count
        
        print("✅ Sync completed: \(result.updatedCount) updated, \(result.externalCount) external, \(result.removedCount) removed")
        
        return result
    }
}

/// Result of a sync operation
struct SyncResult {
    var totalMessages: Int = 0
    var totalImages: Int = 0
    var updatedCount: Int = 0
    var imagesUpdatedCount: Int = 0
    var externalCount: Int = 0
    var removedCount: Int = 0
    var defaultsUpdatedCount: Int = 0

    var summary: String {
        """
        Sync completed successfully:
        • \(totalMessages) messages on Apple
        • \(totalImages) images on Apple
        • \(updatedCount) local messages updated
        • \(imagesUpdatedCount) local images updated
        • \(externalCount) external messages imported as placeholders
        • \(removedCount) messages no longer on Apple
        • \(defaultsUpdatedCount) default-message flags updated
        """
    }
}
