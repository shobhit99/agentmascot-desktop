import SwiftUI

struct APNGAvatarView: View {
    let animation: APNGAnimation
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(startedAt)
            let index = AvatarFrameScheduler.frameIndex(
                elapsed: elapsed,
                animation: animation
            )

            Image(decorative: animation.frames[index].image, scale: 1)
                .resizable()
                .scaledToFit()
        }
    }
}
