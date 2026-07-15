import SwiftUI
import AppKit

@main struct AgentMascotApplication: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    var body: some Scene {
        MenuBarExtra("Agent Mascot", systemImage: appDelegate.model.aggregateState == .needsInput ? "questionmark.circle.fill" : "sparkles") {
            RootView(model: appDelegate.model, presentation: .menuBar)
        }.menuBarExtraStyle(.window)
        Settings {
            RootView(model: appDelegate.model, presentation: .settings)
        }
    }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private var coordinator: AppCoordinator?
    private var mascotWindow: MascotWindowController?
    func applicationDidFinishLaunching(_ notification: Notification) {
        let coordinator = AppCoordinator(model: model)
        self.coordinator = coordinator
        let mascotWindow = MascotWindowController(model: model)
        self.mascotWindow = mascotWindow
        mascotWindow.show()
        Task { await coordinator.start(demoState: DemoState(arguments: ProcessInfo.processInfo.arguments)) }
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        mascotWindow?.close()
        guard let coordinator else { return .terminateNow }
        Task { await coordinator.stop(); sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
}

enum DemoState {
    case none, idle, working, needsInput
    init(arguments: [String]) {
        guard let index=arguments.firstIndex(of:"--demo-state"), arguments.indices.contains(index+1) else {self = .none; return}
        switch arguments[index+1] {case "idle":self = .idle;case "working":self = .working;case "needsInput":self = .needsInput;default:self = .none}
    }
}

@MainActor final class AppCoordinator {
    let model: AppModel
    let store = AgentSessionStore()
    let claudeRegistry = ClaudePendingRequestRegistry()
    let notifications = AgentNotificationCoordinator(sender: SystemNotificationSender())
    var server: LocalHTTPServer?
    var streamTask: Task<Void, Never>?
    var pendingTask: Task<Void, Never>?
    var codex: CodexAppServerController?
    private let avatarSelection: AvatarSelectionCoordinator
    private var isStarting = false
    private var lifecycleGeneration = 0
    init(model: AppModel) {
        self.model = model
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Agent Mascot")
        avatarSelection = AvatarSelectionCoordinator(
            model: model,
            store: CustomAvatarStore(
                directoryURL: support,
                decoder: ImageIOAPNGDecoder()
            ),
            picker: SystemAvatarFilePicker()
        )
    }

    func start(demoState: DemoState = .none) async {
        guard !isStarting, server == nil, streamTask == nil else { return }
        isStarting = true
        lifecycleGeneration &+= 1
        let lifecycle = lifecycleGeneration
        defer {
            if lifecycleGeneration == lifecycle {
                isStarting = false
            }
        }

        await avatarSelection.start()
        guard lifecycleGeneration == lifecycle else { return }
        if demoState != .none { await startDemo(demoState); return }
        do {
            let support=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Agent Mascot")
            let applicationSupport = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
            let token=try InstallationTokenStore(url:support.appendingPathComponent("bridge.token")).loadOrCreate(adoptingLegacyTokenAt: LegacyInstallationIdentifiers.tokenURL(in: applicationSupport))
            let home=FileManager.default.homeDirectoryForCurrentUser
            let claudeInstaller = ClaudeHookInstaller(settingsURL:home.appendingPathComponent(".claude/settings.json"),scriptURL:support.appendingPathComponent("Hooks/agent-mascot-claude-event.sh"))
            let codexInstaller = CodexHookInstaller(configURL:home.appendingPathComponent(".codex/config.toml"),scriptURL:support.appendingPathComponent("Hooks/agent-mascot-codex-event.sh"))
            let migration = AgentMascotMigration(claude: claudeInstaller, codex: codexInstaller, legacyClaudeScriptURL: LegacyInstallationIdentifiers.claudeScriptURL(in: applicationSupport), legacyCodexScriptURL: LegacyInstallationIdentifiers.codexScriptURL(in: applicationSupport))
            let migrationReport = migration.migrate(token: token, port: 7824)
            model.migrationWarning = migrationReport.warnings.first
            let server=LocalHTTPServer(token:token,store:store,claudeRegistry:claudeRegistry); try server.start(); self.server=server
            model.bridgeStatus="Bridge 127.0.0.1:7824"
            configureInstallers(support:support,token:token)
            let codex=CodexAppServerController(store:store); self.codex=codex
            model.codexStatus="Starting Codex app-server…"
            Task { [weak self] in
                do {
                    try await codex.start()
                    self?.model.codexStatus="Connected: \(await codex.remoteCommand)"
                } catch {
                    self?.model.codexStatus="Codex app-server error: \(error.localizedDescription)"
                }
            }
        } catch { model.bridgeStatus="Bridge error: \(error.localizedDescription)" }
        wireUI(); startStreams()
    }
    private func startDemo(_ state: DemoState) async {
        model.bridgeStatus="Demo mode — no services or config changes"
        let mapped:AgentSessionState = state == .working ? .working : state == .needsInput ? .needsInput : .idle
        let q=AgentQuestion(id:"demo:q",prompt:"Which direction should Agent Mascot take?",choices:[AgentChoice(id:"demo:a",label:"Continue",description:"Proceed with the current plan",value:"continue"),AgentChoice(id:"demo:b",label:"Pause",description:"Wait for more input",value:"pause")],allowsFreeText:true,isMultiSelect:false)
        model.sessions=[AgentSession(id:"demo",agent:.claudeCode,state:mapped,cwd:"/tmp/demo",title:"Demo session",pid:nil,questions:mapped == .needsInput ? [q]:[],updatedAt:.now)]
    }
    private func wireUI() {
        let navigator = AgentHarnessNavigator()
        model.openSession = { try navigator.open(session: $0) }
        model.answerClaude = { [weak self] requestID,answers in guard let self else{return false}; let pending=await self.claudeRegistry.pendingRequests().first{$0.requestID==requestID}; let ok=await self.claudeRegistry.resolve(requestID:requestID,answers:answers); if ok,let pending{for q in pending.questions{await self.store.answer(questionID:q.id,agent:.claudeCode,sessionID:pending.sessionID)}};return ok }
        model.cancelClaude = { [weak self] id in await self?.claudeRegistry.cancel(id:id) }
    }
    private func startStreams() {
        streamTask=Task { [weak self] in guard let self else{return}; let stream=await store.stream(); for await sessions in stream {guard !Task.isCancelled else{break};await notifications.consume(sessions);model.sessions=sessions} }
        pendingTask=Task { [weak self] in guard let self else{return};let stream=await claudeRegistry.stream();for await requests in stream{guard !Task.isCancelled else{break};model.pendingClaudeRequests=requests} }
    }
    private func configureInstallers(support:URL,token:String) {
        let home=FileManager.default.homeDirectoryForCurrentUser
        let claude=ClaudeHookInstaller(settingsURL:home.appendingPathComponent(".claude/settings.json"),scriptURL:support.appendingPathComponent("Hooks/agent-mascot-claude-event.sh"))
        model.claudeHookStatus=claude.status();model.installClaudeHooks={try claude.install(token:token,port:7824)};model.uninstallClaudeHooks={try claude.uninstall()}
        let codex=CodexHookInstaller(configURL:home.appendingPathComponent(".codex/config.toml"),scriptURL:support.appendingPathComponent("Hooks/agent-mascot-codex-event.sh"))
        model.codexHookStatus=codex.status();model.installCodexHooks={try codex.install(token:token,port:7824)};model.uninstallCodexHooks={try codex.uninstall()}
    }
    func stop() async {
        lifecycleGeneration &+= 1
        isStarting = false
        avatarSelection.stop()
        pendingTask?.cancel();streamTask?.cancel();pendingTask=nil;streamTask=nil
        await claudeRegistry.shutdown();await codex?.stop();codex=nil
        server?.stop();server=nil;model.answerClaude=nil;model.cancelClaude=nil
    }
    deinit { pendingTask?.cancel();streamTask?.cancel();server?.stop() }
}
