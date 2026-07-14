# Manual acceptance

1. Build/package, launch `build/Agent Mascot.app`, and verify `/healthz` only on `127.0.0.1:7824`.
2. Opt in to Claude hooks in Settings, restart a disposable Claude session, trigger `AskUserQuestion`, select an answer, and verify the session continues.
3. Start one main Codex session with subagents and verify the floating capsule says `Working · 1`; subagents must not appear in the session list or notifications.
4. Run two main working sessions with duplicate titles. Open the `Working · N` capsule and verify each distinct row shows its provider, sorts newest-first, supports keyboard activation/Escape, and disappears when no main session remains.
5. Select a Codex and a Claude Code row and verify each opens that provider's exact task. Temporarily remove a handler and verify the popover remains open with an inline error.
6. Drag the mascot background and verify it moves; buttons and popover controls must remain clickable.
7. Connect a TUI with the displayed `codex --remote ws://127.0.0.1:<port>` command; trigger an approval/input request and verify exact routing.
8. Migrate a disposable legacy installation containing managed Claude and/or Codex entries plus unrelated configuration. Verify the token is adopted, only marked entries change, legacy scripts are removed after success, and a failed migration leaves legacy scripts intact with a warning.
9. Quit with a request pending: it must fall back/decline and the owned app-server must terminate. Deny notifications and occupy ports; diagnostics must report recovery information.

Automated app-server initialization: `swiftc -parse-as-library scripts/e2e/CodexInitializeProbe.swift -o .build/debug/CodexInitializeProbe && scripts/e2e/verify-codex-app-server.sh`.
