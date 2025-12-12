import CloudKit
import Foundation
import SwiftUI

public struct DebugInfo: Sendable {
    let containerID: String
    let buildType: String
    let environment: String
    let testQueryResults: Int
    let firstRecordID: String?
    let firstRecordFields: [String]
    let errorMessage: String?
}

public protocol CloudKitClientProtocol: Sendable {
    func validateSchema() async -> Bool
    func save(records: [CKRecord]) async throws
    func fetchAllRecords() async throws -> [CKRecord]
    func createTelemetryClient(clientId: String, created: Date, isEnabled: Bool) async throws -> CKRecord
    func updateTelemetryClient(recordID: CKRecord.ID, clientId: String?, created: Date?, isEnabled: Bool?) async throws -> CKRecord
    func deleteTelemetryClient(recordID: CKRecord.ID) async throws
    func fetchTelemetryClients(isEnabled: Bool?) async throws -> [CKRecord]
    func debugDatabaseInfo() async
    func detectEnvironment() async -> String
    func getDebugInfo() async -> DebugInfo
    func deleteAllRecords() async throws -> Int
}

struct CloudKitClient: CloudKitClientProtocol {
    let container: CKContainer
    let database: CKDatabase
    let identifier: String

    enum TelemetryClientError: Error, LocalizedError {
        case unexpectedRecordType(String)

        var errorDescription: String? {
            switch self {
            case .unexpectedRecordType(let recordType):
                return "Expected \(TelemetrySchema.clientRecordType) but found \(recordType)"
            }
        }
    }

    init(containerIdentifier: String = TelemetrySchema.cloudKitContainerIdentifierTelemetry) {
        let resolvedContainer = CKContainer(identifier: containerIdentifier)
        container = resolvedContainer
        database = resolvedContainer.publicCloudDatabase
        identifier = containerIdentifier
    }

    func validateSchema() async -> Bool {
        do {
            try await TelemetrySchema.validateSchema(in: database)
            return true
        } catch {
            print("Telemetry schema validation failed: \(error)")
            return false
        }
    }

