//
//  HubStyle.swift
//  ReportsApp
//
//  The app's one look, taken from the insight card: a flat page, white
//  cards with a hairline and a soft shadow, small-caps section headers,
//  numbers in tabular figures, teal for the one line that matters. The
//  gradient backgrounds and the glass effect are gone.
//

import SwiftUI

enum HubStyle {
    /// The widest a page gets on an iPad before it is centered.
    static let readableWidth: CGFloat = 820

    /// The page behind every screen. Adapts to dark mode.
    static let page = Color(.systemGroupedBackground)
    /// A card on the page.
    static let card = Color(.secondarySystemGroupedBackground)
    /// The line around a card.
    static let hairline = Color.primary.opacity(0.08)
    /// Grid lines inside a chart.
    static let grid = Color.primary.opacity(0.07)
    /// The faint fill behind a chip.
    static let chip = Color(.tertiarySystemFill)
    static let cornerRadius: CGFloat = 16
}

extension View {
    /// The flat page background, in place of the teal-to-purple gradient.
    func hubPage() -> some View {
        background(HubStyle.page.ignoresSafeArea())
    }

    /// One readable column on a wide screen. The phone's pages are built for
    /// a phone's width; on an iPad they sit centered at this width instead
    /// of stretching across the window.
    func hubReadable(_ width: CGFloat = HubStyle.readableWidth) -> some View {
        frame(maxWidth: width)
            .frame(maxWidth: .infinity)
    }

    /// A card: padding, white, a hairline, a soft shadow.
    func hubCard(padding: CGFloat = 16, cornerRadius: CGFloat = HubStyle.cornerRadius) -> some View {
        self
            .padding(padding)
            .background(HubStyle.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(HubStyle.hairline, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
    }
}

/// The one section header: small caps, like "YOUR REPORTS", with room for
/// a trailing link.
struct HubSectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            trailing()
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandColors.teal)
        }
    }
}

extension HubSectionHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}
