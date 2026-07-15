# Custom Floating Avatar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:dispatching-parallel-agents` for the independent Wave 1 tasks, and `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` for the sequential tasks. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user choose one APNG from the Agent Mascot menu-bar window and persist it as the floating mascot avatar.

**Architecture:** A native ImageIO decoder produces a validated animation domain value, an atomic store owns `~/Library/Application Support/Agent Mascot/avatar.apng`, and a pure scheduler drives a SwiftUI APNG view. A selection coordinator loads and replaces the saved avatar away from the main actor, while menu and Settings presentation contexts keep the picker menu-bar-only.

**Tech Stack:** Swift 6.2, SwiftUI, AppKit, Observation, ImageIO, CoreGraphics, UniformTypeIdentifiers, XCTest, Swift Package Manager; macOS 15 minimum.

## Global Constraints

- Change only the 360×203 animated image in the floating mascot panel.
- Keep the menu-bar icon and static menu/settings mascot unchanged.
- Show **Change Avatar…** only in the menu-bar window; do not show it in Settings.
- Do not add restore, remove, reset, preview, crop, zoom, or gallery controls.
- Accept exactly one animated PNG, using `.apng` or `.png`; reject static PNGs and all other formats by inspecting their contents.
- Copy the accepted file to `~/Library/Application Support/Agent Mascot/avatar.apng`; never depend on the original file after import.
- Preserve the previous displayed and persisted avatar on every failed import.
- Decode at most 25 MB (26,214,400 bytes), 300 frames, 4096×4096 per frame, and 128 MiB (134,217,728 bytes) of estimated decoded RGBA storage.
- Prefer APNG unclamped delay, then standard delay, then 1/12 second; clamp delays below 1/60 second to 1/60 second.
- Loop continuously and aspect-fit without cropping, stretching, resizing the panel, or changing the status capsule.
- Add no third-party dependency and keep the source APNG/MOV excluded from the signed app bundle.
- Treat `docs/superpowers/specs/2026-07-15-custom-floating-avatar-design.md` as the authoritative behavior contract.

---

## File Structure

### New production files

- `Sources/AgentMascotApp/Avatar/APNGAnimation.swift` — animation value, decoder protocol, and stable import errors.
- `Sources/AgentMascotApp/Avatar/ImageIOAPNGDecoder.swift` — ImageIO validation, frame decoding, limits, and delay normalization.
- `Sources/AgentMascotApp/Avatar/CustomAvatarStore.swift` — Application Support persistence and atomic replacement.
- `Sources/AgentMascotApp/Avatar/AvatarFrameScheduler.swift` — pure elapsed-time-to-frame mapping.
- `Sources/AgentMascotApp/Avatar/AvatarFilePicker.swift` — APNG/PNG `NSOpenPanel` configuration.
- `Sources/AgentMascotApp/Avatar/AvatarSelectionCoordinator.swift` — startup load and user-selection workflow.
- `Sources/AgentMascotApp/UI/Mascot/APNGAvatarView.swift` — SwiftUI timeline renderer.
- `Sources/AgentMascotApp/UI/Avatar/AvatarMenuControl.swift` — menu-bar-only action and accessible error.

### Modified production files

- `Sources/AgentMascotApp/App/AppModel.swift` — observable avatar state and injected choose action.
- `Sources/AgentMascotApp/AgentMascotApp.swift` — lifecycle coordinator and menu/settings presentation context wiring.
- `Sources/AgentMascotApp/UI/RootView.swift` — presentation context and conditional avatar control.
- `Sources/AgentMascotApp/UI/Mascot/VideoMascotWidget.swift` — custom/bundled renderer selection.
- `README.md` — user-facing avatar and persistence behavior.
- `docs/manual-acceptance.md` — custom-avatar acceptance coverage.

### New tests

- `Tests/AgentMascotTests/AvatarDomainTests.swift`
- `Tests/AgentMascotTests/ImageIOAPNGDecoderTests.swift`
- `Tests/AgentMascotTests/CustomAvatarStoreTests.swift`
- `Tests/AgentMascotTests/AvatarFrameSchedulerTests.swift`
- `Tests/AgentMascotTests/AvatarSelectionCoordinatorTests.swift`
- `Tests/AgentMascotTests/AvatarPresentationTests.swift`

`Package.swift` does not need a dependency or source-list change because SwiftPM discovers the new Swift files automatically.

## Parallel Execution Map

1. Execute Task 1 sequentially and commit the shared contracts.
2. Use `superpowers:using-git-worktrees` at execution time to create three worktrees from the Task 1 commit:

```bash
git worktree add -b codex/custom-avatar-menu-decoder /tmp/agentmascot-avatar-decoder HEAD
git worktree add -b codex/custom-avatar-menu-store /tmp/agentmascot-avatar-store HEAD
git worktree add -b codex/custom-avatar-menu-playback /tmp/agentmascot-avatar-playback HEAD
```

3. Dispatch all three Wave 1 agents in one parallel call with `fork_turns="none"`:

- Decoder agent workdir: `/tmp/agentmascot-avatar-decoder`; implement only Task 2.
- Store agent workdir: `/tmp/agentmascot-avatar-store`; implement only Task 3.
- Playback agent workdir: `/tmp/agentmascot-avatar-playback`; implement only Task 4.

Each prompt must include the applicable task text, the Global Constraints, its exact workdir, the instruction not to edit files owned by another task, and this required return shape: commit hash, files changed, commands run with results, and unresolved concerns.

Use these exact focused prompts:

```text
Work in /tmp/agentmascot-avatar-decoder on branch codex/custom-avatar-menu-decoder. Read the Global Constraints and Task 2 in docs/superpowers/plans/2026-07-15-custom-floating-avatar.md, then implement Task 2 exactly with TDD. Your scope is only Sources/AgentMascotApp/Avatar/ImageIOAPNGDecoder.swift and Tests/AgentMascotTests/ImageIOAPNGDecoderTests.swift. Do not edit the shared Task 1 contract or any store, playback, model, lifecycle, documentation, or UI file. Run every Task 2 command and commit with the specified message. Return the commit hash, files changed, commands with pass/fail results, and any unresolved concern.
```

```text
Work in /tmp/agentmascot-avatar-store on branch codex/custom-avatar-menu-store. Read the Global Constraints and Task 3 in docs/superpowers/plans/2026-07-15-custom-floating-avatar.md, then implement Task 3 exactly with TDD. Your scope is only Sources/AgentMascotApp/Avatar/CustomAvatarStore.swift and Tests/AgentMascotTests/CustomAvatarStoreTests.swift. Depend only on the Task 1 APNGDecoding contract. Do not edit the decoder, playback, model, lifecycle, documentation, or UI files. Run every Task 3 command and commit with the specified message. Return the commit hash, files changed, commands with pass/fail results, and any unresolved concern.
```

