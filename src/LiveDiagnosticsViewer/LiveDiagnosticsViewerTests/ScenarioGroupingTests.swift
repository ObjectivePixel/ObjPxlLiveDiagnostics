import CloudKit
import ObjPxlLiveTelemetry
import Testing

@testable import LiveDiagnosticsViewer

struct ScenarioGroupingTests {

    // MARK: - Grouping

    @Test func groupScenarios_emptyInput_returnsEmptyArray() {
        let result = ScenariosView.groupScenarios([])
        #expect(result.isEmpty)
    }

    @Test func groupScenarios_singleScenario_returnsSingleGroup() {
        let scenario = TelemetryScenarioRecord(
            recordID: CKRecord.ID(recordName: "record-1"),
            clientId: "client-1",
            scenarioName: "NetworkRequests",
            isEnabled: true
        )

        let result = ScenariosView.groupScenarios([scenario])

        #expect(result.count == 1)
        #expect(result[0].name == "NetworkRequests")
        #expect(result[0].scenarios.count == 1)
    }

    @Test func groupScenarios_multipleClientsForSameScenario_groupsTogether() {
        let scenarios = [
            TelemetryScenarioRecord(
                recordID: CKRecord.ID(recordName: "record-1"),
                clientId: "client-1",
                scenarioName: "DataSync",
                isEnabled: true
            ),
            TelemetryScenarioRecord(
                recordID: CKRecord.ID(recordName: "record-2"),
                clientId: "client-2",
                scenarioName: "DataSync",
                isEnabled: false
            ),
        ]

        let result = ScenariosView.groupScenarios(scenarios)

        #expect(result.count == 1)
        #expect(result[0].name == "DataSync")
        #expect(result[0].scenarios.count == 2)
    }

    @Test func groupScenarios_multipleDifferentScenarios_sortedAlphabetically() {
        let scenarios = [
            TelemetryScenarioRecord(
                recordID: CKRecord.ID(recordName: "record-1"),
                clientId: "client-1",
                scenarioName: "UserInteraction",
                isEnabled: true
            ),
            TelemetryScenarioRecord(
                recordID: CKRecord.ID(recordName: "record-2"),
                clientId: "client-1",
                scenarioName: "DataSync",
                isEnabled: false
            ),
            TelemetryScenarioRecord(
                recordID: CKRecord.ID(recordName: "record-3"),
                clientId: "client-1",
                scenarioName: "NetworkRequests",
                isEnabled: true
            ),
        ]

        let result = ScenariosView.groupScenarios(scenarios)

        #expect(result.count == 3)
        #expect(result[0].name == "DataSync")
        #expect(result[1].name == "NetworkRequests")
        #expect(result[2].name == "UserInteraction")
    }

    @Test func groupScenarios_mixedScenariosAndClients_groupsAndSortsCorrectly() {
        let scenarios = [
            TelemetryScenarioRecord(
                recordID: CKRecord.ID(recordName: "record-1"),
                clientId: "client-1",
                scenarioName: "Zebra",
                isEnabled: true
            ),
            TelemetryScenarioRecord(
                recordID: CKRecord.ID(recordName: "record-2"),
                clientId: "client-2",
                scenarioName: "Alpha",
                isEnabled: false
            ),
            TelemetryScenarioRecord(
                recordID: CKRecord.ID(recordName: "record-3"),
                clientId: "client-1",
                scenarioName: "Alpha",
                isEnabled: true
            ),
            TelemetryScenarioRecord(
                recordID: CKRecord.ID(recordName: "record-4"),
                clientId: "client-3",
                scenarioName: "Zebra",
                isEnabled: false
            ),
        ]

        let result = ScenariosView.groupScenarios(scenarios)

        #expect(result.count == 2)
        #expect(result[0].name == "Alpha")
        #expect(result[0].scenarios.count == 2)
        #expect(result[1].name == "Zebra")
        #expect(result[1].scenarios.count == 2)
    }
}
