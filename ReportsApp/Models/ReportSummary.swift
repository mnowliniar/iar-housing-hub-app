//
//  ReportSummary.swift
//  ReportsApp
//
//  Created by Matt Nowlin on 8/26/25.
//


import Foundation

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
    let img_url: String?
    let update_date: String?
    let type: String?
    let format: String?

    var csvURL: URL? {
        guard
            let geo = geo_id,
            let url = img_url,
            let updateDate = update_date,
            let prop = proptype
        else {
            return nil
        }

        let base = "https://data.indianarealtors.com/files/output"
        let fullPath = "\(base)/\(updateDate)/\(geo)/\(prop)/\(url)_chart.csv"
        return URL(string: fullPath)
    }
}
