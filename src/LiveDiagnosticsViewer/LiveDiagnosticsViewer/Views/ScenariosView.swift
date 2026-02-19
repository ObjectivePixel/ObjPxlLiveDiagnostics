import CloudKit
import ObjPxlLiveTelemetry
import SwiftUI

extension Notification.Name {
    static let telemetryScenariosDidChange = Notification.Name("telemetryScenariosDidChange")
}

struct ScenariosView: View {
    @Environment(\.cloudKitClient) private var cloudKitClient

    @State private var scenarios: [TelemetryScenarioRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var togglingScenarioID: CKRecord.ID?

    private var groupedScenarios: [(name: String, scenarios: [TelemetryScenarioRecord])] {
        Self.groupScenarios(scenarios)
    }

    var body: some View {
        VStack(alignment: .leading) {
            if isLoading && scenarios.isEmpty {
                ProgressView("Loading scenarios...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if scenarios.isEmpty {
                ContentUnavailableView(
                    "No Scenarios",
                    systemImage: "tag",
                    description: Text("No scenario records found. Scenarios will appear when clients register them.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(groupedScenarios, id: \.name) { group in
                        ScenarioGroupView(
                            scenarioName: group.name,
                            scenarios: group.scenarios,
                            togglingScenarioID: togglingScenarioID,
                            toggleScenario: toggleScenario
                        )
                    }
                }
            }

            if let errorMessage {
                Text("Error: \(errorMessage)")
                    .foregroundStyle(.red)
                    .padding()
            }
        }
        .navigationTitle("Scenarios (\(scenarios.count))")
        .task {
            await setupSubscription()
            await fetchScenarios()
        }
        .onReceive(NotificationCenter.default.publisher(for: .telemetryScenariosDidChange)) { _ in
            Task { await fetchScenariosWithRetry() }
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
        let isAlreadyLoading = isLoading
        guard !isAlreadyLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            let fetched = try await cloudKitClient.fetchScenarios(forClient: nil)
            scenarios = fetched
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private func fetchScenariosWithRetry() async {
        guard let cloudKitClient else { return }
        let previousCount = scenarios.count

        for attempt in 1...3 {
            let delay = attempt == 1 ? 0.3 : 0.5
            try? await Task.sleep(for: .seconds(delay))

            do {
                let fetched = try await cloudKitClient.fetchScenarios(forClient: nil)
                if fetched.count != previousCount {
                    scenarios = fetched
                    return
                }
            } catch {
                print("[Viewer] fetchScenariosWithRetry attempt \(attempt) failed: \(error)")
            }
        }

        await fetchScenarios()
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
                clientId: scenario.clientId,
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

            await refreshScenarioStatus(for: recordID, expectedState: targetState)
        } catch {
            print("[Viewer] Failed to toggle scenario: \(error)")
            errorMessage = error.localizedDescription
        }

        togglingScenarioID = nil
    }

    private func refreshScenarioStatus(for id: CKRecord.ID, expectedState: Bool) async {
        guard let cloudKitClient else { return }

        for _ in 0..<4 {
            do {
                let fetched = try await cloudKitClient.fetchScenarios(forClient: nil)
                let didUpdate = fetched.first(where: { $0.recordID == id })?.isEnabled == expectedState

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

    private func setupSubscription() async {
        guard let cloudKitClient else { return }

        do {
            let subscriptionID = "TelemetryScenario-All"
            if let _ = try await cloudKitClient.fetchSubscription(id: subscriptionID) {
                print("[Viewer] TelemetryScenario subscription already exists")
                return
            }

            let newID = try await cloudKitClient.createScenarioSubscription()
            print("[Viewer] Created TelemetryScenario subscription: \(newID)")
        } catch {
            print("[Viewer] Failed to setup scenario subscription: \(error)")
        }
    }

    /// Groups scenarios by name and sorts groups alphabetically.
    static func groupScenarios(_ scenarios: [TelemetryScenarioRecord]) -> [(name: String, scenarios: [TelemetryScenarioRecord])] {
        Dictionary(grouping: scenarios, by: \.scenarioName)
            .sorted { $0.key < $1.key }
            .map { (name: $0.key, scenarios: $0.value) }
    }
}
