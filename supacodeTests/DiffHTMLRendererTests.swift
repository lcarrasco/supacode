import Foundation
import Testing

@testable import supacode

@Suite struct WordDiffTests {
  @Test func highlightsOnlyChangedTokens() {
    let (old, new) = WordDiff.segments(old: "let value = 1", new: "let value = 2")
    // Shared prefix stays unchanged; only the trailing number differs.
    #expect(old.contains(WordDiff.Segment(text: "1", changed: true)))
    #expect(new.contains(WordDiff.Segment(text: "2", changed: true)))
    #expect(old.contains { $0.text.contains("value") && !$0.changed })
  }

  @Test func identicalLinesHaveNoChangedSegments() {
    let (old, new) = WordDiff.segments(old: "same", new: "same")
    #expect(old.allSatisfy { !$0.changed })
    #expect(new.allSatisfy { !$0.changed })
  }

  @Test func wholeLineChangedWhenNothingInCommon() {
    let (old, new) = WordDiff.segments(old: "aaa", new: "bbb")
    #expect(old == [WordDiff.Segment(text: "aaa", changed: true)])
    #expect(new == [WordDiff.Segment(text: "bbb", changed: true)])
  }
}

@Suite struct DiffHTMLRendererTests {
  private nonisolated static let file = ChangedFile(path: "src/App.swift", previousPath: nil, status: .modified)

  @Test func escapesFileContentToPreventInjection() {
    let diff = FileDiff(
      hunks: [
        DiffHunk(
          id: 0,
          header: "@@ -1 +1 @@",
          lines: [
            DiffLine(id: 0, kind: .added, text: "<script>alert(1)</script>", oldLineNumber: nil, newLineNumber: 1)
          ]
        )
      ],
      isBinary: false
    )
    let html = DiffHTMLRenderer.document(
      files: [Self.file], diffs: [Self.file.id: diff], failedIDs: [], diffsSettled: true
    )
    #expect(!html.contains("<script>alert(1)</script>"))
    #expect(html.contains("&lt;script&gt;"))
  }

  @Test func rendersFileHeaderAndCounts() {
    let diff = FileDiff(
      hunks: [
        DiffHunk(
          id: 0,
          header: "@@ -1,2 +1,2 @@",
          lines: [
            DiffLine(id: 0, kind: .removed, text: "old", oldLineNumber: 1, newLineNumber: nil),
            DiffLine(id: 1, kind: .added, text: "new", oldLineNumber: nil, newLineNumber: 1),
          ]
        )
      ],
      isBinary: false
    )
    let html = DiffHTMLRenderer.document(
      files: [Self.file], diffs: [Self.file.id: diff], failedIDs: [], diffsSettled: true
    )
    #expect(html.contains("App.swift"))
    #expect(html.contains("src"))  // directory tag
    #expect(html.contains("+1"))
    #expect(html.contains("−1"))
    #expect(html.contains("<details open"))
  }

  @Test func showsLoadingPlaceholderUntilSettled() {
    let html = DiffHTMLRenderer.document(
      files: [Self.file], diffs: [:], failedIDs: [], diffsSettled: false
    )
    #expect(html.contains("Loading"))
  }

  @Test func showsErrorWhenSettledButMissing() {
    let html = DiffHTMLRenderer.document(
      files: [Self.file], diffs: [:], failedIDs: [Self.file.id], diffsSettled: true
    )
    #expect(html.contains("Couldn't load diff"))
  }

  @Test func emitsLanguageAndChangedRanges() {
    let diff = FileDiff(
      hunks: [
        DiffHunk(
          id: 0,
          header: "@@ -1 +1 @@",
          lines: [
            DiffLine(id: 0, kind: .removed, text: "let value = 1", oldLineNumber: 1, newLineNumber: nil),
            DiffLine(id: 1, kind: .added, text: "let value = 2", oldLineNumber: nil, newLineNumber: 1),
          ]
        )
      ],
      isBinary: false
    )
    let html = DiffHTMLRenderer.document(
      files: [Self.file], diffs: [Self.file.id: diff], failedIDs: [], diffsSettled: true
    )
    #expect(html.contains("data-l=\"swift\""))
    // The trailing "1"/"2" differ → a change range is emitted.
    #expect(html.contains("data-c="))
  }

  @Test func emitsAbsolutePathWhenWorktreeDirectoryGiven() {
    let html = DiffHTMLRenderer.document(
      files: [Self.file],
      diffs: [:],
      failedIDs: [],
      diffsSettled: true,
      worktreeDirectory: URL(fileURLWithPath: "/tmp/wt")
    )
    #expect(html.contains("data-path=\"/tmp/wt/src/App.swift\""))
  }

  @Test func omitsPathWhenNoWorktreeDirectory() {
    let html = DiffHTMLRenderer.document(
      files: [Self.file], diffs: [:], failedIDs: [], diffsSettled: true
    )
    #expect(!html.contains("data-path="))
  }

  @Test func languageMapsCommonExtensions() {
    #expect(DiffHTMLRenderer.language(forPath: "a/b/File.swift") == "swift")
    #expect(DiffHTMLRenderer.language(forPath: "x.yml") == "yaml")
    #expect(DiffHTMLRenderer.language(forPath: "x.tsx") == "typescript")
    #expect(DiffHTMLRenderer.language(forPath: "lib/main.dart") == "dart")
    #expect(DiffHTMLRenderer.language(forPath: "Makefile") == nil)
  }

  @Test func notesOmittedFiles() {
    let html = DiffHTMLRenderer.document(
      files: [Self.file], diffs: [:], failedIDs: [], diffsSettled: true, omittedCount: 5
    )
    #expect(html.contains("5 more file"))
  }
}
