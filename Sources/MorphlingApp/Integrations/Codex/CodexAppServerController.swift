import Foundation

actor CodexAppServerController {
    private let store:AgentSessionStore
    private var process:Process?
    private var socket:URLSessionWebSocketTask?
    private var receiveTask:Task<Void,Never>?
    private(set) var port:UInt16=0
    var remoteCommand:String{"codex --remote ws://127.0.0.1:\(port)"}
    init(store:AgentSessionStore){self.store=store}
    func start()async throws {
        guard process == nil else{return}
        port=try Self.freePort()
        let p=Process();p.executableURL=URL(fileURLWithPath:"/usr/bin/env");p.arguments=["codex","app-server","--listen","ws://127.0.0.1:\(port)"];p.standardOutput=Pipe();p.standardError=Pipe();try p.run();process=p
        var last:Error?
        for _ in 0..<30 {do{try await connectAndInitialize();return}catch{last=error;try? await Task.sleep(for:.milliseconds(100))}}
        p.terminate();process=nil;throw last ?? URLError(.cannotConnectToHost)
    }
    private func connectAndInitialize()async throws {
        let socket=URLSession(configuration:.ephemeral).webSocketTask(with:URL(string:"ws://127.0.0.1:\(port)")!);socket.resume();self.socket=socket
        let initData=try JSONSerialization.data(withJSONObject:["jsonrpc":"2.0","id":1,"method":"initialize","params":["clientInfo":["name":"morphling","title":"Morphling","version":"0.1.0"],"capabilities":["experimentalApi":true]]])
        try await socket.send(.data(initData));let message=try await socket.receive();let data=try Self.data(message);let frame=try CodexJSONRPC.decode(data)
        guard frame.id == .number(1),frame.result != nil,frame.error == nil else{throw CocoaError(.coderInvalidValue)}
        receiveTask=Task{[weak self] in await self?.receiveLoop(socket)}
    }
    private func receiveLoop(_ socket:URLSessionWebSocketTask)async {while !Task.isCancelled {do{let frame=try CodexJSONRPC.decode(try Self.data(try await socket.receive()));if let event=CodexAppServerMapper.event(from:frame){await store.apply(event)}else if frame.id != nil,frame.method != nil{do{let pending=try CodexPendingRequest(frame:frame);await store.apply(AgentEvent(version:1,id:UUID(),agent:.codex,sessionID:pending.threadID,kind:.inputRequested,cwd:nil,pid:nil,title:"Codex",question:pending.questions.first,occurredAt:.now));let response=try pending.response(answers:[pending.questions[0].id:["decline"]]);try await socket.send(.data(response))}catch{}}}catch{break}}}
    func stop()async {receiveTask?.cancel();receiveTask=nil;socket?.cancel(with:.goingAway,reason:nil);socket=nil;if let p=process,p.isRunning{p.terminate();for _ in 0..<20 where p.isRunning{try? await Task.sleep(for:.milliseconds(50))};if p.isRunning{kill(p.processIdentifier,SIGKILL)}};process=nil}
    private static func data(_ message:URLSessionWebSocketTask.Message)throws->Data{switch message{case .data(let d):return d;case .string(let s):return Data(s.utf8);@unknown default:throw CocoaError(.coderInvalidValue)}}
    private static func freePort()throws->UInt16{let fd=Darwin.socket(AF_INET,SOCK_STREAM,0);guard fd>=0 else{throw POSIXError(.EADDRINUSE)};defer{close(fd)};var a=sockaddr_in();a.sin_len=UInt8(MemoryLayout.size(ofValue:a));a.sin_family=sa_family_t(AF_INET);a.sin_port=0;a.sin_addr=in_addr(s_addr:inet_addr("127.0.0.1"));var copy=a;let result=withUnsafePointer(to:&copy){$0.withMemoryRebound(to:sockaddr.self,capacity:1){Darwin.bind(fd,$0,socklen_t(MemoryLayout<sockaddr_in>.size))}};guard result==0 else{throw POSIXError(.EADDRINUSE)};var length=socklen_t(MemoryLayout<sockaddr_in>.size);getsockname(fd,withUnsafeMutablePointer(to:&copy){$0.withMemoryRebound(to:sockaddr.self,capacity:1){$0}},&length);return UInt16(bigEndian:copy.sin_port)}
}
