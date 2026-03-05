import CloudKit
import SwiftUI

enum AdminDeleteMode: String, CaseIterable, Identifiable {
    case sessionId = "Session ID"
    case clientCode = "Client Code"
    case recordName = "Record Name"

    var id: Self { self }

    var prompt: String {
        switch self {
        case .sessionId:
            return "Enter a session ID to delete all telemetry records from that session."
        case .clientCode:
            return "Enter a client code to delete the client, its scenarios, and associated telemetry records."
        case .recordName:
            return "Enter a CloudKit record name to delete a single record directly."
        }
    }

    var placeholder: String {
        switch self {
        case .sessionId: return "e.g. abc123-session-456"
        case .clientCode: return "e.g. a1b2c3d4e5f6"
        case .recordName: return "e.g. 7B2F09A1-..."
        }
    }
}

struct AdminDeleteView: View {
    @Environment(\.cloudKitClient) private var cloudKitClient

    @State private var mode: AdminDeleteMode = .sessionId
    @State private var identifier = ""
    @State private var recordType: String = "TelemetryEvent"
    @State private var isDeleting = false
    @State private var showConfirmation = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    private var trimmedIdentifier: String {
        identifier.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Admin Delete")
                .font(.largeTitle)
                .bold()

            Picker("Delete By", selection: $mode) {
                ForEach(AdminDeleteMode.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 500)

            Text(mode.prompt)
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                TextField(mode.placeholder, text: $identifier)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .autocorrectionDisabled()
                    .frame(maxWidth: 500)
                    .onSubmit {
                        if !trimmedIdentifier.isEmpty && !isDeleting {
                            showConfirmation = true
                        }
                    }

                if mode == .recordName {
                    Picker("Record Type", selection: $recordType) {
                        Text("Telemetry Event").tag(TelemetrySchema.recordType)
                        Text("Client").tag(TelemetrySchema.clientRecordType)
                        Text("Scenario").tag(TelemetrySchema.scenarioRecordType)
                    }
                    .frame(maxWidth: 200)
                }
            }

            HStack(spacing: 12) {
                Button("Delete", systemImage: "trash", role: .destructive) {
                    showConfirmation = true
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(trimmedIdentifier.isEmpty || isDeleting)

                if isDeleting {
                    ProgressView()
                }
            }

            if let resultMessage {
                Label(resultMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Admin")
        .onChange(of: mode) { _, _ in
            resultMessage = nil
            errorMessage = nil
        }
        .alert(confirmationTitle, isPresented: $showConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                Task { await performDelete() }
            }
        } message: {
            Text(confirmationMessage)
        }
    }

    private var confirmationTitle: String {
        switch mode {
        case .sessionId:
            return "Delete Session Records"
        case .clientCode:
            return "Delete Client Data"
        case .recordName:
            return "Delete Record"
        }
    }

    private var confirmationMessage: String {
        switch mode {
        case .sessionId:
            return "This will permanently delete all telemetry records for session \"\(trimmedIdentifier)\". This action cannot be undone."
        case .clientCode:
            return "This will permanently delete the client record, all scenario records, and all associated telemetry records for client \"\(trimmedIdentifier)\". This action cannot be undone."
        case .recordName:
            return "This will permanently delete the record with name \"\(trimmedIdentifier)\". This action cannot be undone."
        }
    }

    private func performDelete() async {
        guard let cloudKitClient else { return }
        let value = trimmedIdentifier
        guard !value.isEmpty else { return }

        isDeleting = true
        resultMessage = nil
        errorMessage = nil

        do {
            switch mode {
            case .sessionId:
                let count = try await cloudKitClient.deleteRecordsBySessionId(value)
                resultMessage = "Deleted \(count) telemetry record\(count == 1 ? "" : "s") for session."

            case .clientCode:
                let result = try await cloudKitClient.deleteRecordsByClientCode(value)
                let parts = [
                    result.clients > 0 ? "\(result.clients) client\(result.clients == 1 ? "" : "s")" : nil,
                    result.scenarios > 0 ? "\(result.scenarios) scenario\(result.scenarios == 1 ? "" : "s")" : nil,
                    result.records > 0 ? "\(result.records) record\(result.records == 1 ? "" : "s")" : nil,
                ].compactMap { $0 }

                if parts.isEmpty {
                    resultMessage = "No records found for client \"\(value)\"."
                } else {
                    resultMessage = "Deleted \(parts.joined(separator: ", "))."
                }

            case .recordName:
                try await cloudKitClient.deleteRecordByRecordName(value, recordType: recordType)
                resultMessage = "Record deleted successfully."
            }

            identifier = ""
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }

        isDeleting = false
    }
}
