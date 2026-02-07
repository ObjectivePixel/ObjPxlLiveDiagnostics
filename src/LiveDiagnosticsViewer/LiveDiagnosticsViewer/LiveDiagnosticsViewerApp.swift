import AppIntents
import CloudKit
import ObjPxlLiveTelemetry
import SwiftUI
import UserNotifications

#if os(macOS)
import AppKit

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
        registerForPushNotifications()
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📱 [Viewer] Registered for remote notifications: \(token)")
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ [Viewer] Failed to register for remote notifications: \(error)")
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        print("📡 [Viewer] didReceiveRemoteNotification called")
        handleRemoteNotification(userInfo: userInfo)
    }

    // UNUserNotificationCenterDelegate - handles notifications when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("📡 [Viewer] userNotificationCenter willPresent called")
        handleRemoteNotification(userInfo: notification.request.content.userInfo as? [String: Any] ?? [:])
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("📡 [Viewer] userNotificationCenter didReceive called")
        handleRemoteNotification(userInfo: response.notification.request.content.userInfo as? [String: Any] ?? [:])
        completionHandler()
    }

    private func registerForPushNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            print("📡 [Viewer] Notification authorization: granted=\(granted), error=\(String(describing: error))")
        }
        NSApplication.shared.registerForRemoteNotifications()
        print("📡 [Viewer] Registered for remote notifications")
    }

    private func handleRemoteNotification(userInfo: [String: Any]) {
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
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .telemetryClientsDidChange, object: nil)
            }
        }
    }
}

#else
import UIKit

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        registerForPushNotifications()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        print("📱 [Viewer] Registered for remote notifications: \(token)")
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ [Viewer] Failed to register for remote notifications: \(error)")
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        print("📡 [Viewer] didReceiveRemoteNotification called")
        handleRemoteNotification(userInfo: userInfo as? [String: Any] ?? [:])
        completionHandler(.newData)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("📡 [Viewer] userNotificationCenter willPresent called")
        handleRemoteNotification(userInfo: notification.request.content.userInfo as? [String: Any] ?? [:])
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("📡 [Viewer] userNotificationCenter didReceive called")
        handleRemoteNotification(userInfo: response.notification.request.content.userInfo as? [String: Any] ?? [:])
        completionHandler()
    }

    private func registerForPushNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            print("📡 [Viewer] Notification authorization: granted=\(granted), error=\(String(describing: error))")
        }
        UIApplication.shared.registerForRemoteNotifications()
        print("📡 [Viewer] Registered for remote notifications")
    }

    private func handleRemoteNotification(userInfo: [String: Any]) {
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
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .telemetryClientsDidChange, object: nil)
            }
        }
    }
}
#endif

@main
struct LiveDiagnosticsViewerApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #else
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif

    private let cloudKitClient: CloudKitClient

    init() {
        cloudKitClient = CloudKitClient(containerIdentifier: "iCloud.objpxl.example.telemetry")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.cloudKitClient, cloudKitClient)
        }
    }
}
