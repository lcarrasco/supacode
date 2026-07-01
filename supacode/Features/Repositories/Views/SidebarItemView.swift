import ComposableArchitecture
import SupacodeSettingsShared
import SwiftUI

/// Layout constants shared by the leaf row (`SidebarItemView`) and the group
/// header row so indentation stays in lock-step across both view files.
enum SidebarNestLayout {
  /// Pixel step a row indents per branch-nesting depth level.
  static let indentStep: CGFloat = 14
  /// Leading space reserved for the section rail so the row content sits to the
  /// right of the vertical guide line.
  static let railGutter: CGFloat = 27
  /// Where the 1pt rail sits within that gutter, measured from the leading edge
  /// (roughly under the repo header's favicon column).
  static let railLeadingInset: CGFloat = 23
}

/// Continuous leading guide line for in-section rows. Lives in a
/// `listRowBackground` so it fills the entire cell (including the sidebar
/// style's inter-row padding) and joins edge-to-edge with neighboring rows.
struct SidebarRailBackground: View {
  var body: some View {
    Rectangle()
      .fill(.quaternary)
      .frame(width: 1)
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
      .padding(.leading, SidebarNestLayout.railLeadingInset)
      .accessibilityHidden(true)
  }
}

/// Applies the rail background only to in-section rows; hoisted Pinned / Active
/// rows keep the List's default background so their selection highlight stays.
private struct SidebarRailBackgroundModifier: ViewModifier {
  let active: Bool

  func body(content: Content) -> some View {
    if active {
      content.listRowBackground(SidebarRailBackground())
    } else {
      content
    }
  }
}

/// Repo identity carried alongside a sidebar row so the highlight sections
/// can render a colored `repo · worktree` subtitle that mirrors the window
/// toolbar. `nil` on a row keeps the standard per-repo subtitle.
struct SidebarHighlightRepoTag: Equatable, Hashable, Sendable {
  let repoName: String
  let repoColor: RepositoryColor?
  /// `[user@]host[:port]` when the repo is remote, else nil; shown as `· host`
  /// plus a `wifi` glyph in the subtitle.
  let hostInfo: String?
}

struct SidebarItemView: View {
  let store: StoreOf<SidebarItemFeature>
  let hideSubtitle: Bool
  let hideSubtitleOnMatch: Bool
  let showsPullRequestInfo: Bool
  let shortcutHint: String?
  /// Trailing branch-component label injected by the branch-nesting renderer so
  /// a row nested under a `feature/tools` header reads as `a` instead of the
  /// full `feature/tools/a`. `nil` keeps the original branch name.
  var displayNameOverride: String?
  /// Number of group-header ancestors above this row, used by the renderer
  /// to apply a per-level leading indent. `0` keeps the existing baseline.
  var nestDepth: Int = 0
  /// Non-nil only inside the global Pinned / Active sections.
  var highlightSubtitle: SidebarHighlightRepoTag?

