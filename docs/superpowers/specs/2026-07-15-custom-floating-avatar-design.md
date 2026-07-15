# Custom Floating Avatar Design

**Date:** 2026-07-15

**Status:** Approved

## Purpose

Let a user choose one animated PNG from the Agent Mascot menu-bar window and make it the persistent avatar for the floating mascot. The custom avatar updates immediately, survives app restarts, and remains available if the original file is moved or deleted.

## Scope

The feature changes only the 360×203 animated image inside the floating mascot panel. It does not change:

- The menu-bar icon.
- The static, state-aware mascot displayed inside the menu-bar window or Settings.
- The floating status capsule, session picker, panel size, panel placement, or drag behavior.
- Agent state aggregation, notifications, provider navigation, hooks, or bridge behavior.

The menu-bar window gains one action named **Change Avatar…**. Settings does not show the action. There is no restore or remove action. Before a user chooses an avatar, the bundled frame animation remains the default. Afterward, the user can replace the custom avatar by choosing another valid APNG.

## Accepted file and presentation behavior

- The picker accepts one `.apng` or `.png` file. Content validation, rather than the filename extension, must prove that the file is an animated PNG.
- A valid avatar contains at least two decodable frames.
- The custom animation loops continuously even when its APNG metadata specifies a finite loop count, matching the existing mascot behavior.
- The renderer honors each frame's APNG timing metadata. It prefers unclamped delay, falls back to standard delay, then falls back to 1/12 second. Delays shorter than 1/60 second are clamped to 1/60 second.
- The avatar uses aspect-fit inside the existing 360×203 image area. It preserves the entire image, aspect ratio, alpha, and transparent surrounding space. It is never cropped, stretched, or allowed to resize the floating panel.

## Architecture

The feature uses macOS ImageIO and existing SwiftUI/AppKit facilities. It adds no third-party dependency.

### Avatar domain contract

`APNGAnimation` is an immutable, sendable value containing ordered `APNGFrame` values and the animation's total duration. Each frame holds a decoded `CGImage`, its duration, and its cumulative end time. Construction rejects empty frames or non-positive total duration.

`APNGDecoding` defines `decode(url:) throws -> APNGAnimation`. The protocol keeps storage and integration tests independent from ImageIO.

`AvatarImportError` defines stable, user-facing failure categories for unreadable files, non-animated PNGs, resource-limit violations, malformed frames, and persistence failures.

### Native APNG decoder

`ImageIOAPNGDecoder` uses `CGImageSourceCreateWithURL`, `CGImageSourceGetCount`, `CGImageSourceCopyPropertiesAtIndex`, and `CGImageSourceCreateImageAtIndex`. It reads `kCGImagePropertyAPNGUnclampedDelayTime` and `kCGImagePropertyAPNGDelayTime` from each frame's `kCGImagePropertyPNGDictionary`.

The decoder enforces all of these limits before returning an animation:

- Source file size: at most 25 MB (26,214,400 bytes).
- Frame count: 2 through 300 inclusive.
- Frame dimensions: each width and height is at most 4096 pixels and greater than zero.
- Estimated decoded storage: at most 128 MiB (134,217,728 bytes), calculated as the sum of `width × height × 4` for all decoded frames with overflow-safe arithmetic.

The checked-in source APNG is 22 MB, 640×360, and 97 frames, so it fits within these limits.

### Persistent custom-avatar store

`CustomAvatarStore` owns a deterministic destination:

`~/Library/Application Support/Agent Mascot/avatar.apng`

`load()` returns `nil` when no custom file exists and otherwise decodes the saved APNG.

`importAvatar(from:)` follows a validate-stage-replace sequence:

1. Decode and validate the user-selected source without changing current state.
2. Create the Agent Mascot Application Support directory if needed.
3. Copy the source to a uniquely named staging file in that directory.
4. Decode the staging file to prove that the persisted bytes remain valid.
5. Atomically replace `avatar.apng` with the staging file.
6. Return the decoded staged animation.

If any step fails, the store removes only its staging file. It preserves the previous `avatar.apng` and returns an error. Copying the bytes into Application Support means the app never depends on a security-scoped bookmark or the original file remaining in place.

### Model and lifecycle integration

`AppModel` publishes:

- `customAvatar: APNGAnimation?`
- `avatarImportError: String?`
- An injected `chooseCustomAvatar` action used by the menu-bar view.

`AppCoordinator` creates the decoder and store from the existing Agent Mascot Application Support URL. During startup it loads the persisted avatar. A successful load sets `model.customAvatar`; a missing file leaves it `nil`; a decode failure leaves it `nil` and sets a recoverable warning.

The choose action presents the file picker on the main actor, imports the selected file away from the main actor, and then publishes the success or error on the main actor. Canceling the picker is a no-op and does not show an error. Starting a new selection clears the old error; a successful import clears it again.

