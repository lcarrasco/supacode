import ComposableArchitecture
import Foundation

/// Typed AppStorage handle for the Changed Files inspector visibility.
/// Centralising the key + default keeps the read sites (reducer State,
/// View-menu binding, inspector attach point) from drifting. Defaults off
/// so the panel is opt-in.
nonisolated extension SharedReaderKey where Self == AppStorageKey<Bool>.Default {
  static var changedFilesInspectorVisible: Self {
    Self[.appStorage("changedFilesInspectorVisible"), default: false]
  }
}
