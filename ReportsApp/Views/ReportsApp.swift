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
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let destination = response.notification.request.content.userInfo["destination"] as? String
        if destination == "digest" {
            DispatchQueue.main.async {
                self.appState?.showDigest = true
                self.appState?.selectedTab = 1
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
