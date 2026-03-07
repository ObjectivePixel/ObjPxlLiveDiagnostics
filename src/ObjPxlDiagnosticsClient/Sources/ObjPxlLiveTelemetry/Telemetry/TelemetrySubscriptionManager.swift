import CloudKit
import ObjPxlDiagnosticsShared
import Foundation

public protocol TelemetrySubscriptionManaging: Sendable {
    var currentSubscriptionID: CKSubscription.ID? { get async }
    func registerSubscription(for clientId: String) async throws
    func unregisterSubscription() async throws
}

public actor TelemetrySubscriptionManager: TelemetrySubscriptionManaging {
    private let cloudKitClient: CloudKitClientProtocol
    private var _currentSubscriptionID: CKSubscription.ID?
    private var currentClientId: String?

    public var currentSubscriptionID: CKSubscription.ID? {
        _currentSubscriptionID
    }

    public init(cloudKitClient: CloudKitClientProtocol) {
        self.cloudKitClient = cloudKitClient
    }

    public func registerSubscription(for clientId: String) async throws {
        print("📡 [SubscriptionManager] registerSubscription called for clientId: \(clientId)")

        // If already registered for this client, skip
        if currentClientId == clientId, _currentSubscriptionID != nil {
            print("📡 [SubscriptionManager] Already registered for this client, skipping")
            return
        }

        // Unregister any existing subscription first
        if let existingID = _currentSubscriptionID {
            print("📡 [SubscriptionManager] Removing existing subscription: \(existingID)")
            try? await cloudKitClient.removeCommandSubscription(existingID)
            _currentSubscriptionID = nil
            currentClientId = nil
        }

        // Check if subscription already exists on server
        print("📡 [SubscriptionManager] Checking for existing subscription on server...")
        if let existingSubscriptionID = try await cloudKitClient.fetchCommandSubscription(for: clientId) {
            print("📡 [SubscriptionManager] Found existing subscription: \(existingSubscriptionID)")
            _currentSubscriptionID = existingSubscriptionID
            currentClientId = clientId
            return
        }

        // Create new subscription
        print("📡 [SubscriptionManager] Creating new subscription...")
        let subscriptionID = try await cloudKitClient.createCommandSubscription(for: clientId)
        print("✅ [SubscriptionManager] Subscription created: \(subscriptionID)")
        _currentSubscriptionID = subscriptionID
        currentClientId = clientId
    }

    public func unregisterSubscription() async throws {
        guard let subscriptionID = _currentSubscriptionID else {
            return
        }

        try await cloudKitClient.removeCommandSubscription(subscriptionID)
        _currentSubscriptionID = nil
        currentClientId = nil
    }
}
