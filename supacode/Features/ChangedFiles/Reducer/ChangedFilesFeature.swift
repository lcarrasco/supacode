import ComposableArchitecture
import Foundation

/// Drives the Changed Files inspector: tracks the active worktree, loads its
/// changed-file list (refreshed by the worktree watcher), and lazily fetches
/// each file's diff when its row is expanded. Diffs are cached per file so a
/// watcher tick that doesn't alter the file set is cheap.
@Reducer
struct ChangedFilesFeature {
  @ObservableState
  struct State: Equatable {
    /// Mirror of the View's `@Shared(.changedFilesInspectorVisible)` binding,
    /// pushed in via `inspectorVisibilityChanged` so the reducer can gate
    /// loads on visibility without owning the shared key (keeps it
    /// deterministic in tests).
    var isInspectorVisible = false

    /// The worktree the panel currently reflects. `directory` is nil when the
    /// selection can't be diffed (folder repo, remote worktree, no selection),
    /// which leaves the panel idle.
    var activeWorktreeID: Worktree.ID?
    var activeWorktreeDirectory: URL?

    var loadingState: LoadingState = .idle
    var files: [ChangedFile] = []
    var expandedFileIDs: Set<ChangedFile.ID> = []
    var loadedDiffs: [ChangedFile.ID: FileDiff] = [:]
    var failedDiffIDs: Set<ChangedFile.ID> = []

    enum LoadingState: Equatable {
      case idle
      case loading
      case loaded
      case failed(String)
    }

    /// True while a row is expanded but its diff hasn't resolved yet.
    func isLoadingDiff(_ id: ChangedFile.ID) -> Bool {
      expandedFileIDs.contains(id) && loadedDiffs[id] == nil && !failedDiffIDs.contains(id)
    }
  }

  enum Action: Equatable {
    case worktreeSelected(id: Worktree.ID?, directory: URL?)
    case filesChangedEvent(worktreeID: Worktree.ID)
    case inspectorVisibilityChanged(Bool)
    case refreshRequested
    case fileListLoaded([ChangedFile])
    case fileListFailed(String)
    case fileRowTapped(ChangedFile.ID)
    case diffLoaded(ChangedFile.ID, FileDiff)
    case diffFailed(ChangedFile.ID, String)
  }

  @Dependency(GitClientDependency.self) private var gitClient

  private nonisolated enum CancelID: Hashable {
    case fileListLoad
    case diffLoad(ChangedFile.ID)
  }

  var body: some Reducer<State, Action> {
    Reduce { state, action in
      switch action {
      case .worktreeSelected(let id, let directory):
        guard id != state.activeWorktreeID || directory != state.activeWorktreeDirectory else {
          return .none
        }
        state.activeWorktreeID = id
        state.activeWorktreeDirectory = directory
        state.files = []
        state.loadedDiffs = [:]
        state.failedDiffIDs = []
        state.expandedFileIDs = []
        state.loadingState = .idle
        guard directory != nil, state.isInspectorVisible else {
          return .cancel(id: CancelID.fileListLoad)
        }
        return loadFileList(state: &state)

      case .filesChangedEvent(let worktreeID):
        guard worktreeID == state.activeWorktreeID,
          state.activeWorktreeDirectory != nil,
          state.isInspectorVisible
        else {
          return .none
        }
        return loadFileList(state: &state)

      case .inspectorVisibilityChanged(let isVisible):
        state.isInspectorVisible = isVisible
        // Reload whenever the panel opens for a diffable worktree: file-change
        // ticks are dropped while hidden, so a non-empty list may be stale.
        // `loadFileList` is cheap and cancels any in-flight load.
        guard isVisible, state.activeWorktreeDirectory != nil else { return .none }
        return loadFileList(state: &state)

      case .refreshRequested:
        guard state.activeWorktreeDirectory != nil else { return .none }
        return loadFileList(state: &state)

      case .fileListLoaded(let files):
        state.loadingState = .loaded
        state.files = files
        // Drop cached diffs / expansion for files no longer present.
        let presentIDs = Set(files.map(\.id))
        state.loadedDiffs = state.loadedDiffs.filter { presentIDs.contains($0.key) }
        state.failedDiffIDs = state.failedDiffIDs.intersection(presentIDs)
        state.expandedFileIDs = state.expandedFileIDs.intersection(presentIDs)
        // Re-fetch diffs for still-expanded files whose content may have changed.
        let directory = state.activeWorktreeDirectory
        let toReload = state.expandedFileIDs.compactMap { id in files.first { $0.id == id } }
        guard let directory, !toReload.isEmpty else { return .none }
        state.failedDiffIDs = []
        for file in toReload { state.loadedDiffs[file.id] = nil }
        return .merge(toReload.map { loadDiff(for: $0, directory: directory) })

      case .fileListFailed(let message):
        state.loadingState = .failed(message)
        return .none

      case .fileRowTapped(let id):
        if state.expandedFileIDs.contains(id) {
          state.expandedFileIDs.remove(id)
          return .cancel(id: CancelID.diffLoad(id))
        }
        state.expandedFileIDs.insert(id)
        state.failedDiffIDs.remove(id)
        // Cache hit: nothing to load.
        guard state.loadedDiffs[id] == nil,
          let directory = state.activeWorktreeDirectory,
          let file = state.files.first(where: { $0.id == id })
        else {
          return .none
        }
        return loadDiff(for: file, directory: directory)

      case .diffLoaded(let id, let diff):
        state.loadedDiffs[id] = diff
        state.failedDiffIDs.remove(id)
        return .none

      case .diffFailed(let id, _):
        state.failedDiffIDs.insert(id)
        return .none
      }
    }
  }

  private func loadFileList(state: inout State) -> Effect<Action> {
    guard let directory = state.activeWorktreeDirectory else { return .none }
    state.loadingState = .loading
    return .run { [gitClient] send in
      do {
        let files = try await gitClient.changedFiles(directory)
        await send(.fileListLoaded(files))
      } catch {
        await send(.fileListFailed(error.localizedDescription))
      }
    }
    .cancellable(id: CancelID.fileListLoad, cancelInFlight: true)
  }

  private func loadDiff(for file: ChangedFile, directory: URL) -> Effect<Action> {
    .run { [gitClient] send in
      do {
        let diff = try await gitClient.fileDiff(directory, file)
        await send(.diffLoaded(file.id, diff))
      } catch {
        await send(.diffFailed(file.id, error.localizedDescription))
      }
    }
    .cancellable(id: CancelID.diffLoad(file.id), cancelInFlight: true)
  }
}
