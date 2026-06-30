import Foundation

/// A single file that differs from `HEAD` in a worktree (or is untracked),
/// as surfaced by the Changed Files inspector. `id` is the repo-relative
/// path of the file's *current* name, stable enough to key expansion and
/// the per-file diff cache.
nonisolated struct ChangedFile: Equatable, Identifiable, Sendable {
  let path: String
  /// Non-nil only for renames/copies: the previous path the file moved from.
  let previousPath: String?
  let status: ChangedFileStatus

  /// Repo-relative path; stable key for expansion + the per-file diff cache.
  var id: String { path }

  /// Last path component, shown as the row's primary label.
  var fileName: String {
    path.split(separator: "/").last.map(String.init) ?? path
  }

  /// Parent directory shown as the row's dim secondary label; empty for a
  /// file at the repo root.
  var directory: String {
    let components = path.split(separator: "/")
    guard components.count > 1 else { return "" }
    return components.dropLast().joined(separator: "/")
  }
}

/// Collapsed single-axis status for display. `git status` reports a 2-char
/// `XY` code (staged / unstaged); the inspector shows "uncommitted vs HEAD",
/// so the two axes are folded into one badge.
nonisolated enum ChangedFileStatus: Equatable, Sendable {
  case added
  case modified
  case deleted
  case renamed
  case copied
  case unmerged
  case untracked

  /// Single-letter badge glyph (`A`/`M`/`D`/`R`/`C`/`U`/`?`).
  var badge: String {
    switch self {
    case .added: "A"
    case .modified: "M"
    case .deleted: "D"
    case .renamed: "R"
    case .copied: "C"
    case .unmerged: "U"
    case .untracked: "?"
    }
  }
}

/// Parsed unified diff for one file. `isBinary` short-circuits rendering
/// (git emits "Binary files … differ" with no hunks).
nonisolated struct FileDiff: Equatable, Sendable {
  let hunks: [DiffHunk]
  let isBinary: Bool
  /// Human note for a hunk-less change git still reports (e.g. a mode/perms
  /// flip). Shown instead of the generic "No textual changes" placeholder.
  var nonContentNote: String?

  init(hunks: [DiffHunk], isBinary: Bool, nonContentNote: String? = nil) {
    self.hunks = hunks
    self.isBinary = isBinary
    self.nonContentNote = nonContentNote
  }

  static let binary = FileDiff(hunks: [], isBinary: true)
  static let empty = FileDiff(hunks: [], isBinary: false)

  /// Added / removed line tallies for the file's header `+N −M` badge.
  var addedLines: Int {
    hunks.reduce(0) { $0 + $1.lines.lazy.filter { $0.kind == .added }.count }
  }

  var removedLines: Int {
    hunks.reduce(0) { $0 + $1.lines.lazy.filter { $0.kind == .removed }.count }
  }
}

/// One `@@ … @@` section of a unified diff.
nonisolated struct DiffHunk: Equatable, Sendable, Identifiable {
  /// Stable within a file: hunks never reorder, so the index is the id.
  let id: Int
  /// Raw `@@ -l,s +l,s @@` header line, verbatim.
  let header: String
  let lines: [DiffLine]
}

/// One line of a unified diff, with resolved old/new line numbers so the
/// inspector can render a two-column gutter without re-deriving them.
nonisolated struct DiffLine: Equatable, Sendable, Identifiable {
  enum Kind: Equatable, Sendable {
    case context
    case added
    case removed
    /// `\ No newline at end of file` marker line.
    case noNewline
  }

  let id: Int
  let kind: Kind
  /// Content without the leading `+`/`-`/space marker.
  let text: String
  /// Old-side line number; nil for added lines and the no-newline marker.
  let oldLineNumber: Int?
  /// New-side line number; nil for removed lines and the no-newline marker.
  let newLineNumber: Int?
}
