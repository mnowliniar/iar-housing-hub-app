//
//  ReportSummary.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 8/26/25.
//


import Foundation

struct JSONValue: Decodable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = NSNull()
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let arrayValue = try? container.decode([JSONValue].self) {
            value = arrayValue.map(\.value)
        } else if let dictValue = try? container.decode([String: JSONValue].self) {
            value = dictValue.mapValues(\.value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }
}

struct ReportSummary: Decodable {
    let title: String
    let geo: String
    let report_date: String
    let vizzes: [VizSummary]
}

struct VizSummary: Identifiable, Decodable {
    let vizid: Int
    var id: Int { vizid }
    let title: String

    let fact1: String?
    let fact1label: String?
    let fact2: String?
    let fact2label: String?
    let fact3: String?
    let fact3label: String?

    let exp1: String?
    let exp2: String?
    let exp3: String?
    
    let geo_id: Int?
    let proptype: String?
    let update_date: String?
    let type: String?
    let format: String?
    let chart_data: [[String: JSONValue]]?
}
