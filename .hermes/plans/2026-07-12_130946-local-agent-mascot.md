# Local Coding-Agent Mascot Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Build a native macOS Swift application that discovers and monitors concurrent Claude Code and Codex sessions, shows a mascot in Idle/Working/Needs Input states, sends local notifications, renders agent questions and choices, and returns the selected answer to the blocked agent.

**Architecture:** Create a Swift Package Manager macOS app in the currently empty `morphling/` workspace. A localhost-only HTTP bridge receives Claude Code hooks; a Codex app-server client consumes Codex JSON-RPC events and responds to approval/input requests for Codex sessions connected through `codex --remote`. Normalize both integrations into one actor-backed session store consumed by SwiftUI, notifications, and a small mascot window. Keep adapters protocol-based so Hermes and other agents can be added later without changing the UI or state machine.

**Tech Stack:** Swift 6.3, SwiftUI, AppKit, Observation, UserNotifications, Network.framework, Foundation `Process`, XCTest, Claude Code HTTP hooks, Codex app-server WebSocket/JSON-RPC.

---

## Scope and verified constraints

- Workspace: `/Users/shobhit/Documents/projects/workview-os/morphling` is empty, so this is a new standalone app rather than a change to `supercmd-swift`.
- Installed tools at planning time: Claude Code `2.1.207`, Codex CLI `0.133.0`, Swift `6.3.2`, Xcode `26.5`.
- Claude Code provides lifecycle hooks including `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `Notification`, `Stop`, `SessionEnd`, and blocking `PermissionRequest` HTTP hooks. `AskUserQuestion` payloads can be held by the HTTP request while the user answers in Morphling.
- Codex provides lifecycle hooks, but the deep bidirectional integration for approvals and streamed events is Codex app-server. It supports localhost WebSocket transport and clients connect using `codex --remote ws://127.0.0.1:<port>`.
- Honest MVP limitation: no macOS app can safely inject answers into arbitrary already-running terminal TTYs. Morphling can discover such sessions and show status, but interactive Codex responses require the Codex TUI to be connected to Morphling's managed app-server. Claude sessions must have loaded Morphling's hooks at session start.
- “Agent started running” means transition into `working`, not merely process launch. Session launch itself is represented by `idle` plus a “session connected” event.
- Static mascot images are used initially: one each for `idle`, `working`, and `needsInput`. The view must hide the asset implementation behind a renderer so MP4/Lottie/Rive can replace it later.
- The localhost endpoints must bind only to `127.0.0.1`, reject oversized/malformed bodies, and use an installation-specific bearer token. Do not expose an unauthenticated listener on the LAN.
- Existing reference implementation worth consulting (do not couple to it): `/Users/shobhit/Documents/projects/workview-os/dynamic/Extensions/agents-status/` already demonstrates Claude/Codex state mapping, hook configuration merging, multi-session tracking, process discovery, and Claude `AskUserQuestion` handling.

## State model

```swift
enum AgentKind: String, Codable, Sendable {
    case claudeCode
    case codex
}

enum AgentSessionState: String, Codable, Sendable {
    case idle
    case working
    case needsInput
    case ended
    case error
}

struct AgentChoice: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let label: String
    let description: String?
    let value: String
}

struct AgentQuestion: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let prompt: String
    let choices: [AgentChoice]
    let allowsFreeText: Bool
    let isMultiSelect: Bool
}

struct AgentSession: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let agent: AgentKind
    var state: AgentSessionState
    var cwd: String
    var title: String
    var pid: Int32?
    var questions: [AgentQuestion]
    var updatedAt: Date
}
```

State priority for the mascot and menu-bar badge is `needsInput > error > working > idle`. The session list retains every live session independently.

## Event contract

Claude hook scripts POST to `http://127.0.0.1:7824/v1/events`:

```json
{
  "version": 1,
  "eventId": "uuid",
  "agent": "claudeCode",
  "sessionId": "claude-session-id",
  "event": "userPromptSubmitted",
  "cwd": "/path/to/repo",
  "pid": 1234,
  "title": "Implement login",
  "occurredAt": "2026-07-12T07:30:00Z"
}
```

Blocking Claude questions POST to `/v1/claude/permission-request`. The request remains open until an answer, cancellation, or timeout. Morphling returns Claude's documented `hookSpecificOutput.permissionDecision` response. Ordinary permission requests that are not `AskUserQuestion` must be passed through without silently granting them.

All event requests include `Authorization: Bearer <installation-token>`. The token is generated on first launch, stored in the user's Application Support directory with owner-only permissions, and embedded into the hook command environment rather than logged.

---

### Task 1: Bootstrap the macOS app and test targets

**Objective:** Create a buildable SwiftUI menu-bar application with a test target and no third-party dependencies.

**Files:**
- Create: `Package.swift`
- Create: `Sources/MorphlingApp/MorphlingApp.swift`
- Create: `Sources/MorphlingApp/App/AppDelegate.swift`
- Create: `Sources/MorphlingApp/UI/RootView.swift`
- Create: `Tests/MorphlingTests/SmokeTests.swift`
- Create: `.gitignore`

**Step 1: Write the failing smoke test**

Add `SmokeTests.swift` that imports `@testable import MorphlingApp`, constructs the initial app model, and asserts it has no sessions and reports `.idle`.

**Step 2: Run the test to verify RED**

