import Foundation

enum AvatarFrameScheduler {
    static func frameIndex(elapsed: TimeInterval, animation: APNGAnimation) -> Int {
        guard elapsed >= 0 else { return 0 }

        let position = elapsed.truncatingRemainder(dividingBy: animation.totalDuration)
        return animation.frames.firstIndex { frame in
            // Treat only the immediately adjacent representable value before a
            // cumulative boundary as the boundary itself. This absorbs
            // rounding from sums such as 0.1 + 0.2 without advancing early.
            position < frame.cumulativeEndTime - frame.cumulativeEndTime.ulp
        }
            ?? (animation.frames.count - 1)
    }
}
