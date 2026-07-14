import XCTest
@testable import AgentMascotApp

@MainActor final class AgentHarnessNavigatorTests: XCTestCase {
    private func session(agent: AgentKind, rawID: String) -> AgentSession {
        AgentSession(id: "\(agent.rawValue):composite", agent: agent, providerSessionID: rawID, state: .working, cwd: "/", title: "Task", pid: nil, questions: [], updatedAt: .now)
    }

    func testUsesRawProviderSessionIDAndProviderURLs() throws {
        XCTAssertEqual(try AgentHarnessNavigator.url(for: session(agent: .codex, rawID: "a/b")).absoluteString, "codex://threads/a%2Fb")
        XCTAssertEqual(try AgentHarnessNavigator.url(for: session(agent: .claudeCode, rawID: "thread")).absoluteString, "claude://claude.ai/code/thread")
    }

    func testRejectedOpenThrows() {
        let navigator = AgentHarnessNavigator(opener: { _ in false })
        XCTAssertThrowsError(try navigator.open(session: session(agent: .codex, rawID: "thread")))
    }
}
