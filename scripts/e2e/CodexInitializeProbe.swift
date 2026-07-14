import Foundation

@main struct Probe {
 static func main() async {
  guard CommandLine.arguments.count == 2,let url=URL(string:CommandLine.arguments[1]) else{exit(2)}
  let task=URLSession(configuration:.ephemeral).webSocketTask(with:url);task.resume()
  let timeout=Task { try? await Task.sleep(for:.seconds(2));task.cancel(with:.goingAway,reason:nil) }
  defer { timeout.cancel() }
  let payload=Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"agentmascot-e2e","title":"Agent Mascot E2E","version":"0.1.0"},"capabilities":{"experimentalApi":true}}}"#.utf8)
  do {try await task.send(.string(String(decoding:payload,as:UTF8.self)));let message=try await task.receive();let data:Data;switch message{case .data(let d):data=d;case .string(let s):data=Data(s.utf8);@unknown default:exit(3)};let root=try JSONSerialization.jsonObject(with:data) as? [String:Any];guard root?["id"] as? Int == 1,root?["result"] is [String:Any] else{exit(4)};task.cancel(with:.normalClosure,reason:nil);exit(0)}catch{exit(1)}
 }
}