### Menu-bar-only control

`RootView` receives a presentation context distinguishing `.menuBar` from `.settings`. `AgentMascotApplication` passes `.menuBar` to the `MenuBarExtra` instance and `.settings` to the Settings scene.

An `AvatarMenuControl` is rendered only for `.menuBar`. It contains **Change Avatar…** and an accessible inline error message when `avatarImportError` is non-nil. There is no restore control, custom-avatar preview, or avatar action in Settings.

The picker uses `NSOpenPanel`, disallows directories and multiple selection, and allows `UTType.png` plus the dynamic type for the `apng` extension. The decoder remains the authority on whether the chosen bytes are animated PNG data.

### Floating renderer

The existing bundled animation is retained as `BundledMascotAnimationView`. `VideoMascotWidget` chooses between:

- `APNGAvatarView(animation:)` when `model.customAvatar` is non-nil.
- `BundledMascotAnimationView` otherwise.

`APNGAvatarView` uses `TimelineView(.animation)` and a pure `AvatarFrameScheduler` to map elapsed time modulo total duration to the first frame whose cumulative end time exceeds that position. The SwiftUI image is resizable and scaled to fit in the unchanged 360×203 frame.

The status capsule stays layered over the avatar exactly as it is today, including the working-session popover and accessibility label.

## Error behavior

- Canceling the picker changes nothing.
- A static PNG, corrupt file, unreadable file, malformed frame, or resource-limit violation leaves the current displayed and persisted avatars unchanged.
- A staging, copy, or replacement failure leaves the previous persisted avatar unchanged.
- Import failures appear beside **Change Avatar…** in the menu-bar window and are accessible to VoiceOver.
- A corrupt persisted avatar at launch falls back to the bundled floating animation and shows a recoverable menu-bar warning. The file is not automatically deleted; choosing another valid APNG repairs the state.
- Settings never surfaces avatar errors because avatar controls are menu-bar-only.

## Testing strategy

### Unit tests

- Domain tests cover animation invariants and stable error descriptions.
- Decoder tests use the checked-in `haland.apng` as a known valid APNG and generated/static/corrupt inputs for rejection paths. They assert frame count, dimensions, timing preference and clamping, size limit, frame-count limit, dimension limit, and decoded-budget limit.
- Store tests inject a fake decoder and temporary Application Support directory. They cover no-file load, successful import, source-file independence, replacement, validation failure rollback, staged-validation rollback, and destination replacement failure.
- Scheduler tests use synthetic frames and fixed elapsed times to cover boundaries, variable durations, wraparound, and continuous looping.
- Model/integration tests verify success and error publication without invoking a real panel.
- Presentation-context tests verify that avatar controls are enabled for `.menuBar` and disabled for `.settings`.

### Repository verification

- Run avatar-focused tests first, then the complete `swift test` suite.
- Run `swift build -c release` to catch Swift 6 concurrency and release-only integration issues.
- Run `./scripts/build-app.sh` and verify that the app still packages without bundling the source APNG or MOV assets excluded by `Package.swift`.

### Manual acceptance

1. Launch the packaged app with no saved `avatar.apng`; confirm the bundled floating animation is unchanged.
2. Open the menu-bar window; confirm **Change Avatar…** is present and Settings has no avatar action.
3. Choose a valid APNG; confirm the floating avatar changes immediately, retains transparency, aspect-fits without cropping, loops, and leaves the static menu/settings mascot unchanged.
4. Move or delete the original selected file; restart the app and confirm the custom avatar persists.
5. Select a second valid APNG and confirm it atomically replaces the first.
6. Cancel the picker and confirm nothing changes.
7. Try a static PNG, corrupt file, and oversized APNG; confirm an accessible inline error appears and the existing custom avatar continues playing.
8. Confirm the status capsule, working-session popover, drag behavior, panel dimensions, and session navigation still work.

## Parallel implementation boundaries

After a small sequential domain-contract task, three implementation domains can run concurrently without editing the same files:

1. ImageIO decoding and decoder tests.
2. Atomic persistence and store tests.
3. Frame scheduling, SwiftUI playback, and scheduler tests.

Application/model/menu integration follows after those domains merge because it consumes all three interfaces. Full-suite, packaging, and manual verification form the final sequential gate.

## Explicitly excluded

- Restore, remove, or reset-to-built-in controls.
- Choosing folders or numbered PNG sequences.
- GIF, video, SVG, JPEG, HEIC, or other avatar formats.
- State-specific custom avatars.
- Customizing the menu-bar icon or static menu/settings mascot.
- Cropping, zooming, editing, previewing, or resizing the selected avatar.
- Cloud sync, multiple saved avatars, galleries, or recent-avatar history.
