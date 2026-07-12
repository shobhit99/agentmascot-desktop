@preconcurrency import Network
import Foundation

final class LocalHTTPServer: @unchecked Sendable {
    private var listener: NWListener?
    private let router: BridgeRouter
    private let queue = DispatchQueue(label: "morphling.loopback")
    private var connections: [UUID: NWConnection] = [:]

    init(token: String, store: AgentSessionStore, claudeRegistry: ClaudePendingRequestRegistry = ClaudePendingRequestRegistry()) {
        self.router = BridgeRouter(token: token, store: store, claudeRegistry: claudeRegistry)
    }

    func start(port: UInt16 = 7824) throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        listener.start(queue: queue)
    }

    func stop() { listener?.cancel(); listener = nil; queue.sync { connections.values.forEach { $0.cancel() }; connections.removeAll() } }

    private func accept(_ connection: NWConnection) {
        let id = UUID()
        guard connections.count < 64 else { connection.cancel(); return }
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in if case .cancelled = state { self?.connections[id] = nil } }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 10) { [weak self, weak connection] in guard let self, self.connections[id] != nil else { return }; connection?.cancel(); self.connections[id] = nil }
        receive(connection, Data())
    }

    private func receive(_ connection: NWConnection, _ accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 262_200) { [weak self] data, _, complete, error in
            guard let self else { return }
            var all = accumulated
            if let data { all.append(data) }
            guard all.count <= 272 * 1024 else { self.respond(connection, response: HTTPResponse(status: 413)); return }
            do {
                let request = try HTTPRequestParser().parse(all)
                Task {
                    let response = await self.router.handle(request)
                    self.respond(connection, response: response)
                }
            } catch HTTPParseError.incomplete where !complete && error == nil {
                self.receive(connection, all)
            } catch HTTPParseError.tooLarge {
                self.respond(connection, response: HTTPResponse(status: 413, body: Data(#"{"error":"too large"}"#.utf8)))
            } catch HTTPParseError.unsupportedMethod {
                self.respond(connection, response: HTTPResponse(status: 405))
            } catch {
                self.respond(connection, response: HTTPResponse(status: 400, body: Data(#"{"error":"bad request"}"#.utf8)))
            }
        }
    }

    private func respond(_ connection: NWConnection, response: HTTPResponse) {
        let reasons = [200: "OK", 202: "Accepted", 400: "Bad Request", 401: "Unauthorized", 404: "Not Found", 405: "Method Not Allowed", 413: "Payload Too Large"]
        let reason = reasons[response.status] ?? "Error"
        var data = Data("HTTP/1.1 \(response.status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(response.body.count)\r\nConnection: close\r\n\r\n".utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }
}

extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
