import AppKit
import SwiftUI

struct VideoMascotWidget: View {
    @Bindable var model: AppModel
    @State private var showingWorkingSessions = false

    private var status: String {
        switch model.aggregateState {
        case .working: "Working"
        case .needsInput: "Needs input"
        case .error: "Agent error"
        case .idle, .ended: model.mainSessions.isEmpty ? "Waiting for agent" : "Idle"
        }
    }

    private var accent: Color {
        switch model.aggregateState {
        case .working: .purple
        case .needsInput: .orange
        case .error: .red
        case .idle, .ended: .secondary
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            AnimatedMascotView()
                .frame(width: 360, height: 203)

            statusCapsule
                .padding(.bottom, 8)
        }
        .frame(width: 360, height: 220, alignment: .top)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Agent Mascot mascot, \(status)")
    }

    @ViewBuilder private var statusCapsule: some View {
        if model.aggregateState == .working {
            Button("Working · \(model.workingMainCount)") { showingWorkingSessions.toggle() }
                .buttonStyle(.plain)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
                .popover(isPresented: $showingWorkingSessions, arrowEdge: .bottom) {
                    WorkingSessionsPopover(sessions: model.workingMainSessions, open: model.open(session:), isPresented: $showingWorkingSessions)
                }
        } else {
            HStack(spacing: 7) {
                Circle().fill(accent).frame(width: 7, height: 7)
                Text(status).font(.system(size: 12, weight: .semibold))
                if !model.mainSessions.isEmpty {
                    Text("· \(model.mainSessions.count)")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }
}

private struct AnimatedMascotView: View {
    private let frames = Self.loadFrames()
    private let startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: frames.count < 2)) { timeline in
            if !frames.isEmpty {
                let elapsed = timeline.date.timeIntervalSince(startedAt)
                let index = Int(elapsed * 12.0) % frames.count
                Image(nsImage: frames[index])
                    .resizable()
                    .scaledToFit()
            }
        }
    }

    private static func loadFrames() -> [NSImage] {
        (1...49).compactMap { index in
            let name = String(format: "frame-%03d", index)
            let url = AgentMascotResources.url(
                forResource: name,
                withExtension: "png"
            )
            return url.flatMap(NSImage.init(contentsOf:))
        }
    }
}

@MainActor
final class MascotWindowController {
    private let panel: NSPanel

    init(model: AppModel) {
        let size = NSSize(width: 360, height: 220)
        panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.contentView = NSHostingView(rootView: VideoMascotWidget(model: model))
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.setFrameTopLeftPoint(Self.initialTopLeft(for: size))
    }

    func show() {
        panel.setFrameTopLeftPoint(Self.initialTopLeft(for: panel.frame.size))
        panel.orderFrontRegardless()
    }
    func close() { panel.close() }

    private static func initialTopLeft(for size: NSSize) -> NSPoint {
        guard let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.screens.first else {
            return .zero
        }
        let frame = screen.visibleFrame
        return NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - 36
        )
    }
}
