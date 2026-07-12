import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private let videoProvider = VideoFrameProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupWindow()
        videoProvider.start()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Mascot")
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Mascot", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func setupWindow() {
        let contentSize = NSSize(width: 380, height: 150)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isMovableByWindowBackground = true
        window.ignoresMouseEvents = false

        let hostingView = NSHostingView(rootView: MascotView().environmentObject(videoProvider))
        hostingView.frame = NSRect(origin: .zero, size: contentSize)
        window.contentView = hostingView

        if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - contentSize.width - 40
            let y = screen.visibleFrame.minY + 40
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.makeKeyAndOrderFront(nil)
    }
}
