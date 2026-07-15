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
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(directoryURL: root, decoder: IntegrationDecoder()),
            picker: StubPicker(url: nil)
        )

        await coordinator.start()

        XCTAssertEqual(model.customAvatar?.frames.count, 2)
        XCTAssertNil(model.avatarImportError)
        XCTAssertNotNil(model.chooseCustomAvatar)
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

    func testCancelClearsPreviousErrorWithoutChangingAvatar() async throws {
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
        XCTAssertNil(model.avatarImportError)
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

private func testAnimation() throws -> APNGAnimation {
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
    return try APNGAnimation(images: [image, image], durations: [0.1, 0.1])
}
