//
//  SparkLibraryView.swift
//  ReportsApp
//
//  Spark's sidebar and its recipes/schedules/runs manager, built to work like
//  the web chat's: search across every chat, your top recipes, the latest
//  runs, then conversations with "Show older chats". The manager runs,
//  creates, schedules, pauses and deletes.
//

import SwiftUI

/// A recipe run ready to send: the built prompt, the label the chat shows,
/// and the run id that links the run to its chat.
struct PreparedRecipeRun {
    let prompt: String
    let display: String
    let planFirst: Bool?
    let runID: Int?
}

@MainActor
final class SparkLibraryModel: ObservableObject {
    @Published var recipes: [SparkRecipe] = []
    @Published var starters: [SparkRecipe] = []
    @Published var schedules: [SparkSchedule] = []
    @Published var runs: [SparkRun] = []
    @Published var catalog: SparkSegmentCatalog?
    @Published var loggedIn = true
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// A one-line confirmation, like "Sent. Check your inbox."
    @Published var notice: String?

    /// The sidebar's three: most-run first, like the web.
    var topRecipes: [SparkRecipe] {
        Array(recipes.sorted { $0.uses > $1.uses }.prefix(3))
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let list = try await SparkLibraryService.recipes()
            recipes = list.recipes
            starters = list.starters
            loggedIn = list.loggedIn
        } catch {
            errorMessage = error.localizedDescription
        }
        schedules = (try? await SparkLibraryService.schedules()) ?? schedules
        runs = (try? await SparkLibraryService.runs(limit: 100)) ?? runs
        if catalog == nil {
            catalog = try? await SparkLibraryService.segmentCatalog()
        }
    }

    /// Builds the recipe's prompt and records the run. Nil after an error,
    /// which lands in errorMessage.
    func prepareRun(_ recipe: SparkRecipe, geo: String, segmentValues: [String]) async -> PreparedRecipeRun? {
        do {
            let built = try await SparkLibraryService.prompt(recipeID: recipe.id, geo: geo, segmentValues: segmentValues)
            let runID = await SparkLibraryService.markUsed(recipeID: recipe.id, geo: geo)
            let place = !geo.isEmpty ? geo : (recipe.geoMode == "fixed" ? (recipe.geoLabel ?? "") : "")
            let display = place.isEmpty ? recipe.name : "\(recipe.name) · \(place)"
            return PreparedRecipeRun(prompt: built.prompt, display: display, planFirst: built.planFirst, runID: runID)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func createRecipe(describing text: String, threadID: String? = nil) async -> Bool {
        do {
            let recipe = try await SparkLibraryService.createRecipe(describing: text, threadID: threadID)
            recipes.insert(recipe, at: 0)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func fork(_ starter: SparkRecipe) async {
        do {
            let recipe = try await SparkLibraryService.fork(starterID: starter.id)
            recipes.insert(recipe, at: 0)
            notice = "Added \(recipe.name) to your recipes."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ recipe: SparkRecipe, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != recipe.name else { return }
        do {
            let updated = try await SparkLibraryService.rename(recipeID: recipe.id, to: trimmed)
            if let i = recipes.firstIndex(where: { $0.id == recipe.id }) { recipes[i] = updated }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ recipe: SparkRecipe) async {
        do {
            try await SparkLibraryService.deleteRecipe(id: recipe.id)
            recipes.removeAll { $0.id == recipe.id }
            // Deleting a recipe deletes its schedules on the server too.
            schedules.removeAll { $0.recipeID == recipe.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Nil on success, else the message to show in the sheet.
    func schedule(_ recipe: SparkRecipe, cadence: String, geo: String,
                  segmentValues: [String], threadID: String?) async -> String? {
        do {
            let created = try await SparkLibraryService.createSchedule(
                recipeID: recipe.id, cadence: cadence, geo: geo,
                segmentValues: segmentValues, threadID: threadID
            )
            schedules.insert(created, at: 0)
            if recipe.isStarter {
                // The server copied the starter into the member's recipes.
                let list = try? await SparkLibraryService.recipes()
                if let list { recipes = list.recipes }
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func setActive(_ schedule: SparkSchedule, _ active: Bool) async {
        do {
            let updated = try await SparkLibraryService.setScheduleActive(id: schedule.id, active: active)
            if let i = schedules.firstIndex(where: { $0.id == schedule.id }) { schedules[i] = updated }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ schedule: SparkSchedule) async {
        do {
            try await SparkLibraryService.deleteSchedule(id: schedule.id)
            schedules.removeAll { $0.id == schedule.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @Published var runningNowID: String?

    func runNow(_ schedule: SparkSchedule) async {
        runningNowID = schedule.id
        defer { runningNowID = nil }
        do {
            try await SparkLibraryService.runScheduleNow(id: schedule.id)
            notice = "Sent. Check your inbox."
            runs = (try? await SparkLibraryService.runs(limit: 100)) ?? runs
            schedules = (try? await SparkLibraryService.schedules()) ?? schedules
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Sidebar

/// The chat list, laid out like the web sidebar.
struct SparkSidebarSheet: View {
    @ObservedObject var chatManager: ChatManager
    let onOpenThread: (String) -> Void
    let onStartRun: (PreparedRecipeRun) -> Void

    @StateObject private var library = SparkLibraryModel()
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var searchResults: [ChatSummary]?
    @State private var setupRecipe: SparkRecipe?

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        List {
            if isSearching {
                searchSection
            } else {
                recipesSection
                runsSection
                conversationsSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Spark")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Search chats")
        .task(id: searchText) {
            // Debounced like the web's 300 ms, then searched on the server.
            guard isSearching else { searchResults = nil; return }
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            let found = await chatManager.searchChats(searchText)
            guard !Task.isCancelled else { return }
            searchResults = found
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await chatManager.fetchChats()
                        await library.refresh()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh")
            }
        }
        .task {
            if chatManager.chats.isEmpty { await chatManager.fetchChats() }
            await library.refresh()
        }
        .sheet(item: $setupRecipe) { recipe in
            NavigationStack {
                RecipeSetupSheet(recipe: recipe, purpose: .run, catalog: library.catalog) { geo, values, _ in
                    guard let prepared = await library.prepareRun(recipe, geo: geo, segmentValues: values) else {
                        return library.errorMessage ?? "Couldn't start this recipe."
                    }
                    onStartRun(prepared)
                    return nil
                }
            }
        }
        .alert("Spark", isPresented: errorShowing) {
            Button("OK", role: .cancel) { library.errorMessage = nil }
        } message: {
            Text(library.errorMessage ?? "")
        }
    }

    private var errorShowing: Binding<Bool> {
        Binding(get: { library.errorMessage != nil && setupRecipe == nil },
                set: { if !$0 { library.errorMessage = nil } })
    }

    // MARK: Sections

    @ViewBuilder
    private var searchSection: some View {
        Section("Results") {
            if let results = searchResults {
                if results.isEmpty {
                    Text("No chats match.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { chatRow($0) }
                }
            } else {
                ProgressView()
            }
        }
    }

    @ViewBuilder
    private var recipesSection: some View {
        Section {
            ForEach(library.topRecipes) { recipe in
                Button { run(recipe) } label: {
                    SparkRow(icon: "fork.knife", title: recipe.name, subtitle: recipe.subtitle)
                }
                .buttonStyle(.plain)
            }
            NavigationLink {
                SparkManagerView(
                    library: library,
                    currentThreadID: chatManager.messages.isEmpty ? nil : chatManager.threadID,
                    currentChatPrompt: chatManager.messages.first(where: { $0.sender == .user })?.text,
                    onStartRun: onStartRun,
                    onOpenThread: onOpenThread
                )
            } label: {
                Text("All recipes, schedules and runs")
                    .font(.subheadline)
                    .foregroundStyle(BrandColors.teal)
            }
        } header: {
            Text("Your Recipes")
        }
    }

    @ViewBuilder
    private var runsSection: some View {
        if !library.runs.isEmpty {
            Section("Runs") {
                ForEach(library.runs.prefix(3)) { run in
                    SparkRunRow(run: run, onOpen: onOpenThread)
                }
            }
        }
    }

    @ViewBuilder
    private var conversationsSection: some View {
        Section("Your Conversations") {
            if chatManager.isLoadingChats && chatManager.chats.isEmpty {
                ProgressView()
            } else if let error = chatManager.chatListError, chatManager.chats.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Couldn't load chats")
                        .font(.subheadline.weight(.semibold))
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Try again") { Task { await chatManager.fetchChats() } }
                }
            } else if chatManager.chats.isEmpty {
                Text("Your conversations will show up here.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(chatManager.chats) { chatRow($0) }
                if chatManager.hasOlderChats {
                    Button {
                        Task { await chatManager.loadOlderChats() }
                    } label: {
                        HStack {
                            Text("Show older chats")
                            if chatManager.isLoadingChats { ProgressView() }
                        }
                        .foregroundStyle(BrandColors.teal)
                    }
                }
            }
        }
    }

    private func chatRow(_ item: ChatSummary) -> some View {
        Button {
            onOpenThread(item.id)
        } label: {
            HStack(spacing: 8) {
                if item.run?.recipeID != nil {
                    Image(systemName: "fork.knife")
                        .font(.caption)
                        .foregroundStyle(BrandColors.teal)
                        .accessibilityLabel("Made by a recipe")
                }
                ChatListRow(item: item)
            }
        }
        .buttonStyle(.plain)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                Task { await chatManager.deleteChat(threadID: item.id) }
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    /// Runs right away unless the recipe needs an area or a market focus.
    private func run(_ recipe: SparkRecipe) {
        if recipe.needsArea || recipe.segment?.asks == true {
            setupRecipe = recipe
            return
        }
        Task {
            if let prepared = await library.prepareRun(recipe, geo: "", segmentValues: []) {
                onStartRun(prepared)
            }
        }
    }
}

// MARK: - Manager

/// Recipes, Schedules and Runs: the web's recipe manager.
struct SparkManagerView: View {
    @ObservedObject var library: SparkLibraryModel
    /// The open chat, for "From this chat" and for a schedule's origin.
    let currentThreadID: String?
    let currentChatPrompt: String?
    let onStartRun: (PreparedRecipeRun) -> Void
    let onOpenThread: (String) -> Void

    /// One sheet asks what a recipe needs, for a run or a schedule.
    private struct SetupRequest: Identifiable {
        let recipe: SparkRecipe
        let purpose: RecipeSetupSheet.Purpose
        var id: String { recipe.id + (purpose == .run ? "#run" : "#schedule") }
    }

    private enum Tab: String, CaseIterable, Identifiable {
        case recipes = "Recipes", schedules = "Schedules", runs = "Runs"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .recipes
    @State private var showingNewRecipe = false
    @State private var pickingRecipeToSchedule = false
    @State private var setup: SetupRequest?
    @State private var renaming: SparkRecipe?
    @State private var renameText = ""

    var body: some View {
        List {
            Section {
                Picker("Show", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if !library.loggedIn {
                Section {
                    Text("Sign out and back in to see your recipes and schedules on this device.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            switch tab {
            case .recipes: recipesTab
            case .schedules: schedulesTab
            case .runs: runsTab
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(tab.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await library.refresh() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showingNewRecipe = true } label: {
                        Label("New recipe", systemImage: "plus")
                    }
                    Button { pickingRecipeToSchedule = true } label: {
                        Label("New schedule", systemImage: "calendar.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New")
            }
        }
        .sheet(isPresented: $showingNewRecipe) {
            NavigationStack {
                NewRecipeSheet(library: library, currentThreadID: currentThreadID, currentChatPrompt: currentChatPrompt)
            }
        }
        .sheet(isPresented: $pickingRecipeToSchedule) {
            NavigationStack {
                RecipePickerSheet(recipes: library.recipes, starters: library.starters) { picked in
                    pickingRecipeToSchedule = false
                    // Let the picker finish closing before the next sheet opens.
                    Task {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                        setup = SetupRequest(recipe: picked, purpose: .schedule)
                    }
                }
            }
        }
        .sheet(item: $setup) { request in
            NavigationStack {
                RecipeSetupSheet(recipe: request.recipe, purpose: request.purpose, catalog: library.catalog) { geo, values, cadence in
                    switch request.purpose {
                    case .run:
                        guard let prepared = await library.prepareRun(request.recipe, geo: geo, segmentValues: values) else {
                            let message = library.errorMessage ?? "Couldn't start this recipe."
                            library.errorMessage = nil
                            return message
                        }
                        onStartRun(prepared)
                        return nil
                    case .schedule:
                        let error = await library.schedule(request.recipe, cadence: cadence, geo: geo,
                                                           segmentValues: values, threadID: currentThreadID)
                        if error == nil { tab = .schedules }
                        return error
                    }
                }
            }
        }
        .alert("Rename recipe", isPresented: renameShowing) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let recipe = renaming {
                    Task { await library.rename(recipe, to: renameText) }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .alert("Spark", isPresented: noticeShowing) {
            Button("OK", role: .cancel) {
                library.notice = nil
                library.errorMessage = nil
            }
        } message: {
            Text(library.errorMessage ?? library.notice ?? "")
        }
    }

    private var renameShowing: Binding<Bool> {
        Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })
    }

    private var noticeShowing: Binding<Bool> {
        Binding(
            get: { (library.notice != nil || library.errorMessage != nil) && setup == nil && !showingNewRecipe },
            set: { if !$0 { library.notice = nil; library.errorMessage = nil } }
        )
    }

    // MARK: Tabs

    @ViewBuilder
    private var recipesTab: some View {
        Section("Your recipes") {
            if library.recipes.isEmpty {
                Button { showingNewRecipe = true } label: {
                    Label("New recipe", systemImage: "plus")
                }
            }
            ForEach(library.recipes) { recipe in
                Button { run(recipe) } label: {
                    SparkRow(icon: "fork.knife", title: recipe.name, subtitle: recipeSubtitle(recipe))
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await library.delete(recipe) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button { run(recipe) } label: { Label("Run", systemImage: "play") }
                    Button { setup = SetupRequest(recipe: recipe, purpose: .schedule) } label: { Label("Schedule this", systemImage: "calendar.badge.plus") }
                    Button {
                        renameText = recipe.name
                        renaming = recipe
                    } label: { Label("Rename", systemImage: "pencil") }
                    Button(role: .destructive) {
                        Task { await library.delete(recipe) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
        }
        if !library.starters.isEmpty {
            Section {
                ForEach(library.starters) { starter in
                    Button { run(starter) } label: {
                        SparkRow(icon: "sparkles", title: starter.name, subtitle: starter.subtitle)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button { run(starter) } label: { Label("Run", systemImage: "play") }
                        Button {
                            Task { await library.fork(starter) }
                        } label: { Label("Add to my recipes", systemImage: "plus") }
                        Button { setup = SetupRequest(recipe: starter, purpose: .schedule) } label: { Label("Schedule this", systemImage: "calendar.badge.plus") }
                    }
                }
            } header: {
                Text("Start from a template")
            } footer: {
                Text("Touch and hold a recipe to schedule, rename or delete it.")
            }
        }
    }

    @ViewBuilder
    private var schedulesTab: some View {
        Section {
            if library.schedules.isEmpty {
                Text("Nothing scheduled. Pick a recipe and Spark emails it each time new data lands.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            ForEach(library.schedules) { schedule in
                SparkScheduleRow(
                    schedule: schedule,
                    isRunning: library.runningNowID == schedule.id,
                    onToggle: { active in Task { await library.setActive(schedule, active) } },
                    onOpen: onOpenThread
                )
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { await library.delete(schedule) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        Task { await library.runNow(schedule) }
                    } label: { Label("Run now", systemImage: "paperplane") }
                    Button {
                        Task { await library.setActive(schedule, !schedule.active) }
                    } label: {
                        Label(schedule.active ? "Pause" : "Resume", systemImage: schedule.active ? "pause" : "play")
                    }
                    Button(role: .destructive) {
                        Task { await library.delete(schedule) }
                    } label: { Label("Delete", systemImage: "trash") }
                }
            }
            Button { pickingRecipeToSchedule = true } label: {
                Label("New schedule", systemImage: "calendar.badge.plus")
            }
        } footer: {
            Text("Weekly schedules run when the weekly data lands, monthly ones when the monthly data does. Touch and hold to run now.")
        }
    }

    @ViewBuilder
    private var runsTab: some View {
        Section {
            if library.runs.isEmpty {
                Text("No runs yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(library.runs) { run in
                SparkRunRow(run: run, onOpen: onOpenThread)
            }
        }
    }

    /// Runs right away unless the recipe needs an area or a market focus.
    private func run(_ recipe: SparkRecipe) {
        if recipe.needsArea || recipe.segment?.asks == true {
            setup = SetupRequest(recipe: recipe, purpose: .run)
            return
        }
        Task {
            if let prepared = await library.prepareRun(recipe, geo: "", segmentValues: []) {
                onStartRun(prepared)
            }
        }
    }

    private func recipeSubtitle(_ recipe: SparkRecipe) -> String {
        let formats = recipe.formats.isEmpty ? "Answer" : recipe.formats.map { $0.capitalized }.joined(separator: ", ")
        let runs = recipe.uses == 0 ? "not run yet" : recipe.uses == 1 ? "1 run" : "\(recipe.uses) runs"
        let last = SparkDates.ago(recipe.lastUsed)
        return [formats, runs, last.isEmpty ? nil : "last \(last)"].compactMap { $0 }.joined(separator: " · ")
    }
}

// MARK: - Rows

private struct SparkRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(BrandColors.teal)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

private struct SparkRunRow: View {
    let run: SparkRun
    let onOpen: (String) -> Void

    private var icon: String {
        switch run.status {
        case "failed": return "exclamationmark.triangle"
        case "running": return "clock"
        default: return run.trigger == "manual" ? "play.circle" : "calendar"
        }
    }

    var body: some View {
        Button {
            if run.canOpen, let thread = run.threadID { onOpen(thread) }
        } label: {
            SparkRow(icon: icon, title: run.recipeName, subtitle: run.subtitle)
                .opacity(run.canOpen ? 1 : 0.6)
        }
        .buttonStyle(.plain)
        .disabled(!run.canOpen)
    }
}

private struct SparkScheduleRow: View {
    let schedule: SparkSchedule
    let isRunning: Bool
    let onToggle: (Bool) -> Void
    let onOpen: (String) -> Void

    private var detail: String {
        var parts = [schedule.cadenceLabel, schedule.geoLabel.isEmpty ? "Indiana" : schedule.geoLabel]
        if !schedule.active { parts.append("paused") }
        return parts.joined(separator: " · ")
    }

    private var lastLine: String? {
        let ago = SparkDates.ago(schedule.lastRun)
        guard !ago.isEmpty else { return nil }
        return (schedule.lastStatus ?? "").hasPrefix("failed") ? "Failed \(ago)" : "Ran \(ago)"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                if let thread = schedule.lastThreadID, !thread.isEmpty { onOpen(thread) }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(schedule.recipeName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isRunning {
                        Text("Running now…")
                            .font(.caption2)
                            .foregroundStyle(BrandColors.teal)
                    } else if let lastLine {
                        Text(lastLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Toggle("Active", isOn: Binding(get: { schedule.active }, set: onToggle))
                .labelsHidden()
                .tint(BrandColors.teal)
        }
    }
}

// MARK: - Sheets

/// Asks what a recipe needs before it runs or gets scheduled: the area, the
/// market focus, and for a schedule the cadence.
struct RecipeSetupSheet: View {
    enum Purpose { case run, schedule }

    let recipe: SparkRecipe
    let purpose: Purpose
    let catalog: SparkSegmentCatalog?
    /// Returns an error to show, or nil when it worked.
    let onSubmit: @MainActor (_ geo: String, _ segmentValues: [String], _ cadence: String) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var geo = ""
    @State private var selected: Set<String> = []
    @State private var cadence = "monthly"
    @State private var working = false
    @State private var error: String?
    @State private var didSeed = false

    private var asksSegment: Bool { recipe.segment?.asks == true }

    private var canSubmit: Bool {
        if working { return false }
        if recipe.needsArea && geo.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
        if asksSegment && selected.isEmpty { return false }
        return true
    }

    var body: some View {
        Form {
            if recipe.needsArea {
                Section("Area") {
                    TextField("County, ZIP or town", text: $geo)
                        .textInputAutocapitalization(.words)
                }
            } else if purpose == .schedule, let fixed = recipe.geoLabel, !fixed.isEmpty {
                Section("Area") { Text(fixed) }
            }

            if asksSegment, let segment = recipe.segment {
                Section(catalog?.segments[segment.concept]?.label ?? "Market focus") {
                    ForEach(segmentOptions(segment)) { option in
                        Button {
                            if selected.contains(option.value) {
                                selected.remove(option.value)
                            } else {
                                selected.insert(option.value)
                            }
                        } label: {
                            HStack {
                                Text(option.label).foregroundStyle(.primary)
                                Spacer()
                                if selected.contains(option.value) {
                                    Image(systemName: "checkmark").foregroundStyle(BrandColors.teal)
                                }
                            }
                        }
                    }
                }
            }

            if purpose == .schedule {
                Section {
                    Picker("How often", selection: $cadence) {
                        Text("Monthly").tag("monthly")
                        Text("Weekly").tag("weekly")
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("How often")
                } footer: {
                    Text(cadence == "weekly"
                         ? "Emailed each week when the weekly data lands."
                         : "Emailed each month when the monthly data lands.")
                }
            }

            if let error {
                Section {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(recipe.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if working {
                    ProgressView()
                } else {
                    Button(purpose == .run ? "Run" : "Schedule") { submit() }
                        .disabled(!canSubmit)
                }
            }
        }
        .onAppear {
            guard !didSeed else { return }
            didSeed = true
            geo = recipe.exampleGeo ?? ""
            selected = Set(recipe.segment?.values ?? [])
        }
    }

    /// Labeled values from the catalog, or the recipe's raw values if the
    /// catalog hasn't loaded.
    private func segmentOptions(_ segment: SparkRecipeSegment) -> [SparkSegmentOption] {
        let fromCatalog = catalog?.options(for: segment.concept) ?? []
        if !fromCatalog.isEmpty { return fromCatalog }
        return segment.values.map { SparkSegmentOption(value: $0, label: $0) }
    }

    private func submit() {
        working = true
        error = nil
        let area = geo.trimmingCharacters(in: .whitespacesAndNewlines)
        let values = Array(selected).sorted()
        Task {
            let problem = await onSubmit(recipe.needsArea ? area : "", asksSegment ? values : [], cadence)
            working = false
            if let problem {
                error = problem
            } else {
                dismiss()
            }
        }
    }
}

/// "New recipe": describe it, or turn the open chat's question into one.
private struct NewRecipeSheet: View {
    @ObservedObject var library: SparkLibraryModel
    let currentThreadID: String?
    let currentChatPrompt: String?

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var working = false
    @State private var error: String?

    var body: some View {
        Form {
            Section {
                TextField("A monthly email on prices and inventory for a county", text: $text, axis: .vertical)
                    .lineLimit(3...8)
            } header: {
                Text("Describe it")
            } footer: {
                Text("Spark writes the recipe. Leave the place general and it asks for one each run.")
            }
            if let prompt = currentChatPrompt, let thread = currentThreadID {
                Section("Or start from this chat") {
                    Button {
                        create(prompt, threadID: thread)
                    } label: {
                        Text(prompt)
                            .lineLimit(3)
                            .foregroundStyle(.primary)
                    }
                    .disabled(working)
                }
            }
            if let error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("New recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if working {
                    ProgressView()
                } else {
                    Button("Create") { create(text, threadID: nil) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func create(_ description: String, threadID: String?) {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        working = true
        error = nil
        Task {
            let ok = await library.createRecipe(describing: trimmed, threadID: threadID)
            working = false
            if ok {
                dismiss()
            } else {
                error = library.errorMessage
                library.errorMessage = nil
            }
        }
    }
}

/// Picks the recipe a new schedule runs.
private struct RecipePickerSheet: View {
    let recipes: [SparkRecipe]
    let starters: [SparkRecipe]
    let onPick: (SparkRecipe) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if !recipes.isEmpty {
                Section("Your recipes") {
                    ForEach(recipes) { recipe in
                        Button { onPick(recipe) } label: {
                            SparkRow(icon: "fork.knife", title: recipe.name, subtitle: recipe.subtitle)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !starters.isEmpty {
                Section("Templates") {
                    ForEach(starters) { starter in
                        Button { onPick(starter) } label: {
                            SparkRow(icon: "sparkles", title: starter.name, subtitle: starter.subtitle)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("Schedule a recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
    }
}
