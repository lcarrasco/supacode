import Foundation
import Testing

@testable import supacode

@Suite struct UnifiedDiffParserTests {
  // MARK: - Changed-file list

  @Test func parsesPorcelainModifiedAddedDeletedUntracked() {
    // ` M keep.txt`, `D  todelete.txt`, `?? untracked.txt`, `A  added.txt`
    let raw = " M keep.txt\u{0}D  todelete.txt\u{0}?? untracked.txt\u{0}A  added.txt\u{0}"
    let files = UnifiedDiffParser.parseChangedFiles(porcelainZ: raw)
    #expect(files.count == 4)
    let byPath = Dictionary(uniqueKeysWithValues: files.map { ($0.path, $0.status) })
    #expect(byPath["keep.txt"] == .modified)
    #expect(byPath["todelete.txt"] == .deleted)
    #expect(byPath["untracked.txt"] == .untracked)
    #expect(byPath["added.txt"] == .added)
  }

  @Test func parsesRenameConsumingSourceToken() {
    // `RM renamed.txt` then the source `orig.txt` as a separate NUL field.
    let raw = "RM renamed.txt\u{0}orig.txt\u{0} M keep.txt\u{0}"
    let files = UnifiedDiffParser.parseChangedFiles(porcelainZ: raw)
    #expect(files.count == 2)
    let rename = files.first { $0.status == .renamed }
    #expect(rename?.path == "renamed.txt")
    #expect(rename?.previousPath == "orig.txt")
    // The trailing modified entry must still parse (source token consumed correctly).
    #expect(files.contains { $0.path == "keep.txt" && $0.status == .modified })
  }

  @Test func sortsByPathCaseInsensitively() {
    let raw = " M Zebra.txt\u{0} M alpha.txt\u{0}"
    let files = UnifiedDiffParser.parseChangedFiles(porcelainZ: raw)
    #expect(files.map(\.path) == ["alpha.txt", "Zebra.txt"])
  }

  // MARK: - Unified diff

  @Test func parsesHunkLineNumbersAndKinds() {
    let raw = """
      diff --git a/App.swift b/App.swift
      index 111..222 100644
      --- a/App.swift
      +++ b/App.swift
      @@ -1,3 +1,3 @@
       context
      -old line
      +new line
       tail
      """
    let diff = UnifiedDiffParser.parseFileDiff(raw)
    #expect(diff.isBinary == false)
    #expect(diff.hunks.count == 1)
    let lines = diff.hunks[0].lines
    #expect(lines.map(\.kind) == [.context, .removed, .added, .context])
    // Context starts at old=1/new=1.
    #expect(lines[0].oldLineNumber == 1)
    #expect(lines[0].newLineNumber == 1)
    // Removed advances only the old side.
    #expect(lines[1].oldLineNumber == 2)
    #expect(lines[1].newLineNumber == nil)
    // Added advances only the new side.
    #expect(lines[2].oldLineNumber == nil)
    #expect(lines[2].newLineNumber == 2)
    // Trailing context realigned on both sides.
    #expect(lines[3].oldLineNumber == 3)
    #expect(lines[3].newLineNumber == 3)
  }

  @Test func detectsBinaryDiff() {
    let raw = """
      diff --git a/logo.png b/logo.png
      Binary files a/logo.png and b/logo.png differ
      """
    let diff = UnifiedDiffParser.parseFileDiff(raw)
    #expect(diff.isBinary)
    #expect(diff.hunks.isEmpty)
  }

  // MARK: - Untracked synthesized diff

  @Test func synthesizesAllAddedDiffForUntrackedText() {
    let data = Data("first\nsecond\n".utf8)
    let diff = UnifiedDiffParser.untrackedFileDiff(data: data)
    #expect(diff.isBinary == false)
    #expect(diff.hunks.count == 1)
    let lines = diff.hunks[0].lines
    #expect(lines.count == 2)
    #expect(lines.allSatisfy { $0.kind == .added })
    #expect(lines.map(\.newLineNumber) == [1, 2])
    #expect(lines.map(\.text) == ["first", "second"])
  }

  @Test func detectsBinaryUntrackedViaNulByte() {
    let data = Data([0x41, 0x00, 0x42])
    let diff = UnifiedDiffParser.untrackedFileDiff(data: data)
    #expect(diff.isBinary)
  }

  @Test func emptyUntrackedFileYieldsEmptyDiff() {
    #expect(UnifiedDiffParser.untrackedFileDiff(data: Data()) == .empty)
  }
}
