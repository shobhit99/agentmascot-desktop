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
    func status()->CodexHookStatus { guard let text=try? String(contentsOf:configURL,encoding:.utf8),text.contains("# agent-mascot-managed"),text.contains(scriptURL.path) else{return .notInstalled};return .installed }
    func install(token:String,port:Int)throws {
        let fm=FileManager.default;try fm.createDirectory(at:configURL.deletingLastPathComponent(),withIntermediateDirectories:true);try fm.createDirectory(at:scriptURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        let script="#!/bin/sh\nset -eu\npayload=${1:-}\n[ -n \"$payload\" ] || exit 0\nexec curl -fsS --connect-timeout 1 --max-time 2 -H 'Authorization: Bearer \(token.replacingOccurrences(of:"'",with:"'\\''"))' -H 'Content-Type: application/json' --data-binary \"$payload\" http://127.0.0.1:\(port)/v1/events >/dev/null || true\n"
        try Data(script.utf8).write(to:scriptURL,options:.atomic);try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:scriptURL.path)
        var text=(try? String(contentsOf:configURL,encoding:.utf8)) ?? ""
        let withoutLegacy = Self.removingLegacyBlocks(from: text)
        if text.contains("# agent-mascot-managed") {
            if withoutLegacy != text { try Data(withoutLegacy.utf8).write(to: configURL, options: .atomic) }
            return
        }
        text = withoutLegacy
        if fm.fileExists(atPath:configURL.path){let backup=configURL.appendingPathExtension("agentmascot-backup");if !fm.fileExists(atPath:backup.path){try Data(text.utf8).write(to:backup,options:.atomic)}}
        if !text.isEmpty && !text.hasSuffix("\n"){text += "\n"}
        text += "# agent-mascot-managed\nnotify = [\"\(scriptURL.path.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\""))\"]\n"
        try Data(text.utf8).write(to:configURL,options:.atomic)
    }
    func hasLegacyEntry() -> Bool { (try? String(contentsOf: configURL, encoding: .utf8))?.contains(LegacyInstallationIdentifiers.codexMarker) == true }
    func uninstall()throws {
        guard let text = try? String(contentsOf:configURL,encoding:.utf8) else{return}
        let result = Self.removingManagedBlocks(from: text)
        try Data(result.utf8).write(to:configURL,options:.atomic)
    }
    static func removingManagedBlocks(from text: String) -> String {
        let lines = text.components(separatedBy:"\n"); var result:[String] = []; var skipNotify = false
        for line in lines {
            if line.contains("# agent-mascot-managed") || line.contains(LegacyInstallationIdentifiers.codexMarker) { skipNotify = true; continue }
            if skipNotify && line.trimmingCharacters(in:.whitespaces).hasPrefix("notify =") { skipNotify = false; continue }
            skipNotify = false; result.append(line)
        }
        return result.joined(separator:"\n")
    }
    static func removingLegacyBlocks(from text: String) -> String {
        let lines = text.components(separatedBy:"\n"); var result:[String] = []; var skipNotify = false
        for line in lines {
            if line.contains(LegacyInstallationIdentifiers.codexMarker) { skipNotify = true; continue }
            if skipNotify && line.trimmingCharacters(in:.whitespaces).hasPrefix("notify =") { skipNotify = false; continue }
            skipNotify = false; result.append(line)
        }
        return result.joined(separator:"\n")
    }
}
