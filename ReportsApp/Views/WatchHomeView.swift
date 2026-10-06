import SwiftUI
import Charts

struct WatchHomeView: View {
    @State private var showSettings = false
    @StateObject private var vm = MonthlyVM()
    @AppStorage("selectedGeoLabel") private var geoLabel: String = "Indiana"

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading || (vm.month.isEmpty && vm.facts.isEmpty && vm.pointsByLabel.isEmpty) {
                    VStack { ProgressView(); Text("Loading…").font(.caption2).foregroundColor(.secondary) }
                } else {
                    List {
                        // Where you're standing, first: the doorstep numbers.
                        WatchHereCard()
                        // One full-screen card per indicator; crown flips between rows (carousel)
                        ForEach(Array(vm.facts.enumerated()), id: \.offset) { _, f in
                            VStack(alignment: .leading, spacing: 6) {
                                // The market and week ride on each card, so the
                                // doorstep card above gets the whole first screen.
                                if !vm.month.isEmpty {
                                    Text("\(geoLabel) · \(vm.month)")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Text(f.label)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Text(f.value)
                                    .font(.title3).bold()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("12-week trend")
                                    .font(.system(size: 10))
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if let pts = vm.pointsByLabel[f.label], !pts.isEmpty {
                                    let minVal = pts.min() ?? 0
                                    let maxVal = pts.max() ?? 0
                                    Chart(Array(pts.enumerated()), id: \.0) { i, v in
                                        LineMark(x: .value("i", i), y: .value("v", v))
                                            .foregroundStyle(Color.accentColor)
                                    }
                                    .chartYScale(domain: minVal...maxVal)
                                    .chartXAxis(.hidden)
                                    .chartYAxis(.hidden)
                                    .frame(height: 30)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                        }
                    }
                    .listStyle(.carousel)          // Digital Crown pages through cards
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
        }
        .task(id: vm.geoID) {
            await vm.load()
        }
        .sheet(isPresented: $showSettings) {
            WatchSettingsView()
        }
    }
    
}
