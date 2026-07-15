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
