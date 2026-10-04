//
//  MarketPackOptionsSheet.swift
//  ReportsApp
//
//  The pack's setup: which markets (up to five), which three indicators,
//  the look of the cards, the voice of the script, and the monthly email.
//

import SwiftUI

struct MarketPackOptionsSheet: View {
    let setup: PackSetup
    let onSave: (String, String, String, [PackMarket], Bool) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var combo: String
    @State private var preset: String
    @State private var template: String
    @State private var markets: [PackMarket]
    @State private var active: Bool
    @State private var adding = false
    @State private var saving = false

    init(setup: PackSetup, onSave: @escaping (String, String, String, [PackMarket], Bool) async -> Void) {
        self.setup = setup
        self.onSave = onSave
        _combo = State(initialValue: setup.combo)
        _preset = State(initialValue: setup.preset)
        _template = State(initialValue: setup.template)
        _markets = State(initialValue: setup.markets)
        _active = State(initialValue: setup.active)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(markets) { market in
                        Text(market.geoLabel)
                    }
                    .onDelete { offsets in
                        markets.remove(atOffsets: offsets)
                        if markets.isEmpty { active = false }
                    }
                    if markets.count < setup.maxMarkets {
                        Button {
                            adding = true
                        } label: {
                            Label("Add a market", systemImage: "plus")
                        }
                    }
                } header: {
                    Text("Markets")
                } footer: {
                    Text("Up to \(setup.maxMarkets). Each market gets its own cards and reel. Swipe left to remove one.")
                }

                Section("Indicators") {
                    Picker("Indicators", selection: $combo) {
                        ForEach(setup.combos) { choice in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(choice.label)
                                if let detail = choice.detail {
                                    Text(detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(choice.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section("Look") {
                    Picker("Look", selection: $template) {
                        ForEach(setup.templates) { choice in
                            Text(choice.label).tag(choice.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Picker("Voice", selection: $preset) {
                        ForEach(setup.presets) { choice in
                            Text(choice.label).tag(choice.id)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } header: {
                    Text("Voice of the script")
                } footer: {
                    Text("The numbers never change; the framing does.")
                }

                Section {
                    Toggle("Email me the pack each month", isOn: $active)
                        .tint(BrandColors.teal)
                        .disabled(markets.isEmpty)
                } footer: {
                    Text(markets.isEmpty
                         ? "Add a market to turn on the monthly email."
                         : "Each market's cards, reel and script land in your inbox when the month's numbers post.")
                }
            }
            .navigationTitle("Pack options")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        saving = true
                        Task {
                            await onSave(combo, preset, template, markets, active)
                            dismiss()
                        }
                    } label: {
                        if saving {
                            ProgressView()
                        } else {
                            Text("Save").bold()
                        }
                    }
                    .disabled(saving)
                }
            }
            .sheet(isPresented: $adding) {
                FavoriteMarketPickerSheet(existingIDs: markets.map(\.geoID)) { geo in
                    guard markets.count < setup.maxMarkets else { return }
                    markets.append(PackMarket(geoID: geo.geoid, geoLabel: geo.displayName))
                }
            }
        }
    }
}
