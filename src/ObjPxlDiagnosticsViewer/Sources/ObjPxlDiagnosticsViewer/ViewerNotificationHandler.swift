import CloudKit
import ObjPxlDiagnosticsShared
import Foundation

public extension Notification.Name {
    static let telemetryClientsDidChange = Notification.Name("telemetryClientsDidChange")
    static let telemetryScenariosDidChange = Notification.Name("telemetryScenariosDidChange")
}

public func handleViewerRemoteNotification(userInfo: [String: Any]) {
    print("📡 [Viewer] handleRemoteNotification: \(userInfo)")

    guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
        print("📡 [Viewer] Could not parse CKNotification")
        return
    }

    guard let queryNotification = notification as? CKQueryNotification else {
        print("📡 [Viewer] Not a CKQueryNotification, type: \(type(of: notification))")
        return
    }

    guard let subscriptionID = queryNotification.subscriptionID else {
        print("📡 [Viewer] No subscriptionID in notification")
        return
    }

    print("📡 [Viewer] Received notification for subscription: \(subscriptionID)")

    if subscriptionID.hasPrefix("TelemetryClient") {
        print("📡 [Viewer] TelemetryClient changed, posting notification")
        NotificationCenter.default.post(name: .telemetryClientsDidChange, object: nil)
    }

    if subscriptionID.hasPrefix("TelemetryScenario") {
        print("📡 [Viewer] TelemetryScenario changed, posting notification")
        NotificationCenter.default.post(name: .telemetryScenariosDidChange, object: nil)
    }
}
