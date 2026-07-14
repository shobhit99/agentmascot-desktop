import AppKit
import Foundation

@MainActor protocol AgentHarnessNavigating {
    func open(session: AgentSession) throws
}

enum AgentHarnessNavigationError: LocalizedError, Equatable {
    case unsupportedProvider
    case invalidSessionURL
    case noHandler

    var errorDescription: String? {
        switch self {
        case .unsupportedProvider: "This agent provider cannot open sessions."
        case .invalidSessionURL: "This session does not have a valid navigation URL."
        case .noHandler: "No installed application can open this session."
        }
    }
}

@MainActor final class AgentHarnessNavigator: AgentHarnessNavigating {
    private let opener: (URL) -> Bool

    init(opener: @escaping (URL) -> Bool = { NSWorkspace.shared.open($0) }) {
        self.opener = opener
    }

    func open(session: AgentSession) throws {
        let url = try Self.url(for: session)
        guard opener(url) else { throw AgentHarnessNavigationError.noHandler }
    }

    static func url(for session: AgentSession) throws -> URL {
        var components = URLComponents()
        switch session.agent {
        case .codex:
            components.scheme = "codex"; components.host = "threads"
        case .claudeCode:
            components.scheme = "claude"; components.host = "claude.ai"
        }
        let prefix = session.agent == .codex ? "/" : "/code/"
        components.percentEncodedPath = prefix + session.providerSessionID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!.replacingOccurrences(of: "/", with: "%2F")
        guard let url = components.url else { throw AgentHarnessNavigationError.invalidSessionURL }
        return url
    }
}
