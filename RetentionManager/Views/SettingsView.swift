//
//  SettingsView.swift
//  RetentionManager
//
//  Created by John Hawley on 3/11/26.
//

import SwiftUI

struct SettingsView: View {
    @State private var selectedEnvironment: APIEnvironment = RetentionMessagingAPIService.shared.environment
    @State private var showingSaveConfirmation = false

    // Configuration editing
    @State private var showingConfigurationEditor = false

    // Realtime endpoint configuration state
    @State private var realtimeURLInput: String = AppConfiguration.sandboxRealtimeEndpointURL
    @State private var configuredRealtimeURL: String?
    @State private var realtimeStatusMessage: String?
    @State private var realtimeStatusIsError = false
    @State private var isRealtimeOperationInProgress = false

    // Performance test state (persisted so results can be checked across launches)
    @AppStorage("perfTestTransactionId") private var perfTestTransactionId = ""
    @AppStorage("perfTestRequestId") private var perfTestRequestId = ""
    @State private var perfTestStatusMessage: String?
    @State private var perfTestStatusIsError = false
    @State private var isPerfTestOperationInProgress = false

    var body: some View {
        Form {
            Section("Configuration") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Team ID:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(AppConfiguration.teamID)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Key ID:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(AppConfiguration.keyID)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Bundle ID:")
                            .fontWeight(.medium)
                        Spacer()
                        Text(AppConfiguration.bundleID)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("Private Key:")
                            .fontWeight(.medium)
                        Spacer()
                        if AppConfiguration.privateKeyPEM.isEmpty {
                            Text("Not configured")
                                .foregroundStyle(.red)
                        } else {
                            Label("Configured", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                        }
                    }

                    HStack {
                        Text("Products:")
                            .fontWeight(.medium)
                        Spacer()
                        Text("\(AppConfiguration.productIDs.count) configured")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }

                Button("Edit Configuration…") {
                    showingConfigurationEditor = true
                }
            }
            
            Section("Environment") {
                Picker("API Environment", selection: $selectedEnvironment) {
                    ForEach(APIEnvironment.allCases) { env in
                        Text(env.rawValue).tag(env)
                    }
                }
                .pickerStyle(.segmented)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "testtube.2")
                            .foregroundStyle(.orange)
                        Text("Sandbox:")
                            .fontWeight(.medium)
                        Text("For testing with sandbox Apple IDs")
                    }
                    .font(.caption)
                    
                    HStack {
                        Image(systemName: "checkmark.shield")
                            .foregroundStyle(.green)
                        Text("Production:")
                            .fontWeight(.medium)
                        Text("For live retention messages")
                    }
                    .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            
            Section("Realtime Endpoint") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The URL Apple's App Store server calls to get real-time retention message selections for the \(selectedEnvironment.rawValue) environment.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Endpoint URL", text: $realtimeURLInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    if let configuredURL = configuredRealtimeURL {
                        HStack {
                            Text("Currently configured:")
                                .fontWeight(.medium)
                            Text(configuredURL)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                    }

