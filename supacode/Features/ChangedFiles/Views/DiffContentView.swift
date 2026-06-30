import SwiftUI

/// Renders a parsed `FileDiff` inline: binary / empty placeholders, or the
/// list of hunks. Monospaced; add/remove tinting via system colors.
struct DiffContentView: View {
  let diff: FileDiff

  var body: some View {
    if diff.isBinary {
      placeholder("Binary file")
    } else if diff.hunks.isEmpty {
      placeholder("No textual changes")
    } else {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(diff.hunks) { hunk in
          DiffHunkView(hunk: hunk)
        }
      }
      .font(.caption.monospaced())
      .textSelection(.enabled)
    }
  }

  private func placeholder(_ text: String) -> some View {
    Text(text)
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.vertical, 6)
      .padding(.leading, 8)
  }
}

private struct DiffHunkView: View {
  let hunk: DiffHunk

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(hunk.header)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
        .padding(.horizontal, 8)
        .background(.quaternary.opacity(0.5))
      ForEach(hunk.lines) { line in
        DiffLineView(line: line)
      }
    }
  }
}

private struct DiffLineView: View {
  let line: DiffLine

  var body: some View {
    HStack(alignment: .top, spacing: 0) {
      gutter(line.oldLineNumber)
      gutter(line.newLineNumber)
      Text(marker)
        .foregroundStyle(.secondary)
        .frame(width: 10, alignment: .leading)
      Text(line.text.isEmpty ? " " : line.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
    }
    .padding(.trailing, 4)
    .background(background)
  }

  private var marker: String {
    switch line.kind {
    case .added: "+"
    case .removed: "-"
    case .context: " "
    case .noNewline: "\\"
    }
  }

  private var background: Color {
    switch line.kind {
    case .added: Color(nsColor: .systemGreen).opacity(0.15)
    case .removed: Color(nsColor: .systemRed).opacity(0.15)
    case .context, .noNewline: .clear
    }
  }

  private func gutter(_ number: Int?) -> some View {
    Text(number.map(String.init) ?? "")
      .foregroundStyle(.tertiary)
      .frame(width: 34, alignment: .trailing)
      .padding(.horizontal, 3)
  }
}
