import Foundation

enum AvatarFrameScheduler {
    static func frameIndex(elapsed: TimeInterval, animation: APNGAnimation) -> Int {
        guard elapsed >= 0 else { return 0 }

        let position = elapsed.truncatingRemainder(dividingBy: animation.totalDuration)
        return animation.frames.firstIndex { frame in
            // The immediately preceding representable value remains in the
            // prior frame, while the cumulative boundary itself advances.
            position <= frame.cumulativeEndTime.nextDown
        }
            ?? (animation.frames.count - 1)
    }
}
