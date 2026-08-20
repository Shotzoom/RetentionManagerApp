//
//  ImportView.swift
//  RetentionManager
//
//  CSV Import tool for retention messages
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var showingFilePicker = false
    @State private var isImporting = false
    @State private var importResult: ImportResult?
    @State private var showingResult = false
    @State private var showingInstructions = true
    @State private var showingCopiedAlert = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Instructions Section
                    if showingInstructions {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("Import Instructions")
                                    .font(.title2)
                                    .fontWeight(.semibold)
                                Spacer()
                                Button(action: copyInstructionsToClipboard) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                        Text("Copy")
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                Button(action: { showingInstructions.toggle() }) {
                                    Image(systemName: "chevron.up")
                                }
                            }
                            
                            Divider()
                            
                            Group {
                                Text("CSV Format Requirements")
                                    .font(.headline)
                                
                                Text("""
                                Your CSV file must include the following columns in order:
                                ProductID, AlternateProductID, CultureCode, Scenario, MessageType, PromoCode, HeaderText, BodyText, ImageID
                                
                                Note: MessageID and MessageState will be auto-generated during import (all messages start as PENDING).
                                """)
                                .font(.caption)
                                .padding(.vertical, 4)
                                
                                Text("Field Requirements:")
                                    .font(.headline)
                                    .padding(.top, 8)
                                
                                VStack(alignment: .leading, spacing: 6) {
                                    BulletPoint("ProductID: Must match one of the application's product IDs")
                                    BulletPoint("AlternateProductID: Optional. When MessageType is 'alternateProduct', both ProductID and AlternateProductID must be in the same subscription group (you must verify this manually)")
                                    BulletPoint("CultureCode: Valid locale format (e.g., en, es, fr, de, en-US)")
                                    BulletPoint("Scenario: Must be one of: Default, TrialCancel, MoreThan30, LessThan30")
                                    BulletPoint("MessageType: Must be one of: message, alternateProduct, promotionalOffer")
                                    BulletPoint("PromoCode: Optional. Required for promotionalOffer type")
                                    BulletPoint("HeaderText: Required. Cannot be empty")
                                    BulletPoint("BodyText: Required. Cannot be empty")
                                    BulletPoint("ImageID: Optional. UUID format if provided")
                                }
                                .font(.caption)
                                
                                Text("Important Notes:")
                                    .font(.headline)
                                    .padding(.top, 8)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("• The import will fail if ANY row has validation errors")
                                    Text("• All rows must pass validation before import")
                                    Text("• MessageIDs are auto-generated as UUIDs")
                                    Text("• Empty required fields will cause import failure")
                                }
                                .font(.caption)
                                .foregroundStyle(.orange)
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Button(action: { showingInstructions.toggle() }) {
                            HStack {
                                Text("Show Import Instructions")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "chevron.down")
                            }
                        }
                        .padding()
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    
                    // Import Button
                    VStack(spacing: 12) {
                        Button(action: { showingFilePicker = true }) {
                            HStack {
                                if isImporting {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "square.and.arrow.down")
                                }
                                Text("Select CSV File to Import")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isImporting)
                        
                        if let result = importResult {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(result.success ? .green : .red)
                                    Text(result.success ? "Import Successful" : "Import Failed")
                                        .font(.headline)
                                }
                                
                                if result.success {
                                    Text("Imported \(result.successCount) messages")
                                        .font(.caption)
                                    if result.skippedCount > 0 {
                                        Text("Skipped \(result.skippedCount) message(s) that already exist locally")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                } else {
                                    Text("Errors found:")
                                        .font(.subheadline)
                                        .fontWeight(.semibold)
                                    
                                    ForEach(Array(result.errors.enumerated()), id: \.offset) { index, error in
                                        Text("• \(error)")
                                            .font(.caption)
                                            .foregroundStyle(.red)
                                    }
                                }
                            }
                            .padding()
                            .background(result.success ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Import Messages")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .fileImporter(
                isPresented: $showingFilePicker,
                allowedContentTypes: [.commaSeparatedText],
                allowsMultipleSelection: false
            ) { result in
                handleFileSelection(result)
            }
            .alert("Instructions Copied", isPresented: $showingCopiedAlert) {
                Button("OK") { }
            } message: {
                Text("Import instructions have been copied to your clipboard")
            }
        }
    }
    
    private func copyInstructionsToClipboard() {
        let instructions = """
        CSV IMPORT INSTRUCTIONS FOR RETENTION MESSAGES
        
        CSV FORMAT:
        Your CSV file must have these columns in order:
        ProductID,AlternateProductID,CultureCode,Scenario,MessageType,PromoCode,HeaderText,BodyText,ImageID
        
        Note: MessageID and MessageState will be auto-generated during import.
        All imported messages start with MessageState = PENDING.
        
        FIELD REQUIREMENTS:
        
        • ProductID: REQUIRED
          Must match one of the configured product IDs:
        \(AppConfiguration.productIDs.map { "  - \($0)" }.joined(separator: "\n"))

        • AlternateProductID: OPTIONAL
          If provided, must be one of the product IDs above.
          When MessageType is 'alternateProduct', both ProductID and AlternateProductID 
          must be in the same subscription group (you must verify this manually).
        
        • CultureCode: REQUIRED
          Valid locale format. Examples: en, es, fr, de, en-US, es-MX
        
        • Scenario: REQUIRED
          Must be one of: Default, TrialCancel, MoreThan30, LessThan30
        
        • MessageType: REQUIRED
          Must be one of: message, alternateProduct, promotionalOffer
        
        • PromoCode: OPTIONAL
          Required when MessageType is 'promotionalOffer', otherwise leave empty.
        
        • HeaderText: REQUIRED
          Cannot be empty. The message header/title.
        
        • BodyText: REQUIRED
          Cannot be empty. The main message content.
        
        • ImageID: OPTIONAL
          UUID format if provided, otherwise leave empty.
        
        IMPORTANT NOTES:
        • The import will fail if ANY row has validation errors
        • All rows must pass validation before any data is imported
        • MessageIDs are auto-generated as UUIDs
        • Empty required fields will cause import failure
        
        EXAMPLE CSV:
        ProductID,AlternateProductID,CultureCode,Scenario,MessageType,PromoCode,HeaderText,BodyText,ImageID
        \(AppConfiguration.productIDs.first ?? "com.example.app.subscription"),\(AppConfiguration.productIDs.dropFirst().first ?? ""),en,TrialCancel,alternateProduct,,Don't go,Try a low price monthly plan,
        \(AppConfiguration.productIDs.first ?? "com.example.app.subscription"),,es,TrialCancel,message,,No vayas,Prueba un plan mensual a bajo costo,
        """
        
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(instructions, forType: .string)
        
        showingCopiedAlert = true
    }
    
    private func handleFileSelection(_ result: Result<[URL], Error>) {
        guard let url = try? result.get().first else { return }
        
        isImporting = true
        importResult = nil
        
        Task {
            do {
                let result = try await importCSV(from: url)
                await MainActor.run {
                    importResult = result
                    isImporting = false
                    showingResult = true
                }
            } catch {
                await MainActor.run {
                    importResult = ImportResult(
                        success: false,
                        successCount: 0,
                        errors: ["Failed to read file: \(error.localizedDescription)"]
                    )
                    isImporting = false
                }
            }
        }
    }
    
    private func importCSV(from url: URL) async throws -> ImportResult {
        // Start accessing security-scoped resource
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        let csvContent = try String(contentsOf: url, encoding: .utf8)
        let lines = csvContent.components(separatedBy: .newlines)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        
        guard lines.count > 1 else {
            return ImportResult(success: false, successCount: 0, errors: ["CSV file is empty or only contains headers"])
        }
        
        // Validate header — two formats are accepted:
        // 1. Authoring format: hand-written CSVs for creating new messages
        //    (MessageID and MessageState are auto-generated)
        // 2. Full export format: files produced by this app's Export feature
        //    (MessageID and MessageState are preserved so a sync can re-match Apple)
        let header = lines[0]
        let authoringHeader = "ProductID,AlternateProductID,CultureCode,Scenario,MessageType,PromoCode,HeaderText,BodyText,ImageID"
        let fullExportHeader = "MessageID,ProductID,AlternateProductID,CultureCode,Scenario,MessageType,PromoCode,HeaderText,BodyText,MessageState,ImageID,DateAdded_UTC,DateModified_UTC"

        let format: CSVImportFormat
        if header == authoringHeader {
            format = .authoring
        } else if header == fullExportHeader {
            format = .fullExport
        } else {
            return ImportResult(
                success: false,
                successCount: 0,
                errors: ["Invalid CSV header. Expected either:\n\(authoringHeader)\nor (app export format):\n\(fullExportHeader)"]
            )
        }

        // Parse and validate all rows first
        var messagesToImport: [RetentionMessage] = []
        var errors: [String] = []

        for (index, line) in lines.dropFirst().enumerated() {
            let rowNumber = index + 2 // +2 because we skip header and arrays are 0-indexed

            do {
                let message = try parseCSVRow(line, rowNumber: rowNumber, format: format)
                messagesToImport.append(message)
            } catch {
                errors.append("Row \(rowNumber): \(error.localizedDescription)")
            }
        }

        // If any errors, fail the entire import
        if !errors.isEmpty {
            return ImportResult(success: false, successCount: 0, errors: errors)
        }

        // All validation passed. Insert messages, skipping identifiers that already
        // exist locally so re-importing a backup is idempotent.
        var insertedCount = 0
        var skippedCount = 0

        await MainActor.run {
            let descriptor = FetchDescriptor<RetentionMessage>()
            let existingIDs = Set(((try? modelContext.fetch(descriptor)) ?? []).map { $0.messageIdentifier.lowercased() })

            for message in messagesToImport {
                if existingIDs.contains(message.messageIdentifier.lowercased()) {
                    skippedCount += 1
                    continue
                }
                modelContext.insert(message)
                insertedCount += 1
            }

            do {
                try modelContext.save()
            } catch {
                // This shouldn't happen since we validated everything
            }
        }

        return ImportResult(success: true, successCount: insertedCount, errors: [], skippedCount: skippedCount)
    }

    /// The CSV layouts the importer understands
    private enum CSVImportFormat {
        case authoring    // 9 columns, IDs auto-generated
        case fullExport   // 13 columns from this app's Export feature, IDs preserved
    }

    private func parseCSVRow(_ line: String, rowNumber: Int, format: CSVImportFormat) throws -> RetentionMessage {
        let fields = parseCSVLine(line).map { $0.trimmingCharacters(in: .whitespaces) }

        let expectedFieldCount = format == .authoring ? 9 : 13
        guard fields.count >= expectedFieldCount else {
            throw ImportError.invalidFormat("Expected \(expectedFieldCount) fields, got \(fields.count)")
        }

        let productID: String
        let alternateProductID: String
        let cultureCode: String
        let scenario: String
        let messageType: String
        let promoCode: String
        let headerText: String
        let bodyText: String
        let imageID: String
        let messageID: String
        let messageState: String
        var createdAt: Date?
        var updatedAt: Date?

        switch format {
        case .authoring:
            productID = fields[0]
            alternateProductID = fields[1]
            cultureCode = fields[2]
            scenario = fields[3]
            messageType = fields[4]
            promoCode = fields[5]
            headerText = fields[6]
            bodyText = fields[7]
            imageID = fields[8]

            // Auto-generate MessageID (lowercased to match Apple's normalization)
            messageID = UUID().uuidString.lowercased()
            messageState = "PENDING"

        case .fullExport:
            // Preserve the original MessageID so a subsequent sync re-matches
            // this message against Apple's records
            guard let uuid = UUID(uuidString: fields[0]) else {
                throw ImportError.invalidFormat("MessageID '\(fields[0])' is not a valid UUID")
            }
            messageID = uuid.uuidString.lowercased()
            productID = fields[1]
            alternateProductID = fields[2]
            cultureCode = fields[3]
            scenario = fields[4]
            messageType = fields[5]
            promoCode = fields[6]
            headerText = fields[7]
            bodyText = fields[8]
            messageState = fields[9].isEmpty ? "PENDING" : fields[9]
            imageID = fields[10]
            createdAt = ISO8601DateFormatter().date(from: fields[11])
            updatedAt = ISO8601DateFormatter().date(from: fields[12])
        }
        
        // Validate ProductID exists in the configured list
        guard AppConfiguration.productIDs.contains(productID) else {
            throw ImportError.invalidProductID("ProductID '\(productID)' is not recognized. Must be one of the configured product IDs.")
        }

        // Validate AlternateProductID if provided
        if !alternateProductID.isEmpty {
            guard AppConfiguration.productIDs.contains(alternateProductID) else {
                throw ImportError.invalidProductID("AlternateProductID '\(alternateProductID)' is not recognized")
            }

            // Note: User is responsible for ensuring ProductID and AlternateProductID
            // are in the same subscription group for alternateProduct type messages
        }
        
        // Validate CultureCode (basic locale format check)
        guard cultureCode.range(of: "^[a-z]{2}(-[A-Z]{2})?$", options: .regularExpression) != nil else {
            throw ImportError.invalidLocale("CultureCode '\(cultureCode)' is not valid. Expected format: en, es, fr, de, en-US, etc.")
        }
        
        // Validate Scenario
        let validScenarios = ["Default", "TrialCancel", "MoreThan30", "LessThan30"]
        guard validScenarios.contains(scenario) else {
            throw ImportError.invalidScenario("Scenario '\(scenario)' is not valid. Must be one of: \(validScenarios.joined(separator: ", "))")
        }
        
        // Validate MessageType
        let validMessageTypes = ["message", "alternateProduct", "promotionalOffer"]
        guard validMessageTypes.contains(messageType) else {
            throw ImportError.invalidMessageType("MessageType '\(messageType)' is not valid. Must be one of: \(validMessageTypes.joined(separator: ", "))")
        }
        
        // Validate PromoCode requirement for promotionalOffer
        if messageType == "promotionalOffer" && promoCode.isEmpty {
            throw ImportError.missingPromoCode("PromoCode is required for MessageType 'promotionalOffer'")
        }
        
        // Validate required text fields
        guard !headerText.isEmpty else {
            throw ImportError.missingField("HeaderText cannot be empty")
        }
        
        guard !bodyText.isEmpty else {
            throw ImportError.missingField("BodyText cannot be empty")
        }
        
        // Validate ImageID if provided
        if !imageID.isEmpty {
            guard UUID(uuidString: imageID) != nil else {
                throw ImportError.invalidFormat("ImageID is not a valid UUID")
            }
        }
        
        // Create the message. Upload status starts as localOnly; a sync against
        // Apple will flip re-matched messages to uploaded with their current state.
        let message = RetentionMessage(
            messageIdentifier: messageID,
            productID: productID,
            headerText: headerText,
            bodyText: bodyText,
            imageIdentifier: imageID.isEmpty ? nil : imageID,
            messageState: messageState,
            uploadStatus: UploadStatus.localOnly.rawValue,
            locale: cultureCode,
            messageType: messageType,
            alternateProductID: alternateProductID.isEmpty ? nil : alternateProductID,
            promoCode: promoCode.isEmpty ? nil : promoCode,
            scenario: scenario
        )

        // Preserve original timestamps from full-export files
        if let createdAt {
            message.createdAt = createdAt
        }
        if let updatedAt {
            message.updatedAt = updatedAt
        }

        return message
    }
    
    // Parse CSV line handling quoted fields
    private func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var currentField = ""
        var insideQuotes = false
        
        for char in line {
            if char == "\"" {
                insideQuotes.toggle()
            } else if char == "," && !insideQuotes {
                fields.append(currentField)
                currentField = ""
            } else {
                currentField.append(char)
            }
        }
        fields.append(currentField)
        
        return fields.map { $0.replacingOccurrences(of: "\"\"", with: "\"") }
    }
}

struct BulletPoint: View {
    let text: String
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Text("•")
            Text(text)
        }
    }
}

struct ImportResult {
    let success: Bool
    let successCount: Int
    let errors: [String]
    var skippedCount: Int = 0
}

enum ImportError: LocalizedError {
    case invalidFormat(String)
    case invalidProductID(String)
    case invalidLocale(String)
    case invalidScenario(String)
    case invalidMessageType(String)
    case missingField(String)
    case missingPromoCode(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFormat(let msg),
             .invalidProductID(let msg),
             .invalidLocale(let msg),
             .invalidScenario(let msg),
             .invalidMessageType(let msg),
             .missingField(let msg),
             .missingPromoCode(let msg):
            return msg
        }
    }
}

#Preview {
    ImportView()
        .modelContainer(for: [RetentionMessage.self], inMemory: true)
}
