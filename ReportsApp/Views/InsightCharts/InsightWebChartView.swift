import SwiftUI
import WebKit

/// Server-rendered fallback chart for insight kinds the app has no native
/// renderer for. Loads the hub's insight_viz page in chart-only embed mode,
/// so new insight kinds added server-side render here without an app update.
struct InsightWebChartView: UIViewRepresentable {
    let instanceID: Int
    let insightType: String

    private var url: URL? {
        URL(string: "https://data.indianarealtors.com/reports/insight_viz/\(instanceID)/\(insightType)/?embed=1")
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.isUserInteractionEnabled = false
        if let url {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
