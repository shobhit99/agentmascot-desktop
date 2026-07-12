# Morphling

Native macOS menu-bar mascot for Claude Code 2.x and Codex CLI 0.133.x. Morphling binds an authenticated bridge only to `127.0.0.1:7824`, owns a loopback Codex app-server on a dynamically selected port, and displays three bundled static mascot assets.

## Build and development package

```bash
swift test
swift build -c release
./scripts/build-app.sh
codesign --verify --deep --strict build/Morphling.app
```

`build/Morphling.app` is **ad-hoc signed for local development only**. It is not Developer ID signed or notarized and is not claimed to pass public Gatekeeper distribution. A public release requires Developer ID signing, hardened runtime, notarization, and stapling.

Demo without services or config mutation: `swift run MorphlingApp --demo-state needsInput`.

## Integrations and security

The installation token is stored at `~/Library/Application Support/Morphling/bridge.token` as an owner-only regular file. The HTTP parser enforces exact Bearer syntax, unambiguous framing, bounded headers/body/total size, connection limits, and idle cleanup. Prompts and answers stay in memory.

Hook installation is explicit and reversible:
- Claude: modifies `~/.claude/settings.json`, creates `.morphling-backup`, and installs a helper under Application Support.
- Codex status-only: appends a marked `notify` command to `~/.codex/config.toml`, creates a backup, and installs its helper.

Restart already-running sessions after installation. Ordinary Codex sessions are status-only. Interactive approvals/input require the displayed `codex --remote ws://127.0.0.1:<port>` command. On timeout or shutdown Morphling asks/declines; it never silently approves.

## Verification

```bash
swiftc -parse-as-library scripts/e2e/CodexInitializeProbe.swift -o .build/debug/CodexInitializeProbe
scripts/e2e/verify-codex-app-server.sh
```

See `docs/manual-acceptance.md` for bridge, Claude, concurrency, notification, and failure checks.

## Uninstall

Use the integration uninstall controls before removing the app. They remove only `morphling-managed` entries. If the app is already gone, restore only the marked entries from the adjacent `.morphling-backup`; do not replace newer unrelated settings wholesale.
