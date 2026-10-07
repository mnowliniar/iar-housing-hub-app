//
//  PackPresentation.swift
//  ReportsApp
//
//  The Market Pack as a presentation: a title, one slide per card with the
//  number and the caption beside it, and a closing slide with the month in
//  three numbers. On a second screen the slides go there and the script
//  stays on the iPad; with no second screen the iPad is the screen.
//

import SwiftUI
import UIKit

// MARK: - The deck

enum PackSlide: Identifiable {
    case title
    case card(PackAsset, PackStat?)
    case closing([PackStat], PackAsset?)

    var id: String {
        switch self {
        case .title: return "title"
        case .card(let asset, _): return "card-\(asset.id)"
        case .closing: return "closing"
        }
    }

    var name: String {
        switch self {
        case .title: return "Title"
        case .card(let asset, _): return asset.title
        case .closing: return "The month in numbers"
        }
    }

    /// The line to say with this slide: the talking point, else the caption.
    var caption: String? {
        if case .card(let asset, _) = self { return asset.talkingPoint ?? asset.caption }
        return nil
    }
}

struct PackDeck {
    let geoLabel: String
    let monthLabel: String
    let script: String
    let slides: [PackSlide]

    static let empty = PackDeck(geoLabel: "Housing Hub", monthLabel: "", script: "", slides: [.title])

    /// Title, the square cards that have rendered, then the recap. The
    /// Story card closes the deck when it exists.
    static func make(issue: PackIssue, assets: [PackAsset], label: String) -> PackDeck {
        var slides: [PackSlide] = [.title]
        var story: PackAsset?
        for asset in assets where asset.ready && asset.url != nil {
            switch asset.kind {
            case .square(_, let vizID):
                slides.append(.card(asset, issue.stat(forViz: vizID)))
            case .story:
                story = asset
            case .reel:
                break
            }
        }
        let stats = (issue.stats ?? []).filter { !($0.displayValue ?? "").isEmpty }
        slides.append(.closing(Array(stats.prefix(3)), story))
        return PackDeck(geoLabel: issue.geoLabel ?? label,
                        monthLabel: issue.monthLabel ?? "",
                        script: issue.script ?? "",
                        slides: slides)
    }
}

// MARK: - The state both screens watch

@MainActor
final class PackPresentation: ObservableObject {
    static let shared = PackPresentation()

    @Published private(set) var deck: PackDeck?
    @Published var index = 0
    @Published private(set) var images: [String: UIImage] = [:]

    private var fetchTask: Task<Void, Never>?

    var isPresenting: Bool { deck != nil }

    var slide: PackSlide? {
        guard let deck, deck.slides.indices.contains(index) else { return nil }
        return deck.slides[index]
    }

    var nextSlide: PackSlide? {
        guard let deck, deck.slides.indices.contains(index + 1) else { return nil }
        return deck.slides[index + 1]
    }

    func start(_ deck: PackDeck) {
        self.deck = deck
        index = 0
        images = [:]
        ExternalDisplay.shared.show()
        prefetch(deck)
    }

    func end() {
        fetchTask?.cancel()
        deck = nil
        images = [:]
        index = 0
        ExternalDisplay.shared.hide()
    }

    func next() {
        guard let deck, index < deck.slides.count - 1 else { return }
        index += 1
    }

    func previous() {
        guard index > 0 else { return }
        index -= 1
    }

    /// Every card up front, so a slide never waits on the network while
    /// someone is watching.
    private func prefetch(_ deck: PackDeck) {
        let assets: [PackAsset] = deck.slides.flatMap { slide -> [PackAsset] in
            switch slide {
            case .card(let asset, _): return [asset]
            case .closing(_, let story): return story.map { [$0] } ?? []
            case .title: return []
            }
        }
        fetchTask = Task { [weak self] in
            await withTaskGroup(of: (String, UIImage?).self) { group in
                for asset in assets {
                    guard let url = asset.url else { continue }
                    group.addTask {
                        let reply = try? await URLSession.shared.data(from: url)
                        return (asset.id, reply.flatMap { UIImage(data: $0.0) })
                    }
                }
                for await (id, image) in group {
                    guard let image, let self, !Task.isCancelled else { continue }
                    self.images[id] = image
                }
            }
        }
    }
}

// MARK: - One slide

/// Drawn at 1920 × 1080 and scaled to whatever screen it lands on.
struct PackSlideView: View {
    let slide: PackSlide
    let deck: PackDeck
    let images: [String: UIImage]

