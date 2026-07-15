import CoreGraphics
import Foundation
import XCTest
@testable import AgentMascotApp

@MainActor
final class AvatarSelectionCoordinatorTests: XCTestCase {
    func testStartLoadsPersistedAvatarAndInstallsChooseAction() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("saved".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let model = AppModel()
        let decoder = ThreadRecordingDecoder()
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(directoryURL: root, decoder: decoder),
            picker: StubPicker(url: nil)
        )

        await coordinator.start()

        XCTAssertEqual(model.customAvatar?.frames.count, 2)
        XCTAssertNil(model.avatarImportError)
        XCTAssertNotNil(model.chooseCustomAvatar)
        XCTAssertTrue(decoder.allCallsWereOffMain)
        coordinator.stop()
        XCTAssertNil(model.chooseCustomAvatar)
    }

    func testChooseImportsAndPublishesValidAvatar() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try sourceFile(named: "chosen.apng", bytes: "chosen")
        defer { try? FileManager.default.removeItem(at: source) }
        let model = AppModel()
        let decoder = ThreadRecordingDecoder()
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(directoryURL: root, decoder: decoder),
            picker: StubPicker(url: source)
        )

        await coordinator.chooseAndImport()

        XCTAssertEqual(model.customAvatar?.frames.count, 2)
        XCTAssertNil(model.avatarImportError)
        XCTAssertTrue(decoder.allCallsWereOffMain)
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent("avatar.apng")),
            Data("chosen".utf8)
        )
    }

    func testFailedChooseKeepsDisplayedAvatarAndPublishesError() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try sourceFile(named: "invalid.apng", bytes: "invalid")
        defer { try? FileManager.default.removeItem(at: source) }
        let model = AppModel()
        model.customAvatar = try testAnimation()
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(
                directoryURL: root,
                decoder: IntegrationDecoder(failingNames: ["invalid.apng"])
            ),
            picker: StubPicker(url: source)
        )

        await coordinator.chooseAndImport()

        XCTAssertEqual(model.customAvatar?.frames.count, 2)
        XCTAssertEqual(
            model.avatarImportError,
            "Choose an animated PNG with at least two frames."
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("avatar.apng").path))
    }

    func testCancelLeavesPreviousAvatarAndErrorUnchanged() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel()
        model.customAvatar = try testAnimation()
        model.avatarImportError = "Previous error"
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(directoryURL: root, decoder: IntegrationDecoder()),
            picker: StubPicker(url: nil)
        )

        await coordinator.chooseAndImport()

        XCTAssertEqual(model.customAvatar?.frames.count, 2)
        XCTAssertEqual(model.avatarImportError, "Previous error")
    }

    func testCorruptPersistedAvatarFallsBackAndPublishesRecoverableError() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("broken".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let model = AppModel()
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(
                directoryURL: root,
                decoder: IntegrationDecoder(failingNames: ["avatar.apng"])
            ),
            picker: StubPicker(url: nil)
        )

        await coordinator.start()

        XCTAssertNil(model.customAvatar)
        XCTAssertEqual(
            model.avatarImportError,
            "Choose an animated PNG with at least two frames."
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("avatar.apng").path))
    }

    func testDuplicateStartsPerformOneLoad() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("saved".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let decoder = BlockingDecoder(blockedContents: ["saved"])
        let model = AppModel()
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(directoryURL: root, decoder: decoder),
            picker: StubPicker(url: nil)
        )

        let firstStart = Task { await coordinator.start() }
        await Task.yield()
        XCTAssertEqual(decoder.waitForEntry(of: "saved"), .success)

        await coordinator.start()
        XCTAssertEqual(decoder.decodeCount, 1)

        decoder.release("saved")
        await firstStart.value

        XCTAssertEqual(model.customAvatar?.frames.count, 2)
        XCTAssertNotNil(model.chooseCustomAvatar)
    }

    func testStopPreventsStaleStartLoadFromPublishing() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("saved".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let decoder = BlockingDecoder(blockedContents: ["saved"])
        let model = AppModel()
        model.customAvatar = try testAnimation(frameCount: 3)
        model.avatarImportError = "Previous error"
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(directoryURL: root, decoder: decoder),
            picker: StubPicker(url: nil)
        )

        let start = Task { await coordinator.start() }
        await Task.yield()
        XCTAssertEqual(decoder.waitForEntry(of: "saved"), .success)

        coordinator.stop()
        decoder.release("saved")
        await start.value

        XCTAssertEqual(model.customAvatar?.frames.count, 3)
        XCTAssertEqual(model.avatarImportError, "Previous error")
        XCTAssertNil(model.chooseCustomAvatar)
    }

    func testQueuedSelectionCancelledBeforeRestartDoesNotOpenImportOrPublish() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("saved".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let source = try sourceFile(named: "selected.apng", bytes: "selected")
        defer { try? FileManager.default.removeItem(at: source) }
        let picker = CountingPicker(url: source)
        let decoder = SelectionTrackingDecoder()
        let model = AppModel()
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(directoryURL: root, decoder: decoder),
            picker: picker
        )

        await coordinator.start()
        let choose = try XCTUnwrap(model.chooseCustomAvatar)
        choose()
        coordinator.stop()
        await coordinator.start()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(picker.chooseCount, 0)
        XCTAssertEqual(decoder.selectedDecodeCount, 0)
        XCTAssertEqual(model.customAvatar?.frames.count, 3)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("avatar.apng")), Data("saved".utf8))
    }

    func testRetainedChoiceFromPreviousLifecycleDoesNotOpenPickerAfterRestart() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("saved".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let source = try sourceFile(named: "selected.apng", bytes: "selected")
        defer { try? FileManager.default.removeItem(at: source) }
        let picker = CountingPicker(url: source)
        let decoder = SelectionTrackingDecoder()
        let model = AppModel()
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(directoryURL: root, decoder: decoder),
            picker: picker
        )

        await coordinator.start()
        let staleChoice = try XCTUnwrap(model.chooseCustomAvatar)
        coordinator.stop()
        await coordinator.start()
        staleChoice()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(picker.chooseCount, 0)
        XCTAssertEqual(decoder.selectedDecodeCount, 0)
        XCTAssertEqual(model.customAvatar?.frames.count, 3)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("avatar.apng")), Data("saved".utf8))
    }

    func testStopAndRestartDuringStagedImportPreservesPreviousPersistedAvatar() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("saved".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let source = try sourceFile(named: "selected.apng", bytes: "selected")
        defer { try? FileManager.default.removeItem(at: source) }
        let decoder = StagedImportBlockingDecoder()
        let model = AppModel()
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(directoryURL: root, decoder: decoder),
            picker: StubPicker(url: source)
        )

        await coordinator.start()
        let choose = try XCTUnwrap(model.chooseCustomAvatar)
        choose()
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(decoder.waitForStagedImport(), .success)

        coordinator.stop()
        let restart = Task { await coordinator.start() }
        await Task.yield()
        decoder.releaseStagedImport()
        await restart.value

        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("avatar.apng")), Data("saved".utf8))
        XCTAssertEqual(model.customAvatar?.frames.count, 3)
        XCTAssertNil(model.avatarImportError)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["avatar.apng"])
    }

    func testSupersededInstalledSelectionCannotCommitAfterNewSelectionIsCancelled() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("saved".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let source = try sourceFile(named: "first.apng", bytes: "first")
        defer { try? FileManager.default.removeItem(at: source) }
        let decoder = StagedImportBlockingDecoder()
        let fileSystem = CommitRecordingFileSystem()
        let model = AppModel()
        let picker = SequencePicker(urls: [source, nil])
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(
                directoryURL: root,
                decoder: decoder,
                fileSystem: fileSystem
            ),
            picker: picker
        )

        await coordinator.start()
        let choose = try XCTUnwrap(model.chooseCustomAvatar)

        choose()
        await Task.yield()
        await Task.yield()
        XCTAssertEqual(decoder.waitForStagedImport(), .success)
        model.customAvatar = try testAnimation(frameCount: 3)
        model.avatarImportError = "Previous error"

        choose()
        await Task.yield()
        XCTAssertEqual(picker.chooseCount, 2)
        decoder.releaseStagedImport()

        XCTAssertEqual(fileSystem.waitForCommit(), .timedOut)

        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("avatar.apng")), Data("saved".utf8))
        XCTAssertEqual(model.customAvatar?.frames.count, 3)
        XCTAssertEqual(model.avatarImportError, "Previous error")
    }

    func testOverlappingImportsPublishAndPersistNewestSelection() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstSource = try sourceFile(named: "first.apng", bytes: "first")
        let secondSource = try sourceFile(named: "second.apng", bytes: "second")
        defer {
            try? FileManager.default.removeItem(at: firstSource)
            try? FileManager.default.removeItem(at: secondSource)
        }
        let decoder = BlockingDecoder(blockedContents: ["first", "second"])
        let model = AppModel()
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(directoryURL: root, decoder: decoder),
            picker: SequencePicker(urls: [firstSource, secondSource])
        )

        let firstImport = Task { await coordinator.chooseAndImport() }
        await Task.yield()
        XCTAssertEqual(decoder.waitForEntry(of: "first"), .success)

        let secondImport = Task { await coordinator.chooseAndImport() }
        await Task.yield()
        decoder.release("first")
        XCTAssertEqual(decoder.waitForEntry(of: "second"), .success)
        decoder.release("second")

        await firstImport.value
        await secondImport.value

        XCTAssertEqual(model.customAvatar?.frames.count, 3)
        XCTAssertNil(model.avatarImportError)
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent("avatar.apng")),
            Data("second".utf8)
        )
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sourceFile(named name: String, bytes: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + name)
        try Data(bytes.utf8).write(to: url)
        return url
    }
}

