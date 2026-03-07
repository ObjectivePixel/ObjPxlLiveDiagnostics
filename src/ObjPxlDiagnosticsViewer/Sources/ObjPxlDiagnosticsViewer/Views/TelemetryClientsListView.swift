import CloudKit
import ObjPxlDiagnosticsShared
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct TelemetryClientsListView: View {
    let clients: [TelemetryClientDisplay]
    let isLoading: Bool
    let isDeletingAll: Bool
    let togglingClientID: CKRecord.ID?
    let scenarioCounts: [String: Int]
    let toggleClientState: (TelemetryClientDisplay) async -> Void

    var body: some View {
        List(clients) { client in
            NavigationLink(value: client) {
                TelemetryClientRowView(
                    client: client,
                    isUpdating: togglingClientID == client.id,
                    isDisabled: isLoading || isDeletingAll || togglingClientID == client.id,
                    scenarioCount: scenarioCounts[client.clientId] ?? 0
                ) {
                    Task { await toggleClientState(client) }
                }
            }
            .contextMenu {
                Button("Copy Client Code", systemImage: "doc.on.doc") {
                    copyToPasteboard(client.clientId)
                }
                if let userRecordId = client.userRecordId {
                    Button("Copy User Record ID", systemImage: "square.on.square") {
                        copyToPasteboard(userRecordId)
                    }
                }
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}
