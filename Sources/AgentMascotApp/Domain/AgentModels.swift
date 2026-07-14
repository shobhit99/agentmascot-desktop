import Foundation

enum AgentKind: String, Codable, Sendable, CaseIterable { case claudeCode, codex }
enum AgentSessionState: String, Codable, Sendable { case idle, working, needsInput, ended, error }
enum AgentSessionRole: String, Codable, Sendable { case main, subagent }
struct AgentChoice: Identifiable, Codable, Equatable, Sendable { let id: String; let label: String; let description: String?; let value: String }
struct AgentQuestion: Identifiable, Codable, Equatable, Sendable { let id: String; let prompt: String; let choices: [AgentChoice]; let allowsFreeText: Bool; let isMultiSelect: Bool }
struct AgentSession: Identifiable, Codable, Equatable, Sendable {
    let id: String; let agent: AgentKind; let providerSessionID: String; let role: AgentSessionRole; var state: AgentSessionState; var cwd: String; var title: String; var pid: Int32?; var questions: [AgentQuestion]; var updatedAt: Date
    init(id: String, agent: AgentKind, providerSessionID: String? = nil, role: AgentSessionRole = .main, state: AgentSessionState, cwd: String, title: String, pid: Int32?, questions: [AgentQuestion], updatedAt: Date) {
        self.id = id; self.agent = agent; self.providerSessionID = providerSessionID ?? id; self.role = role; self.state = state; self.cwd = cwd; self.title = title; self.pid = pid; self.questions = questions; self.updatedAt = updatedAt
    }
}
enum AgentEventKind: String, Codable, Sendable { case sessionStarted, workStarted, workProgressed, inputRequested, workStopped, sessionEnded, failed }
struct AgentEvent: Identifiable, Codable, Equatable, Sendable {
    let version: Int; let id: UUID; let agent: AgentKind; let sessionID: String; let role: AgentSessionRole; let kind: AgentEventKind; let cwd: String?; let pid: Int32?; let title: String?; let question: AgentQuestion?; let occurredAt: Date
    init(version: Int, id: UUID, agent: AgentKind, sessionID: String, role: AgentSessionRole = .main, kind: AgentEventKind, cwd: String?, pid: Int32?, title: String?, question: AgentQuestion?, occurredAt: Date) {
        self.version = version; self.id = id; self.agent = agent; self.sessionID = sessionID; self.role = role; self.kind = kind; self.cwd = cwd; self.pid = pid; self.title = title; self.question = question; self.occurredAt = occurredAt
    }
    enum CodingKeys: String, CodingKey { case version, id, agent, sessionID, role, kind, cwd, pid, title, question, occurredAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version); id = try c.decode(UUID.self, forKey: .id); agent = try c.decode(AgentKind.self, forKey: .agent); sessionID = try c.decode(String.self, forKey: .sessionID); role = try c.decodeIfPresent(AgentSessionRole.self, forKey: .role) ?? .main; kind = try c.decode(AgentEventKind.self, forKey: .kind); cwd = try c.decodeIfPresent(String.self, forKey: .cwd); pid = try c.decodeIfPresent(Int32.self, forKey: .pid); title = try c.decodeIfPresent(String.self, forKey: .title); question = try c.decodeIfPresent(AgentQuestion.self, forKey: .question); occurredAt = try c.decode(Date.self, forKey: .occurredAt)
    }
}
protocol AgentAdapter: Sendable { func start() async throws; func stop() async }
func aggregateState(for sessions: [AgentSession]) -> AgentSessionState {
    if sessions.contains(where: {$0.state == .needsInput}) { return .needsInput }
    if sessions.contains(where: {$0.state == .error}) { return .error }
    if sessions.contains(where: {$0.state == .working}) { return .working }
    return .idle
}
