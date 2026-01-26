//
//  AppState.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 9/3/25.
//


import Foundation

final class AppState: ObservableObject {
    @Published var selectedGeoID: String = "18" // default market (Indiana)
}
