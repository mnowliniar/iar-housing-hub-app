//
//  SparkMark.swift
//  ReportsApp
//
//  The Spark logo, drawn: a vertical and a horizontal bar through the
//  center and four shorter diagonals that stop short of it, round caps.
//  Drawn rather than a PNG so it is crisp at every size and takes a color.
//

import SwiftUI

struct SparkMarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x / 100 * rect.width, y: rect.minY + y / 100 * rect.height)
        }
        path.move(to: pt(50, 4)); path.addLine(to: pt(50, 96))
        path.move(to: pt(4, 50)); path.addLine(to: pt(96, 50))
        let diagonals: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (14, 14, 39, 39), (86, 14, 61, 39), (14, 86, 39, 61), (86, 86, 61, 61),
        ]
        for (x1, y1, x2, y2) in diagonals {
            path.move(to: pt(x1, y1)); path.addLine(to: pt(x2, y2))
        }
        return path
    }
}

struct SparkMark: View {
    var size: CGFloat = 24
    var color: Color = BrandColors.sparkTeal

    var body: some View {
        SparkMarkShape()
            .stroke(color, style: StrokeStyle(lineWidth: max(1.5, size * 0.095), lineCap: .round))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// The mark and the word, as on the web.
struct SparkWordmark: View {
    var size: CGFloat = 22
    var color: Color = BrandColors.sparkTeal

    var body: some View {
        HStack(spacing: size * 0.35) {
            SparkMark(size: size, color: color)
            Text("Spark")
                .font(.system(size: size * 0.95, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .accessibilityLabel("Spark")
    }
}
