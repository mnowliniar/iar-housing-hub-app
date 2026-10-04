//
//  MarketPackView.swift
//  ReportsApp
//
//  The Market Pack, on the phone: swipe through this month's Story card,
//  three squares and the reel for a market, share each one where it goes,
//  tap another market at the top, and set the pack up under Options.
//

import SwiftUI
import AVKit

struct MarketPackView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var auth: AuthManager
    @StateObject private var model = MarketPackModel()
    @State private var page = "story"
    @State private var showOptions = false
    @State private var addingMarket = false
    @State private var scriptExpanded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                marketRow
                if let error = model.error {
                    errorCard(error)
                } else if model.loadingSetup || (model.loadingIssue && model.issue == nil) {
                    loadingCards
                } else if let issue = model.issue {
                    header(issue)
                    pager
                    script(issue)
                    downloadAll
                    subscription
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .hubPage()
        .navigationTitle("Market Pack")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showOptions = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .disabled(model.setup == nil)
            }
        }
        .sheet(isPresented: $showOptions) {
            if let setup = model.setup {
                MarketPackOptionsSheet(setup: setup) { combo, preset, template, markets, active in
                    await model.save(combo: combo, preset: preset, template: template, markets: markets, active: active)
                }
            }
        }
        .sheet(isPresented: $addingMarket) {
            FavoriteMarketPickerSheet(existingIDs: model.markets.map(\.geoID)) { geo in
                Task { await model.addMarket(geo) }
            }
        }
        .sheet(item: $model.shareItem) { item in
            ActivityViewController(activityItems: item.items)
        }
        .alert("Market Pack", isPresented: Binding(
            get: { model.notice != nil },
            set: { if !$0 { model.notice = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.notice ?? "")
        }
        .task {
            if let raw = app.userPrefs.app.dashboardGeoID, let id = Int(raw) { model.fallbackGeoID = id }
            if model.setup == nil { await model.load() }
        }
        .onChange(of: model.currentGeoID) { _, _ in
            page = "story"
            scriptExpanded = false
        }
        .onDisappear { model.stop() }
    }

    // MARK: Markets

    private var marketRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if model.hasOwnMarkets {
                        ForEach(model.markets) { market in
                            marketChip(market.geoLabel, selected: market.geoID == model.currentGeoID) {
                                Task { await model.select(market.geoID) }
                            }
                            .contextMenu {
                                Button(role: .destructive) {
                                    Task { await model.removeMarket(market) }
                                } label: {
                                    Label("Remove from pack", systemImage: "minus.circle")
                                }
                            }
                        }
                    } else if model.setup != nil {
                        marketChip(model.currentLabel, selected: true) {}
                    }
                    if model.canAddMarket, model.setup != nil {
                        Button {
                            addingMarket = true
                        } label: {
                            Label(model.hasOwnMarkets ? "Add" : "Add a market", systemImage: "plus")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(BrandColors.teal)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(HubStyle.card, in: Capsule())
                                .overlay(Capsule().stroke(BrandColors.teal.opacity(0.35), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.horizontal, -16)
            if model.setup != nil && !model.hasOwnMarkets {
                Text("Your pack has no markets yet. Add up to \(model.maxMarkets); each one gets its own cards and reel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func marketChip(_ label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? BrandColors.teal : HubStyle.card, in: Capsule())
                .overlay(Capsule().stroke(selected ? Color.clear : HubStyle.hairline, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Sections

    private func header(_ issue: PackIssue) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text((issue.monthLabel ?? "This month").uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(issue.geoLabel ?? model.currentLabel)
                .font(.title2.weight(.bold))
            Text("Swipe through the cards. Share each one where it goes.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var pager: some View {
        VStack(spacing: 10) {
            TabView(selection: $page) {
                ForEach(model.assets) { asset in
                    Group {
                        if asset.isReel {
                            PackReelPage(asset: asset, state: model.reel, busy: model.busyAssetID == asset.id,
                                         create: { model.createReel() },
                                         share: { Task { await model.shareAsset(asset) } })
                        } else {
                            PackCardPage(asset: asset, busy: model.busyAssetID == asset.id,
                                         retry: { model.retryRender(asset) },
                                         share: { Task { await model.shareAsset(asset) } })
                        }
                    }
                    .tag(asset.id)
                    .padding(.horizontal, 2)
                    .padding(.bottom, 8)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 620)

            HStack(spacing: 6) {
                ForEach(model.assets) { asset in
                    Capsule()
                        .fill(asset.id == page ? BrandColors.teal : HubStyle.hairline)
                        .frame(width: asset.id == page ? 18 : 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: page)
                }
                Spacer()
                Text(pageLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 4)
        }
    }

    private var pageLabel: String {
        guard let i = model.assets.firstIndex(where: { $0.id == page }) else { return "" }
        return "\(i + 1) of \(model.assets.count) · \(model.assets[i].title)"
    }

    private func script(_ issue: PackIssue) -> some View {
        Group {
            if let text = issue.script, !text.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    HubSectionHeader(title: "What to say") {
                        Button("Copy") {
                            UIPasteboard.general.string = text
                            model.notice = "Script copied."
                        }
                    }
                    Text(text)
                        .font(.subheadline)
                        .lineSpacing(3)
                        .lineLimit(scriptExpanded ? nil : 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(scriptExpanded ? "Show less" : "Show more") {
                        withAnimation { scriptExpanded.toggle() }
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BrandColors.teal)
                }
                .hubCard()
            }
        }
    }

    private var downloadAll: some View {
        Button {
            Task { await model.exportAll() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandColors.teal)
                    .frame(width: 32, height: 32)
                    .background(BrandColors.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Download everything")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Every card, the reel when it's made, the script and captions, in one file")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if model.exporting {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .hubCard(padding: 12)
        }
        .buttonStyle(.plain)
        .disabled(model.exporting)
    }

    private var subscription: some View {
        VStack(alignment: .leading, spacing: 10) {
            HubSectionHeader(title: "Your pack") {
                Button("Options") { showOptions = true }
            }
            if let setup = model.setup {
                Toggle(isOn: Binding(
                    get: { setup.active },
                    set: { value in Task { await model.setActive(value) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Email me the pack each month")
                            .font(.body.weight(.semibold))
                        Text(model.hasOwnMarkets
                             ? "\(model.markets.count) \(model.markets.count == 1 ? "market" : "markets") · \(setup.summary)"
                             : "Add a market first")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(BrandColors.teal)
                .disabled(!model.hasOwnMarkets && !setup.active)
            }
        }
        .hubCard()
    }

    private var loadingCards: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(HubStyle.chip).frame(width: 90, height: 10)
                RoundedRectangle(cornerRadius: 4).fill(HubStyle.chip).frame(width: 200, height: 24)
            }
            VStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(HubStyle.chip)
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .frame(height: 430)
                    .overlay {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("Building this month's pack…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                RoundedRectangle(cornerRadius: 4).fill(HubStyle.chip).frame(height: 10)
            }
            .frame(maxWidth: .infinity)
            .hubCard()
        }
    }

    private func errorCard(_ error: SparkLibraryService.ServiceError) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(error.message)
                .font(.subheadline)
            HStack(spacing: 12) {
                if error.needsSignIn {
                    Button("Sign in") { auth.signInAgain() }
                        .buttonStyle(.borderedProminent)
                        .tint(BrandColors.teal)
                }
                Button("Try again") {
                    Task {
                        if model.setup == nil { await model.load() } else { await model.reload() }
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubCard()
        .onChange(of: auth.session?.accessToken) { _, _ in
            Task { await model.load() }
        }
    }
}

// MARK: - One card

struct PackCardPage: View {
    let asset: PackAsset
    let busy: Bool
    let retry: () -> Void
    let share: () -> Void

    private let stage: CGFloat = 430

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(asset.eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                if asset.ready, let url = asset.url {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
                        case .failure:
                            placeholder(text: "Couldn't load this card.", spinning: false)
                        default:
                            placeholder(text: "Loading…", spinning: true)
                        }
                    }
                } else if asset.failed {
                    placeholder(text: "This card didn't render.", spinning: false)
                } else {
                    placeholder(text: "Making this card…", spinning: true)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: stage)

            VStack(alignment: .leading, spacing: 4) {
                Text(asset.title)
                    .font(.body.weight(.semibold))
                if let line = asset.statLine {
                    Text(line)
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let caption = asset.caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                } else if case .story = asset.kind {
                    Text("Post this to your Story, then the squares to your feed.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                if let caption = asset.caption {
                    Button {
                        UIPasteboard.general.string = caption
                    } label: {
                        Label("Copy caption", systemImage: "doc.on.doc")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                }
                if asset.failed {
                    Button("Try again", action: retry)
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(action: share) {
                    HStack(spacing: 6) {
                        if busy {
                            ProgressView().controlSize(.small).tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                        Text("Share")
                    }
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(BrandColors.teal)
                .disabled(!asset.ready || busy)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .hubCard()
    }

    private func placeholder(text: String, spinning: Bool) -> some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(HubStyle.chip)
            .aspectRatio(asset.aspect, contentMode: .fit)
            .overlay {
                VStack(spacing: 8) {
                    if spinning { ProgressView() }
                    Text(text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
    }
}

// MARK: - The reel

struct PackReelPage: View {
    let asset: PackAsset
    let state: ReelState
    let busy: Bool
    let create: () -> Void
    let share: () -> Void

    @State private var player: AVPlayer?
    private let stage: CGFloat = 430

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(asset.eyebrow.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                if case .ready(let url) = state {
                    VideoPlayer(player: player)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .shadow(color: .black.opacity(0.10), radius: 10, y: 4)
                        .onAppear {
                            if player == nil { player = AVPlayer(url: url) }
                        }
                        .onDisappear { player?.pause() }
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(HubStyle.chip)
                        .aspectRatio(9.0 / 16.0, contentMode: .fit)
                        .overlay {
                            VStack(spacing: 10) {
                                if state.inProgress {
                                    ProgressView()
                                } else {
                                    Image(systemName: "play.rectangle")
                                        .font(.title)
                                        .foregroundStyle(.secondary)
                                }
                                Text(stageText)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: stage)

            VStack(alignment: .leading, spacing: 4) {
                Text("Reel")
                    .font(.body.weight(.semibold))
                Text(detailText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Spacer()
                switch state {
                case .ready:
                    Button(action: share) {
                        HStack(spacing: 6) {
                            if busy {
                                ProgressView().controlSize(.small).tint(.white)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Text("Share")
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrandColors.teal)
                    .disabled(busy)
                case .idle, .failed:
                    Button(action: create) {
                        Label(stateIsFailed ? "Try again" : "Create your reel", systemImage: "sparkles")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrandColors.teal)
                case .queued, .rendering:
                    Button(action: {}) {
                        Label("Rendering…", systemImage: "hourglass")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(true)
                case .emailOnly:
                    EmptyView()
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .hubCard()
        .onChange(of: state) { _, newState in
            if case .ready(let url) = newState {
                player = AVPlayer(url: url)
            } else {
                player?.pause()
                player = nil
            }
        }
    }

    private var stateIsFailed: Bool {
        if case .failed = state { return true }
        return false
    }

    private var stageText: String {
        switch state {
        case .idle: return "A 30-second reel of this month's numbers, made for you."
        case .emailOnly: return "Your reel arrives with the monthly pack email."
        case .queued: return "Waiting for a renderer…"
        case .rendering: return "Recording your reel… about a minute."
        case .failed(let text): return text
        case .ready: return ""
        }
    }

    private var detailText: String {
        switch state {
        case .ready: return "Vertical video, ready for Reels, Stories and TikTok. Share saves it to Photos too."
        case .emailOnly: return "This month's reel is rendered with the email, not on demand."
        case .queued, .rendering: return "Stay on this page or come back; it keeps going."
        case .failed: return "Reels render on the Hub's servers. Trying again usually works."
        case .idle: return "The same three indicators as your cards, narrated on screen."
        }
    }
}
