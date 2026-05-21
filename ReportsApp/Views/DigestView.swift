import SwiftUI
import UserNotifications

struct DigestView: View {
    @EnvironmentObject var app: AppState
    @State private var digest: DigestResponse?
    @State private var isLoading = false
    @State private var geoCache: [Int: Geo] = [:]

    var body: some View {
        Group {
            if isLoading && digest == nil {
                ProgressView("Loading digest…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let digest {
                List {
                    if !digest.subscriptions.isEmpty {
                        subscriptionsSection(digest.subscriptions)
                    }
                    digestSection(digest.digest)
                }
                .listStyle(.insetGrouped)
            } else {
                ContentUnavailableView(
                    "No Digest",
                    systemImage: "bell.slash",
                    description: Text("Add favorite markets and reports to see your digest.")
                )
            }
        }
        .navigationTitle("My Digest")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Test Notification") {
                    let isWeekly = Bool.random()
                    let content = UNMutableNotificationContent()
                    content.title = isWeekly ? "Your Weekly Digest" : "Your Monthly Digest"
                    content.body = "Your Indiana housing market digest is ready."
                    content.sound = .default
                    content.userInfo = ["destination": "digest"]
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
                    let request = UNNotificationRequest(identifier: "digest.test", content: content, trigger: trigger)
                    UNUserNotificationCenter.current().add(request)
                }
                .font(.caption)
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    // MARK: - Sections

    @ViewBuilder
    private func subscriptionsSection(_ groups: [SubscriptionGroup]) -> some View {
        Section("My Subscriptions") {
            ForEach(groups) { group in
                ForEach(group.markets) { market in
                    SubscriptionRow(
                        group: group,
                        market: market,
                        onToggle: { await toggleSubscription(geoID: market.geoID, reportID: group.reportID, proptype: market.propertyType) }
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func digestSection(_ groups: [DigestGroup]) -> some View {
        ForEach(groups) { group in
            Section(group.date) {
                ForEach(group.reports) { report in
                    ForEach(report.markets) { market in
                        DigestMarketRow(
                            report: report,
                            market: market,
                            geo: market.geoIDInt.flatMap { geoCache[$0] },
                            onOpen: { openReport(report: report, market: market) },
                            onToggle: { await toggleSubscription(geoID: market.geoID, reportID: report.reportID, proptype: market.proptype) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        digest = await APIService.fetchDigest()
        await prefetchGeos()
    }

    private func prefetchGeos() async {
        var ids: Set<Int> = []
        if let digest {
            for group in digest.digest {
                for report in group.reports {
                    for market in report.markets {
                        if let id = market.geoIDInt { ids.insert(id) }
                    }
                }
            }
        }
        for id in ids where geoCache[id] == nil {
            if let geo = await APIService.fetchGeo(geoid: String(id)) {
                geoCache[id] = geo
            }
        }
    }

    private func openReport(report: DigestReportEntry, market: DigestMarket) {
        guard let geo = market.geoIDInt.flatMap({ geoCache[$0] }) else { return }
        app.activeReport = ActiveReport(
            report: Report(id: report.reportID, title: report.title),
            geo: geo,
            updateDate: ""
        )
    }

    private func toggleSubscription(geoID: String, reportID: Int, proptype: String) async {
        let nowSubscribed = await APIService.toggleDigestSubscription(geoID: geoID, reportID: reportID, proptype: proptype)
        // Optimistically update local state
        guard var current = digest else { return }
        if nowSubscribed {
            // Add to subscriptions if not already there
            var groups = current.subscriptions
            let idx = groups.firstIndex(where: { $0.reportID == reportID })
            if let idx {
                if !groups[idx].markets.contains(where: { $0.geoID == geoID }) {
                    let newMarket = SubscriptionMarket(geoID: geoID, geoLabel: "", propertyType: proptype, updateDate: nil)
                    groups[idx] = SubscriptionGroup(reportID: groups[idx].reportID, reportTitle: groups[idx].reportTitle, markets: groups[idx].markets + [newMarket])
                }
            }
        }
        // Refresh to get accurate state
        digest = await APIService.fetchDigest()
    }
}

// MARK: - Row Views

private struct SubscriptionRow: View {
    let group: SubscriptionGroup
    let market: SubscriptionMarket
    let onToggle: () async -> Void

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 3) {
                Text(market.geoLabel)
                    .font(.body)
                Text(group.reportTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let updated = market.formattedUpdateDate {
                    Text(updated)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                Task { await onToggle() }
            } label: {
                Image(systemName: "bell.fill")
                    .foregroundStyle(BrandColors.teal)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}

private struct DigestMarketRow: View {
    let report: DigestReportEntry
    let market: DigestMarket
    let geo: Geo?
    let onOpen: () -> Void
    let onToggle: () async -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(market.label)
                    .font(.body)
                Text(report.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if market.vizCount > 0 {
                    Text("\(market.vizCount) of \(market.vizTotal) charts")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if geo != nil {
                Button("Open", action: onOpen)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .buttonStyle(.plain)
            }
            Button {
                Task { await onToggle() }
            } label: {
                Image(systemName: market.subscribed ? "bell.fill" : "bell")
                    .foregroundStyle(market.subscribed ? BrandColors.teal : .secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }
}
