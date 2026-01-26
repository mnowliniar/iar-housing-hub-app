//
//  HomeView.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 9/3/25.
//

// HomeView.swift
import SwiftUI

struct HomeView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1) Dashboard section
                MarketDashboardView(geoID: app.selectedGeoID)

                // 2) Blogs section
                BlogRail()
                // 3) Reports section
                ReportsRail()
            }
            .padding(.vertical, 4)
        }
        .background(
                LinearGradient(
                    colors: [BrandColors.teal.opacity(0.1), BrandColors.purple.opacity(0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
        )
        .navigationTitle("Home")
    }
}

// --- Blog rail (cards share dash style)
struct Blog: Decodable, Identifiable {
    var id: String { slug }
    let title: String
    let thumbnail: String?
    let slug: String
    let blurb: String?
    let pinned: Bool?
}

final class BlogService {
    static func fetch() async throws -> [Blog] {
        let url = URL(string: "https://data.indianarealtors.com/api/research")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let root = try JSONDecoder().decode([String:[Blog]].self, from: data) // { "gresults": [...] }
        return root["gresults"] ?? []
    }
}

struct BlogRail: View {
    @State private var items: [Blog] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest Blogs").font(.headline).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if loading {
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.gray.opacity(0.15))
                                .frame(width: 260, height: 400)
                        }
                    } else {
                        ForEach(items) { b in BlogCard(blog: b) }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
        }
        .task {
            do { items = try await BlogService.fetch() } catch { items = [] }
            loading = false
        }
    }
}

struct BlogCard: View {
    let blog: Blog

    private func absoluteURL(from s: String?) -> URL? {
        guard let s = s, !s.isEmpty else { return nil }
        if s.hasPrefix("http") { return URL(string: s) }
        return URL(string: "https://data.indianarealtors.com" + s)
    }

    var body: some View {
        let thumbURL = absoluteURL(from: blog.thumbnail)
        let linkURL  = absoluteURL(from: blog.slug) ?? URL(string: "https://data.indianarealtors.com")!

        Link(destination: linkURL) {
            ZStack(alignment: .bottomTrailing) {
                VStack(alignment: .leading, spacing: 10) {
                    // Image on top
                    AsyncImage(url: thumbURL) { img in
                        img.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.gray.opacity(0.15))
                    }
                    .frame(height: 140)
                    .clipped()
                    .cornerRadius(8)

                    // Title
                    Text(blog.title)
                        .font(.headline)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    // Blurb
                    if let blurb = blog.blurb, !blurb.isEmpty {
                        Text(blurb)
                            .font(.caption)
                            .lineLimit(3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 0)
                }
                if blog.pinned == true {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .padding(6)
                }
            }
            .padding()
            .frame(width: 260, height: 300, alignment: .topLeading)
            .glassCard(cornerRadius: 12)
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// --- Reports rail (same card style) ---
struct ReportListItem: Decodable, Identifiable {
    let report_id: Int
    let title: String
    let report_date: String
    let update_date: String
    let thumbnail: String?
    var id: Int { report_id }
}

final class ReportsService {
    static func fetch(limit: Int = 12) async throws -> [ReportListItem] {
        var comps = URLComponents(string: "https://data.indianarealtors.com/app/reports/latest/")!
        comps.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        let (data, _) = try await URLSession.shared.data(from: comps.url!)
        return try JSONDecoder().decode([ReportListItem].self, from: data)
    }
}

struct ReportsRail: View {
    @State private var items: [ReportListItem] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Latest Reports").font(.headline).padding(.horizontal)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    if loading {
                        ForEach(0..<3) { _ in
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.gray.opacity(0.15))
                                .frame(width: 260, height: 100)
                        }
                    } else {
                        ForEach(items) { r in ReportCard(item: r) }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            .scrollClipDisabled()
        }
        .task {
            do { items = try await ReportsService.fetch() } catch { items = [] }
            loading = false
        }
    }
}

struct ReportCard: View {
    let item: ReportListItem

    private func formattedUpdate(_ s: String) -> String {
        // Expecting one of:
        //  - yyyy-MM-dd'T'HH:mm:ss
        //  - yyyy-MM-dd'T'HH:mm:ss.SSS
        //  - (optionally) with timezone suffix (e.g., Z or ±HH:mm)
        let posix = Locale(identifier: "en_US_POSIX")
        let df = DateFormatter()
        df.locale = posix
        df.timeZone = TimeZone(secondsFromGMT: 0)

        var date: Date? = nil
        let fmts = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
        ]
        for f in fmts {
            df.dateFormat = f
            if let d = df.date(from: s) { date = d; break }
        }

        if let d = date {
            let out = DateFormatter()
            out.locale = posix
            out.timeZone = .current
            out.dateFormat = "MMM d 'at' h:mm a"
            return "Updated " + out.string(from: d)
        }

        // Fallback (shouldn't happen): show raw date with T replaced
        return "Updated " + s.replacingOccurrences(of: "T", with: " ")
    }

    var body: some View {
        NavigationLink {
            // Minimal Report stub to satisfy ReportBuilderView
            ReportBuilderView(report: Report(id: item.report_id, title: item.title))
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                // Dates
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.report_date)
                        .font(.caption)
                        .bold()
                    Text(formattedUpdate(item.update_date))
                        .font(.caption2)
                        .opacity(0.9)
                }
                // Title
                Text(item.title)
                    .font(.headline)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding()
            .frame(width: 260, height: 100, alignment: .topLeading)
            .glassCard(cornerRadius: 12, tint: BrandColors.teal)
            // Shadow last
            .shadow(color: Color.black.opacity(0.08), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// Convenience initializer so rails can construct a Report with minimal fields
extension Report {
    init(id: Int, title: String) {
        self.init(id: id, title: title, description: "", category: "", is_protected: false)
    }
}

extension View {
    @ViewBuilder
    func glassCard(
        cornerRadius: CGFloat = 12,
        tint: Color = .clear,
        tintOpacity: Double = 0.18,
        strokeOpacity: Double = 0.25
    ) -> some View {
        if #available(iOS 26.0, *) {
            self
                .glassEffect(
                    .regular,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                // Optional tint layer to nudge color toward brand
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(tintOpacity))
                )
                // Subtle edge to match the glass look
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(strokeOpacity), lineWidth: 1)
                )
        } else {
            // Fallback for iOS < 18
            self
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(tint.opacity(tintOpacity))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(.white.opacity(strokeOpacity), lineWidth: 1)
                )
        }
    }
}