Run: `swift test --filter SmokeTests`
Expected: FAIL because `MorphlingApp` and `AppModel` do not exist.

**Step 3: Add the minimal package and app shell**

Use a Swift tools 6.2 package with a macOS 15 executable target named `MorphlingApp`, processed resources, and an XCTest target. Implement `@main struct MorphlingApp`, an `NSApplicationDelegate`, an empty `RootView`, and a minimal observable `AppModel`.

**Step 4: Verify GREEN and launchability**

Run: `swift test --filter SmokeTests`
Expected: PASS.

Run: `swift build`
Expected: `Build complete!` with no warnings introduced by the project.

**Step 5: Commit**

```bash
git add Package.swift Sources Tests .gitignore
git commit -m "feat: bootstrap Morphling macOS app"
```

---

### Task 2: Define normalized agent domain models

**Objective:** Establish provider-neutral session, question, choice, and event types.

**Files:**
- Create: `Sources/MorphlingApp/Domain/AgentModels.swift`
- Create: `Sources/MorphlingApp/Domain/AgentEvent.swift`
- Create: `Sources/MorphlingApp/Domain/AgentAdapter.swift`
- Create: `Tests/MorphlingTests/AgentModelsTests.swift`

**Step 1: Write failing model tests**

Test Codable round trips for all three visible states, a single-select question, and an event carrying agent/session/cwd/pid metadata. Test that aggregate state precedence is `needsInput`, then `error`, then `working`, then `idle`.

**Step 2: Verify RED**

Run: `swift test --filter AgentModelsTests`
Expected: FAIL because the domain types do not exist.

**Step 3: Implement the complete normalized model**

Add the structures shown in “State model,” plus:

```swift
enum AgentEventKind: String, Codable, Sendable {
    case sessionStarted, workStarted, workProgressed
    case inputRequested, workStopped, sessionEnded, failed
}

struct AgentEvent: Identifiable, Codable, Equatable, Sendable {
    let version: Int
    let id: UUID
    let agent: AgentKind
    let sessionID: String
    let kind: AgentEventKind
    let cwd: String?
    let pid: Int32?
    let title: String?
    let question: AgentQuestion?
    let occurredAt: Date
}

protocol AgentAdapter: Sendable {
    func start() async throws
    func stop() async
}
```

Add a pure `aggregateState(for:)` function. Keep provider payload types out of this module.

**Step 4: Verify GREEN**

Run: `swift test --filter AgentModelsTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/MorphlingApp/Domain Tests/MorphlingTests/AgentModelsTests.swift
git commit -m "feat: define normalized agent session model"
```

---

### Task 3: Implement the actor-backed session state machine

**Objective:** Reliably reduce out-of-order, duplicate, and concurrent provider events into live sessions.

**Files:**
- Create: `Sources/MorphlingApp/Domain/AgentSessionStore.swift`
- Create: `Tests/MorphlingTests/AgentSessionStoreTests.swift`

**Step 1: Write one failing test per transition**

Cover these vertical slices separately:

1. `sessionStarted` creates an idle session.
2. `workStarted` changes only the matching session to working.
3. `inputRequested` stores the question and changes state to needs input.
4. Answering the last question returns that session to working.
5. `workStopped` changes the session to idle and clears stale questions.
6. `sessionEnded` removes the session.
7. Duplicate `eventId` is ignored.
8. An older `occurredAt` event cannot roll back a newer state.
9. Two providers with the same raw session ID remain distinct by `(agent, sessionID)`.

**Step 2: Run each test and confirm RED before its implementation**

Run: `swift test --filter AgentSessionStoreTests/<test-name>`
Expected: each new test fails for the missing behavior, not compilation mistakes.

**Step 3: Implement minimal actor behavior per test**

Use `actor AgentSessionStore`; publish immutable snapshots through `AsyncStream<[AgentSession]>`. Bound the deduplication cache and prune IDs after a reasonable window to avoid unlimited growth.

**Step 4: Verify GREEN after every slice**

Run the focused test, then `swift test --filter AgentSessionStoreTests`.
Expected: PASS after each vertical slice.

**Step 5: Commit**

```bash
git add Sources/MorphlingApp/Domain/AgentSessionStore.swift Tests/MorphlingTests/AgentSessionStoreTests.swift
git commit -m "feat: add concurrent agent session state machine"
```

---

### Task 4: Build a secure localhost HTTP bridge

**Objective:** Receive authenticated Claude events and hold blocking question requests without blocking the UI actor.

**Files:**
- Create: `Sources/MorphlingApp/Bridge/LocalHTTPServer.swift`
- Create: `Sources/MorphlingApp/Bridge/HTTPRequestParser.swift`
- Create: `Sources/MorphlingApp/Bridge/BridgeRouter.swift`
- Create: `Sources/MorphlingApp/Bridge/InstallationTokenStore.swift`
- Create: `Tests/MorphlingTests/HTTPRequestParserTests.swift`
- Create: `Tests/MorphlingTests/BridgeRouterTests.swift`
- Create: `Tests/MorphlingTests/LocalHTTPServerIntegrationTests.swift`

**Step 1: Test HTTP parsing and limits first**

Write focused tests for a valid JSON POST, bearer-token parsing, malformed request lines, unsupported methods, missing/wrong auth, content length over 256 KiB, and incomplete bodies.

