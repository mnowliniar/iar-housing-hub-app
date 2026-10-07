//
//  MarketMapCanvas.swift
//  ReportsApp
//
//  The map itself: MapKit drawing one polygon per county, ZIP or township,
//  filled by the layer's color rule, with a tap finding the place under
//  the finger. UIKit's map view, because a thousand townships draw faster
//  there than as SwiftUI content.
//

import SwiftUI
import MapKit

struct MarketMapCanvas: UIViewRepresentable {
    let layer: MapLayer?
    /// The fill for a place, or nil to leave it off the map.
    let fill: (MapFeature) -> UIColor?
    let selectedID: String?
    let onTap: (MapFeature?) -> Void

    /// The whole state, with a little air.
    static let indiana = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.80, longitude: -86.30),
        span: MKCoordinateSpan(latitudeDelta: 4.4, longitudeDelta: 4.0))

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        config.pointOfInterestFilter = .excludingAll
        map.preferredConfiguration = config
        map.delegate = context.coordinator
        map.showsCompass = false
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.setRegion(Self.indiana, animated: false)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)
        context.coordinator.map = map
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let c = context.coordinator
        c.onTap = onTap
        c.features = layer?.features ?? []
        let key = layer?.key
        if key != c.layerKey {
            c.layerKey = key
            map.removeOverlays(map.overlays)
            c.owners = [:]
            c.fills = [:]
            for feature in c.features {
                let color = fill(feature)
                for polygon in feature.polygons {
                    c.owners[polygon] = feature.id
                    c.fills[polygon] = color
                }
                map.addOverlays(feature.polygons, level: .aboveRoads)
            }
            c.selectedID = selectedID
            return
        }
        // Same places, new colors or a new selection: repaint in place.
        var changed = false
        for feature in c.features {
            let color = fill(feature)
            for polygon in feature.polygons where c.fills[polygon] != color {
                c.fills[polygon] = color
                changed = true
            }
        }
        let selectionChanged = c.selectedID != selectedID
        c.selectedID = selectedID
        guard changed || selectionChanged else { return }
        for overlay in map.overlays {
            guard let polygon = overlay as? MKPolygon,
                  let renderer = map.renderer(for: polygon) as? MKPolygonRenderer else { continue }
            c.style(renderer, polygon: polygon)
            renderer.setNeedsDisplay()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        weak var map: MKMapView?
        var features: [MapFeature] = []
        var layerKey: String?
        var owners: [MKPolygon: String] = [:]
        var fills: [MKPolygon: UIColor?] = [:]
        var selectedID: String?
        var onTap: (MapFeature?) -> Void = { _ in }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polygon = overlay as? MKPolygon else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolygonRenderer(polygon: polygon)
            style(renderer, polygon: polygon)
            return renderer
        }

        func style(_ renderer: MKPolygonRenderer, polygon: MKPolygon) {
            let color = fills[polygon] ?? nil
            let selected = owners[polygon] == selectedID && selectedID != nil
            if let color {
                renderer.fillColor = color.withAlphaComponent(selected ? 0.85 : 0.7)
                renderer.strokeColor = selected ? UIColor.black.withAlphaComponent(0.9) : UIColor.white.withAlphaComponent(0.6)
                renderer.lineWidth = selected ? 2.5 : 0.6
            } else {
                renderer.fillColor = .clear
                renderer.strokeColor = selected ? UIColor.black.withAlphaComponent(0.9) : UIColor.white.withAlphaComponent(0.25)
                renderer.lineWidth = selected ? 2.5 : 0.4
            }
        }

        @objc func tapped(_ gesture: UITapGestureRecognizer) {
            guard let map else { return }
            let point = gesture.location(in: map)
            let coordinate = map.convert(point, toCoordinateFrom: map)
            let hit = features.first { $0.contains(coordinate) }
            onTap(hit)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