```text
Work in /tmp/agentmascot-avatar-playback on branch codex/custom-avatar-menu-playback. Read the Global Constraints and Task 4 in docs/superpowers/plans/2026-07-15-custom-floating-avatar.md, then implement Task 4 exactly with TDD. Your scope is only Sources/AgentMascotApp/Avatar/AvatarFrameScheduler.swift, Sources/AgentMascotApp/UI/Mascot/APNGAvatarView.swift, and Tests/AgentMascotTests/AvatarFrameSchedulerTests.swift. Do not edit VideoMascotWidget.swift or any decoder, store, model, lifecycle, documentation, or other UI file. Run every Task 4 command and commit with the specified message. Return the commit hash, files changed, commands with pass/fail results, and any unresolved concern.
```

4. Review each result, then merge the three exact branches on `codex/custom-avatar-menu`:

```bash
git merge --no-ff codex/custom-avatar-menu-decoder
git merge --no-ff codex/custom-avatar-menu-store
git merge --no-ff codex/custom-avatar-menu-playback
swift test --filter 'AvatarDomainTests|ImageIOAPNGDecoderTests|CustomAvatarStoreTests|AvatarFrameSchedulerTests'
```

Expected: all four test classes pass and the merges touch disjoint files outside the shared Task 1 contracts.

5. Execute Tasks 5–7 sequentially after Wave 1 is integrated.

---

### Task 1: Establish the avatar domain contract

**Execution:** Sequential prerequisite.

**Files:**
- Create: `Sources/AgentMascotApp/Avatar/APNGAnimation.swift`
- Test: `Tests/AgentMascotTests/AvatarDomainTests.swift`

**Interfaces:**
- Produces: `APNGFrame`, `APNGAnimation.init(images:durations:)`, `APNGDecoding.decode(url:)`, and `AvatarImportError`.
- Consumers: Tasks 2, 3, 4, and 5 use these names and signatures unchanged.

- [ ] **Step 1: Write the failing domain tests**

Create `Tests/AgentMascotTests/AvatarDomainTests.swift`:

```swift
import CoreGraphics
import XCTest
@testable import AgentMascotApp

final class AvatarDomainTests: XCTestCase {
    func testAnimationBuildsCumulativeTimeline() throws {
        let image = makeImage()
        let animation = try APNGAnimation(
            images: [image, image, image],
            durations: [0.1, 0.2, 0.3]
        )

        XCTAssertEqual(animation.frames.map(\.duration), [0.1, 0.2, 0.3])
        XCTAssertEqual(animation.frames[0].cumulativeEndTime, 0.1, accuracy: 0.000_001)
        XCTAssertEqual(animation.frames[1].cumulativeEndTime, 0.3, accuracy: 0.000_001)
        XCTAssertEqual(animation.frames[2].cumulativeEndTime, 0.6, accuracy: 0.000_001)
        XCTAssertEqual(animation.totalDuration, 0.6, accuracy: 0.000_001)
    }

    func testAnimationRejectsEmptyMismatchedOrInvalidFrames() {
        let image = makeImage()

        assertMalformed(images: [], durations: [])
        assertMalformed(images: [image], durations: [])
        assertMalformed(images: [image], durations: [0])
        assertMalformed(images: [image], durations: [.infinity])
    }

    func testImportErrorsExposeStableUserMessages() {
        XCTAssertEqual(
            AvatarImportError.notAnimatedPNG.errorDescription,
            "Choose an animated PNG with at least two frames."
        )
        XCTAssertEqual(
            AvatarImportError.persistenceFailed.errorDescription,
            "Agent Mascot could not save the selected avatar."
        )
    }

    private func assertMalformed(images: [CGImage], durations: [TimeInterval]) {
        XCTAssertThrowsError(try APNGAnimation(images: images, durations: durations)) { error in
            XCTAssertEqual(error as? AvatarImportError, .malformedFrames)
        }
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
```

- [ ] **Step 2: Run the test and verify the contract is absent**

Run:

```bash
swift test --filter AvatarDomainTests
```

Expected: compilation fails with errors such as `cannot find 'APNGAnimation' in scope`.

- [ ] **Step 3: Implement the domain values, protocol, and errors**

Create `Sources/AgentMascotApp/Avatar/APNGAnimation.swift`:

```swift
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
```

- [ ] **Step 4: Run the domain tests**

Run:

```bash
swift test --filter AvatarDomainTests
```

Expected: `AvatarDomainTests` passes.

- [ ] **Step 5: Commit the shared contract**

```bash
git add Sources/AgentMascotApp/Avatar/APNGAnimation.swift Tests/AgentMascotTests/AvatarDomainTests.swift
git commit -m "feat: define custom avatar domain"
```

Expected: one commit containing only the domain file and its tests. Create all three Wave 1 worktrees from this commit.

---

### Task 2: Decode and validate APNG files with ImageIO

**Execution:** Wave 1 parallel agent A in `/tmp/agentmascot-avatar-decoder`.

**Files:**
- Create: `Sources/AgentMascotApp/Avatar/ImageIOAPNGDecoder.swift`
- Test: `Tests/AgentMascotTests/ImageIOAPNGDecoderTests.swift`

**Interfaces:**
- Consumes: `APNGAnimation.init(images:durations:)`, `APNGDecoding`, and `AvatarImportError` from Task 1.
- Produces: `APNGDecoderLimits.production`, `ImageIOAPNGDecoder.init(limits:)`, `decode(url:)`, and `normalizedDelay(unclamped:standard:)`.
- Constraint: do not edit the Task 1 contract or any store, playback, model, or UI file.

- [ ] **Step 1: Write failing decoder tests**

Create `Tests/AgentMascotTests/ImageIOAPNGDecoderTests.swift`:

