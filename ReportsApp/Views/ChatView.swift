//
//  ChatView.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/13/26.
//


import SwiftUI
import UIKit
import WebKit
import Charts

struct ChatView: View {
    @StateObject private var chat = ChatManager()
    @EnvironmentObject var app: AppState
    @FocusState private var inputFocused: Bool
    @State private var activeGutsContent: GutsModalContent?
    @State private var showingChatList = false
    @State private var showingFiles = false
    /// A recipe from Home that needs an area or market focus before it runs.
    @State private var recipeSetup: SparkRecipe?
    @StateObject private var runLibrary = SparkLibraryModel()
    @State private var isConsumingSparkPrompt = false

    private func associatedGutsText(for index: Int) -> String? {
        guard chat.messages.indices.contains(index) else { return nil }

        if chat.messages[index].payloadType == .guts {
            return chat.messages[index].text
        }

        for nextIndex in (index + 1)..<chat.messages.count {
            if chat.messages[nextIndex].payloadType == .guts {
                return chat.messages[nextIndex].text
            }
        }

        if index > 0 {
            for previousIndex in stride(from: index - 1, through: 0, by: -1) {
                if chat.messages[previousIndex].payloadType == .guts {
                    return chat.messages[previousIndex].text
                }
            }
        }

        return nil
    }

    private func isMessageExpanded(at index: Int) -> Bool {
        false
    }

    private func toggleGuts(at index: Int) {
        guard let gutsText = associatedGutsText(for: index) else { return }
        activeGutsContent = GutsModalContent(text: gutsText)
    }

    @MainActor
    private func consumeSparkPromptIfNeeded() async {
        guard let prompt = app.sparkPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
              !prompt.isEmpty else { return }

        isConsumingSparkPrompt = true
        chat.newChat()
        inputFocused = false
        app.sparkPrompt = nil

        await chat.send(prompt: prompt)
        isConsumingSparkPrompt = false
    }

    /// A recipe Home asked Spark to run.
    @MainActor
    private func runRequestedRecipeIfNeeded() async {
        guard let recipe = app.recipeToRun else { return }
        app.recipeToRun = nil
        if recipe.needsArea || recipe.segment?.asks == true {
            if runLibrary.catalog == nil {
                runLibrary.catalog = try? await SparkLibraryService.segmentCatalog()
            }
            recipeSetup = recipe
            return
        }
        if let prepared = await runLibrary.prepareRun(recipe, geo: "", segmentValues: []) {
            startRun(prepared)
        }
    }

    private func startRun(_ prepared: PreparedRecipeRun) {
        Task {
            await chat.runRecipe(
                prompt: prepared.prompt,
                display: prepared.display,
                planFirst: prepared.planFirst,
                recipeRunID: prepared.runID
            )
        }
    }

    /// A chat opened from a universal link.
    @MainActor
    private func openLinkedThreadIfNeeded() async {
        guard let thread = app.sparkThreadToOpen, !thread.isEmpty else { return }
        app.sparkThreadToOpen = nil
        showingChatList = false
        showingFiles = false
        await chat.loadChat(threadID: thread)
    }

    private var hasPendingSparkPrompt: Bool {
        guard let prompt = app.sparkPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return false
        }
        return !prompt.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(chat.conversationName ?? "Chat")
                    .font(.headline)
                Spacer()

                if !chat.messages.isEmpty {
                    Button {
                        showingFiles = true
                    } label: {
                        Label("Files", systemImage: "tray.full")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }

                Button {
                    showingChatList = true
                } label: {
                    Label("Chats", systemImage: "bubble.left.and.bubble.right")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)

                Button("New") {
                    chat.newChat()
                }
            }
            .padding()

            Divider()

            if !chat.statusMessages.isEmpty {
                StatusPanel(messages: chat.statusMessages)
                    .padding(.horizontal)
                    .padding(.top, 10)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    //LazyVStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        if chat.messages.isEmpty && !hasPendingSparkPrompt && !isConsumingSparkPrompt {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Ask a question")
                                    .font(.headline)
                                Text("Try asking about markets, trends, prices, inventory, or a specific geography.")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        }

                        ForEach(Array(chat.messages.enumerated()), id: \.element.id) { index, message in
                            ChatBubble(
                                message: message,
                                isExpanded: isMessageExpanded(at: index),
                                onToggleGuts: {
                                    toggleGuts(at: index)
                                }
                            )
                            .id(message.id)

                            if let answerID = message.answerID {
                                AnswerFeedbackBar { positive, note in
                                    Task { await chat.sendFeedback(answerID: answerID, positive: positive, note: note) }
                                }
                            }
                        }

                        if let preview = chat.streamingText {
                            StreamingPreviewBubble(text: preview)
                        }

                        if !chat.isSending {
                            if let offer = chat.repeatOffer {
                                RepeatOfferCard(
                                    offer: offer,
                                    isWorking: chat.isAcceptingRepeatOffer,
                                    onAccept: { cadence in Task { await chat.acceptRepeatOffer(cadence: cadence) } },
                                    onDismiss: { chat.dismissRepeatOffer() }
                                )
                            } else if let chip = chat.followUpChip {
                                Button {
                                    Task { await chat.sendFollowUpChip() }
                                } label: {
                                    Label(chip, systemImage: "arrow.turn.down.right")
                                        .font(.subheadline)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Capsule().stroke(BrandColors.teal.opacity(0.5), lineWidth: 1))
                                        .foregroundStyle(BrandColors.teal)
                                }
                                .buttonStyle(.plain)
                            }
                            if let status = chat.repeatOfferStatus {
                                Text(status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding()
                }
//                .onChange(of: chat.pendingScrollTarget) { _, target in
//                    guard let target else { return }
//
//                    Task { @MainActor in
//                        try? await Task.sleep(for: .milliseconds(300))
//                        withAnimation(.easeOut(duration: 0.2)) {
//                            proxy.scrollTo(target, anchor: .top)
//                        }
//                        chat.pendingScrollTarget = nil
//                    }
//                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 12) {
                TextField("Ask about the market…", text: $chat.inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($inputFocused)

                Button {
                    let trimmed = chat.inputText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }

                    inputFocused = false
                    Task { await chat.sendCurrentMessage() }
                } label: {
                    if chat.isSending {
                        ProgressView()
                            .frame(width: 28, height: 28)
                    } else {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                    }
                }
                .disabled(chat.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || chat.isSending)
            }
            .padding()
        }
        .navigationTitle("Spark")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $activeGutsContent) { item in
            NavigationStack {
                HTMLTextView(html: item.text)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding()
                    .navigationTitle("How I answered this")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                activeGutsContent = nil
                            }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingFiles) {
            NavigationStack {
                SparkFilesSheet(chat: chat)
            }
        }
        .sheet(isPresented: $showingChatList) {
            NavigationStack {
                SparkSidebarSheet(
                    chatManager: chat,
                    onOpenThread: { threadID in
                        showingChatList = false
                        Task { await chat.loadChat(threadID: threadID) }
                    },
                    onStartRun: { prepared in
                        showingChatList = false
                        Task {
                            await chat.runRecipe(
                                prompt: prepared.prompt,
                                display: prepared.display,
                                planFirst: prepared.planFirst,
                                recipeRunID: prepared.runID
                            )
                        }
                    }
                )
            }
        }
        .task {
            await consumeSparkPromptIfNeeded()
            await openLinkedThreadIfNeeded()
            await runRequestedRecipeIfNeeded()
        }
        .onChange(of: app.sparkThreadToOpen) { _, _ in
            Task { await openLinkedThreadIfNeeded() }
        }
        .onChange(of: app.recipeToRun) { _, _ in
            Task { await runRequestedRecipeIfNeeded() }
        }
        .sheet(item: $recipeSetup) { recipe in
            NavigationStack {
                RecipeSetupSheet(recipe: recipe, purpose: .run, catalog: runLibrary.catalog) { geo, values, _ in
                    guard let prepared = await runLibrary.prepareRun(recipe, geo: geo, segmentValues: values) else {
                        let message = runLibrary.errorMessage ?? "Couldn't start this recipe."
                        runLibrary.errorMessage = nil
                        return message
                    }
                    startRun(prepared)
                    return nil
                }
            }
        }
        .onChange(of: app.sparkPrompt) { _, _ in
            Task {
                await consumeSparkPromptIfNeeded()
            }
        }
    }
}

