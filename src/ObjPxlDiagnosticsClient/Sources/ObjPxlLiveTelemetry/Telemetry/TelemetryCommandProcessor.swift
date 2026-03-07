import CloudKit
import ObjPxlDiagnosticsShared
import Foundation

public actor TelemetryCommandProcessor {
    public typealias ActivateHandler = @Sendable () async throws -> Void
    public typealias EnableHandler = @Sendable () async throws -> Void
    public typealias DisableHandler = @Sendable () async throws -> Void
    public typealias DeleteEventsHandler = @Sendable () async throws -> Void
    public typealias SetScenarioLevelHandler = @Sendable (_ scenarioName: String, _ level: Int) async throws -> Void

    private let cloudKitClient: CloudKitClientProtocol
    private let clientId: String
    private let onActivate: ActivateHandler
    private let onEnable: EnableHandler
    private let onDisable: DisableHandler
    private let onDeleteEvents: DeleteEventsHandler
    private let onSetScenarioLevel: SetScenarioLevelHandler

    public init(
        cloudKitClient: CloudKitClientProtocol,
        clientId: String,
        onActivate: @escaping ActivateHandler,
        onEnable: @escaping EnableHandler,
        onDisable: @escaping DisableHandler,
        onDeleteEvents: @escaping DeleteEventsHandler,
        onSetScenarioLevel: @escaping SetScenarioLevelHandler
    ) {
        self.cloudKitClient = cloudKitClient
        self.clientId = clientId
        self.onActivate = onActivate
        self.onEnable = onEnable
        self.onDisable = onDisable
        self.onDeleteEvents = onDeleteEvents
        self.onSetScenarioLevel = onSetScenarioLevel
    }

    public func processCommands() async {
        print("📥 [CommandProcessor] Fetching pending commands for clientId: \(clientId)")
        do {
            let commands = try await cloudKitClient.fetchPendingCommands(for: clientId)
            print("📥 [CommandProcessor] Found \(commands.count) pending command(s)")
            for command in commands {
                print("📥 [CommandProcessor] Processing command: \(command.commandId) action=\(command.action.rawValue)")
                await processCommand(command)
            }
        } catch {
            print("❌ [CommandProcessor] Failed to fetch pending commands: \(error)")
        }
    }

    public func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async -> Bool {
        print("📲 [CommandProcessor] Received remote notification")
        print("📲 [CommandProcessor] userInfo: \(userInfo)")

        guard let notification = CKQueryNotification(fromRemoteNotificationDictionary: userInfo) else {
            print("⚠️ [CommandProcessor] Could not parse CKQueryNotification from userInfo")
            return false
        }

        print("📲 [CommandProcessor] CKNotification type: \(notification.notificationType.rawValue), subscriptionID: \(notification.subscriptionID ?? "nil")")

        guard notification.subscriptionID?.hasPrefix("TelemetryCommand-") == true else {
            print("⚠️ [CommandProcessor] Notification subscriptionID does not match TelemetryCommand prefix, ignoring")
            return false
        }

        // Extract the record ID from the notification to fetch directly
        // This avoids race conditions where the query can't find the record yet
        if let recordID = notification.recordID {
            print("📲 [CommandProcessor] Notification contains recordID: \(recordID.recordName)")
            await fetchAndProcessCommand(recordID: recordID)
        } else {
            print("⚠️ [CommandProcessor] No recordID in notification, falling back to query")
            await processCommands()
        }

        return true
    }

    private func fetchAndProcessCommand(recordID: CKRecord.ID, retryCount: Int = 0) async {
        let maxRetries = 3
        let retryDelayMs: UInt64 = 500

        print("📥 [CommandProcessor] Fetching command by recordID: \(recordID.recordName) (attempt \(retryCount + 1)/\(maxRetries + 1))")

        do {
            if let command = try await cloudKitClient.fetchCommand(recordID: recordID) {
                // Only process if still pending (avoid reprocessing)
                if command.status == .pending {
                    print("📥 [CommandProcessor] Found pending command: \(command.commandId) action=\(command.action.rawValue)")
                    await processCommand(command)
                } else {
                    print("📥 [CommandProcessor] Command \(command.commandId) already processed (status: \(command.status.rawValue))")
                }
            } else if retryCount < maxRetries {
                // Record not found yet - CloudKit propagation delay
                print("⏳ [CommandProcessor] Record not found yet, retrying in \(retryDelayMs)ms...")
                try? await Task.sleep(nanoseconds: retryDelayMs * 1_000_000)
                await fetchAndProcessCommand(recordID: recordID, retryCount: retryCount + 1)
            } else {
                print("⚠️ [CommandProcessor] Record not found after \(maxRetries + 1) attempts, falling back to query")
                await processCommands()
            }
        } catch {
            print("❌ [CommandProcessor] Failed to fetch command by recordID: \(error)")
            // Fall back to query-based approach
            await processCommands()
        }
    }

    private func processCommand(_ command: TelemetryCommandRecord) async {
        guard let recordID = command.recordID else {
            print("❌ [CommandProcessor] Command \(command.commandId) missing recordID, skipping")
            return
        }

        print("🔄 [CommandProcessor] Executing command \(command.commandId): \(command.action.rawValue)")
        do {
            switch command.action {
            case .activate:
                print("🔄 [CommandProcessor] Calling onActivate handler...")
                try await onActivate()
            case .enable:
                print("🔄 [CommandProcessor] Calling onEnable handler...")
                try await onEnable()
            case .disable:
                print("🔄 [CommandProcessor] Calling onDisable handler...")
                try await onDisable()
            case .deleteEvents:
                print("🔄 [CommandProcessor] Calling onDeleteEvents handler...")
                try await onDeleteEvents()
            case .setScenarioLevel:
                guard let scenarioName = command.scenarioName else {
                    print("❌ [CommandProcessor] setScenarioLevel command missing scenarioName")
                    let updatedCommand = try await cloudKitClient.updateCommandStatus(
                        recordID: recordID,
                        status: .failed,
                        executedAt: .now,
                        errorMessage: "Missing scenarioName for setScenarioLevel command"
                    )
                    print("⚠️ [CommandProcessor] Command \(updatedCommand.commandId) marked as failed (missing scenarioName)")
                    return
                }
                let level = command.diagnosticLevel ?? TelemetryScenarioRecord.levelOff
                print("🔄 [CommandProcessor] Calling onSetScenarioLevel handler for '\(scenarioName)' level=\(level)...")
                try await onSetScenarioLevel(scenarioName, level)
            }

            print("✅ [CommandProcessor] Command \(command.commandId) executed successfully, deleting...")
            try await cloudKitClient.deleteCommand(recordID: recordID)
            print("✅ [CommandProcessor] Command \(command.commandId) deleted")
        } catch {
            print("❌ [CommandProcessor] Command \(command.commandId) failed: \(error)")
            do {
                let updatedCommand = try await cloudKitClient.updateCommandStatus(
                    recordID: recordID,
                    status: .failed,
                    executedAt: .now,
                    errorMessage: error.localizedDescription
                )
                print("⚠️ [CommandProcessor] Command \(updatedCommand.commandId) marked as failed")
            } catch {
                print("❌ [CommandProcessor] Failed to update command status to failed: \(error)")
            }
        }
    }
}
