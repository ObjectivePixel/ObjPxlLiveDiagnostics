import CloudKit

extension CloudKitClient {

    /// Fetches telemetry event records filtered by scenario and/or log level
    /// using a server-side CloudKit predicate. Both parameters are optional —
    /// pass `nil` to skip that filter dimension.
    public func fetchRecords(
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
    public func deleteFilteredRecords(
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

        let count = try await deleteRecordsByPredicate(
            predicate,
            recordType: TelemetrySchema.recordType
        )
        print("🗑️ Deleted \(count) filtered records")
        return count
    }
}
