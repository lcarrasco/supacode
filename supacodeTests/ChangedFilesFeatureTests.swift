import ComposableArchitecture
import Foundation
import Testing

@testable import supacode

@MainActor
@Suite(.serialized)
struct ChangedFilesFeatureTests {
  private nonisolated static let worktreeURL = URL(fileURLWithPath: "/tmp/wt")
  private nonisolated static let fileA = ChangedFile(path: "A.swift", previousPath: nil, status: .modified)
  private nonisolated static let fileB = ChangedFile(path: "B.swift", previousPath: nil, status: .added)
  private nonisolated static let sampleDiff = FileDiff(
    hunks: [DiffHunk(id: 0, header: "@@ -1 +1 @@", lines: [])],
    isBinary: false
  )

  private func makeState(visible: Bool) -> ChangedFilesFeature.State {
    var state = ChangedFilesFeature.State()
    state.isInspectorVisible = visible
    return state
  }

  @Test func loadsFilesWhenVisibleWorktreeSelected() async {
    let store = TestStore(initialState: makeState(visible: true)) {
      ChangedFilesFeature()
    } withDependencies: {
      $0.gitClient.changedFiles = { _ in [Self.fileA] }
    }
    await store.send(.worktreeSelected(id: "wt", directory: Self.worktreeURL)) {
      $0.activeWorktreeID = "wt"
      $0.activeWorktreeDirectory = Self.worktreeURL
      $0.loadingState = .loading
    }
    await store.receive(\.fileListLoaded) {
      $0.files = [Self.fileA]
      $0.loadingState = .loaded
    }
  }

  @Test func hiddenInspectorSkipsLoadOnSelect() async {
    let store = TestStore(initialState: makeState(visible: false)) {
      ChangedFilesFeature()
    }
    // No git call, no fileListLoaded: only the selection bookkeeping changes.
    await store.send(.worktreeSelected(id: "wt", directory: Self.worktreeURL)) {
      $0.activeWorktreeID = "wt"
      $0.activeWorktreeDirectory = Self.worktreeURL
    }
  }

  @Test func filesChangedForOtherWorktreeIgnored() async {
    var state = makeState(visible: true)
    state.activeWorktreeID = "wt"
    state.activeWorktreeDirectory = Self.worktreeURL
    let store = TestStore(initialState: state) { ChangedFilesFeature() }
    // Tick for a different worktree: no effect.
    await store.send(.filesChangedEvent(worktreeID: "other"))
  }

  @Test func filesChangedForActiveWorktreeReloads() async {
    var state = makeState(visible: true)
    state.activeWorktreeID = "wt"
    state.activeWorktreeDirectory = Self.worktreeURL
    let store = TestStore(initialState: state) {
      ChangedFilesFeature()
    } withDependencies: {
      $0.gitClient.changedFiles = { _ in [Self.fileA, Self.fileB] }
    }
    await store.send(.filesChangedEvent(worktreeID: "wt")) {
      $0.loadingState = .loading
    }
    await store.receive(\.fileListLoaded) {
      $0.files = [Self.fileA, Self.fileB]
      $0.loadingState = .loaded
    }
  }

  @Test func expandingRowLoadsDiffThenCachesOnReExpand() async {
    var state = makeState(visible: true)
    state.activeWorktreeID = "wt"
    state.activeWorktreeDirectory = Self.worktreeURL
    state.files = [Self.fileA]
    state.loadingState = .loaded
    let store = TestStore(initialState: state) {
      ChangedFilesFeature()
    } withDependencies: {
      $0.gitClient.fileDiff = { _, _ in Self.sampleDiff }
    }

    await store.send(.fileRowTapped("A.swift")) {
      $0.expandedFileIDs = ["A.swift"]
    }
    await store.receive(\.diffLoaded) {
      $0.loadedDiffs = ["A.swift": Self.sampleDiff]
    }
    // Collapse.
    await store.send(.fileRowTapped("A.swift")) {
      $0.expandedFileIDs = []
    }
    // Re-expand: cache hit, no diff load effect.
    await store.send(.fileRowTapped("A.swift")) {
      $0.expandedFileIDs = ["A.swift"]
    }
  }

  @Test func fileListReloadDropsStaleDiffsAndExpansion() async {
    var state = makeState(visible: true)
    state.activeWorktreeID = "wt"
    state.activeWorktreeDirectory = Self.worktreeURL
    state.files = [Self.fileA, Self.fileB]
    state.expandedFileIDs = ["B.swift"]
    state.loadedDiffs = ["B.swift": Self.sampleDiff]
    let store = TestStore(initialState: state) { ChangedFilesFeature() }
    // B is gone after reload: its cached diff + expansion must be pruned.
    await store.send(.fileListLoaded([Self.fileA])) {
      $0.files = [Self.fileA]
      $0.loadingState = .loaded
      $0.loadedDiffs = [:]
      $0.expandedFileIDs = []
    }
  }

  @Test func inspectorVisibilityChangeLoadsWhenActiveAndEmpty() async {
    var state = makeState(visible: false)
    state.activeWorktreeID = "wt"
    state.activeWorktreeDirectory = Self.worktreeURL
    let store = TestStore(initialState: state) {
      ChangedFilesFeature()
    } withDependencies: {
      $0.gitClient.changedFiles = { _ in [Self.fileA] }
    }
    await store.send(.inspectorVisibilityChanged(true)) {
      $0.isInspectorVisible = true
      $0.loadingState = .loading
    }
    await store.receive(\.fileListLoaded) {
      $0.files = [Self.fileA]
      $0.loadingState = .loaded
    }
  }
}
