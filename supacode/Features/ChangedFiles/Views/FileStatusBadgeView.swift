import SwiftUI

/// Single-letter colored badge (`A`/`M`/`D`/`R`/`C`/`U`/`?`) for a changed
/// file's status. Layout-agnostic; the parent owns placement.
struct FileStatusBadgeView: View {
  let status: ChangedFileStatus

  var body: some View {
    Text(status.badge)
      .font(.caption2.weight(.bold).monospaced())
      .foregroundStyle(tint)
      .frame(width: 14, height: 14)
      .background(tint.opacity(0.18), in: RoundedRectangle(cornerRadius: 3))
      .accessibilityLabel(accessibilityLabel)
  }

  private var tint: Color {
    switch status {
    case .added: Color(nsColor: .systemGreen)
    case .modified: Color(nsColor: .systemYellow)
    case .deleted: Color(nsColor: .systemRed)
    case .renamed: Color(nsColor: .systemBlue)
    case .copied: Color(nsColor: .systemTeal)
    case .unmerged: Color(nsColor: .systemPurple)
    case .untracked: Color(nsColor: .secondaryLabelColor)
    }
  }

  private var accessibilityLabel: String {
    switch status {
    case .added: "Added"
    case .modified: "Modified"
    case .deleted: "Deleted"
    case .renamed: "Renamed"
    case .copied: "Copied"
    case .unmerged: "Unmerged"
    case .untracked: "Untracked"
    }
  }
}
