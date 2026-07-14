import SwiftUI

struct WorkingSessionsPopover: View {
    let sessions: [AgentSession]
    let open: (AgentSession) throws -> Void
    @Binding var isPresented: Bool
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Working sessions").font(.headline)
            ForEach(sessions) { session in
                Button {
                    do { try open(session); isPresented = false }
                    catch { self.error = error.localizedDescription }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title).lineLimit(1)
                        Text(session.agent == .codex ? "Codex" : "Claude Code").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityLabel("Open \(session.title) in \(session.agent == .codex ? "Codex" : "Claude Code")")
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
        }
        .padding()
        .frame(minWidth: 240)
        .onChange(of: sessions.isEmpty) { _, empty in if empty { isPresented = false } }
    }
}
