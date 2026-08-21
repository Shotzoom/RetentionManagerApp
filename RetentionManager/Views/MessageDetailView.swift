//
//  MessageDetailView.swift
//  RetentionManager
//
//  Created by John Hawley on 3/11/26.
//

import SwiftUI
import SwiftData

struct MessageDetailView: View {
    @Bindable var message: RetentionMessage
    @Query private var images: [RetentionImage]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Observed so the view re-renders when the environment changes in Settings
    @AppStorage("apiEnvironment") private var apiEnvironmentRaw = APIEnvironment.sandbox.rawValue

    private var environment: APIEnvironment {
        APIEnvironment(rawValue: apiEnvironmentRaw) ?? .sandbox
    }

    @State private var isUploading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingSuccess = false
    @State private var isSettingDefault = false
    @State private var showingDefaultSuccess = false
    @State private var isDeleting = false
    @State private var showingDeleteConfirmation = false
    @State private var showingEditSheet = false
    
    var messageImage: RetentionImage? {
        guard let imageId = message.imageIdentifier else { return nil }
        return images.first { $0.imageIdentifier == imageId }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Message Details")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    HStack {
                        StatusBadge(state: message.messageState(in: environment))
                        
                        UploadStatusBadge(status: message.uploadStatus(in: environment))
                        
                        if message.isDefault(in: environment) {
                            HStack(spacing: 4) {
                                Image(systemName: "star.fill")
                                Text("Default")
                            }
                            .font(.caption2)
                            .fontWeight(.medium)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.yellow.opacity(0.2))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                        }
                        
                        Spacer()
                        
