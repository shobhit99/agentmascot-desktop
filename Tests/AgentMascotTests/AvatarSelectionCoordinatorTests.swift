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
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(directoryURL: root, decoder: IntegrationDecoder()),
            picker: StubPicker(url: source)
        )

        await coordinator.chooseAndImport()

        XCTAssertEqual(model.customAvatar?.frames.count, 2)
        XCTAssertNil(model.avatarImportError)
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
    private var urls: [URL]

    init(urls: [URL]) {
        self.urls = urls
    }

    func chooseAPNG() -> URL? {
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
