import Foundation
import Combine

// MARK: - 写真追加メニューを MainView レベルで制御するコーディネーター

final class PhotoDialogCoordinator: ObservableObject {
    @Published var isPresented = false
    private(set) var hasPhoto = false
    private(set) var onTakePhoto: () -> Void = {}
    private(set) var onSelectLibrary: () -> Void = {}
    private(set) var onDeletePhoto: () -> Void = {}

    func show(
        hasPhoto: Bool,
        onTakePhoto: @escaping () -> Void,
        onSelectLibrary: @escaping () -> Void,
        onDeletePhoto: @escaping () -> Void
    ) {
        self.hasPhoto = hasPhoto
        self.onTakePhoto = onTakePhoto
        self.onSelectLibrary = onSelectLibrary
        self.onDeletePhoto = onDeletePhoto
        isPresented = true
    }
}
