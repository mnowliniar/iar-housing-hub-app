import SwiftUI

struct ReportBuilderView: View {
    let report: Report

    @State private var geoTypes: [String] = []
    @State private var selectedGeoType: String?
    @State private var geos: [Geo] = []
    @State private var selectedGeo: Geo?
    @State private var dates: [ReportDate] = []
    @State private var selectedDate: ReportDate?

    var body: some View {
        Form {
            Section(header: Text("Step 1: Select Geography Type")) {
                Picker("Geo Type", selection: $selectedGeoType) {
                    Text("Select a geo type").tag(String?.none)
                    ForEach(geoTypes, id: \.self) { type in
                        Text(type).tag(type as String?)
                    }
                }
                .onChange(of: selectedGeoType) { _, _ in
                    Task { await loadGeos() }
                }
            }

            if !geos.isEmpty {
                Section(header: Text("Step 2: Select Geography")) {
                    Picker("Geography", selection: $selectedGeo) {
                        Text("Select a geo").tag(Geo?.none)
                        ForEach(geos) { geo in
                            Text(geo.displayName).tag(geo as Geo?)
                        }
                    }
                }
            }

            if !dates.isEmpty {
                Section(header: Text("Step 3: Select Report Date")) {
                    Picker("Date", selection: $selectedDate) {
                        Text("Select a date").tag(ReportDate?.none)
                        ForEach(dates) { date in
                            Text(date.displayName).tag(date as ReportDate?)
                        }
                    }
                }
            }

            if let selectedGeo = selectedGeo, let selectedDate = selectedDate {
                Section {
                    NavigationLink("View Report") {
                        ReportDetailView(
                            report: report,
                            geo: selectedGeo,
                            updateDate: selectedDate.update_date_only
                        )
                    }
                    .font(.headline)
                }
            }
        }
        .navigationTitle("Build \(report.title)")
        .onAppear {
            Task {
                await loadGeoTypes()
                await loadDates()
            }
        }
    }

    func loadGeoTypes() async {
        geoTypes = await APIService.fetchGeoTypes()
        if selectedGeoType == nil, geoTypes.contains("State") {
            selectedGeoType = "State"
            await loadGeos()
        }
    }

    func loadGeos() async {
        guard let selectedGeoType = selectedGeoType else { return }
        geos = await APIService.fetchGeos(ofType: selectedGeoType)
        if selectedGeo == nil, let indiana = geos.first(where: { $0.displayName == "Indiana" }) {
            selectedGeo = indiana
        }
    }

    func loadDates() async {
        dates = await APIService.fetchReportDates(reportID: report.id)
        if selectedDate == nil {
            selectedDate = dates.max(by: { $0.update_date_only < $1.update_date_only })
        }
    }
}

// Reusable database-driven picker for selecting a market
struct GeoPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onSelectGeo: (String) -> Void

    @State private var types: [String] = []
    @State private var selectedType: String?
    @State private var geos: [Geo] = []
    @State private var selectedGeo: Geo?
    @State private var query: String = ""
    @State private var isLoading: Bool = false

    private var filteredGeos: [Geo] {
        guard !query.isEmpty else { return geos }
        return geos.filter { $0.displayName.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Step 1: Select Geography Type") {
                    Picker("Geo Type", selection: $selectedType) {
                        Text("Select a geo type").tag(String?.none)
                        ForEach(types, id: \.self) { t in Text(t).tag(t as String?) }
                    }
                    .onChange(of: selectedType) { _, _ in Task { await loadGeos() } }
                }

                if !geos.isEmpty {
                    Section("Step 2: Select Geography") {
                        TextField("Search geos", text: $query)
                        Picker("Geography", selection: $selectedGeo) {
                            Text("Select a geo").tag(Geo?.none)
                            ForEach(filteredGeos) { g in Text(g.displayName).tag(g as Geo?) }
                        }
                    }
                }

                if let g = selectedGeo {
                    Section { Button("Use \(g.displayName)") { onSelectGeo(String(g.geoid)); dismiss() } }
                }
            }
            .navigationTitle("Select Market")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Close") { dismiss() } } }
            .task { await initialLoad() }
        }
    }

    // MARK: - Data
    private func initialLoad() async {
        await loadTypes()
        await loadGeos()
    }

    private func loadTypes() async {
        isLoading = true
        let ts = await APIService.fetchGeoTypes()
        types = ts
        if selectedType == nil, ts.contains("State") { selectedType = "State" }
        isLoading = false
    }

    private func loadGeos() async {
        guard let selectedType else { geos = []; selectedGeo = nil; return }
        isLoading = true
        let list = await APIService.fetchGeos(ofType: selectedType)
        geos = list
        if selectedGeo == nil, let indiana = list.first(where: { $0.displayName == "Indiana" }) {
            selectedGeo = indiana
        }
        isLoading = false
    }
}
