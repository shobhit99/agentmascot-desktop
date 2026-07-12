import SwiftUI

struct MascotView: View {
    @EnvironmentObject var videoProvider: VideoFrameProvider
    @State private var pulse = false

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            speechBubble
            mascotImage
                .frame(width: 220, height: 124)
        }
        .frame(width: 380, height: 150)
    }

    @ViewBuilder
    private var mascotImage: some View {
        if let image = videoProvider.image {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Color.clear
        }
    }

    private var speechBubble: some View {
        HStack(spacing: 6) {
            Text("Working")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)

            HStack(spacing: 3) {
                ForEach(0..<3) { i in
                    Circle()
                        .frame(width: 5, height: 5)
                        .foregroundColor(.secondary)
                        .opacity(pulse ? 1 : 0.3)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever(autoreverses: true)
                                .delay(Double(i) * 0.2),
                            value: pulse
                        )
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        )
        .onAppear { pulse = true }
    }
}