```swift
import Foundation
import XCTest
@testable import AgentMascotApp

final class ImageIOAPNGDecoderTests: XCTestCase {
    func testCheckedInAPNGDecodesFramesDimensionsAndTiming() throws {
        let animation = try ImageIOAPNGDecoder().decode(url: checkedInAPNG)

        XCTAssertEqual(animation.frames.count, 97)
        XCTAssertEqual(animation.frames[0].image.width, 640)
        XCTAssertEqual(animation.frames[0].image.height, 360)
        XCTAssertEqual(animation.frames[0].duration, 1.0 / 24.0, accuracy: 0.002)
        XCTAssertGreaterThan(animation.totalDuration, 0)
    }

    func testCorruptAndStaticPNGInputsAreRejected() throws {
        let corrupt = try temporaryFile(data: Data("not an image".utf8), extension: "apng")
        defer { try? FileManager.default.removeItem(at: corrupt) }

        XCTAssertThrowsError(try ImageIOAPNGDecoder().decode(url: corrupt)) { error in
            XCTAssertEqual(error as? AvatarImportError, .unreadableFile)
        }

        let staticPNG = Data(
            base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9WlBzZkAAAAASUVORK5CYII="
        )!
        let staticURL = try temporaryFile(data: staticPNG, extension: "png")
        defer { try? FileManager.default.removeItem(at: staticURL) }

        XCTAssertThrowsError(try ImageIOAPNGDecoder().decode(url: staticURL)) { error in
            XCTAssertEqual(error as? AvatarImportError, .notAnimatedPNG)
        }
    }

    func testProductionLimitsAreEnforcedIndependently() {
        assertFixtureFails(
            limits: APNGDecoderLimits(maxFileBytes: 1),
            expected: .fileTooLarge(maxBytes: 1)
        )
        assertFixtureFails(
            limits: APNGDecoderLimits(maxFrameCount: 2),
            expected: .tooManyFrames(maximum: 2)
        )
        assertFixtureFails(
            limits: APNGDecoderLimits(maxDimension: 100),
            expected: .invalidDimensions(maximum: 100)
        )
        assertFixtureFails(
            limits: APNGDecoderLimits(maxDecodedBytes: 1),
            expected: .decodedDataTooLarge(maxBytes: 1)
        )
    }

    func testDelayPreferenceFallbackAndClamp() {
        XCTAssertEqual(
            ImageIOAPNGDecoder.normalizedDelay(unclamped: 1.0 / 24.0, standard: 0.05),
            1.0 / 24.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ImageIOAPNGDecoder.normalizedDelay(unclamped: 0, standard: 0.1),
            0.1,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ImageIOAPNGDecoder.normalizedDelay(unclamped: nil, standard: nil),
            1.0 / 12.0,
            accuracy: 0.000_001
        )
        XCTAssertEqual(
            ImageIOAPNGDecoder.normalizedDelay(unclamped: 0.001, standard: nil),
            1.0 / 60.0,
            accuracy: 0.000_001
        )
    }

    private func assertFixtureFails(limits: APNGDecoderLimits, expected: AvatarImportError) {
        XCTAssertThrowsError(try ImageIOAPNGDecoder(limits: limits).decode(url: checkedInAPNG)) { error in
            XCTAssertEqual(error as? AvatarImportError, expected)
        }
    }

    private var checkedInAPNG: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/AgentMascotApp/Resources/Mascots/haland.apng")
    }

    private func temporaryFile(data: Data, extension fileExtension: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try data.write(to: url, options: .atomic)
        return url
    }
}
```

- [ ] **Step 2: Run the decoder tests and verify the implementation is absent**

Run:

```bash
swift test --filter ImageIOAPNGDecoderTests
```

Expected: compilation fails with `cannot find 'ImageIOAPNGDecoder' in scope` and `cannot find 'APNGDecoderLimits' in scope`.

- [ ] **Step 3: Implement the decoder and resource limits**

Create `Sources/AgentMascotApp/Avatar/ImageIOAPNGDecoder.swift`:

```swift
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
```

- [ ] **Step 4: Run decoder and shared-domain tests**

Run:

```bash
swift test --filter 'AvatarDomainTests|ImageIOAPNGDecoderTests'
```

Expected: both test classes pass; the checked-in APNG reports 97 decoded frames.

- [ ] **Step 5: Commit the decoder worktree**

```bash
git add Sources/AgentMascotApp/Avatar/ImageIOAPNGDecoder.swift Tests/AgentMascotTests/ImageIOAPNGDecoderTests.swift
git commit -m "feat: decode custom APNG avatars"
```

Expected: one commit on `codex/custom-avatar-menu-decoder`. Return its hash and the test output summary to the coordinator.

---

### Task 3: Persist the selected avatar with rollback-safe replacement

**Execution:** Wave 1 parallel agent B in `/tmp/agentmascot-avatar-store`.

**Files:**
- Create: `Sources/AgentMascotApp/Avatar/CustomAvatarStore.swift`
- Test: `Tests/AgentMascotTests/CustomAvatarStoreTests.swift`

**Interfaces:**
- Consumes: `APNGAnimation`, `APNGDecoding`, and `AvatarImportError` from Task 1.
- Produces: `CustomAvatarStore.init(directoryURL:decoder:fileSystem:)`, `avatarURL`, `load()`, and `importAvatar(from:)`.
- Constraint: use only the Task 1 protocol; do not depend on or edit the concrete ImageIO decoder, playback, model, or UI files.

- [ ] **Step 1: Write failing persistence and rollback tests**

Create `Tests/AgentMascotTests/CustomAvatarStoreTests.swift`:

