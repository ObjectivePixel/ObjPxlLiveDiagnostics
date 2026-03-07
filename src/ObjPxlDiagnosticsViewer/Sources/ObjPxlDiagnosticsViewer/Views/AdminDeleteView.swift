import CloudKit
import ObjPxlDiagnosticsShared
import SwiftUI

enum AdminDeleteMode: String, CaseIterable, Identifiable {
    case sessionId = "Session ID"
    case clientCode = "Client Code"
    case userRecordId = "User Record ID"

    var id: Self { self }

    var prompt: String {
        switch self {
        case .sessionId:
            return "Enter a session ID to delete all telemetry records from that session."
        case .clientCode:
            return "Enter a client code to delete the client, its scenarios, and associated telemetry records."
        case .userRecordId:
            return "Enter a user record ID to delete all clients, scenarios, commands, and telemetry records for that user."
        }
    }

    var placeholder: String {
        switch self {
        case .sessionId: return "e.g. abc123-session-456"
        case .clientCode: return "e.g. a1b2c3d4e5f6"
        case .userRecordId: return "e.g. _abc123def456..."
        }
    }
}

struct AdminDeleteView: View {
    @Environment(\.cloudKitClient) private var cloudKitClient

    @State private var mode: AdminDeleteMode = .sessionId
    @State private var identifier = ""
    @State private var isDeleting = false
    @State private var showConfirmation = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    // Delete All state
    @State private var deleteAllConfirmText = ""
    @State private var isDeletingAll = false
    @State private var showDeleteAllConfirmation = false
    @State private var deleteAllResultMessage: String?
    @State private var deleteAllErrorMessage: String?

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

            Divider()
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 12) {
                Text("Delete All Records")
                    .font(.headline)
                    .foregroundStyle(.red)

                Text("Permanently delete every record across all types: events, clients, scenarios, and commands. Type DELETE to confirm.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    TextField("Type DELETE to confirm", text: $deleteAllConfirmText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        .frame(maxWidth: 300)

                    Button("Delete All Records", systemImage: "trash.fill", role: .destructive) {
                        showDeleteAllConfirmation = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(deleteAllConfirmText != "DELETE" || isDeletingAll)

                    if isDeletingAll {
                        ProgressView()
                    }
                }

                if let deleteAllResultMessage {
                    Label(deleteAllResultMessage, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.callout)
                }

                if let deleteAllErrorMessage {
                    Label(deleteAllErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
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
        .alert("Delete All Records", isPresented: $showDeleteAllConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete Everything", role: .destructive) {
                Task { await performDeleteAll() }
            }
        } message: {
            Text("This will permanently delete ALL events, clients, scenarios, and commands in the database. This action cannot be undone.")
        }
    }

    private var confirmationTitle: String {
        switch mode {
        case .sessionId:
            return "Delete Session Records"
        case .clientCode:
            return "Delete Client Data"
        case .userRecordId:
            return "Delete All User Data"
        }
    }

    private var confirmationMessage: String {
        switch mode {
        case .sessionId:
            return "This will permanently delete all telemetry records for session \"\(trimmedIdentifier)\". This action cannot be undone."
        case .clientCode:
            return "This will permanently delete the client record, all scenario records, and all associated telemetry records for client \"\(trimmedIdentifier)\". This action cannot be undone."
        case .userRecordId:
            return "This will permanently delete all clients, scenarios, commands, and telemetry records for user \"\(trimmedIdentifier)\". This action cannot be undone."
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
            var failedCount = 0

            switch mode {
            case .sessionId:
                let result = try await cloudKitClient.deleteRecordsBySessionId(value)
                failedCount = result.failed
                resultMessage = "Deleted \(result.deleted) telemetry record\(result.deleted == 1 ? "" : "s") for session."

            case .clientCode:
                let result = try await cloudKitClient.deleteRecordsByClientCode(value)
                failedCount = result.failed
                let parts = [
                    result.clients > 0 ? "\(result.clients) client\(result.clients == 1 ? "" : "s")" : nil,
                    result.scenarios > 0 ? "\(result.scenarios) scenario\(result.scenarios == 1 ? "" : "s")" : nil,
                    result.records > 0 ? "\(result.records) record\(result.records == 1 ? "" : "s")" : nil,
                ].compactMap { $0 }

                if parts.isEmpty && failedCount == 0 {
                    resultMessage = "No records found for client \"\(value)\"."
                } else {
                    resultMessage = "Deleted \(parts.joined(separator: ", "))."
                }

            case .userRecordId:
                let result = try await cloudKitClient.deleteRecordsByUserRecordId(value)
                failedCount = result.failed
                let parts = [
                    result.clients > 0 ? "\(result.clients) client\(result.clients == 1 ? "" : "s")" : nil,
                    result.scenarios > 0 ? "\(result.scenarios) scenario\(result.scenarios == 1 ? "" : "s")" : nil,
                    result.commands > 0 ? "\(result.commands) command\(result.commands == 1 ? "" : "s")" : nil,
                    result.events > 0 ? "\(result.events) event\(result.events == 1 ? "" : "s")" : nil,
                ].compactMap { $0 }

                if parts.isEmpty && failedCount == 0 {
                    resultMessage = "No records found for user \"\(value)\"."
                } else {
                    resultMessage = "Deleted \(parts.joined(separator: ", "))."
                }
            }

            if failedCount > 0 {
                errorMessage = "\(failedCount) record\(failedCount == 1 ? "" : "s") failed to delete. Check console for details."
            }

            identifier = ""
        } catch {
            errorMessage = "Delete failed: \(error.localizedDescription)"
        }

        isDeleting = false
    }

    private func performDeleteAll() async {
        guard let cloudKitClient else { return }
        guard deleteAllConfirmText == "DELETE" else { return }

        isDeletingAll = true
        deleteAllResultMessage = nil
        deleteAllErrorMessage = nil

        do {
            let result = try await cloudKitClient.deleteAllTelemetryData()
            let parts = [
                result.events > 0 ? "\(result.events) event\(result.events == 1 ? "" : "s")" : nil,
                result.clients > 0 ? "\(result.clients) client\(result.clients == 1 ? "" : "s")" : nil,
                result.scenarios > 0 ? "\(result.scenarios) scenario\(result.scenarios == 1 ? "" : "s")" : nil,
                result.commands > 0 ? "\(result.commands) command\(result.commands == 1 ? "" : "s")" : nil,
            ].compactMap { $0 }

            if parts.isEmpty && result.failed == 0 {
                deleteAllResultMessage = "No records found."
            } else {
                deleteAllResultMessage = "Deleted \(parts.joined(separator: ", "))."
            }

            if result.failed > 0 {
                deleteAllErrorMessage = "\(result.failed) record\(result.failed == 1 ? "" : "s") failed to delete. Check console for details."
            }

            deleteAllConfirmText = ""
        } catch {
            deleteAllErrorMessage = "Delete all failed: \(error.localizedDescription)"
        }

        isDeletingAll = false
    }
}
