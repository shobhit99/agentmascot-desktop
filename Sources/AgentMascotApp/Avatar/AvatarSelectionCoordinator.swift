import Foundation

@MainActor
final class AvatarSelectionCoordinator {
    private let model: AppModel
    private let store: CustomAvatarStore
    private let picker: any AvatarFilePicking

    init(
        model: AppModel,
        store: CustomAvatarStore,
        picker: any AvatarFilePicking
    ) {
        self.model = model
        self.store = store
        self.picker = picker
    }

    func start() async {
        model.chooseCustomAvatar = { [weak self] in
            Task { await self?.chooseAndImport() }
        }

        do {
            model.customAvatar = try await Task.detached(priority: .userInitiated) { [store] in
                try store.load()
            }.value
        } catch {
            model.customAvatar = nil
            model.avatarImportError = Self.message(for: error)
        }
    }

    func chooseAndImport() async {
        model.avatarImportError = nil
        guard let sourceURL = picker.chooseAPNG() else { return }

        do {
            let animation = try await Task.detached(priority: .userInitiated) { [store] in
                try store.importAvatar(from: sourceURL)
            }.value
            model.customAvatar = animation
            model.avatarImportError = nil
        } catch {
            model.avatarImportError = Self.message(for: error)
        }
    }

    func stop() {
        model.chooseCustomAvatar = nil
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