@MainActor
private struct StubPicker: AvatarFilePicking {
    let url: URL?
    func chooseAPNG() -> URL? { url }
}

private struct IntegrationDecoder: APNGDecoding {
    let failingNames: Set<String>

    init(failingNames: Set<String> = []) {
        self.failingNames = failingNames
    }

    func decode(url: URL) throws -> APNGAnimation {
        if failingNames.contains(where: { url.lastPathComponent.hasSuffix($0) }) {
            throw AvatarImportError.notAnimatedPNG
        }
        return try testAnimation()
    }
}

@MainActor
private final class SequencePicker: AvatarFilePicking {
    private var urls: [URL?]
    private(set) var chooseCount = 0

    init(urls: [URL?]) {
        self.urls = urls
    }

    func chooseAPNG() -> URL? {
        chooseCount += 1
        guard !urls.isEmpty else { return nil }
        return urls.removeFirst()
    }
}

private final class ThreadRecordingDecoder: APNGDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private var callsOnMainThread = false

    var allCallsWereOffMain: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !callsOnMainThread
    }

    func decode(url: URL) throws -> APNGAnimation {
        lock.lock()
        callsOnMainThread = callsOnMainThread || Thread.isMainThread
        lock.unlock()
        return try testAnimation()
    }
}

private final class BlockingDecoder: APNGDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private var blockedContents: Set<String>
    private var entered: [String: DispatchSemaphore] = [:]
    private var releases: [String: DispatchSemaphore] = [:]
    private var totalDecodeCount = 0

    init(blockedContents: Set<String>) {
        self.blockedContents = blockedContents
        for content in blockedContents {
            entered[content] = DispatchSemaphore(value: 0)
            releases[content] = DispatchSemaphore(value: 0)
        }
    }

    var decodeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return totalDecodeCount
    }

    func waitForEntry(of content: String) -> DispatchTimeoutResult {
        lock.lock()
        let semaphore = entered[content]
        lock.unlock()
        return semaphore?.wait(timeout: .now() + 5) ?? .timedOut
    }

    func release(_ content: String) {
        lock.lock()
        let semaphore = releases[content]
        lock.unlock()
        semaphore?.signal()
    }

    func decode(url: URL) throws -> APNGAnimation {
        let content = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        let shouldBlock: Bool
        let entry: DispatchSemaphore?
        let release: DispatchSemaphore?
        lock.lock()
        totalDecodeCount += 1
        shouldBlock = blockedContents.remove(content) != nil
        entry = entered[content]
        release = releases[content]
        lock.unlock()

        if shouldBlock {
            entry?.signal()
            release?.wait()
        }

        return try testAnimation(frameCount: content == "second" ? 3 : 2)
    }
}

