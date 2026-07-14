import XCTest
@testable import AgentMascotApp

final class SessionFilteringTests: XCTestCase {
    func testLegacyEventDefaultsToMainRole() throws {
        let data = Data(#"{"version":1,"id":"00000000-0000-0000-0000-000000000001","agent":"codex","sessionID":"thread","kind":"workStarted","occurredAt":0}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(AgentEvent.self, from: data).role, .main)
    }

    func testSubagentEventsNeverEnterTheStore() async {
        let store = AgentSessionStore()
        await store.apply(AgentEvent(version: 2, id: UUID(), agent: .codex, sessionID: "child", role: .subagent, kind: .workStarted, cwd: nil, pid: nil, title: nil, question: nil, occurredAt: .now))
        let sessions = await store.snapshot()
        XCTAssertTrue(sessions.isEmpty)
    }

    @MainActor func testWorkingMainSessionsAreOrderedAndFiltered() {
        let model = AppModel()
        model.sessions = [
            AgentSession(id: "codex:old", agent: .codex, providerSessionID: "old", state: .working, cwd: "/", title: "Old", pid: nil, questions: [], updatedAt: .distantPast),
            AgentSession(id: "codex:new", agent: .codex, providerSessionID: "new", state: .working, cwd: "/", title: "New", pid: nil, questions: [], updatedAt: .now),
            AgentSession(id: "codex:child", agent: .codex, providerSessionID: "child", role: .subagent, state: .working, cwd: "/", title: "Child", pid: nil, questions: [], updatedAt: .now.addingTimeInterval(1))
        ]
        XCTAssertEqual(model.workingMainSessions.map(\.providerSessionID), ["new", "old"])
        XCTAssertEqual(model.workingMainCount, 2)
    }
}
