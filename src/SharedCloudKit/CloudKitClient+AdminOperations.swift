import CloudKit

extension CloudKitClient {

    /// Deletes all telemetry event records matching a given session ID.
    /// Returns the number of deleted and failed records.
    public func deleteRecordsBySessionId(_ sessionId: String) async throws -> (deleted: Int, failed: Int) {
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
    /// Returns a summary of how many records of each type were deleted, plus total failures.
    public func deleteRecordsByClientCode(_ clientCode: String) async throws -> (clients: Int, scenarios: Int, records: Int, failed: Int) {
        // 1. Delete the client record
        let clientPredicate = NSPredicate(
            format: "%K == %@",
            TelemetrySchema.ClientField.clientId.rawValue,
            clientCode
        )
        let clientResult = try await deleteRecordsByPredicate(
            clientPredicate,
            recordType: TelemetrySchema.clientRecordType
        )

        // 2. Delete all scenario records for this client
        let scenarioPredicate = NSPredicate(
            format: "%K == %@",
            TelemetrySchema.ScenarioField.clientId.rawValue,
            clientCode
        )
        let scenarioResult = try await deleteRecordsByPredicate(
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
        let recordResult = try await deleteRecordsByPredicate(
            recordPredicate,
            recordType: TelemetrySchema.recordType
        )

        return (
            clients: clientResult.deleted,
            scenarios: scenarioResult.deleted,
            records: recordResult.deleted,
            failed: clientResult.failed + scenarioResult.failed + recordResult.failed
        )
    }

    /// Deletes all records across all record types for a given user record ID.
    /// Finds clients by the custom `userRecordId` field, then cascades to
    /// scenarios, commands, and events for each client.
    public func deleteRecordsByUserRecordId(
        _ userRecordId: String
    ) async throws -> (clients: Int, scenarios: Int, commands: Int, events: Int, failed: Int) {
        // 1. Find all clients belonging to this user
        let clientIds = try await fetchClientIds(forUserRecordId: userRecordId)

        // 2. Delete the client records
        let clientPredicate = NSPredicate(
            format: "%K == %@",
            TelemetrySchema.ClientField.userRecordId.rawValue,
            userRecordId
        )
        let clientResult = try await deleteRecordsByPredicate(
            clientPredicate,
            recordType: TelemetrySchema.clientRecordType
        )

        // 3. Delete scenarios, commands, and events for each client
        var totalScenarios = 0
        var totalCommands = 0
        var totalEvents = 0
        var totalFailed = clientResult.failed

        for clientId in clientIds {
            let scenarioPredicate = NSPredicate(
                format: "%K == %@",
                TelemetrySchema.ScenarioField.clientId.rawValue,
                clientId
            )
            let scenarioResult = try await deleteRecordsByPredicate(
                scenarioPredicate,
                recordType: TelemetrySchema.scenarioRecordType
            )
            totalScenarios += scenarioResult.deleted
            totalFailed += scenarioResult.failed

            let commandPredicate = NSPredicate(
                format: "%K == %@",
                TelemetrySchema.CommandField.clientId.rawValue,
                clientId
            )
            let commandResult = try await deleteRecordsByPredicate(
                commandPredicate,
                recordType: TelemetrySchema.commandRecordType
            )
            totalCommands += commandResult.deleted
            totalFailed += commandResult.failed

            let eventPredicate = NSPredicate(
                format: "%K BEGINSWITH %@",
                TelemetrySchema.Field.sessionId.rawValue,
                clientId
            )
            let eventResult = try await deleteRecordsByPredicate(
                eventPredicate,
                recordType: TelemetrySchema.recordType
            )
            totalEvents += eventResult.deleted
            totalFailed += eventResult.failed
        }

        return (
            clients: clientResult.deleted,
            scenarios: totalScenarios,
            commands: totalCommands,
            events: totalEvents,
            failed: totalFailed
        )
    }

    /// Deletes every record across all telemetry record types.
    /// Returns counts per type plus total failures.
    public func deleteAllTelemetryData() async throws -> (events: Int, clients: Int, scenarios: Int, commands: Int, failed: Int) {
        let allPredicate = NSPredicate(value: true)

        let eventsResult = try await deleteRecordsByPredicate(
            allPredicate,
            recordType: TelemetrySchema.recordType
        )
        let clientsResult = try await deleteRecordsByPredicate(
            allPredicate,
            recordType: TelemetrySchema.clientRecordType
        )
        let scenariosResult = try await deleteRecordsByPredicate(
            allPredicate,
            recordType: TelemetrySchema.scenarioRecordType
        )
        let commandsResult = try await deleteRecordsByPredicate(
            allPredicate,
            recordType: TelemetrySchema.commandRecordType
        )

        return (
            events: eventsResult.deleted,
            clients: clientsResult.deleted,
            scenarios: scenariosResult.deleted,
            commands: commandsResult.deleted,
            failed: eventsResult.failed + clientsResult.failed + scenariosResult.failed + commandsResult.failed
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
