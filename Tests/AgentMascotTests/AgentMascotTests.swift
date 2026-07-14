import XCTest
@testable import AgentMascotApp

final class AgentMascotTests: XCTestCase {
    func testInitialModelAndAggregatePriority() async {
        let model = await AppModel()
        let sessions = await model.sessions
        let state = await model.aggregateState
        XCTAssertTrue(sessions.isEmpty)
        XCTAssertEqual(state, .idle)
        XCTAssertEqual(aggregateState(for: [
            AgentSession(id: "a", agent: .claudeCode, state: .working, cwd: "/", title: "A", pid: nil, questions: [], updatedAt: .now),
            AgentSession(id: "b", agent: .codex, state: .needsInput, cwd: "/", title: "B", pid: nil, questions: [], updatedAt: .now)
        ]), .needsInput)
    }

    func testStoreTransitionsDeduplicatesAndSeparatesProviders() async {
        let store = AgentSessionStore()
        let now = Date()
        let start = AgentEvent(version: 1, id: UUID(), agent: .claudeCode, sessionID: "same", kind: .sessionStarted, cwd: "/tmp", pid: 1, title: "Claude", question: nil, occurredAt: now)
        await store.apply(start); await store.apply(start)
        await store.apply(AgentEvent(version: 1, id: UUID(), agent: .codex, sessionID: "same", kind: .sessionStarted, cwd: "/tmp", pid: 2, title: "Codex", question: nil, occurredAt: now))
        await store.apply(AgentEvent(version: 1, id: UUID(), agent: .claudeCode, sessionID: "same", kind: .workStarted, cwd: nil, pid: nil, title: nil, question: nil, occurredAt: now.addingTimeInterval(1)))
        let sessions = await store.snapshot()
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions.first(where: {$0.agent == .claudeCode})?.state, .working)
    }

    func testHTTPParserAuthAndLimits() throws {
        let body = Data("{}".utf8)
        let raw = Data("POST /v1/events HTTP/1.1\r\nAuthorization: Bearer secret\r\nContent-Length: 2\r\n\r\n{}".utf8)
        let request = try HTTPRequestParser().parse(raw)
        XCTAssertEqual(request.body, body)
        XCTAssertEqual(request.bearerToken, "secret")
        XCTAssertThrowsError(try HTTPRequestParser(maxBodyBytes: 1).parse(raw))
    }

    func testHTTPParserRejectsAmbiguousFramingAndWrongAuthScheme() throws {
        let parser = HTTPRequestParser(maxHeaderBytes: 128, maxBodyBytes: 32, maxTotalBytes: 160)
        let basic = try parser.parse(Data("POST /x HTTP/1.1\r\nAuthorization: Basic secret\r\nContent-Length: 0\r\n\r\n".utf8))
        XCTAssertNil(basic.bearerToken)
        XCTAssertThrowsError(try parser.parse(Data("POST /x HTTP/1.1\r\nContent-Length: 0\r\nContent-Length: 0\r\n\r\n".utf8)))
        XCTAssertThrowsError(try parser.parse(Data("POST /x HTTP/1.1\r\nTransfer-Encoding: chunked\r\nContent-Length: 0\r\n\r\n".utf8)))
        XCTAssertThrowsError(try parser.parse(Data("POST http://evil/x HTTP/1.1\r\nContent-Length: 0\r\n\r\n".utf8)))
        XCTAssertThrowsError(try parser.parse(Data("POST /x HTTP/1.1\r\nContent-Length: 0\r\n\r\ntrailing".utf8)))
    }

    func testCodexSchemaShapedInputAndApprovalResponse() throws {
        let input = Data(#"{"jsonrpc":"2.0","id":7,"method":"item/tool/requestUserInput","params":{"threadId":"t","turnId":"u","itemId":"i","questions":[{"id":"q1","header":"Choice","question":"Pick one","isOther":true,"options":[{"label":"A","description":"First"}]}]}}"#.utf8)
        let pending = try CodexPendingRequest(frame: CodexJSONRPC.decode(input))
        XCTAssertEqual(pending.questions.first?.prompt, "Pick one")
        XCTAssertTrue(String(decoding: try pending.response(answers: ["q1": ["A"]]), as: UTF8.self).contains("\"answers\""))
        let approvalFrame = try CodexJSONRPC.decode(Data(#"{"jsonrpc":"2.0","id":"a","method":"item/commandExecution/requestApproval","params":{"threadId":"t","turnId":"u","itemId":"i","startedAtMs":1,"command":"pwd","availableDecisions":["accept","decline","cancel"]}}"#.utf8))
        let approval = try CodexPendingRequest(frame: approvalFrame)
        XCTAssertTrue(String(decoding: try approval.response(answers: [approval.questions[0].id: ["decline"]]), as: UTF8.self).contains("decline"))
    }

    func testClaudeAskQuestionMappingAndResponse() throws {
        let json = #"{"session_id":"s","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Ship?","header":"Decision","multiSelect":false,"options":[{"label":"Yes","description":"Proceed"},{"label":"No","description":"Stop"}]}]}}"#.data(using: .utf8)!
        let request = try ClaudePermissionRequest.decode(json)
        XCTAssertEqual(request.questions.first?.choices.map(\.label), ["Yes", "No"])
        let response = request.response(answers: [request.questions[0].id: ["Yes"]])
        XCTAssertNotNil(response["hookSpecificOutput"])
    }

    func testClaudeInstallerUsesInjectedPathAndPreservesSettings() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let settings = root.appendingPathComponent("settings.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"theme":"dark"}"#.utf8).write(to: settings)
        let installer = ClaudeHookInstaller(settingsURL: settings, scriptURL: root.appendingPathComponent("hook.sh"))
        try installer.install(token: "x", port: 7824)
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any]
        XCTAssertEqual(object["theme"] as? String, "dark")
        XCTAssertEqual(installer.status(), .installed)
        let script = try String(contentsOf: root.appendingPathComponent("hook.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("Authorization: Bearer x"))
        XCTAssertFalse(script.contains("Bearer ***"))
        let hooks = object["hooks"] as! [String: Any]
        let permissionEntries = hooks["PermissionRequest"] as! [[String: Any]]
        let permissionHook = (permissionEntries[0]["hooks"] as! [[String: Any]])[0]
        XCTAssertEqual(permissionHook["type"] as? String, "http")
        XCTAssertEqual(permissionHook["url"] as? String, "http://127.0.0.1:7824/v1/claude/permission-request")
        XCTAssertEqual(permissionHook["timeout"] as? Int, 300)
        try installer.uninstall()
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(contentsOf: settings)) as! [String: Any])["theme"] as? String, "dark")
    }

    func testPendingClaudeRequestResolvesAndTimesOutSafely() async throws {
        let registry = ClaudePendingRequestRegistry()
        let request = try ClaudePermissionRequest.decode(Data(#"{"session_id":"s","permission_request_id":"r1","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Ship?","multiSelect":false,"options":[{"label":"Yes"}]}]}}"#.utf8))
        let waiter = Task { await registry.registerAndWait(request, timeout: .seconds(2)) }
        while await registry.pendingRequests().isEmpty { await Task.yield() }
        let didResolve = await registry.resolve(requestID: "r1", answers: [request.questions[0].id: ["Yes"]])
        XCTAssertTrue(didResolve)
        let resolved = await waiter.value
        let resolvedJSON = try JSONSerialization.jsonObject(with: resolved) as! [String: Any]
        XCTAssertNotNil(resolvedJSON["hookSpecificOutput"])
        let didResolveTwice = await registry.resolve(requestID: "r1", answers: [:])
        XCTAssertFalse(didResolveTwice)

        let timeoutRequest = try ClaudePermissionRequest.decode(Data(#"{"session_id":"s","permission_request_id":"r2","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[]}}"#.utf8))
        let fallback = await registry.registerAndWait(timeoutRequest, timeout: .milliseconds(20))
        let fallbackJSON = try JSONSerialization.jsonObject(with: fallback) as! [String: Any]
        let output = fallbackJSON["hookSpecificOutput"] as! [String: Any]
        XCTAssertEqual(output["permissionDecision"] as? String, "ask")
        let shutdownRequest = try ClaudePermissionRequest.decode(Data(#"{"session_id":"s","permission_request_id":"r3","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[]}}"#.utf8))
        let shutdownWaiter = Task { await registry.registerAndWait(shutdownRequest, timeout: .seconds(2)) }
        while await registry.pendingRequests().isEmpty { await Task.yield() }
        await registry.shutdown()
        let shutdownBody = await shutdownWaiter.value
        let shutdownJSON = try JSONSerialization.jsonObject(with: shutdownBody) as! [String: Any]
        XCTAssertEqual((shutdownJSON["hookSpecificOutput"] as? [String: Any])?["permissionDecision"] as? String, "ask")
        let remaining = await registry.pendingRequests()
        XCTAssertTrue(remaining.isEmpty)
    }

    func testClaudeBridgePermissionRequestBlocksUntilUIAnswer() async throws {
        let store = AgentSessionStore()
        let registry = ClaudePendingRequestRegistry()
        let router = BridgeRouter(token: "secret", store: store, claudeRegistry: registry, permissionTimeout: .seconds(2))
        let payload = Data(#"{"session_id":"s","permission_request_id":"bridge-r","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Ship?","multiSelect":false,"options":[{"label":"Yes"}]}]}}"#.utf8)
        let request = HTTPRequest(method: "POST", path: "/v1/claude/permission-request", headers: ["authorization":"Bearer secret"], body: payload)
        let responseTask = Task { await router.handle(request) }
        while await registry.pendingRequests().isEmpty { await Task.yield() }
        let sessions = await store.snapshot()
        XCTAssertEqual(sessions.first?.state, .needsInput)
        let pending = await registry.pendingRequests()[0]
        _ = await registry.resolve(requestID: pending.requestID, answers: [pending.questions[0].id: ["Yes"]])
        let response = await responseTask.value
        XCTAssertEqual(response.status, 200)
        let json = try JSONSerialization.jsonObject(with: response.body) as! [String: Any]
        XCTAssertNotNil(json["hookSpecificOutput"])
    }

    func testRealLoopbackServerRejectsWrongTokenAndCompletesPermissionRequest() async throws {
        let port = UInt16.random(in: 20_000...50_000)
        let store = AgentSessionStore()
        let registry = ClaudePendingRequestRegistry()
        let server = LocalHTTPServer(token: "secret", store: store, claudeRegistry: registry)
        try server.start(port: port)
        defer { server.stop() }
        try await Task.sleep(for: .milliseconds(100))

        var unauthorized = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/events")!)
        unauthorized.httpMethod = "POST"
        unauthorized.httpBody = Data("{}".utf8)
        let (_, unauthorizedResponse) = try await URLSession.shared.data(for: unauthorized)
        XCTAssertEqual((unauthorizedResponse as? HTTPURLResponse)?.statusCode, 401)

        let payload = Data(#"{"session_id":"socket-s","permission_request_id":"socket-r","hook_event_name":"PermissionRequest","tool_name":"AskUserQuestion","tool_input":{"questions":[{"question":"Continue?","multiSelect":false,"options":[{"label":"Yes"}]}]}}"#.utf8)
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/claude/permission-request")!)
        request.httpMethod = "POST"; request.httpBody = payload
        request.setValue("Bearer secret", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let socketTask = Task { try await URLSession.shared.data(for: request) }
        while await registry.pendingRequests().isEmpty { await Task.yield() }
        let pending = await registry.pendingRequests()[0]
        _ = await registry.resolve(requestID: pending.requestID, answers: [pending.questions[0].id: ["Yes"]])
        let (body, response) = try await socketTask.value
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("permissionDecision"))
    }

    func testCodexJSONRPCAndMapper() throws {
        let frame = try CodexJSONRPC.decode(Data(#"{"jsonrpc":"2.0","method":"turn/started","params":{"threadId":"t"}}"#.utf8))
        XCTAssertEqual(frame.method, "turn/started")
        XCTAssertEqual(CodexAppServerMapper.event(from: frame)?.kind, .workStarted)
        let initializeResponse = try CodexJSONRPC.decode(Data(#"{"id":1,"result":{"userAgent":"Codex Desktop/0.144.1"}}"#.utf8))
        XCTAssertEqual(initializeResponse.id, .number(1))
        XCTAssertNotNil(initializeResponse.result)
    }

    func testCodexExecutableResolverFindsLocalShimWithoutGUIPath() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let executable = home.appendingPathComponent(".local/bin/codex")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        defer { try? FileManager.default.removeItem(at: home) }

        let resolved = CodexExecutableResolver.resolve(
            environment: ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"],
            homeDirectory: home,
            systemCandidates: []
        )
        XCTAssertEqual(resolved?.standardizedFileURL, executable.standardizedFileURL)
    }

    func testCodexExecutableResolverPrefersExplicitPath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let executable = root.appendingPathComponent("custom-codex")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        defer { try? FileManager.default.removeItem(at: root) }

        let resolved = CodexExecutableResolver.resolve(
            environment: ["AGENT_MASCOT_CODEX_PATH": executable.path, "PATH": "/usr/bin:/bin"],
            homeDirectory: root,
            systemCandidates: []
        )
        XCTAssertEqual(resolved?.standardizedFileURL, executable.standardizedFileURL)
    }

    func testCodexExecutableResolverRepairsFinderPathForNVMShim() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nvmBin = home.appendingPathComponent(".nvm/versions/node/v24.6.0/bin")
        let nvmCodex = nvmBin.appendingPathComponent("codex")
        let node = nvmBin.appendingPathComponent("node")
        let localBin = home.appendingPathComponent(".local/bin")
        let localCodex = localBin.appendingPathComponent("codex")
        try FileManager.default.createDirectory(at: nvmBin, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: localBin, withIntermediateDirectories: true)
        try Data("#!/usr/bin/env node\n".utf8).write(to: nvmCodex)
        try Data("#!/bin/sh\n".utf8).write(to: node)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nvmCodex.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: node.path)
        try FileManager.default.createSymbolicLink(at: localCodex, withDestinationURL: nvmCodex)
        defer { try? FileManager.default.removeItem(at: home) }

        let minimalGUIEnvironment = ["HOME": home.path, "PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
        let resolved = try XCTUnwrap(CodexExecutableResolver.resolve(
            environment: minimalGUIEnvironment,
            homeDirectory: home,
            systemCandidates: []
        ))
        let launchEnvironment = CodexExecutableResolver.launchEnvironment(
            for: resolved,
            environment: minimalGUIEnvironment,
            homeDirectory: home
        )

        XCTAssertEqual(resolved.standardizedFileURL, localCodex.standardizedFileURL)
        let firstPath = try XCTUnwrap(launchEnvironment["PATH"]?.split(separator: ":").first.map(String.init))
        XCTAssertEqual(
            URL(fileURLWithPath: firstPath).resolvingSymlinksInPath(),
            nvmBin.resolvingSymlinksInPath()
        )
    }

    func testCodexThreadDiscoveryMapsLiveDesktopAndSubagentTurns() throws {
        let desktopFrame = try CodexJSONRPC.decode(Data(#"{"id":21,"result":{"thread":{"id":"desktop-thread","parentThreadId":null,"agentNickname":null,"name":"Fix session detection","cwd":"/tmp/desktop","updatedAt":1784032676,"turns":[{"status":"interrupted","completedAt":null}]}}}"#.utf8))
        let subagentFrame = try CodexJSONRPC.decode(Data(#"{"id":22,"result":{"thread":{"id":"subagent-thread","parentThreadId":"desktop-thread","agentNickname":"Popper","name":null,"cwd":"/tmp/worker","updatedAt":1784032696,"turns":[{"status":"inProgress","completedAt":null}]}}}"#.utf8))

        let desktop = try XCTUnwrap(CodexThreadDiscovery.event(fromThreadRead: desktopFrame))
        let subagent = try XCTUnwrap(CodexThreadDiscovery.event(fromThreadRead: subagentFrame))

        XCTAssertEqual(desktop.sessionID, "desktop-thread")
        XCTAssertEqual(desktop.kind, .workStarted)
        XCTAssertEqual(desktop.title, "Fix session detection")
        XCTAssertEqual(subagent.sessionID, "subagent-thread")
        XCTAssertEqual(subagent.kind, .workStarted)
        XCTAssertEqual(subagent.title, "Popper (Codex subagent)")
    }

    func testCodexThreadDiscoveryDoesNotCreateCompletedHistoricalSession() throws {
        let frame = try CodexJSONRPC.decode(Data(#"{"id":23,"result":{"thread":{"id":"finished","parentThreadId":null,"agentNickname":null,"name":"Finished task","cwd":"/tmp","updatedAt":1784032206,"turns":[{"status":"completed","completedAt":1784032206}]}}}"#.utf8))
        XCTAssertNil(CodexThreadDiscovery.event(fromThreadRead: frame, includeCompleted: false))
    }

    func testCodexThreadListDiscoveryExcludesRecentSubagents() throws {
        let frame = try CodexJSONRPC.decode(Data(#"{"id":24,"result":{"data":[{"id":"desktop","updatedAt":1784032696},{"id":"subagent","updatedAt":1784032692,"parentThreadId":"desktop"},{"id":"old","updatedAt":1784020000}]}}"#.utf8))
        let summaries = CodexThreadDiscovery.recentThreads(
            fromThreadList: frame,
            updatedAfter: Date(timeIntervalSince1970: 1784032600)
        )
        XCTAssertEqual(summaries.map(\.id), ["desktop"])

        let request = try JSONSerialization.jsonObject(with: CodexThreadDiscovery.threadListRequest(id: 25)) as! [String: Any]
        let params = request["params"] as! [String: Any]
        let sourceKinds = params["sourceKinds"] as! [String]
        XCTAssertTrue(sourceKinds.contains("vscode"))
        XCTAssertFalse(sourceKinds.contains("subAgent"))
        XCTAssertEqual(request["method"] as? String, "thread/list")
    }

    func testRealCodexControllerConnectsWhenEnabled() async throws {
        guard ProcessInfo.processInfo.environment["AGENT_MASCOT_RUN_CODEX_INTEGRATION"] == "1" else {
            throw XCTSkip("Set AGENT_MASCOT_RUN_CODEX_INTEGRATION=1 to exercise the installed Codex CLI")
        }
        let store = AgentSessionStore()
        let controller = CodexAppServerController(store: store)
        try await controller.start()
        if ProcessInfo.processInfo.environment["AGENT_MASCOT_EXPECT_ACTIVE_CODEX"] == "1" {
            let clock = ContinuousClock()
            let deadline = clock.now.advanced(by: .seconds(10))
            while clock.now < deadline,
                  !(await store.snapshot()).contains(where: { $0.agent == .codex && $0.state == .working }) {
                try await Task.sleep(for: .milliseconds(100))
            }
            let sessions = await store.snapshot()
            XCTAssertTrue(sessions.contains(where: { $0.agent == .codex && $0.state == .working }))
        }
        await controller.stop()
    }

    func testMascotAndQuestionForm() async {
        XCTAssertNotNil(AgentMascotResources.url(forResource: "MascotIdle", withExtension: "svg"))
        XCTAssertNotNil(AgentMascotResources.url(forResource: "frame-001", withExtension: "png"))
        XCTAssertNil(AgentMascotResources.url(forResource: "haland_out", withExtension: "mov"))
        XCTAssertEqual(DefaultMascotAssets().assetName(for: .error), "MascotNeedsInput")
        let q = AgentQuestion(id: "q", prompt: "Pick", choices: [AgentChoice(id: "1", label: "One", description: nil, value: "one")], allowsFreeText: false, isMultiSelect: false)
        let form = await QuestionFormModel(questions: [q])
        let before = await form.canSubmit
        XCTAssertFalse(before)
        await form.select(choiceID: "1", for: "q")
        let after = await form.canSubmit
        XCTAssertTrue(after)
    }
}
