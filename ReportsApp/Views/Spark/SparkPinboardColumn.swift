//
//  SparkPinboardColumn.swift
//  ReportsApp
//
//  The pinboard beside the chat on an iPad: the charts, posts and sources
//  this chat has made, live, with a title you can change, a card you can
//  drop, and the things the board builds (slides, report, one-pager, a
//  PowerPoint of the charts).
//

import SwiftUI

struct SparkPinboardColumn: View {
    @ObservedObject var chat: ChatManager
    @EnvironmentObject var auth: AuthManager
    @Environment(\.openURL) private var openURL

    @State private var pins: [SparkPin] = []
    @State private var loading = true
    @State private var renaming: SparkPin?
    @State private var newTitle = ""
    @State private var buildingDeck = false
    @State private var deckFile: DeckFileItem?
    @State private var webLink: WebLinkItem?
    @State private var openingPath: String?
    @State private var errorMessage: String?
    @State private var signingIn = false
    @State private var pathAfterSignIn: String?

    private var chartJSONs: [String] {
        chat.messages.compactMap { $0.payloadType == .chart ? $0.chartSpecJSON : nil }
    }

    private struct PinGroup: Identifiable {
        let name: String
        let pins: [SparkPin]
        var id: String { name }
    }

    private var groups: [PinGroup] {
        ["Charts", "Posts and emails", "One-sheets", "Sources", "Other"].compactMap { name in
            let matching = pins.filter { $0.group == name }
            return matching.isEmpty ? nil : PinGroup(name: name, pins: matching)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pinboard")
                    .font(.headline)
                if !pins.isEmpty {
                    Text("\(pins.count)")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(HubStyle.chip, in: Capsule())
                }
                Spacer()
                if loading && !pins.isEmpty { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    makeSection
                    if loading && pins.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else if pins.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Nothing pinned yet")
                                .font(.subheadline.weight(.semibold))
                            Text("Charts, posts and sources land here as Spark makes them. Press and hold one to rename or remove it.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .hubCard(padding: 12)
                    } else {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 8) {
                                HubSectionHeader(title: group.name)
                                ForEach(group.pins) { pin in
                                    SparkPinTile(pin: pin,
                                                 rename: { renaming = pin; newTitle = pin.label },
                                                 remove: { Task { await remove(pin) } })
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 24)
            }
        }
        .background(HubStyle.page)
        .task(id: "\(chat.threadID)-\(chat.pinsVersion)") { await reload() }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } }),
               presenting: renaming) { pin in
            TextField("Title", text: $newTitle)
            Button("Save") { Task { await rename(pin) } }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("A chart's new title goes on the chart, the deck and the report.")
        }
        .alert("Couldn't do that", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }),
               presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .sheet(item: $deckFile) { item in
            ChartActivityView(activityItems: [item.url])
        }
        .sheet(item: $webLink) { item in
            SafariView(url: item.url)
                .ignoresSafeArea()
        }
        .sheet(isPresented: $signingIn) {
            SafariView(url: auth.loginStartURL)
                .ignoresSafeArea()
        }
        .onChange(of: auth.session?.accessToken) { _, _ in
            signingIn = false
            guard let path = pathAfterSignIn, auth.state == .signedIn else { return }
            pathAfterSignIn = nil
            Task { await open(path) }
        }
    }

    // MARK: Make

    private var makeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HubSectionHeader(title: "Make")
            VStack(spacing: 0) {
                makeRow(title: chartJSONs.isEmpty ? "PowerPoint" : "PowerPoint of \(chartJSONs.count) \(chartJSONs.count == 1 ? "chart" : "charts")",
                        subtitle: chartJSONs.isEmpty ? "Ask for a chart first" : "One chart per slide, with its title",
                        icon: "rectangle.on.rectangle", busy: buildingDeck, enabled: !chartJSONs.isEmpty && !buildingDeck) {
                    Task { await buildDeck() }
                }
                Divider().padding(.leading, 44)
                makeRow(title: "Slides", subtitle: "Preview, download or edit on the Hub", icon: "rectangle.stack",
                        busy: openingPath == "/chat/\(chat.threadID)/slides/", enabled: chat.canOpenOnWeb && openingPath == nil) {
                    Task { await open("/chat/\(chat.threadID)/slides/") }
                }
                Divider().padding(.leading, 44)
                makeRow(title: "Report", subtitle: "Preview, download or edit on the Hub", icon: "doc.text",
                        busy: openingPath == "/chat/\(chat.threadID)/report/", enabled: chat.canOpenOnWeb && openingPath == nil) {
                    Task { await open("/chat/\(chat.threadID)/report/") }
                }
                Divider().padding(.leading, 44)
                makeRow(title: "One-pager", subtitle: "Preview, download or edit on the Hub", icon: "doc.richtext",
                        busy: openingPath == "/chat/\(chat.threadID)/onepager/", enabled: chat.canOpenOnWeb && openingPath == nil) {
                    Task { await open("/chat/\(chat.threadID)/onepager/") }
                }
            }
            .hubCard(padding: 0)
        }
    }

    private func makeRow(title: String, subtitle: String, icon: String, busy: Bool, enabled: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BrandColors.teal)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if busy {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }

    // MARK: Doing

    private func reload() async {
        loading = true
        pins = await chat.loadPins()
        loading = false
    }

    private func rename(_ pin: SparkPin) async {
        let title = newTitle
        renaming = nil
        if !(await chat.renamePin(pin, to: title)) {
            errorMessage = "The new title didn't save. Try again in a moment."
        }
    }

    private func remove(_ pin: SparkPin) async {
        if await chat.deletePin(pin) {
            pins.removeAll { $0.id == pin.id }
        } else {
            errorMessage = "That pin didn't go. Try again in a moment."
        }
    }

    private func open(_ path: String) async {
        openingPath = path
        defer { openingPath = nil }
        do {
            webLink = WebLinkItem(url: try await chat.webLink(path: path))
        } catch {
            if let service = error as? SparkLibraryService.ServiceError, service.needsSignIn {
                auth.needsFreshSignIn = true
                pathAfterSignIn = path
                signingIn = true
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private func buildDeck() async {
        buildingDeck = true
        defer { buildingDeck = false }
        do {
            let url = try await SparkDeckExporter.export(
                chartJSONs: chartJSONs,
                title: chat.conversationName ?? "Market Update",
                threadID: chat.threadID)
            deckFile = DeckFileItem(url: url)
            EventTracker.fireSpark(.sparkExport, kind: "deck", target: "\(chartJSONs.count) charts")
            ChatManager.recordPinUse(.exported, .allCharts)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - One pin on the board

struct SparkPinTile: View {
    let pin: SparkPin
    let rename: () -> Void
    let remove: () -> Void

    @Environment(\.displayScale) private var displayScale
    @State private var copied = false

    private var chartSpec: NormalizedChartSpec? {
        guard let json = pin.chartSpecJSON, let data = json.data(using: .utf8),
              let ai = try? JSONDecoder().decode(AIChartSpec.self, from: data) else { return nil }
        return ChartNormalizer.build(from: ai)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let spec = chartSpec {
                SparkChartView(spec: spec)
                    .frame(height: 190)
            } else {
                Text(pin.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                if let text = pin.text, !text.isEmpty {
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(5)
                } else if let link = pin.url {
                    Text(link)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            HStack(spacing: 14) {
                if chartSpec != nil {
                    Button {
                        copyChartImage()
                    } label: {
                        Label(copied ? "Copied" : "Copy image", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                } else if let text = pin.text, !text.isEmpty {
                    Button {
                        UIPasteboard.general.string = text
                        flashCopied()
                        EventTracker.fireSpark(.sparkCopy, kind: pin.type, target: text)
                        ChatManager.recordPinUse(.copied, .id(pin.id))
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    }
                } else if let link = pin.url,
                          let url = URL(string: link.hasPrefix("http") ? link : ChatManager.serverBaseURL + link) {
                    Link(destination: url) {
                        Label("Open", systemImage: "arrow.up.right")
                    }
                }
                Spacer()
                Menu {
                    Button { rename() } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) { remove() } label: { Label("Remove from board", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(BrandColors.teal)
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubCard(padding: 12)
        .contextMenu {
            Button { rename() } label: { Label("Rename", systemImage: "pencil") }
            Button(role: .destructive) { remove() } label: { Label("Remove from board", systemImage: "trash") }
        }
    }

    private func copyChartImage() {
        guard let spec = chartSpec else { return }
        let renderer = ImageRenderer(
            content: SparkChartView(spec: spec)
                .frame(width: 700, height: 220)
                .padding(16)
                .background(Color(.systemBackground))
        )
        renderer.scale = displayScale
        guard let image = renderer.uiImage else { return }
        UIPasteboard.general.image = image
        flashCopied()
        EventTracker.fireSpark(.sparkCopy, kind: "chart_image", target: spec.title)
        ChatManager.recordPinUse(.copied, .id(pin.id))
    }

    private func flashCopied() {
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1200))
            copied = false
        }
    }
}
