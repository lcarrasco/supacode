import Foundation

/// Pure parsers turning raw `git` output into the inspector's value types.
/// Stateless static methods so they unit-test without a shell.
nonisolated enum UnifiedDiffParser {
  // MARK: - Changed-file list (`git status --porcelain=v1 -z -M`)

  /// Parse NUL-delimited porcelain v1 output. Each record is
  /// `XY<space>PATH`, except renames/copies which emit the destination
  /// first then a separate NUL field for the source:
  /// `R…<space>NEW` `\0` `OLD`. Untracked files carry the `??` code.
  static func parseChangedFiles(porcelainZ output: String) -> [ChangedFile] {
    // Trailing NUL leaves an empty final token; drop empties.
    let tokens = output.split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
    var files: [ChangedFile] = []
    var index = 0
    while index < tokens.count {
      let record = tokens[index]
      index += 1
      // A valid record is at least "XY " + one path char.
      guard record.count >= 4 else { continue }
      let codeStart = record.startIndex
      let indexStatus = record[codeStart]
      let worktreeStatus = record[record.index(after: codeStart)]
      // Path begins after the 2-char code and its separating space.
      let path = String(record[record.index(codeStart, offsetBy: 3)...])
      let status = Self.status(index: indexStatus, worktree: worktreeStatus)
      var previousPath: String?
      // Renames/copies consume the following token as the source path.
      if (indexStatus == "R" || indexStatus == "C") && index < tokens.count {
        previousPath = tokens[index]
        index += 1
      }
      files.append(ChangedFile(path: path, previousPath: previousPath, status: status))
    }
    return files.sorted { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }
  }

  /// Fold the 2-char `XY` porcelain code into a single display status.
  /// Index (staged) status wins for the structural cases; the working-tree
  /// column refines plain modifications.
  private static func status(index: Character, worktree: Character) -> ChangedFileStatus {
    if index == "?" && worktree == "?" { return .untracked }
    if index == "U" || worktree == "U" { return .unmerged }
    if index == "R" || worktree == "R" { return .renamed }
    if index == "C" || worktree == "C" { return .copied }
    if index == "A" { return .added }
    if index == "D" || worktree == "D" { return .deleted }
    return .modified
  }

  // MARK: - Per-file unified diff (`git diff HEAD -- <path>`)

  /// Parse a single-file unified diff into hunks with resolved line numbers.
  /// Returns `.binary` when git reports a binary delta.
  static func parseFileDiff(_ raw: String) -> FileDiff {
    if raw.contains("\nBinary files ") || raw.hasPrefix("Binary files ") {
      return .binary
    }
    var hunks: [DiffHunk] = []
    var currentHeader: String?
    var currentLines: [DiffLine] = []
    var oldLine = 0
    var newLine = 0
    var lineID = 0
    var hunkID = 0

    func flush() {
      guard let header = currentHeader else { return }
      hunks.append(DiffHunk(id: hunkID, header: header, lines: currentLines))
      hunkID += 1
      currentLines = []
      currentHeader = nil
    }

    for rawLine in raw.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = String(rawLine)
      if line.hasPrefix("@@") {
        flush()
        currentHeader = line
        let (oldStart, newStart) = Self.hunkStarts(from: line)
        oldLine = oldStart
        newLine = newStart
        continue
      }
      // Skip file-header noise that precedes the first hunk.
      guard currentHeader != nil else { continue }
      guard let marker = line.first else {
        // A truly empty line inside a hunk is a context line with no content.
        currentLines.append(
          DiffLine(id: lineID, kind: .context, text: "", oldLineNumber: oldLine, newLineNumber: newLine)
        )
        lineID += 1
        oldLine += 1
        newLine += 1
        continue
      }
      let content = String(line.dropFirst())
      switch marker {
      case "+":
        currentLines.append(
          DiffLine(id: lineID, kind: .added, text: content, oldLineNumber: nil, newLineNumber: newLine)
        )
        newLine += 1
      case "-":
        currentLines.append(
          DiffLine(id: lineID, kind: .removed, text: content, oldLineNumber: oldLine, newLineNumber: nil)
        )
        oldLine += 1
      case "\\":
        // "\ No newline at end of file"
        currentLines.append(
          DiffLine(id: lineID, kind: .noNewline, text: content, oldLineNumber: nil, newLineNumber: nil)
        )
      default:
        currentLines.append(
          DiffLine(id: lineID, kind: .context, text: content, oldLineNumber: oldLine, newLineNumber: newLine)
        )
        oldLine += 1
        newLine += 1
      }
      lineID += 1
    }
    flush()
    return FileDiff(hunks: hunks, isBinary: false)
  }

  /// Extract the old/new starting line numbers from an `@@ -o,s +n,s @@` header.
  private static func hunkStarts(from header: String) -> (old: Int, new: Int) {
    var old = 0
    var new = 0
    if let match = header.firstMatch(of: /@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/) {
      old = Int(match.1) ?? 0
      new = Int(match.2) ?? 0
    }
    return (old, new)
  }

  // MARK: - Untracked file (synthesized all-added diff)

  /// Build an all-added diff for an untracked file from its raw bytes.
  /// Detects binary content via an embedded NUL byte (git's own heuristic).
  static func untrackedFileDiff(data: Data) -> FileDiff {
    if data.prefix(8000).contains(0) {
      return .binary
    }
    guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
      return .empty
    }
    var lines: [DiffLine] = []
    // A trailing newline produces an empty final component we don't render.
    let components = text.split(separator: "\n", omittingEmptySubsequences: false)
    let dropTrailingEmpty = text.hasSuffix("\n")
    let body = dropTrailingEmpty ? components.dropLast() : components[...]
    for (offset, content) in body.enumerated() {
      lines.append(
        DiffLine(id: offset, kind: .added, text: String(content), oldLineNumber: nil, newLineNumber: offset + 1)
      )
    }
    guard !lines.isEmpty else { return .empty }
    let header = "@@ -0,0 +1,\(lines.count) @@"
    return FileDiff(hunks: [DiffHunk(id: 0, header: header, lines: lines)], isBinary: false)
  }
}
