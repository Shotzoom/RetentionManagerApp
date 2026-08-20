//
//  AddMessageView.swift
//  RetentionManager
//
//  Created by John Hawley on 3/11/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct AddMessageView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    let preselectedProductID: String

    @State private var messageType: MessageType = .message
    @State private var scenario: CancellationScenario = .trialCancel
    @State private var alternateProductID: String?
    @State private var promoCode = ""
    @State private var headerText = ""
    @State private var bodyText = ""
    @State private var selectedLocales: Set<SupportedLocale> = [.english]
    @State private var selectedImage: NSImage?
    @State private var imageData: Data?
    @State private var altText = ""
    
    // Translations
    @State private var isTranslating = false
    @State private var translatedHeaders: [String: String] = [:]
    @State private var translatedBodies: [String: String] = [:]
    
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var showingImagePicker = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Message Information") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Message Identifiers")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Each locale will receive its own unique UUID")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(8)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Product ID")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(preselectedProductID)
                            .font(.body)
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    
                    Picker("Cancellation Scenario", selection: $scenario) {
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
                    
                    Picker("Message Type", selection: $messageType) {
                        ForEach(MessageType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .help("Type of retention message for your server to handle")
                    .onChange(of: messageType) { oldValue, newValue in
                        // Clear image when switching away from text message type
                        if newValue != .message {
                            selectedImage = nil
                            imageData = nil
                            altText = ""
                        }
                    }
                    
                    // Show alternate product picker for alternateProduct type
                    if messageType == .alternateProduct {
                        Picker("Alternate Product ID", selection: $alternateProductID) {
                            Text("Select Product").tag(nil as String?)
                            ForEach(AppConfiguration.productIDs, id: \.self) { productID in
                                Text(productID).tag(productID as String?)
                            }
                        }
                        .help("The product to offer as an alternative")
                    }
                    
                    // Show promo code field for promotionalOffer type
                    if messageType == .promotionalOffer {
                        TextField("Promo Code", text: $promoCode)
                            .help("The promotional offer code to apply")
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Target Locales")
                            .font(.headline)
                        Text("Select all locales to generate messages for. Each locale will create a separate message.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        ForEach(SupportedLocale.allCases) { locale in
                            Toggle(isOn: Binding(
                                get: { selectedLocales.contains(locale) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedLocales.insert(locale)
                                    } else {
                                        selectedLocales.remove(locale)
                                    }
                                }
                            )) {
                                HStack {
                                    Text(locale.displayName)
                                    Text("(\(locale.rawValue))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
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
                        TextField("Enter a short, compelling header", text: $headerText)
                            .textFieldStyle(.roundedBorder)
                        Text("Example: \"Don't miss out on premium features\"")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
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
                        Text("Main message explaining the value of staying subscribed")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                // Only show image section for standard text messages
                if messageType == .message {
                    Section("Image (Optional)") {
                        if let selectedImage = selectedImage {
                            HStack {
                                Image(nsImage: selectedImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 100)
                                
                                Spacer()
                                
                                Button("Remove") {
                                    self.selectedImage = nil
                                    self.imageData = nil
                                }
                            }
                        } else {
                            Button("Select Image") {
                                showingImagePicker = true
                            }
                        }
                        
                        if selectedImage != nil {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Spacer()
                                    CharacterCountLabel(count: altText.count, limit: RetentionMessageLimits.maxAltTextLength)
                                }
                                TextField("Alt Text", text: $altText)
                                    .help("Alternative text describing the image")
                            }
                        }
                    }
                } else {
                    Section {
                        Text("Images are only supported for text-based messages")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Section("Translations") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("English text will be automatically translated to selected locales when you save.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        if selectedLocales.count > 1 {
                            if isTranslating {
                                HStack {
                                    ProgressView()
                                    Text("Generating translations...")
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Button("Preview Translations") {
                                    Task {
                                        await autoTranslate()
                                    }
                                }
                                .disabled(headerText.isEmpty || bodyText.isEmpty)
                            }
                            
                            if !translatedHeaders.isEmpty {
                                Divider()
                                Text("Translation Preview")
                                    .font(.headline)
                                
                                ForEach(Array(translatedHeaders.keys.sorted()), id: \.self) { localeCode in
                                    let translatedHeader = translatedHeaders[localeCode] ?? ""
                                    let translatedBody = translatedBodies[localeCode] ?? ""
                                    let headerOverLimit = translatedHeader.count > RetentionMessageLimits.maxHeaderLength
                                    let bodyOverLimit = translatedBody.count > RetentionMessageLimits.maxBodyLength

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(SupportedLocale(rawValue: localeCode)?.displayName ?? localeCode)
                                                .font(.subheadline)
                                                .fontWeight(.semibold)
                                            if headerOverLimit || bodyOverLimit {
                                                Image(systemName: "exclamationmark.triangle.fill")
                                                    .foregroundStyle(.red)
                                                    .font(.caption)
                                                    .help("Translation exceeds Apple's character limits and will be rejected")
                                            }
                                        }
                                        HStack(alignment: .top) {
                                            Text(translatedHeader)
                                                .font(.caption)
                                                .foregroundStyle(headerOverLimit ? .red : .primary)
                                            Spacer()
                                            CharacterCountLabel(count: translatedHeader.count, limit: RetentionMessageLimits.maxHeaderLength)
                                        }
                                        HStack(alignment: .top) {
                                            Text(translatedBody)
                                                .font(.caption2)
                                                .foregroundStyle(bodyOverLimit ? .red : .secondary)
                                            Spacer()
                                            CharacterCountLabel(count: translatedBody.count, limit: RetentionMessageLimits.maxBodyLength)
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.gray.opacity(0.05))
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Retention Message")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveMessage()
                    }
                    .disabled(headerText.isEmpty || bodyText.isEmpty || isOverCharacterLimits)
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
            .fileImporter(
                isPresented: $showingImagePicker,
                allowedContentTypes: [.png, .jpeg],
                allowsMultipleSelection: false
            ) { result in
                handleImageSelection(result)
            }
        }
    }
    
    /// Whether any field exceeds Apple's character limits
    private var isOverCharacterLimits: Bool {
        headerText.count > RetentionMessageLimits.maxHeaderLength ||
        bodyText.count > RetentionMessageLimits.maxBodyLength ||
        altText.count > RetentionMessageLimits.maxAltTextLength
    }

    private func autoTranslate() async {
        isTranslating = true
        defer { isTranslating = false }
        
        do {
            let translations = try await TranslationService.shared.translateMessage(
                header: headerText,
                body: bodyText
            )
            
            await MainActor.run {
                translatedHeaders = [
                    "es": translations.header.spanish,
                    "fr": translations.header.french,
                    "de": translations.header.german
                ]
                translatedBodies = [
                    "es": translations.body.spanish,
                    "fr": translations.body.french,
                    "de": translations.body.german
                ]
            }
        } catch {
            await MainActor.run {
                errorMessage = "Translation failed: \(error.localizedDescription)"
                showingError = true
            }
        }
    }
    
    private func handleImageSelection(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            
            // Start accessing security-scoped resource
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            
            // Read image data
            let data = try Data(contentsOf: url)
            guard let image = NSImage(data: data) else {
                throw NSError(domain: "AddMessageView", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to load image"])
            }
            
            selectedImage = image
            imageData = data
            
            // Set default alt text based on filename
            if altText.isEmpty {
                altText = url.deletingPathExtension().lastPathComponent
            }
        } catch {
            errorMessage = "Failed to load image: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    private func saveMessage() {
        Task {
            // If translations haven't been generated yet and we need them, generate them first
            if selectedLocales.count > 1 && translatedHeaders.isEmpty {
                await autoTranslate()
            }
            
            await MainActor.run {
                // Create a shared image if one was selected
                var sharedImageIdentifier: String?
                if let imageData = imageData {
                    // Lowercased to match Apple's identifier normalization
                    let imageIdentifier = UUID().uuidString.lowercased()
                    let image = RetentionImage(
                        imageIdentifier: imageIdentifier,
                        imageData: imageData,
                        altText: altText
                    )
                    sharedImageIdentifier = imageIdentifier
                    modelContext.insert(image)
                }
                
                // Create a message for each selected locale
                for locale in selectedLocales {
                    let localeCode = locale.rawValue
                    
                    // Determine header and body text for this locale
                    let localizedHeader: String
                    let localizedBody: String
                    
                    if localeCode == "en" {
                        // English uses the original text
                        localizedHeader = headerText
                        localizedBody = bodyText
                    } else {
                        // Other locales use translated text
                        localizedHeader = translatedHeaders[localeCode] ?? headerText
                        localizedBody = translatedBodies[localeCode] ?? bodyText
                    }
                    
                    // Create unique message ID for this locale (proper UUID)
                    // Lowercased to match Apple's identifier normalization
                    let messageIdentifier = UUID().uuidString.lowercased()
                    
                    let message = RetentionMessage(
                        messageIdentifier: messageIdentifier,
                        productID: preselectedProductID,
                        headerText: localizedHeader,
                        bodyText: localizedBody,
                        imageIdentifier: sharedImageIdentifier,
                        messageState: "PENDING",
                        uploadStatus: UploadStatus.localOnly.rawValue,
                        locale: localeCode,
                        messageType: messageType.rawValue,
                        alternateProductID: alternateProductID,
                        promoCode: promoCode.isEmpty ? nil : promoCode,
                        scenario: scenario.rawValue
                    )
                    
                    modelContext.insert(message)
                }
                
                dismiss()
            }
        }
    }
}

/// Live character counter showing usage against an API limit.
/// Turns orange when approaching the limit and red when over it.
struct CharacterCountLabel: View {
    let count: Int
    let limit: Int

    var body: some View {
        Text("\(count)/\(limit)")
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(countColor)
    }

    private var countColor: Color {
        if count > limit {
            return .red
        } else if count >= limit - 10 {
            return .orange
        } else {
            return .secondary
        }
    }
}

#Preview {
    AddMessageView(preselectedProductID: "com.example.app.subscription")
        .modelContainer(for: [RetentionMessage.self, RetentionImage.self], inMemory: true)
}
