import CloudKit
import ObjPxlDiagnosticsShared
import SwiftUI

struct TelemetryClientRowView: View {
    let client: TelemetryClientDisplay
    let isUpdating: Bool
    let isDisabled: Bool
    let scenarioCount: Int
    let toggleState: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                Text(client.clientId)
                    .font(.headline)
                Spacer()
                if isUpdating {
                    Label("Updating...", systemImage: "clock.arrow.2.circlepath")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                } else if client.isForceOn {
                    Label("Forced", systemImage: "bolt.circle.fill")
                        .foregroundStyle(.purple)
                        .font(.caption)
                } else {
                    Label(
                        client.isEnabled ? "Active" : "Inactive",
                        systemImage: client.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
                    )
                    .foregroundStyle(client.isEnabled ? .green : .orange)
                    .font(.caption)
                }
            }

            Text(client.created, format: .dateTime.year().month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(client.id.recordName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if scenarioCount > 0 {
                    Spacer()
                    Label("\(scenarioCount) scenario\(scenarioCount == 1 ? "" : "s")", systemImage: "tag")
                        .font(.caption2)
                        .foregroundStyle(.tint)
                }
            }

            Button(
                client.isEnabled ? "Deactivate" : "Activate",
                systemImage: client.isEnabled ? "pause.fill" : "play.fill",
                action: toggleState
            )
            .buttonStyle(.bordered)
            .disabled(isDisabled)
        }
    }
}