                        Text("Updated: \(message.updatedAt, style: .date)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Upload Error Display
                if message.uploadStatus(in: environment) == UploadStatus.failed.rawValue,
                   let error = message.uploadError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    .padding(8)
                    .background(Color.red.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                
                // Upload Actions
                HStack(spacing: 12) {
                    if message.uploadStatus(in: environment) == UploadStatus.localOnly.rawValue ||
                       message.uploadStatus(in: environment) == UploadStatus.failed.rawValue {
                        Button(action: uploadMessage) {
                            HStack {
                                if isUploading {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "icloud.and.arrow.up")
                                }
                                Text(message.uploadStatus(in: environment) == UploadStatus.failed.rawValue ? "Retry Upload" : "Upload to API")
                            }
                        }
                        .disabled(isUploading)
                        .buttonStyle(.borderedProminent)
                    }
                    
                    if message.uploadStatus(in: environment) == UploadStatus.uploaded.rawValue {
                        HStack {
                            Image(systemName: "checkmark.icloud.fill")
                                .foregroundStyle(.green)
                            Text("Synced with Apple")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        // Only show "Set as Default" for uploaded text messages or text with image.
                        // External placeholders have no known product/locale to configure.
                        // Apple rejects non-APPROVED messages with 403 MessageNotApprovedError,
                        // so keep the button disabled until the message passes review.
                        if message.messageType == MessageType.message.rawValue && !message.isExternal {
                            Button(action: setAsDefaultMessage) {
                                HStack {
                                    if isSettingDefault {
                                        ProgressView()
                                            .controlSize(.small)
                                    } else {
                                        Image(systemName: "star.circle")
                                    }
                                    Text("Set as Default")
                                }
                            }
                            .disabled(isSettingDefault || !isApproved)
                            .buttonStyle(.bordered)
                            .help(isApproved
                                  ? "Configure this as the default message for \(message.productID) in \(message.locale)"
                                  : "Available once Apple approves this message. Current state: \(message.messageState(in: environment)). Use Sync from Apple to refresh.")

                            if !isApproved {
                                Text("Awaiting Apple approval")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Spacer()

                    Button(action: { showingEditSheet = true }) {
                        HStack {
                            Image(systemName: "pencil")
                            Text("Edit")
                        }
                    }
                    .help(message.isUploadedAnywhere
                          ? "Edit the internal cancellation scenario (message content on Apple is immutable)"
                          : "Edit this message")

                    Button(role: .destructive, action: { showingDeleteConfirmation = true }) {
                        HStack {
                            if isDeleting {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "trash")
                            }
                            Text("Delete")
                        }
                    }
                    .disabled(isDeleting)
                    .help(isUploaded ? "Delete this message from Apple and/or locally" : "Delete this message from the local database")
                }
                
                Divider()
                
                // Message Information
                VStack(alignment: .leading, spacing: 12) {
                    DetailRow(label: "Message ID", value: message.messageIdentifier)
                    DetailRow(
                        label: "Product",
                        value: message.productID
                    )
                    DetailRow(label: "Primary Locale", value: message.locale)
                    DetailRow(
                        label: "Message Type",
                        value: MessageType(rawValue: message.messageType)?.displayName ?? message.messageType
                    )
                    DetailRow(
                        label: "Scenario",
                        value: CancellationScenario(rawValue: message.scenario)?.displayName ?? message.scenario
                    )

                    if message.messageType == MessageType.promotionalOffer.rawValue {
                        DetailRow(label: "Promo Code", value: message.promoCode ?? "⚠️ Not set")
                    }

                    if message.messageType == MessageType.alternateProduct.rawValue {
                        DetailRow(label: "Alternate Product", value: message.alternateProductID ?? "⚠️ Not set")
                    }

                    DetailRow(label: "Created", value: message.createdAt.formatted(date: .abbreviated, time: .shortened))
                }
                
                Divider()
                
                // Image Section
                if let image = messageImage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Image")
                            .font(.headline)
                        
                        if let nsImage = NSImage(data: image.imageData) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        
                        Text("Alt Text: \(image.altText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Divider()
                }
                
                // Message Content
                VStack(alignment: .leading, spacing: 8) {
                    Text("Message Content (\(message.locale))")
                        .font(.headline)
                    
                    Text("Header")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(message.headerText)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    Text("Body")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(message.bodyText)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding()
        }
        .frame(minWidth: 400)
        .alert("Upload Successful", isPresented: $showingSuccess) {
            Button("OK") { }
        } message: {
            Text("Message uploaded to Apple's API successfully. It will be reviewed and approved.")
        }
        .alert("Default Message Configured", isPresented: $showingDefaultSuccess) {
            Button("OK") { }
        } message: {
            Text("This message is now configured as the default for \(message.productID) in \(message.locale). Apple will use this message if your server doesn't respond.")
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showingEditSheet) {
            EditMessageView(message: message, isUploaded: message.isUploadedAnywhere)
        }
        .confirmationDialog("Delete Message", isPresented: $showingDeleteConfirmation) {
            if isUploaded {
                Button("Delete from Apple & Locally", role: .destructive) {
                    deleteMessage(fromApple: true)
                }
                Button("Delete Locally Only", role: .destructive) {
                    deleteMessage(fromApple: false)
                }
            } else {
                Button("Delete", role: .destructive) {
                    deleteMessage(fromApple: false)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            if isUploaded {
                Text("This message exists on Apple's servers. Deleting from Apple removes it from the Retention Messaging API. Deleting locally only will cause it to reappear as an external message on the next sync.")
            } else {
                Text("This message only exists locally and has not been sent to Apple. This cannot be undone.")
            }
        }
    }

    /// Whether this message has been uploaded to Apple
    private var isUploaded: Bool {
        message.uploadStatus(in: environment) == UploadStatus.uploaded.rawValue
    }

    /// Whether Apple has approved this message for use
    private var isApproved: Bool {
        message.messageState(in: environment).uppercased() == "APPROVED"
    }

    /// Delete this message, optionally from Apple's servers first
    private func deleteMessage(fromApple: Bool) {
        isDeleting = true

        Task {
            do {
                if fromApple {
                    try await RetentionMessagingAPIService.shared.deleteMessage(
                        messageIdentifier: message.messageIdentifier
                    )
                }

                await MainActor.run {
                    modelContext.delete(message)
                    try? modelContext.save()
                    isDeleting = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = "Failed to delete from Apple: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }

    private func uploadMessage() {
        isUploading = true
        let env = environment
        message.setUploadStatus(UploadStatus.uploading.rawValue, in: env)
        message.uploadError = nil
        
        Task {
            do {
                var uploadedImageId: String? = nil
                
                // Upload image first if needed
                if let imageData = messageImage?.imageData,
                   let imageId = message.imageIdentifier {
                    print("⬆️ Uploading image first...")
                    uploadedImageId = try await RetentionMessagingAPIService.shared.uploadImage(
                        imageData: imageData,
                        imageIdentifier: imageId,
                        altText: messageImage?.altText ?? "Retention message image"
                    )
                    print("✅ Image uploaded successfully")
                }
                
                // Upload message
                print("⬆️ Uploading message...")
                _ = try await RetentionMessagingAPIService.shared.uploadMessage(
                    messageIdentifier: message.messageIdentifier,
                    header: message.headerText,
                    body: message.bodyText,
                    locale: message.locale,
                    imageIdentifier: uploadedImageId
                )
                
                await MainActor.run {
                    message.setUploadStatus(UploadStatus.uploaded.rawValue, in: env)
                    message.uploadError = nil
                    message.updatedAt = Date()
                    isUploading = false
                    showingSuccess = true
                }
            } catch {
                await MainActor.run {
                    message.setUploadStatus(UploadStatus.failed.rawValue, in: env)
                    message.uploadError = error.localizedDescription
                    isUploading = false
                    errorMessage = error.localizedDescription
                    print("❌ Upload failed: \(error)")
                    showingError = true
                }
            }
        }
    }
    
    private func setAsDefaultMessage() {
        isSettingDefault = true
        
        Task {
            do {
                // First, clear any existing default for this product/locale combo
                let descriptor = FetchDescriptor<RetentionMessage>()
                let allMessages = try modelContext.fetch(descriptor)
                
                for msg in allMessages {
                    if msg.productID == message.productID && 
                       msg.locale == message.locale && 
                       msg.isDefault(in: environment) {
                        msg.setIsDefault(false, in: environment)
                    }
                }
                
                // Mark this message as default in the current environment
                message.setIsDefault(true, in: environment)
                
                // Save the changes locally
                try modelContext.save()
                
                // Configure this message as the default on Apple's API.
                // Normalize handles any legacy short-code locales ("en" → "en-US").
                try await RetentionMessagingAPIService.shared.configureDefaultMessage(
                    productID: message.productID,
                    locale: SupportedLocale.normalize(message.locale),
                    messageIdentifier: message.messageIdentifier
                )
                
                await MainActor.run {
                    isSettingDefault = false
                    showingDefaultSuccess = true
                }
            } catch {
                await MainActor.run {
                    isSettingDefault = false
                    errorMessage = "Failed to set as default: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
}

/// Sheet for editing a retention message.
/// Uploaded messages: only the internal cancellation scenario is editable, since
/// message content on Apple is immutable (no update API — only delete + re-upload).
/// Local-only messages: all fields are editable.
struct EditMessageView: View {
    @Bindable var message: RetentionMessage
    @Environment(\.dismiss) private var dismiss

    let isUploaded: Bool

    @State private var scenario: CancellationScenario
    @State private var messageType: MessageType
    @State private var headerText: String
    @State private var bodyText: String
    @State private var selectedProductID: String?
    @State private var selectedLocale: SupportedLocale?
    @State private var alternateProductID: String?
    @State private var promoCode: String

    init(message: RetentionMessage, isUploaded: Bool) {
        self.message = message
        self.isUploaded = isUploaded
        _scenario = State(initialValue: CancellationScenario(rawValue: message.scenario) ?? .trialCancel)
        _messageType = State(initialValue: MessageType(rawValue: message.messageType) ?? .message)
        _headerText = State(initialValue: message.headerText)
        _bodyText = State(initialValue: message.bodyText)
        _selectedProductID = State(initialValue: AppConfiguration.productIDs.contains(message.productID) ? message.productID : nil)
        _selectedLocale = State(initialValue: SupportedLocale(rawValue: message.locale))
        _alternateProductID = State(initialValue: message.alternateProductID)
        _promoCode = State(initialValue: message.promoCode ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                if isUploaded {
                    Section {
                        HStack {
                            Image(systemName: "lock.icloud")
                                .foregroundStyle(.secondary)
                            Text("This message is uploaded to Apple, so its content can't be changed. The cancellation scenario is internal metadata that only affects how our server selects messages.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Cancellation Scenario") {
                    Picker("Scenario", selection: $scenario) {
                        ForEach(CancellationScenario.allCases) { scenario in
                            VStack(alignment: .leading) {
                                Text(scenario.displayName)
                                Text(scenario.description)
                                    .font(.caption2)
                            }
                            .tag(scenario)
                        }
                    }
                    .help("When is the user cancelling their subscription?")
                }

                if !isUploaded {
                    Section("Message Type") {
                        Picker("Message Type", selection: $messageType) {
                            ForEach(MessageType.allCases) { type in
                                Text(type.displayName).tag(type)
                            }
                        }

                        if messageType == .alternateProduct {
                            Picker("Alternate Product ID", selection: $alternateProductID) {
                                Text("Select Product").tag(nil as String?)
                                ForEach(AppConfiguration.productIDs, id: \.self) { productID in
                                    Text(productID).tag(productID as String?)
                                }
                            }
                        }

                        if messageType == .promotionalOffer {
                            TextField("Promo Code", text: $promoCode)
                                .help("The promotional offer code to apply")
                        }
                    }

                    Section("Product & Locale") {
                        Picker("Product ID", selection: $selectedProductID) {
                            ForEach(AppConfiguration.productIDs, id: \.self) { productID in
                                Text(productID).tag(productID as String?)
                            }
                        }

                        Picker("Locale", selection: $selectedLocale) {
                            ForEach(SupportedLocale.allCases) { locale in
                                Text("\(locale.displayName) (\(locale.rawValue))").tag(locale as SupportedLocale?)
                            }
                        }
                    }

                    Section("Message Content") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Header")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                CharacterCountLabel(count: headerText.count, limit: RetentionMessageLimits.maxHeaderLength)
                            }
                            TextField("Header", text: $headerText)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Body")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                CharacterCountLabel(count: bodyText.count, limit: RetentionMessageLimits.maxBodyLength)
                            }
                            TextEditor(text: $bodyText)
                                .frame(minHeight: 100)
                                .font(.body)
                                .scrollContentBackground(.hidden)
                                .background(Color.gray.opacity(0.05))
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isUploaded ? "Edit Scenario" : "Edit Message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                    }
                    .disabled(!canSave)
                }
            }
        }
        .frame(minWidth: 500, minHeight: isUploaded ? 250 : 600)
    }

    private var canSave: Bool {
        if isUploaded {
            return true
        }
        return !headerText.isEmpty
            && !bodyText.isEmpty
            && headerText.count <= RetentionMessageLimits.maxHeaderLength
            && bodyText.count <= RetentionMessageLimits.maxBodyLength
    }

    private func saveChanges() {
        message.scenario = scenario.rawValue

        if !isUploaded {
            message.messageType = messageType.rawValue
            message.headerText = headerText
            message.bodyText = bodyText
            if let selectedProductID {
                message.productID = selectedProductID
            }
            if let selectedLocale {
                message.locale = selectedLocale.rawValue
            }
            message.alternateProductID = messageType == .alternateProduct ? alternateProductID : nil
            message.promoCode = messageType == .promotionalOffer && !promoCode.isEmpty ? promoCode : nil
        }

        message.updatedAt = Date()
        dismiss()
    }
}

/// Badge showing upload status
struct UploadStatusBadge: View {
    let status: String
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
            Text(status)
        }
        .font(.caption2)
        .fontWeight(.medium)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(statusColor.opacity(0.2))
        .foregroundStyle(statusColor)
        .clipShape(Capsule())
    }
    
    private var statusIcon: String {
        switch status {
        case UploadStatus.localOnly.rawValue:
            return "chevron.up.circle"
        case UploadStatus.uploading.rawValue:
            return "arrow.up.circle"
        case UploadStatus.uploaded.rawValue:
            return "checkmark.icloud.fill"
        case UploadStatus.failed.rawValue:
            return "exclamationmark.triangle.fill"
        default:
            return "questionmark.circle"
        }
    }
    
    private var statusColor: Color {
        switch status {
        case UploadStatus.localOnly.rawValue:
            return .blue
        case UploadStatus.uploading.rawValue:
            return .orange
        case UploadStatus.uploaded.rawValue:
            return .green
        case UploadStatus.failed.rawValue:
            return .red
        default:
            return .gray
        }
    }
}

/// Detail row for displaying key-value pairs
struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .fontWeight(.medium)
                .frame(width: 120, alignment: .leading)
            
            Text(value)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
}

/// Section showing message content in a specific language
#Preview {
    @Previewable @State var message = RetentionMessage(
        messageIdentifier: UUID().uuidString,
        productID: "com.example.app.subscription",
        headerText: "Welcome to TOUR Caddie PRO",
        bodyText: "Get access to all premium features including advanced statistics, course maps, and more.",
        messageState: "APPROVED",
        locale: "en-US"
    )
    
    MessageDetailView(message: message)
        .modelContainer(for: [RetentionMessage.self, RetentionImage.self], inMemory: true)
}
