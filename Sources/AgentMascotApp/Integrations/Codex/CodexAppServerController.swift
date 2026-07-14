import Foundation

enum CodexAppServerError: LocalizedError, Equatable {
    case executableNotFound
    case serverExited(String)
    case readinessTimedOut
    case initializeTimedOut
    case invalidInitializeResponse

    var errorDescription: String? {
        switch self {
        case .executableNotFound:
            return "Codex CLI not found. Install Codex or set AGENT_MASCOT_CODEX_PATH to the executable."
        case .serverExited(let detail):
            return detail.isEmpty
                ? "Codex app-server exited before it became ready."
                : "Codex app-server exited before it became ready: \(detail)"
        case .readinessTimedOut:
            return "Codex app-server did not become ready within 10 seconds."
        case .initializeTimedOut:
            return "Codex app-server did not answer the initialize request within 10 seconds."
        case .invalidInitializeResponse:
            return "Codex app-server returned an invalid initialize response."
        }
    }
}

enum CodexExecutableResolver {
    static func resolve(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        systemCandidates: [URL] = defaultSystemCandidates
    ) -> URL? {
        var candidates: [URL] = []

        if let explicitPath = environment["AGENT_MASCOT_CODEX_PATH"], !explicitPath.isEmpty {
            candidates.append(URL(fileURLWithPath: explicitPath))
        } else if let legacyPath = environment["MORPHLING_CODEX_PATH"], !legacyPath.isEmpty {
            candidates.append(URL(fileURLWithPath: legacyPath))
        }

        if let path = environment["PATH"] {
            candidates.append(contentsOf: path
                .split(separator: ":")
                .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex") })
        }

        candidates.append(contentsOf: [
            homeDirectory.appendingPathComponent(".local/bin/codex"),
            homeDirectory.appendingPathComponent(".volta/bin/codex"),
            homeDirectory.appendingPathComponent(".bun/bin/codex"),
            homeDirectory.appendingPathComponent("Library/pnpm/codex")
        ])
        candidates.append(contentsOf: nvmCandidates(homeDirectory: homeDirectory))
        candidates.append(contentsOf: systemCandidates)

        return candidates.first(where: isExecutable)
    }

    private static let defaultSystemCandidates = [
        URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
        URL(fileURLWithPath: "/usr/local/bin/codex"),
        URL(fileURLWithPath: "/Applications/ChatGPT.app/Contents/Resources/codex")
    ]

    private static func nvmCandidates(homeDirectory: URL) -> [URL] {
        let versionsDirectory = homeDirectory.appendingPathComponent(".nvm/versions/node")
        let versions = (try? FileManager.default.contentsOfDirectory(
            at: versionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return versions
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
            .map { $0.appendingPathComponent("bin/codex") }
    }

    private static func isExecutable(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && !isDirectory.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path)
    }

    static func launchEnvironment(
        for executableURL: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        var result = environment
        guard let interpreter = envInterpreter(for: executableURL),
              executable(named: interpreter, in: result["PATH"]) == nil else { return result }

        var candidates = nvmInterpreterCandidates(named: interpreter, homeDirectory: homeDirectory)
        candidates.append(contentsOf: [
            homeDirectory.appendingPathComponent(".volta/bin/\(interpreter)"),
            homeDirectory.appendingPathComponent(".bun/bin/\(interpreter)"),
            URL(fileURLWithPath: "/opt/homebrew/bin/\(interpreter)"),
            URL(fileURLWithPath: "/usr/local/bin/\(interpreter)")
        ])
        guard let interpreterURL = candidates.first(where: isExecutable) else { return result }
        let directory = interpreterURL.deletingLastPathComponent().path
        let currentPath = result["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        result["PATH"] = "\(directory):\(currentPath)"
        return result
    }

    private static func envInterpreter(for executableURL: URL) -> String? {
        let resolvedURL = executableURL.resolvingSymlinksInPath()
        guard let handle = try? FileHandle(forReadingFrom: resolvedURL) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 256),
              let firstLine = String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline).first else { return nil }
        let parts = firstLine.split(separator: " ").map(String.init)
        guard parts.first == "#!/usr/bin/env" else { return nil }
        return parts.dropFirst().first(where: { !$0.hasPrefix("-") })
    }

    private static func executable(named name: String, in path: String?) -> URL? {
        path?.split(separator: ":")
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent(name) }
            .first(where: isExecutable)
    }

