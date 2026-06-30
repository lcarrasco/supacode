import Foundation

/// Token-level intra-line diff used to highlight the *changed segments* of a
/// modified line (t3code's darker word highlight), not just the whole line.
/// Pure + stateless so it unit-tests without UI.
nonisolated enum WordDiff {
  struct Segment: Equatable, Sendable {
    let text: String
    let changed: Bool
  }

  /// Skip the O(n·m) LCS for very long lines — they'd be slow and rarely
  /// benefit from word granularity; the caller treats them as wholly changed.
  private static let maxTokensForPairing = 400

  /// Segments the old and new variants of a changed line, marking tokens that
  /// don't appear in the common subsequence as `changed`.
  static func segments(old: String, new: String) -> (old: [Segment], new: [Segment]) {
    let oldTokens = tokenize(old)
    let newTokens = tokenize(new)
    guard oldTokens.count <= maxTokensForPairing, newTokens.count <= maxTokensForPairing else {
      return (
        old: old.isEmpty ? [] : [Segment(text: old, changed: true)],
        new: new.isEmpty ? [] : [Segment(text: new, changed: true)]
      )
    }
    let (oldKept, newKept) = longestCommonSubsequence(oldTokens, newTokens)
    return (
      old: merge(tokens: oldTokens, kept: oldKept),
      new: merge(tokens: newTokens, kept: newKept)
    )
  }

  /// Groups characters into word runs (letters/digits/underscore) and emits
  /// every other character as its own token, so punctuation aligns cleanly.
  private static func tokenize(_ string: String) -> [String] {
    var tokens: [String] = []
    var current = ""
    for character in string {
      if character.isLetter || character.isNumber || character == "_" {
        current.append(character)
      } else {
        if !current.isEmpty {
          tokens.append(current)
          current = ""
        }
        tokens.append(String(character))
      }
    }
    if !current.isEmpty { tokens.append(current) }
    return tokens
  }

  /// Standard LCS DP returning, for each side, which token indices are part of
  /// the common subsequence (i.e. unchanged).
  private static func longestCommonSubsequence(
    _ lhs: [String],
    _ rhs: [String]
  ) -> (lhsKept: Set<Int>, rhsKept: Set<Int>) {
    let lhsCount = lhs.count
    let rhsCount = rhs.count
    guard lhsCount > 0, rhsCount > 0 else { return ([], []) }
    var table = [[Int]](
      repeating: [Int](repeating: 0, count: rhsCount + 1),
      count: lhsCount + 1
    )
    for lhsIndex in stride(from: lhsCount - 1, through: 0, by: -1) {
      for rhsIndex in stride(from: rhsCount - 1, through: 0, by: -1) {
        if lhs[lhsIndex] == rhs[rhsIndex] {
          table[lhsIndex][rhsIndex] = table[lhsIndex + 1][rhsIndex + 1] + 1
        } else {
          table[lhsIndex][rhsIndex] = max(table[lhsIndex + 1][rhsIndex], table[lhsIndex][rhsIndex + 1])
        }
      }
    }
    var lhsKept: Set<Int> = []
    var rhsKept: Set<Int> = []
    var lhsIndex = 0
    var rhsIndex = 0
    while lhsIndex < lhsCount, rhsIndex < rhsCount {
      if lhs[lhsIndex] == rhs[rhsIndex] {
        lhsKept.insert(lhsIndex)
        rhsKept.insert(rhsIndex)
        lhsIndex += 1
        rhsIndex += 1
      } else if table[lhsIndex + 1][rhsIndex] >= table[lhsIndex][rhsIndex + 1] {
        lhsIndex += 1
      } else {
        rhsIndex += 1
      }
    }
    return (lhsKept, rhsKept)
  }

  /// Collapses consecutive tokens of the same changed-ness into segments.
  private static func merge(tokens: [String], kept: Set<Int>) -> [Segment] {
    var segments: [Segment] = []
    for (index, token) in tokens.enumerated() {
      let changed = !kept.contains(index)
      if var last = segments.last, last.changed == changed {
        last = Segment(text: last.text + token, changed: changed)
        segments[segments.count - 1] = last
      } else {
        segments.append(Segment(text: token, changed: changed))
      }
    }
    return segments
  }
}
