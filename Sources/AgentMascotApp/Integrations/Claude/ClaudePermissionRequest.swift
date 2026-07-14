import Foundation

enum ClaudePermissionError: Error { case invalid, notQuestion }
struct ClaudePermissionRequest: Sendable {
    let sessionID: String; let requestID: String; let questions: [AgentQuestion]
    static func decode(_ data: Data) throws -> Self {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String:Any], let sid = root["session_id"] as? String, root["tool_name"] as? String == "AskUserQuestion", let input = root["tool_input"] as? [String:Any], let raw = input["questions"] as? [[String:Any]] else { throw ClaudePermissionError.notQuestion }
        let rid = (root["permission_request_id"] as? String) ?? UUID().uuidString
        let questions = try raw.enumerated().map { index, item -> AgentQuestion in
            guard let prompt = item["question"] as? String else { throw ClaudePermissionError.invalid }
            let options = (item["options"] as? [[String:Any]] ?? []).enumerated().compactMap { oi, option -> AgentChoice? in
                guard let label = option["label"] as? String else { return nil }
                return AgentChoice(id: "\(rid):\(index):\(oi)", label: label, description: option["description"] as? String, value: label)
            }
            return AgentQuestion(id: "\(rid):\(index)", prompt: prompt, choices: options, allowsFreeText: true, isMultiSelect: item["multiSelect"] as? Bool ?? false)
        }
        return Self(sessionID: sid, requestID: rid, questions: questions)
    }
    func response(answers: [String:[String]]) -> [String:Any] {
        var map: [String:Any] = [:]
        for q in questions { map[q.prompt] = q.isMultiSelect ? (answers[q.id] ?? []) : (answers[q.id]?.first ?? "") }
        return ["hookSpecificOutput": ["hookEventName":"PermissionRequest", "permissionDecision":"allow", "permissionDecisionReason":"Answered by user in Agent Mascot", "updatedInput":["answers":map]]]
    }
    static var safeFallback: [String:Any] { ["hookSpecificOutput":["hookEventName":"PermissionRequest", "permissionDecision":"ask", "permissionDecisionReason":"Agent Mascot unavailable; ask in Claude Code"]] }
}

actor ClaudePendingRequestRegistry {
    private struct Entry {
        let request: ClaudePermissionRequest
        let continuation: CheckedContinuation<Data, Never>
        let timeoutTask: Task<Void, Never>
    }
    private var pending: [String: Entry] = [:]
    private var observers: [UUID: AsyncStream<[ClaudePermissionRequest]>.Continuation] = [:]
    private static let fallback = try! JSONSerialization.data(withJSONObject: ClaudePermissionRequest.safeFallback)

    func registerAndWait(_ request: ClaudePermissionRequest, timeout: Duration = .seconds(290)) async -> Data {
        if let existing = pending.removeValue(forKey: request.requestID) {
            existing.timeoutTask.cancel()
            existing.continuation.resume(returning: Self.fallback)
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let timeoutTask = Task { [requestID = request.requestID] in
                    try? await Task.sleep(for: timeout)
                    guard !Task.isCancelled else { return }
                    self.expire(requestID)
                }
                pending[request.requestID] = Entry(request: request, continuation: continuation, timeoutTask: timeoutTask)
                publish()
            }
        } onCancel: {
            Task { await self.cancel(id: request.requestID) }
        }
    }

    func pendingRequests() -> [ClaudePermissionRequest] {
        pending.values.map(\.request).sorted { $0.requestID < $1.requestID }
    }

    func stream() -> AsyncStream<[ClaudePermissionRequest]> {
        let id = UUID()
        return AsyncStream { continuation in
            observers[id] = continuation
            continuation.yield(pendingRequests())
            continuation.onTermination = { _ in Task { await self.removeObserver(id) } }
        }
    }
    private func removeObserver(_ id: UUID) { observers[id] = nil }
    private func publish() { let value = pendingRequests(); observers.values.forEach { $0.yield(value) } }

    @discardableResult func resolve(requestID: String, answers: [String: [String]]) -> Bool {
        guard let entry = pending.removeValue(forKey: requestID) else { return false }
        entry.timeoutTask.cancel()
        let data = (try? JSONSerialization.data(withJSONObject: entry.request.response(answers: answers))) ?? Self.fallback
        entry.continuation.resume(returning: data)
        publish()
        return true
    }

    func cancel(id: String) { finishFallback(id) }
    private func expire(_ id: String) { finishFallback(id) }
    private func finishFallback(_ id: String) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.timeoutTask.cancel()
        entry.continuation.resume(returning: Self.fallback)
        publish()
    }
    func shutdown() {
        let entries = pending.values
        pending.removeAll()
        for entry in entries { entry.timeoutTask.cancel(); entry.continuation.resume(returning: Self.fallback) }
        publish()
    }
}
