import ObjPxlLiveTelemetry

extension CloudKitClientProtocol {
    func deleteAllTelemetryClients() async throws -> Int {
        let clients = try await fetchTelemetryClients(clientId: nil, isEnabled: nil)
        var deletedCount = 0

        for client in clients {
            guard let recordID = client.recordID else {
                throw TelemetryClientRecord.Error.missingRecordID
            }
            try await deleteTelemetryClient(recordID: recordID)
            deletedCount += 1
        }

        return deletedCount
    }
}
