//
//  WatchWidgetBundle.swift
//  IAR Housing Hub Watch Widgets
//
//  The watch face complication. Shares WidgetAPI and the configuration
//  intent with the iPhone widget; only the views are the watch's own.
//

import WidgetKit
import SwiftUI

@main
struct HousingHubWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        HousingHubComplication()
    }
}
