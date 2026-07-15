import CoreGraphics
import Foundation
import XCTest
@testable import AgentMascotApp

final class CustomAvatarStoreTests: XCTestCase {
    func testLoadReturnsNilWhenNoSavedAvatarExists() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = CustomAvatarStore(directoryURL: root, decoder: StubDecoder())
        XCTAssertNil(try store.load())
    }

    func testImportCopiesBytesAndDoesNotDependOnOriginal() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".apng")
        defer { try? FileManager.default.removeItem(at: source) }
        try Data("first-avatar".utf8).write(to: source)
        let store = CustomAvatarStore(directoryURL: root, decoder: StubDecoder())

        let animation = try store.importAvatar(from: source)
        try FileManager.default.removeItem(at: source)

        XCTAssertEqual(animation.frames.count, 2)
        XCTAssertEqual(try Data(contentsOf: store.avatarURL), Data("first-avatar".utf8))
        XCTAssertNotNil(try store.load())
    }

    func testSecondImportReplacesExistingAvatar() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try sourceFile(named: "first.apng", bytes: "first")
        let second = try sourceFile(named: "second.apng", bytes: "second")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let store = CustomAvatarStore(directoryURL: root, decoder: StubDecoder())

        _ = try store.importAvatar(from: first)
        _ = try store.importAvatar(from: second)

        XCTAssertEqual(try Data(contentsOf: store.avatarURL), Data("second".utf8))
    }

    func testSourceValidationFailurePreservesExistingAvatar() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("old".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let invalid = try sourceFile(named: "invalid.apng", bytes: "invalid")
        defer { try? FileManager.default.removeItem(at: invalid) }
        let store = CustomAvatarStore(
            directoryURL: root,
            decoder: StubDecoder(failure: .sourceNamed("invalid.apng"))
        )

        XCTAssertThrowsError(try store.importAvatar(from: invalid)) { error in
            XCTAssertEqual(error as? AvatarImportError, .notAnimatedPNG)
        }
        XCTAssertEqual(try Data(contentsOf: store.avatarURL), Data("old".utf8))
    }

    func testStagedValidationFailurePreservesExistingAvatarAndCleansStage() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("old".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let source = try sourceFile(named: "new.apng", bytes: "new")
        defer { try? FileManager.default.removeItem(at: source) }
        let store = CustomAvatarStore(
            directoryURL: root,
            decoder: StubDecoder(failure: .stagingFile)
        )

        XCTAssertThrowsError(try store.importAvatar(from: source)) { error in
            XCTAssertEqual(error as? AvatarImportError, .malformedFrames)
        }
        XCTAssertEqual(try Data(contentsOf: store.avatarURL), Data("old".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["avatar.apng"])
    }

    func testReplacementFailurePreservesExistingAvatarAndMapsPersistenceError() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("old".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let source = try sourceFile(named: "new.apng", bytes: "new")
        defer { try? FileManager.default.removeItem(at: source) }
        let store = CustomAvatarStore(
            directoryURL: root,
            decoder: StubDecoder(),
            fileSystem: ReplacementFailingFileSystem()
        )

        XCTAssertThrowsError(try store.importAvatar(from: source)) { error in
            XCTAssertEqual(error as? AvatarImportError, .persistenceFailed)
        }
        XCTAssertEqual(try Data(contentsOf: store.avatarURL), Data("old".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["avatar.apng"])
    }

    func testInvalidatedCommitAuthorizationPreservesExistingAvatarAndCleansStage() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("old".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let source = try sourceFile(named: "new.apng", bytes: "new")
        defer { try? FileManager.default.removeItem(at: source) }
        let gate = AvatarImportCommitGate()
        gate.invalidate()
        let store = CustomAvatarStore(directoryURL: root, decoder: StubDecoder())

        XCTAssertThrowsError(
            try store.importAvatar(from: source, commitAuthorization: gate)
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertEqual(try Data(contentsOf: store.avatarURL), Data("old".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["avatar.apng"])
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

private struct StubDecoder: APNGDecoding {
    enum Failure: Sendable {
        case none
        case sourceNamed(String)
        case stagingFile
    }

    let failure: Failure

    init(failure: Failure = .none) {
        self.failure = failure
    }

    func decode(url: URL) throws -> APNGAnimation {
        switch failure {
        case .none:
            break
        case let .sourceNamed(name) where url.lastPathComponent.hasSuffix(name):
            throw AvatarImportError.notAnimatedPNG
        case .stagingFile where url.lastPathComponent.hasPrefix(".avatar-"):
            throw AvatarImportError.malformedFrames
        default:
            break
        }
        let image = makeTestImage()
        return try APNGAnimation(images: [image, image], durations: [0.1, 0.1])
    }
}

private struct ReplacementFailingFileSystem: AvatarFileSystem {
    private let base = LocalAvatarFileSystem()

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
    func copyItem(at source: URL, to destination: URL) throws {
        try base.copyItem(at: source, to: destination)
    }
    func moveItem(at source: URL, to destination: URL) throws {
        try base.moveItem(at: source, to: destination)
    }
    func replaceItem(at destination: URL, with source: URL) throws {
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)
    }
    func removeItemIfExists(at url: URL) throws { try base.removeItemIfExists(at: url) }
}

private func makeTestImage() -> CGImage {
    let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return context.makeImage()!
}
