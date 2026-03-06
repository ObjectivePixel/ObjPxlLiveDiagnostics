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

    /// Deletes all records across all record types for a given user record ID.
    /// Finds clients by the custom `userRecordId` field, then cascades to
    /// scenarios, commands, and events for each client.
    public func deleteRecordsByUserRecordId(
        _ userRecordId: String
    ) async throws -> (clients: Int, scenarios: Int, commands: Int, events: Int) {
        // 1. Find all clients belonging to this user
        let clientIds = try await fetchClientIds(forUserRecordId: userRecordId)

        // 2. Delete the client records
        let clientPredicate = NSPredicate(
            format: "%K == %@",
            TelemetrySchema.ClientField.userRecordId.rawValue,
            userRecordId
        )
        let deletedClients = try await deleteRecordsByPredicate(
            clientPredicate,
            recordType: TelemetrySchema.clientRecordType
        )

        // 3. Delete scenarios, commands, and events for each client
        var totalScenarios = 0
        var totalCommands = 0
        var totalEvents = 0

        for clientId in clientIds {
            let scenarioPredicate = NSPredicate(
                format: "%K == %@",
                TelemetrySchema.ScenarioField.clientId.rawValue,
                clientId
            )
            totalScenarios += try await deleteRecordsByPredicate(
                scenarioPredicate,
                recordType: TelemetrySchema.scenarioRecordType
            )

            let commandPredicate = NSPredicate(
                format: "%K == %@",
                TelemetrySchema.CommandField.clientId.rawValue,
                clientId
            )
            totalCommands += try await deleteRecordsByPredicate(
                commandPredicate,
                recordType: TelemetrySchema.commandRecordType
            )

            let eventPredicate = NSPredicate(
                format: "%K BEGINSWITH %@",
                TelemetrySchema.Field.sessionId.rawValue,
                clientId
            )
            totalEvents += try await deleteRecordsByPredicate(
                eventPredicate,
                recordType: TelemetrySchema.recordType
            )
        }

        return (
            clients: deletedClients,
            scenarios: totalScenarios,
            commands: totalCommands,
            events: totalEvents
        )
    }

    /// Returns the client IDs for all TelemetryClient records with the given `userRecordId`.
    private func fetchClientIds(forUserRecordId userRecordId: String) async throws -> [String] {
        let predicate = NSPredicate(
            format: "%K == %@",
            TelemetrySchema.ClientField.userRecordId.rawValue,
            userRecordId
        )
        let query = CKQuery(recordType: TelemetrySchema.clientRecordType, predicate: predicate)
        query.sortDescriptors = []

        let (results, _) = try await database.records(
            matching: query,
            desiredKeys: [TelemetrySchema.ClientField.clientId.rawValue]
        )

        return results.compactMap { _, result in
            guard let record = try? result.get() else { return nil }
            return record[TelemetrySchema.ClientField.clientId.rawValue] as? String
        }
    }
}