**Step 2: Verify RED**

Run: `swift test --filter HTTPRequestParserTests`
Expected: FAIL because parser types are absent.

**Step 3: Implement the parser and response writer**

Use Network.framework `NWListener` bound to host `127.0.0.1`, default port `7824`. Support only the required HTTP/1.1 subset, always close connections after a response, and never log authorization headers or full prompts.

**Step 4: Add router tests and implementation**

Routes:

- `GET /healthz` → `200 {"ok":true}` without exposing session data.
- `POST /v1/events` → decode, normalize, enqueue, return `202`.
- `POST /v1/claude/permission-request` → delegate to the Claude adapter's pending-request registry.
- Unknown route → `404`; wrong method → `405`; wrong token → `401`.

**Step 5: Add real socket integration tests**

Start on an ephemeral loopback port, send requests with `URLSession`, and assert actual status/body. Confirm a non-loopback bind is not configurable through user input.

**Step 6: Verify GREEN**

Run: `swift test --filter HTTPRequestParserTests`
Run: `swift test --filter BridgeRouterTests`
Run: `swift test --filter LocalHTTPServerIntegrationTests`
Expected: PASS.

**Step 7: Commit**

```bash
git add Sources/MorphlingApp/Bridge Tests/MorphlingTests/*HTTP* Tests/MorphlingTests/BridgeRouterTests.swift
git commit -m "feat: add authenticated localhost event bridge"
```

---

### Task 5: Parse and map Claude Code lifecycle hooks

**Objective:** Convert Claude hook payloads into normalized state transitions.

**Files:**
- Create: `Sources/MorphlingApp/Integrations/Claude/ClaudeHookPayload.swift`
- Create: `Sources/MorphlingApp/Integrations/Claude/ClaudeEventMapper.swift`
- Create: `Tests/MorphlingTests/ClaudeEventMapperTests.swift`
- Create: `Tests/MorphlingTests/Fixtures/claude-session-start.json`
- Create: `Tests/MorphlingTests/Fixtures/claude-user-prompt-submit.json`
- Create: `Tests/MorphlingTests/Fixtures/claude-notification.json`
- Create: `Tests/MorphlingTests/Fixtures/claude-stop.json`

**Step 1: Write fixture-driven failing tests**

Map:

- `SessionStart` → `sessionStarted` / idle.
- `UserPromptSubmit`, `PreToolUse`, `PostToolUse` → working.
- Permission notifications → needs input only when they genuinely represent a blocking prompt.
- `Stop` → idle.
- `SessionEnd` → ended.
- Interrupted `PostToolUseFailure` → idle; ordinary tool failure remains working.

Use sanitized fixtures captured from installed Claude Code rather than hand-waving field names during implementation.

**Step 2: Verify RED**

Run: `swift test --filter ClaudeEventMapperTests`
Expected: FAIL because the mapper is absent.

**Step 3: Implement strict decoding with tolerant optional metadata**

Require `session_id` and `hook_event_name`; treat cwd/title/pid/transcript as optional. Reject unknown top-level event names with a structured error instead of mutating state.

**Step 4: Verify GREEN**

Run: `swift test --filter ClaudeEventMapperTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/MorphlingApp/Integrations/Claude Tests/MorphlingTests/ClaudeEventMapperTests.swift Tests/MorphlingTests/Fixtures/claude-*.json
git commit -m "feat: map Claude Code hook lifecycle events"
```

---

### Task 6: Install and remove Claude hooks safely

**Objective:** Idempotently merge Morphling hooks into Claude's user settings without destroying user configuration.

**Files:**
- Create: `Sources/MorphlingApp/Integrations/Claude/ClaudeHookInstaller.swift`
- Create: `Sources/MorphlingApp/Integrations/Claude/ClaudeHookConfiguration.swift`
- Create: `Sources/MorphlingApp/Resources/Hooks/morphling-claude-event.sh`
- Create: `Tests/MorphlingTests/ClaudeHookInstallerTests.swift`
- Create: `Tests/MorphlingTests/Fixtures/claude-settings-existing.json`

**Step 1: Write failing merge tests**

Test empty settings, preservation of unrelated keys/hooks, no duplicate installation, removal of only Morphling-marked hooks, malformed JSON refusal, backup creation, and atomic replacement.

**Step 2: Verify RED**

Run: `swift test --filter ClaudeHookInstallerTests`
Expected: FAIL because the installer is absent.

**Step 3: Implement configuration generation**

Install command/HTTP hooks for:

- `SessionStart`
- `UserPromptSubmit`
- `PreToolUse`
- `PostToolUse`
- `PostToolUseFailure`
- `Notification`
- `Stop`
- `SessionEnd`
- blocking `PermissionRequest`

Copy the helper script into `~/Library/Application Support/Morphling/Hooks/` with executable owner-only permissions. Merge into `~/.claude/settings.json`, tag every Morphling entry, preserve unrelated hooks, write a one-time backup, and use an atomic temporary-file rename. The script reads hook JSON from stdin and POSTs to loopback with short timeouts; lifecycle delivery must never block Claude if Morphling is closed.

**Step 4: Add status and uninstall tests**

Expose `installed`, `partiallyInstalled`, and `notInstalled`. Uninstall only entries bearing Morphling's marker and leave the backup untouched.

**Step 5: Verify GREEN**

