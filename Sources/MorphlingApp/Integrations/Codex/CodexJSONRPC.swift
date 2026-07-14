import Foundation

enum JSONValue: Codable, Equatable, Sendable {
    case string(String), number(Double), bool(Bool), object([String: JSONValue]), array([JSONValue]), null
    init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); if c.decodeNil(){self = .null} else if let v=try? c.decode(String.self){self = .string(v)} else if let v=try? c.decode(Bool.self){self = .bool(v)} else if let v=try? c.decode(Double.self){self = .number(v)} else if let v=try? c.decode([String:JSONValue].self){self = .object(v)} else {self = .array(try c.decode([JSONValue].self))} }
    func encode(to encoder: Encoder) throws { var c=encoder.singleValueContainer(); switch self { case .string(let v):try c.encode(v); case .number(let v):try c.encode(v); case .bool(let v):try c.encode(v); case .object(let v):try c.encode(v); case .array(let v):try c.encode(v); case .null:try c.encodeNil() } }
    var string: String? { if case .string(let value)=self{return value}; return nil }
    var number: Double? { if case .number(let value)=self{return value}; return nil }
    var object: [String:JSONValue]? { if case .object(let value)=self{return value}; return nil }
    var array: [JSONValue]? { if case .array(let value)=self{return value}; return nil }
    var isNull: Bool { if case .null=self{return true}; return false }
}
enum JSONRPCID: Codable, Equatable, Sendable { case string(String), number(Int)
    init(from decoder: Decoder)throws{let c=try decoder.singleValueContainer(); if let v=try? c.decode(Int.self){self = .number(v)}else{self = .string(try c.decode(String.self))}}
    func encode(to encoder: Encoder)throws{var c=encoder.singleValueContainer(); switch self{case .string(let v):try c.encode(v);case .number(let v):try c.encode(v)}}
}
struct CodexJSONRPC: Codable, Sendable {
    let jsonrpc: String?; let id: JSONRPCID?; let method: String?; let params: JSONValue?; let result: JSONValue?; let error: JSONValue?
    static func decode(_ data: Data) throws -> Self { let value=try JSONDecoder().decode(Self.self,from:data); guard value.jsonrpc == nil || value.jsonrpc == "2.0", value.method != nil || value.id != nil else { throw CocoaError(.coderInvalidValue) }; return value }
    var paramsObject: [String:JSONValue] { params?.object ?? [:] }
}

enum CodexRequestError: Error { case unsupported, malformed, invalidAnswer }
struct CodexPendingRequest: Sendable {
    enum Kind: Sendable { case approval, userInput }
    let id: JSONRPCID; let method: String; let threadID: String; let questions: [AgentQuestion]; let kind: Kind
    init(frame: CodexJSONRPC) throws {
        guard let id=frame.id, let method=frame.method, let thread=frame.paramsObject["threadId"]?.string else { throw CodexRequestError.malformed }
        self.id=id; self.method=method; self.threadID=thread
        if method == "item/tool/requestUserInput" {
            guard case .array(let rawQuestions)? = frame.paramsObject["questions"] else { throw CodexRequestError.malformed }
            self.kind = .userInput
            self.questions = try rawQuestions.map { value in
                guard let q=value.object, let qid=q["id"]?.string, let prompt=q["question"]?.string else { throw CodexRequestError.malformed }
                let options: [AgentChoice]
                if case .array(let raw)?=q["options"] { options = try raw.map { guard let o=$0.object, let label=o["label"]?.string else {throw CodexRequestError.malformed}; return AgentChoice(id: label,label: label,description:o["description"]?.string,value:label) } } else { options=[] }
                let other = q["isOther"] == .bool(true)
                return AgentQuestion(id: qid,prompt:prompt,choices:options,allowsFreeText:other || options.isEmpty,isMultiSelect:false)
            }
        } else if ["item/commandExecution/requestApproval","item/fileChange/requestApproval"].contains(method) {
            self.kind = .approval
            let prompt=frame.paramsObject["command"]?.string ?? frame.paramsObject["reason"]?.string ?? "Approve requested changes?"
            let decisions: [String]
            if case .array(let values)?=frame.paramsObject["availableDecisions"] { decisions=values.compactMap(\.string) } else { decisions=["accept","decline","cancel"] }
            self.questions=[AgentQuestion(id:"\(thread):approval",prompt:prompt,choices:decisions.map{AgentChoice(id:$0,label:$0,description:nil,value:$0)},allowsFreeText:false,isMultiSelect:false)]
        } else { throw CodexRequestError.unsupported }
    }
    func response(answers: [String:[String]]) throws -> Data {
        let result: JSONValue
        switch kind {
        case .approval:
            guard let answer=answers[questions[0].id]?.first, questions[0].choices.contains(where:{$0.value == answer}) else { throw CodexRequestError.invalidAnswer }
            result = .object(["decision":.string(answer)])
        case .userInput:
            var mapped:[String:JSONValue]=[:]
            for q in questions { guard let values=answers[q.id], !values.isEmpty else {throw CodexRequestError.invalidAnswer}; mapped[q.id] = .object(["answers":.array(values.map(JSONValue.string))]) }
            result = .object(["answers":.object(mapped)])
        }
        return try JSONEncoder().encode(CodexJSONRPC(jsonrpc:"2.0",id:id,method:nil,params:nil,result:result,error:nil))
    }
}

