import SwiftUI

extension Font {
  /// DM Sans (t3code's UI face, bundled under `Resources/Fonts`) sized to a
  /// system text style and scaled with Dynamic Type via `relativeTo:`.
  ///
  /// `Font.custom(_:size:relativeTo:)` needs an explicit reference size, so the
  /// per-style macOS defaults live here once instead of leaking as magic numbers
  /// across call sites. Call as `.font(.dmSans(.callout))` and chain
  /// `.fontWeight(_:)` as usual — the bundled family ships Regular/Medium/
  /// SemiBold/Bold, so weight selection resolves to a real face.
  static func dmSans(_ style: Font.TextStyle) -> Font {
    .custom("DM Sans", size: referenceSize(for: style), relativeTo: style)
  }

  /// macOS default point sizes for each text style (the values SwiftUI resolves
  /// the system face to at the standard Dynamic Type setting).
  private static func referenceSize(for style: Font.TextStyle) -> CGFloat {
    switch style {
    case .largeTitle: 26
    case .title: 22
    case .title2: 17
    case .title3: 15
    case .headline: 13
    case .body: 13
    case .callout: 12
    case .subheadline: 11
    case .footnote: 10
    case .caption: 10
    case .caption2: 10
    @unknown default: 13
    }
  }
}