Run: `swift test --filter ClaudeHookInstallerTests`
Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/MorphlingApp/Integrations/Claude Sources/MorphlingApp/Resources/Hooks Tests/MorphlingTests/ClaudeHookInstallerTests.swift Tests/MorphlingTests/Fixtures/claude-settings-existing.json
git commit -m "feat: manage Claude Code hooks safely"
```

---

### Task 7: Handle Claude `AskUserQuestion` end-to-end

**Objective:** Show all Claude-provided questions/options and return the user's selections through the blocking hook response.

**Files:**
- Create: `Sources/MorphlingApp/Integrations/Claude/ClaudePermissionRequest.swift`
- Create: `Sources/MorphlingApp/Integrations/Claude/ClaudePendingRequestRegistry.swift`
- Create: `Tests/MorphlingTests/ClaudePermissionRequestTests.swift`
- Create: `Tests/MorphlingTests/ClaudePendingRequestRegistryTests.swift`
- Create: `Tests/MorphlingTests/Fixtures/claude-ask-user-question.json`

**Step 1: Write failing parser tests**

Verify multiple questions, every option label/description/value, single-select, multi-select, free-text fallback, malformed options, and non-`AskUserQuestion` permission requests.

**Step 2: Implement parser and normalized questions**

Preserve question order and option order exactly. Generate stable IDs from the permission request plus question index; do not use display labels as IDs.

**Step 3: Write failing async registry tests**

Test register → await → resolve, cancellation, duplicate resolution, timeout, session end, and app shutdown. Assert continuations resume exactly once.

**Step 4: Implement the registry**

Use an actor owning checked continuations and deadlines. Default to Claude's ordinary permission UI for non-question permissions. On Morphling timeout or shutdown, return a non-destructive fallback that does not auto-approve tools.

**Step 5: Verify the exact Claude response contract**

Construct `hookSpecificOutput` for `PermissionRequest` using the current Claude documentation and captured fixture. For multi-question input, return a keyed answer map; for multi-select preserve all selected values; for free text return the entered text.

**Step 6: Verify GREEN**

Run: `swift test --filter ClaudePermissionRequestTests`
Run: `swift test --filter ClaudePendingRequestRegistryTests`
Expected: PASS with no leaked continuations.

**Step 7: Commit**

```bash
git add Sources/MorphlingApp/Integrations/Claude Tests/MorphlingTests/Claude*RequestTests.swift Tests/MorphlingTests/Fixtures/claude-ask-user-question.json
git commit -m "feat: answer Claude questions from Morphling"
```

---

### Task 8: Add Codex hook-based discovery and lifecycle status

**Objective:** Detect ordinary local Codex sessions and normalize lifecycle state even when they are not connected for interactive control.

**Files:**
- Create: `Sources/MorphlingApp/Integrations/Codex/CodexHookPayload.swift`
- Create: `Sources/MorphlingApp/Integrations/Codex/CodexEventMapper.swift`
- Create: `Sources/MorphlingApp/Integrations/Codex/CodexHookInstaller.swift`
- Create: `Sources/MorphlingApp/Resources/Hooks/morphling-codex-event.sh`
- Create: `Tests/MorphlingTests/CodexEventMapperTests.swift`
- Create: `Tests/MorphlingTests/CodexHookInstallerTests.swift`
- Create: `Tests/MorphlingTests/Fixtures/codex-hooks.json`
- Create: `Tests/MorphlingTests/Fixtures/codex-events.jsonl`

**Step 1: Generate version-matched protocol evidence**

Before coding payload types, run the installed Codex schema generator into a temporary directory and inspect the current hook/app-server fields. Do not commit generated output unless it becomes the chosen source of truth.

**Step 2: Write failing mapper tests from sanitized real fixtures**

Cover `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, and `Stop`. A shell command's nonzero exit is a tool outcome, not automatically a dead agent session.

**Step 3: Implement the mapper**

Convert Codex lifecycle events into the same normalized model used by Claude. Preserve `turn_id` internally for ordering and deduplication.

**Step 4: Write failing configuration tests**

Test safe merging into `~/.codex/config.toml` and `~/.codex/hooks.json`, preservation of unrelated config, idempotency, backup, uninstall, and refusal to overwrite malformed input.

**Step 5: Implement hook installation**

Enable the current Codex hook feature only if required by the installed version. Install Morphling-marked commands for the supported lifecycle events and preserve all unrelated hooks. Clearly mark these sessions as `statusOnly` in the domain capabilities.

**Step 6: Verify GREEN**

Run: `swift test --filter CodexEventMapperTests`
Run: `swift test --filter CodexHookInstallerTests`
Expected: PASS.

**Step 7: Commit**

```bash
git add Sources/MorphlingApp/Integrations/Codex Sources/MorphlingApp/Resources/Hooks/morphling-codex-event.sh Tests/MorphlingTests/Codex* Tests/MorphlingTests/Fixtures/codex-*
git commit -m "feat: monitor local Codex lifecycle hooks"
```

---

### Task 9: Implement the Codex app-server JSON-RPC client

**Objective:** Receive streamed Codex state and interactive approval/input requests for remotely connected Codex TUIs.

