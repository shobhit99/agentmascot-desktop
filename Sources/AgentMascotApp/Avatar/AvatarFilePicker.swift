import AppKit
import UniformTypeIdentifiers

@MainActor
protocol AvatarFilePicking {
    func chooseAPNG() -> URL?
}

@MainActor
struct SystemAvatarFilePicker: AvatarFilePicking {
    func chooseAPNG() -> URL? {
        let panel = NSOpenPanel()
        let apng = UTType(filenameExtension: "apng", conformingTo: .png)
        panel.allowedContentTypes = [.png] + [apng].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose Avatar"
        panel.message = "Choose one animated PNG for the floating mascot."

        return panel.runModal() == .OK ? panel.url : nil
    }
}