private struct ChatBubble: View {
    let message: ChatMessage
    let isExpanded: Bool
    let onToggleGuts: () -> Void

    var isUser: Bool { message.sender == .user }
    var isSystem: Bool { message.sender == .system }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 40) }

            bubbleBody
                .padding(12)
                .background(backgroundShape)

            if !isUser { Spacer(minLength: 40) }
        }
    }

    @ViewBuilder
    private var bubbleBody: some View {
        switch message.payloadType {
        case .gutslink:
            Button(action: onToggleGuts) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                    Text(message.text)
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

        case .guts:
            EmptyView()

        case .chart:
            if let json = debugChartJSON(message.chartSpecJSON),
               let data = debugChartData(from: json),
               let aiSpec = debugDecodedChartSpec(from: data) {
                ChartCardView(spec: ChartNormalizer.build(from: aiSpec))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Chart unavailable")
                    .foregroundStyle(.secondary)
            }
        default:
            RichChatText(
                blocks: message.displayBlocks,
                fallbackText: message.text,
                foregroundStyle: isUser ? .white : (isSystem ? .secondary : .primary)
            )
            .multilineTextAlignment(.leading)
        }
    }

    private func debugChartJSON(_ json: String?) -> String? {
        if let json {
            debugLog("[Chart] message.chartSpecJSON:")
            debugLog(json)
            return json
        }

        debugLog("[Chart] chartSpecJSON is nil")
        return nil
    }

    private func debugChartData(from json: String) -> Data? {
        if let data = json.data(using: .utf8) {
            return data
        }

        debugLog("[Chart] could not convert spec to utf8 data")
        return nil
    }

    private func debugDecodedChartSpec(from data: Data) -> AIChartSpec? {
        do {
            return try JSONDecoder().decode(AIChartSpec.self, from: data)
        } catch {
            debugLog("[Chart] decode failed:", error)
            return nil
        }
    }

    private var backgroundShape: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(backgroundColor)
    }

    private var backgroundColor: Color {
        if isUser {
            return BrandColors.teal
        }
        if isSystem {
            return Color(.tertiarySystemBackground)
        }
        switch message.payloadType {
        case .gutslink:
            return Color(.tertiarySystemBackground)
        case .guts:
            return Color(.secondarySystemBackground)
        case .chart:
            return Color(.secondarySystemBackground)
        case .error:
            return Color.red.opacity(0.12)
        default:
            return Color(.secondarySystemBackground)
        }
    }
}

/// Thumbs up or down under an answer. Down asks what was wrong, like the
/// web's feedback modal; the note is optional.
private struct AnswerFeedbackBar: View {
    let onSend: (_ positive: Bool, _ note: String) -> Void
    @State private var sent: Bool?
    @State private var askingWhy = false
    @State private var note = ""