**Files:**
- Create: `Sources/MorphlingApp/Integrations/Codex/CodexAppServerProcess.swift`
- Create: `Sources/MorphlingApp/Integrations/Codex/CodexWebSocketClient.swift`
- Create: `Sources/MorphlingApp/Integrations/Codex/CodexJSONRPC.swift`
- Create: `Sources/MorphlingApp/Integrations/Codex/CodexAppServerMapper.swift`
- Create: `Tests/MorphlingTests/CodexJSONRPCTests.swift`
- Create: `Tests/MorphlingTests/CodexAppServerMapperTests.swift`
- Create: `Tests/MorphlingTests/CodexAppServerIntegrationTests.swift`
- Create: `Tests/MorphlingTests/Fixtures/codex-app-server-events.jsonl`

**Step 1: Capture current schema and fixture names**

Run:

```bash
codex app-server generate-json-schema --experimental --out /tmp/morphling-codex-schema
```

Inspect exact request/notification names for initialization, thread/turn lifecycle, approvals, user-input requests, cancellation, and errors. Commit sanitized fixture messages, not guessed APIs.

**Step 2: Write failing JSON-RPC codec tests**

Cover requests, responses, errors, notifications, unknown methods, request ID correlation, and malformed frames.

**Step 3: Implement the codec**

Represent envelopes generically and decode method-specific payloads in the mapper. Keep unknown notification handling forward-compatible and logged only at metadata level.

**Step 4: Write failing state-mapping tests**

Map thread creation to idle, turn started/progress to working, input/approval server requests to needs input, turn completion to idle, and thread closure to ended.

**Step 5: Implement managed app-server lifecycle**

Launch:

```bash
codex app-server --listen ws://127.0.0.1:4500
```

Use a configurable free loopback port if 4500 is occupied. Wait for `/readyz`, initialize JSON-RPC, reconnect with bounded exponential backoff, terminate only the child process Morphling owns, and surface version/protocol errors in settings.

**Step 6: Add an actual process integration test**

Start the installed app-server on an ephemeral loopback port, connect, send `initialize`/`initialized`, and assert a valid response. Skip with an explicit reason only when the `codex` executable is absent.

**Step 7: Verify GREEN**

Run: `swift test --filter CodexJSONRPCTests`
Run: `swift test --filter CodexAppServerMapperTests`
Run: `swift test --filter CodexAppServerIntegrationTests`
Expected: PASS against Codex `0.133.0`.

**Step 8: Commit**

```bash
git add Sources/MorphlingApp/Integrations/Codex Tests/MorphlingTests/Codex*AppServer* Tests/MorphlingTests/CodexJSONRPCTests.swift Tests/MorphlingTests/Fixtures/codex-app-server-events.jsonl
git commit -m "feat: connect Morphling to Codex app-server"
```

---

### Task 10: Return Codex choices and approval decisions

**Objective:** Let a user answer Codex requests from Morphling and continue the corresponding turn.

**Files:**
- Create: `Sources/MorphlingApp/Integrations/Codex/CodexPendingRequestRegistry.swift`
- Create: `Sources/MorphlingApp/Integrations/Codex/CodexAnswerEncoder.swift`
- Create: `Tests/MorphlingTests/CodexPendingRequestRegistryTests.swift`
- Create: `Tests/MorphlingTests/CodexAnswerEncoderTests.swift`

**Step 1: Write failing tests from generated schema**

Cover every interactive request supported by the installed protocol: command approval, file-change approval, structured choice input if exposed, free-text input if exposed, cancellation, and unknown request fallback.

**Step 2: Implement normalized request conversion**

Map Codex requests into `AgentQuestion` while retaining the JSON-RPC request ID and exact response schema privately in the adapter.

**Step 3: Implement answer encoding**

Translate selected Morphling choice IDs back to Codex's expected JSON-RPC result. Never infer approval from a timeout; cancellation and app shutdown must return denial/cancel where the protocol supports it.

**Step 4: Verify GREEN**

Run: `swift test --filter CodexPendingRequestRegistryTests`
Run: `swift test --filter CodexAnswerEncoderTests`
Expected: PASS.

**Step 5: Commit**

```bash
git add Sources/MorphlingApp/Integrations/Codex/CodexPendingRequestRegistry.swift Sources/MorphlingApp/Integrations/Codex/CodexAnswerEncoder.swift Tests/MorphlingTests/Codex*RequestRegistryTests.swift Tests/MorphlingTests/CodexAnswerEncoderTests.swift
git commit -m "feat: answer Codex app-server requests"
```

---

### Task 11: Add the static mascot renderer and floating interface

**Objective:** Present one replaceable mascot image for Idle, Working, and Needs Input while supporting multiple sessions.

**Files:**
- Create: `Sources/MorphlingApp/UI/Mascot/MascotAssetProviding.swift`
- Create: `Sources/MorphlingApp/UI/Mascot/StaticMascotView.swift`
- Create: `Sources/MorphlingApp/UI/Mascot/MascotWindowController.swift`
- Create: `Sources/MorphlingApp/UI/SessionListView.swift`
- Create: `Sources/MorphlingApp/Resources/Assets.xcassets/Contents.json`
- Create: `Sources/MorphlingApp/Resources/Assets.xcassets/MascotIdle.imageset/Contents.json`
- Create: `Sources/MorphlingApp/Resources/Assets.xcassets/MascotWorking.imageset/Contents.json`
- Create: `Sources/MorphlingApp/Resources/Assets.xcassets/MascotNeedsInput.imageset/Contents.json`
- Create: placeholder PNGs in each imageset
- Create: `Tests/MorphlingTests/MascotPresentationTests.swift`

