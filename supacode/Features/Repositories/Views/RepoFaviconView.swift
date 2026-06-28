import AppKit
import SwiftUI

/// Repo brand glyph for the sidebar section header: loads an `apple-touch-icon.png`
/// shipped inside the repository folder (the convention web projects already follow).
/// Falls back to a tinted rounded square when the file is absent so every repo still
/// reads as an icon-led row à la Superset.
struct RepoFaviconView: View {
  let rootURL: URL?
  let color: Color
  var size: CGFloat = 16

  @State private var image: NSImage?

  var body: some View {
    Group {
      if let image {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: .fill)
      } else {
        RoundedRectangle(cornerRadius: size * 0.25, style: .continuous)
          .fill(color.gradient)
      }
    }
    .frame(width: size, height: size)
    .clipShape(RoundedRectangle(cornerRadius: size * 0.25, style: .continuous))
    .accessibilityHidden(true)
    .task(id: rootURL) { await load() }
  }

  private func load() async {
    guard let rootURL else {
      image = nil
      return
    }
    image = await RepoFaviconLoader.shared.icon(for: rootURL)
  }
}

/// Disk-backed favicon resolver with an in-memory cache so repeated row appearances
/// don't re-scan the filesystem. Lookups run off the main actor.
actor RepoFaviconLoader {
  static let shared = RepoFaviconLoader()

  /// Relative paths probed in order; covers root plus the usual web-project homes.
  private static let candidates = [
    "apple-touch-icon.png",
    "public/apple-touch-icon.png",
    "web/apple-touch-icon.png",
    "web/icons/apple-touch-icon.png",
    "static/apple-touch-icon.png",
    "assets/apple-touch-icon.png",
  ]

  private var cache: [URL: NSImage?] = [:]

  func icon(for rootURL: URL) -> NSImage? {
    if let cached = cache[rootURL] { return cached }
    let resolved = Self.candidates.lazy
      .map { rootURL.appending(path: $0, directoryHint: .notDirectory) }
      .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
      .flatMap { NSImage(contentsOf: $0) }
    cache[rootURL] = resolved
    return resolved
  }
}
