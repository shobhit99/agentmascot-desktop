import Foundation

enum HookInstallStatus { case installed, partiallyInstalled, notInstalled }
struct ClaudeHookInstaller {
    let settingsURL: URL; let scriptURL: URL
    private let marker = "morphling-managed"
    func status() -> HookInstallStatus {
        guard let data = try? Data(contentsOf: settingsURL), let root = try? JSONSerialization.jsonObject(with: data) as? [String:Any], let hooks = root["hooks"] as? [String:Any] else { return .notInstalled }
        let count = hooks.values.compactMap {$0 as? [[String:Any]]}.flatMap {$0}.filter {$0["morphling"] as? String == marker}.count
        return count >= 9 ? .installed : (count > 0 ? .partiallyInstalled : .notInstalled)
    }
    func install(token: String, port: Int) throws {
        let fm = FileManager.default; try fm.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true); try fm.createDirectory(at: scriptURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let escapedToken = token.replacingOccurrences(of: "'", with: "'\\''")
        let script = "#!/bin/sh\nexec curl -fsS --connect-timeout 1 --max-time 2 -H 'Authorization: Bearer \(escapedToken)' -H 'Content-Type: application/json' --data-binary @- http://127.0.0.1:\(port)/v1/events >/dev/null || true\n"
        try Data(script.utf8).write(to: scriptURL, options: .atomic); try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        var root: [String:Any] = [:]
        if fm.fileExists(atPath: settingsURL.path) { let data = try Data(contentsOf: settingsURL); guard let value = try JSONSerialization.jsonObject(with: data) as? [String:Any] else { throw CocoaError(.fileReadCorruptFile) }; root = value; let backup = settingsURL.appendingPathExtension("morphling-backup"); if !fm.fileExists(atPath: backup.path) { try data.write(to: backup, options: .atomic) } }
        var hooks = root["hooks"] as? [String:Any] ?? [:]
        let lifecycleEvents = ["SessionStart","UserPromptSubmit","PreToolUse","PostToolUse","PostToolUseFailure","Notification","Stop","SessionEnd"]
        for event in lifecycleEvents { var entries = hooks[event] as? [[String:Any]] ?? []; entries.removeAll {$0["morphling"] as? String == marker}; entries.append(["morphling":marker,"hooks":[["type":"command","command":scriptURL.path]]]); hooks[event] = entries }
        var permissionEntries = hooks["PermissionRequest"] as? [[String:Any]] ?? []
        permissionEntries.removeAll {$0["morphling"] as? String == marker}
        permissionEntries.append(["morphling":marker,"matcher":"AskUserQuestion","hooks":[["type":"http","url":"http://127.0.0.1:\(port)/v1/claude/permission-request","headers":["Authorization":"Bearer \(token)"],"timeout":300]]])
        hooks["PermissionRequest"] = permissionEntries
        root["hooks"] = hooks; try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted,.sortedKeys]).write(to: settingsURL, options: .atomic)
    }
    func uninstall() throws {
        guard let data = try? Data(contentsOf: settingsURL), var root = try JSONSerialization.jsonObject(with: data) as? [String:Any], var hooks = root["hooks"] as? [String:Any] else { return }
        for (key,value) in hooks { if var entries = value as? [[String:Any]] { entries.removeAll {$0["morphling"] as? String == marker}; hooks[key] = entries } }
        root["hooks"] = hooks; try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted,.sortedKeys]).write(to: settingsURL, options: .atomic)
    }
}
