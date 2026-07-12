import Foundation

struct CodexHookPayload: Decodable, Sendable {
    let type: String; let threadID: String; let turnID: String?; let cwd: String?; let lastAssistantMessage: String?
    enum CodingKeys:String,CodingKey {case type;case threadID="thread-id";case turnID="turn-id";case cwd;case lastAssistantMessage="last-assistant-message"}
}
struct CodexHookMapper {
    static func map(_ data:Data)throws->AgentEvent {
        let p=try JSONDecoder().decode(CodexHookPayload.self,from:data)
        let kind:AgentEventKind
        switch p.type {case "agent-turn-complete":kind = .workStopped;case "session-start":kind = .sessionStarted;case "turn-start":kind = .workStarted;default:throw CocoaError(.coderInvalidValue)}
        return AgentEvent(version:1,id:UUID(),agent:.codex,sessionID:p.threadID,kind:kind,cwd:p.cwd,pid:nil,title:"Codex (status only)",question:nil,occurredAt:.now)
    }
}

enum CodexHookStatus:String,Sendable {case installed,notInstalled}
struct CodexHookInstaller:Sendable {
    let configURL:URL;let scriptURL:URL
    func status()->CodexHookStatus { guard let text=try? String(contentsOf:configURL,encoding:.utf8),text.contains("# morphling-managed"),text.contains(scriptURL.path) else{return .notInstalled};return .installed }
    func install(token:String,port:Int)throws {
        let fm=FileManager.default;try fm.createDirectory(at:configURL.deletingLastPathComponent(),withIntermediateDirectories:true);try fm.createDirectory(at:scriptURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        let script="#!/bin/sh\nset -eu\npayload=${1:-}\n[ -n \"$payload\" ] || exit 0\nexec curl -fsS --connect-timeout 1 --max-time 2 -H 'Authorization: Bearer \(token.replacingOccurrences(of:"'",with:"'\\''"))' -H 'Content-Type: application/json' --data-binary \"$payload\" http://127.0.0.1:\(port)/v1/events >/dev/null || true\n"
        try Data(script.utf8).write(to:scriptURL,options:.atomic);try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:scriptURL.path)
        var text=(try? String(contentsOf:configURL,encoding:.utf8)) ?? ""
        guard !text.contains("# morphling-managed") else{return}
        if fm.fileExists(atPath:configURL.path){let backup=configURL.appendingPathExtension("morphling-backup");if !fm.fileExists(atPath:backup.path){try Data(text.utf8).write(to:backup,options:.atomic)}}
        if !text.isEmpty && !text.hasSuffix("\n"){text += "\n"}
        text += "# morphling-managed\nnotify = [\"\(scriptURL.path.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\""))\"]\n"
        try Data(text.utf8).write(to:configURL,options:.atomic)
    }
    func uninstall()throws {guard var text=try? String(contentsOf:configURL,encoding:.utf8) else{return};let lines=text.components(separatedBy:"\n");text=lines.filter{!$0.contains("morphling-managed") && !($0.trimmingCharacters(in:.whitespaces).hasPrefix("notify =") && $0.contains(scriptURL.path))}.joined(separator:"\n");try Data(text.utf8).write(to:configURL,options:.atomic)}
}