**Step 1: Write failing presentation tests**

Test aggregate-state-to-asset mapping and accessibility labels. Verify error uses needs-input artwork plus an error badge until dedicated art exists.

**Step 2: Implement an asset abstraction**

```swift
protocol MascotAssetProviding {
    func assetName(for state: AgentSessionState) -> String
}
```

The SwiftUI view must depend on this abstraction, not hard-coded animation technology. That is the seam for future MP4/Lottie/Rive support.

**Step 3: Build the interface**

Create a small always-on-top, movable, transparent AppKit panel containing the mascot and status count. Clicking it opens a popover/session list. Needs-input state expands the relevant question automatically. Provide a menu-bar item for Show/Hide, Settings, and Quit.

**Step 4: Verify GREEN and preview states**

Run: `swift test --filter MascotPresentationTests`
Expected: PASS.

Run: `swift run MorphlingApp --demo-state needsInput`
Expected: static needs-input mascot appears with a deterministic sample question; this flag must not start hooks or mutate user config.

**Step 5: Commit**

```bash
git add Sources/MorphlingApp/UI Sources/MorphlingApp/Resources/Assets.xcassets Tests/MorphlingTests/MascotPresentationTests.swift
git commit -m "feat: add static state mascot interface"
```

---

### Task 12: Build the question and option-selection UI

**Objective:** Display every pending question and option, validate selection, and submit to the correct provider/session.

**Files:**
- Create: `Sources/MorphlingApp/UI/Questions/QuestionCardView.swift`
- Create: `Sources/MorphlingApp/UI/Questions/QuestionFormModel.swift`
- Create: `Sources/MorphlingApp/UI/Questions/PendingQuestionsView.swift`
- Create: `Tests/MorphlingTests/QuestionFormModelTests.swift`

**Step 1: Write failing form-model tests**

Cover single selection, multi-selection, required unanswered state, free-text answers, multiple questions, option descriptions, cancellation, double-submit prevention, and provider submission failure.

**Step 2: Implement the form model**

Keep draft selections keyed by question ID. Submit all answers atomically to the adapter's pending request. Disable the button while sending; on failure retain choices and present retry/cancel.

**Step 3: Implement accessible SwiftUI controls**

Use radio-style controls for single choice, checkboxes for multi-choice, and `TextField`/`TextEditor` for free text. Show agent, session title, cwd, and question number. Never truncate the actual question or omit options; use scrolling for long content.

**Step 4: Verify GREEN**

Run: `swift test --filter QuestionFormModelTests`
Expected: PASS.

Run the demo state and manually verify keyboard-only selection, VoiceOver labels, scrolling, and submit/cancel behavior.

**Step 5: Commit**

```bash
git add Sources/MorphlingApp/UI/Questions Tests/MorphlingTests/QuestionFormModelTests.swift
git commit -m "feat: add interactive agent question UI"
```

---

### Task 13: Add transition-based macOS notifications

**Objective:** Notify once when work starts and once when input is required, without notification storms from progress hooks.

**Files:**
- Create: `Sources/MorphlingApp/Notifications/AgentNotificationCoordinator.swift`
- Create: `Sources/MorphlingApp/Notifications/NotificationSending.swift`
- Create: `Tests/MorphlingTests/AgentNotificationCoordinatorTests.swift`

**Step 1: Write failing transition tests**

Verify:

- idle → working sends “Claude Code started working” or “Codex started working.”
- working → working sends nothing.
- any state → needs input sends one notification containing the first question and provider/session context.
- repeated identical needs-input snapshots send nothing.
- a distinct later request sends again.
- ended sessions do not trigger a false idle/working notification.

**Step 2: Implement coordinator and production sender**

Use `UNUserNotificationCenter`; request permission in context, not at launch without explanation. Notification clicks activate Morphling and focus the exact pending question.

**Step 3: Verify GREEN**

Run: `swift test --filter AgentNotificationCoordinatorTests`
Expected: PASS.

**Step 4: Commit**

```bash
git add Sources/MorphlingApp/Notifications Tests/MorphlingTests/AgentNotificationCoordinatorTests.swift
git commit -m "feat: notify on agent work and input transitions"
```

---

### Task 14: Add onboarding, settings, and integration health

**Objective:** Make setup explicit, reversible, and understandable without editing dotfiles manually.

**Files:**
- Create: `Sources/MorphlingApp/UI/Onboarding/OnboardingView.swift`
- Create: `Sources/MorphlingApp/UI/Settings/IntegrationsSettingsView.swift`
- Create: `Sources/MorphlingApp/UI/Settings/DiagnosticsView.swift`
- Create: `Sources/MorphlingApp/App/AppSettings.swift`
- Create: `Tests/MorphlingTests/AppSettingsTests.swift`

**Step 1: Write failing settings tests**

Test default port selection, enabled integrations, launch-at-login preference representation, and migration-safe decoding.

**Step 2: Implement onboarding**

Explain and request separately:

1. Notification permission.
2. Claude hook install.
3. Codex hook install for status.
4. Managed Codex app-server for interactive control.

Show the exact files Morphling changes and provide uninstall buttons. State that already-running sessions need restart/reconnect.

