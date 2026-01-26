import SwiftUI
import Charts

struct WatchHomeView: View {
    @State private var showSettings = false
    @StateObject private var vm = MonthlyVM()

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading || (vm.month.isEmpty && vm.facts.isEmpty && vm.pointsByLabel.isEmpty) {
                    VStack { ProgressView(); Text("Loading…").font(.caption2).foregroundColor(.secondary) }
                } else {
                    // Small header above the cards
                    if !vm.month.isEmpty {
                        HStack(spacing: 8) {
                            Text(vm.month)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer(minLength: 4)
                            Button {
                                showSettings = true
                            } label: {
                                Image(systemName: "gearshape")
                            }
                            .buttonStyle(.plain)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 2)
                    }

                    List {
                        // One full-screen card per indicator; crown flips between rows (carousel)
                        ForEach(Array(vm.facts.enumerated()), id: \.offset) { _, f in
                            VStack(alignment: .leading, spacing: 6) {
                                // Put the sparkline only on the Closed Sales card

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
        }
        .task(id: vm.geoID) {
            await vm.load()
        }
        .sheet(isPresented: $showSettings) {
            WatchSettingsView()
        }
    }
    
}
