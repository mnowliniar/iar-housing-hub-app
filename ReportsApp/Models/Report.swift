import Foundation

struct Report: Identifiable, Decodable {
    let id: Int
    let title: String
    let description: String
    let category: String
    let is_protected: Bool
}