import Foundation

/// Renders the changed-file set as a single self-contained HTML document for
/// the inspector's `WKWebView`. Pure + stateless (no UI, no I/O) so it unit
/// tests directly. All file content is HTML-escaped before interpolation.
nonisolated enum DiffHTMLRenderer {
  /// Builds the full document. `diffsSettled` distinguishes "still loading"
  /// from "loaded but failed" for files missing from `diffs`.
  static func document(
    files: [ChangedFile],
    diffs: [ChangedFile.ID: FileDiff],
    failedIDs: Set<ChangedFile.ID>,
    diffsSettled: Bool,
    omittedCount: Int = 0
  ) -> String {
    var body = ""
    for file in files {
      body += fileSection(file: file, diffs: diffs, failedIDs: failedIDs, diffsSettled: diffsSettled)
    }
    if omittedCount > 0 {
      body += "<div class=\"note\">\(omittedCount) more file(s) not shown</div>"
    }
    return """
      <!DOCTYPE html><html><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>\(css)</style></head><body>\(body)</body></html>
      """
  }

  // MARK: - File section

  private static func fileSection(
    file: ChangedFile,
    diffs: [ChangedFile.ID: FileDiff],
    failedIDs: Set<ChangedFile.ID>,
    diffsSettled: Bool
  ) -> String {
    let badge = statusBadge(file.status)
    let name = escape(file.fileName)
    let dir = file.directory.isEmpty ? "" : "<span class=\"dir\">\(escape(file.directory))</span>"
    let counts = countsBadge(file: file, diffs: diffs)
    let summary = """
      <summary><span class="chev"></span>\(badge)<span class="name">\(name)</span>\(dir)\
      <span class="spacer"></span>\(counts)</summary>
      """
    let body = diffBody(file: file, diffs: diffs, failedIDs: failedIDs, diffsSettled: diffsSettled)
    return "<details open class=\"file\">\(summary)\(body)</details>"
  }

  private static func diffBody(
    file: ChangedFile,
    diffs: [ChangedFile.ID: FileDiff],
    failedIDs: Set<ChangedFile.ID>,
    diffsSettled: Bool
  ) -> String {
    if failedIDs.contains(file.id) {
      return note("Couldn't load diff")
    }
    guard let diff = diffs[file.id] else {
      return note(diffsSettled ? "Couldn't load diff" : "Loading…")
    }
    if diff.isBinary { return note("Binary file") }
    if diff.hunks.isEmpty { return note("No textual changes") }
    var rows = ""
    for hunk in diff.hunks {
      rows += "<div class=\"hunk\">\(escape(hunk.header))</div>"
      rows += renderLines(hunk.lines)
    }
    return "<div class=\"diff\">\(rows)</div>"
  }

  // MARK: - Lines (with intra-line word diff on paired changes)

  private static func renderLines(_ lines: [DiffLine]) -> String {
    var html = ""
    var index = 0
    while index < lines.count {
      let line = lines[index]
      switch line.kind {
      case .context:
        html += row(line, code: escape(line.text), cssClass: "ctx")
        index += 1
      case .noNewline:
        html += "<div class=\"row meta\"><span class=\"ln\"></span><span class=\"ln\"></span>"
        html += "<span class=\"code\">\\ No newline at end of file</span></div>"
        index += 1
      case .removed:
        // Gather the maximal removed run, then any immediately following added
        // run, and word-diff the index-aligned pairs.
        var removed: [DiffLine] = []
        while index < lines.count, lines[index].kind == .removed {
          removed.append(lines[index])
          index += 1
        }
        var added: [DiffLine] = []
        while index < lines.count, lines[index].kind == .added {
          added.append(lines[index])
          index += 1
        }
        html += renderChangeBlock(removed: removed, added: added)
      case .added:
        // Added run with no preceding removed (pure insertion).
        var added: [DiffLine] = []
        while index < lines.count, lines[index].kind == .added {
          added.append(lines[index])
          index += 1
        }
        for line in added { html += row(line, code: escape(line.text), cssClass: "add") }
      }
    }
    return html
  }

  private static func renderChangeBlock(removed: [DiffLine], added: [DiffLine]) -> String {
    var html = ""
    let paired = min(removed.count, added.count)
    for offset in 0..<paired {
      let segs = WordDiff.segments(old: removed[offset].text, new: added[offset].text)
      html += row(removed[offset], code: highlighted(segs.old), cssClass: "del")
      html += row(added[offset], code: highlighted(segs.new), cssClass: "add")
    }
    for line in removed.dropFirst(paired) { html += row(line, code: escape(line.text), cssClass: "del") }
    for line in added.dropFirst(paired) { html += row(line, code: escape(line.text), cssClass: "add") }
    return html
  }

  private static func highlighted(_ segments: [WordDiff.Segment]) -> String {
    segments.map { $0.changed ? "<span class=\"w\">\(escape($0.text))</span>" : escape($0.text) }
      .joined()
  }

  private static func row(_ line: DiffLine, code: String, cssClass: String) -> String {
    let oldNum = line.oldLineNumber.map(String.init) ?? ""
    let newNum = line.newLineNumber.map(String.init) ?? ""
    return """
      <div class="row \(cssClass)"><span class="ln">\(oldNum)</span>\
      <span class="ln">\(newNum)</span><span class="code">\(code.isEmpty ? " " : code)</span></div>
      """
  }

  // MARK: - Header bits

  private static func statusBadge(_ status: ChangedFileStatus) -> String {
    let cls: String
    switch status {
    case .added: cls = "s-add"
    case .modified: cls = "s-mod"
    case .deleted: cls = "s-del"
    case .renamed: cls = "s-ren"
    case .copied: cls = "s-cop"
    case .unmerged: cls = "s-unm"
    case .untracked: cls = "s-unt"
    }
    return "<span class=\"badge \(cls)\">\(status.badge)</span>"
  }

  private static func countsBadge(file: ChangedFile, diffs: [ChangedFile.ID: FileDiff]) -> String {
    guard let diff = diffs[file.id], !diff.isBinary else { return "" }
    var html = ""
    if diff.removedLines > 0 { html += "<span class=\"c-del\">−\(diff.removedLines)</span>" }
    if diff.addedLines > 0 { html += "<span class=\"c-add\">+\(diff.addedLines)</span>" }
    return "<span class=\"counts\">\(html)</span>"
  }

  private static func note(_ text: String) -> String {
    "<div class=\"note\">\(escape(text))</div>"
  }

  // MARK: - Escaping

  /// Entity-encodes text so file contents can't inject markup. Order matters:
  /// `&` first.
  static func escape(_ text: String) -> String {
    var out = text.replacing("&", with: "&amp;")
    out = out.replacing("<", with: "&lt;")
    out = out.replacing(">", with: "&gt;")
    out = out.replacing("\"", with: "&quot;")
    return out
  }

  // MARK: - Stylesheet

  private static let css = """
    :root {
      color-scheme: light dark;
      --bg: #ffffff; --fg: #1f2328; --muted: #59636e; --border: #d1d9e0;
      --hunk-bg: #f6f8fa; --add-bg: rgba(46,160,67,0.15); --del-bg: rgba(248,81,73,0.15);
      --add-word: rgba(46,160,67,0.40); --del-word: rgba(248,81,73,0.40);
      --green: #1a7f37; --red: #cf222e;
    }
    @media (prefers-color-scheme: dark) {
      :root {
        --bg: #0d1117; --fg: #e6edf3; --muted: #9198a1; --border: #30363d;
        --hunk-bg: #161b22; --add-bg: rgba(46,160,67,0.18); --del-bg: rgba(248,81,73,0.18);
        --add-word: rgba(46,160,67,0.45); --del-word: rgba(248,81,73,0.45);
        --green: #3fb950; --red: #f85149;
      }
    }
    * { box-sizing: border-box; }
    body {
      margin: 0; padding: 8px; background: var(--bg); color: var(--fg);
      font: 12px ui-monospace, "SF Mono", Menlo, monospace; -webkit-user-select: text;
    }
    .file { border: 1px solid var(--border); border-radius: 8px; margin-bottom: 8px; overflow: hidden; }
    summary {
      display: flex; align-items: center; gap: 6px; padding: 6px 8px; cursor: default;
      list-style: none; background: var(--hunk-bg); font-weight: 500; user-select: none;
    }
    summary::-webkit-details-marker { display: none; }
    .chev {
      width: 0; height: 0; border-left: 5px solid var(--muted);
      border-top: 4px solid transparent; border-bottom: 4px solid transparent;
      transition: transform .12s; flex: none;
    }
    details[open] > summary .chev { transform: rotate(90deg); }
    .badge {
      flex: none; width: 15px; height: 15px; border-radius: 3px; font-size: 10px; font-weight: 700;
      display: inline-flex; align-items: center; justify-content: center;
    }
    .s-add { color: var(--green); background: rgba(46,160,67,0.18); }
    .s-mod { color: #9a6700; background: rgba(210,153,34,0.20); }
    .s-del { color: var(--red); background: rgba(248,81,73,0.18); }
    .s-ren { color: #0969da; background: rgba(9,105,218,0.18); }
    .s-cop { color: #1b7c83; background: rgba(27,124,131,0.18); }
    .s-unm { color: #8250df; background: rgba(130,80,223,0.18); }
    .s-unt { color: var(--muted); background: rgba(140,140,140,0.18); }
    .name { white-space: nowrap; }
    .dir { color: var(--muted); font-size: 11px; overflow: hidden; text-overflow: ellipsis; }
    .spacer { flex: 1 1 auto; }
    .counts { flex: none; display: flex; gap: 6px; }
    .c-add { color: var(--green); }
    .c-del { color: var(--red); }
    .diff { overflow-x: auto; }
    .hunk { padding: 1px 8px; color: var(--muted); background: var(--hunk-bg); white-space: pre; }
    .row { display: flex; min-width: max-content; }
    .row.add { background: var(--add-bg); }
    .row.del { background: var(--del-bg); }
    .ln {
      flex: none; width: 44px; padding: 0 6px; text-align: right; color: var(--muted);
      user-select: none; position: sticky; background: inherit;
    }
    .row .ln:nth-child(1) { left: 0; }
    .row .ln:nth-child(2) { left: 44px; }
    .code { white-space: pre; padding: 0 6px; flex: 1 1 auto; }
    .row.add .w { background: var(--add-word); border-radius: 2px; }
    .row.del .w { background: var(--del-word); border-radius: 2px; }
    .meta .code { color: var(--muted); }
    .note { padding: 8px; color: var(--muted); }
    """
}
