//
//  HubCacheWarm.swift
//  ReportsApp
//
//  App-only: the watch shares HubCache but not the dashboard or insights.
//

import Foundation

// MARK: - Warming favorites

extension HubCache {
    /// After launch: the dashboard, insights and charts for the member's
    /// favorite markets, so opening one is instant. Each call goes through
    /// `data(_:family:)`, so nothing is fetched twice and nothing is fetched
    /// at all when the week's data hasn't moved.
    static func warm(geoIDs: [String], vizIDs: [Int]) async {
        for geoID in geoIDs {
            if Task.isCancelled { return }
            _ = try? await DashboardService().fetchTiles(geoID: geoID, vizIDs: vizIDs)
            let insights = await APIService.fetchInsightPreview(geoID: geoID, top: 6)
            _ = await InsightSupport.loadVizData(for: insights)
        }
    }
}
