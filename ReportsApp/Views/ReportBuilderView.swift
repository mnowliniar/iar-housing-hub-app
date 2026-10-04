import SwiftUI

struct ReportBuilderView: View {
    let report: Report
    var onViewReport: ((ActiveReport) -> Void)? = nil

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
                    if let onViewReport {
                        Button("View Report") {
                            onViewReport(ActiveReport(
                                report: report,
                                geo: selectedGeo,
                                updateDate: selectedDate.update_date_only
                            ))
                        }
                        .font(.headline)
                    } else {
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
