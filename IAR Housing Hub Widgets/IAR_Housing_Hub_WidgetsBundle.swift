//
//  HousingHubWidgetBundle.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/18/26.
//


import WidgetKit
import SwiftUI

@main
struct HousingHubWidgetBundle: WidgetBundle {
    var body: some Widget {
        HousingHubWidget()
        HousingHubInsightWidget()
    }
}
