# Manual acceptance

1. Build/package, launch `build/Morphling.app`, and verify `/healthz` only on `127.0.0.1:7824`.
2. Opt in to Claude hooks in Settings, restart a disposable Claude session, trigger `AskUserQuestion`, select an answer, and verify the session continues.
3. Opt in to Codex status hooks, start an ordinary Codex turn, and verify its row is labelled status-only.
4. Connect a TUI with the displayed `codex --remote ws://127.0.0.1:<port>` command; trigger an approval/input request and verify exact routing.
5. Run two sessions per provider and confirm independent rows and aggregate mascot priority.
6. Quit with a request pending: it must fall back/decline and the owned app-server must terminate.
7. Deny notifications and occupy ports; diagnostics must report recovery information.

Automated app-server initialization: `swiftc -parse-as-library scripts/e2e/CodexInitializeProbe.swift -o .build/debug/CodexInitializeProbe && scripts/e2e/verify-codex-app-server.sh`.
