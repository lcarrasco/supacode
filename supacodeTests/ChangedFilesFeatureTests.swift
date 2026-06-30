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

  @Test func loadsFilesAndDiffBatchWhenVisibleWorktreeSelected() async {
    let store = TestStore(initialState: makeState(visible: true)) {
      ChangedFilesFeature()
    } withDependencies: {
      $0.gitClient.changedFiles = { _ in [Self.fileA] }
      $0.gitClient.fileDiff = { _, _ in Self.sampleDiff }
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
    await store.receive(\.diffsLoaded) {
      $0.loadedDiffs = ["A.swift": Self.sampleDiff]
      $0.diffsLoaded = true
    }
  }

  @Test func hiddenInspectorSkipsLoadOnSelect() async {
    let store = TestStore(initialState: makeState(visible: false)) {
      ChangedFilesFeature()
    }
    await store.send(.worktreeSelected(id: "wt", directory: Self.worktreeURL)) {
      $0.activeWorktreeID = "wt"
      $0.activeWorktreeDirectory = Self.worktreeURL
    }
  }

  @Test func emptyFileListSettlesWithoutDiffBatch() async {
    var state = makeState(visible: true)
    state.activeWorktreeID = "wt"
    state.activeWorktreeDirectory = Self.worktreeURL
    let store = TestStore(initialState: state) {
      ChangedFilesFeature()
    } withDependencies: {
      $0.gitClient.changedFiles = { _ in [] }
    }
    await store.send(.refreshRequested) {
      $0.loadingState = .loading
    }
    await store.receive(\.fileListLoaded) {
      $0.loadingState = .loaded
      $0.diffsLoaded = true
    }
  }

  @Test func filesChangedForOtherWorktreeIgnored() async {
    var state = makeState(visible: true)
    state.activeWorktreeID = "wt"
    state.activeWorktreeDirectory = Self.worktreeURL
    let store = TestStore(initialState: state) { ChangedFilesFeature() }
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
      $0.gitClient.fileDiff = { _, _ in Self.sampleDiff }
    }
    await store.send(.filesChangedEvent(worktreeID: "wt")) {
      $0.loadingState = .loading
    }
    await store.receive(\.fileListLoaded) {
      $0.files = [Self.fileA, Self.fileB]
      $0.loadingState = .loaded
    }
    await store.receive(\.diffsLoaded) {
      $0.loadedDiffs = ["A.swift": Self.sampleDiff, "B.swift": Self.sampleDiff]
      $0.diffsLoaded = true
    }
  }

  @Test func diffBatchRecordsFailuresWhenDiffThrows() async {
    var state = makeState(visible: true)
    state.activeWorktreeID = "wt"
    state.activeWorktreeDirectory = Self.worktreeURL
    struct Boom: Error {}
    let store = TestStore(initialState: state) {
      ChangedFilesFeature()
    } withDependencies: {
      $0.gitClient.changedFiles = { _ in [Self.fileA] }
      $0.gitClient.fileDiff = { _, _ in throw Boom() }
    }
    await store.send(.refreshRequested) {
      $0.loadingState = .loading
    }
    await store.receive(\.fileListLoaded) {
      $0.files = [Self.fileA]
      $0.loadingState = .loaded
    }
    await store.receive(\.diffsLoaded) {
      $0.failedDiffIDs = ["A.swift"]
      $0.diffsLoaded = true
    }
  }

  @Test func openFileTappedEmitsDelegate() async {
    let store = TestStore(initialState: makeState(visible: true)) {
      ChangedFilesFeature()
    }
    await store.send(.openFileTapped("/tmp/wt/A.swift"))
    await store.receive(\.delegate.openFile)
  }

  @Test func openFileTappedIgnoresEmptyPath() async {
    let store = TestStore(initialState: makeState(visible: true)) {
      ChangedFilesFeature()
    }
    await store.send(.openFileTapped(""))
  }

  @Test func inspectorVisibilityChangeLoadsWhenActive() async {
    var state = makeState(visible: false)
    state.activeWorktreeID = "wt"
    state.activeWorktreeDirectory = Self.worktreeURL
    let store = TestStore(initialState: state) {
      ChangedFilesFeature()
    } withDependencies: {
      $0.gitClient.changedFiles = { _ in [Self.fileA] }
      $0.gitClient.fileDiff = { _, _ in Self.sampleDiff }
    }
    await store.send(.inspectorVisibilityChanged(true)) {
      $0.isInspectorVisible = true
      $0.loadingState = .loading
    }
    await store.receive(\.fileListLoaded) {
      $0.files = [Self.fileA]
      $0.loadingState = .loaded
    }
    await store.receive(\.diffsLoaded) {
      $0.loadedDiffs = ["A.swift": Self.sampleDiff]
      $0.diffsLoaded = true
    }
  }
}
