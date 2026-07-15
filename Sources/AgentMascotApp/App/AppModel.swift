import Foundation
import Observation

@MainActor @Observable final class AppModel {
    var sessions: [AgentSession] = []
    var pendingClaudeRequests: [ClaudePermissionRequest] = []
    var bridgeStatus = "Starting…"
    var claudeHookStatus: HookInstallStatus = .notInstalled
    var codexHookStatus: CodexHookStatus = .notInstalled
    var codexStatus = "Not connected"
    var migrationWarning: String?
    var customAvatar: APNGAnimation?
    var avatarImportError: String?
    @ObservationIgnored var answerClaude: ((String, [String: [String]]) async -> Bool)?
    @ObservationIgnored var cancelClaude: ((String) async -> Void)?
    @ObservationIgnored var installClaudeHooks: (() throws -> Void)?
    @ObservationIgnored var uninstallClaudeHooks: (() throws -> Void)?
    @ObservationIgnored var installCodexHooks: (() throws -> Void)?
    @ObservationIgnored var uninstallCodexHooks: (() throws -> Void)?
    @ObservationIgnored var openSession: ((AgentSession) throws -> Void)?
    @ObservationIgnored var chooseCustomAvatar: (() -> Void)?

    var mainSessions: [AgentSession] { sessions.filter { $0.role == .main } }
    var workingMainSessions: [AgentSession] { mainSessions.filter { $0.state == .working }.sorted { $0.updatedAt > $1.updatedAt } }
    var workingMainCount: Int { workingMainSessions.count }
    var aggregateState: AgentSessionState { AgentMascotApp.aggregateState(for: mainSessions) }

    func submit(requestID: String, answers: [String: [String]]) async -> Bool {
        await answerClaude?(requestID, answers) ?? false
    }
    func cancel(requestID: String) async { await cancelClaude?(requestID) }
    func open(session: AgentSession) throws { try openSession?(session) }
    func chooseAvatar() { chooseCustomAvatar?() }
    func installHooks() { do { try installClaudeHooks?(); try installCodexHooks?(); claudeHookStatus = .installed; codexHookStatus = .installed } catch { bridgeStatus = "Hook install error: \(error.localizedDescription)" } }
    func uninstallHooks() { do { try uninstallClaudeHooks?(); try uninstallCodexHooks?(); claudeHookStatus = .notInstalled; codexHookStatus = .notInstalled } catch { bridgeStatus = "Hook uninstall error: \(error.localizedDescription)" } }
}
