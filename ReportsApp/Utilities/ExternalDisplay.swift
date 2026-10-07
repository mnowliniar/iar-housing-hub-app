//
//  ExternalDisplay.swift
//  ReportsApp
//
//  The second screen: an Apple TV over AirPlay, or a projector on a cable.
//  iOS hands the app a window scene for it; nothing is drawn there until a
//  presentation starts, so mirroring keeps working the rest of the time.
//

import SwiftUI
import UIKit

@MainActor
final class ExternalDisplay: ObservableObject {
    static let shared = ExternalDisplay()

    @Published private(set) var isConnected = false

    private var scene: UIWindowScene?
    private var window: UIWindow?

    /// The screen showed up (or was there when the app launched).
    func attach(_ scene: UIWindowScene) {
        self.scene = scene
        isConnected = true
        if PackPresentation.shared.isPresenting { show() }
    }

    func detach(_ scene: UIScene) {
        guard scene === self.scene else { return }
        hide()
        self.scene = nil
        isConnected = false
    }

    /// Puts the stage on the big screen. The window replaces the mirror
    /// image for as long as it exists.
    func show() {
        guard let scene, window == nil else { return }
        let w = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: ExternalStageView())
        host.view.backgroundColor = .black
        w.rootViewController = host
        w.isHidden = false
        window = w
    }

    /// Takes the stage down; the screen goes back to mirroring the iPad.
    func hide() {
        window?.isHidden = true
        window = nil
    }
}

/// The delegate iOS gets for the external display's scene. UIResponder
/// keeps it on the main actor.
final class ExternalSceneDelegate: UIResponder, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        ExternalDisplay.shared.attach(windowScene)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ExternalDisplay.shared.detach(scene)
    }
}

/// What the big screen shows: the current slide, or a quiet card between
/// presentations.
struct ExternalStageView: View {
    @ObservedObject private var presentation = PackPresentation.shared

    var body: some View {
        ZStack {
            Color.black
            if let deck = presentation.deck, let slide = presentation.slide {
                PackSlideView(slide: slide, deck: deck, images: presentation.images)
            } else {
                PackSlideView(slide: .title, deck: .empty, images: [:])
            }
        }
        .ignoresSafeArea()
    }
}