@MainActor
private final class CountingPicker: AvatarFilePicking {
    private let url: URL?
    private(set) var chooseCount = 0

    init(url: URL?) {
        self.url = url
    }

    func chooseAPNG() -> URL? {
        chooseCount += 1
        return url
    }
}

private final class SelectionTrackingDecoder: APNGDecoding, @unchecked Sendable {
    private let lock = NSLock()
    private var selectedDecodes = 0

    var selectedDecodeCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return selectedDecodes
    }

    func decode(url: URL) throws -> APNGAnimation {
        let contents = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        if contents == "selected" {
            lock.lock()
            selectedDecodes += 1
            lock.unlock()
        }
        return try testAnimation(frameCount: contents == "selected" ? 2 : 3)
    }
}

private final class StagedImportBlockingDecoder: APNGDecoding, @unchecked Sendable {
    private let stagedImportEntered = DispatchSemaphore(value: 0)
    private let stagedImportRelease = DispatchSemaphore(value: 0)

    func waitForStagedImport() -> DispatchTimeoutResult {
        stagedImportEntered.wait(timeout: .now() + 5)
    }

    func releaseStagedImport() {
        stagedImportRelease.signal()
    }

    func decode(url: URL) throws -> APNGAnimation {
        let contents = String(decoding: try Data(contentsOf: url), as: UTF8.self)
        if url.lastPathComponent.hasPrefix(".avatar-") {
            stagedImportEntered.signal()
            stagedImportRelease.wait()
        }
        return try testAnimation(frameCount: contents == "saved" ? 3 : 2)
    }
}

private final class CommitRecordingFileSystem: AvatarFileSystem, @unchecked Sendable {
    private let fileSystem = LocalAvatarFileSystem()
    private let commit = DispatchSemaphore(value: 0)

    func waitForCommit() -> DispatchTimeoutResult {
        commit.wait(timeout: .now() + 1)
    }

    func fileExists(at url: URL) -> Bool {
        fileSystem.fileExists(at: url)
    }

    func createDirectory(at url: URL) throws {
        try fileSystem.createDirectory(at: url)
    }

    func copyItem(at source: URL, to destination: URL) throws {
        try fileSystem.copyItem(at: source, to: destination)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try fileSystem.moveItem(at: source, to: destination)
        commit.signal()
    }

    func replaceItem(at destination: URL, with source: URL) throws {
        try fileSystem.replaceItem(at: destination, with: source)
        commit.signal()
    }

    func removeItemIfExists(at url: URL) throws {
        try fileSystem.removeItemIfExists(at: url)
    }
}

private func testAnimation(frameCount: Int = 2) throws -> APNGAnimation {
    let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let image = context.makeImage()!
    return try APNGAnimation(
        images: Array(repeating: image, count: frameCount),
        durations: Array(repeating: 0.1, count: frameCount)
    )
}