    func save(records: [CKRecord]) async throws {
        let operation = CKModifyRecordsOperation(recordsToSave: records)
        operation.savePolicy = .allKeys

        return try await withCheckedThrowingContinuation { continuation in
            operation.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    func fetchAllRecords() async throws -> [CKRecord] {
        let query = CKQuery(recordType: TelemetrySchema.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: TelemetrySchema.Field.eventTimestamp.rawValue, ascending: false)]

        return try await withCheckedThrowingContinuation { continuation in
            var allRecords: [CKRecord] = []
            var didResume = false

            func resume(with result: Result<[CKRecord], Error>) {
                guard !didResume else { return }
                didResume = true
                switch result {
                case .success(let records):
                    continuation.resume(returning: records)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            func configure(operation: CKQueryOperation) {
                operation.resultsLimit = CKQueryOperation.maximumResults
                operation.qualityOfService = .userInitiated

                operation.recordMatchedBlock = { _, result in
                    if case let .success(record) = result {
                        allRecords.append(record)
                    }
                }

                operation.queryResultBlock = { result in
                    switch result {
                    case .success(let cursor):
                        if let cursor {
                            let nextOperation = CKQueryOperation(cursor: cursor)
                            configure(operation: nextOperation)
                            database.add(nextOperation)
                        } else {
                            resume(with: .success(allRecords))
                        }
                    case .failure(let error):
                        resume(with: .failure(error))
                    }
                }
            }

            let operation = CKQueryOperation(query: query)
            configure(operation: operation)
            database.add(operation)
        }
    }

    func createTelemetryClient(clientId: String, created: Date = .now, isEnabled: Bool) async throws -> CKRecord {
        let record = CKRecord(recordType: TelemetrySchema.clientRecordType)
        record[TelemetrySchema.ClientField.clientId.rawValue] = clientId as CKRecordValue
        record[TelemetrySchema.ClientField.created.rawValue] = created as CKRecordValue
        record[TelemetrySchema.ClientField.isEnabled.rawValue] = isEnabled as CKRecordValue

        return try await database.save(record)
    }

    func updateTelemetryClient(
        recordID: CKRecord.ID,
        clientId: String? = nil,
        created: Date? = nil,
        isEnabled: Bool? = nil
    ) async throws -> CKRecord {
        let record = try await database.record(for: recordID)

        guard record.recordType == TelemetrySchema.clientRecordType else {
            throw TelemetryClientError.unexpectedRecordType(record.recordType)
        }

        if let clientId {
            record[TelemetrySchema.ClientField.clientId.rawValue] = clientId as CKRecordValue
        }

        if let created {
            record[TelemetrySchema.ClientField.created.rawValue] = created as CKRecordValue
        }

        if let isEnabled {
            record[TelemetrySchema.ClientField.isEnabled.rawValue] = isEnabled as CKRecordValue
        }

        return try await database.save(record)
    }

    func deleteTelemetryClient(recordID: CKRecord.ID) async throws {
        _ = try await database.deleteRecord(withID: recordID)
    }

    func fetchTelemetryClients(isEnabled: Bool? = nil) async throws -> [CKRecord] {
        let predicate: NSPredicate
        if let isEnabled {
            predicate = NSPredicate(
                format: "%K == %@",
                TelemetrySchema.ClientField.isEnabled.rawValue,
                NSNumber(value: isEnabled)
            )
        } else {
            predicate = NSPredicate(value: true)
        }

        let query = CKQuery(recordType: TelemetrySchema.clientRecordType, predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: TelemetrySchema.ClientField.created.rawValue, ascending: false)]

        return try await withCheckedThrowingContinuation { continuation in
            var allRecords: [CKRecord] = []
            var didResume = false

            func resume(with result: Result<[CKRecord], Error>) {
                guard !didResume else { return }
                didResume = true
                switch result {
                case .success(let records):
                    continuation.resume(returning: records)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            func configure(operation: CKQueryOperation) {
                operation.resultsLimit = CKQueryOperation.maximumResults
                operation.qualityOfService = .userInitiated

                operation.recordMatchedBlock = { _, result in
                    if case let .success(record) = result {
                        allRecords.append(record)
                    }
                }

                operation.queryResultBlock = { result in
                    switch result {
                    case .success(let cursor):
                        if let cursor {
                            let nextOperation = CKQueryOperation(cursor: cursor)
                            configure(operation: nextOperation)
                            database.add(nextOperation)
                        } else {
                            resume(with: .success(allRecords))
                        }
                    case .failure(let error):
                        resume(with: .failure(error))
                    }
                }
            }

            let operation = CKQueryOperation(query: query)
            configure(operation: operation)
            database.add(operation)
        }
    }

    func debugDatabaseInfo() async {
        print("🔍 Database Debug Info:")
        print("   Container ID: \(container.containerIdentifier ?? "unknown")")
        print("   Database: \(database)")
        print("   Database scope: Public")

        #if DEBUG
        print("   Build Type: DEBUG")
        print("   ⚠️ Debug builds typically use Development environment")
        #else
        print("   Build Type: RELEASE")
        print("   🚀 Release builds use Production environment")
        #endif

        let query = CKQuery(recordType: TelemetrySchema.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = []

        do {
            let result = try await database.records(matching: query, resultsLimit: 1)
            print("   Test query found \(result.matchResults.count) results")
            if let first = result.matchResults.first {
                switch first.1 {
                case .success(let record):
                    print("   First record ID: \(record.recordID.recordName)")
                    print("   First record fields: \(record.allKeys())")
                case .failure(let error):
                    print("   First record error: \(error)")
                }
            }
        } catch {
            print("   Test query failed: \(error)")
        }
    }

    func getDebugInfo() async -> DebugInfo {
        let containerID = container.containerIdentifier ?? "unknown"

        #if DEBUG
        let buildType = "DEBUG"
        let environment = "🔧 Development"
        #else
        let buildType = "RELEASE"
        let environment = "🚀 Production"
        #endif

        let query = CKQuery(recordType: TelemetrySchema.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = []

        do {
            let result = try await database.records(matching: query, resultsLimit: 1)
            let testQueryResults = result.matchResults.count

            if let first = result.matchResults.first {
                switch first.1 {
                case .success(let record):
                    return DebugInfo(
                        containerID: containerID,
                        buildType: buildType,
                        environment: environment,
                        testQueryResults: testQueryResults,
                        firstRecordID: record.recordID.recordName,
                        firstRecordFields: record.allKeys().sorted(),
                        errorMessage: nil
                    )
                case .failure(let error):
                    return DebugInfo(
                        containerID: containerID,
                        buildType: buildType,
                        environment: environment,
                        testQueryResults: 0,
                        firstRecordID: nil,
                        firstRecordFields: [],
                        errorMessage: "First record error: \(error.localizedDescription)"
                    )
                }
            } else {
                return DebugInfo(
                    containerID: containerID,
                    buildType: buildType,
                    environment: environment,
                    testQueryResults: testQueryResults,
                    firstRecordID: nil,
                    firstRecordFields: [],
                    errorMessage: nil
                )
            }
        } catch {
            return DebugInfo(
                containerID: containerID,
                buildType: buildType,
                environment: environment,
                testQueryResults: 0,
                firstRecordID: nil,
                firstRecordFields: [],
                errorMessage: "Test query failed: \(error.localizedDescription)"
            )
        }
    }

    func detectEnvironment() async -> String {
        let debugInfo = await getDebugInfo()
        return debugInfo.environment
    }

    func deleteAllRecords() async throws -> Int {
        let query = CKQuery(recordType: TelemetrySchema.recordType, predicate: NSPredicate(value: true))
        let result = try await database.records(matching: query)

        let recordIDs = result.matchResults.compactMap { _, result in
            switch result {
            case .success(let record):
                return record.recordID
            case .failure:
                return nil
            }
        }

        guard !recordIDs.isEmpty else {
            return 0
        }

        let batchSize = 400
        var totalDeleted = 0

        for i in stride(from: 0, to: recordIDs.count, by: batchSize) {
            let endIndex = min(i + batchSize, recordIDs.count)
            let batch = Array(recordIDs[i..<endIndex])

            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: batch)

            let _: Void = try await withCheckedThrowingContinuation { continuation in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                database.add(operation)
            }

            totalDeleted += batch.count
        }

        return totalDeleted
    }
}

private struct CloudKitClientKey: EnvironmentKey {
    static let defaultValue = CloudKitClient()
}

extension EnvironmentValues {
    var cloudKitClient: CloudKitClient {
        get { self[CloudKitClientKey.self] }
        set { self[CloudKitClientKey.self] = newValue }
    }
}
