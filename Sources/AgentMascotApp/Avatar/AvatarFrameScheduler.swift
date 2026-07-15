import Foundation

enum AvatarFrameScheduler {
    static func frameIndex(elapsed: TimeInterval, animation: APNGAnimation) -> Int {
        guard elapsed >= 0 else { return 0 }

        let position = elapsed.truncatingRemainder(dividingBy: animation.totalDuration)
        let boundaryTolerance = 1e-9
        return animation.frames.firstIndex { position < $0.cumulativeEndTime - boundaryTolerance }
            ?? (animation.frames.count - 1)
    }
}
