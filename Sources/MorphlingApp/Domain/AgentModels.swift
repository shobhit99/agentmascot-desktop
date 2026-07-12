import Foundation

enum AgentKind: String, Codable, Sendable, CaseIterable { case claudeCode, codex }
enum AgentSessionState: String, Codable, Sendable { case idle, working, needsInput, ended, error }
struct AgentChoice: Identifiable, Codable, Equatable, Sendable { let id: String; let label: String; let description: String?; let value: String }
struct AgentQuestion: Identifiable, Codable, Equatable, Sendable { let id: String; let prompt: String; let choices: [AgentChoice]; let allowsFreeText: Bool; let isMultiSelect: Bool }
struct AgentSession: Identifiable, Codable, Equatable, Sendable {
    let id: String; let agent: AgentKind; var state: AgentSessionState; var cwd: String; var title: String; var pid: Int32?; var questions: [AgentQuestion]; var updatedAt: Date
}
enum AgentEventKind: String, Codable, Sendable { case sessionStarted, workStarted, workProgressed, inputRequested, workStopped, sessionEnded, failed }
struct AgentEvent: Identifiable, Codable, Equatable, Sendable {
    let version: Int; let id: UUID; let agent: AgentKind; let sessionID: String; let kind: AgentEventKind; let cwd: String?; let pid: Int32?; let title: String?; let question: AgentQuestion?; let occurredAt: Date
}
protocol AgentAdapter: Sendable { func start() async throws; func stop() async }
func aggregateState(for sessions: [AgentSession]) -> AgentSessionState {
    if sessions.contains(where: {$0.state == .needsInput}) { return .needsInput }
    if sessions.contains(where: {$0.state == .error}) { return .error }
    if sessions.contains(where: {$0.state == .working}) { return .working }
    return .idle
}
