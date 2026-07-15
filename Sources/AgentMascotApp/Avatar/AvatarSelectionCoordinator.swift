import Foundation

private actor AvatarSelectionWorkQueue {
    private var tail: Task<Void, Never>?

    func perform<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let predecessor = tail
        let task = Task.detached(priority: .userInitiated) {
            _ = await predecessor?.value
            return try operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}

@MainActor
final class AvatarSelectionCoordinator {
    private let model: AppModel
    private let store: CustomAvatarStore
    private let picker: any AvatarFilePicking
    private let workQueue = AvatarSelectionWorkQueue()
    private var isStarted = false
    private var isActive = true
    private var lifecycleGeneration = 0
    private var latestOperation = 0
    private var selectionTask: Task<Void, Never>?
    private var importCommitGates: [Int: AvatarImportCommitGate] = [:]

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
        guard !isStarted else { return }
        isStarted = true
        isActive = true
        lifecycleGeneration &+= 1
        latestOperation &+= 1
        let lifecycle = lifecycleGeneration
        let operation = latestOperation

        model.chooseCustomAvatar = { [weak self] in
            self?.beginChoosing(lifecycle: lifecycle)
        }

        do {
            let avatar = try await workQueue.perform { [store] in
                try store.load()
            }
            guard canPublish(lifecycle: lifecycle, operation: operation) else { return }
            model.customAvatar = avatar
            model.avatarImportError = nil
        } catch {
            guard canPublish(lifecycle: lifecycle, operation: operation) else { return }
            model.customAvatar = nil
            model.avatarImportError = Self.message(for: error)
        }
    }

    func chooseAndImport() async {
        await chooseAndImport(lifecycle: lifecycleGeneration)
    }

    private func chooseAndImport(lifecycle: Int) async {
        guard canContinue(lifecycle: lifecycle) else { return }
        guard let sourceURL = picker.chooseAPNG() else { return }
        guard canContinue(lifecycle: lifecycle) else { return }

        latestOperation &+= 1
        let operation = latestOperation
        let commitGate = AvatarImportCommitGate()
        importCommitGates[operation] = commitGate
        defer { clearImportCommitGate(commitGate, for: operation) }
        model.avatarImportError = nil

        do {
            guard canContinue(lifecycle: lifecycle) else { return }
            let animation = try await workQueue.perform { [store, commitGate] in
                try store.importAvatar(from: sourceURL, commitAuthorization: commitGate)
            }
            guard canPublish(lifecycle: lifecycle, operation: operation) else { return }
            model.customAvatar = animation
            model.avatarImportError = nil
        } catch {
            guard canPublish(lifecycle: lifecycle, operation: operation) else { return }
            model.avatarImportError = Self.message(for: error)
        }
    }

    func stop() {
        invalidateImportCommitGates()
        lifecycleGeneration &+= 1
        isStarted = false
        isActive = false
        selectionTask?.cancel()
        selectionTask = nil
        model.chooseCustomAvatar = nil
    }

    private func beginChoosing(lifecycle: Int) {
        guard canContinue(lifecycle: lifecycle) else { return }
        invalidateImportCommitGates()
        selectionTask?.cancel()
        selectionTask = Task { [weak self] in
            await self?.chooseAndImport(lifecycle: lifecycle)
        }
    }

    private func invalidateImportCommitGates() {
        let gates = importCommitGates.values
        importCommitGates.removeAll()
        for gate in gates {
            gate.invalidate()
        }
    }

    private func clearImportCommitGate(_ gate: AvatarImportCommitGate, for operation: Int) {
        guard importCommitGates[operation] === gate else { return }
        importCommitGates.removeValue(forKey: operation)
    }

    private func canContinue(lifecycle: Int) -> Bool {
        isActive && lifecycleGeneration == lifecycle && !Task.isCancelled
    }

    private func canPublish(lifecycle: Int, operation: Int) -> Bool {
        canContinue(lifecycle: lifecycle) && latestOperation == operation
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
