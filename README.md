# Morphling

Native macOS menu-bar mascot for Claude Code 2.x and Codex CLI 0.144.x. Morphling binds an authenticated bridge only to `127.0.0.1:7824`, owns a loopback Codex app-server on a dynamically selected port, discovers active Codex Desktop/CLI threads and subagents through the app-server protocol, and displays three bundled static mascot assets.

## Build and development package

```bash
swift test
swift build -c release
./scripts/build-app.sh
codesign --verify --deep --strict build/Morphling.app
ALLOW_ADHOC_DMG=1 ./scripts/build-dmg.sh
```

`build/Morphling.app` is **ad-hoc signed for local development only**. It is not Developer ID signed or notarized and is not claimed to pass public Gatekeeper distribution. A public release requires Developer ID signing, hardened runtime, notarization, and stapling.

The packaging scripts copy SwiftPM's generated `Morphling_MorphlingApp.bundle` into the app before signing. Do not copy `Sources/MorphlingApp/Resources` into a signed app manually: `Bundle.module` metadata expects the generated bundle, and changing the app after signing invalidates the signature.

Only the rendered PNG frames, status SVGs, and hook scripts are included in the app. The source APNG and MOV files are intentionally excluded from the package so release artifacts never need to be slimmed after signing.

For a public build, use a Developer ID Application identity and a saved `notarytool` keychain profile:

```bash
SIGNING_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)" \
NOTARYTOOL_PROFILE="morphling-notary" \
./scripts/build-dmg.sh
```

App Store Connect API keys are also supported without storing a profile:

```bash
SIGNING_IDENTITY="Developer ID Application: Example, Inc. (TEAMID)" \
NOTARYTOOL_KEY="$HOME/.private_keys/AuthKey_KEYID.p8" \
NOTARYTOOL_KEY_ID="KEYID" \
NOTARYTOOL_ISSUER="00000000-0000-0000-0000-000000000000" \
./scripts/build-dmg.sh
```

`NOTARYTOOL_ISSUER` is optional for an individual App Store Connect API key.

For the local Codex run loop, use `./script/build_and_run.sh --verify`. The Run action in `.codex/environments/environment.toml` uses the same entrypoint.

Demo without services or config mutation: `swift run MorphlingApp --demo-state needsInput`.

Morphling resolves Codex from `MORPHLING_CODEX_PATH`, the inherited `PATH`, common user install locations such as `~/.local/bin`, nvm installations, Homebrew, or the Codex binary bundled with ChatGPT. This is required because apps opened from Finder do not inherit an interactive shell's `PATH`.

## Integrations and security

The installation token is stored at `~/Library/Application Support/Morphling/bridge.token` as an owner-only regular file. The HTTP parser enforces exact Bearer syntax, unambiguous framing, bounded headers/body/total size, connection limits, and idle cleanup. Prompts and answers stay in memory.

Claude hook installation is explicit and reversible: it modifies `~/.claude/settings.json`, creates `.morphling-backup`, and installs a helper under Application Support. Codex discovery is zero-config and does not modify Codex configuration.

Restart already-running Claude sessions after installing their hooks. Ordinary Codex Desktop/CLI sessions and Codex subagents are detected automatically. Interactive Codex approvals/input still require the displayed `codex --remote ws://127.0.0.1:<port>` command. On timeout or shutdown Morphling asks/declines; it never silently approves.

## Verification

```bash
swiftc -parse-as-library scripts/e2e/CodexInitializeProbe.swift -o .build/debug/CodexInitializeProbe
scripts/e2e/verify-codex-app-server.sh
```

See `docs/manual-acceptance.md` for bridge, Claude, concurrency, notification, and failure checks.

## Uninstall

Use the integration uninstall controls before removing the app. They remove only `morphling-managed` entries. If the app is already gone, restore only the marked entries from the adjacent `.morphling-backup`; do not replace newer unrelated settings wholesale.