**Step 3: Add Codex connection instructions**

Display a copyable command using the actual selected port:

```bash
codex --remote ws://127.0.0.1:<port>
```

Optionally provide a shell alias snippet, but do not mutate shell startup files automatically.

**Step 4: Add diagnostics**

Show bridge health, bind address, Claude hook status, Codex hook status, Codex app-server status/version, live session count, and last metadata-only error. Add “Export diagnostics” that redacts tokens, prompts, answers, home-directory username, and transcript contents.

**Step 5: Verify GREEN**

Run: `swift test --filter AppSettingsTests`
Run: `swift test`
Expected: PASS.

**Step 6: Commit**

```bash
git add Sources/MorphlingApp/UI/Onboarding Sources/MorphlingApp/UI/Settings Sources/MorphlingApp/App/AppSettings.swift Tests/MorphlingTests/AppSettingsTests.swift
git commit -m "feat: add integration onboarding and diagnostics"
```

---

### Task 15: Wire application lifecycle and graceful shutdown

**Objective:** Start adapters once, consume snapshots on the main actor, and cleanly release pending requests and child processes.

**Files:**
- Modify: `Sources/MorphlingApp/App/AppDelegate.swift`
- Modify: `Sources/MorphlingApp/MorphlingApp.swift`
- Modify: `Sources/MorphlingApp/UI/RootView.swift`
- Create: `Sources/MorphlingApp/App/AppCoordinator.swift`
- Create: `Tests/MorphlingTests/AppCoordinatorTests.swift`

**Step 1: Write failing coordinator tests**

Test startup order, partial adapter failure, snapshot delivery, duplicate start prevention, shutdown cancellation, HTTP listener stop, pending request resolution, and owned Codex process termination.

**Step 2: Implement coordinator**

Inject all services. Start the session store, localhost server, installed adapters, notification coordinator, and UI snapshot task. One provider failing must not disable the other. Stop services in reverse order and do not terminate external Claude/Codex processes.

**Step 3: Verify GREEN**

Run: `swift test --filter AppCoordinatorTests`
Expected: PASS.

Run: `swift test`
Expected: all tests PASS.

**Step 4: Commit**

```bash
git add Sources/MorphlingApp/App Sources/MorphlingApp/MorphlingApp.swift Sources/MorphlingApp/UI/RootView.swift Tests/MorphlingTests/AppCoordinatorTests.swift
git commit -m "feat: wire Morphling application lifecycle"
```

---

### Task 16: Run end-to-end acceptance tests with real CLIs

**Objective:** Prove the app works against installed Claude Code and Codex, not only mocks.

**Files:**
- Create: `scripts/e2e/verify-bridge.sh`
- Create: `scripts/e2e/verify-claude-hooks.sh`
- Create: `scripts/e2e/verify-codex-app-server.sh`
- Create: `docs/manual-acceptance.md`

**Step 1: Verify clean build and all automated tests**

Run:

```bash
swift package clean
swift build
swift test
```

Expected: build succeeds and all tests pass without warnings introduced by Morphling.

**Step 2: Verify the real bridge**

Launch Morphling, call `/healthz` on loopback, send a signed fixture event, and assert the session appears in the app. Verify wrong-token, malformed JSON, and oversized requests are rejected.

**Step 3: Verify Claude lifecycle**

In a disposable Claude settings HOME or dedicated test account:

1. Install hooks through Morphling.
2. Start Claude Code and confirm session idle/connected.
3. Submit a harmless prompt and confirm one “started working” notification.
4. Trigger `AskUserQuestion` with at least two options.
5. Confirm Morphling shows exact question/options.
6. Select an option and confirm Claude continues with that answer.
7. Stop/end the session and confirm idle/removal.
8. Uninstall and diff settings to prove unrelated configuration survived.

**Step 4: Verify Codex lifecycle and response**

1. Start Morphling's managed app-server.
2. Connect using `codex --remote ws://127.0.0.1:<port>`.
3. Start a harmless turn and confirm working notification/state.
4. Trigger a command/file approval or supported structured user-input request.
5. Answer in Morphling and confirm Codex continues.
6. End the turn and confirm idle.
7. Start a normal unconnected `codex` session and confirm it is visible as status-only.

**Step 5: Verify concurrency**

Run two Claude and two Codex sessions in separate directories. Confirm independent rows, correct titles/cwds, aggregate mascot priority, and that an answer goes only to the selected session/request.

**Step 6: Verify failure behavior**

Quit Morphling during a pending question, restart while agents are active, kill the managed app-server, occupy the default ports, disconnect the Codex WebSocket, and deny notifications. Confirm no agent is silently approved, no process is killed accidentally, and diagnostics explain recovery.

**Step 7: Commit**

```bash
git add scripts/e2e docs/manual-acceptance.md
git commit -m "test: add real agent integration acceptance checks"
```

---

### Task 17: Package the macOS application

**Objective:** Produce a distributable `.app` with documented signing and first-run behavior.

**Files:**
- Create: `scripts/build-app.sh`
- Create: `Resources/Info.plist`
- Create: `Resources/Morphling.entitlements`
- Create: `README.md`

**Step 1: Write a packaging verification script first**

The script must fail if the executable, Info.plist, mascot assets, hook resources, or expected bundle identifier are absent.

**Step 2: Implement deterministic app bundling**

