import Foundation

enum LegacyInstallationIdentifiers {
    static let applicationSupportName = "Morphling"
    static let tokenName = "bridge.token"
    static let claudeMarker = "morphling-managed"
    static let codexMarker = "# morphling-managed"
    static let codexPathEnvironmentKey = "MORPHLING_CODEX_PATH"

    static func tokenURL(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(applicationSupportName).appendingPathComponent(tokenName)
    }

    static func claudeScriptURL(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(applicationSupportName).appendingPathComponent("Hooks/morphling-claude-event.sh")
    }

    static func codexScriptURL(in applicationSupport: URL) -> URL {
        applicationSupport.appendingPathComponent(applicationSupportName).appendingPathComponent("Hooks/morphling-codex-event.sh")
    }
}
