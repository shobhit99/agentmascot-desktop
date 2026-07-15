import Foundation

enum AvatarFrameScheduler {
    static func frameIndex(elapsed: TimeInterval, animation: APNGAnimation) -> Int {
        guard elapsed >= 0 else { return 0 }

        let loopPosition = elapsed.truncatingRemainder(dividingBy: animation.totalDuration)
        guard let position = decimalTimeInterval(loopPosition) else {
            return animation.frames.count - 1
        }

        // Preserve the Double modulo calculation, then compare canonical
        // decimal values so decimal frame boundaries do not drift from sums
        // such as 0.1 + 0.2.
        var cumulativeDuration = Decimal.zero
        for (index, frame) in animation.frames.enumerated() {
            guard let duration = decimalTimeInterval(frame.duration) else {
                return animation.frames.count - 1
            }

            cumulativeDuration += duration
            if position < cumulativeDuration {
                return index
            }
        }

        return animation.frames.count - 1
    }

    private static func decimalTimeInterval(_ interval: TimeInterval) -> Decimal? {
        Decimal(string: String(interval), locale: Locale(identifier: "en_US_POSIX"))
    }
}
