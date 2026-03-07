import CloudKit
import ObjPxlDiagnosticsShared
import Testing

@testable import ObjPxlDiagnosticsViewer

struct ScenarioFilterTests {

    /// Creates a CKRecord with the given scenario field for testing.
    private func makeTelemetryRecord(eventName: String, scenario: String? = nil) -> TelemetryRecord {
        let record = CKRecord(recordType: TelemetrySchema.recordType)
        record[TelemetrySchema.Field.eventName.rawValue] = eventName
        record[TelemetrySchema.Field.eventTimestamp.rawValue] = Date()
        record[TelemetrySchema.Field.deviceType.rawValue] = "iPhone"
        record[TelemetrySchema.Field.deviceName.rawValue] = "Test Device"
        record[TelemetrySchema.Field.deviceModel.rawValue] = "iPhone15,2"
        record[TelemetrySchema.Field.osVersion.rawValue] = "26.0"
        record[TelemetrySchema.Field.appVersion.rawValue] = "1.0"
        record[TelemetrySchema.Field.threadId.rawValue] = "main"
        record[TelemetrySchema.Field.property1.rawValue] = "test"
        if let scenario {
            record[TelemetrySchema.Field.scenario.rawValue] = scenario
        }
        return TelemetryRecord(record)
    }

    // MARK: - Filtering

    @Test func filterRecords_nilFilter_returnsAllRecords() {
        let records = [
            makeTelemetryRecord(eventName: "Event1", scenario: "NetworkRequests"),
            makeTelemetryRecord(eventName: "Event2", scenario: "DataSync"),
            makeTelemetryRecord(eventName: "Event3"),
        ]

        let result = RecordsListView.filterRecords(records, byScenario: nil)
        #expect(result.count == 3)
    }

    @Test func filterRecords_specificScenario_returnsOnlyMatchingRecords() {
        let records = [
            makeTelemetryRecord(eventName: "Event1", scenario: "NetworkRequests"),
            makeTelemetryRecord(eventName: "Event2", scenario: "DataSync"),
            makeTelemetryRecord(eventName: "Event3", scenario: "NetworkRequests"),
            makeTelemetryRecord(eventName: "Event4"),
        ]

        let result = RecordsListView.filterRecords(records, byScenario: "NetworkRequests")

        #expect(result.count == 2)
        #expect(result.allSatisfy { $0.scenario == "NetworkRequests" })
    }

    @Test func filterRecords_nonexistentScenario_returnsEmptyArray() {
        let records = [
            makeTelemetryRecord(eventName: "Event1", scenario: "NetworkRequests"),
            makeTelemetryRecord(eventName: "Event2", scenario: "DataSync"),
        ]

        let result = RecordsListView.filterRecords(records, byScenario: "NonExistent")
        #expect(result.isEmpty)
    }

    @Test func filterRecords_emptyRecords_returnsEmptyArray() {
        let result = RecordsListView.filterRecords([], byScenario: "NetworkRequests")
        #expect(result.isEmpty)
    }

    @Test func filterRecords_recordsWithNoScenario_notReturnedForSpecificFilter() {
        let records = [
            makeTelemetryRecord(eventName: "Event1"),
            makeTelemetryRecord(eventName: "Event2"),
        ]

        let result = RecordsListView.filterRecords(records, byScenario: "SomeScenario")
        #expect(result.isEmpty)
    }

    @Test func filterRecords_caseSensitiveMatching() {
        let records = [
            makeTelemetryRecord(eventName: "Event1", scenario: "NetworkRequests"),
            makeTelemetryRecord(eventName: "Event2", scenario: "networkrequests"),
        ]

        let result = RecordsListView.filterRecords(records, byScenario: "NetworkRequests")

        #expect(result.count == 1)
        #expect(result[0].eventName == "Event1")
    }
}
