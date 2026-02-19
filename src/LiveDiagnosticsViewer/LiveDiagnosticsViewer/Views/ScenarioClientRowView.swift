import ObjPxlLiveTelemetry
import SwiftUI

struct ScenarioClientRowView: View {
    let scenario: TelemetryScenarioRecord
    let isToggling: Bool
    let toggleScenario: () -> Void

    var body: some View {
        HStack {
            Text(scenario.clientId)
                .font(.body)

            Spacer()

            if isToggling {
                Label("Updating...", systemImage: "clock.arrow.2.circlepath")
                    .foregroundStyle(.secondary)
            } else {
                Label(
                    scenario.isEnabled ? "Active" : "Inactive",
                    systemImage: scenario.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
                )
                .foregroundStyle(scenario.isEnabled ? .green : .orange)
            }

            Button(
                scenario.isEnabled ? "Disable" : "Enable",
                systemImage: scenario.isEnabled ? "pause.fill" : "play.fill"
            ) {
                toggleScenario()
            }
            .buttonStyle(.bordered)
            .disabled(isToggling)
        }
    }
}