    private let canvas = CGSize(width: 1920, height: 1080)

    var body: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / canvas.width, geo.size.height / canvas.height)
            ZStack {
                background
                content
                    .foregroundStyle(.white)
            }
            .frame(width: canvas.width, height: canvas.height)
            .scaleEffect(scale)
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .clipped()
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(red: 0.02, green: 0.16, blue: 0.19), Color(red: 0.0, green: 0.40, blue: 0.44)],
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    @ViewBuilder
    private var content: some View {
        switch slide {
        case .title:
            titleSlide
        case .card(let asset, let stat):
            cardSlide(asset: asset, stat: stat)
        case .closing(let stats, let story):
            closingSlide(stats: stats, story: story)
        }
    }

    private var titleSlide: some View {
        VStack(alignment: .leading, spacing: 0) {
            eyebrow("IAR Housing Hub" + (deck.monthLabel.isEmpty ? "" : " · \(deck.monthLabel)"))
            Spacer()
            Text(deck.geoLabel)
                .font(.system(size: 150, weight: .bold))
                .lineLimit(2)
                .minimumScaleFactor(0.5)
            Text("What the housing market did last month")
                .font(.system(size: 54, weight: .regular))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.top, 20)
            Spacer()
            footer
        }
        .padding(110)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    /// The card carries the number and its sparkline already; the slide
    /// says what the number means, in one sentence the member can read
    /// aloud.
    private func cardSlide(asset: PackAsset, stat: PackStat?) -> some View {
        HStack(alignment: .center, spacing: 100) {
            cardImage(asset, side: 840)
            VStack(alignment: .leading, spacing: 34) {
                eyebrow(stat?.title ?? asset.title)
                if let point = asset.talkingPoint {
                    Text(point)
                        .font(.system(size: 72, weight: .bold))
                        .lineSpacing(10)
                        .lineLimit(5)
                        .minimumScaleFactor(0.7)
                } else if let caption = asset.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.system(size: 52, weight: .semibold))
                        .lineSpacing(10)
                        .lineLimit(6)
                } else if let value = stat?.displayValue, !value.isEmpty {
                    Text([value, stat?.valueLabel ?? ""].filter { !$0.isEmpty }.joined(separator: " "))
                        .font(.system(size: 72, weight: .bold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 110)
        .padding(.vertical, 90)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .overlay(alignment: .bottomLeading) { footer.padding(.horizontal, 110).padding(.bottom, 50) }
    }

    private func closingSlide(stats: [PackStat], story: PackAsset?) -> some View {
        HStack(alignment: .center, spacing: 90) {
            VStack(alignment: .leading, spacing: 30) {
                eyebrow(deck.geoLabel + (deck.monthLabel.isEmpty ? "" : " · \(deck.monthLabel)"))
                Text("The month in \(stats.count == 1 ? "one number" : "\(Self.spelled(stats.count)) numbers")")
                    .font(.system(size: 84, weight: .bold))
                    .lineLimit(2)
                    .padding(.bottom, 20)
                ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                    HStack(alignment: .firstTextBaseline, spacing: 30) {
                        Text(stat.displayValue ?? "")
                            .font(.system(size: 96, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stat.title ?? "")
                                .font(.system(size: 44, weight: .semibold))
                            if let label = stat.valueLabel, !label.isEmpty {
                                Text(label)
                                    .font(.system(size: 34))
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                        }
                        .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Text("Let's talk about your move.")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let story {
                cardImage(story, side: 880)
            }
        }
        .padding(.horizontal, 110)
        .padding(.vertical, 90)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func cardImage(_ asset: PackAsset, side: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: 36, style: .continuous)
        Group {
            if let image = images[asset.id] {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                shape.fill(.white.opacity(0.08))
                    .aspectRatio(asset.aspect, contentMode: .fit)
                    .overlay { ProgressView().tint(.white).scaleEffect(2.5) }
            }
        }
        .frame(maxHeight: side)
        .clipShape(shape)
        .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
    }

    private func eyebrow(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 34, weight: .semibold))
            .tracking(3)
            .foregroundStyle(.white.opacity(0.7))
            .lineLimit(1)
    }

    private var footer: some View {
        Text("Indiana Association of REALTORS® · Housing Hub")
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
    }

    private static func spelled(_ n: Int) -> String {
        ["zero", "one", "two", "three", "four", "five"].indices.contains(n)
            ? ["zero", "one", "two", "three", "four", "five"][n] : String(n)
    }
}

// MARK: - The iPad while presenting

struct PackPresenterView: View {
    @ObservedObject private var presentation = PackPresentation.shared
    @ObservedObject private var external = ExternalDisplay.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showControls = true
    @State private var showNotes = false

    var body: some View {
        Group {
            if external.isConnected {
                presenterLayout
            } else {
                stageLayout
            }
        }
        .statusBarHidden(true)
        .background { keyboard }
        .onChange(of: external.isConnected) { _, connected in
            if !connected { showControls = true }
        }
    }

    // The TV has the slides; the iPad has the words.
    private var presenterLayout: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(presentation.deck?.geoLabel ?? "")
                        .font(.headline)
                    Text(presentation.deck?.monthLabel ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label("On the big screen", systemImage: "tv")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BrandColors.teal, in: Capsule())
                Button("End") { finish() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 12) {
                    if let deck = presentation.deck, let slide = presentation.slide {
                        PackSlideView(slide: slide, deck: deck, images: presentation.images)
                            .aspectRatio(16.0 / 9.0, contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay {
                                HStack(spacing: 0) {
                                    Color.clear.contentShape(Rectangle()).onTapGesture { presentation.previous() }
                                    Color.clear.contentShape(Rectangle()).onTapGesture { presentation.next() }
                                }
                            }
                    }
                    HStack(spacing: 16) {
                        Button { presentation.previous() } label: { Image(systemName: "chevron.left") }
                            .disabled(presentation.index == 0)
                        Text(counter)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                        Button { presentation.next() } label: { Image(systemName: "chevron.right") }
                            .disabled(presentation.nextSlide == nil)
                        Spacer()
                        if let next = presentation.nextSlide {
                            Text("Next: \(next.name)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Last slide")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        HubSectionHeader(title: "What to say")
                        Text(presentation.deck?.script.isEmpty == false
                             ? presentation.deck?.script ?? ""
                             : "This pack has no script yet.")
                            .font(.title3)
                            .lineSpacing(6)
                        if let caption = presentation.slide?.caption, !caption.isEmpty {
                            HubSectionHeader(title: "On this slide")
                                .padding(.top, 8)
                            Text(caption)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .lineSpacing(4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
                .frame(width: 360)
                .background(HubStyle.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
        .hubPage()
    }

    // No second screen: the iPad is the screen. Swipe, or tap the edges.
    private var stageLayout: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let deck = presentation.deck {
                TabView(selection: $presentation.index) {
                    ForEach(Array(deck.slides.enumerated()), id: \.element.id) { i, slide in
                        PackSlideView(slide: slide, deck: deck, images: presentation.images)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .ignoresSafeArea()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.easeInOut(duration: 0.2)) { showControls.toggle() } }
        .overlay(alignment: .top) {
            if showControls {
                HStack {
                    Text(presentation.deck?.geoLabel ?? "")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("Notes") { showNotes = true }
                    Button("End") { finish() }
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if showControls {
                HStack(spacing: 16) {
                    Button { presentation.previous() } label: { Image(systemName: "chevron.left") }
                        .disabled(presentation.index == 0)
                    Text(counter)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                    Button { presentation.next() } label: { Image(systemName: "chevron.right") }
                        .disabled(presentation.nextSlide == nil)
                }
                .buttonStyle(.bordered)
                .tint(.white)
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.black.opacity(0.45), in: Capsule())
                .padding(.bottom, 24)
                .transition(.opacity)
            }
        }
        .sheet(isPresented: $showNotes) {
            NavigationStack {
                ScrollView {
                    Text(presentation.deck?.script.isEmpty == false
                         ? presentation.deck?.script ?? ""
                         : "This pack has no script yet.")
                        .font(.title3)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("What to say")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { showNotes = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var counter: String {
        guard let deck = presentation.deck else { return "" }
        return "\(presentation.index + 1) of \(deck.slides.count)"
    }

    /// A keyboard or a clicker: arrows and space move, escape ends.
    private var keyboard: some View {
        Group {
            Button("Next") { presentation.next() }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Next") { presentation.next() }.keyboardShortcut(.space, modifiers: [])
            Button("Previous") { presentation.previous() }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("End") { finish() }.keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func finish() {
        presentation.end()
        dismiss()
    }
}
