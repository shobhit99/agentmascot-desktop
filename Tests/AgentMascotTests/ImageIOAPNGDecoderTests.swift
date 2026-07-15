import Foundation
import XCTest
@testable import AgentMascotApp

final class ImageIOAPNGDecoderTests: XCTestCase {
    func testCheckedInAPNGDecodesFramesDimensionsAndTiming() throws {
        let animation = try ImageIOAPNGDecoder().decode(url: checkedInAPNG)

        XCTAssertEqual(animation.frames.count, 97)
        XCTAssertEqual(animation.frames[0].image.width, 640)
        XCTAssertEqual(animation.frames[0].image.height, 360)
        XCTAssertEqual(animation.frames[0].duration, 1.0 / 24.0, accuracy: 0.002)
        XCTAssertGreaterThan(animation.totalDuration, 0)
    }

    func testCorruptAndStaticPNGInputsAreRejected() throws {
        let corrupt = try temporaryFile(data: Data("not an image".utf8), extension: "apng")
        defer { try? FileManager.default.removeItem(at: corrupt) }

        XCTAssertThrowsError(try ImageIOAPNGDecoder().decode(url: corrupt)) { error in
            XCTAssertEqual(error as? AvatarImportError, .unreadableFile)
        }

        let staticPNG = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlBzZkAAAAASUVORK5CYII="
        )!
        let staticURL = try temporaryFile(data: staticPNG, extension: "png")
        defer { try? FileManager.default.removeItem(at: staticURL) }

        XCTAssertThrowsError(try ImageIOAPNGDecoder().decode(url: staticURL)) { error in
            XCTAssertEqual(error as? AvatarImportError, .notAnimatedPNG)
        }
    }

    func testProductionLimitsAreEnforcedIndependently() {
        assertFixtureFails(
            limits: APNGDecoderLimits(maxFileBytes: 1),
            expected: .fileTooLarge(maxBytes: 1)
        )
        assertFixtureFails(
            limits: APNGDecoderLimits(maxFrameCount: 2),
            expected: .tooManyFrames(maximum: 2)
        )
        assertFixtureFails(
            limits: APNGDecoderLimits(maxDimension: 100),
            expected: .invalidDimensions(maximum: 100)
        )
        assertFixtureFails(
            limits: APNGDecoderLimits(maxDecodedBytes: 1),
            expected: .decodedDataTooLarge(maxBytes: 1)
        )
    }

    func testDelayPreferenceFallbackAndClamp() {
        XCTAssertEqual(
            ImageIOAPNGDecoder.normalizedDelay(unclamped: 1.0 / 24.0, standard: 0.05),
            1.0 / 24.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ImageIOAPNGDecoder.normalizedDelay(unclamped: 0, standard: 0.1),
            0.1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ImageIOAPNGDecoder.normalizedDelay(unclamped: nil, standard: nil),
            1.0 / 12.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ImageIOAPNGDecoder.normalizedDelay(unclamped: 0.001, standard: nil),
            1.0 / 60.0,
            accuracy: 0.000_001
        )
    }

    private func assertFixtureFails(limits: APNGDecoderLimits, expected: AvatarImportError) {
        XCTAssertThrowsError(try ImageIOAPNGDecoder(limits: limits).decode(url: checkedInAPNG)) { error in
            XCTAssertEqual(error as? AvatarImportError, expected)
        }
    }

    private var checkedInAPNG: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AgentMascotApp/Resources/Mascots/haland.apng")
    }

    private func temporaryFile(data: Data, extension fileExtension: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }
}
