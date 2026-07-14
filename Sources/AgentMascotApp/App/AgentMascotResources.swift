import Foundation

enum AgentMascotResources {
    private static let bundleName = "AgentMascot_AgentMascotApp.bundle"

    static let bundle: Bundle? = {
        let executableDirectory = Bundle.main.executableURL?.deletingLastPathComponent()
        var optionalCandidates: [URL?] = [
            Bundle.main.bundleURL.appendingPathComponent(bundleName),
            Bundle.main.resourceURL?.appendingPathComponent(bundleName),
            executableDirectory?.appendingPathComponent(bundleName)
        ]
        var ancestor = executableDirectory
        for _ in 0..<5 {
            ancestor = ancestor?.deletingLastPathComponent()
            optionalCandidates.append(ancestor?.appendingPathComponent(bundleName))
        }
        let candidates: [URL] = optionalCandidates.compactMap { $0 }

        let locatedBundle = candidates.lazy.compactMap { Bundle(url: $0) }.first
#if DEBUG
        return locatedBundle ?? Bundle.module
#else
        return locatedBundle
#endif
    }()

    static func url(forResource name: String, withExtension extensionName: String) -> URL? {
        bundle?.url(forResource: name, withExtension: extensionName)
            ?? Bundle.main.url(forResource: name, withExtension: extensionName)
            ?? Bundle.main.url(forResource: name, withExtension: extensionName, subdirectory: "Mascots")
            ?? Bundle.main.url(forResource: name, withExtension: extensionName, subdirectory: "Mascots/HalandFramesV2")
    }
}