  var body: some View {
    let resolved = ResolvedRowDisplay(
      kind: store.kind,
      branchName: displayNameOverride ?? store.branchName,
      worktreeName: store.sidebarDisplayName,
      isMainWorktree: store.isMainWorktree,
      isPinned: store.isPinned,
      hideSubtitle: hideSubtitle,
      hideSubtitleOnMatch: hideSubtitleOnMatch,
      highlightSubtitle: highlightSubtitle,
      customTitle: store.customTitle,
      customTint: store.customTint
    )

    // "Needs attention" reads as an unread row: bold + full-prominence title,
    // replacing the old notification dot. Sourced from state so it clears on
    // read and doesn't flicker with agent activity.
    let requiresAttention = store.requiresAttention

    Label {
      HStack(spacing: 8) {
        TitleView(
          name: resolved.name,
          accent: resolved.accent,
          customTint: store.customTint,
          requiresAttention: requiresAttention,
          isLifecycleBusy: store.lifecycle.isBusy,
          isTaskRunning: store.isTaskRunning
        )
        .equatable()
        Spacer(minLength: 0)
        TrailingView(
          store: store,
          shortcutHint: shortcutHint,
          showsPullRequestInfo: showsPullRequestInfo
        )
      }
    } icon: {
      IconView(
        isFolder: store.kind == .folder,
        isRemote: store.isRemote,
        isMissing: store.isMissing,
        branchName: store.branchName,
        pullRequest: store.pullRequest,
        showsPullRequestInfo: showsPullRequestInfo,
        lifecycle: store.lifecycle
      )
    }
    .labelStyle(.verticallyCentered)
    // Rows inside a repo / folder section get a leading vertical rail (à la
    // t3code) that visually ties the group together; hoisted Pinned / Active
    // rows (highlightSubtitle != nil) render flush without it. The rail rides a
    // `listRowBackground` (not an overlay) so it fills the full cell height,
    // including the sidebar style's inter-row padding, and reads as one
    // continuous line instead of breaking at every row gap.
    .padding(.leading, showsRail ? SidebarNestLayout.railGutter : 0)
    .padding(.vertical, 6)
    .modifier(SidebarRailBackgroundModifier(active: showsRail))
    .listRowInsets(.leading, CGFloat(nestDepth) * SidebarNestLayout.indentStep)
    .listRowInsets(.trailing, 4)
    .listRowInsets(.vertical, 0)
  }

  /// The leading rail belongs to in-section rows, not the hoisted highlight rows.
  private var showsRail: Bool { highlightSubtitle == nil }
}

struct ResolvedRowDisplay: Equatable {
  enum Subtitle: Equatable {
    case none
    /// Standard per-repo subtitle. Rendered in the row's accent color.
    case plain(String)
    /// Highlight-section subtitle: `repo · host · trail`. `repo` paints with
    /// `repoColor`, `trail` with the row's accent; `hostInfo` (when set) inserts
    /// `· host` plus a `wifi` glyph. `trail == nil` collapses to just the repo.
    case highlight(repo: String, repoColor: RepositoryColor?, trail: String?, hostInfo: String?)
  }

  let name: String
  let subtitle: Subtitle
  let accent: WorktreeAccent

  init(
    kind: SidebarItemFeature.State.Kind,
    branchName: String,
    worktreeName: String?,
    isMainWorktree: Bool,
    isPinned: Bool,
    hideSubtitle: Bool,
    hideSubtitleOnMatch: Bool,
    highlightSubtitle: SidebarHighlightRepoTag? = nil,
    customTitle: String? = nil,
    customTint: RepositoryColor? = nil
  ) {
    self.accent =
      if isMainWorktree { .main } else if isPinned { .pinned } else { .default }

    // User override (trimmed) takes precedence over derived names.
    let resolvedCustom = SidebarDisplayName.resolved(custom: customTitle, fallback: nil)
    let hasCustomTitle = resolvedCustom != nil

    if kind == .folder {
      self.name = resolvedCustom ?? branchName
      // Folder rows ARE the repo; a remote folder's `wifi` glyph rides the title
      // line (via `TitleView`), so there's no subtitle.
      self.subtitle = .none
      return
    }

    let resolvedWorktreeName = worktreeName ?? "Default"
    let effectiveWorktreeName = resolvedWorktreeName.isEmpty ? branchName : resolvedWorktreeName
    self.name = resolvedCustom ?? branchName

    let branchLastComponent = branchName.split(separator: "/").last.map(String.init) ?? branchName
    let isMatch = effectiveWorktreeName == branchLastComponent
    // Once a user types a custom title, they've lost the visual cue that the auto-derived name was
    // providing, so we always render the subtitle even when it would otherwise collapse on match.
    let shouldHideOnMatch = hideSubtitleOnMatch && !hasCustomTitle && isMatch

    if let highlightSubtitle {
      let trail: String?
      if shouldHideOnMatch {
        trail = nil
      } else if isMainWorktree {
        trail = "Default"
      } else if let worktreeName, !worktreeName.isEmpty {
        trail = worktreeName
      } else {
        trail = nil
      }
      self.subtitle = .highlight(
        repo: highlightSubtitle.repoName,
        repoColor: highlightSubtitle.repoColor,
        trail: trail,
        hostInfo: highlightSubtitle.hostInfo
      )
      return
    }

    // The main worktree's "Default" marker now rides a trailing pill (see
    // `DefaultBadgeContent`), so we drop it from the subtitle line entirely.
    if hideSubtitle || shouldHideOnMatch || isMainWorktree {
      self.subtitle = .none
    } else {
      self.subtitle = .plain(effectiveWorktreeName)
    }
  }
}

