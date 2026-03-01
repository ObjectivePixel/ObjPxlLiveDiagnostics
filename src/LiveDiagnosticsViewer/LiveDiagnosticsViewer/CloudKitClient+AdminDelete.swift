import CloudKit
import ObjPxlLiveTelemetry

extension CloudKitClient {

    /// Deletes all telemetry event records matching a given session ID.
    /// Returns the number of deleted records.
    func deleteRecordsBySessionId(_ sessionId: String) async throws -> Int {
        let predicate = NSPredicate(
            format: "%K == %@",
            TelemetrySchema.Field.sessionId.rawValue,
            sessionId
        )
        return try await queryAndDeleteRecords(
            recordType: TelemetrySchema.recordType,
            predicate: predicate
        )
    }

    /// Deletes a client record, all its scenario records, and all telemetry
    /// event records whose sessionId or scenario match the client.
    /// Returns a summary of how many records of each type were deleted.
    func deleteRecordsByClientCode(_ clientCode: String) async throws -> (clients: Int, scenarios: Int, records: Int) {
        // 1. Delete the client record
        let clientPredicate = NSPredicate(
            format: "%K == %@",
            TelemetrySchema.ClientField.clientId.rawValue,
            clientCode
        )
        let deletedClients = try await queryAndDeleteRecords(
            recordType: TelemetrySchema.clientRecordType,
            predicate: clientPredicate
        )

        // 2. Delete all scenario records for this client
        let scenarioPredicate = NSPredicate(
            format: "%K == %@",
            TelemetrySchema.ScenarioField.clientId.rawValue,
            clientCode
        )
        let deletedScenarios = try await queryAndDeleteRecords(
            recordType: TelemetrySchema.scenarioRecordType,
            predicate: scenarioPredicate
        )

        // 3. Delete all telemetry event records for this client.
        //    Events don't have a direct clientId field, but they do have a
        //    sessionId that begins with the clientCode.
        let recordPredicate = NSPredicate(
            format: "%K BEGINSWITH %@",
            TelemetrySchema.Field.sessionId.rawValue,
            clientCode
        )
        let deletedRecords = try await queryAndDeleteRecords(
            recordType: TelemetrySchema.recordType,
            predicate: recordPredicate
        )

        return (clients: deletedClients, scenarios: deletedScenarios, records: deletedRecords)
    }

    /// Deletes a single CloudKit record by its record name.
    /// The caller must specify which record type to look in.
    func deleteRecordByRecordName(_ recordName: String, recordType: String) async throws {
        let recordID = CKRecord.ID(recordName: recordName)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: [recordID])
            operation.qualityOfService = .utility

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

    // MARK: - Private helpers

    /// Queries for all record IDs matching the predicate and deletes them
    /// in batches of 400. Returns the total number of deleted records.
    private func queryAndDeleteRecords(
        recordType: String,
        predicate: NSPredicate
    ) async throws -> Int {
        let query = CKQuery(recordType: recordType, predicate: predicate)
        query.sortDescriptors = []

        var recordIDs: [CKRecord.ID] = []
        var queryCursor: CKQueryOperation.Cursor?

        repeat {
            let page: ([CKRecord.ID], CKQueryOperation.Cursor?) = try await withCheckedThrowingContinuation { continuation in
                let op: CKQueryOperation
                if let queryCursor {
                    op = CKQueryOperation(cursor: queryCursor)
                } else {
                    op = CKQueryOperation(query: query)
                }
                op.desiredKeys = []
                op.resultsLimit = CKQueryOperation.maximumResults
                op.qualityOfService = .utility

                var pageIDs: [CKRecord.ID] = []

                op.recordMatchedBlock = { recordID, result in
                    if case .success = result {
                        pageIDs.append(recordID)
                    }
                }

                op.queryResultBlock = { result in
                    switch result {
                    case .success(let nextCursor):
                        continuation.resume(returning: (pageIDs, nextCursor))
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                database.add(op)
            }

            recordIDs.append(contentsOf: page.0)
            queryCursor = page.1
        } while queryCursor != nil

        guard !recordIDs.isEmpty else { return 0 }

        let batchSize = 400
        var totalDeleted = 0

        for i in stride(from: 0, to: recordIDs.count, by: batchSize) {
            let endIndex = min(i + batchSize, recordIDs.count)
            let batch = Array(recordIDs[i..<endIndex])

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let operation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: batch)
                operation.qualityOfService = .utility

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
