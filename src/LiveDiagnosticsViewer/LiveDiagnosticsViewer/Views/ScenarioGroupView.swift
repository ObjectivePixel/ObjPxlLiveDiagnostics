import CloudKit
import ObjPxlLiveTelemetry
import SwiftUI

struct ScenarioGroupView: View {
    let scenarioName: String
    let scenarios: [TelemetryScenarioRecord]
    let togglingScenarioID: CKRecord.ID?
    let toggleScenario: (TelemetryScenarioRecord) async -> Void

    var body: some View {
        DisclosureGroup {
            ForEach(scenarios, id: \.recordID) { scenario in
                ScenarioClientRowView(
                    scenario: scenario,
                    isToggling: togglingScenarioID == scenario.recordID,
                    toggleScenario: { Task { await toggleScenario(scenario) } }
                )
            }
        } label: {
            Label(scenarioName, systemImage: "tag")
                .font(.headline)
                .badge(scenarios.count)
        }
    }
}
