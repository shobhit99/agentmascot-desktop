import Foundation

struct HTTPResponse: Sendable {
    let status: Int
    let body: Data

    init(status: Int, body: Data = Data("{}".utf8)) {
        self.status = status
        self.body = body
    }
}

struct BridgeRouter: Sendable {
    let token: String
    let store: AgentSessionStore
    let claudeRegistry: ClaudePendingRequestRegistry
    let permissionTimeout: Duration

    init(token: String, store: AgentSessionStore, claudeRegistry: ClaudePendingRequestRegistry, permissionTimeout: Duration = .seconds(290)) {
        self.token = token
        self.store = store
        self.claudeRegistry = claudeRegistry
        self.permissionTimeout = permissionTimeout
    }

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        if request.method == "GET", request.path == "/healthz" {
            return HTTPResponse(status: 200, body: Data(#"{"ok":true}"#.utf8))
        }
        guard request.bearerToken == token else { return json(status: 401, message: "unauthorized") }
        guard request.method == "POST" else { return HTTPResponse(status: 405) }

        if request.path == "/v1/events" {
            do {
                let event: AgentEvent
                if let decoded = try? JSONDecoder.iso8601.decode(AgentEvent.self, from: request.body) {
                    event = decoded
                } else if let codex = try? CodexHookMapper.map(request.body) {
                    event = codex
                } else {
                    event = try ClaudeEventMapper.map(request.body)
                }
                await store.apply(event)
                return HTTPResponse(status: 202)
            } catch {
                return json(status: 400, message: "invalid event")
            }
        }

        if request.path == "/v1/claude/permission-request" {
            do {
                let permission = try ClaudePermissionRequest.decode(request.body)
                for question in permission.questions {
                    await store.apply(AgentEvent(version: 1, id: UUID(), agent: .claudeCode, sessionID: permission.sessionID, kind: .inputRequested, cwd: nil, pid: nil, title: "Claude Code", question: question, occurredAt: .now))
                }
                let body = await claudeRegistry.registerAndWait(permission, timeout: permissionTimeout)
                return HTTPResponse(status: 200, body: body)
            } catch ClaudePermissionError.notQuestion {
                let body = (try? JSONSerialization.data(withJSONObject: ClaudePermissionRequest.safeFallback)) ?? Data("{}".utf8)
                return HTTPResponse(status: 200, body: body)
            } catch {
                return json(status: 400, message: "invalid permission request")
            }
        }
        return HTTPResponse(status: 404)
    }

    private func json(status: Int, message: String) -> HTTPResponse {
        HTTPResponse(status: status, body: (try? JSONSerialization.data(withJSONObject: ["error": message])) ?? Data("{}".utf8))
    }
}