Build release mode, assemble `Morphling.app`, copy resources, set `LSUIElement` if the final UX is menu-bar-only, and sign locally with ad-hoc signing for development. Keep Developer ID notarization as a documented release step, not a fake success path.

**Step 3: Document setup and limitations**

Include install/run instructions, supported agent versions, hook files changed, uninstall procedure, localhost ports, security model, `codex --remote` requirement for interaction, static mascot replacement seam, and troubleshooting.

**Step 4: Verify artifact**

Run:

```bash
./scripts/build-app.sh
codesign --verify --deep --strict build/Morphling.app
open build/Morphling.app
```

Expected: signature verification succeeds and the app launches.

**Step 5: Commit**

```bash
git add scripts/build-app.sh Resources README.md
git commit -m "build: package Morphling macOS application"
```

---

## Files likely to change

All implementation is new beneath `/Users/shobhit/Documents/projects/workview-os/morphling`:

- `Package.swift`
- `Sources/MorphlingApp/App/`
- `Sources/MorphlingApp/Domain/`
- `Sources/MorphlingApp/Bridge/`
- `Sources/MorphlingApp/Integrations/Claude/`
- `Sources/MorphlingApp/Integrations/Codex/`
- `Sources/MorphlingApp/Notifications/`
- `Sources/MorphlingApp/UI/`
- `Sources/MorphlingApp/Resources/`
- `Tests/MorphlingTests/`
- `scripts/`
- `Resources/`
- `README.md`

No changes are planned in `supercmd-swift` or `dynamic/Extensions/agents-status`.

## Validation matrix

| Behavior | Unit | Integration | Manual real CLI |
|---|---:|---:|---:|
| State reduction and concurrency | Yes | Yes | Yes |
| HTTP parsing/auth/limits | Yes | Real loopback socket | Yes |
| Claude event mapping | Fixture | Real hook POST | Claude CLI |
| Claude question/answer | Fixture + async | Blocking HTTP | Claude CLI |
| Codex hook status | Fixture | Hook POST | Codex CLI |
| Codex JSON-RPC | Fixture | Real app-server | `codex --remote` |
| Notifications | Fake sender | — | Notification Center |
| Mascot mapping | Yes | Demo mode | Visual/VoiceOver |
| Config install/uninstall | Temp HOME | Disposable config | User opt-in |
| App packaging | Script | Bundle checks | Launch `.app` |

Primary commands:

```bash
swift build
swift test
./scripts/build-app.sh
codesign --verify --deep --strict build/Morphling.app
```

## Risks and tradeoffs

1. **“All running sessions” cannot mean arbitrary input injection.** Process scanning/hooks can discover status, but answering an existing terminal prompt without a provider protocol is brittle and unsafe. Use Claude's blocking hook and Codex app-server; label unsupported sessions status-only.
2. **Codex protocol is experimental and versioned.** Generate schemas from the installed binary, retain unknown-method tolerance, expose compatibility diagnostics, and test against the installed CLI in CI/release checks.
3. **Hook settings are user-owned files.** Every change must be opt-in, marker-based, backed up, atomic, idempotent, reversible, and covered by temp-directory tests.
4. **Blocking hooks can deadlock agents.** Use bounded deadlines, resolve continuations once, and fall back to the provider's normal prompt or safe cancellation—not approval—when Morphling disappears.
5. **Notification storms are likely from tool events.** Notify only on state/request identity transitions, not every progress event.
6. **Multiple simultaneous questions need exact correlation.** Provider request IDs remain private adapter metadata; UI IDs alone are insufficient for routing responses.
7. **App Sandbox may conflict with dotfile mutation and child-process management.** Start with a non-App-Store Developer ID distribution. Reassess helper-tool/XPC architecture if sandboxing becomes a release requirement.
8. **Static images are temporary.** Keep rendering behind `MascotAssetProviding`; do not introduce a video dependency until animation format and performance requirements are chosen.
9. **Privacy:** prompts and answers can contain source code/secrets. Keep them in memory only, redact logs/diagnostics, bind to loopback, authenticate requests, and avoid persistence in MVP.

## Open questions to settle before public release

- Final product name and bundle identifier (`Morphling` is assumed).
- Minimum supported macOS version; plan assumes macOS 15+.
- Whether the mascot panel is always visible, menu-bar only, or user-selectable.
- Final static image artwork and licensing; placeholders are acceptable for implementation.
- Whether permission approvals (shell/file changes) should be shown alongside explicit agent questions. The architecture supports both, but copy and safety affordances should differ.
- Whether launch-at-login is required for MVP.
- Whether to import/migrate behavior from the existing Agents Status extension or keep Morphling fully standalone as planned.

## Completion criteria

- A signed development `Morphling.app` launches and binds only to loopback.
- Two Claude and two Codex sessions can appear concurrently without state collision.
- Idle, Working, and Needs Input display distinct static mascot images.
- Work-start and needs-input transitions produce deduplicated macOS notifications.
- Claude `AskUserQuestion` options render exactly and a selected answer resumes Claude.
- A Codex TUI connected through app-server can surface a supported request and resume after Morphling submits the response.
- Ordinary unconnected Codex sessions are clearly status-only.
- Hook installation/uninstallation preserves unrelated user configuration.
- All automated tests, real CLI acceptance checks, package verification, and code-sign verification pass.
