import SwiftUI

/// One changed-file card in the continuous diff scroll: a header (chevron +
/// status badge + file name + dim directory + `+N −M` counts) above the file's
/// inline diff. Expanded by default; the diff lazy-loads when the card appears.
struct ChangedFileRowView: View {
  let file: ChangedFile
  let isExpanded: Bool
  let isLoadingDiff: Bool
  let diff: FileDiff?
  let didFail: Bool
  let onToggle: () -> Void
  let onAppear: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      if isExpanded {
        Divider()
        diffBody
          .onAppear { onAppear() }
      }
    }
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator, lineWidth: 1))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private var header: some View {
    Button(action: onToggle) {
      HStack(spacing: 6) {
        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .frame(width: 10)
          .accessibilityHidden(true)
        FileStatusBadgeView(status: file.status)
        Text(file.fileName)
          .font(.callout.weight(.medium))
          .lineLimit(1)
          .truncationMode(.middle)
        if !file.directory.isEmpty {
          Text(file.directory)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .truncationMode(.head)
        }
        Spacer(minLength: 4)
        if let diff, !diff.isBinary {
          DiffCountsView(added: diff.addedLines, removed: diff.removedLines)
        }
      }
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .help(file.previousPath.map { "Renamed from \($0)" } ?? file.path)
  }

  @ViewBuilder
  private var diffBody: some View {
    if let diff {
      DiffContentView(diff: diff)
        .padding(.vertical, 2)
    } else if didFail {
      placeholder("Couldn't load diff")
    } else if isLoadingDiff {
      ProgressView()
        .controlSize(.small)
        .padding(.vertical, 8)
        .padding(.leading, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func placeholder(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.vertical, 6)
      .padding(.leading, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
  }
}

/// Compact `+N −M` line-count badge for a file header.
private struct DiffCountsView: View {
  let added: Int
  let removed: Int

  var body: some View {
    HStack(spacing: 5) {
      if removed > 0 {
        Text("−\(removed)")
          .foregroundStyle(Color(nsColor: .systemRed))
      }
      if added > 0 {
        Text("+\(added)")
          .foregroundStyle(Color(nsColor: .systemGreen))
      }
    }
    .font(.caption.monospacedDigit())
    .accessibilityLabel("\(added) added, \(removed) removed")
  }
}
