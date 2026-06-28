import Foundation
import SupacodeSettingsShared
import Testing

@testable import supacode

struct SidebarActivityDisplayTests {
  // MARK: - AgentStatusPill priority.

  @Test func noAgentsYieldsNoPill() {
    #expect(AgentStatusPill.resolve([]) == nil)
  }

  @Test func busyAgentWinsAsWorking() {
    let agents = [
      AgentPresenceFeature.AgentInstance(agent: .claude, activity: .idle),
      AgentPresenceFeature.AgentInstance(agent: .claude, activity: .awaitingInput),
      AgentPresenceFeature.AgentInstance(agent: .claude, activity: .busy),
    ]
    #expect(AgentStatusPill.resolve(agents) == .working)
  }

  @Test func awaitingInputOutranksIdle() {
    let agents = [
      AgentPresenceFeature.AgentInstance(agent: .claude, activity: .idle),
      AgentPresenceFeature.AgentInstance(agent: .claude, activity: .awaitingInput),
    ]
    #expect(AgentStatusPill.resolve(agents) == .waiting)
  }

  @Test func idleOnlyReadsAsCompleted() {
    let agents = [AgentPresenceFeature.AgentInstance(agent: .claude, activity: .idle)]
    #expect(AgentStatusPill.resolve(agents) == .completed)
  }

  // MARK: - Relative time formatting.

  @Test func relativeTimeBuckets() {
    let now = Date(timeIntervalSince1970: 1_000_000_000)
    func ago(_ seconds: TimeInterval) -> String {
      RelativeTimeText.short(for: now.addingTimeInterval(-seconds), relativeTo: now)
    }
    #expect(ago(5) == "just now")
    #expect(ago(120) == "2m ago")
    #expect(ago(3 * 3_600) == "3h ago")
    #expect(ago(24 * 86_400) == "24d ago")
    #expect(ago(2 * 2_592_000) == "2mo ago")
    #expect(ago(3 * 31_536_000) == "3y ago")
  }

  @Test func futureDateClampsToJustNow() {
    let now = Date(timeIntervalSince1970: 1_000)
    #expect(RelativeTimeText.short(for: now.addingTimeInterval(500), relativeTo: now) == "just now")
  }
}
