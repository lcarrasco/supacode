import SwiftUI

/// One changed-file row: a tappable header (chevron + status badge + file
/// name + dim directory) that discloses the file's inline diff when expanded.
/// Layout-agnostic; the parent `List` owns width and separators.
struct ChangedFileRowView: View {
  let file: ChangedFile
  let isExpanded: Bool
  let isLoadingDiff: Bool
  let diff: FileDiff?
  let didFail: Bool
  let onTap: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button(action: onTap) {
        HStack(spacing: 6) {
          Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .frame(width: 10)
            .accessibilityHidden(true)
          FileStatusBadgeView(status: file.status)
          VStack(alignment: .leading, spacing: 1) {
            Text(file.fileName)
              .font(.callout)
              .lineLimit(1)
              .truncationMode(.middle)
            if !file.directory.isEmpty {
              Text(file.directory)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
            }
          }
          Spacer(minLength: 0)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .help(file.previousPath.map { "Renamed from \($0)" } ?? file.path)

      if isExpanded {
        Group {
          if let diff {
            DiffContentView(diff: diff)
          } else if didFail {
            Text("Couldn't load diff")
              .font(.caption)
              .foregroundStyle(.secondary)
              .padding(.vertical, 6)
              .padding(.leading, 8)
          } else if isLoadingDiff {
            ProgressView()
              .controlSize(.small)
              .padding(.vertical, 6)
              .padding(.leading, 8)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
  }
}