    var body: some View {
        HStack(spacing: 14) {
            if let sent {
                Label(sent ? "Thanks" : "Thanks, noted", systemImage: sent ? "hand.thumbsup.fill" : "hand.thumbsdown.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    sent = true
                    onSend(true, "")
                } label: {
                    Image(systemName: "hand.thumbsup")
                }
                .accessibilityLabel("Good answer")
                Button {
                    askingWhy = true
                } label: {
                    Image(systemName: "hand.thumbsdown")
                }
                .accessibilityLabel("Bad answer")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .padding(.leading, 12)
        .alert("What was wrong?", isPresented: $askingWhy) {
            TextField("Optional", text: $note)
            Button("Send") {
                sent = false
                onSend(false, note)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

/// "Make this automatic": the member asked for the same piece for the same
/// place on an earlier day. Mirrors the web card: monthly, weekly, dismiss.
private struct RepeatOfferCard: View {
    let offer: RepeatOffer
    let isWorking: Bool
    let onAccept: (_ cadence: String) -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Make this automatic")
                        .font(.subheadline.weight(.semibold))
                    Text("Spark writes your \(offer.place) \(offer.kind) each time new data lands.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            HStack(spacing: 10) {
                Button("Send monthly") { onAccept("monthly") }
                    .buttonStyle(.borderedProminent)
                Button("Send weekly") { onAccept("weekly") }
                    .buttonStyle(.bordered)
                if isWorking {
                    ProgressView()
                }
            }
            .tint(BrandColors.teal)
            .font(.subheadline)
            .disabled(isWorking)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

/// The answer while it streams, as plain text in an assistant bubble. The
/// finished answer replaces it with full formatting, charts and cards.
private struct StreamingPreviewBubble: View {
    let text: String

    var body: some View {
        HStack {
            Text(text)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .animation(.easeOut(duration: 0.15), value: text)
            Spacer(minLength: 40)
        }
    }
}

private struct ChartShareItem: Identifiable {
    let id = UUID()
    let image: UIImage
}

private enum ChartExportLayout: String, CaseIterable, Identifiable {
    case post
    case square
    case story

    var id: String { rawValue }

    var title: String {
        switch self {
        case .post:
            return "Post"
        case .square:
            return "Square"
        case .story:
            return "Story"
        }
    }

    var systemImage: String {
        switch self {
        case .post:
            return "rectangle.portrait"
        case .square:
            return "square"
        case .story:
            return "rectangle"
        }
    }

    var size: CGSize {
        switch self {
        case .post:
            return CGSize(width: 1080, height: 1350)
        case .square:
            return CGSize(width: 1080, height: 1080)
        case .story:
            return CGSize(width: 1080, height: 1920)
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .post:
            return 56
        case .square:
            return 48
        case .story:
            return 56
        }
    }

    var topPadding: CGFloat {
        switch self {
        case .post:
            return 52
        case .square:
            return 48
        case .story:
            return 64
        }
    }

    var bottomPadding: CGFloat {
        switch self {
        case .post:
            return 40
        case .square:
            return 40
        case .story:
            return 48
        }
    }

    var chartTopPadding: CGFloat {
        switch self {
        case .post:
            return 80
        case .square:
            return 64
        case .story:
            return 92
        }
    }

    var chartHeightRatio: CGFloat {
        switch self {
        case .post:
            return 0.56
        case .square:
            return 0.50
        case .story:
            return 0.48
        }
    }

    var titleFontSize: CGFloat {
        switch self {
        case .post:
            return 58
        case .square:
            return 52
        case .story:
            return 60
        }
    }

    var subtitleFontSize: CGFloat {
        switch self {
        case .post:
            return 30
        case .square:
            return 28
        case .story:
            return 30
        }
    }

    var footerFontSize: CGFloat {
        switch self {
        case .post:
            return 26
        case .square:
            return 26
        case .story:
            return 26
        }
    }
}

private struct ChartCardView: View {
    let spec: NormalizedChartSpec
    @Environment(\.displayScale) private var displayScale

    @State private var shareItem: ChartShareItem?
    @State private var showingExpandedChart = false
    @State private var didCopy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SparkChartView(spec: spec)
                .frame(height: 240)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                Button {
                    if let image = renderChartImage(height: 220) {
                        UIPasteboard.general.image = image
                        EventTracker.fireSpark(.sparkCopy, kind: "chart_image", target: spec.title)
                        didCopy = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .milliseconds(1200))
                            didCopy = false
                        }
                    }
                } label: {
                    Label(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Menu {
                    ForEach(ChartExportLayout.allCases) { layout in
                        Button {
                            if let image = renderExportImage(layout: layout) {
                                shareItem = ChartShareItem(image: image)
                                EventTracker.fireSpark(.sparkExport, kind: "chart_\(layout.rawValue)", target: spec.title)
                            }
                        } label: {
                            Label(layout.title, systemImage: layout.systemImage)
                        }
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.caption)
                }

                Button {
                    showingExpandedChart = true
                } label: {
                    Label("Expand", systemImage: "arrow.up.left.and.arrow.down.right")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)
        }
        .sheet(item: $shareItem) { item in
            ChartActivityView(activityItems: [item.image])
        }
        .sheet(isPresented: $showingExpandedChart) {
            NavigationStack {
                ScrollView {
                    SparkChartView(spec: spec)
                        .frame(height: 360)
                        .padding()
                }
                .navigationTitle(spec.title ?? "Chart")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            showingExpandedChart = false
                        }
                    }
                }
            }
        }
    }

    private func renderChartImage(height: CGFloat) -> UIImage? {
        let renderer = ImageRenderer(
            content: SparkChartView(spec: spec)
                .frame(width: 700, height: height)
                .padding(16)
                .background(Color(.systemBackground))
        )
        renderer.scale = displayScale
        return renderer.uiImage
    }

    private func renderExportImage(layout: ChartExportLayout) -> UIImage? {
        let width = layout.size.width
        let height = layout.size.height
        let horizontalPadding = layout.horizontalPadding
        let topPadding = layout.topPadding
        let bottomPadding = layout.bottomPadding
        let chartTopPadding = layout.chartTopPadding
        let chartHeight = height * layout.chartHeightRatio

        let renderer = ImageRenderer(
            content: VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    if let title = spec.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: layout.titleFontSize, weight: .bold, design: .default))
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(layout == .story ? 4 : 3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let subtitle = spec.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: layout.subtitleFontSize, weight: .regular, design: .default))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.top, topPadding)

                SparkChartView(spec: spec, showsHeader: false, isExportStyle: true)
                    .frame(height: chartHeight)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.top, chartTopPadding)

                Spacer(minLength: 0)

                Text("Source: Indiana Association of REALTORS® | Housing Hub")
                    .font(.system(size: layout.footerFontSize, weight: .regular, design: .default))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, horizontalPadding)
                    .padding(.bottom, bottomPadding)
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .background(Color(.systemBackground))
        )
        renderer.scale = displayScale
        return renderer.uiImage
    }
}

// MARK: - Files, pinboard and PowerPoint

private struct WebLinkItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct DeckFileItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// A chat's deliverables, like the web's Files panel and pinboard: the chat's
/// charts as a PowerPoint, the web's editors for slides, report and
/// one-pager (opened signed in), and everything pinned.
private struct SparkFilesSheet: View {
    @ObservedObject var chat: ChatManager
    @Environment(\.dismiss) private var dismiss
    @State private var pins: [SparkPin] = []
    @State private var loadingPins = true
    @State private var buildingDeck = false
    @State private var deckFile: DeckFileItem?
    @State private var webLink: WebLinkItem?
    @State private var openingPath: String?
    @State private var errorMessage: String?

    private var chartJSONs: [String] {
        chat.messages.compactMap { $0.payloadType == .chart ? $0.chartSpecJSON : nil }
    }

    private struct PinGroup: Identifiable {
        let name: String
        let pins: [SparkPin]
        var id: String { name }
    }

    private var groups: [PinGroup] {
        let order = ["Charts", "Posts and emails", "One-sheets", "Sources", "Other"]
        return order.compactMap { name -> PinGroup? in
            let matching = pins.filter { $0.group == name }
            return matching.isEmpty ? nil : PinGroup(name: name, pins: matching)
        }
    }