/// Sidebar status palette lifted from t3code (pingdotgg/t3code,
/// `ThreadStatusIndicators.tsx` / `Sidebar.logic.ts`): Tailwind `*-300` at the
/// dark-mode opacities the project uses (e.g. `dark:text-emerald-300/90`).
enum T3StatusPalette {
  /// teal-300 (#5EEAD4) — t3code's running/branch accent.
  static let teal = Color(.sRGB, red: 94 / 255, green: 234 / 255, blue: 212 / 255, opacity: 0.9)
  /// emerald-300 (#6EE7B7) — open / passing.
  static let emerald = Color(.sRGB, red: 110 / 255, green: 231 / 255, blue: 183 / 255, opacity: 0.9)
  /// amber-300 (#FCD34D) — in progress / pending.
  static let amber = Color(.sRGB, red: 252 / 255, green: 211 / 255, blue: 77 / 255, opacity: 0.9)
  /// red-300 (#FCA5A5) — failing.
  static let red = Color(.sRGB, red: 252 / 255, green: 165 / 255, blue: 165 / 255, opacity: 0.9)
  /// violet-300 (#C4B5FD) — merged.
  static let violet = Color(.sRGB, red: 196 / 255, green: 181 / 255, blue: 253 / 255, opacity: 0.9)
  /// zinc-400 (#A1A1AA) — closed / draft / muted.
  static let zinc = Color(.sRGB, red: 161 / 255, green: 161 / 255, blue: 170 / 255, opacity: 0.8)
}

enum SidebarCheckBadgeState: Equatable {
  case passing
  case failing
  case inProgress

  var accessibilityLabel: String {
    switch self {
    case .passing: "Checks passed"
    case .failing: "Checks failed"
    case .inProgress: "Checks in progress"
    }
  }
}

enum SidebarPullRequestIcon: Equatable {
  case branch
  case open
  case draft
  case queued
  case merged
  case closed

  static func resolve(_ pullRequest: GithubPullRequest?) -> Self {
    guard let pullRequest else { return .branch }
    switch pullRequest.state.uppercased() {
    case "MERGED": return .merged
    case "CLOSED": return .closed
    case "OPEN" where pullRequest.isDraft: return .draft
    case "OPEN" where PullRequestMergeQueueStatus(pullRequest: pullRequest) != nil: return .queued
    case "OPEN": return .open
    default: return .branch
    }
  }

  var assetName: String {
    switch self {
    case .branch: "git-branch"
    case .open: "git-pull-request"
    case .draft: "git-pull-request-draft"
    case .queued: "git-merge-queue"
    case .merged: "git-merge"
    case .closed: "git-pull-request-closed"
    }
  }
}

private func resolveCheckBadgeState(_ pullRequest: GithubPullRequest?) -> SidebarCheckBadgeState? {
  guard let checks = pullRequest?.statusCheckRollup?.checks, !checks.isEmpty else { return nil }
  let breakdown = PullRequestCheckBreakdown(checks: checks)
  if breakdown.failed > 0 { return .failing }
  if breakdown.inProgress > 0 || breakdown.expected > 0 { return .inProgress }
  return .passing
}

