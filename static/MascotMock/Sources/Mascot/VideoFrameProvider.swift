import AVFoundation
import AppKit
import Combine
import CoreImage

final class VideoFrameProvider: ObservableObject {
    @Published var image: NSImage?

    private var player: AVPlayer?
    private var output: AVPlayerItemVideoOutput?
    private var timer: Timer?
    private let ciContext = CIContext()

    func start() {
        guard let url = Bundle.module.url(forResource: "haland_out", withExtension: "mov") else {
            print("Could not find haland_out.mov in bundle resources")
            return
        }

        let item = AVPlayerItem(url: url)
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: attributes)
        item.add(output)
        self.output = output

        let player = AVPlayer(playerItem: item)
        player.actionAtItemEnd = .none
        self.player = player

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(loop),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )

        player.play()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    @objc private func loop() {
        player?.seek(to: .zero)
        player?.play()
    }

    private func tick() {
        guard let output = output, let player = player else { return }
        let time = player.currentTime()
        guard output.hasNewPixelBuffer(forItemTime: time) else { return }
        guard let pixelBuffer = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else { return }

        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }

        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: ciImage.extent.width, height: ciImage.extent.height))
        DispatchQueue.main.async {
            self.image = nsImage
        }
    }
}
