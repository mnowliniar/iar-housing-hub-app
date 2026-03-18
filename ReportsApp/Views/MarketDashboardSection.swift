//
//  MarketDashboardSection.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/17/26.
//


import SwiftUI

struct MarketDashboardSection: View {
    @Environment(\.horizontalSizeClass) private var hSize
    @EnvironmentObject var app: AppState

    let geoID: String

    @State private var tiles: [Tile] = []
    @State private var isLoading = true
    @State private var showLoadedTiles = false
    @State private var showSkeletonTiles = true

    private var vizIDs: [Int] {
        let ids = app.userPrefs.app.dashboardVizIDs
        return ids.isEmpty ? [9, 3, 7] : ids
    }

    var body: some View {
        let columns: [GridItem] = (hSize == .compact)
            ? [GridItem(.flexible())]
            : [GridItem(.flexible()), GridItem(.flexible())]

        let skeletonCount = min(3, vizIDs.count)

        ZStack(alignment: .topLeading) {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(0..<skeletonCount, id: \.self) { _ in
                    TileCardSkeleton()
                }
            }
            .opacity(showSkeletonTiles ? 1 : 0)

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tiles) { tile in
                    TileCard(tile: tile)
                        .opacity(showLoadedTiles ? 1 : 0)
                }
            }
        }
        .padding(.horizontal)
        .task {
            await loadTiles()
        }
        .onChange(of: geoID) { _, _ in
            Task {
                await loadTiles()
            }
        }
        .onChange(of: app.userPrefs.app.dashboardVizIDs) { _, _ in
            Task {
                await loadTiles()
            }
        }
    }

    private func loadTiles() async {
        let trimmedID = geoID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else {
            tiles = []
            isLoading = false
            showLoadedTiles = false
            showSkeletonTiles = false
            return
        }

        isLoading = true
        showSkeletonTiles = true
        showLoadedTiles = false

        do {
            let svc = DashboardService()
            let fetched = try await svc.fetchTiles(geoID: trimmedID, vizIDs: vizIDs)
            tiles = Array(fetched.prefix(3))
        } catch {
#if DEBUG
            print("MarketDashboardSection load error:", error)
#endif
            tiles = []
        }

        isLoading = false
        withAnimation(.easeInOut(duration: 0.25)) {
            showLoadedTiles = true
            showSkeletonTiles = false
        }
    }
}