private struct TitleView: View, Equatable {
  let name: String
  let accent: WorktreeAccent
  /// User-supplied row tint. When set, paints the title; otherwise the title uses the default.
  let customTint: RepositoryColor?
  /// Unseen notifications / agent awaiting input: render the title as an unread row (bold + bright).
  let requiresAttention: Bool
  let isLifecycleBusy: Bool
  let isTaskRunning: Bool
  // `==` ignores @Environment; SwiftUI tracks env changes separately.
  @Environment(\.backgroundProminence) private var backgroundProminence

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.name == rhs.name
      && lhs.accent == rhs.accent
      && lhs.customTint == rhs.customTint
      && lhs.requiresAttention == rhs.requiresAttention
      && lhs.isLifecycleBusy == rhs.isLifecycleBusy
      && lhs.isTaskRunning == rhs.isTaskRunning
  }

  var body: some View {
    let isBusy = isLifecycleBusy || isTaskRunning
    let isEmphasized = backgroundProminence == .increased
    // Selected row reads in full-prominence white + semibold; a row that needs
    // attention reads the same (unread). Every other row recedes to muted gray
    // (Superset / T3-style), unless the user pinned an explicit row tint.
    let isProminent = isEmphasized || requiresAttention
    let titleStyle: AnyShapeStyle =
      if isProminent {
        AnyShapeStyle(.primary)
      } else if let customTint {
        AnyShapeStyle(customTint.color)
      } else {
        AnyShapeStyle(.secondary)
      }
    Text(name)
      .font(.dmSans(.callout))
      .fontWeight(isProminent ? .semibold : .regular)
      .lineLimit(1)
      .foregroundStyle(titleStyle)
      .shimmer(isActive: isBusy)
  }
}

private struct IconView: View {
  let isFolder: Bool
  let isRemote: Bool
  let isMissing: Bool
  let branchName: String
  let pullRequest: GithubPullRequest?
  let showsPullRequestInfo: Bool
  let lifecycle: SidebarItemFeature.State.Lifecycle

  var body: some View {
    let display = WorktreePullRequestDisplay(
      worktreeName: branchName,
      pullRequest: showsPullRequestInfo ? pullRequest : nil,
    )
    IconContent(
      isFolder: isFolder,
      isRemote: isRemote,
      isMissing: isMissing,
      icon: SidebarPullRequestIcon.resolve(display.pullRequest),
      checkBadgeState: resolveCheckBadgeState(display.pullRequest),
      rowState: IconRowState(lifecycle),
    )
    .equatable()
  }
}

enum IconRowState: Equatable {
  case idle
  case pending
  case archiving
  case deleting

  init(_ lifecycle: SidebarItemFeature.State.Lifecycle) {
    switch lifecycle {
    case .idle: self = .idle
    case .pending: self = .pending
    case .archiving: self = .archiving
    case .deleting, .deletingScript: self = .deleting
    }
  }
}

