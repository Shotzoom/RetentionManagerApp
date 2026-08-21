//
//  RetentionManagerApp.swift
//  RetentionManager
//
//  Created by John Hawley on 3/11/26.
//

import SwiftUI
import SwiftData

@main
struct RetentionManagerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            RetentionMessage.self,
            RetentionImage.self
        ])
        
        // Enable automatic migration for schema changes
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // Migrate existing messages to add upload status
            let context = container.mainContext
            let descriptor = FetchDescriptor<RetentionMessage>()
            if let messages = try? context.fetch(descriptor) {
                for message in messages {
                    // Set default values for new properties if they're not set
                    if message.uploadStatus.isEmpty {
                        message.uploadStatus = UploadStatus.localOnly.rawValue
                    }

                    // Migrate legacy short locale codes ("en") to the App Store
                    // locale codes Apple uses ("en-US"), which are the canonical
                    // format for storage, exports, and the realtime endpoint
                    let normalizedLocale = SupportedLocale.normalize(message.locale)
                    if normalizedLocale != message.locale {
                        print("🔤 Migrating locale for \(message.messageIdentifier): \(message.locale) → \(normalizedLocale)")
                        message.locale = normalizedLocale
                    }
                }
                try? context.save()
            }
            
            return container
        } catch {
            // If migration fails, we need to reset the database
            print("⚠️ ModelContainer error: \(error)")
            print("📝 Attempting to reset database...")
            
            // Delete the existing database file
            let url = URL.documentsDirectory.appending(path: "default.store")
            try? FileManager.default.removeItem(at: url)
            
            // Try creating container again with fresh database
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even after reset: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1200, height: 800)
        
        Settings {
            SettingsView()
        }
    }
}
