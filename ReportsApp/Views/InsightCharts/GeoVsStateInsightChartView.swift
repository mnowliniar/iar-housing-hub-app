import SwiftUI
import Charts
import Foundation

/// weekly_geo_vs_state: two bars, the geo's YoY pace in teal vs the
/// statewide pace in gray, around a zero baseline. Paces come from the
/// server (geo_pct/state_pct in the insight viz payload).
struct GeoVsStateInsightChartView: View {
    let geoPct: Double
    let statePct: Double
    let geoLabel: String

    private struct Bar: Identifiable {
        let id = UUID()
        let label: String
        let pct: Double
        let isGeo: Bool
    }

    private var bars: [Bar] {
        [
            Bar(label: geoLabel, pct: geoPct * 100.0, isGeo: true),
            Bar(label: "Statewide", pct: statePct * 100.0, isGeo: false),
        ]
    }

    private func signedLabel(_ pct: Double) -> String {
        let mag = abs(pct) < 10 ? String(format: "%.1f", pct) : String(Int(pct.rounded()))
        return "\(pct >= 0 ? "+" : "")\(mag)% YOY"
    }

    private var yDomain: ClosedRange<Double> {
        let vals = bars.map(\.pct) + [0]
        guard let lo = vals.min(), let hi = vals.max() else { return -1...1 }
        let pad = max((hi - lo) * 0.3, 2)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        Chart {
            ForEach(bars) { bar in
                BarMark(
                    x: .value("Market", bar.label),
                    y: .value("YOY", bar.pct),
                    width: .ratio(0.45)
                )
                .foregroundStyle(bar.isGeo ? BrandColors.teal : Color.gray.opacity(0.35))
                .cornerRadius(6)
                .annotation(position: bar.pct >= 0 ? .top : .bottom) {
                    Text(signedLabel(bar.pct))
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(bar.isGeo ? BrandColors.teal : Color.secondary)
                }
            }

            RuleMark(y: .value("Zero", 0))
                .foregroundStyle(Color.gray.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1))
        }
        .chartYScale(domain: yDomain)
        .chartXAxis {
            AxisMarks { value in
                AxisValueLabel {
                    if let label = value.as(String.self) {
                        Text(label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot
                .background(Color.clear)
        }
    }
}
