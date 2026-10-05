//
//  ReportsApp.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 9/3/25.
//


import SwiftUI
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    var appState: AppState?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        PushRegistration.registerIfAuthorized()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistration.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        debugLog("[Push] registration failed:", error)
    }

    /// A notification that lands while the app is open still shows.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        let destination = info["destination"] as? String
        DispatchQueue.main.async {
            switch destination {
            case "digest":
                self.appState?.showDigest = true
                self.appState?.selectedTab = 1
            case "insight":
                // The Thursday tap: this week's top insight for the member's market.
                let geo = (info["geo_id"] as? Int).map(String.init) ?? (info["geo_id"] as? String) ?? "18"
                if let url = URL(string: "iarhousinghub://market/\(geo)/insights") {
                    self.appState?.handleDeepLink(url)
                }
            default:
                break
            }
        }
        completionHandler()
    }
}

@main
struct ReportsApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()
    @StateObject private var auth = AuthManager()
    @Environment(\.scenePhase) private var scenePhase
    @State private var wentToBackgroundAt: Date?

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(auth)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .onOpenURL { url in
                    auth.handleIncomingURL(url)
                    appState.handleDeepLink(url)
                }
                .onAppear {
                    appDelegate.appState = appState
                    EventTracker.fire(.appOpen, oncePerSession: true)
                    Task.detached(priority: .background) { HubCache.prune() }
                }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .background:
                        wentToBackgroundAt = Date()
                    case .active:
                        // Back after a while: ask the Hub what moved, and
                        // rebuild Home so each section shows then checks.
                        guard let away = wentToBackgroundAt else { return }
                        wentToBackgroundAt = nil
                        if Date().timeIntervalSince(away) > 20 * 60 {
                            Task {
                                await Freshness.shared.invalidate()
                                appState.reloadStamp += 1
                            }
                        }
                    default:
                        break
                    }
                }
        }
    }
}
