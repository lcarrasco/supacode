import ComposableArchitecture
import Foundation

/// Drives the Changed Files inspector: tracks the active worktree, loads its
/// changed-file list (refreshed by the worktree watcher), then batch-loads
/// every file's diff. The view renders the whole set as one HTML document in a
/// `WKWebView`, so collapse/scroll are handled client-side and the reducer
/// only owns data.
@Reducer
struct ChangedFilesFeature {
  /// Upper bound on how many files we fetch diffs for in one batch, so a huge
  /// changeset can't fan out into thousands of `git diff` processes. Files
  /// beyond the cap still appear in the list; the renderer notes the omission.
  static let diffBatchCap = 400

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
    /// Successfully loaded per-file diffs; absent ⇒ still loading or failed.
    var loadedDiffs: [ChangedFile.ID: FileDiff] = [:]
    var failedDiffIDs: Set<ChangedFile.ID> = []
    /// True once the diff batch for the current file set has settled.
    var diffsLoaded = false

    enum LoadingState: Equatable {
      case idle
      case loading
      case loaded
      case failed(String)
    }
  }

  enum Action: Equatable {
    case worktreeSelected(id: Worktree.ID?, directory: URL?)
    case filesChangedEvent(worktreeID: Worktree.ID)
    case inspectorVisibilityChanged(Bool)
    case refreshRequested
    case fileListLoaded([ChangedFile])
    case fileListFailed(String)
    /// Result of the per-file diff batch for the current file set.
    case diffsLoaded(diffs: [ChangedFile.ID: FileDiff], failedIDs: Set<ChangedFile.ID>)
    /// The user clicked a file name in the diff; `path` is the absolute file path.
    case openFileTapped(String)
    case delegate(Delegate)
  }

  @CasePathable
  enum Delegate: Equatable {
    case openFile(URL)
  }

  @Dependency(GitClientDependency.self) private var gitClient

  private nonisolated enum CancelID: Hashable {
    case fileListLoad
    case diffBatchLoad
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
        state.resetForReload()
        guard directory != nil, state.isInspectorVisible else {
          return .merge(.cancel(id: CancelID.fileListLoad), .cancel(id: CancelID.diffBatchLoad))
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
        // ticks are dropped while hidden, so the list may be stale.
        guard isVisible, state.activeWorktreeDirectory != nil else { return .none }
        return loadFileList(state: &state)

      case .refreshRequested:
        guard state.activeWorktreeDirectory != nil else { return .none }
        return loadFileList(state: &state)

      case .fileListLoaded(let files):
        state.loadingState = .loaded
        state.files = files
        state.loadedDiffs = [:]
        state.failedDiffIDs = []
        state.diffsLoaded = false
        guard let directory = state.activeWorktreeDirectory, !files.isEmpty else {
          state.diffsLoaded = true
          return .none
        }
        return loadDiffBatch(files: files, directory: directory)

      case .fileListFailed(let message):
        state.loadingState = .failed(message)
        state.diffsLoaded = true
        return .none

      case .diffsLoaded(let diffs, let failedIDs):
        state.loadedDiffs = diffs
        state.failedDiffIDs = failedIDs
        state.diffsLoaded = true
        return .none

      case .openFileTapped(let path):
        guard !path.isEmpty else { return .none }
        return .send(.delegate(.openFile(URL(fileURLWithPath: path))))

      case .delegate:
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

  /// Fetches every file's diff concurrently (bounded by `diffBatchCap`) and
  /// emits a single `diffsLoaded`, so the web view reloads once per refresh.
  private func loadDiffBatch(files: [ChangedFile], directory: URL) -> Effect<Action> {
    let batch = Array(files.prefix(Self.diffBatchCap))
    return .run { [gitClient] send in
      let results = await withTaskGroup(of: (ChangedFile.ID, FileDiff?).self) { group in
        for file in batch {
          group.addTask {
            (file.id, try? await gitClient.fileDiff(directory, file))
          }
        }
        var diffs: [ChangedFile.ID: FileDiff] = [:]
        var failed: Set<ChangedFile.ID> = []
        for await (id, diff) in group {
          if let diff { diffs[id] = diff } else { failed.insert(id) }
        }
        return (diffs, failed)
      }
      await send(.diffsLoaded(diffs: results.0, failedIDs: results.1))
    }
    .cancellable(id: CancelID.diffBatchLoad, cancelInFlight: true)
  }
}

extension ChangedFilesFeature.State {
  fileprivate mutating func resetForReload() {
    files = []
    loadedDiffs = [:]
    failedDiffIDs = []
    diffsLoaded = false
    loadingState = .idle
  }
}
