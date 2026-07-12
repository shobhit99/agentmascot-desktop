import Foundation

struct ClaudeEventMapper {
    static func map(_ data: Data) throws -> AgentEvent {
        let root = try JSONSerialization.jsonObject(with: data) as! [String:Any]; guard let sid = root["session_id"] as? String, let name = root["hook_event_name"] as? String else { throw CocoaError(.fileReadCorruptFile) }
        let kind: AgentEventKind
        switch name { case "SessionStart": kind = .sessionStarted; case "UserPromptSubmit","PreToolUse","PostToolUse": kind = .workStarted; case "Stop": kind = .workStopped; case "SessionEnd": kind = .sessionEnded; case "PostToolUseFailure": kind = root["is_interrupt"] as? Bool == true ? .workStopped : .workProgressed; default: throw CocoaError(.featureUnsupported) }
        return AgentEvent(version: 1, id: UUID(), agent: .claudeCode, sessionID: sid, kind: kind, cwd: root["cwd"] as? String, pid: (root["pid"] as? NSNumber)?.int32Value, title: root["title"] as? String, question: nil, occurredAt: .now)
    }
}
