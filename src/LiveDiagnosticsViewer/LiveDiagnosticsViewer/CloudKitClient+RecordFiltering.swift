import CloudKit
import ObjPxlLiveTelemetry

extension CloudKitClient {

    /// Fetches telemetry event records filtered by scenario and/or log level
    /// using a server-side CloudKit predicate. Both parameters are optional —
    /// pass `nil` to skip that filter dimension.
    func fetchRecords(
        scenario: String?,
        logLevel: Int?,
        sessionId: String?,
        limit: Int,
        cursor: CKQueryOperation.Cursor?
    ) async throws -> ([CKRecord], CKQueryOperation.Cursor?) {
        let operation: CKQueryOperation

        if let cursor {
            // Predicate is baked into the cursor — just paginate
            operation = CKQueryOperation(cursor: cursor)
        } else {
            var subpredicates: [NSPredicate] = []

            if let scenario {
                subpredicates.append(NSPredicate(
                    format: "%K == %@",
                    TelemetrySchema.Field.scenario.rawValue,
                    scenario
                ))
            }

            if let logLevel {
                subpredicates.append(NSPredicate(
                    format: "%K == %d",
                    TelemetrySchema.Field.logLevel.rawValue,
                    logLevel
                ))
            }

            if let sessionId {
                subpredicates.append(NSPredicate(
                    format: "%K == %@",
                    TelemetrySchema.Field.sessionId.rawValue,
                    sessionId
                ))
            }

            let predicate = subpredicates.isEmpty
                ? NSPredicate(value: true)
                : NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)

            let query = CKQuery(
                recordType: TelemetrySchema.recordType,
                predicate: predicate
            )
            query.sortDescriptors = [
                NSSortDescriptor(
                    key: TelemetrySchema.Field.eventTimestamp.rawValue,
                    ascending: false
                )
            ]
            operation = CKQueryOperation(query: query)
        }

        operation.resultsLimit = limit
        operation.qualityOfService = .userInitiated

        return try await withCheckedThrowingContinuation { continuation in
            var pageRecords: [CKRecord] = []

            operation.recordMatchedBlock = { _, result in
                if case .success(let record) = result {
                    pageRecords.append(record)
                }
            }

            operation.queryResultBlock = { result in
                switch result {
                case .success(let cursor):
                    continuation.resume(returning: (pageRecords, cursor))
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            database.add(operation)
        }
    }

    /// Deletes telemetry event records matching the given filters.
    /// If all filter parameters are nil, deletes all records.
    /// Returns the number of records deleted.
    func deleteFilteredRecords(
        scenario: String?,
        logLevel: Int?,
        sessionId: String?
    ) async throws -> Int {
        var subpredicates: [NSPredicate] = []

        if let scenario {
            subpredicates.append(NSPredicate(
                format: "%K == %@",
                TelemetrySchema.Field.scenario.rawValue,
                scenario
            ))
        }

        if let logLevel {
            subpredicates.append(NSPredicate(
                format: "%K == %d",
                TelemetrySchema.Field.logLevel.rawValue,
                logLevel
            ))
        }

        if let sessionId {
            subpredicates.append(NSPredicate(
                format: "%K == %@",
                TelemetrySchema.Field.sessionId.rawValue,
                sessionId
            ))
        }

        let predicate = subpredicates.isEmpty
            ? NSPredicate(value: true)
            : NSCompoundPredicate(andPredicateWithSubpredicates: subpredicates)

        let query = CKQuery(
            recordType: TelemetrySchema.recordType,
            predicate: predicate
        )
        query.sortDescriptors = []

        // Collect all matching record IDs via pagination
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

        // Batch delete in groups of 400
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

        print("🗑️ Deleted \(totalDeleted) filtered records")
        return totalDeleted
    }
}
