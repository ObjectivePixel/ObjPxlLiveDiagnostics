import CloudKit
import SwiftUI

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
                            setScenarioLevel: setScenarioLevel
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
                clientId: scenario.clientId,
                action: .setScenarioLevel,
                scenarioName: scenario.scenarioName,
                diagnosticLevel: level
            )
            let savedCommand = try await cloudKitClient.createCommand(command)
            print("[Viewer] SetScenarioLevel command created: \(savedCommand.commandId)")

            // Do not directly update the scenario record — the client owns it
            // Wait for the change to propagate
            await refreshScenarioLevel(for: recordID, expectedLevel: level)
        } catch {
            print("[Viewer] Failed to set scenario level: \(error)")
            errorMessage = error.localizedDescription
        }

        togglingScenarioID = nil
    }

    private func refreshScenarioLevel(for id: CKRecord.ID, expectedLevel: Int) async {
        guard let cloudKitClient else { return }

        for _ in 0..<4 {
            do {
                let fetched = try await cloudKitClient.fetchScenarios(forClient: nil)
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

    /// Groups scenarios by name and sorts groups alphabetically.
    static func groupScenarios(_ scenarios: [TelemetryScenarioRecord]) -> [(name: String, scenarios: [TelemetryScenarioRecord])] {
        Dictionary(grouping: scenarios, by: \.scenarioName)
            .sorted { $0.key < $1.key }
            .map { (name: $0.key, scenarios: $0.value) }
    }
}