    var body: some View {
        List {
            Section {
                Button {
                    Task { await buildDeck() }
                } label: {
                    HStack {
                        Label(chartJSONs.count == 1 ? "PowerPoint of 1 chart" : "PowerPoint of \(chartJSONs.count) charts",
                              systemImage: "rectangle.on.rectangle")
                        Spacer()
                        if buildingDeck { ProgressView() }
                    }
                }
                .disabled(chartJSONs.isEmpty || buildingDeck)
            } header: {
                Text("Download")
            } footer: {
                if chartJSONs.isEmpty {
                    Text("Ask for a chart and it can go into a deck.")
                } else {
                    Text("One chart per slide, with its title. To arrange the deck, open Slides below.")
                }
            }

            Section {
                ForEach(webEditors, id: \.path) { editor in
                    Button {
                        Task { await open(editor.path) }
                    } label: {
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(editor.title)
                                    Text(editor.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: editor.icon)
                            }
                            Spacer()
                            if openingPath == editor.path {
                                ProgressView()
                            } else {
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .disabled(!chat.canOpenOnWeb || openingPath != nil)
                }
            } header: {
                Text("On the web")
            } footer: {
                Text(chat.canOpenOnWeb
                     ? "Opens on the Hub, signed in as you. Tap any text to edit it."
                     : "Chats started in earlier versions of the app can't open in the web editors. New chats can.")
            }

            if loadingPins {
                Section("Pinboard") { ProgressView() }
            } else if pins.isEmpty {
                Section("Pinboard") {
                    Text("Charts, posts and sources from this chat are pinned here as they're made.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(groups) { group in
                    Section(group.name) {
                        ForEach(group.pins) { pin in
                            SparkPinRow(pin: pin)
                        }
                    }
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            pins = await chat.loadPins()
            loadingPins = false
        }
        .refreshable {
            pins = await chat.loadPins()
        }
        .sheet(item: $deckFile) { item in
            ChartActivityView(activityItems: [item.url])
        }
        .sheet(item: $webLink) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
    }

    private struct WebEditor {
        let title: String
        let subtitle: String
        let icon: String
        let path: String
    }

    private var webEditors: [WebEditor] {
        let base = "/chat/\(chat.threadID)"
        return [
            WebEditor(title: "Slides", subtitle: "Preview, download or edit", icon: "rectangle.stack", path: "\(base)/slides/"),
            WebEditor(title: "Report", subtitle: "Preview, download or edit", icon: "doc.text", path: "\(base)/report/"),
            WebEditor(title: "One-pager", subtitle: "Preview, download or edit", icon: "doc.richtext", path: "\(base)/onepager/"),
            WebEditor(title: "All files", subtitle: "Everything this chat made", icon: "folder", path: "\(base)/files/"),
        ]
    }

    private func open(_ path: String) async {
        openingPath = path
        errorMessage = nil
        defer { openingPath = nil }
        do {
            let url = try await chat.webLink(path: path)
            webLink = WebLinkItem(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func buildDeck() async {
        buildingDeck = true
        errorMessage = nil
        defer { buildingDeck = false }
        do {
            let url = try await SparkDeckExporter.export(
                chartJSONs: chartJSONs,
                title: chat.conversationName ?? "Market Update",
                threadID: chat.threadID
            )
            deckFile = DeckFileItem(url: url)
            EventTracker.fireSpark(.sparkExport, kind: "deck", target: "\(chartJSONs.count) charts")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SparkPinRow: View {
    let pin: SparkPin
    @State private var copied = false

    private var chartSpec: NormalizedChartSpec? {
        guard let json = pin.chartSpecJSON, let data = json.data(using: .utf8),
              let ai = try? JSONDecoder().decode(AIChartSpec.self, from: data) else { return nil }
        return ChartNormalizer.build(from: ai)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // A chart draws its own title; the label on top printed it twice.
            if chartSpec == nil {
                Text(pin.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
            }
            if let spec = chartSpec {
                SparkChartView(spec: spec)
                    .frame(height: 170)
            } else if let text = pin.text, !text.isEmpty {
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(6)
                Button {
                    UIPasteboard.general.string = text
                    copied = true
                    EventTracker.fireSpark(.sparkCopy, kind: pin.type, target: text)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(BrandColors.teal)
            } else if let link = pin.url, let url = URL(string: link.hasPrefix("http") ? link : ChatManager.serverBaseURL + link) {
                Link(destination: url) {
                    Label("Open", systemImage: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                }
                .foregroundStyle(BrandColors.teal)
            }
        }
        .padding(.vertical, 4)
    }
}

/// The chat's charts as a PowerPoint: each drawn by the app's own chart view
/// at 16:9, sent to the web's /deck/pptx/, which builds the same deck the
/// web's download does (one chart per slide, its title, the member's
/// attribution).
@MainActor
private enum SparkDeckExporter {
    struct DeckError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func export(chartJSONs: [String], title: String, threadID: String) async throws -> URL {
        var slides: [[String: Any]] = []
        for json in chartJSONs.prefix(30) {
            guard let data = json.data(using: .utf8),
                  let ai = try? JSONDecoder().decode(AIChartSpec.self, from: data) else { continue }
            let spec = ChartNormalizer.build(from: ai)
            let renderer = ImageRenderer(
                content: SparkChartView(spec: spec)
                    .frame(width: 1200, height: 675)
                    .padding(24)
                    .background(Color.white)
                    .environment(\.colorScheme, .light)
            )
            renderer.scale = 2
            guard let png = renderer.uiImage?.pngData() else { continue }
            slides.append([
                "title": spec.title ?? "",
                "subtitle": spec.subtitle ?? "",
                "image": "data:image/png;base64," + png.base64EncodedString(),
            ])
        }
        guard !slides.isEmpty else { throw DeckError(message: "None of this chat's charts could be drawn.") }

        var components = URLComponents(string: "\(ChatManager.serverBaseURL)/deck/pptx/")!
        if let chatUserID = UserDefaults.standard.string(forKey: "chat_user_id"), !chatUserID.isEmpty {
            components.queryItems = [URLQueryItem(name: "chat_user_id", value: chatUserID)]
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["title": title, "slides": slides, "thread_id": threadID]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request.withAppIdentity())
        // A .pptx is a zip; anything else is the server's error text.
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              data.starts(with: Array("PK".utf8)) else {
            throw DeckError(message: "The Hub couldn't build the deck. Try again in a minute.")
        }
        let name = title
            .replacingOccurrences(of: #"[^A-Za-z0-9-_ ]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " ", with: "_")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(name.isEmpty ? "Market_Update" : String(name.prefix(60)))
            .appendingPathExtension("pptx")
        try data.write(to: url, options: .atomic)
        return url
    }
}

private struct ChartActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct StatusPanel: View {
    let messages: [ChatMessage]

    private var progressFraction: CGFloat {
        if messages.contains(where: { $0.payloadType == .success }) {
            return 1.0
        }
        // The server sends real progress with each status. Take the highest seen
        // rather than the latest: a turn can report several tool calls, and the
        // bar should never walk backwards.
        let reported = messages.compactMap(\.progressPct).max()
        if let reported {
            return CGFloat(min(max(reported, 0), 100) / 100)
        }
        // Fallback for older servers, which only expressed progress in wording.
        let latestText = messages.last?.text ?? ""
        if latestText.localizedCaseInsensitiveContains("Building") {
            return 0.25
        } else if latestText.localizedCaseInsensitiveContains("Fetching") {
            return 0.50
        } else if latestText.localizedCaseInsensitiveContains("Analyzing the results") {
            return 0.75
        }
        return 0.12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let latest = messages.last {
                HStack(spacing: 10) {
                    Group {
                        switch latest.payloadType {
                        case .error:
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        case .success:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        default:
                            ProgressView()
                        }
                    }

                    Text(latest.text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)

                    Spacer()
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 6)

                    Capsule()
                        .fill(BrandColors.teal)
                        .frame(width: max(12, geo.size.width * progressFraction), height: 6)
                        .animation(.easeInOut(duration: 0.25), value: progressFraction)
                }
            }
            .frame(height: 6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .padding(.bottom, 6)
    }
}

private struct RichChatText: View {
    let blocks: [ChatDisplayBlock]?
    let fallbackText: String
    let foregroundStyle: Color

    var body: some View {
        let resolvedBlocks = blocks ?? [
            ChatDisplayBlock(
                kind: .paragraph,
                plainText: fallbackText,
                attributedText: nil,
                tableData: nil,
                relatedLinks: []
            )
        ]

        VStack(alignment: .leading, spacing: 8) {
            ForEach(resolvedBlocks) { block in
                switch block.kind {
                case .paragraph:
                    VStack(alignment: .leading, spacing: 8) {
                        InlineMarkdownText(
                            plainText: block.plainText,
                            attributedText: block.attributedText,
                            foregroundStyle: foregroundStyle
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)

                        if let relatedLinks = block.relatedLinks, !relatedLinks.isEmpty {
                            RelatedLinksView(links: relatedLinks)
                        }
                    }

                case .bullet:
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("•")
                                .foregroundStyle(foregroundStyle)
                            InlineMarkdownText(
                                plainText: block.plainText,
                                attributedText: block.attributedText,
                                foregroundStyle: foregroundStyle
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        if let relatedLinks = block.relatedLinks, !relatedLinks.isEmpty {
                            RelatedLinksView(links: relatedLinks)
                                .padding(.leading, 18)
                        }
                    }
                case .table:
                    if let table = block.tableData {
                        ChatTableView(table: table)
                    }
                case .contentCard:
                    if let card = block.contentCardData {
                        if card.kind == "onesheet" {
                            OnesheetCardView(card: card)
                        } else {
                            ContentCardView(card: card)
                        }
                    }
                case .sparkCard:
                    if let card = block.sparkCard {
                        SparkCardView(card: card)
                    }
                }
            }
        }
    }
}

private struct SparkCardView: View {
    let card: SparkCard

    var body: some View {
        switch card {
        case .insights(let items):
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(items) { item in
                        SparkInsightCard(insight: item)
                    }
                }
            }
        case .file(let file):
            linkRow(
                systemImage: "arrow.down.doc",
                title: file.name,
                subtitle: file.description ?? "Download the data",
                url: file.url
            )
        case .download(let label, let webURL):
            linkRow(
                systemImage: "square.and.arrow.down.on.square",
                title: label,
                subtitle: "Decks and image bundles download from Spark on the web",
                url: webURL
            )
        case .drawArea(let name, let webURL):
            linkRow(
                systemImage: "scribble.variable",
                title: "Draw \(name) on the map",
                subtitle: "Spark doesn't know this area yet. Draw it on the web, then ask again.",
                url: webURL
            )
        }
    }

    @ViewBuilder
    private func linkRow(systemImage: String, title: String, subtitle: String, url: String) -> some View {
        if let destination = URL(string: url) {
            Link(destination: destination) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.title3)
                        .foregroundStyle(BrandColors.teal)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(.systemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct SparkInsightCard: View {
    let insight: SparkInsight

    private var arrow: String? {
        switch insight.direction?.lowercased() {
        case "up": return "arrow.up.right"
        case "down": return "arrow.down.right"
        default: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let arrow {
                    Image(systemName: arrow)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(BrandColors.teal)
                }
                if let geo = insight.geo {
                    Text(geo)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Text(insight.headline)
                .font(.subheadline.weight(.semibold))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
            if let value = insight.valueFmt {
                Text(insight.change.map { "\(value) · \($0)" } ?? value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let date = insight.reportDate {
                Text(date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(width: 230, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ContentCardView: View {
    let card: ContentCardData
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: card.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandColors.teal)
                Text(card.heading)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    // Emails get an HTML flavor alongside plain, so mail
                    // clients paste real hyperlinks. Everything else pastes
                    // flattened text with visible URLs.
                    if let html = card.copyHTML, let data = html.data(using: .utf8) {
                        UIPasteboard.general.items = [[
                            "public.html": data,
                            "public.utf8-plain-text": card.copyPlainText,
                        ]]
                    } else {
                        UIPasteboard.general.string = card.copyPlainText
                    }
                    EventTracker.fireSpark(.sparkCopy, kind: card.kind, target: card.copyPlainText)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(copied ? .secondary : BrandColors.teal)
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: copied)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))

            Divider()

            Text(card.content)
                .font(.body)
                .foregroundStyle(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

/// A one-sheet block: branded PDF handout built server-side. The card shows a
/// text preview of what's on the page; the action is Download, not Copy —
/// the deliverable is the file, and the JSON behind it is nothing a person
/// should ever see.
private struct OnesheetCardView: View {
    let card: ContentCardData

    private enum DownloadState: Equatable {
        case idle, building, failed
    }
    /// Wrapper so .sheet(item:) gets Identifiable without a retroactive
    /// conformance on URL, which would collide with any other declaration.
    private struct SharePDF: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    @State private var state: DownloadState = .idle
    @State private var sharePDF: SharePDF?

    private var spec: OnesheetSpec? { OnesheetSpec.parse(card.content) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: card.systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandColors.teal)
                Text(card.heading)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button {
                    Task { await download() }
                } label: {
                    switch state {
                    case .building:
                        ProgressView().controlSize(.small)
                    case .failed:
                        Label("Try again", systemImage: "arrow.clockwise")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    case .idle:
                        Label("Download", systemImage: "arrow.down.doc")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BrandColors.teal)
                    }
                }
                .buttonStyle(.plain)
                .disabled(state == .building)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if let spec {
                    if let title = spec.title, !title.isEmpty {
                        Text(title).font(.headline)
                    }
                    if let subtitle = spec.subtitle, !subtitle.isEmpty {
                        Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    }
                    ForEach(Array((spec.sections ?? []).prefix(4).enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 3) {
                            if let heading = section.heading, !heading.isEmpty {
                                Text(heading.uppercased())
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(BrandColors.teal)
                            }
                            ForEach(Array((section.bullets ?? []).prefix(5).enumerated()), id: \.offset) { _, bullet in
                                HStack(alignment: .top, spacing: 6) {
                                    Circle().fill(BrandColors.teal)
                                        .frame(width: 4, height: 4)
                                        .padding(.top, 6)
                                    Text(bullet).font(.footnote)
                                }
                            }
                        }
                    }
                } else {
                    // Spec didn't parse. Better an honest line than raw JSON.
                    Text("A one-page PDF is ready to download.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .sheet(item: $sharePDF) { item in
            OnesheetShareSheet(activityItems: [item.url])
        }
    }

    private func download() async {
        state = .building
        do {
            // The server logs spark_export for this download; chat_user_id
            // lets it credit the member instead of dropping the event.
            var request = URLRequest(url: URL(string: "\(ChatManager.serverBaseURL)/onesheet/pdf/")!.appendingChatUserID())
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = card.content.data(using: .utf8)
            let (data, response) = try await URLSession.shared.data(for: request.withAppIdentity())
            guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                  data.starts(with: Array("%PDF".utf8)) else {
                state = .failed
                return
            }
            let name = (spec?.title ?? "one-sheet")
                .replacingOccurrences(of: #"[^A-Za-z0-9-_ ]"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
                .replacingOccurrences(of: " ", with: "_")
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(name.isEmpty ? "one-sheet" : name)
                .appendingPathExtension("pdf")
            try data.write(to: url, options: .atomic)
            state = .idle
            sharePDF = SharePDF(url: url)
        } catch {
            state = .failed
        }
    }
}

private struct OnesheetShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private enum RelatedLinkKind {
    case chart
    case report
    case link

    init(label: String?, urlString: String) {
        let normalizedLabel = label?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalizedLabel == "chart" {
            self = .chart
            return
        }
        if normalizedLabel == "report" {
            self = .report
            return
        }

        let lower = urlString.lowercased()
        if lower.contains("reports/viz/") {
            self = .chart
        } else if lower.contains("reports/viewreport") {
            self = .report
        } else {
            self = .link
        }
    }

    var title: String {
        switch self {
        case .chart:
            return "Chart"
        case .report:
            return "Report"
        case .link:
            return "Link"
        }
    }

    var systemImage: String {
        switch self {
        case .chart:
            return "chart.xyaxis.line"
        case .report:
            return "doc.text"
        case .link:
            return "link"
        }
    }

    var tint: Color {
        switch self {
        case .chart:
            return BrandColors.teal
        case .report:
            return BrandColors.teal
        case .link:
            return BrandColors.teal
        }
    }
}

private struct ParsedRelatedLinkPresentation {
    let label: String?
    let title: String
    let note: String?

    init(linkTitle: String) {
        let trimmed = linkTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        var working = trimmed
        var parsedLabel: String?

        if working.hasPrefix("["), let close = working.firstIndex(of: "]") {
            let labelStart = working.index(after: working.startIndex)
            let rawLabel = String(working[labelStart..<close]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !rawLabel.isEmpty {
                parsedLabel = rawLabel
            }
            working = String(working[working.index(after: close)...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let separatorRange = working.range(of: " • ", options: .backwards) {
            let left = String(working[..<separatorRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            let right = String(working[separatorRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            self.label = parsedLabel
            self.title = left.isEmpty ? trimmed : left
            self.note = right.isEmpty ? nil : right
        } else {
            self.label = parsedLabel
            self.title = working.isEmpty ? trimmed : working
            self.note = nil
        }
    }
}

private struct RelatedLinksView: View {
    let links: [ChatRelatedLink]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(links.enumerated()), id: \.offset) { _, link in
                if let url = URL(string: link.urlString) {
                    Link(destination: url) {
                        RelatedLinkCard(link: link)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct RelatedLinkCard: View {
    let link: ChatRelatedLink

    private var parsed: ParsedRelatedLinkPresentation {
        ParsedRelatedLinkPresentation(linkTitle: link.title)
    }

    private var kind: RelatedLinkKind {
        RelatedLinkKind(label: parsed.label, urlString: link.urlString)
    }

    private var hostLabel: String {
        URL(string: link.urlString)?.host ?? "data.indianarealtors.com"
    }

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(kind.tint.opacity(0.12))
                .frame(width: 36, height: 36)
                .overlay(
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(kind.tint)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(parsed.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Text(parsed.label?.uppercased() ?? kind.title.uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(kind.tint)

                    if let note = parsed.note, !note.isEmpty {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Text("•")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(hostLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct ChatTableView: View {
    let table: ChatTableData

    private let cellWidth: CGFloat = 120

    private var columnCount: Int {
        max(
            table.headers.count,
            table.rows.map(\.count).max() ?? 0
        )
    }

    private func headerText(at index: Int) -> String {
        guard index < table.headers.count else { return "" }
        return table.headers[index]
    }

    private func cellText(in row: [String], at index: Int) -> String {
        guard index < row.count else { return "" }
        return row[index]
    }

    private var tableAsTSV: String {
        let headerLine = table.headers.joined(separator: "\t")
        let rowLines = table.rows.map { $0.joined(separator: "\t") }
        return ([headerLine] + rowLines).joined(separator: "\n")
    }

    private var tableAsCSV: String {
        func escape(_ value: String) -> String {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }

        let headerLine = table.headers.map(escape).joined(separator: ",")
        let rowLines = table.rows.map { row in
            row.map(escape).joined(separator: ",")
        }
        return ([headerLine] + rowLines).joined(separator: "\n")
    }

    /// Called from `body`, so it runs on every render. A fresh UUID per call
    /// wrote a new temp file each pass; naming the file by its contents and
    /// skipping the write when it exists keeps it to one file per table.
    private func makeCSVFile() -> URL? {
        let csv = tableAsCSV
        let name = "spark-table-\(String(UInt(bitPattern: csv.hashValue), radix: 36)).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: url.path) { return url }

        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            debugLog("Failed to write CSV:", error)
            return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        ForEach(0..<columnCount, id: \.self) { index in
                            Text(headerText(at: index))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(width: cellWidth, alignment: .leading)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                        }
                    }
                    .background(BrandColors.teal.opacity(0.10))

                    ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            ForEach(0..<columnCount, id: \.self) { index in
                                Text(cellText(in: row, at: index))
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                                    .frame(width: cellWidth, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                            }
                        }
                        .background(rowIndex.isMultiple(of: 2) ? Color(.secondarySystemBackground) : Color.clear)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 16) {
                Button {
                    UIPasteboard.general.string = tableAsTSV
                    EventTracker.fireSpark(.sparkCopy, kind: "table", target: table.headers.joined(separator: ","))
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                if let url = makeCSVFile() {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    // ShareLink has no action hook; count the tap that opens it.
                    .simultaneousGesture(TapGesture().onEnded {
                        EventTracker.fireSpark(.sparkExport, kind: "table_csv", target: table.headers.joined(separator: ","))
                    })
                }
            }
            .foregroundStyle(.secondary)
        }
    }
}

private struct InlineMarkdownText: View {
    let plainText: String
    let attributedText: AttributedString?
    let foregroundStyle: Color

    var body: some View {
        SwiftUI.Group {
            if let attributedText {
                Text(attributedText)
            } else {
                Text(plainText)
            }
        }
        .foregroundStyle(foregroundStyle)
        .textSelection(.enabled)
    }
}


private struct GutsModalContent: Identifiable, Equatable {
    let text: String
    var id: String { text }
}

private struct HTMLTextView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        let polishedHTML = preprocessHTML(html)
        let wrappedHTML = """
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
        <style>
        :root {
            color-scheme: light;
        }
        html, body {
            margin: 0;
            padding: 0;
            background: transparent;
            font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', sans-serif;
            font-size: 15px;
            color: #111111;
            line-height: 1.45;
            -webkit-text-size-adjust: 100%;
            overflow-wrap: anywhere;
            word-break: break-word;
        }
        .intro {
            font-size: 17px;
            font-weight: 600;
            line-height: 1.4;
            margin: 0 0 14px 0;
        }
        .chips {
            margin: 0;
            padding: 0;
        }
        .chip {
            display: inline-block;
            background: #eef7f8;
            color: #1b1b1b;
            border: 1px solid #cfe7ea;
            border-radius: 999px;
            padding: 6px 10px;
            margin: 0 8px 8px 0;
            font-size: 14px;
            line-height: 1.3;
        }
        code, pre {
            font-family: 'SF Mono', Menlo, monospace;
            font-size: 13px;
            white-space: pre-wrap;
        }
        a {
            color: #00737e;
            text-decoration: underline;
        }
        </style>
        </head>
        <body>
        \(polishedHTML)
        </body>
        </html>
        """

        if webView.url == nil || webView.isLoading == false {
            webView.loadHTMLString(wrappedHTML, baseURL: URL(string: "https://data.indianarealtors.com"))
        }
    }

    private func preprocessHTML(_ html: String) -> String {
        let working = html.trimmingCharacters(in: .whitespacesAndNewlines)

        if let ulRange = working.range(of: "<ul>", options: .caseInsensitive) {
            let intro = working[..<ulRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
            let listPart = String(working[ulRange.lowerBound...])

            var chips = listPart
            chips = chips.replacingOccurrences(of: "<ul>", with: "<div class=\"chips\">", options: .caseInsensitive)
            chips = chips.replacingOccurrences(of: "</ul>", with: "</div>", options: .caseInsensitive)
            chips = chips.replacingOccurrences(of: "<li>", with: "<span class=\"chip\">", options: .caseInsensitive)
            chips = chips.replacingOccurrences(of: "</li>", with: "</span>", options: .caseInsensitive)

            let introHTML = intro.isEmpty ? "" : "<div class=\"intro\">\(intro)</div>"
            return introHTML + chips
        }

        return "<div class=\"intro\">\(working)</div>"
    }
}

private struct AIChartSpec: Decodable {
    let chartType: String?
    let labels: [String]?
    let title: String?
    let subtitle: String?
    let datasets: [AIChartDataset]?

    enum CodingKeys: String, CodingKey {
        case chartType = "chart_type"
        case labels
        case title
        case subtitle
        case datasets
    }
}

private struct AIChartDataset: Decodable {
    let label: String?
    let data: [Double]?
    let borderWidth: Double?
    let tension: Double?
    let pointRadius: Double?
    let fill: Bool?
    let borderColor: String?
    let backgroundColor: String?

    enum CodingKeys: String, CodingKey {
        case label
        case data
        case borderWidth
        case tension
        case pointRadius
        case fill
        case borderColor
        case backgroundColor
    }
}

private enum ChartKind: String {
    case line
    case bar
}

private struct NormalizedChartSpec {
    let chartType: ChartKind
    let title: String?
    let subtitle: String?
    let series: [NormalizedSeries]
}

private struct NormalizedSeries: Identifiable {
    let id = UUID()
    let label: String
    let points: [ChartPoint]
    let lineWidth: Double
    let pointRadius: Double
    let fill: Bool
    let color: Color
    let fillColor: Color
}

private struct ChartPoint: Identifiable {
    let id = UUID()
    let xLabel: String
    let yValue: Double
}

private let chartBrandColors: [Color] = [
    Color(hex: "#00737e"),
    Color(hex: "#e77c05"),
    Color(hex: "#95215e"),
    Color(hex: "#433277")
]

private extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&int)

        let a, r, g, b: UInt64
        switch cleaned.count {
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 115, 126)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

private enum ChartNormalizer {
    static func build(from spec: AIChartSpec) -> NormalizedChartSpec {
        let labels = spec.labels ?? []
        let chartType = ChartKind(rawValue: spec.chartType ?? "") ?? .line

        let series: [NormalizedSeries] = (spec.datasets ?? []).enumerated().map { index, ds in
            let baseColor = ds.borderColor.map(Color.init(hex:)) ?? chartBrandColors[index % chartBrandColors.count]
            let values = ds.data ?? []

            let points = zip(labels, values).map { label, value in
                ChartPoint(xLabel: label, yValue: value)
            }

            return NormalizedSeries(
                label: ds.label ?? "Series \(index + 1)",
                points: points,
                lineWidth: ds.borderWidth ?? 4,
                pointRadius: ds.pointRadius ?? 4,
                fill: ds.fill ?? false,
                color: baseColor,
                fillColor: baseColor.opacity(ds.fill ?? false ? 0.18 : 0.85)
            )
        }

        return NormalizedChartSpec(
            chartType: chartType,
            title: spec.title,
            subtitle: spec.subtitle,
            series: series
        )
    }
}

private struct SparkChartView: View {
    let spec: NormalizedChartSpec
    var showsHeader: Bool = true
    var isExportStyle: Bool = false

    private enum AxisLabelKind {
        case categorical
        case monthly
        case weekly
    }

    private func axisLabelKind(for labels: [String]) -> AxisLabelKind {
        if let subtitle = spec.subtitle?.lowercased(), subtitle.contains("week") {
            return .weekly
        }

        guard let sample = labels.first?.lowercased() else { return .categorical }

        if sample.contains("week of") {
            return .weekly
        }

        let monthTokens = [
            "jan", "feb", "mar", "apr", "may", "jun",
            "jul", "aug", "sep", "sept", "oct", "nov", "dec"
        ]

        if monthTokens.contains(where: { sample.contains($0) }) {
            return .monthly
        }

        return .categorical
    }

    private func periodicAnchorLabels(from labels: [String], every period: Int) -> [String] {
        guard !labels.isEmpty else { return [] }
        guard period > 0 else { return labels }

        var output: [String] = []
        var index = 0
        while index < labels.count {
            output.append(labels[index])
            index += period
        }

        return output
    }

    private func visibleXAxisLabels() -> [String] {
        guard let labels = spec.series.first?.points.map(\.xLabel), !labels.isEmpty else { return [] }

        let kind = axisLabelKind(for: labels)

        switch kind {
        case .categorical:
            return labels

        case .monthly:
            if labels.count < 6 {
                return labels
            } else if labels.count < 18 {
                return periodicAnchorLabels(from: labels, every: 3)
            } else {
                return periodicAnchorLabels(from: labels, every: 12)
            }

        case .weekly:
            if labels.count < 104 {
                if labels.count <= 2 {
                    return labels
                }
                return [labels.first!, labels.last!]
            } else {
                return periodicAnchorLabels(from: labels, every: 52)
            }
        }
    }

    private var isLongMonthlySeries: Bool {
        guard let labels = spec.series.first?.points.map(\.xLabel), !labels.isEmpty else { return false }
        return axisLabelKind(for: labels) == .monthly && labels.count >= 18
    }

    private func compactXAxisLabel(_ label: String, visibleLabels: [String]) -> String {
        guard isLongMonthlySeries else { return label }

        let monthTokens = [
            "jan", "feb", "mar", "apr", "may", "jun",
            "jul", "aug", "sep", "sept", "oct", "nov", "dec"
        ]

        let visibleLower = visibleLabels.map { $0.lowercased() }
        let sharedMonth = monthTokens.first { token in
            visibleLower.allSatisfy { $0.contains(token) }
        }

        let parts = label.split(separator: " ")
        guard let yearPart = parts.last, yearPart.count == 4 else { return label }
        let year = String(yearPart.suffix(2))

        if sharedMonth != nil {
            return "’\(year)"
        }

        if let month = parts.first {
            return "\(month) ’\(year)"
        }

        return label
    }

    private var chartEndPadding: CGFloat {
        if isExportStyle, visibleXAxisLabels().count > 2 {
            return 84
        }
        return isExportStyle ? 40 : 12
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            chartHeader
            chartLegendView
            chartContent
        }
    }
    @ViewBuilder
    private var chartLegendView: some View {
        if spec.series.count > 1 {
            HStack(spacing: isExportStyle ? 20 : 14) {
                ForEach(spec.series) { series in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(series.color)
                            .frame(width: isExportStyle ? 16 : 10, height: isExportStyle ? 16 : 10)

                        Text(series.label)
                            .font(isExportStyle ? .system(size: 26, weight: .semibold) : .caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.bottom, isExportStyle ? 14 : 0)
        }
    }

    @ViewBuilder
    private var chartHeader: some View {
        if showsHeader, let title = spec.title, !title.isEmpty {
            Text(title)
                .font(.subheadline.weight(.semibold))
        }

        if showsHeader, let subtitle = spec.subtitle, !subtitle.isEmpty {
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var chartContent: some View {
        Chart {
            ForEach(spec.series) { series in
                seriesMarks(for: series)
            }
        }
        .chartXAxis { xAxisMarks }
        .chartXScale(range: .plotDimension(startPadding: isExportStyle ? 40 : 12, endPadding: chartEndPadding))
        .chartYAxis { yAxisMarks }
        .chartLegend(.hidden)
    }

    @ChartContentBuilder
    private func seriesMarks(for series: NormalizedSeries) -> some ChartContent {
        if spec.chartType == .line, series.fill {
            ForEach(series.points) { point in
                AreaMark(
                    x: .value("Label", point.xLabel),
                    y: .value("Value", point.yValue),
                    series: .value("Series", series.label)
                )
                .foregroundStyle(series.fillColor)
            }
        }

        ForEach(series.points) { point in
            primaryMark(for: point, in: series)
        }

        if spec.chartType == .line, let first = series.points.first {
            PointMark(
                x: .value("Label", first.xLabel),
                y: .value("Value", first.yValue)
            )
            .foregroundStyle(series.color)
            .symbolSize(isExportStyle ? 160 : 85)
        }

        if spec.chartType == .line,
           let last = series.points.last,
           last.id != series.points.first?.id {
            PointMark(
                x: .value("Label", last.xLabel),
                y: .value("Value", last.yValue)
            )
            .foregroundStyle(series.color)
            .symbolSize(isExportStyle ? 160 : 85)
        }
    }

    @ChartContentBuilder
    private func primaryMark(for point: ChartPoint, in series: NormalizedSeries) -> some ChartContent {
        switch spec.chartType {
        case .line:
            LineMark(
                x: .value("Label", point.xLabel),
                y: .value("Value", point.yValue),
                series: .value("Series", series.label)
            )
            .foregroundStyle(series.color)
            .lineStyle(
                StrokeStyle(
                    lineWidth: isExportStyle ? max(series.lineWidth, 10) : series.lineWidth,
                    lineCap: .round,
                    lineJoin: .round
                )
            )

        case .bar:
            BarMark(
                x: .value("Label", point.xLabel),
                y: .value("Value", point.yValue)
            )
            .foregroundStyle(series.color)
        }
    }

    private var xAxisMarks: some AxisContent {
        let visible = visibleXAxisLabels()
        let lastVisible = visible.last
        let shouldLeftAnchorLast = visible.count > 2 && !isLongMonthlySeries

        return AxisMarks(values: visible) { value in
            AxisGridLine()
                .foregroundStyle(Color.primary.opacity(isExportStyle ? 0.30 : 0.20))

            AxisTick()
                .foregroundStyle(Color.primary.opacity(0.12))

            if let label = value.as(String.self) {
                if shouldLeftAnchorLast, label == lastVisible {
                    AxisValueLabel(anchor: .topLeading) {
                        Text(compactXAxisLabel(label, visibleLabels: visible))
                            .font(isExportStyle ? .system(size: 28, weight: .medium) : .caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                } else {
                    AxisValueLabel(centered: false) {
                        Text(compactXAxisLabel(label, visibleLabels: visible))
                            .font(isExportStyle ? .system(size: 28, weight: .medium) : .caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .fixedSize()
                    }
                }
            }
        }
    }

    private var yAxisMarks: some AxisContent {
        AxisMarks(position: .leading) { value in
            AxisGridLine()
                .foregroundStyle(Color.primary.opacity(isExportStyle ? 0.30 : 0.20))
            AxisTick()
                .foregroundStyle(Color.primary.opacity(0.12))
            AxisValueLabel() {
                if let number = value.as(Double.self) {
                    Text(number.formatted())
                        .font(isExportStyle ? .system(size: 28, weight: .medium) : .caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
/// One conversation in the Spark sidebar (SparkLibraryView.swift).
struct ChatListRow: View {
    let item: ChatSummary

    private var timestampText: String? {
        if let updated = item.updated, let date = parseISODate(updated) {
            return "Updated " + formattedDisplay(for: date)
        }

        if let created = item.created, let date = parseISODate(created) {
            return "Created " + formattedDisplay(for: date)
        }

        return nil
    }

    private func parseISODate(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) {
            return date
        }

        let fallback = ISO8601DateFormatter()
        fallback.formatOptions = [.withInternetDateTime]
        return fallback.date(from: value)
    }

    private func formattedDisplay(for date: Date) -> String {
        let now = Date()
        let seconds = now.timeIntervalSince(date)

        if seconds < 60 {
            return "just now"
        }

        if seconds < 60 * 60 * 24 * 7 {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .full
            return formatter.localizedString(for: date, relativeTo: now)
        }

        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter.string(from: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            if let timestampText {
                Text(timestampText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}
