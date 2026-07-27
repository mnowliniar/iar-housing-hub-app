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
                }
        }
    }
}