struct CodexAppServerMapper {
    static func event(from frame: CodexJSONRPC) -> AgentEvent? {
        guard let method=frame.method else{return nil}; let p=frame.paramsObject
        let sid=p["threadId"]?.string ?? p["thread"]?.object?["id"]?.string
        guard let sid else{return nil}
        let kind:AgentEventKind
        switch method {case "thread/started":kind = .sessionStarted;case "turn/started","item/started","item/completed":kind = .workStarted;case "turn/completed":kind = .workStopped;case "thread/closed":kind = .sessionEnded;default:return nil}
        return AgentEvent(version:1,id:UUID(),agent:.codex,sessionID:sid,kind:kind,cwd:p["cwd"]?.string,pid:nil,title:"Codex",question:nil,occurredAt:.now)
    }
}

struct CodexThreadSummary: Equatable, Sendable {
    let id: String
    let updatedAt: Double
}

enum CodexThreadDiscovery {
    private static let sourceKinds = [
        "cli", "vscode", "exec", "appServer", "subAgent", "subAgentReview",
        "subAgentCompact", "subAgentThreadSpawn", "subAgentOther", "unknown"
    ]

    static func threadListRequest(id: Int) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "id": id,
            "method": "thread/list",
            "params": [
                "limit": 50,
                "sortKey": "updated_at",
                "sortDirection": "desc",
                "sourceKinds": sourceKinds
            ]
        ])
    }

    static func threadReadRequest(id: Int, threadID: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "id": id,
            "method": "thread/read",
            "params": ["threadId": threadID, "includeTurns": true]
        ])
    }

    static func recentThreads(fromThreadList frame: CodexJSONRPC, updatedAfter cutoff: Date) -> [CodexThreadSummary] {
        guard let rows = frame.result?.object?["data"]?.array else { return [] }
        return rows.compactMap { value in
            guard let row = value.object,
                  let id = row["id"]?.string,
                  let updatedAt = row["updatedAt"]?.number,
                  updatedAt >= cutoff.timeIntervalSince1970 else { return nil }
            return CodexThreadSummary(id: id, updatedAt: updatedAt)
        }
    }

    static func event(fromThreadRead frame: CodexJSONRPC, includeCompleted: Bool = true) -> AgentEvent? {
        guard let thread = frame.result?.object?["thread"]?.object,
              let threadID = thread["id"]?.string,
              let cwd = thread["cwd"]?.string,
              let updatedAt = thread["updatedAt"]?.number,
              let lastTurn = thread["turns"]?.array?.last?.object else { return nil }

        let status = lastTurn["status"]?.string
        let completedAt = lastTurn["completedAt"]
        let isComplete = (completedAt != nil && completedAt?.isNull == false)
            || status == "completed"
            || status == "failed"
        guard includeCompleted || !isComplete else { return nil }

        let isSubagent = thread["parentThreadId"]?.string != nil
        let kind: AgentEventKind
        if isComplete {
            kind = isSubagent ? .sessionEnded : .workStopped
        } else {
            kind = .workStarted
        }

        let title: String
        if isSubagent, let nickname = thread["agentNickname"]?.string, !nickname.isEmpty {
            title = "\(nickname) (Codex subagent)"
        } else if let name = thread["name"]?.string, !name.isEmpty {
            title = name
        } else {
            title = isSubagent ? "Codex subagent" : "Codex"
        }

        return AgentEvent(
            version: 1,
            id: UUID(),
            agent: .codex,
            sessionID: threadID,
            kind: kind,
            cwd: cwd,
            pid: nil,
            title: title,
            question: nil,
            occurredAt: Date(timeIntervalSince1970: updatedAt)
        )
    }
}
