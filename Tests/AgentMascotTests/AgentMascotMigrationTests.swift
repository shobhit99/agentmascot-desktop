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

    func testCodexMigrationReplacesLegacyBlockAndKeepsUserConfiguration() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let config = root.appendingPathComponent("config.toml"), legacyScript = root.appendingPathComponent("old-codex.sh")
        let currentScript = root.appendingPathComponent("new-codex.sh")
        try Data("model = \"user-model\"\nnotify = [\"keep.sh\"]\n# morphling-managed\nnotify = [\"old-codex.sh\"]\n".utf8).write(to: config)
        try Data().write(to: legacyScript)
        let migration = AgentMascotMigration(
            claude: ClaudeHookInstaller(settingsURL: root.appendingPathComponent("settings.json"), scriptURL: root.appendingPathComponent("new-claude.sh")),
            codex: CodexHookInstaller(configURL: config, scriptURL: currentScript),
            legacyClaudeScriptURL: root.appendingPathComponent("old-claude.sh"),
            legacyCodexScriptURL: legacyScript
        )
        XCTAssertTrue(migration.migrate(token: "token", port: 7824).warnings.isEmpty)
        let text = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(text.contains("model = \"user-model\""))
        XCTAssertTrue(text.contains("notify = [\"keep.sh\"]"))
        XCTAssertFalse(text.contains("morphling-managed"))
        XCTAssertTrue(text.contains("agent-mascot-managed"))
        XCTAssertTrue(text.contains(currentScript.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyScript.path))
    }

    func testMigrationIsIdempotentAndUninstallRemovesBothGenerations() throws {
        let root = try temporaryDirectory(); defer { try? FileManager.default.removeItem(at: root) }
        let settings = root.appendingPathComponent("settings.json"), config = root.appendingPathComponent("config.toml")
        let claude = ClaudeHookInstaller(settingsURL: settings, scriptURL: root.appendingPathComponent("new-claude.sh"))
        let codex = CodexHookInstaller(configURL: config, scriptURL: root.appendingPathComponent("new-codex.sh"))
        try Data(#"{"hooks":{"Stop":[{"morphling":"morphling-managed","hooks":[]},{"matcher":"keep","hooks":[]}]}}"#.utf8).write(to: settings)
        try Data("theme = \"keep\"\n# morphling-managed\nnotify = [\"old.sh\"]\n".utf8).write(to: config)
        let migration = AgentMascotMigration(claude: claude, codex: codex, legacyClaudeScriptURL: root.appendingPathComponent("old-claude.sh"), legacyCodexScriptURL: root.appendingPathComponent("old-codex.sh"))
        XCTAssertTrue(migration.migrate(token: "token", port: 7824).warnings.isEmpty)
        let onceSettings = try Data(contentsOf: settings), onceConfig = try Data(contentsOf: config)
        XCTAssertTrue(migration.migrate(token: "token", port: 7824).warnings.isEmpty)
        XCTAssertEqual(try Data(contentsOf: settings), onceSettings)
        XCTAssertEqual(try Data(contentsOf: config), onceConfig)
        try claude.uninstall(); try codex.uninstall()
        let finalSettings = try String(contentsOf: settings, encoding: .utf8)
        let finalConfig = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(finalSettings.contains("keep"))
        XCTAssertFalse(finalSettings.contains("managed"))
        XCTAssertTrue(finalConfig.contains("theme = \"keep\""))
        XCTAssertFalse(finalConfig.contains("managed"))
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
