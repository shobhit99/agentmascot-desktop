import AppKit
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            StaticMascotView(state: model.aggregateState)
            Text("Morphling").font(.title.bold())
            Text(model.bridgeStatus).font(.caption).foregroundStyle(.secondary)

            if !model.pendingClaudeRequests.isEmpty {
                ScrollView {
                    ForEach(model.pendingClaudeRequests, id: \.requestID) { request in
                        ClaudeRequestView(request: request) { answers in
                            await model.submit(requestID: request.requestID, answers: answers)
                        } cancel: {
                            await model.cancel(requestID: request.requestID)
                        }
                    }
                }
            } else if model.sessions.isEmpty {
                ContentUnavailableView("No agent sessions", systemImage: "terminal")
            } else {
                List(model.sessions) { session in
                    VStack(alignment: .leading) {
                        HStack { Text(session.title).bold(); Spacer(); Text(session.state.rawValue) }
                        Text("\(session.agent.rawValue) • \(session.cwd)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Divider()
            HStack {
                Text("Claude hooks: \(String(describing: model.claudeHookStatus))").font(.caption)
                Text("Codex: \(model.codexStatus)").font(.caption)
                Spacer()
                if model.claudeHookStatus == .installed {
                    Button("Uninstall Hooks") { model.uninstallHooks() }
                } else {
                    Button("Install Claude Hooks") { model.installHooks() }
                }
            }
            Button("Quit Super Pocket") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
        .padding().frame(minWidth: 420, minHeight: 480)
    }
}

private struct ClaudeRequestView: View {
    let request: ClaudePermissionRequest
    let submit: ([String: [String]]) async -> Bool
    let cancel: () async -> Void
    @State private var selections: [String: Set<String>] = [:]
    @State private var text: [String: String] = [:]
    @State private var submitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Claude Code needs input", systemImage: "questionmark.circle.fill").font(.headline)
            ForEach(request.questions) { question in
                VStack(alignment: .leading, spacing: 6) {
                    Text(question.prompt).font(.body.bold())
                    ForEach(question.choices) { choice in
                        Toggle(isOn: binding(question, choice)) {
                            VStack(alignment: .leading) {
                                Text(choice.label)
                                if let description = choice.description { Text(description).font(.caption).foregroundStyle(.secondary) }
                            }
                        }.toggleStyle(.checkbox)
                    }
                    if question.allowsFreeText {
                        TextField("Other answer", text: Binding(get: { text[question.id] ?? "" }, set: { text[question.id] = $0 }))
                    }
                }
            }
            HStack {
                Button("Cancel") { Task { await cancel() } }
                Spacer()
                Button(submitting ? "Submitting…" : "Submit") {
                    submitting = true
                    Task { _ = await submit(answers()); await MainActor.run { submitting = false } }
                }.disabled(submitting || !canSubmit)
            }
        }.padding().background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }

    private func binding(_ question: AgentQuestion, _ choice: AgentChoice) -> Binding<Bool> {
        Binding(get: { selections[question.id]?.contains(choice.id) == true }, set: { selected in
            if question.isMultiSelect {
                var values = selections[question.id] ?? []
                if selected { values.insert(choice.id) } else { values.remove(choice.id) }
                selections[question.id] = values
            } else { selections[question.id] = selected ? [choice.id] : [] }
        })
    }
    private var canSubmit: Bool { request.questions.allSatisfy { !(selections[$0.id] ?? []).isEmpty || !(text[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    private func answers() -> [String: [String]] {
        Dictionary(uniqueKeysWithValues: request.questions.map { question in
            let values = question.choices.filter { selections[question.id]?.contains($0.id) == true }.map(\.value)
            let free = (text[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return (question.id, values.isEmpty && !free.isEmpty ? [free] : values)
        })
    }
}
