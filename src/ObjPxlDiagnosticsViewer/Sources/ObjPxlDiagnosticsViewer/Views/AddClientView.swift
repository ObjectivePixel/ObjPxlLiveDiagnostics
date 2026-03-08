import SwiftUI
import ObjPxlDiagnosticsShared

struct AddClientView: View {
    @Binding var clientCode: String
    let isSending: Bool
    let errorMessage: String?
    let onSubmit: () async -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Client Code", text: $clientCode)
                        .font(.system(.body, design: .monospaced))
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                } header: {
                    Text("Enter the 12-character code displayed in the client app.")
                } footer: {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Add Client")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending {
                        ProgressView()
                    } else {
                        Button("Activate") {
                            Task { await onSubmit() }
                        }
                        .disabled(clientCode.trimmingCharacters(in: .whitespaces).count < 10)
                    }
                }
            }
        }
    }
}
