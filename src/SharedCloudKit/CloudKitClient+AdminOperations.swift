import CloudKit

extension CloudKitClient {

    /// Deletes all telemetry event records matching a given session ID.
    /// Returns the number of deleted records.
    public func deleteRecordsBySessionId(_ sessionId: String) async throws -> Int {
        let predicate = NSPredicate(
            format: "%K == %@",
            TelemetrySchema.Field.sessionId.rawValue,
            sessionId
        )
        return try await deleteRecordsByPredicate(
            predicate,
            recordType: TelemetrySchema.recordType
        )
    }

    /// Deletes a client record, all its scenario records, and all telemetry
    /// event records whose sessionId or scenario match the client.
    /// Returns a summary of how many records of each type were deleted.
    public func deleteRecordsByClientCode(_ clientCode: String) async throws -> (clients: Int, scenarios: Int, records: Int) {
        // 1. Delete the client record
        let clientPredicate = NSPredicate(
            format: "%K == %@",
            TelemetrySchema.ClientField.clientId.rawValue,
            clientCode
        )
        let deletedClients = try await deleteRecordsByPredicate(
            clientPredicate,
            recordType: TelemetrySchema.clientRecordType
        )

        // 2. Delete all scenario records for this client
        let scenarioPredicate = NSPredicate(
            format: "%K == %@",
            TelemetrySchema.ScenarioField.clientId.rawValue,
            clientCode
        )
        let deletedScenarios = try await deleteRecordsByPredicate(
            scenarioPredicate,
            recordType: TelemetrySchema.scenarioRecordType
        )

        // 3. Delete all telemetry event records for this client.
        //    Events don't have a direct clientId field, but they do have a
        //    sessionId that begins with the clientCode.
        let recordPredicate = NSPredicate(
            format: "%K BEGINSWITH %@",
            TelemetrySchema.Field.sessionId.rawValue,
            clientCode
        )
        let deletedRecords = try await deleteRecordsByPredicate(
            recordPredicate,
            recordType: TelemetrySchema.recordType
        )

        return (clients: deletedClients, scenarios: deletedScenarios, records: deletedRecords)
    }

    /// Deletes a single CloudKit record by its record name.
    /// The caller must specify which record type to look in.
    public func deleteRecordByRecordName(_ recordName: String, recordType: String) async throws {
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
}
