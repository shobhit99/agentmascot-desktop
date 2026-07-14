import UserNotifications
import Foundation

protocol NotificationSending: Sendable { func send(title: String, body: String) async }
struct SystemNotificationSender: NotificationSending { func send(title: String, body: String) async { let content = UNMutableNotificationContent(); content.title = title; content.body = body; try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) } }
actor AgentNotificationCoordinator { private var previous: [String:AgentSession] = [:]; let sender: any NotificationSending; init(sender: any NotificationSending) { self.sender = sender }
    func consume(_ sessions: [AgentSession]) async { for s in sessions { let old = previous[s.id]; if s.state == .working && old?.state != .working { await sender.send(title:"\(s.agent == .codex ? "Codex" : "Claude Code") started working", body:s.title) }; if s.state == .needsInput && old?.questions.first?.id != s.questions.first?.id { await sender.send(title:"Agent Mascot needs your input", body:s.questions.first?.prompt ?? s.title) } }; previous = Dictionary(uniqueKeysWithValues:sessions.map {($0.id,$0)}) }
}
