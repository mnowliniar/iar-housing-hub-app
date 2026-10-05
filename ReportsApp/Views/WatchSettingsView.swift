//
//  WatchSettingsView.swift
//  ReportsApp (watchOS)
//
//  The watch's market picker. One field, which on the wrist means
//  dictation: say "Hamilton" and pick from what the Hub finds. Before you
//  say anything, your markets from the phone. The pick is stored as a
//  number, which is what the data model reads.
//

import SwiftUI

struct WatchSettingsView: View {
    @AppStorage("selectedGeo") private var geoID: Int = 18
    @AppStorage("selectedGeoLabel") private var geoLabel: String = "Indiana"
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var searching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var top: PlacesTop?

    private var trimmed: String { query.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        List {
            Section {
                TextField("Say a county, ZIP or town", text: $query)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            if !trimmed.isEmpty {
                Section("Matches") {
                    if trimmed.count < 2 {
                        Text("Keep going…").foregroundStyle(.secondary)
                    } else if searching && results.isEmpty {
                        ProgressView()
                    } else if results.isEmpty {
                        Text("Nothing matches “\(trimmed)”.").foregroundStyle(.secondary)
                    } else {
                        ForEach(results.prefix(12)) { place in row(place) }
                    }
                }
            } else {
                Section("Suggested") {
                    if let top {
                        let mine = top.mine
                        if let d = mine?.dashboard { row(d) }
                        ForEach((mine?.favorites ?? []).filter { $0.id != mine?.dashboard?.id }) { row($0) }
                        if let s = mine?.statewide { row(s) }
                        ForEach(mine?.recents ?? []) { row($0) }
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .navigationTitle("Market")
        .task {
            for await loaded in PlacesService.top() {
                top = loaded
            }
        }
        .onChange(of: query) { _, newValue in
            schedule(newValue)
        }
    }

    private func row(_ place: Place) -> some View {
        Button {
            geoID = place.id
            geoLabel = place.label
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(place.label).font(.body.weight(.semibold)).lineLimit(1)
                    if place.id == geoID {
                        Spacer()
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
                Text(place.sub ?? place.type).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private func schedule(_ text: String) {
        searchTask?.cancel()
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            results = []
            searching = false
            return
        }
        searching = true
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            let found = await PlacesService.search(q)
            if Task.isCancelled { return }
            results = found
            searching = false
        }
    }
}
