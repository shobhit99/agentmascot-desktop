import Foundation

protocol AvatarFileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func createDirectory(at url: URL) throws
    func copyItem(at source: URL, to destination: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func replaceItem(at destination: URL, with source: URL) throws
    func removeItemIfExists(at url: URL) throws
}

struct LocalAvatarFileSystem: AvatarFileSystem {
    func fileExists(at url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func createDirectory(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    func copyItem(at source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func replaceItem(at destination: URL, with source: URL) throws {
        _ = try FileManager.default.replaceItemAt(destination, withItemAt: source)
    }

    func removeItemIfExists(at url: URL) throws {
        guard fileExists(at: url) else { return }
        try FileManager.default.removeItem(at: url)
    }
}

struct CustomAvatarStore: Sendable {
    let directoryURL: URL
    let decoder: any APNGDecoding
    let fileSystem: any AvatarFileSystem

    init(
        directoryURL: URL,
        decoder: any APNGDecoding,
        fileSystem: any AvatarFileSystem = LocalAvatarFileSystem()
    ) {
        self.directoryURL = directoryURL
        self.decoder = decoder
        self.fileSystem = fileSystem
    }

    var avatarURL: URL {
        directoryURL.appendingPathComponent("avatar.apng", isDirectory: false)
    }

    func load() throws -> APNGAnimation? {
        guard fileSystem.fileExists(at: avatarURL) else { return nil }
        return try decoder.decode(url: avatarURL)
    }

    func importAvatar(from sourceURL: URL) throws -> APNGAnimation {
        _ = try decoder.decode(url: sourceURL)

        let stagingURL = directoryURL
            .appendingPathComponent(".avatar-\(UUID().uuidString)", isDirectory: false)
            .appendingPathExtension("apng")
        defer { try? fileSystem.removeItemIfExists(at: stagingURL) }

        do {
            try fileSystem.createDirectory(at: directoryURL)
            try fileSystem.copyItem(at: sourceURL, to: stagingURL)
            let stagedAnimation = try decoder.decode(url: stagingURL)

            if fileSystem.fileExists(at: avatarURL) {
                try fileSystem.replaceItem(at: avatarURL, with: stagingURL)
            } else {
                try fileSystem.moveItem(at: stagingURL, to: avatarURL)
            }
            return stagedAnimation
        } catch let error as AvatarImportError {
            throw error
        } catch {
            throw AvatarImportError.persistenceFailed
        }
    }
}
