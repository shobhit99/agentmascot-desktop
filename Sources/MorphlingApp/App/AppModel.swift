import Foundation
import Observation

@MainActor @Observable final class AppModel {
    var sessions: [AgentSession] = []
    var pendingClaudeRequests: [ClaudePermissionRequest] = []
    var bridgeStatus = "Starting…"
    var claudeHookStatus: HookInstallStatus = .notInstalled
    var codexHookStatus: CodexHookStatus = .notInstalled
    var codexStatus = "Not connected"
    @ObservationIgnored var answerClaude: ((String, [String: [String]]) async -> Bool)?
    @ObservationIgnored var cancelClaude: ((String) async -> Void)?
    @ObservationIgnored var installClaudeHooks: (() throws -> Void)?
    @ObservationIgnored var uninstallClaudeHooks: (() throws -> Void)?
    @ObservationIgnored var installCodexHooks: (() throws -> Void)?
    @ObservationIgnored var uninstallCodexHooks: (() throws -> Void)?

    var aggregateState: AgentSessionState { MorphlingApp.aggregateState(for: sessions) }

    func submit(requestID: String, answers: [String: [String]]) async -> Bool {
        await answerClaude?(requestID, answers) ?? false
    }
    func cancel(requestID: String) async { await cancelClaude?(requestID) }
    func installHooks() { do { try installClaudeHooks?(); claudeHookStatus = .installed } catch { bridgeStatus = "Hook install error: \(error.localizedDescription)" } }
    func uninstallHooks() { do { try uninstallClaudeHooks?(); claudeHookStatus = .notInstalled } catch { bridgeStatus = "Hook uninstall error: \(error.localizedDescription)" } }
}
