import ComposableArchitecture
import SwiftUI

/// Right-side inspector listing the active worktree's changed files with their
/// inline diffs, rendered as one HTML document in a `WKWebView`.
struct ChangedFilesInspectorView: View {
  @Bindable var store: StoreOf<ChangedFilesFeature>

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      content
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var header: some View {
    HStack(spacing: 6) {
      Text("Changed Files")
        .font(.headline)
      if !store.files.isEmpty {
        Text("\(store.files.count)")
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
          .padding(.horizontal, 6)
          .padding(.vertical, 1)
          .background(.quaternary, in: Capsule())
      }
      Spacer()
      Button {
        store.send(.refreshRequested)
      } label: {
        Label("Refresh", systemImage: "arrow.clockwise")
          .labelStyle(.iconOnly)
      }
      .buttonStyle(.borderless)
      .help("Refresh changed files")
      .disabled(store.activeWorktreeDirectory == nil)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
  }

  @ViewBuilder
  private var content: some View {
    switch store.loadingState {
    case .idle where store.activeWorktreeDirectory == nil:
      message("Select a git worktree to see its changes.")
    case .loading where store.files.isEmpty:
      ProgressView()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    case .failed(let error):
      message(error)
    default:
      if store.files.isEmpty {
        message("No uncommitted changes.")
      } else {
        DiffWebView(html: html)
      }
    }
  }

  /// Vendored highlight.js source, loaded once and inlined into the diff HTML.
  private static let highlightScript: String = {
    guard let url = Bundle.main.url(forResource: "highlight.min", withExtension: "js"),
      let source = try? String(contentsOf: url, encoding: .utf8)
    else { return "" }
    return source
  }()

  private var html: String {
    DiffHTMLRenderer.document(
      files: store.files,
      diffs: store.loadedDiffs,
      failedIDs: store.failedDiffIDs,
      diffsSettled: store.diffsLoaded,
      omittedCount: max(0, store.files.count - ChangedFilesFeature.diffBatchCap),
      highlightScript: Self.highlightScript
    )
  }

  private func message(_ text: String) -> some View {
    Text(text)
      .font(.callout)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .padding()
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
