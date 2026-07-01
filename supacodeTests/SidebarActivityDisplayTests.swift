import Foundation
import SupacodeSettingsShared
import Testing

@testable import supacode

struct SidebarActivityDisplayTests {
  // MARK: - Relative time formatting.

  @Test func relativeTimeBuckets() {
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    func ago(_ seconds: TimeInterval) -> String {
      RelativeTimeText.short(for: now.addingTimeInterval(-seconds), relativeTo: now)
    }
    #expect(ago(5) == "just now")
    #expect(ago(120) == "2m ago")
    #expect(ago(3 * 3_600) == "3h ago")
    #expect(ago(3 * 86_400) == "3d ago")
    #expect(ago(6 * 86_400) == "6d ago")
  }

  @Test func beyondAWeekShowsAbsoluteDate() {
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    func ago(_ seconds: TimeInterval) -> String {
      RelativeTimeText.short(for: now.addingTimeInterval(-seconds), relativeTo: now)
    }
    // Past a week the relative "Xd ago" form gives way to a calendar date.
    let twelveDays = ago(12 * 86_400)
    #expect(!twelveDays.hasSuffix("ago"))
    #expect(!twelveDays.isEmpty)

    let twoYears = ago(2 * 365 * 86_400)
    #expect(!twoYears.hasSuffix("ago"))
    #expect(!twoYears.isEmpty)
  }

  @Test func futureDateClampsToJustNow() {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(RelativeTimeText.short(for: now.addingTimeInterval(500), relativeTo: now) == "just now")
  }
}