private struct IconContent: View, Equatable {
  let isFolder: Bool
  let isRemote: Bool
  let isMissing: Bool
  let icon: SidebarPullRequestIcon
  let checkBadgeState: SidebarCheckBadgeState?
  let rowState: IconRowState
  // `==` ignores @Environment; SwiftUI tracks env changes separately.
  @Environment(\.backgroundProminence) private var backgroundProminence

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.isFolder == rhs.isFolder
      && lhs.isRemote == rhs.isRemote
      && lhs.isMissing == rhs.isMissing
      && lhs.icon == rhs.icon
      && lhs.checkBadgeState == rhs.checkBadgeState
      && lhs.rowState == rhs.rowState
  }

  private var isEmphasized: Bool {
    backgroundProminence == .increased
  }

  private var isSystemImage: Bool {
    rowState != .idle || isFolder || isMissing
  }

  /// Show the leading PR glyph for any row backed by a pull request (open,
  /// draft, queued, merged, closed). Idle git rows with no PR render a
  /// transparent placeholder so titles stay aligned without an icon.
  private var showsBranchIcon: Bool {
    icon != .branch
  }

  /// State-driven tint for the leading glyph, folding the old CI check badge
  /// into the icon color using t3code's palette (`T3StatusPalette`): merged is
  /// violet, draft / closed read zinc-gray, and a live PR (open / merge-queued)
  /// takes its CI color — emerald passing, amber in progress, red failing —
  /// falling back to teal when it has no checks yet. Selection flattens
  /// everything to `.secondary` for legibility on the highlight fill.
  private var branchIconStyle: AnyShapeStyle {
    guard !isEmphasized else { return AnyShapeStyle(.secondary) }
    switch icon {
    case .merged: return AnyShapeStyle(T3StatusPalette.violet)
    case .closed, .draft: return AnyShapeStyle(T3StatusPalette.zinc)
    case .open, .queued:
      switch checkBadgeState {
      case .passing: return AnyShapeStyle(T3StatusPalette.emerald)
      case .inProgress: return AnyShapeStyle(T3StatusPalette.amber)
      case .failing: return AnyShapeStyle(T3StatusPalette.red)
      case .none: return AnyShapeStyle(T3StatusPalette.teal)
      }
    case .branch: return AnyShapeStyle(.secondary)
    }
  }

  private var folderIconName: String {
    if isMissing { return "exclamationmark.triangle.fill" }
    switch rowState {
    case .pending: return "truck.box.badge.clock"
    case .archiving: return "archivebox"
    case .deleting: return "trash"
    case .idle: return "folder"
    }
  }

  private var folderColor: AnyShapeStyle {
    guard !isEmphasized else { return AnyShapeStyle(.secondary) }
    if isMissing { return AnyShapeStyle(.orange) }
    switch rowState {
    case .pending: return AnyShapeStyle(.blue)
    case .archiving: return AnyShapeStyle(.orange)
    case .deleting: return AnyShapeStyle(.red)
    case .idle: return AnyShapeStyle(.secondary)
    }
  }

  private var accessibilityLabel: String? {
    if isMissing { return "Working directory missing" }
    switch rowState {
    case .pending: return "Creating"
    case .archiving: return "Archiving"
    case .deleting: return "Deleting"
    case .idle: break
    }
    // The CI check badge is gone (folded into the icon color), so surface its
    // state here instead — color alone isn't accessible.
    switch icon {
    case .open, .queued: return checkBadgeState?.accessibilityLabel
    default: return nil
    }
  }

  var body: some View {
    Group {
      if isSystemImage {
        Image(systemName: folderIconName)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .fontWeight(.semibold)
          .foregroundStyle(folderColor)
      } else if showsBranchIcon {
        Image(icon.assetName)
          .renderingMode(.template)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .foregroundStyle(branchIconStyle)
      } else {
        // No open PR: keep the icon slot empty so titles stay left-aligned.
        Color.clear
      }
    }
    .frame(width: 13, height: 13)
    .accessibilityLabel(accessibilityLabel ?? "")
    .accessibilityHidden(accessibilityLabel == nil)
  }
}

private struct TrailingView: View {
  let store: StoreOf<SidebarItemFeature>
  let shortcutHint: String?
  let showsPullRequestInfo: Bool

  var body: some View {
    let hasHint = shortcutHint != nil
    let display = WorktreePullRequestDisplay(
      worktreeName: store.branchName,
      pullRequest: showsPullRequestInfo ? store.pullRequest : nil,
    )
    let prText = display.pullRequestBadgeStyle?.text
    let prURL = display.pullRequest.flatMap { URL(string: $0.url) }
    let lastActiveAt = store.lastActiveAt

    // Cross-fade via opacity so flipping ⌘ doesn't snap the row.
    ZStack(alignment: .trailing) {
      HStack(spacing: 6) {
        if store.isMainWorktree {
          DefaultBadgeContent()
        }
        if store.kind == .folder, let host = store.host {
          Image(systemName: "wifi")
            .imageScale(.small)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .help(host.displayAuthority)
            .accessibilityLabel("Remote host \(host.displayAuthority)")
        }
        if let lastActiveAt {
          RelativeDateContent(date: lastActiveAt)
            .equatable()
        }
        if let prText {
          PullRequestBadgeContent(text: prText, url: prURL)
            .equatable()
        }
      }
      // Title takes the squeeze under narrow widths, not the counters.
      .fixedSize(horizontal: true, vertical: false)
      .opacity(hasHint ? 0 : 1)
      .allowsHitTesting(!hasHint)

      Text(shortcutHint ?? "")
        .font(.dmSans(.caption))
        .foregroundStyle(.secondary)
        .opacity(hasHint ? 1 : 0)
    }
    .animation(.easeInOut(duration: TerminalTabBarMetrics.fadeAnimationDuration), value: hasHint)
  }
}

