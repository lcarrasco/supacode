import SwiftUI
import WebKit

/// Hosts the rendered diff HTML in a `WKWebView`. WebKit's text layout +
/// scroll virtualization handles large diffs far better than a native view
/// tree. Reloads only when the HTML string actually changes.
struct DiffWebView: NSViewRepresentable {
  let html: String

  func makeNSView(context: Context) -> WKWebView {
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    webView.underPageBackgroundColor = .textBackgroundColor
    return webView
  }

  func updateNSView(_ webView: WKWebView, context: Context) {
    guard context.coordinator.lastHTML != html else { return }
    context.coordinator.lastHTML = html
    webView.loadHTMLString(html, baseURL: nil)
  }

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator {
    var lastHTML: String?
  }
}
