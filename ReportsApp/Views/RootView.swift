//
//  RootView.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/12/26.
//


import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        Group {
            switch auth.state {
            case .launching:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Loading…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .signedOut:
                LoginView()

            case .signingIn:
                VStack(spacing: 16) {
                    ProgressView()
                    Text("Signing in…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            case .signedIn:
                ContentView()

            case .error(let message):
                VStack(spacing: 16) {
                    Text("Sign-in error")
                        .font(.headline)
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Try Again") {
                        auth.logout()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}