/// Trailing "default" pill marking the repo's main worktree. Lowercase, muted
/// gray text inside a subtle gray capsule — quieter than the old yellow label.
private struct DefaultBadgeContent: View, Equatable {
  var body: some View {
    Text("default")
      .font(.dmSans(.caption2))
      .foregroundStyle(.tertiary)
      .padding(.horizontal, 6)
      .padding(.vertical, 1)
      .background(.quaternary, in: Capsule())
  }
}

private struct PullRequestBadgeContent: View, Equatable {
  let text: String
  let url: URL?
  // `==` ignores @Environment; SwiftUI tracks env changes separately.
  @Environment(\.openURL) private var openURL

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text && lhs.url == rhs.url }

  var body: some View {
    let label = Text(text)
      .font(.dmSans(.caption))
      .foregroundStyle(.secondary)
      .transition(.blurReplace)
    if let url {
      Button {
        openURL(url)
      } label: {
        label
      }
      .buttonStyle(.plain)
      .contentShape(.rect)
      .help("Open pull request on GitHub")
      .accessibilityLabel("Open pull request on GitHub")
    } else {
      label
    }
  }
}

/// "Last active" relative timestamp shown where diff stats used to live.
/// Compact form ("just now", "5m ago", "24d ago") à la the reference sidebar.
private struct RelativeDateContent: View, Equatable {
  let date: Date
  // `==` ignores @Environment; SwiftUI tracks env changes separately.
  @Environment(\.backgroundProminence) private var backgroundProminence

  static func == (lhs: Self, rhs: Self) -> Bool { lhs.date == rhs.date }

  var body: some View {
    // t3code: very dim by default (`text-muted-foreground/40`), brighter on the
    // selected row (`text-foreground/82`).
    let isEmphasized = backgroundProminence == .increased
    Text(RelativeTimeText.short(for: date))
      .font(.dmSans(.caption))
      .foregroundStyle(isEmphasized ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
      .monospacedDigit()
      .transition(.blurReplace)
  }
}

/// Compact relative-time formatting for the sidebar's "last active" label.
/// Recomputed at render time; refreshes whenever the row's state changes.
enum RelativeTimeText {
  static func short(for date: Date, relativeTo now: Date = Date()) -> String {
    let seconds = max(0, now.timeIntervalSince(date))
    switch seconds {
    case ..<45: return "just now"
    case ..<3_600: return "\(Int((seconds / 60).rounded()))m ago"
    case ..<86_400: return "\(Int((seconds / 3_600).rounded()))h ago"
    case ..<604_800: return "\(Int((seconds / 86_400).rounded()))d ago"
    // Past a week, a calendar date ("Jun 20") scans faster than "12d ago".
    default: return absolute(date, relativeTo: now)
    }
  }

  private static func absolute(_ date: Date, relativeTo now: Date) -> String {
    let calendar = Calendar.current
    let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
    return (sameYear ? monthDayFormatter : monthDayYearFormatter).string(from: date)
  }

  private static let monthDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMMd")
    return formatter
  }()

  private static let monthDayYearFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("MMMdyyyy")
    return formatter
  }()
}

private nonisolated let notificationEnvironmentLogger = SupaLogger("Notifications")

extension EnvironmentValues {
  @Entry var focusNotificationAction: (WorktreeTerminalNotification) -> Void = { _ in
    notificationEnvironmentLogger.warning("focusNotificationAction called but was never set in the environment.")
  }
}
