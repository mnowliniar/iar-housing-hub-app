//
//  WatchSettingsView.swift
//  ReportsApp (watchOS)
//
//  Created by Matt Nowlin on 8/27/25.
//
import SwiftUI

// Minimal models to mirror your existing selector flow
struct GeoType: Identifiable, Hashable { let id: String; let name: String }
struct GeoItem: Identifiable, Hashable { let id: String; let name: String }

@MainActor
final class GeoSelectorVM: ObservableObject {
    @Published var types: [GeoType] = []
    @Published var geos: [GeoItem] = []
    @Published var selectedTypeID: String = "" {
        didSet { Task { await loadGeos(for: selectedTypeID) } }
    }
    @Published var isLoading = false

    // Persist the last used type for convenience
    @AppStorage("selectedGeoType") private var storedTypeID: String = ""

    func load() async {
        guard !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            // Assumes you have these APIs from the iOS selector
            let fetchedTypes = try await APIService.fetchGeoTypes() // [String] or [ (id:String, name:String) ]
            // If fetchGeoTypes() returns [String], use the string for both id and name
            self.types = fetchedTypes.map { GeoType(id: $0, name: $0) }

            // Prefer stored type; else first
            if let first = types.first?.id {
                let initial = storedTypeID.isEmpty ? first : storedTypeID
                selectedTypeID = initial
            }
        } catch {
            // Fallback: at least offer State as a type
            self.types = [GeoType(id: "state", name: "State")]
            selectedTypeID = "state"
        }
    }

    func loadGeos(for typeID: String) async {
        guard !typeID.isEmpty else { return }
        isLoading = true; defer { isLoading = false }
        let fetched = await APIService.fetchGeos(ofType: typeID) // [ (id:String, name:String) ]
        self.geos = fetched.map { GeoItem(id: String($0.id), name: $0.name) }
        storedTypeID = typeID
    }
}

struct WatchSettingsView: View {
    // Persist the chosen geo id so MonthlyVM picks it up
    @AppStorage("selectedGeo") private var geoID: String = "18"
    @StateObject private var vm = GeoSelectorVM()

    var body: some View {
        List {
            // Type picker
            if !vm.types.isEmpty {
                Picker("Type", selection: $vm.selectedTypeID) {
                    ForEach(vm.types) { t in
                        Text(t.name).tag(t.id)
                    }
                }
            }

            // Geo picker (populated after type loads)
            if vm.geos.isEmpty {
                HStack { ProgressView(); Text("Loading areas…").font(.caption2).foregroundColor(.secondary) }
            } else {
                Picker("Area", selection: $geoID) {
                    ForEach(vm.geos) { g in
                        Text(g.name).tag(g.id)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .task { await vm.load() }
        .onChange(of: vm.selectedTypeID) { _ in /* handled in didSet */ }
        .onChange(of: vm.geos) { geos in
            if !geos.contains(where: { $0.id == geoID }), let first = geos.first?.id {
                geoID = first
            }
        }
    }
}
