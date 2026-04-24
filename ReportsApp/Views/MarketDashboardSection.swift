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
        Group {
            if hSize == .compact {
                ZStack(alignment: .topLeading) {
                    LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                        ForEach(0..<min(3, vizIDs.count), id: \.self) { _ in
                            TileCardSkeleton()
                        }
                    }
                    .opacity(showSkeletonTiles ? 1 : 0)

                    LazyVGrid(columns: [GridItem(.flexible())], spacing: 12) {
                        ForEach(tiles) { tile in
                            TileCard(tile: tile)
                                .opacity(showLoadedTiles ? 1 : 0)
                        }
                    }
                }
            } else {
                ZStack(alignment: .topLeading) {
                    if showSkeletonTiles {
                        dashboardWideSkeletonLayout
                            .opacity(showSkeletonTiles ? 1 : 0)
                    }

                    if showLoadedTiles {
                        dashboardWideLoadedLayout
                            .opacity(showLoadedTiles ? 1 : 0)
                    }
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

    private var dashboardWideSkeletonLayout: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 12
            let columnWidth = (geo.size.width - spacing) / 2
            let tileHeight = max(170, columnWidth * 0.42)
            let featuredHeight = tileHeight * 2 + spacing

            HStack(alignment: .top, spacing: spacing) {
                VStack(spacing: spacing) {
                    TileCardSkeleton()
                        .frame(height: tileHeight)
                    TileCardSkeleton()
                        .frame(height: tileHeight)
                }
                .frame(width: columnWidth)

                TileCardSkeleton()
                    .frame(width: columnWidth, height: featuredHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .frame(height: 300)
    }

    @ViewBuilder
    private var dashboardWideLoadedLayout: some View {
        if tiles.count >= 3 {
            GeometryReader { geo in
                let spacing: CGFloat = 12
                let columnWidth = (geo.size.width - spacing) / 2
                let tileHeight = max(170, columnWidth * 0.42)
                let featuredHeight = tileHeight * 2 + spacing

                HStack(alignment: .top, spacing: spacing) {
                    VStack(spacing: spacing) {
                        TileCard(tile: tiles[0])
                            .frame(height: tileHeight)
                        TileCard(tile: tiles[1])
                            .frame(height: tileHeight)
                    }
                    .frame(width: columnWidth)

                    TileCard(tile: tiles[2])
                        .frame(width: columnWidth, height: featuredHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
            .frame(height: 300)
        } else {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(tiles) { tile in
                    TileCard(tile: tile)
                }
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
