//
//  ReportBuilderView.swift
//  ReportsApp
//
//  Opening a report. It arrives filled in: your dashboard market and the
//  latest edition, one tap to open. The market row opens the one place
//  picker. Under that, the same report for each of your markets, one tap.
//

import SwiftUI

struct ReportBuilderView: View {
    let report: Report
    var onViewReport: ((ActiveReport) -> Void)? = nil

    @EnvironmentObject var app: AppState
    @State private var geo: Geo?
    @State private var dates: [ReportDate] = []
    @State private var selectedDate: ReportDate?
    @State private var myPlaces: [Place] = []
    @State private var pickingMarket = false
    @State private var opening: ActiveReport?
    @State private var showOpening = false

    private var latestDate: ReportDate? {
        dates.max(by: { $0.update_date_only < $1.update_date_only })
    }

    private var dashboardGeoID: Int {
        Int(app.userPrefs.app.dashboardGeoID ?? "") ?? 18
    }

    private var ready: Bool { geo != nil && selectedDate != nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                about
                settings
                openButton
                yourMarkets
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .hubPage()
        .navigationTitle(report.title)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pickingMarket) {
            PlacePickerSheet(current: geo?.geoid) { picked in
                geo = picked
            }
        }
        .navigationDestination(isPresented: $showOpening) {
            if let active = opening {
                ReportDetailView(report: active.report, geo: active.geo, updateDate: active.updateDate)
            }
        }
        .task {
            async let dateList = APIService.fetchReportDates(reportID: report.id)
            async let dashboard = APIService.fetchGeo(geoid: String(dashboardGeoID))
            let (list, home) = await (dateList, dashboard)
            dates = list
            if selectedDate == nil { selectedDate = latestDate }
            if geo == nil { geo = home }
            for await top in PlacesService.top() {
                var places: [Place] = []
                if let d = top.mine?.dashboard { places.append(d) }
                places.append(contentsOf: top.mine?.favorites ?? [])
                if let s = top.mine?.statewide { places.append(s) }
                myPlaces = places
            }
        }
    }

    // MARK: Sections

    private var about: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let meta = report.metaLine {
                Text(meta.uppercased())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.4)
            }
            if !report.description.isEmpty {
                Text(report.description)
                    .font(.subheadline)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineSpacing(2)
            } else if report.metaLine == nil {
                Text("Pick a market and an edition, then open the report.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hubCard()
    }

    private var settings: some View {
        VStack(spacing: 0) {
            Button {
                pickingMarket = true
            } label: {
                settingRow(label: "Market",
                           value: geo?.displayName ?? "Choosing…",
                           detail: geo?.geoid == dashboardGeoID ? "Your dashboard market · tap to change" : "Tap to change",
                           trailing: "chevron.right")
            }
            .buttonStyle(.plain)

            Divider().padding(.leading, 0)

            Menu {
                ForEach(dates) { date in
                    Button {
                        selectedDate = date
                    } label: {
                        if date == selectedDate {
                            Label(date.displayName, systemImage: "checkmark")
                        } else {
                            Text(date.displayName)
                        }
                    }
                }
            } label: {
                settingRow(label: editionWord,
                           value: selectedDate?.displayName ?? (dates.isEmpty ? "Loading…" : "Choose"),
                           detail: editionDetail,
                           trailing: "chevron.up.chevron.down")
            }
            .disabled(dates.isEmpty)
        }
        .hubCard(padding: 0)
    }

    private var editionWord: String {
        switch report.cadence {
        case "Weekly": return "Week"
        case "Monthly": return "Month"
        case "Daily": return "Day"
        case "Annual": return "Year"
        default: return "Edition"
        }
    }

    private var editionDetail: String {
        guard !dates.isEmpty else { return "" }
        let earlier = max(dates.count - 1, 0)
        if selectedDate == latestDate {
            return earlier == 0 ? "Latest" : "Latest · \(earlier) earlier"
        }
        return "Tap for the latest"
    }

    private func settingRow(label: String, value: String, detail: String, trailing: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Image(systemName: trailing)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var openButton: some View {
        Button {
            guard let geo, let selectedDate else { return }
            open(ActiveReport(report: report, geo: geo, updateDate: selectedDate.update_date_only))
        } label: {
            HStack {
                Spacer()
                if ready {
                    Text("Open report")
                } else {
                    ProgressView().tint(.white)
                }
                Spacer()
            }
            .font(.body.weight(.semibold))
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .background(BrandColors.teal, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!ready)
    }

    @ViewBuilder
    private var yourMarkets: some View {
        let others = myPlaces.filter { $0.id != geo?.geoid }
        if !others.isEmpty, let latest = latestDate {
            VStack(alignment: .leading, spacing: 8) {
                HubSectionHeader(title: "Your markets · \(latest.displayName)")
                VStack(spacing: 0) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { index, place in
                        Button {
                            open(ActiveReport(report: report, geo: place.geo, updateDate: latest.update_date_only))
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.label)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(place.sub ?? place.type)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        if index < others.count - 1 { Divider() }
                    }
                }
                .hubCard(padding: 0)
            }
        }
    }

    /// The report page counts the view; nothing to fire here.
    private func open(_ active: ActiveReport) {
        if let onViewReport {
            onViewReport(active)
        } else {
            opening = active
            showOpening = true
        }
    }
}
