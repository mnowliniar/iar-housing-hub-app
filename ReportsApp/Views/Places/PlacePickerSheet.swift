//
//  PlacePickerSheet.swift
//  ReportsApp
//
//  The one way to pick a place. A search field with the keyboard up that
//  matches every kind of place at once; before you type, where you are,
//  your markets and the places you opened lately; browse by type under
//  that. One tap picks and the sheet closes.
//

import SwiftUI

// MARK: - The sheet

struct PlacePickerSheet: View {
    var title = "Pick a market"
    /// Places already chosen elsewhere (favorites, pack markets): hidden.
    var excluding: [Int] = []
    /// The place in effect now: shown with a check.
    var current: Int? = nil
    let onPick: (Geo) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var finder = LocationFinder()
    @FocusState private var searchFocused: Bool
    @State private var query = ""
    @State private var top: PlacesTop?
    @State private var results: [Place] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var browsing: PlaceType?
    @State private var browseList: [Place] = []
    @State private var browseLoading = false

    private var trimmedQuery: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchField
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 8)
                List {
                    if !trimmedQuery.isEmpty {
                        searchSection
                    } else if let browsing {
                        browseSection(browsing)
                    } else {
                        mineSection
                        typesSection
                    }
                }
                .listStyle(.insetGrouped)
                .scrollDismissesKeyboard(.immediately)
            }
            .background(HubStyle.page)
            .navigationTitle(browsing?.label ?? title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if browsing != nil && trimmedQuery.isEmpty {
                        Button {
                            browsing = nil
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                    } else {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .task {
                for await loaded in PlacesService.top() {
                    top = loaded
                }
            }
            .onAppear {
                // The keyboard up, as the first thing: most picks are typed.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { searchFocused = true }
            }
            .onChange(of: query) { _, newValue in
                scheduleSearch(newValue)
            }
        }
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("County, ZIP, township, metro…", text: $query)
                .focused($searchFocused)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    if let first = visibleResults.first { pick(first) }
                }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(HubStyle.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(HubStyle.hairline, lineWidth: 1))
    }

    private var visibleResults: [Place] {
        results.filter { !excluding.contains($0.id) }
    }

    private func scheduleSearch(_ text: String) {
        searchTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            searching = false
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            if Task.isCancelled { return }
            let found = await PlacesService.search(q)
            if Task.isCancelled { return }
            results = found
            searching = false
        }
    }

    @ViewBuilder
    private var searchSection: some View {
        Section {
            if trimmedQuery.count < 2 {
                Text("Keep typing…")
                    .foregroundStyle(.secondary)
            } else if searching && visibleResults.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Searching…").foregroundStyle(.secondary)
                }
            } else if visibleResults.isEmpty {
                Text("No place matches “\(trimmedQuery)”.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(visibleResults) { place in
                    row(place)
                }
            }
        }
    }

    // MARK: Before you type

    @ViewBuilder
    private var mineSection: some View {
        let mine = top?.mine
        let favorites = (mine?.favorites ?? []).filter { !excluding.contains($0.id) }
        let recents = (mine?.recents ?? []).filter { !excluding.contains($0.id) }
        let dashboard = mine?.dashboard.flatMap { excluding.contains($0.id) ? nil : $0 }
        let statewide = mine?.statewide.flatMap { excluding.contains($0.id) ? nil : $0 }
        let here = finder.authorized ? finder.here : nil

        if top == nil {
            Section {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Your markets…").foregroundStyle(.secondary)
                }
            }
        } else if here != nil || dashboard != nil || !favorites.isEmpty || statewide != nil || !recents.isEmpty {
            Section("Suggested") {
                if let here, !excluding.contains(here.geoid) {
                    quickRow(icon: "location.fill", title: "You're in \(here.zip)",
                             sub: "\(here.place) · from your location", id: here.geoid) {
                        onPick(Geo(geoid: here.geoid, type: "ZIP Code", name: here.zip, label: here.zip, households: 0))
                        dismiss()
                    }
                }
                if let dashboard {
                    row(dashboard, note: "Your dashboard market", icon: "star.fill")
                }
                ForEach(favorites) { place in
                    row(place, note: "Your market", icon: "star.fill")
                }
                if let statewide {
                    row(statewide, note: "Statewide", icon: "map")
                }
                ForEach(recents) { place in
                    row(place, note: "Recent", icon: "clock")
                }
            }
        }
    }

    // MARK: Browse

    @ViewBuilder
    private var typesSection: some View {
        if let types = top?.types, !types.isEmpty {
            Section("Or browse") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(types) { type in
                            Button {
                                open(type)
                            } label: {
                                Text(type.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(HubStyle.chip, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
    }

    private func open(_ type: PlaceType) {
        browsing = type
        browseList = []
        browseLoading = true
        searchFocused = false
        Task {
            let list = await PlacesService.browse(type: type.id)
            if browsing?.id == type.id {
                browseList = list
                browseLoading = false
            }
        }
    }

    @ViewBuilder
    private func browseSection(_ type: PlaceType) -> some View {
        let list = browseList.filter { !excluding.contains($0.id) }
        Section {
            if browseLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading \(type.label.lowercased())…").foregroundStyle(.secondary)
                }
            } else if list.isEmpty {
                Text("Nothing here yet.").foregroundStyle(.secondary)
            } else {
                ForEach(list) { place in
                    row(place)
                }
            }
        } footer: {
            if let count = type.count, count > 20 {
                Text("Typing is faster: \(count.formatted()) \(type.label.lowercased()) in the Hub.")
            }
        }
    }

    // MARK: Rows

    private func row(_ place: Place, note: String? = nil, icon: String? = nil) -> some View {
        Button {
            pick(place)
        } label: {
            HStack(spacing: 12) {
                badge(text: icon == nil ? place.badge : nil, icon: icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.label)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(note.map { "\($0) · \(place.sub ?? place.type)" } ?? (place.sub ?? place.type))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if place.id == current {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrandColors.teal)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func quickRow(icon: String, title: String, sub: String, id: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                badge(text: nil, icon: icon)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                    Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if id == current {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BrandColors.teal)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func badge(text: String?, icon: String?) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(BrandColors.teal.opacity(0.12))
            if let icon {
                Image(systemName: icon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(BrandColors.teal)
            } else if let text {
                Text(text)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(BrandColors.teal)
            }
        }
        .frame(width: 32, height: 32)
    }

    private func pick(_ place: Place) {
        onPick(place.geo)
        dismiss()
    }
}

// MARK: - The old names, kept so every call site still compiles

/// The dashboard and Market page picker. Picks hand back the geoid as text.
struct GeoPickerSheet: View {
    var current: Int? = nil
    var onSelectGeo: (String) -> Void

    var body: some View {
        PlacePickerSheet(current: current) { geo in
            onSelectGeo(String(geo.geoid))
        }
    }
}

/// Adding a favorite or a pack market: places already added are hidden.
struct FavoriteMarketPickerSheet: View {
    let existingIDs: [Int]
    let onSelect: (Geo) -> Void

    var body: some View {
        PlacePickerSheet(title: "Add a market", excluding: existingIDs, onPick: onSelect)
    }
}
