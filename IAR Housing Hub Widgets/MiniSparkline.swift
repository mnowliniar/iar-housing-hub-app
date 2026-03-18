//
//  MiniSparkline.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/18/26.
//


import SwiftUI

struct MiniSparkline: View {
    let points: [Double]

    private var minY: Double {
        guard let minVal = points.min(), let maxVal = points.max() else { return 0 }
        let span = max(maxVal - minVal, 1)
        return minVal - span * 0.1
    }

    private var maxY: Double {
        guard let minVal = points.min(), let maxVal = points.max() else { return 100 }
        let span = max(maxVal - minVal, 1)
        return maxVal + span * 0.1
    }

    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard points.count > 1 else { return }

                for (index, value) in points.enumerated() {
                    let x = geo.size.width * CGFloat(index) / CGFloat(max(points.count - 1, 1))
                    let yRatio = (value - minY) / max(maxY - minY, 1)
                    let y = geo.size.height * (1 - CGFloat(yRatio))

                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(widgetTeal, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 36)
    }
}
