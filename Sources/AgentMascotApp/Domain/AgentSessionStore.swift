import Foundation

actor AgentSessionStore {
    private var sessions: [String: AgentSession] = [:]
    private var seen: [UUID: Date] = [:]
    private var continuations: [UUID: AsyncStream<[AgentSession]>.Continuation] = [:]
    private func key(_ agent: AgentKind, _ id: String) -> String { "\(agent.rawValue):\(id)" }
    func snapshot() -> [AgentSession] { sessions.values.sorted {$0.updatedAt > $1.updatedAt} }
    func stream() -> AsyncStream<[AgentSession]> {
        let id = UUID(); return AsyncStream { continuation in
            continuations[id] = continuation; continuation.yield(snapshot())
            continuation.onTermination = { _ in Task { await self.removeContinuation(id) } }
        }
    }
    private func removeContinuation(_ id: UUID) { continuations[id] = nil }
    func apply(_ event: AgentEvent) {
        guard event.role == .main else { return }
        if seen[event.id] != nil { return }
        seen[event.id] = event.occurredAt
        if seen.count > 2048 { seen = seen.filter {$0.value > Date().addingTimeInterval(-3600)} }
        let k = key(event.agent, event.sessionID)
        if let current = sessions[k], event.occurredAt < current.updatedAt { return }
        if event.kind == .sessionEnded { sessions[k] = nil; publish(); return }
        var session = sessions[k] ?? AgentSession(id: k, agent: event.agent, providerSessionID: event.sessionID, role: event.role, state: .idle, cwd: event.cwd ?? "", title: event.title ?? event.sessionID, pid: event.pid, questions: [], updatedAt: event.occurredAt)
        if let cwd = event.cwd { session.cwd = cwd }; if let title = event.title { session.title = title }; if let pid = event.pid { session.pid = pid }
        switch event.kind {
        case .sessionStarted: session.state = .idle
        case .workStarted, .workProgressed: session.state = .working
        case .inputRequested: session.state = .needsInput; if let q = event.question, !session.questions.contains(where: {$0.id == q.id}) { session.questions.append(q) }
        case .workStopped: session.state = .idle; session.questions = []
        case .failed: session.state = .error
        case .sessionEnded: break
        }
        session.updatedAt = event.occurredAt; sessions[k] = session; publish()
    }
    func answer(questionID: String, agent: AgentKind, sessionID: String) {
        let k = key(agent, sessionID); guard var s = sessions[k] else { return }
        s.questions.removeAll {$0.id == questionID}; s.state = s.questions.isEmpty ? .working : .needsInput; s.updatedAt = .now; sessions[k] = s; publish()
    }
    private func publish() { let value = snapshot(); continuations.values.forEach {$0.yield(value)} }
}
