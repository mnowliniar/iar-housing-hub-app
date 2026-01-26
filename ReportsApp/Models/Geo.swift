import Foundation

struct Geo: Identifiable, Decodable, Hashable {
    let geoid: Int
    let type: String
    let name: String
    let label: String?
    let households: Int

    // Conform to SwiftUI's Identifiable
    var id: Int { geoid }

    // Fallback to name if label is nil
    var displayName: String {
        label ?? name
    }
}
