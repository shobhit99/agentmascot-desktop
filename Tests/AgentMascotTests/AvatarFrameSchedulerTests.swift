import CoreGraphics
import XCTest
@testable import AgentMascotApp

final class AvatarFrameSchedulerTests: XCTestCase {
    func testSchedulerUsesVariableDurationsAndExactBoundaries() throws {
        let animation = try makeAnimation(durations: [0.1, 0.2, 0.3])

        XCTAssertEqual(AvatarFrameScheduler.frameIndex(elapsed: 0, animation: animation), 0)
        XCTAssertEqual(AvatarFrameScheduler.frameIndex(elapsed: 0.099, animation: animation), 0)
        XCTAssertEqual(AvatarFrameScheduler.frameIndex(elapsed: 0.1, animation: animation), 1)
        XCTAssertEqual(AvatarFrameScheduler.frameIndex(elapsed: 0.299, animation: animation), 1)
        XCTAssertEqual(AvatarFrameScheduler.frameIndex(elapsed: 0.3, animation: animation), 2)
        XCTAssertEqual(AvatarFrameScheduler.frameIndex(elapsed: 0.599, animation: animation), 2)
    }

    func testSchedulerLoopsContinuously() throws {
        let animation = try makeAnimation(durations: [0.1, 0.2, 0.3])

        XCTAssertEqual(
            AvatarFrameScheduler.frameIndex(elapsed: animation.totalDuration, animation: animation),
            0
        )
        XCTAssertEqual(
            AvatarFrameScheduler.frameIndex(elapsed: animation.totalDuration + 0.11, animation: animation),
            1
        )
        XCTAssertEqual(
            AvatarFrameScheduler.frameIndex(elapsed: animation.totalDuration * 2 + 0.01, animation: animation),
            0
        )
    }

    func testSchedulerTreatsNegativeElapsedTimeAsFirstFrame() throws {
        let animation = try makeAnimation(durations: [0.1, 0.2])
        XCTAssertEqual(AvatarFrameScheduler.frameIndex(elapsed: -1, animation: animation), 0)
    }

    private func makeAnimation(durations: [TimeInterval]) throws -> APNGAnimation {
        let image = makeImage()
        return try APNGAnimation(
            images: Array(repeating: image, count: durations.count),
            durations: durations
        )
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
