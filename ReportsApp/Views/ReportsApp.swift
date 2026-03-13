//
//  ReportsApp.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 9/3/25.
//


import SwiftUI

@main
struct ReportsApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .environmentObject(auth)
                .onOpenURL { url in
                    auth.handleIncomingURL(url)
                }
        }
    }
}
