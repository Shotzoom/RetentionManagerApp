//
//  ContentView.swift
//  RetentionManager
//
//  Created by John Hawley on 3/11/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RetentionMessage.updatedAt, order: .reverse) private var allMessages: [RetentionMessage]
    @State private var showingAddMessage = false
    @State private var showingExportOptions = false
    @State private var showingImportOptions = false
    @State private var selectedMessage: RetentionMessage?
    @State private var selectedProductFilter: String = AppConfiguration.productIDs.first ?? ""
    @State private var isSyncing = false
    @State private var syncResult: SyncResult?
    @State private var showingSyncResult = false
    @State private var syncError: Error?
    @State private var showingConfigurationSetup = false

    private var filteredMessages: [RetentionMessage] {
        // External placeholders have no known product, so show them under every filter
        allMessages.filter { $0.productID == selectedProductFilter || $0.isExternal }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Product filter picker
                Picker("Product", selection: $selectedProductFilter) {
                    ForEach(AppConfiguration.productIDs, id: \.self) { productID in
                        Text(productID).tag(productID)
                    }
                }
                .pickerStyle(.menu)
                .padding()
                .background(Color(nsColor: .controlBackgroundColor))
                
                Divider()
                
                List {
                    ForEach(filteredMessages) { message in
                    NavigationLink {
                        MessageDetailView(message: message)
                    } label: {
                        MessageRowView(message: message)
                    }
                    .contextMenu {
                        if message.uploadStatus == UploadStatus.localOnly.rawValue ||
                           message.uploadStatus == UploadStatus.failed.rawValue {
                            Button {
                                uploadMessage(message)
                            } label: {
                                Label(
                                    message.uploadStatus == UploadStatus.failed.rawValue ? "Retry Upload" : "Upload to API",
                                    systemImage: "icloud.and.arrow.up"
                                )
                            }
                        }
                        
                        Divider()

                        if message.uploadStatus == UploadStatus.uploaded.rawValue {
                            Button(role: .destructive) {
                                deleteMessageFromApple(message)
                            } label: {
                                Label("Delete from Apple & Locally", systemImage: "xmark.icloud")
                            }

                            Button(role: .destructive) {
                                deleteMessage(message)
                            } label: {
                                Label("Delete Locally Only", systemImage: "trash")
                            }
                        } else {
                            Button(role: .destructive) {
                                deleteMessage(message)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    }
                }
            }
            .navigationTitle("Retention Messages")
            .navigationSubtitle(environmentSubtitle)
            .navigationSplitViewColumnWidth(min: 300, ideal: 400)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddMessage = true }) {
                        Label("Add Message", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button(action: syncFromApple) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label("Sync from Apple", systemImage: "arrow.triangle.2.circlepath")
                        }
                    }
                    .disabled(isSyncing)
                }
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingImportOptions = true }) {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    Button(action: { showingExportOptions = true }) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .automatic) {
                    SettingsLink {
                        Label("Settings", systemImage: "gear")
                    }
                    .help("Open Settings")
                }
            }
            .sheet(isPresented: $showingAddMessage) {
                AddMessageView(preselectedProductID: selectedProductFilter)
            }
            .sheet(isPresented: $showingConfigurationSetup, onDismiss: {
                // Refresh the product filter once configuration exists
                if selectedProductFilter.isEmpty {
                    selectedProductFilter = AppConfiguration.productIDs.first ?? ""
                }
            }) {
                ConfigurationSetupView()
                    .interactiveDismissDisabled(!AppConfiguration.isConfigured)
            }
            .onAppear {
                if !AppConfiguration.isConfigured {
                    showingConfigurationSetup = true
                }
            }
            .sheet(isPresented: $showingImportOptions) {
                ImportView()
            }
            .sheet(isPresented: $showingExportOptions) {
                ExportView(messages: allMessages)
            }
            .alert("Sync Complete", isPresented: $showingSyncResult, presenting: syncResult) { _ in
                Button("OK") { }
            } message: { result in
                Text(result.summary)
            }
            .alert("Sync Error", isPresented: .constant(syncError != nil), presenting: syncError) { _ in
                Button("OK") { syncError = nil }
            } message: { error in
                Text(error.localizedDescription)
            }
        } detail: {
            if let message = selectedMessage {
                MessageDetailView(message: message)
            } else {
                Text("Select a retention message")
                    .foregroundStyle(.secondary)
            }
        }
    }
    
    private func deleteMessage(_ message: RetentionMessage) {
        withAnimation {
            modelContext.delete(message)
        }
    }

    /// Delete a message from Apple's servers, then remove it locally
    private func deleteMessageFromApple(_ message: RetentionMessage) {
        Task {
            do {
                try await RetentionMessagingAPIService.shared.deleteMessage(
                    messageIdentifier: message.messageIdentifier
                )
                await MainActor.run {
                    withAnimation {
                        modelContext.delete(message)
                    }
                }
            } catch {
                await MainActor.run {
                    message.uploadError = error.localizedDescription
                    syncError = error
                }
            }
        }
    }
    
    private func uploadMessage(_ message: RetentionMessage) {
        message.uploadStatus = UploadStatus.uploading.rawValue
        message.uploadError = nil
        
        Task {
            do {
                _ = try await RetentionMessagingAPIService.shared.uploadMessage(
                    messageIdentifier: message.messageIdentifier,
                    header: message.headerText,
                    body: message.bodyText,
                    locale: message.locale,
                    imageIdentifier: message.imageIdentifier
                )
                
                await MainActor.run {
                    message.uploadStatus = UploadStatus.uploaded.rawValue
                    message.uploadError = nil
                    message.updatedAt = Date()
                }
            } catch {
                await MainActor.run {
                    message.uploadStatus = UploadStatus.failed.rawValue
                    message.uploadError = error.localizedDescription
                }
            }
        }
    }
    
    private func syncFromApple() {
        isSyncing = true
        syncError = nil
        
        Task {
            do {
                let result = try await SyncService.shared.syncFromApple(modelContext: modelContext)
                await MainActor.run {
                    isSyncing = false
                    syncResult = result
                    showingSyncResult = true
                }
            } catch {
                await MainActor.run {
                    isSyncing = false
                    syncError = error
                }
            }
        }
    }
    
    private var environmentSubtitle: String {
        let env = RetentionMessagingAPIService.shared.environment
        return env == .sandbox ? "Sandbox Environment" : "Production Environment"
    }
}

/// Row view for displaying a retention message in the list
struct MessageRowView: View {
    let message: RetentionMessage
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(message.headerText)
                    .font(.headline)
                
                if message.uploadStatus == UploadStatus.failed.rawValue {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
            
            HStack {
                if message.isExternal {
                    Label("External", systemImage: "icloud")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Exists on Apple but was created outside this app; content unavailable")
                } else {
                    Text(message.productID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Upload status indicator
                if message.uploadStatus == UploadStatus.localOnly.rawValue {
                    Image(systemName: "arrow.up.circle")
                        .foregroundStyle(.blue)
                        .font(.caption)
                }
                
                StatusBadge(state: message.messageState)
            }
        }
        .padding(.vertical, 4)
    }
}

/// Badge showing message state
struct StatusBadge: View {
    let state: String
    
    var body: some View {
        Text(state)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(stateColor.opacity(0.2))
            .foregroundStyle(stateColor)
            .clipShape(Capsule())
    }
    
    private var stateColor: Color {
        switch state.uppercased() {
        case "APPROVED":
            return .green
        case "PENDING":
            return .orange
        case "REJECTED":
            return .red
        default:
            return .gray
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [RetentionMessage.self, RetentionImage.self], inMemory: true)
}