                    HStack {
                        Button("Fetch Current") {
                            fetchRealtimeURL()
                        }

                        Button("Configure") {
                            configureRealtimeURL()
                        }
                        .disabled(realtimeURLInput.isEmpty || realtimeURLInput.count > 256)

                        Button("Delete", role: .destructive) {
                            deleteRealtimeURL()
                        }

                        if isRealtimeOperationInProgress {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .disabled(isRealtimeOperationInProgress)

                    if realtimeURLInput.count > 256 {
                        Text("URL exceeds the 256 character maximum (\(realtimeURLInput.count) characters)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }

                    if let statusMessage = realtimeStatusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(realtimeStatusIsError ? .red : .green)
                            .textSelection(.enabled)
                    }
                }
            }

            Section("Performance Test (Sandbox)") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple requires a passing performance test of your Get Retention Message endpoint before you can configure the production realtime URL. Tests always run in the sandbox environment against the sandbox realtime URL, and require the original transaction ID of an active auto-renewable subscription purchased with a sandbox Apple ID.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("Sandbox Original Transaction ID", text: $perfTestTransactionId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    if !perfTestRequestId.isEmpty {
                        HStack {
                            Text("Last test request ID:")
                                .fontWeight(.medium)
                            Text(perfTestRequestId)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        .font(.caption)
                    }

                    HStack {
                        Button("Initiate Performance Test") {
                            initiatePerformanceTest()
                        }
                        .disabled(perfTestTransactionId.trimmingCharacters(in: .whitespaces).isEmpty)

                        Button("Check Results") {
                            checkPerformanceTestResults()
                        }
                        .disabled(perfTestRequestId.isEmpty)

                        if isPerfTestOperationInProgress {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .disabled(isPerfTestOperationInProgress)

                    if let statusMessage = perfTestStatusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(perfTestStatusIsError ? .red : .green)
                            .textSelection(.enabled)
                    }
                }
            }

            Section {
                Button("Save Environment") {
                    saveConfiguration()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 780)
        .sheet(isPresented: $showingConfigurationEditor, onDismiss: {
            // Pick up a possibly-updated sandbox endpoint URL
            if realtimeURLInput.isEmpty {
                realtimeURLInput = AppConfiguration.sandboxRealtimeEndpointURL
            }
        }) {
            ConfigurationSetupView()
        }
        .alert("Environment Saved", isPresented: $showingSaveConfirmation) {
            Button("OK") { }
        } message: {
            Text("API environment set to \(selectedEnvironment.rawValue). All requests will use this environment.")
        }
    }
    
    private func saveConfiguration() {
        // Save environment selection
        RetentionMessagingAPIService.shared.environment = selectedEnvironment
        showingSaveConfirmation = true
    }

    // MARK: - Realtime Endpoint Actions

    /// Fetch the currently configured realtime URL from Apple
    private func fetchRealtimeURL() {
        performRealtimeOperation {
            RetentionMessagingAPIService.shared.environment = selectedEnvironment
            let url = try await RetentionMessagingAPIService.shared.getRealtimeURL()
            configuredRealtimeURL = url
            if let url {
                realtimeURLInput = url
                return "Fetched configured URL for \(selectedEnvironment.rawValue)."
            } else {
                return "No realtime URL is configured for \(selectedEnvironment.rawValue)."
            }
        }
    }

    /// Configure the realtime URL with Apple
    private func configureRealtimeURL() {
        performRealtimeOperation {
            RetentionMessagingAPIService.shared.environment = selectedEnvironment
            try await RetentionMessagingAPIService.shared.configureRealtimeURL(realtimeURLInput)
            configuredRealtimeURL = realtimeURLInput
            return "Realtime URL configured for \(selectedEnvironment.rawValue)."
        }
    }

    /// Delete the configured realtime URL from Apple
    private func deleteRealtimeURL() {
        performRealtimeOperation {
            RetentionMessagingAPIService.shared.environment = selectedEnvironment
            try await RetentionMessagingAPIService.shared.deleteRealtimeURL()
            configuredRealtimeURL = nil
            return "Realtime URL deleted for \(selectedEnvironment.rawValue)."
        }
    }

    // MARK: - Performance Test Actions

    /// Initiate a sandbox performance test of the Get Retention Message endpoint
    private func initiatePerformanceTest() {
        isPerfTestOperationInProgress = true
        perfTestStatusMessage = nil
        Task {
            do {
                let requestId = try await RetentionMessagingAPIService.shared.initiatePerformanceTest(
                    originalTransactionId: perfTestTransactionId.trimmingCharacters(in: .whitespaces)
                )
                perfTestRequestId = requestId
                perfTestStatusMessage = "Performance test started (request ID: \(requestId)). Apple runs the test against your sandbox realtime URL — use Check Results to see the outcome."
                perfTestStatusIsError = false
            } catch {
                perfTestStatusMessage = error.localizedDescription
                perfTestStatusIsError = true
            }
            isPerfTestOperationInProgress = false
        }
    }

    /// Fetch the results of the most recently initiated performance test
    private func checkPerformanceTestResults() {
        isPerfTestOperationInProgress = true
        perfTestStatusMessage = nil
        Task {
            do {
                let result = try await RetentionMessagingAPIService.shared.getPerformanceTestResult(
                    requestId: perfTestRequestId
                )

                var lines: [String] = []

                switch result.result.uppercased() {
                case "PASS":
                    lines.append("✅ PASSED")
                case "FAIL":
                    lines.append("❌ FAILED")
                default:
                    lines.append("⏳ PENDING — test still running, check again shortly")
                }

                var progressLine = ""
                if let successRate = result.successRate {
                    progressLine += "Success rate: \(successRate)%"
                    if let threshold = result.config?.successRateThreshold {
                        progressLine += " (need \(threshold)% to pass)"
                    }
                }
                if let numPending = result.numPending, numPending > 0 {
                    if let total = result.config?.totalRequests {
                        progressLine += " • \(total - numPending)/\(total) requests completed"
                    } else {
                        progressLine += " • \(numPending) requests pending"
                    }
                }
                if !progressLine.isEmpty {
                    lines.append(progressLine)
                }

                if let times = result.responseTimes {
                    var timing: [String] = []
                    if let avg = times.average { timing.append("avg \(avg)ms") }
                    if let p50 = times.p50 { timing.append("p50 \(p50)ms") }
                    if let p90 = times.p90 { timing.append("p90 \(p90)ms") }
                    if let p95 = times.p95 { timing.append("p95 \(p95)ms") }
                    if let p99 = times.p99 { timing.append("p99 \(p99)ms") }
                    if !timing.isEmpty {
                        var timingLine = "Response times: " + timing.joined(separator: ", ")
                        if let threshold = result.config?.responseTimeThreshold {
                            timingLine += " (limit \(threshold)ms)"
                        }
                        lines.append(timingLine)
                    }
                }

                if let config = result.config {
                    var configParts: [String] = []
                    if let total = config.totalRequests { configParts.append("\(total) requests") }
                    if let concurrent = config.maxConcurrentRequests { configParts.append("max \(concurrent) concurrent") }
                    if let duration = config.totalDuration { configParts.append("over \(duration / 1000)s") }
                    if !configParts.isEmpty {
                        lines.append("Test plan: " + configParts.joined(separator: ", "))
                    }
                }

                if let failures = result.failures, !failures.isEmpty {
                    let failureList = failures.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
                    lines.append("⚠️ Failures: \(failureList)")
                }

                if let target = result.target {
                    lines.append("Target: \(target)")
                }

                perfTestStatusMessage = lines.joined(separator: "\n")
                perfTestStatusIsError = result.result.uppercased() == "FAIL"
            } catch {
                perfTestStatusMessage = error.localizedDescription
                perfTestStatusIsError = true
            }
            isPerfTestOperationInProgress = false
        }
    }

    /// Run a realtime endpoint operation with shared progress and error handling
    private func performRealtimeOperation(_ operation: @escaping () async throws -> String) {
        isRealtimeOperationInProgress = true
        realtimeStatusMessage = nil
        Task {
            do {
                let message = try await operation()
                realtimeStatusMessage = message
                realtimeStatusIsError = false
            } catch {
                realtimeStatusMessage = error.localizedDescription
                realtimeStatusIsError = true
            }
            isRealtimeOperationInProgress = false
        }
    }
}

#Preview {
    SettingsView()
}
