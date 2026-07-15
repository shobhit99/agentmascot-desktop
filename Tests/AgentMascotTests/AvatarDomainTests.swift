import CoreGraphics
import XCTest
@testable import AgentMascotApp

final class AvatarDomainTests: XCTestCase {
    func testAnimationBuildsCumulativeTimeline() throws {
        let image = makeImage()
        let animation = try APNGAnimation(
            images: [image, image, image],
            durations: [0.1, 0.2, 0.3]
        )

        XCTAssertEqual(animation.frames.map(\.duration), [0.1, 0.2, 0.3])
        XCTAssertEqual(animation.frames[0].cumulativeEndTime, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(animation.frames[1].cumulativeEndTime, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(animation.frames[2].cumulativeEndTime, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(animation.totalDuration, 0.6, accuracy: 0.000_001)
    }

    func testAnimationRejectsEmptyMismatchedOrInvalidFrames() {
        let image = makeImage()

        assertMalformed(images: [], durations: [])
        assertMalformed(images: [image], durations: [])
        assertMalformed(images: [image], durations: [0])
        assertMalformed(images: [image], durations: [.infinity])
    }

    func testImportErrorsExposeStableUserMessages() {
        XCTAssertEqual(
            AvatarImportError.notAnimatedPNG.errorDescription,
            "Choose an animated PNG with at least two frames."
        )
        XCTAssertEqual(
            AvatarImportError.persistenceFailed.errorDescription,
            "Agent Mascot could not save the selected avatar."
        )
    }

    private func assertMalformed(images: [CGImage], durations: [TimeInterval]) {
        XCTAssertThrowsError(try APNGAnimation(images: images, durations: durations)) { error in
            XCTAssertEqual(error as? AvatarImportError, .malformedFrames)
        }
    }

    private func makeImage() -> CGImage {
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
}