    private static func nvmInterpreterCandidates(named name: String, homeDirectory: URL) -> [URL] {
        let versionsDirectory = homeDirectory.appendingPathComponent(".nvm/versions/node")
        let versions = (try? FileManager.default.contentsOfDirectory(
            at: versionsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        return versions
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
            .map { $0.appendingPathComponent("bin/\(name)") }
    }
}

actor CodexAppServerController {
    private enum DiscoveryRequest {
        case list
        case read(CodexThreadSummary)
    }

    private let store: AgentSessionStore
    private var process: Process?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var discoveryTask: Task<Void, Never>?
    private var nextRequestID = 10
    private var discoveryRequests: [Int: DiscoveryRequest] = [:]
    private var processedThreadRevisions: [String: Double] = [:]
    private var discoveredThreadIDs: Set<String> = []
    private var serverLogURL: URL?
    private var serverLogHandle: FileHandle?
    private(set) var port: UInt16 = 0

    var remoteCommand: String { "codex --remote ws://127.0.0.1:\(port)" }

    init(store: AgentSessionStore) {
        self.store = store
    }

    func start() async throws {
        guard process == nil else { return }
        guard let executableURL = CodexExecutableResolver.resolve() else {
            throw CodexAppServerError.executableNotFound
        }

        port = try Self.freePort()
        let logURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentmascot-codex-app-server-\(UUID().uuidString).log")
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        let logHandle = try FileHandle(forWritingTo: logURL)
        serverLogURL = logURL
        serverLogHandle = logHandle

        let newProcess = Process()
        newProcess.executableURL = executableURL
        newProcess.arguments = ["app-server", "--listen", "ws://127.0.0.1:\(port)"]
        newProcess.environment = CodexExecutableResolver.launchEnvironment(for: executableURL)
        newProcess.standardOutput = logHandle
        newProcess.standardError = logHandle

        do {
            try newProcess.run()
            process = newProcess
            try await waitUntilReady(newProcess)
            try await connectAndInitialize()
        } catch {
            let mappedError: Error
            if !newProcess.isRunning {
                mappedError = CodexAppServerError.serverExited(serverLogExcerpt())
            } else {
                mappedError = error
            }
            await stop()
            throw mappedError
        }
    }

    private func waitUntilReady(_ process: Process) async throws {
        let readyURL = URL(string: "http://127.0.0.1:\(port)/readyz")!
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(10))
        while clock.now < deadline {
            guard process.isRunning else {
                throw CodexAppServerError.serverExited(serverLogExcerpt())
            }
            var request = URLRequest(url: readyURL)
            request.timeoutInterval = 0.2
            if let (_, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200 {
                return
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw CodexAppServerError.readinessTimedOut
    }

    private func connectAndInitialize() async throws {
        var request = URLRequest(url: URL(string: "ws://127.0.0.1:\(port)")!)
        request.timeoutInterval = 10
        let newSocket = URLSession(configuration: .ephemeral).webSocketTask(with: request)
        newSocket.resume()
        socket = newSocket

        let initData = try JSONSerialization.data(withJSONObject: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "clientInfo": ["name": "agentmascot", "title": "Agent Mascot", "version": "0.2.0"],
                "capabilities": ["experimentalApi": true]
            ]
        ])
        try await newSocket.send(.string(String(decoding: initData, as: UTF8.self)))
        let message = try await Self.receive(from: newSocket, timeout: .seconds(10))
        let frame = try CodexJSONRPC.decode(Self.data(message))
        guard frame.id == .number(1), frame.result != nil, frame.error == nil else {
            throw CodexAppServerError.invalidInitializeResponse
        }
        receiveTask = Task { [weak self] in await self?.receiveLoop(newSocket) }
        try await requestThreadList(on: newSocket)
        discoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                try? await self?.requestThreadList(on: newSocket)
            }
        }
    }

