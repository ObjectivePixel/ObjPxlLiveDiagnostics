//  CloudkitClient.swift
//  RemindfullShared
//
//  Created by James Clarke on 12/5/25.
//

import CloudKit

public struct DebugInfo {
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
    func debugDatabaseInfo() async
    func detectEnvironment() async -> String
    func getDebugInfo() async -> DebugInfo
    func deleteAllRecords() async throws -> Int
}

public struct CloudKitClient: CloudKitClientProtocol {
    public let container: CKContainer
    public let database: CKDatabase
    public let identifier: String
    
    public static let cloudKitContainerIdentifierTelemetry = "iCloud.objectivepixel.prototype.remindful.telemetry"

    public init(containerIdentifier: String = cloudKitContainerIdentifierTelemetry) {
        let resolvedContainer = CKContainer(identifier: containerIdentifier)
        self.container = resolvedContainer
        self.database = resolvedContainer.publicCloudDatabase
        self.identifier = containerIdentifier
    }

    public func validateSchema() async -> Bool {
        do {
            try await TelemetrySchema.validateSchema(in: database)
            return true
        } catch {
            print("Telemetry schema validation failed: \(error)")
            return false
        }
    }

    public func save(records: [CKRecord]) async throws {
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

    public func fetchAllRecords() async throws -> [CKRecord] {
        let query = CKQuery(recordType: TelemetrySchema.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: TelemetrySchema.Field.eventTimestamp.rawValue, ascending: false)]

        print("🔍 Fetching records from database: \(database)")
        print("🔍 Record type: \(TelemetrySchema.recordType)")
        print("🔍 Container: \(container.containerIdentifier ?? "unknown")")
        
        return try await withCheckedThrowingContinuation { continuation in
            var allRecords: [CKRecord] = []
            
            let operation = CKQueryOperation(query: query)
            operation.resultsLimit = CKQueryOperation.maximumResults
            operation.qualityOfService = .userInitiated
            
            operation.recordMatchedBlock = { recordID, result in
                switch result {
                case .success(let record):
                    print("✅ Found record: \(record.recordID.recordName)")
                    allRecords.append(record)
                case .failure(let error):
                    print("❌ Failed to fetch record \(recordID): \(error)")
                }
            }
            
            operation.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    print("📊 Fetched \(allRecords.count) records in this batch")
                    if let cursor = cursor {
                        print("➡️ More records available, fetching next batch...")
                        // More records available, continue fetching
                        let nextOperation = CKQueryOperation(cursor: cursor)
                        nextOperation.resultsLimit = CKQueryOperation.maximumResults
                        nextOperation.qualityOfService = .userInitiated
                        
                        nextOperation.recordMatchedBlock = operation.recordMatchedBlock
                        nextOperation.queryResultBlock = operation.queryResultBlock
                        
                        self.database.add(nextOperation)
                    } else {
                        print("✅ Finished fetching. Total records: \(allRecords.count)")
                        continuation.resume(returning: allRecords)
                    }
                case .failure(let error):
                    print("❌ Query failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
            
            database.add(operation)
        }
    }

    // Debug method to check what databases we're working with
    public func debugDatabaseInfo() async {
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
        
        // Try to fetch a single record to see what happens
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
    
    public func getDebugInfo() async -> DebugInfo {
        let containerID = container.containerIdentifier ?? "unknown"
        
        #if DEBUG
        let buildType = "DEBUG"
        let environment = "🔧 Development"
        #else
        let buildType = "RELEASE"
        let environment = "🚀 Production"
        #endif
        
        // Try to fetch a single record to see what happens
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
    
    public func detectEnvironment() async -> String {
        let debugInfo = await getDebugInfo()
        return debugInfo.environment
    }
    
    public func deleteAllRecords() async throws -> Int {
        print("🗑️ Starting to delete all records...")
        
        // First, fetch all record IDs
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
            print("✅ No records to delete")
            return 0
        }
        
        print("🗑️ Found \(recordIDs.count) records to delete")
        
        // Delete records in batches (CloudKit has limits)
        let batchSize = 400 // CloudKit limit is 400 operations per request
        var totalDeleted = 0
        
        for i in stride(from: 0, to: recordIDs.count, by: batchSize) {
            let endIndex = min(i + batchSize, recordIDs.count)
            let batch = Array(recordIDs[i..<endIndex])
            
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: batch)
            
            let _: Void = try await withCheckedThrowingContinuation { continuation in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        print("✅ Deleted batch of \(batch.count) records")
                        continuation.resume()
                    case .failure(let error):
                        print("❌ Failed to delete batch: \(error)")
                        continuation.resume(throwing: error)
                    }
                }
                
                database.add(operation)
            }
            
            totalDeleted += batch.count
        }
        
        print("✅ Successfully deleted \(totalDeleted) records")
        return totalDeleted
    }
}