```swift
import CoreGraphics
import Foundation
import XCTest
@testable import AgentMascotApp

final class CustomAvatarStoreTests: XCTestCase {
    func testLoadReturnsNilWhenNoSavedAvatarExists() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = CustomAvatarStore(directoryURL: root, decoder: StubDecoder())
        XCTAssertNil(try store.load())
    }

    func testImportCopiesBytesAndDoesNotDependOnOriginal() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".apng")
        defer { try? FileManager.default.removeItem(at: source) }
        try Data("first-avatar".utf8).write(to: source)
        let store = CustomAvatarStore(directoryURL: root, decoder: StubDecoder())

        let animation = try store.importAvatar(from: source)
        try FileManager.default.removeItem(at: source)

        XCTAssertEqual(animation.frames.count, 2)
        XCTAssertEqual(try Data(contentsOf: store.avatarURL), Data("first-avatar".utf8))
        XCTAssertNotNil(try store.load())
    }

    func testSecondImportReplacesExistingAvatar() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try sourceFile(named: "first.apng", bytes: "first")
        let second = try sourceFile(named: "second.apng", bytes: "second")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        let store = CustomAvatarStore(directoryURL: root, decoder: StubDecoder())

        _ = try store.importAvatar(from: first)
        _ = try store.importAvatar(from: second)

        XCTAssertEqual(try Data(contentsOf: store.avatarURL), Data("second".utf8))
    }

    func testSourceValidationFailurePreservesExistingAvatar() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("old".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let invalid = try sourceFile(named: "invalid.apng", bytes: "invalid")
        defer { try? FileManager.default.removeItem(at: invalid) }
        let store = CustomAvatarStore(
            directoryURL: root,
            decoder: StubDecoder(failure: .sourceNamed("invalid.apng"))
        )

        XCTAssertThrowsError(try store.importAvatar(from: invalid)) { error in
            XCTAssertEqual(error as? AvatarImportError, .notAnimatedPNG)
        }
        XCTAssertEqual(try Data(contentsOf: store.avatarURL), Data("old".utf8))
    }

    func testStagedValidationFailurePreservesExistingAvatarAndCleansStage() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("old".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let source = try sourceFile(named: "new.apng", bytes: "new")
        defer { try? FileManager.default.removeItem(at: source) }
        let store = CustomAvatarStore(
            directoryURL: root,
            decoder: StubDecoder(failure: .stagingFile)
        )

        XCTAssertThrowsError(try store.importAvatar(from: source)) { error in
            XCTAssertEqual(error as? AvatarImportError, .malformedFrames)
        }
        XCTAssertEqual(try Data(contentsOf: store.avatarURL), Data("old".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["avatar.apng"])
    }

    func testReplacementFailurePreservesExistingAvatarAndMapsPersistenceError() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("old".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let source = try sourceFile(named: "new.apng", bytes: "new")
        defer { try? FileManager.default.removeItem(at: source) }
        let store = CustomAvatarStore(
            directoryURL: root,
            decoder: StubDecoder(),
            fileSystem: ReplacementFailingFileSystem()
        )

        XCTAssertThrowsError(try store.importAvatar(from: source)) { error in
            XCTAssertEqual(error as? AvatarImportError, .persistenceFailed)
        }
        XCTAssertEqual(try Data(contentsOf: store.avatarURL), Data("old".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["avatar.apng"])
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sourceFile(named name: String, bytes: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + name)
        try Data(bytes.utf8).write(to: url)
        return url
    }
}

private struct StubDecoder: APNGDecoding {
    enum Failure: Sendable {
        case none
        case sourceNamed(String)
        case stagingFile
    }

    let failure: Failure

    init(failure: Failure = .none) {
        self.failure = failure
    }

    func decode(url: URL) throws -> APNGAnimation {
        switch failure {
        case .none:
            break
        case let .sourceNamed(name) where url.lastPathComponent.hasSuffix(name):
            throw AvatarImportError.notAnimatedPNG
        case .stagingFile where url.lastPathComponent.hasPrefix(".avatar-"):
            throw AvatarImportError.malformedFrames
        default:
            break
        }
        let image = makeTestImage()
        return try APNGAnimation(images: [image, image], durations: [0.1, 0.1])
    }
}

private struct ReplacementFailingFileSystem: AvatarFileSystem {
    private let base = LocalAvatarFileSystem()

    func fileExists(at url: URL) -> Bool { base.fileExists(at: url) }
    func createDirectory(at url: URL) throws { try base.createDirectory(at: url) }
    func copyItem(at source: URL, to destination: URL) throws {
        try base.copyItem(at: source, to: destination)
    }
    func moveItem(at source: URL, to destination: URL) throws {
        try base.moveItem(at: source, to: destination)
    }
    func replaceItem(at destination: URL, with source: URL) throws {
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)
    }
    func removeItemIfExists(at url: URL) throws { try base.removeItemIfExists(at: url) }
}

private func makeTestImage() -> CGImage {
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
```

- [ ] **Step 2: Run the store tests and verify the store is absent**

Run:

```bash
swift test --filter CustomAvatarStoreTests
```

Expected: compilation fails with `cannot find 'CustomAvatarStore' in scope` and `cannot find type 'AvatarFileSystem' in scope`.

- [ ] **Step 3: Implement the file-system seam and atomic store**

Create `Sources/AgentMascotApp/Avatar/CustomAvatarStore.swift`:

```swift
import Foundation

protocol AvatarFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func copyItem(at source: URL, to destination: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func replaceItem(at destination: URL, with source: URL) throws
    func removeItemIfExists(at url: URL) throws
}

struct LocalAvatarFileSystem: AvatarFileSystem {
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func copyItem(at source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func replaceItem(at destination: URL, with source: URL) throws {
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: source)
    }

    func removeItemIfExists(at url: URL) throws {
        guard fileExists(at: url) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

struct CustomAvatarStore: Sendable {
    let directoryURL: URL
    let decoder: any APNGDecoding
    let fileSystem: any AvatarFileSystem

    init(
        directoryURL: URL,
        decoder: any APNGDecoding,
        fileSystem: any AvatarFileSystem = LocalAvatarFileSystem()
    ) {
        self.directoryURL = directoryURL
        self.decoder = decoder
        self.fileSystem = fileSystem
    }

    var avatarURL: URL {
        directoryURL.appendingPathComponent("avatar.apng", isDirectory: false)
    }

    func load() throws -> APNGAnimation? {
        guard fileSystem.fileExists(at: avatarURL) else { return nil }
        return try decoder.decode(url: avatarURL)
    }

    func importAvatar(from sourceURL: URL) throws -> APNGAnimation {
        _ = try decoder.decode(url: sourceURL)

        let stagingURL = directoryURL
            .appendingPathComponent(".avatar-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("apng")
        defer { try? fileSystem.removeItemIfExists(at: stagingURL) }

        do {
            try fileSystem.createDirectory(at: directoryURL)
            try fileSystem.copyItem(at: sourceURL, to: stagingURL)
            let stagedAnimation = try decoder.decode(url: stagingURL)

            if fileSystem.fileExists(at: avatarURL) {
                try fileSystem.replaceItem(at: avatarURL, with: stagingURL)
            } else {
                try fileSystem.moveItem(at: stagingURL, to: avatarURL)
            }
            return stagedAnimation
        } catch let error as AvatarImportError {
            throw error
        } catch {
            throw AvatarImportError.persistenceFailed
        }
    }
}
```

- [ ] **Step 4: Run store and shared-domain tests**

Run:

```bash
swift test --filter 'AvatarDomainTests|CustomAvatarStoreTests'
```

Expected: both test classes pass, including deterministic replacement-failure rollback through the file-system seam.

- [ ] **Step 5: Commit the store worktree**

```bash
git add Sources/AgentMascotApp/Avatar/CustomAvatarStore.swift Tests/AgentMascotTests/CustomAvatarStoreTests.swift
git commit -m "feat: persist custom avatars atomically"
```

Expected: one commit on `codex/custom-avatar-menu-store`. Return its hash and the test output summary to the coordinator.

---

### Task 4: Schedule and render decoded APNG frames

**Execution:** Wave 1 parallel agent C in `/tmp/agentmascot-avatar-playback`.

**Files:**
- Create: `Sources/AgentMascotApp/Avatar/AvatarFrameScheduler.swift`
- Create: `Sources/AgentMascotApp/UI/Mascot/APNGAvatarView.swift`
- Test: `Tests/AgentMascotTests/AvatarFrameSchedulerTests.swift`

