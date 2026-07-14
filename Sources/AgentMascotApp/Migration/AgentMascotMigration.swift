import Foundation

struct AgentMascotMigrationReport: Equatable { var warnings: [String] = [] }

struct AgentMascotMigration {
    let claude: ClaudeHookInstaller
    let codex: CodexHookInstaller
    let legacyClaudeScriptURL: URL
    let legacyCodexScriptURL: URL
    let fileManager: FileManager = .default

    func migrate(token: String, port: Int) -> AgentMascotMigrationReport {
        let migrateClaude = claude.hasLegacyEntries()
        let migrateCodex = codex.hasLegacyEntry()
        guard migrateClaude || migrateCodex else { return .init() }
        do {
            if migrateClaude { try claude.install(token: token, port: port) }
            if migrateCodex { try codex.install(token: token, port: port) }
            if migrateClaude { try? fileManager.removeItem(at: legacyClaudeScriptURL) }
            if migrateCodex { try? fileManager.removeItem(at: legacyCodexScriptURL) }
            return .init()
        } catch {
            return .init(warnings: ["Existing Agent Mascot hooks were not fully migrated: \(error.localizedDescription)"])
        }
    }
}
