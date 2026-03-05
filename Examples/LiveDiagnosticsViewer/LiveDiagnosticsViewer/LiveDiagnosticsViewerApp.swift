import CloudKit
import ObjPxlDiagnosticsViewer
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
        handleViewerRemoteNotification(userInfo: userInfo)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("📡 [Viewer] userNotificationCenter willPresent called")
        handleViewerRemoteNotification(userInfo: notification.request.content.userInfo as? [String: Any] ?? [:])
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("📡 [Viewer] userNotificationCenter didReceive called")
        handleViewerRemoteNotification(userInfo: response.notification.request.content.userInfo as? [String: Any] ?? [:])
        completionHandler()
    }

    private func registerForPushNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            print("📡 [Viewer] Notification authorization: granted=\(granted), error=\(String(describing: error))")
        }
        NSApplication.shared.registerForRemoteNotifications()
        print("📡 [Viewer] Registered for remote notifications")
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
        handleViewerRemoteNotification(userInfo: userInfo as? [String: Any] ?? [:])
        completionHandler(.newData)
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("📡 [Viewer] userNotificationCenter willPresent called")
        handleViewerRemoteNotification(userInfo: notification.request.content.userInfo as? [String: Any] ?? [:])
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("📡 [Viewer] userNotificationCenter didReceive called")
        handleViewerRemoteNotification(userInfo: response.notification.request.content.userInfo as? [String: Any] ?? [:])
        completionHandler()
    }

    private func registerForPushNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            print("📡 [Viewer] Notification authorization: granted=\(granted), error=\(String(describing: error))")
        }
        UIApplication.shared.registerForRemoteNotifications()
        print("📡 [Viewer] Registered for remote notifications")
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

    var body: some Scene {
        WindowGroup {
            DiagnosticsView(containerIdentifier: "iCloud.objpxl.example.telemetry")
        }
    }
}