**Interfaces:**
- Consumes: `APNGAnimation` and `APNGFrame` from Task 1.
- Produces: `AvatarFrameScheduler.frameIndex(elapsed:animation:)` and `APNGAvatarView.init(animation:)`.
- Constraint: do not edit `VideoMascotWidget.swift`; Task 6 owns renderer integration after Wave 1 merges.

- [ ] **Step 1: Write failing scheduler boundary tests**

Create `Tests/AgentMascotTests/AvatarFrameSchedulerTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the scheduler tests and verify the scheduler is absent**

Run:

```bash
swift test --filter AvatarFrameSchedulerTests
```

Expected: compilation fails with `cannot find 'AvatarFrameScheduler' in scope`.

- [ ] **Step 3: Implement deterministic frame selection**

Create `Sources/AgentMascotApp/Avatar/AvatarFrameScheduler.swift`:

```swift
import Foundation

enum AvatarFrameScheduler {
    static func frameIndex(elapsed: TimeInterval, animation: APNGAnimation) -> Int {
        guard elapsed >= 0 else { return 0 }

        let position = elapsed.truncatingRemainder(dividingBy: animation.totalDuration)
        return animation.frames.firstIndex { position < $0.cumulativeEndTime }
            ?? (animation.frames.count - 1)
    }
}
```

- [ ] **Step 4: Run scheduler tests**

Run:

```bash
swift test --filter AvatarFrameSchedulerTests
```

Expected: `AvatarFrameSchedulerTests` passes.

- [ ] **Step 5: Add the aspect-fit SwiftUI renderer**

Create `Sources/AgentMascotApp/UI/Mascot/APNGAvatarView.swift`:

```swift
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
```

- [ ] **Step 6: Compile the renderer with its scheduler tests**

Run:

```bash
swift test --filter 'AvatarDomainTests|AvatarFrameSchedulerTests'
```

Expected: both test classes pass and `APNGAvatarView.swift` compiles for macOS 15.

- [ ] **Step 7: Commit the playback worktree**

```bash
git add Sources/AgentMascotApp/Avatar/AvatarFrameScheduler.swift Sources/AgentMascotApp/UI/Mascot/APNGAvatarView.swift Tests/AgentMascotTests/AvatarFrameSchedulerTests.swift
git commit -m "feat: render custom APNG avatars"
```

Expected: one commit on `codex/custom-avatar-menu-playback`. Return its hash and the test output summary to the coordinator.

---

### Task 5: Load, choose, and import avatars through the app model

**Execution:** Sequential after Tasks 2–4 merge.

**Files:**
- Create: `Sources/AgentMascotApp/Avatar/AvatarFilePicker.swift`
- Create: `Sources/AgentMascotApp/Avatar/AvatarSelectionCoordinator.swift`
- Modify: `Sources/AgentMascotApp/App/AppModel.swift:4-31`
- Modify: `Sources/AgentMascotApp/AgentMascotApp.swift:42-110`
- Test: `Tests/AgentMascotTests/AvatarSelectionCoordinatorTests.swift`

**Interfaces:**
- Consumes: `ImageIOAPNGDecoder`, `CustomAvatarStore`, `APNGAnimation`, and `AvatarImportError`.
- Produces: `AvatarFilePicking.chooseAPNG()`, `SystemAvatarFilePicker`, `AvatarSelectionCoordinator.start()`, `chooseAndImport()`, and `stop()`.
- Produces on `AppModel`: `customAvatar`, `avatarImportError`, `chooseCustomAvatar`, and `chooseAvatar()`.
- Consumer: Task 6 reads the model state and invokes `chooseAvatar()`.

- [ ] **Step 1: Write failing selection-coordinator tests**

Create `Tests/AgentMascotTests/AvatarSelectionCoordinatorTests.swift`:

```swift
import CoreGraphics
import Foundation
import XCTest
@testable import AgentMascotApp

@MainActor
final class AvatarSelectionCoordinatorTests: XCTestCase {
    func testStartLoadsPersistedAvatarAndInstallsChooseAction() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("saved".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let model = AppModel()
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(directoryURL: root, decoder: IntegrationDecoder()),
            picker: StubPicker(url: nil)
        )

        await coordinator.start()

        XCTAssertEqual(model.customAvatar?.frames.count, 2)
        XCTAssertNil(model.avatarImportError)
        XCTAssertNotNil(model.chooseCustomAvatar)
        coordinator.stop()
        XCTAssertNil(model.chooseCustomAvatar)
    }

    func testChooseImportsAndPublishesValidAvatar() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try sourceFile(named: "chosen.apng", bytes: "chosen")
        defer { try? FileManager.default.removeItem(at: source) }
        let model = AppModel()
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(directoryURL: root, decoder: IntegrationDecoder()),
            picker: StubPicker(url: source)
        )

        await coordinator.chooseAndImport()

        XCTAssertEqual(model.customAvatar?.frames.count, 2)
        XCTAssertNil(model.avatarImportError)
        XCTAssertEqual(
            try Data(contentsOf: root.appendingPathComponent("avatar.apng")),
            Data("chosen".utf8)
        )
    }

    func testFailedChooseKeepsDisplayedAvatarAndPublishesError() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try sourceFile(named: "invalid.apng", bytes: "invalid")
        defer { try? FileManager.default.removeItem(at: source) }
        let model = AppModel()
        model.customAvatar = try testAnimation()
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(
                directoryURL: root,
                decoder: IntegrationDecoder(failingNames: ["invalid.apng"])
            ),
            picker: StubPicker(url: source)
        )

        await coordinator.chooseAndImport()

        XCTAssertEqual(model.customAvatar?.frames.count, 2)
        XCTAssertEqual(
            model.avatarImportError,
            "Choose an animated PNG with at least two frames."
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("avatar.apng").path))
    }

    func testCancelClearsPreviousErrorWithoutChangingAvatar() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let model = AppModel()
        model.customAvatar = try testAnimation()
        model.avatarImportError = "Previous error"
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(directoryURL: root, decoder: IntegrationDecoder()),
            picker: StubPicker(url: nil)
        )

        await coordinator.chooseAndImport()

        XCTAssertEqual(model.customAvatar?.frames.count, 2)
        XCTAssertNil(model.avatarImportError)
    }

    func testCorruptPersistedAvatarFallsBackAndPublishesRecoverableError() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("broken".utf8).write(to: root.appendingPathComponent("avatar.apng"))
        let model = AppModel()
        let coordinator = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(
                directoryURL: root,
                decoder: IntegrationDecoder(failingNames: ["avatar.apng"])
            ),
            picker: StubPicker(url: nil)
        )

        await coordinator.start()

        XCTAssertNil(model.customAvatar)
        XCTAssertEqual(
            model.avatarImportError,
            "Choose an animated PNG with at least two frames."
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("avatar.apng").path))
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func sourceFile(named name: String, bytes: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "-" + name)
        try Data(bytes.utf8).write(to: url)
        return url
    }
}