    private func receiveLoop(_ socket: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let frame = try CodexJSONRPC.decode(Self.data(try await socket.receive()))
                if try await handleDiscovery(frame, socket: socket) {
                    continue
                } else if let event = CodexAppServerMapper.event(from: frame) {
                    await store.apply(event)
                } else if frame.id != nil, frame.method != nil {
                    do {
                        let pending = try CodexPendingRequest(frame: frame)
                        await store.apply(AgentEvent(
                            version: 1,
                            id: UUID(),
                            agent: .codex,
                            sessionID: pending.threadID,
                            kind: .inputRequested,
                            cwd: nil,
                            pid: nil,
                            title: "Codex",
                            question: pending.questions.first,
                            occurredAt: .now
                        ))
                        let response = try pending.response(answers: [pending.questions[0].id: ["decline"]])
                        try await socket.send(.string(String(decoding: response, as: UTF8.self)))
                    } catch {}
                }
            } catch {
                break
            }
        }
    }

    private func requestThreadList(on socket: URLSessionWebSocketTask) async throws {
        guard !discoveryRequests.values.contains(where: {
            if case .list = $0 { return true }
            return false
        }) else { return }
        let requestID = takeRequestID()
        discoveryRequests[requestID] = .list
        do {
            let data = try CodexThreadDiscovery.threadListRequest(id: requestID)
            try await socket.send(.string(String(decoding: data, as: UTF8.self)))
        } catch {
            discoveryRequests[requestID] = nil
            throw error
        }
    }

    private func handleDiscovery(_ frame: CodexJSONRPC, socket: URLSessionWebSocketTask) async throws -> Bool {
        guard case .number(let requestID)? = frame.id,
              let request = discoveryRequests.removeValue(forKey: requestID) else { return false }

        switch request {
        case .list:
            let cutoff = Date().addingTimeInterval(-30 * 60)
            let summaries = CodexThreadDiscovery.recentThreads(fromThreadList: frame, updatedAfter: cutoff)
            for summary in summaries where processedThreadRevisions[summary.id] != summary.updatedAt {
                let alreadyPending = discoveryRequests.values.contains { pending in
                    if case .read(let existing) = pending { return existing.id == summary.id }
                    return false
                }
                guard !alreadyPending else { continue }
                let readID = takeRequestID()
                discoveryRequests[readID] = .read(summary)
                do {
                    let data = try CodexThreadDiscovery.threadReadRequest(id: readID, threadID: summary.id)
                    try await socket.send(.string(String(decoding: data, as: UTF8.self)))
                } catch {
                    discoveryRequests[readID] = nil
                    throw error
                }
            }
        case .read(let summary):
            processedThreadRevisions[summary.id] = summary.updatedAt
            let wasDiscovered = discoveredThreadIDs.contains(summary.id)
            guard let event = CodexThreadDiscovery.event(
                fromThreadRead: frame,
                includeCompleted: wasDiscovered
            ) else { return true }
            if event.kind == .workStarted {
                discoveredThreadIDs.insert(summary.id)
            } else if event.kind == .sessionEnded {
                discoveredThreadIDs.remove(summary.id)
            }
            await store.apply(event)
        }
        return true
    }

    private func takeRequestID() -> Int {
        defer { nextRequestID += 1 }
        return nextRequestID
    }

    func stop() async {
        discoveryTask?.cancel()
        discoveryTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        if let process, process.isRunning {
            process.terminate()
            for _ in 0..<20 where process.isRunning {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        process = nil
        discoveryRequests.removeAll()
        processedThreadRevisions.removeAll()
        discoveredThreadIDs.removeAll()
        try? serverLogHandle?.close()
        serverLogHandle = nil
        if let serverLogURL {
            try? FileManager.default.removeItem(at: serverLogURL)
        }
        serverLogURL = nil
    }

    private func serverLogExcerpt() -> String {
        try? serverLogHandle?.synchronize()
        guard let serverLogURL, let data = try? Data(contentsOf: serverLogURL), !data.isEmpty else {
            return ""
        }
        return String(decoding: data.suffix(1_024), as: UTF8.self)
            .split(whereSeparator: { $0.isNewline })
            .last
            .map(String.init) ?? ""
    }

    private static func receive(
        from socket: URLSessionWebSocketTask,
        timeout: Duration
    ) async throws -> URLSessionWebSocketTask.Message {
        try await withThrowingTaskGroup(of: URLSessionWebSocketTask.Message.self) { group in
            group.addTask { try await socket.receive() }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw CodexAppServerError.initializeTimedOut
            }
            guard let message = try await group.next() else {
                throw CodexAppServerError.initializeTimedOut
            }
            group.cancelAll()
            return message
        }
    }

    private static func data(_ message: URLSessionWebSocketTask.Message) throws -> Data {
        switch message {
        case .data(let data): return data
        case .string(let string): return Data(string.utf8)
        @unknown default: throw CocoaError(.coderInvalidValue)
        }
    }

    private static func freePort() throws -> UInt16 {
        let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EADDRINUSE) }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout.size(ofValue: address))
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        var copy = address
        let result = withUnsafePointer(to: &copy) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw POSIXError(.EADDRINUSE) }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        getsockname(descriptor, withUnsafeMutablePointer(to: &copy) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { $0 }
        }, &length)
        return UInt16(bigEndian: copy.sin_port)
    }
}
