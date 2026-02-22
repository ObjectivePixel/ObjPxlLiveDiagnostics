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
                                scenario.isEnabled ? "Active" : "Inactive",
                                systemImage: scenario.isEnabled ? "checkmark.circle.fill" : "pause.circle.fill"
                            )
                            .foregroundStyle(scenario.isEnabled ? .green : .orange)
                        }

                        Button(
                            scenario.isEnabled ? "Disable" : "Enable",
                            systemImage: scenario.isEnabled ? "pause.fill" : "play.fill"
                        ) {
                            Task { await toggleScenario(scenario) }
                        }
                        .buttonStyle(.bordered)
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

    private func toggleScenario(_ scenario: TelemetryScenarioRecord) async {
        guard let cloudKitClient else { return }
        guard let recordID = scenario.recordID else {
            errorMessage = "Missing CloudKit record identifier for scenario."
            return
        }

        togglingScenarioID = recordID
        errorMessage = nil

        let targetState = !scenario.isEnabled

        do {
            let commandAction: TelemetrySchema.CommandAction = targetState ? .enableScenario : .disableScenario
            let command = TelemetryCommandRecord(
                clientId: client.clientId,
                action: commandAction,
                scenarioName: scenario.scenarioName
            )
            let savedCommand = try await cloudKitClient.createCommand(command)
            print("[Viewer] Scenario command created: \(savedCommand.commandId)")

            let updatedScenario = TelemetryScenarioRecord(
                recordID: recordID,
                clientId: scenario.clientId,
                scenarioName: scenario.scenarioName,
                isEnabled: targetState,
                created: scenario.created
            )
            _ = try await cloudKitClient.updateScenario(updatedScenario)

            if let index = scenarios.firstIndex(where: { $0.recordID == recordID }) {
                scenarios[index] = updatedScenario
            }
        } catch {
            print("[Viewer] Failed to toggle scenario: \(error)")
            errorMessage = error.localizedDescription
        }

        togglingScenarioID = nil
    }
}
