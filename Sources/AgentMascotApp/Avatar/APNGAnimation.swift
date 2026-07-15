import CoreGraphics
import Foundation

struct APNGFrame: Sendable {
    let image: CGImage
    let duration: TimeInterval
    let cumulativeEndTime: TimeInterval
}

struct APNGAnimation: Sendable {
    let frames: [APNGFrame]
    let totalDuration: TimeInterval

    init(images: [CGImage], durations: [TimeInterval]) throws {
        guard !images.isEmpty,
              images.count == durations.count,
              durations.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            throw AvatarImportError.malformedFrames
        }

        var cumulative = 0.0
        var builtFrames: [APNGFrame] = []
        builtFrames.reserveCapacity(images.count)

        for (image, duration) in zip(images, durations) {
            cumulative += duration
            guard cumulative.isFinite else {
                throw AvatarImportError.malformedFrames
            }
            builtFrames.append(
                APNGFrame(
                    image: image,
                    duration: duration,
                    cumulativeEndTime: cumulative
                )
            )
        }

        frames = builtFrames
        totalDuration = cumulative
    }
}

protocol APNGDecoding: Sendable {
    func decode(url: URL) throws -> APNGAnimation
}

enum AvatarImportError: Error, Equatable, LocalizedError, Sendable {
    case unreadableFile
    case notAnimatedPNG
    case fileTooLarge(maxBytes: Int)
    case tooManyFrames(maximum: Int)
    case invalidDimensions(maximum: Int)
    case decodedDataTooLarge(maxBytes: Int)
    case malformedFrames
    case persistenceFailed

    var errorDescription: String? {
        switch self {
        case .unreadableFile:
            "The selected file could not be read."
        case .notAnimatedPNG:
            "Choose an animated PNG with at least two frames."
        case let .fileTooLarge(maxBytes):
            "The selected avatar is larger than \(maxBytes / 1_048_576) MB."
        case let .tooManyFrames(maximum):
            "The selected avatar has more than \(maximum) frames."
        case let .invalidDimensions(maximum):
            "Each avatar frame must be no larger than \(maximum) × \(maximum) pixels."
        case let .decodedDataTooLarge(maxBytes):
            "The selected avatar would use more than \(maxBytes / 1_048_576) MiB when decoded."
        case .malformedFrames:
            "The selected animation contains malformed frames or timing."
        case .persistenceFailed:
            "Agent Mascot could not save the selected avatar."
        }
    }
}
