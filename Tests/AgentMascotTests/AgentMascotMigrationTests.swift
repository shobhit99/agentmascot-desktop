import XCTest
@testable import AgentMascotApp

final class AgentMascotMigrationTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testAdoptsValidLegacyTokenOnlyWhenNewTokenIsAbsent() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("Morphling/bridge.token")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        let token = Data(repeating: 7, count: 32).base64EncodedString()
        try Data(token.utf8).write(to: legacy); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacy.path)
        let current = root.appendingPathComponent("Agent Mascot/bridge.token")
        XCTAssertEqual(try InstallationTokenStore(url: current).loadOrCreate(adoptingLegacyTokenAt: legacy), token)
        XCTAssertEqual(try InstallationTokenStore(url: current).loadOrCreate(adoptingLegacyTokenAt: legacy), token)
    }

    func testCurrentTokenTakesPrecedenceOverLegacyToken() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("Morphling/bridge.token"), current = root.appendingPathComponent("Agent Mascot/bridge.token")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: current.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = Data(repeating: 1, count: 32).base64EncodedString(), new = Data(repeating: 2, count: 32).base64EncodedString()
        try Data(old.utf8).write(to: legacy); try Data(new.utf8).write(to: current)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacy.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: current.path)
        XCTAssertEqual(try InstallationTokenStore(url: current).loadOrCreate(adoptingLegacyTokenAt: legacy), new)
    }

    func testMalformedLegacyTokenIsNotAdopted() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("Morphling/bridge.token"), current = root.appendingPathComponent("Agent Mascot/bridge.token")
        try FileManager.default.createDirectory(at: legacy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not-a-token".utf8).write(to: legacy); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: legacy.path)
        XCTAssertNotEqual(try InstallationTokenStore(url: current).loadOrCreate(adoptingLegacyTokenAt: legacy), "not-a-token")
    }

    func testClaudeMigrationReplacesOnlyManagedEntries() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent("settings.json")
        let oldScript = root.appendingPathComponent("old.sh"), newScript = root.appendingPathComponent("new.sh")
        let fixture = #"{"theme":"dark","hooks":{"Stop":[{"morphling":"morphling-managed","hooks":[{"type":"command","command":"old.sh"}]},{"matcher":"user","hooks":[{"type":"command","command":"keep.sh"}]}]}}"#
        try Data(fixture.utf8).write(to: settings); try Data().write(to: oldScript)
        let claude = ClaudeHookInstaller(settingsURL: settings, scriptURL: newScript)
        let codex = CodexHookInstaller(configURL: root.appendingPathComponent("config.toml"), scriptURL: root.appendingPathComponent("new-codex.sh"))
        _ = AgentMascotMigration(claude: claude, codex: codex, legacyClaudeScriptURL: oldScript, legacyCodexScriptURL: root.appendingPathComponent("old-codex.sh")).migrate(token: "token", port: 7824)
        let rootObject = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        XCTAssertEqual(rootObject["theme"] as? String, "dark")
        let stop = ((rootObject["hooks"] as! [String: Any])["Stop"] as! [[String: Any]])
        XCTAssertTrue(stop.contains { $0["agentmascot"] as? String == "agent-mascot-managed" })
        XCTAssertTrue(stop.contains { $0["matcher"] as? String == "user" })
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldScript.path))
    }

    func testCodexRemovalPreservesUnrelatedNotifyLines() {
        let input = "# user\nnotify = [\"keep.sh\"]\n# morphling-managed\nnotify = [\"old.sh\"]\n"
        XCTAssertEqual(CodexHookInstaller.removingManagedBlocks(from: input), "# user\nnotify = [\"keep.sh\"]\n")
    }

    func testPartialMigrationKeepsLegacyScriptsAndReportsWarning() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent("settings.json"), legacyClaudeScript = root.appendingPathComponent("old.sh")
        try Data(#"{"hooks":{"Stop":[{"morphling":"morphling-managed","hooks":[]}]}}"#.utf8).write(to: settings)
        try Data().write(to: legacyClaudeScript)
        let claude = ClaudeHookInstaller(settingsURL: settings, scriptURL: root.appendingPathComponent("new.sh"))
        let blockedScriptParent = root.appendingPathComponent("blocked-script-parent")
        try Data().write(to: blockedScriptParent)
        let codex = CodexHookInstaller(configURL: root.appendingPathComponent("config.toml"), scriptURL: blockedScriptParent.appendingPathComponent("new-codex.sh"))
        // Add a Codex legacy marker so migration attempts the impossible script-parent path.
        let invalidConfig = codex.configURL
        try Data("# morphling-managed\nnotify = [\"old.sh\"]\n".utf8).write(to: invalidConfig)
        let report = AgentMascotMigration(claude: claude, codex: codex, legacyClaudeScriptURL: legacyClaudeScript, legacyCodexScriptURL: root.appendingPathComponent("old-codex.sh")).migrate(token: "token", port: 7824)
        XCTAssertFalse(report.warnings.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyClaudeScript.path))
    }
}
