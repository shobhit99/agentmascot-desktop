import Foundation
import ImageIO
import UniformTypeIdentifiers

struct APNGDecoderLimits: Sendable, Equatable {
    let maxFileBytes: Int
    let maxFrameCount: Int
    let maxDimension: Int
    let maxDecodedBytes: Int

    init(
        maxFileBytes: Int = 25 * 1_048_576,
        maxFrameCount: Int = 300,
        maxDimension: Int = 4096,
        maxDecodedBytes: Int = 128 * 1_048_576
    ) {
        self.maxFileBytes = maxFileBytes
        self.maxFrameCount = maxFrameCount
        self.maxDimension = maxDimension
        self.maxDecodedBytes = maxDecodedBytes
    }

    static let production = APNGDecoderLimits()
}

struct ImageIOAPNGDecoder: APNGDecoding {
    let limits: APNGDecoderLimits

    init(limits: APNGDecoderLimits = .production) {
        self.limits = limits
    }

    func decode(url: URL) throws -> APNGAnimation {
        let resourceValues: URLResourceValues
        do {
            resourceValues = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        } catch {
            throw AvatarImportError.unreadableFile
        }

        guard resourceValues.isRegularFile == true,
              let fileSize = resourceValues.fileSize else {
            throw AvatarImportError.unreadableFile
        }
        guard fileSize <= limits.maxFileBytes else {
            throw AvatarImportError.fileTooLarge(maxBytes: limits.maxFileBytes)
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sourceType = CGImageSourceGetType(source),
              sourceType as String == UTType.png.identifier else {
            throw AvatarImportError.unreadableFile
        }

        let frameCount = CGImageSourceGetCount(source)
        guard frameCount >= 2 else {
            throw AvatarImportError.notAnimatedPNG
        }
        guard frameCount <= limits.maxFrameCount else {
            throw AvatarImportError.tooManyFrames(maximum: limits.maxFrameCount)
        }

        var decodedBytes = 0
        var images: [CGImage] = []
        var durations: [TimeInterval] = []
        images.reserveCapacity(frameCount)
        durations.reserveCapacity(frameCount)

        for index in 0..<frameCount {
            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil)
                as? [CFString: Any],
                  let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
                  let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
                  width > 0,
                  height > 0 else {
                throw AvatarImportError.malformedFrames
            }
            guard width <= limits.maxDimension, height <= limits.maxDimension else {
                throw AvatarImportError.invalidDimensions(maximum: limits.maxDimension)
            }

            let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
            let (frameBytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
            let (newDecodedBytes, totalOverflow) = decodedBytes.addingReportingOverflow(frameBytes)
            guard !pixelOverflow,
                  !byteOverflow,
                  !totalOverflow,
                  newDecodedBytes <= limits.maxDecodedBytes else {
                throw AvatarImportError.decodedDataTooLarge(maxBytes: limits.maxDecodedBytes)
            }
            decodedBytes = newDecodedBytes

            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else {
                throw AvatarImportError.malformedFrames
            }

            let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any]
            let unclamped = (png?[kCGImagePropertyAPNGUnclampedDelayTime] as? NSNumber)?.doubleValue
            let standard = (png?[kCGImagePropertyAPNGDelayTime] as? NSNumber)?.doubleValue

            images.append(image)
            durations.append(Self.normalizedDelay(unclamped: unclamped, standard: standard))
        }

        return try APNGAnimation(images: images, durations: durations)
    }

    static func normalizedDelay(unclamped: Double?, standard: Double?) -> TimeInterval {
        let selected = [unclamped, standard]
            .compactMap { $0 }
            .first { $0.isFinite && $0 > 0 }
            ?? (1.0 / 12.0)
        return max(1.0 / 60.0, selected)
    }
}
