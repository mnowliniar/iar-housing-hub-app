//
//  NewChatWelcome.swift
//  ReportsApp
//
//  The empty Spark screen. No market is guessed: the place belongs in the
//  question. Three starters true this week, each naming its own market;
//  the member's most-used recipe; market chips that type a name into the
//  box; the last few chats.
//

import SwiftUI

struct SparkStarter: Decodable, Identifiable, Hashable {
    let geoID: Int
    let market: String
    let text: String
    let kind: String

    var id: String { "\(geoID)-\(text)" }

    /// "This week · Hamilton County" or "Try · 46220".
    var eyebrow: String {
        (kind == "data" ? "This week" : "Try") + " · " + market
    }

    enum CodingKeys: String, CodingKey {
        case market, text, kind
        case geoID = "geo_id"
    }
}

struct NewChatWelcome: View {
    let starters: [SparkStarter]
    let recipe: SparkRecipe?
    let places: [Place]
    let recents: [ChatSummary]
    let onStarter: (String) -> Void
    let onRecipe: (SparkRecipe) -> Void
    let onPlace: (String) -> Void
    let onRecent: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("What do you want to know?")
                    .font(.title2.weight(.bold))
                Text("Name any county, ZIP or township in the question. Spark already knows your markets.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)

            ForEach(starters) { starter in
                starterCard(eyebrow: starter.eyebrow, text: starter.text) {
                    onStarter(starter.text)
                }
            }

            if let recipe {
                starterCard(eyebrow: recipeEyebrow(recipe), text: recipe.name, icon: "sparkles") {
                    onRecipe(recipe)
                }
            }

            if !places.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HubSectionHeader(title: "Your markets · tap to start typing about one")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(places) { place in
                                Button {
                                    onPlace(place.label)
                                } label: {
                                    Text(place.label)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 7)
                                        .background(HubStyle.card, in: Capsule())
                                        .overlay(Capsule().stroke(HubStyle.hairline, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 1)
                    }
                }
            }

            if !recents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HubSectionHeader(title: "Recent chats")
                    VStack(spacing: 0) {
                        ForEach(Array(recents.enumerated()), id: \.element.id) { index, chat in
                            Button {
                                onRecent(chat.threadID)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(chat.name)
                                            .font(.body.weight(.semibold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        if let when = Self.relative(chat.updated ?? chat.created) {
                                            Text(when)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
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
                            if index < recents.count - 1 { Divider() }
                        }
                    }
                    .hubCard(padding: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func starterCard(eyebrow: String, text: String, icon: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(eyebrow.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .tracking(0.4)
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(2)
                }
                Spacer(minLength: 0)
                Image(systemName: icon ?? "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BrandColors.teal)
                    .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .hubCard(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private func recipeEyebrow(_ recipe: SparkRecipe) -> String {
        if recipe.isStarter { return "A recipe to try" }
        switch recipe.uses {
        case 0: return "Your recipe"
        case 1: return "Your recipe · used once"
        default: return "Your recipe · used \(recipe.uses) times"
        }
    }

    /// "Yesterday", "Tuesday", "Sep 12".
    static func relative(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let parsers = [ISO8601DateFormatter(), {
            let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f }()]
        var date: Date?
        for p in parsers {
            if let d = p.date(from: iso) { date = d; break }
        }
        if date == nil {
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
            date = f.date(from: String(iso.prefix(19)).replacingOccurrences(of: "T", with: " "))
        }
        guard let date else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let out = DateFormatter()
        if let week = cal.date(byAdding: .day, value: -6, to: Date()), date > week {
            out.dateFormat = "EEEE"
        } else {
            out.dateFormat = "MMM d"
        }
        return out.string(from: date)
    }
}
