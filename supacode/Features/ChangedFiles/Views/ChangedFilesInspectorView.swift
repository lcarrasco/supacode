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
        DiffWebView(html: html) { path in
          store.send(.openFileTapped(path))
        }
      }
    }
  }

  /// Vendored highlight.js core plus extra language grammars (not in the
  /// "common" bundle), loaded once and inlined into the diff HTML. Each
  /// language file self-registers against `hljs`, so order is core-first.
  private static let highlightScript: String = {
    let names = ["highlight.min", "hljs-dart.min"]
    let sources = names.compactMap { name -> String? in
      guard let url = Bundle.main.url(forResource: name, withExtension: "js") else { return nil }
      return try? String(contentsOf: url, encoding: .utf8)
    }
    // Need the core; extras are optional.
    return sources.first == nil ? "" : sources.joined(separator: "\n")
  }()

  private var html: String {
    DiffHTMLRenderer.document(
      files: store.files,
      diffs: store.loadedDiffs,
      failedIDs: store.failedDiffIDs,
      diffsSettled: store.diffsLoaded,
      omittedCount: max(0, store.files.count - ChangedFilesFeature.diffBatchCap),
      highlightScript: Self.highlightScript,
      worktreeDirectory: store.activeWorktreeDirectory
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
