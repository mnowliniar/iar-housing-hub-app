//
//  Geo.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 3/18/26.
//


import AppIntents
import Foundation

// MARK: - Shared Models

struct Geo: Identifiable, Decodable, Hashable {
    let geoid: Int
    let type: String
    let name: String
    let label: String?
    let households: Int

    var id: Int { geoid }

    var displayName: String {
        label ?? name
    }
}

struct VizItem: Identifiable, Hashable, Decodable {
    let id: Int
    let title: String
    let subtitle: String?

    enum CodingKeys: String, CodingKey {
        case id = "viz_id"
        case title = "viz_title"
        case subtitle = "viz_subtitle"
    }
}

private let commonWidgetIndicators: [VizItem] = [
    VizItem(id: 1, title: "New Listings", subtitle: "Weekly total by listing date"),
    VizItem(id: 2, title: "New Pending Contracts", subtitle: "Weekly total of newly pended properties"),
    VizItem(id: 3, title: "Closed Sales", subtitle: "Weekly total of closed sales"),
    VizItem(id: 6, title: "Inventory", subtitle: "Average daily inventory"),
    VizItem(id: 69, title: "Months of Inventory", subtitle: "Based on monthly supply and 12-month sales average"),
    VizItem(id: 10, title: "Median Sale Price", subtitle: "Median monthly sale price"),
    VizItem(id: 23, title: "Listing Price", subtitle: "Median listing price"),
    VizItem(id: 4, title: "Weekly Sale Price", subtitle: "Median price of weekly sales"),
    VizItem(id: 9, title: "Median Days on Market", subtitle: "Days from listing to pending"),
    VizItem(id: 28, title: "Immediate Sales", subtitle: "Percent of new pending sales under contract in three days or less"),
    VizItem(id: 118, title: "Median Monthly Payment", subtitle: "For median-priced home"),
    VizItem(id: 121, title: "Payment as a Percent of Income", subtitle: "Based on 3-mo. median sale price")
]

// MARK: - Widget Config Intent

struct HousingHubWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configure Housing Hub Widget"
    static var description = IntentDescription("Choose a market and indicator for the widget.")

    @Parameter(title: "Geography Type")
    var geoType: GeoType?

    @Parameter(title: "Market", optionsProvider: GeoOptionsProvider())
    var geo: GeoEntity?

    @Parameter(title: "Indicator")
    var indicator: IndicatorEntity?
}

struct HousingHubInsightWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Configure Housing Hub Insight Widget"
    static var description = IntentDescription("Choose a market for the insight widget.")

    @Parameter(title: "Geography Type")
    var geoType: GeoType?

    @Parameter(title: "Market", optionsProvider: GeoOptionsProviderForInsights())
    var geo: GeoEntity?
}

// MARK: - Geo Type Enum

enum GeoType: String, CaseIterable, AppEnum {
    case association = "Association"
    case county = "County"
    case metroArea = "Metro Area"
    case state = "State"
    case township = "Township"
    case zipCode = "ZIP Code"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Geography Type")

    static var caseDisplayRepresentations: [GeoType: DisplayRepresentation] = [
        .association: "Association",
        .county: "County",
        .metroArea: "Metro Area",
        .state: "State",
        .township: "Township",
        .zipCode: "ZIP Code"
    ]
}

struct GeoOptionsProvider: DynamicOptionsProvider {
    @IntentParameterDependency<HousingHubWidgetIntent>(\.$geoType)
    var intent

    func results() async throws -> [GeoEntity] {
        let selectedType = intent?.geoType.rawValue ?? GeoType.state.rawValue
        let geos = try await GeoEntityQuery.fetchGeos(ofType: selectedType)

        return geos
            .map {
                GeoEntity(
                    id: String($0.geoid),
                    name: $0.displayName,
                    type: $0.type
                )
            }
            .sorted { $0.name < $1.name }
    }
}

struct GeoOptionsProviderForInsights: DynamicOptionsProvider {
    @IntentParameterDependency<HousingHubInsightWidgetIntent>(\.$geoType)
    var intent

    func results() async throws -> [GeoEntity] {
        let selectedType = intent?.geoType.rawValue ?? GeoType.state.rawValue
        let geos = try await GeoEntityQuery.fetchGeos(ofType: selectedType)

        return geos
            .map {
                GeoEntity(
                    id: String($0.geoid),
                    name: $0.displayName,
                    type: $0.type
                )
            }
            .sorted { $0.name < $1.name }
    }
}

// MARK: - Geo Entity

struct GeoEntity: AppEntity, Identifiable {
    let id: String
    let name: String
    let type: String

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Market")
    static var defaultQuery = GeoEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(type)"
        )
    }
}

struct GeoEntityQuery: EntityQuery {
    func entities(for identifiers: [GeoEntity.ID]) async throws -> [GeoEntity] {
        let idSet = Set(identifiers)
        var resolved: [GeoEntity] = []

        for type in GeoType.allCases {
            let geos = try await Self.fetchGeos(ofType: type.rawValue)
            let matches = geos
                .filter { idSet.contains(String($0.geoid)) }
                .map {
                    GeoEntity(
                        id: String($0.geoid),
                        name: $0.displayName,
                        type: $0.type
                    )
                }
            resolved.append(contentsOf: matches)
        }

        return resolved
    }

    func suggestedEntities() async throws -> [GeoEntity] {
        let geos = try await Self.fetchGeos(ofType: GeoType.state.rawValue)
        return geos.map {
            GeoEntity(
                id: String($0.geoid),
                name: $0.displayName,
                type: $0.type
            )
        }
        .sorted { $0.name < $1.name }
    }

    func defaultResult() async -> GeoEntity? {
        GeoEntity(id: "18", name: "Indiana", type: "State")
    }

    static func fetchGeos(ofType type: String) async throws -> [Geo] {
        guard
            let encodedType = type.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
            let url = URL(string: "https://data.indianarealtors.com/app/geos/?type=\(encodedType)")
        else {
            return []
        }

        let (data, _) = try await URLSession.shared.data(from: url)
        return try JSONDecoder().decode([Geo].self, from: data)
    }
}

// MARK: - Indicator Entity

struct IndicatorEntity: AppEntity, Identifiable {
    let id: String
    let title: String
    let subtitle: String?

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Indicator")
    static var defaultQuery = IndicatorEntityQuery()

    var displayRepresentation: DisplayRepresentation {
        if let subtitle, !subtitle.isEmpty {
            return DisplayRepresentation(
                title: "\(title)",
                subtitle: "\(subtitle)"
            )
        } else {
            return DisplayRepresentation(title: "\(title)")
        }
    }
}

struct IndicatorEntityQuery: EntityQuery {
    func entities(for identifiers: [IndicatorEntity.ID]) async throws -> [IndicatorEntity] {
        let all = try await suggestedEntities()
        let idSet = Set(identifiers)
        return all.filter { idSet.contains($0.id) }
    }

    func suggestedEntities() async throws -> [IndicatorEntity] {
        commonWidgetIndicators.map {
            IndicatorEntity(
                id: String($0.id),
                title: $0.title,
                subtitle: $0.subtitle
            )
        }
    }

    func defaultResult() async -> IndicatorEntity? {
        IndicatorEntity(id: "6", title: "Inventory", subtitle: "Average daily inventory")
    }
}