@MainActor
private struct StubPicker: AvatarFilePicking {
    let url: URL?
    func chooseAPNG() -> URL? { url }
}

private struct IntegrationDecoder: APNGDecoding {
    let failingNames: Set<String>

    init(failingNames: Set<String> = []) {
        self.failingNames = failingNames
    }

    func decode(url: URL) throws -> APNGAnimation {
        if failingNames.contains(where: { url.lastPathComponent.hasSuffix($0) }) {
            throw AvatarImportError.notAnimatedPNG
        }
        return try testAnimation()
    }
}

private func testAnimation() throws -> APNGAnimation {
    let context = CGContext(
        data: nil,
        width: 1,
        height: 1,
        bitsPerComponent: 8,
        bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    let image = context.makeImage()!
    return try APNGAnimation(images: [image, image], durations: [0.1, 0.1])
}
```

- [ ] **Step 2: Run the selection tests and verify the workflow is absent**

Run:

```bash
swift test --filter AvatarSelectionCoordinatorTests
```

Expected: compilation fails because `AvatarSelectionCoordinator`, `AvatarFilePicking`, and the new `AppModel` properties do not exist.

- [ ] **Step 3: Implement the APNG/PNG system file picker**

Create `Sources/AgentMascotApp/Avatar/AvatarFilePicker.swift`:

```swift
import AppKit
import UniformTypeIdentifiers

@MainActor
protocol AvatarFilePicking {
    func chooseAPNG() -> URL?
}

@MainActor
struct SystemAvatarFilePicker: AvatarFilePicking {
    func chooseAPNG() -> URL? {
        let panel = NSOpenPanel()
        let apng = UTType(filenameExtension: "apng", conformingTo: .png)
        panel.allowedContentTypes = [.png] + [apng].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose Avatar"
        panel.message = "Choose one animated PNG for the floating mascot."

        return panel.runModal() == .OK ? panel.url : nil
    }
}
```

- [ ] **Step 4: Add avatar state and the injected choose action to `AppModel`**

In `Sources/AgentMascotApp/App/AppModel.swift`, add these stored properties after `migrationWarning`:

```swift
    var customAvatar: APNGAnimation?
    var avatarImportError: String?
```

Add this ignored action after `openSession`:

```swift
    @ObservationIgnored var chooseCustomAvatar: (() -> Void)?
```

Add this method after `open(session:)`:

```swift
    func chooseAvatar() { chooseCustomAvatar?() }
```

Do not overload `migrationWarning` or `bridgeStatus` with avatar errors; Task 6 renders `avatarImportError` only in the menu-bar avatar control.

- [ ] **Step 5: Implement startup load and import coordination**

Create `Sources/AgentMascotApp/Avatar/AvatarSelectionCoordinator.swift`:

```swift
import Foundation

@MainActor
final class AvatarSelectionCoordinator {
    private let model: AppModel
    private let store: CustomAvatarStore
    private let picker: any AvatarFilePicking

    init(
        model: AppModel,
        store: CustomAvatarStore,
        picker: any AvatarFilePicking
    ) {
        self.model = model
        self.store = store
        self.picker = picker
    }

    func start() async {
        model.chooseCustomAvatar = { [weak self] in
            Task { await self?.chooseAndImport() }
        }

        do {
            model.customAvatar = try await Task.detached(priority: .userInitiated) { [store] in
                try store.load()
            }.value
        } catch {
            model.customAvatar = nil
            model.avatarImportError = Self.message(for: error)
        }
    }

    func chooseAndImport() async {
        model.avatarImportError = nil
        guard let sourceURL = picker.chooseAPNG() else { return }

        do {
            let animation = try await Task.detached(priority: .userInitiated) { [store] in
                try store.importAvatar(from: sourceURL)
            }.value
            model.customAvatar = animation
            model.avatarImportError = nil
        } catch {
            model.avatarImportError = Self.message(for: error)
        }
    }

    func stop() {
        model.chooseCustomAvatar = nil
    }

    private static func message(for error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
```

- [ ] **Step 6: Wire the avatar coordinator into `AppCoordinator` lifecycle**

In `Sources/AgentMascotApp/AgentMascotApp.swift`, add this property beside the existing coordinator-owned services:

```swift
    private let avatarSelection: AvatarSelectionCoordinator
```

Replace `AppCoordinator.init(model:)` with:

```swift
    init(model: AppModel) {
        self.model = model
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Agent Mascot")
        avatarSelection = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(
                directoryURL: support,
                decoder: ImageIOAPNGDecoder()
            ),
            picker: SystemAvatarFilePicker()
        )
    }
```

In `start(demoState:)`, insert the avatar load after the existing idempotence guard and before the demo-state branch:

```swift
        await avatarSelection.start()
```

In `stop()`, insert this call before clearing the existing model actions:

```swift
        avatarSelection.stop()
```

- [ ] **Step 7: Run selection, storage, and decoder tests**

Run:

```bash
swift test --filter 'ImageIOAPNGDecoderTests|CustomAvatarStoreTests|AvatarSelectionCoordinatorTests'
```

Expected: all three test classes pass, including off-main load/import and failure preservation.

- [ ] **Step 8: Commit the selection workflow**

```bash
git add Sources/AgentMascotApp/Avatar/AvatarFilePicker.swift Sources/AgentMascotApp/Avatar/AvatarSelectionCoordinator.swift Sources/AgentMascotApp/App/AppModel.swift Sources/AgentMascotApp/AgentMascotApp.swift Tests/AgentMascotTests/AvatarSelectionCoordinatorTests.swift
git commit -m "feat: load and choose custom avatars"
```

Expected: one commit containing the selection workflow, lifecycle wiring, model state, and focused tests.

---

### Task 6: Expose the menu action and switch only the floating renderer

**Execution:** Sequential after Task 5.

**Files:**
- Create: `Sources/AgentMascotApp/UI/Avatar/AvatarMenuControl.swift`
- Modify: `Sources/AgentMascotApp/UI/RootView.swift:4-53`
- Modify: `Sources/AgentMascotApp/AgentMascotApp.swift:4-11`
- Modify: `Sources/AgentMascotApp/UI/Mascot/VideoMascotWidget.swift:26-91`
- Test: `Tests/AgentMascotTests/AvatarPresentationTests.swift`

**Interfaces:**
- Consumes: `AppModel.customAvatar`, `avatarImportError`, `chooseAvatar()`, and `APNGAvatarView`.
- Produces: `RootViewPresentation.menuBar`, `.settings`, `showsAvatarControls`, and `AvatarMenuControl`.
- Invariant: `StaticMascotView`, the menu-bar icon, floating panel dimensions, and status capsule behavior remain unchanged.

- [ ] **Step 1: Write the failing presentation-context tests**

Create `Tests/AgentMascotTests/AvatarPresentationTests.swift`:

```swift
import XCTest
@testable import AgentMascotApp

final class AvatarPresentationTests: XCTestCase {
    func testAvatarControlsAreMenuBarOnly() {
        XCTAssertTrue(RootViewPresentation.menuBar.showsAvatarControls)
        XCTAssertFalse(RootViewPresentation.settings.showsAvatarControls)
    }

    @MainActor
    func testChooseAvatarForwardsToInjectedAction() {
        let model = AppModel()
        var calls = 0
        model.chooseCustomAvatar = { calls += 1 }

        model.chooseAvatar()

        XCTAssertEqual(calls, 1)
    }
}
```

- [ ] **Step 2: Run the presentation tests and verify the context is absent**

Run:

```bash
swift test --filter AvatarPresentationTests
```

Expected: compilation fails with `cannot find 'RootViewPresentation' in scope`.

- [ ] **Step 3: Create the menu-bar avatar control**

Create `Sources/AgentMascotApp/UI/Avatar/AvatarMenuControl.swift`:

```swift
import SwiftUI

struct AvatarMenuControl: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button("Change Avatar…") {
                model.chooseAvatar()
            }
            .accessibilityIdentifier("change-avatar")

            if let error = model.avatarImportError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Avatar error: \(error)")
                    .accessibilityIdentifier("avatar-import-error")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```

- [ ] **Step 4: Add an explicit presentation context to `RootView`**

At the top of `Sources/AgentMascotApp/UI/RootView.swift`, after the imports, add:

```swift
enum RootViewPresentation: Sendable, Equatable {
    case menuBar
    case settings

    var showsAvatarControls: Bool { self == .menuBar }
}
```

Add this property beside `model` in `RootView`:

```swift
    let presentation: RootViewPresentation
```

Inside the root `VStack`, immediately after the existing migration-warning block, add:

```swift
            if presentation.showsAvatarControls {
                AvatarMenuControl(model: model)
            }
```

Do not pass `customAvatar` into `StaticMascotView`; its state-aware bundled assets must remain unchanged.

- [ ] **Step 5: Pass the correct context from each scene**

In `Sources/AgentMascotApp/AgentMascotApp.swift`, replace the two `RootView` calls in `AgentMascotApplication.body` with:

```swift
        MenuBarExtra("Agent Mascot", systemImage: appDelegate.model.aggregateState == .needsInput ? "questionmark.circle.fill" : "sparkles") {
            RootView(model: appDelegate.model, presentation: .menuBar)
        }.menuBarExtraStyle(.window)
        Settings {
            RootView(model: appDelegate.model, presentation: .settings)
        }
```

- [ ] **Step 6: Switch only the floating animation surface**

In `Sources/AgentMascotApp/UI/Mascot/VideoMascotWidget.swift`, replace the existing `AnimatedMascotView()` call with:

```swift
            Group {
                if let customAvatar = model.customAvatar {
                    APNGAvatarView(animation: customAvatar)
                } else {
                    BundledMascotAnimationView()
                }
            }
```

Keep the existing `.frame(width: 360, height: 203)` modifier on that `Group` and leave `statusCapsule` unchanged.

Rename the private bundled renderer declaration without changing its frame-loading or 12 FPS behavior:

```swift
private struct BundledMascotAnimationView: View {
```

No other code in `VideoMascotWidget.swift` changes.

- [ ] **Step 7: Run focused UI-contract and playback tests**

Run:

```bash
swift test --filter 'AvatarFrameSchedulerTests|AvatarSelectionCoordinatorTests|AvatarPresentationTests|SessionFilteringTests|AgentHarnessNavigatorTests'
```

Expected: all five test classes pass; existing session-filtering and exact-navigation behavior remains green.

- [ ] **Step 8: Commit menu and floating-surface integration**

```bash
git add Sources/AgentMascotApp/UI/Avatar/AvatarMenuControl.swift Sources/AgentMascotApp/UI/RootView.swift Sources/AgentMascotApp/AgentMascotApp.swift Sources/AgentMascotApp/UI/Mascot/VideoMascotWidget.swift Tests/AgentMascotTests/AvatarPresentationTests.swift
git commit -m "feat: add menu bar avatar selection"
```

Expected: one commit that exposes the action only in the menu-bar window and changes only the floating animation renderer.

---

### Task 7: Document and verify the complete feature

**Execution:** Final sequential gate after Task 6.

**Files:**
- Modify: `README.md:3-19`
- Modify: `docs/manual-acceptance.md:1-13`

**Interfaces:**
- Consumes: the complete feature and all automated tests.
- Produces: user-facing behavior documentation, updated manual acceptance, a verified release build, and a pushed feature branch.

- [ ] **Step 1: Document the menu action and persistence contract**

In `README.md`, replace the opening description with:

```markdown
Native macOS menu-bar mascot for Claude Code 2.x and Codex CLI 0.144.x. Agent Mascot binds an authenticated bridge only to `127.0.0.1:7824`, owns a loopback Codex app-server on a dynamically selected port, discovers active Codex Desktop/CLI threads and subagents through the app-server protocol, and supports a persistent custom APNG for the floating mascot.
```

Replace the existing packaging sentence at line 19 with:

```markdown
Only the rendered PNG frames, status SVGs, and hook scripts for the built-in experience are included in the app. The source APNG and MOV files are intentionally excluded so release artifacts never need to be slimmed after signing. A user-selected avatar is copied at runtime to `~/Library/Application Support/Agent Mascot/avatar.apng`; it is never added to the signed app bundle.
```

Insert this section after the demo command and before “Integrations and security”:

```markdown
## Custom floating avatar

Open the Agent Mascot menu-bar window and choose **Change Avatar…** to select one animated PNG (`.apng` or `.png`). Agent Mascot validates and copies it into Application Support, updates the floating mascot immediately, and keeps it across restarts even if the original file moves. Choosing another valid APNG replaces it. The menu/settings mascot, menu-bar icon, status capsule, and floating window size do not change.
```

- [ ] **Step 2: Add complete manual avatar acceptance coverage**

Replace `docs/manual-acceptance.md` with:

```markdown
# Manual acceptance

1. Build/package, launch `build/Agent Mascot.app`, and verify `/healthz` only on `127.0.0.1:7824`.
2. Opt in to Claude hooks in Settings, restart a disposable Claude session, trigger `AskUserQuestion`, select an answer, and verify the session continues.
3. Start one main Codex session with subagents and verify the floating capsule says `Working · 1`; subagents must not appear in the session list or notifications.
4. Run two main working sessions with duplicate titles. Open the `Working · N` capsule and verify each distinct row shows its provider, sorts newest-first, supports keyboard activation/Escape, and disappears when no main session remains.
5. Select a Codex and a Claude Code row and verify each opens that provider's exact task. Temporarily remove a handler and verify the popover remains open with an inline error.
6. Open the menu-bar window and verify **Change Avatar…** is present. Open Settings and verify no avatar action or avatar error appears there.
7. Choose a valid APNG and verify the floating avatar changes immediately, retains transparency, aspect-fits without cropping, loops continuously, and leaves the static menu/settings mascot and menu-bar icon unchanged.
8. Move or delete the original APNG, restart Agent Mascot, and verify the custom floating avatar still loads from `~/Library/Application Support/Agent Mascot/avatar.apng`.
9. Choose a second valid APNG and verify it replaces the first. Cancel a later picker and verify the displayed and persisted avatar do not change.
10. Try a static PNG, corrupt file, and APNG over a configured resource limit. Verify the menu-bar window shows an accessible inline error and the current custom avatar continues playing.
11. Temporarily corrupt the saved `avatar.apng`, relaunch, and verify the bundled floating animation appears with a recoverable menu-bar error; selecting a valid APNG repairs the state without a restore control.
12. Drag the mascot background and verify it moves; the status capsule, working-session popover, and provider navigation must remain clickable and correct with a custom avatar.
13. Connect a TUI with the displayed `codex --remote ws://127.0.0.1:<port>` command; trigger an approval/input request and verify exact routing.
14. Migrate a disposable legacy installation containing managed Claude and/or Codex entries plus unrelated configuration. Verify the token is adopted, only marked entries change, legacy scripts are removed after success, and a failed migration leaves legacy scripts intact with a warning.
15. Quit with a request pending: it must fall back/decline and the owned app-server must terminate. Deny notifications and occupy ports; diagnostics must report recovery information.

Automated app-server initialization: `swiftc -parse-as-library scripts/e2e/CodexInitializeProbe.swift -o .build/debug/CodexInitializeProbe && scripts/e2e/verify-codex-app-server.sh`.
```

- [ ] **Step 3: Run all automated tests**

Run:

```bash
swift test
```

Expected: the entire `AgentMascotTests` suite passes, including all six new avatar test classes and all existing bridge, migration, session, navigation, and resource tests.

- [ ] **Step 4: Verify the release build**

Run:

```bash
swift build -c release
```

Expected: `Build complete!` with no Swift 6 concurrency errors.

- [ ] **Step 5: Package and verify the app signature**

Run:

```bash
./scripts/build-app.sh
codesign --verify --deep --strict "build/Agent Mascot.app"
```

Expected: the app build finishes, and `codesign` exits with status 0 and no verification error.

- [ ] **Step 6: Verify source animations are still excluded from the app bundle**

Run:

```bash
find "build/Agent Mascot.app" -type f \( -name '*.apng' -o -name '*.mov' \) -print
```

Expected: no output. The runtime file belongs in the user's Application Support directory, not in the signed bundle.

- [ ] **Step 7: Perform the avatar-specific manual acceptance subset**

Prepare deterministic manual inputs:

```bash
mkfile 1k /tmp/agentmascot-corrupt.apng
mkfile 26m /tmp/agentmascot-oversized.apng
```

Use these files while executing steps 6–12 from `docs/manual-acceptance.md` against the newly packaged app:

- Valid APNG: `Sources/AgentMascotApp/Resources/Mascots/haland.apng`
- Static PNG: `Sources/AgentMascotApp/Resources/Mascots/HalandFramesV2/frame-001.png`
- Corrupt APNG: `/tmp/agentmascot-corrupt.apng`
- Oversized APNG: `/tmp/agentmascot-oversized.apng`

For manual step 11, quit Agent Mascot after a valid import, corrupt only the copied test avatar, and relaunch:

```bash
mkfile 1k "$HOME/Library/Application Support/Agent Mascot/avatar.apng"
```

Complete the repair portion by choosing the checked-in valid APNG again.

Expected: menu-only selection, immediate playback, persistence, replacement, cancellation, invalid-input preservation, launch fallback, aspect-fit rendering, and existing floating controls all match the design spec.

- [ ] **Step 8: Commit documentation after verification**

```bash
git add README.md docs/manual-acceptance.md
git commit -m "docs: document custom avatar workflow"
```

Expected: one documentation commit after automated and packaged-app verification succeeds.

- [ ] **Step 9: Remove integrated Wave 1 worktrees and push the feature branch**

```bash
git worktree remove /tmp/agentmascot-avatar-decoder
git worktree remove /tmp/agentmascot-avatar-store
git worktree remove /tmp/agentmascot-avatar-playback
git push origin codex/custom-avatar-menu
```

Expected: the three temporary worktrees are removed and GitHub has the verified implementation commits on `codex/custom-avatar-menu`.

---

## Completion Audit

Before declaring implementation complete, verify each requirement against authoritative evidence:

| Requirement | Evidence |
|---|---|
| Menu-bar-only **Change Avatar…** | `AvatarPresentationTests` plus manual acceptance steps 6 and 10 |
| One APNG/PNG selected locally | `SystemAvatarFilePicker` configuration plus decoder rejection tests |
| Actual animated-PNG validation | `ImageIOAPNGDecoderTests` corrupt/static tests |
| Persistent default independent of source | `CustomAvatarStoreTests.testImportCopiesBytesAndDoesNotDependOnOriginal` plus manual step 8 |
| Atomic replacement and rollback | Store replacement, staged-failure, and failing-file-system tests |
| Only floating mascot changes | `VideoMascotWidget` renderer branch plus manual steps 7 and 12 |
| Aspect-fit, transparency, continuous looping | `APNGAvatarView`, scheduler tests, and manual step 7 |
| Resource limits and timing policy | Decoder limit/delay tests |
| No restore button | `AvatarMenuControl` code inspection plus manual step 11 |
| Launch fallback for corrupt saved avatar | `AvatarSelectionCoordinatorTests` plus manual step 11 |
| Existing controls and integrations preserved | full `swift test`, release build, packaged app, and manual steps 12–15 |
| Source APNG/MOV remain excluded | bundle `find` command returns no output |

All rows require positive evidence. A missing manual check, failing command, unreviewed parallel-agent result, or unexpected bundle artifact means the implementation remains incomplete.
