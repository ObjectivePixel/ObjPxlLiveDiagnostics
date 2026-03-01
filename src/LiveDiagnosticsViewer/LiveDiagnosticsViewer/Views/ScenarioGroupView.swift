import CloudKit
import ObjPxlLiveTelemetry
import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct ScenarioGroupView: View {
    let scenarioName: String
    let scenarios: [TelemetryScenarioRecord]
    let togglingScenarioID: CKRecord.ID?
    let setScenarioLevel: (TelemetryScenarioRecord, Int) async -> Void

    var body: some View {
        DisclosureGroup {
            ForEach(scenarios, id: \.recordID) { scenario in
                ScenarioClientRowView(
                    scenario: scenario,
                    isToggling: togglingScenarioID == scenario.recordID,
                    setLevel: { level in Task { await setScenarioLevel(scenario, level) } }
                )
                .contextMenu {
                    Button("Copy Client Code", systemImage: "doc.on.doc") {
                        copyToPasteboard(scenario.clientId)
                    }
                }
            }
        } label: {
            Label(scenarioName, systemImage: "tag")
                .font(.headline)
                .badge(scenarios.count)
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
