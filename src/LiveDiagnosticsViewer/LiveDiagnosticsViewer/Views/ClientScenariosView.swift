import CloudKit
import ObjPxlLiveTelemetry
import SwiftUI

struct ClientScenariosView: View {
    @Environment(\.cloudKitClient) private var cloudKitClient

    let client: TelemetryClientDisplay

    @State private var scenarios: [TelemetryScenarioRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var togglingScenarioID: CKRecord.ID?

    var body: some View {
        VStack(alignment: .leading) {
            if isLoading && scenarios.isEmpty {
                ProgressView("Loading scenarios...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if scenarios.isEmpty {
                ContentUnavailableView(
                    "No Scenarios",
                    systemImage: "tag",
                    description: Text("No scenarios registered for this client.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(scenarios, id: \.recordID) { scenario in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(scenario.scenarioName)
                                .font(.headline)

                            Text(scenario.created, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if togglingScenarioID == scenario.recordID {
                            Label("Updating...", systemImage: "clock.arrow.2.circlepath")
                                .foregroundStyle(.secondary)
                        } else {
                            Label(
                                scenario.isActive ? levelLabel(for: scenario.diagnosticLevel) : "Off",
                                systemImage: scenario.isActive ? "checkmark.circle.fill" : "pause.circle.fill"
                            )
                            .foregroundStyle(scenario.isActive ? .green : .secondary)
                        }

                        Menu {
                            Button("Off") {
                                Task { await setScenarioLevel(scenario, level: TelemetryScenarioRecord.levelOff) }
                            }
                            Divider()
                            Button("Debug") {
                                Task { await setScenarioLevel(scenario, level: TelemetryLogLevel.debug.rawValue) }
                            }
                            Button("Info") {
                                Task { await setScenarioLevel(scenario, level: TelemetryLogLevel.info.rawValue) }
                            }
                            Button("Warning") {
                                Task { await setScenarioLevel(scenario, level: TelemetryLogLevel.warning.rawValue) }
                            }
                            Button("Error") {
                                Task { await setScenarioLevel(scenario, level: TelemetryLogLevel.error.rawValue) }
                            }
                        } label: {
                            Label("Level", systemImage: "slider.horizontal.3")
                        }
                        .disabled(togglingScenarioID == scenario.recordID)
                    }
                }
            }

            if let errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .navigationTitle(client.clientId)
        .task { await fetchScenarios() }
        .onReceive(NotificationCenter.default.publisher(for: .telemetryScenariosDidChange)) { _ in
            Task { await fetchScenarios() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await fetchScenarios() }
                }
                .disabled(isLoading)
            }
        }
    }

    private func levelLabel(for level: Int) -> String {
        if level < 0 { return "Off" }
        return TelemetryLogLevel(rawValue: level)?.description ?? "Unknown"
    }

    private func fetchScenarios() async {
        guard let cloudKitClient else { return }
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await cloudKitClient.fetchScenarios(forClient: client.clientId)
            scenarios = fetched
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func setScenarioLevel(_ scenario: TelemetryScenarioRecord, level: Int) async {
        guard let cloudKitClient else { return }
        guard let recordID = scenario.recordID else {
            errorMessage = "Missing CloudKit record identifier for scenario."
            return
        }

        togglingScenarioID = recordID
        errorMessage = nil

        do {
            let command = TelemetryCommandRecord(
                clientId: client.clientId,
                action: .setScenarioLevel,
                scenarioName: scenario.scenarioName,
                diagnosticLevel: level
            )
            _ = try await cloudKitClient.createCommand(command)

            // Do not update scenario record directly — the client owns it
            // Refresh to pick up the client's update
            await refreshAfterLevelChange(for: recordID, expectedLevel: level)
        } catch {
            errorMessage = error.localizedDescription
        }

        togglingScenarioID = nil
    }

    private func refreshAfterLevelChange(for id: CKRecord.ID, expectedLevel: Int) async {
        guard let cloudKitClient else { return }

        for _ in 0..<4 {
            do {
                let fetched = try await cloudKitClient.fetchScenarios(forClient: client.clientId)
                let didUpdate = fetched.first(where: { $0.recordID == id })?.diagnosticLevel == expectedLevel

                scenarios = fetched

                if didUpdate {
                    return
                }
            } catch {
                errorMessage = error.localizedDescription
            }

            try? await Task.sleep(for: .seconds(0.5))
        }
    }
}
