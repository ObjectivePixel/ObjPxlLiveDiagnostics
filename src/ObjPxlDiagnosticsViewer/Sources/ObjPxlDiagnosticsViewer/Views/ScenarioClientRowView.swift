import SwiftUI

struct ScenarioClientRowView: View {
    let scenario: TelemetryScenarioRecord
    let isToggling: Bool
    let setLevel: (Int) -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(scenario.clientId)
                    .font(.headline)
                Text(scenario.created, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if isToggling {
                ProgressView()
                    .controlSize(.small)
            } else {
                Text(levelLabel(for: scenario.diagnosticLevel))
                    .foregroundStyle(scenario.isActive ? .green : .secondary)

                Menu {
                    Button("Off") { setLevel(TelemetryScenarioRecord.levelOff) }
                    Divider()
                    Button("Debug") { setLevel(TelemetryLogLevel.debug.rawValue) }
                    Button("Info") { setLevel(TelemetryLogLevel.info.rawValue) }
                    Button("Warning") { setLevel(TelemetryLogLevel.warning.rawValue) }
                    Button("Error") { setLevel(TelemetryLogLevel.error.rawValue) }
                } label: {
                    Label("Level", systemImage: "slider.horizontal.3")
                }
            }
        }
    }

    private func levelLabel(for level: Int) -> String {
        if level < 0 { return "Off" }
        return TelemetryLogLevel(rawValue: level)?.description ?? "Unknown"
    }
}
