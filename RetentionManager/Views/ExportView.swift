//
//  ExportView.swift
//  RetentionManager
//
//  Created by John Hawley on 3/11/26.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ExportView: View {
    @Environment(\.dismiss) private var dismiss
    
    let messages: [RetentionMessage]
    
    @State private var exportFormat: ExportFormat = .csv
    @State private var showingSavePanel = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var didCopy = false
    
    enum ExportFormat: String, CaseIterable {
        case csv = "CSV"
        case sql = "SQL Insert Statements"
        
        var fileExtension: String {
            switch self {
            case .csv: return "csv"
            case .sql: return "sql"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Export Retention Messages")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Picker("Export Format", selection: $exportFormat) {
                    ForEach(ExportFormat.allCases, id: \.self) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                if exportFormat == .sql && csvExportMessages.count != sqlExportMessages.count {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("\(csvExportMessages.count - sqlExportMessages.count) Apple-default message(s) excluded from the SQL export — they serve only as Apple's fallback and aren't returned by our API. (They are included in the CSV backup.)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Preview")
                        .font(.headline)
                    
                    ScrollView {
                        Text(generatePreview())
                            .font(.system(.caption, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.gray.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .frame(maxHeight: 300)
                }
                .padding(.horizontal)
                
                Spacer()
                
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button {
                        copyToClipboard()
                    } label: {
                        HStack {
                            Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                            Text(didCopy ? "Copied!" : "Copy")
                        }
                    }
                    .help("Copy the full \(exportFormat.rawValue) output to the clipboard")

                    Button("Export...") {
                        exportData()
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
            .padding()
            .frame(width: 600, height: 500)
            .alert("Error", isPresented: $showingError) {
                Button("OK") { }
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func generatePreview() -> String {
        switch exportFormat {
        case .csv:
            return generateCSV(limit: 3)
        case .sql:
            return generateSQL(limit: 3)
        }
    }
    
    /// Messages included in the CSV export (backup/transfer format).
    /// External placeholders are excluded — their content is unknown, so there is
    /// nothing to back up; they are recreated by syncing with Apple.
    private var csvExportMessages: [RetentionMessage] {
        messages.filter { !$0.isExternal }
    }

    /// Messages included in the SQL export for the backend. In addition to external
    /// placeholders, Apple-default messages are excluded: they exist solely as Apple's
    /// fallback when our API doesn't respond in time, and exporting them would
    /// conflict with our system's own default handling. The default flag follows
    /// the currently selected environment.
    private var sqlExportMessages: [RetentionMessage] {
        messages.filter { !$0.isExternal && !$0.isDefault(in: APIEnvironment.current) }
    }

    private func generateCSV(limit: Int? = nil) -> String {
        let messagesToExport = limit != nil ? Array(csvExportMessages.prefix(limit!)) : csvExportMessages

        var csv = "# ITunesRetentionDefinitions (\(APIEnvironment.current.rawValue) environment)\n"
        csv += "MessageID,ProductID,AlternateProductID,CultureCode,Scenario,MessageType,PromoCode,HeaderText,BodyText,MessageState,ImageID,DateAdded_UTC,DateModified_UTC\n"

        for message in messagesToExport {
            let exportScenario = message.scenario

            let row = [
                escapeCSV(message.messageIdentifier),
                escapeCSV(message.productID),
                escapeCSV(message.alternateProductID ?? ""),
                escapeCSV(message.locale),
                escapeCSV(exportScenario),
                escapeCSV(message.messageType),
                escapeCSV(message.promoCode ?? ""),
                escapeCSV(message.headerText),
                escapeCSV(message.bodyText),
                escapeCSV(message.messageState(in: APIEnvironment.current)),
                escapeCSV(message.imageIdentifier ?? ""),
                escapeCSV(ISO8601DateFormatter().string(from: message.createdAt)),
                escapeCSV(ISO8601DateFormatter().string(from: message.updatedAt))
            ].joined(separator: ",")
            
            csv += row + "\n"
        }
        
        if let limit = limit, csvExportMessages.count > limit {
            csv += "\n# ... and \(csvExportMessages.count - limit) more messages\n"
        }

        return csv
    }
    
    private func generateSQL(limit: Int? = nil) -> String {
        var sql = """
        -- ITunesRetentionDefinitions Export
        -- Generated: \(Date())
        -- Environment: \(APIEnvironment.current.rawValue)
        -- SQL Server Schema

        -- Replace existing contents (table and schema are managed by the backend)
        DELETE FROM dbo.ITunesRetentionDefinitions;

        -- Insert messages
        
        """
        
        let messagesToExport = limit != nil ? Array(sqlExportMessages.prefix(limit!)) : sqlExportMessages

        for message in messagesToExport {
            let exportScenario = message.scenario

            var insertStatement = "INSERT INTO ITunesRetentionDefinitions (MessageID, ProductID, "
            var valuesList = "VALUES (\n    '\(message.messageIdentifier.uppercased())',\n    '\(escapeSQL(message.productID))',\n    "
            
            // Add AlternateProductID if present
            if let altProductID = message.alternateProductID {
                insertStatement += "AlternateProductID, "
                valuesList += "'\(escapeSQL(altProductID))',\n    "
            }
            
            insertStatement += "CultureCode, Scenario, MessageType, "
            valuesList += "'\(escapeSQL(message.locale))',\n    '\(escapeSQL(exportScenario))',\n    '\(escapeSQL(message.messageType))',\n    "
            
            // Add PromoCode if present
            if let promoCode = message.promoCode {
                insertStatement += "PromoCode, "
                valuesList += "'\(escapeSQL(promoCode))',\n    "
            }
            
            insertStatement += "HeaderText, BodyText, MessageState"
            valuesList += "'\(escapeSQL(message.headerText))',\n    '\(escapeSQL(message.bodyText))',\n    '\(escapeSQL(message.messageState(in: APIEnvironment.current)))'"
            
            // Add ImageID if present
            if let imageID = message.imageIdentifier {
                insertStatement += ", ImageID"
                valuesList += ",\n    '\(escapeSQL(imageID))'"
            }
            
            insertStatement += ")\n"
            valuesList += "\n);\n"
            
            sql += insertStatement + valuesList
        }
        
        if let limit = limit, sqlExportMessages.count > limit {
            sql += "-- ... and \(sqlExportMessages.count - limit) more messages\n"
        }

        return sql
    }
    
    private func escapeCSV(_ string: String) -> String {
        if string.contains(",") || string.contains("\"") || string.contains("\n") {
            return "\"\(string.replacingOccurrences(of: "\"", with: "\"\""))\""
        }
        return string
    }
    
    private func escapeSQL(_ string: String) -> String {
        return string.replacingOccurrences(of: "'", with: "''")
    }
    
    /// Copy the full export content (not the truncated preview) to the clipboard
    private func copyToClipboard() {
        let content: String
        switch exportFormat {
        case .csv:
            content = generateCSV()
        case .sql:
            content = generateSQL()
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(content, forType: .string)

        // Brief visual confirmation, then revert the button label
        didCopy = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopy = false
        }
    }

    private func exportData() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: exportFormat.fileExtension)!]
        panel.nameFieldStringValue = "retention_messages.\(exportFormat.fileExtension)"
        
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    let content: String
                    switch exportFormat {
                    case .csv:
                        content = generateCSV()
                    case .sql:
                        content = generateSQL()
                    }
                    
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    dismiss()
                } catch {
                    errorMessage = "Failed to export: \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
}

#Preview {
    let message = RetentionMessage(
        messageIdentifier: UUID().uuidString,
        productID: "com.example.app.subscription",
        headerText: "Welcome to TOUR Caddie PRO",
        bodyText: "Get access to all premium features.",
        messageState: "APPROVED",
        locale: "en-US"
    )
    
    ExportView(messages: [message])
}
