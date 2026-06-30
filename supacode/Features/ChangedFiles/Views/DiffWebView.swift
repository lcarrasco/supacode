import SwiftUI
import WebKit

/// Hosts the rendered diff HTML in a `WKWebView`. WebKit's text layout +
/// scroll virtualization handles large diffs far better than a native view
/// tree. Reloads only when the HTML string actually changes, and bridges
/// filename clicks back to Swift via the `openFile` message handler.
struct DiffWebView: NSViewRepresentable {
  let html: String
  let onOpenFile: (String) -> Void

  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.userContentController.add(context.coordinator, name: "openFile")
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.underPageBackgroundColor = .textBackgroundColor
    return webView
  }

  func updateNSView(_ webView: WKWebView, context: Context) {
    context.coordinator.onOpenFile = onOpenFile
    guard context.coordinator.lastHTML != html else { return }
    context.coordinator.lastHTML = html
    webView.loadHTMLString(html, baseURL: nil)
  }

  func makeCoordinator() -> Coordinator { Coordinator(onOpenFile: onOpenFile) }

  final class Coordinator: NSObject, WKScriptMessageHandler {
    var lastHTML: String?
    var onOpenFile: (String) -> Void

    init(onOpenFile: @escaping (String) -> Void) {
      self.onOpenFile = onOpenFile
    }

    func userContentController(
      _ userContentController: WKUserContentController,
      didReceive message: WKScriptMessage
    ) {
      guard message.name == "openFile", let path = message.body as? String else { return }
      onOpenFile(path)
    }
  }
}
