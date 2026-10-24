import Foundation
import Darwin
@testable import OciStart

// Headless state-machine checks. The production app entry point is not linked.
// Every service and WebSocket operation below uses an in-memory fake.
private struct FixtureFailure: Error, CustomStringConvertible {
    let description: String
}

private func encoded(_ object: [String: Any]) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: object)
    guard let text = String(data: data, encoding: .utf8) else {
        throw FixtureFailure(description: "Could not encode fixture event")
    }
    return text
}

// Fail locally if a future refactor accidentally performs an HTTP operation.
// No authentication/bootstrap entry point is called by this fixture.
private final class RejectNetworkProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requestCount = 0
    static var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return requestCount
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requestCount += 1
        Self.lock.unlock()
        client?.urlProtocol(self, didFailWithError: NSError(
            domain: "AiChatFixture.NetworkForbidden", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Unexpected HTTP request in headless fixture"]))
    }
    override func stopLoading() {}
}

@MainActor
private final class FakeService: AiChatServing {
    var holdTenants = false
    var heldModelIds = Set<Int64>()
    private(set) var tenantRequests = 0
    private(set) var modelRequests: [Int64] = []
    private(set) var pendingTenants: CheckedContinuation<[AiChatTenantOption], Error>?
    private(set) var pendingModels: [Int64: CheckedContinuation<[AiChatModelOption], Error>] = [:]

    static func model(_ id: String = "model-1") -> AiChatModelOption {
        AiChatModelOption(id: id, displayName: id, version: "fixture")
    }
    static var tenants: [AiChatTenantOption] {
        [AiChatTenantOption(id: 1, name: "Fixture Tokyo", region: "ap-tokyo-1", supportAI: true),
         AiChatTenantOption(id: 2, name: "Fixture Singapore", region: "ap-singapore-1", supportAI: true)]
    }
    func listTenants() async throws -> [AiChatTenantOption] {
        tenantRequests += 1
        if holdTenants {
            return try await withCheckedThrowingContinuation { pendingTenants = $0 }
        }
        return Self.tenants
    }
    func models(tenantId: Int64) async throws -> [AiChatModelOption] {
        modelRequests.append(tenantId)
        if heldModelIds.contains(tenantId) {
            // Deliberately ignore Task cancellation: late HTTP completions must
            // still be rejected by the production request-generation checks.
            return try await withCheckedThrowingContinuation { storeModelContinuation($0, tenantId: tenantId) }
        }
        return [Self.model("model-\(tenantId)")]
    }
    private func storeModelContinuation(_ continuation: CheckedContinuation<[AiChatModelOption], Error>, tenantId: Int64) {
        pendingModels[tenantId] = continuation
    }
    func resolveModels(_ tenantId: Int64, _ models: [AiChatModelOption]) throws {
        guard let pending = pendingModels.removeValue(forKey: tenantId) else {
            throw FixtureFailure(description: "No pending models for tenant \(tenantId)")
        }
        pending.resume(returning: models)
    }
    func resolveTenants() throws {
        guard let pending = pendingTenants else {
            throw FixtureFailure(description: "No pending tenant request")
        }
        pendingTenants = nil
        pending.resume(returning: Self.tenants)
    }
    func rejectTenants() throws {
        guard let pending = pendingTenants else {
            throw FixtureFailure(description: "No pending tenant request to reject")
        }
        pendingTenants = nil
        pending.resume(throwing: FixtureFailure(description: "fixture tenant refresh rejected"))
    }
}

private final class FakeSocket: NativeWSConnection {
    var onState: ((NativeWSClient.State) -> Void)?
    var onText: ((String) -> Void)?
    var onBinary: ((Data) -> Void)?
    private(set) var urls: [URL] = []
    private(set) var sent: [[String: Any]] = []
    private(set) var disconnectCount = 0

    struct Callbacks {
        let state: ((NativeWSClient.State) -> Void)?
        let text: ((String) -> Void)?
        let binary: ((Data) -> Void)?
        func replayLateEvents() throws {
            state?(.open)
            text?(try encoded(["type": "init", "status": "success"]))
            text?(try encoded(["type": "chat", "role": "assistant", "isChunk": true, "message": "STALE"]))
            text?(try encoded(["type": "chat_end", "status": "success"]))
            text?(try encoded(["type": "error", "message": "stale error"]))
            binary?(Data("invalid stale payload".utf8))
            state?(.closed("stale close"))
        }
    }
    var callbacks: Callbacks { Callbacks(state: onState, text: onText, binary: onBinary) }
    func connect(url: URL) {
        urls.append(url)
        onState?(.connecting)
        // Only the test can deliver the actual successful handshake.
    }
    func sendJSON(_ object: [String: Any]) { sent.append(object) }
    func disconnect(reason: String?) {
        disconnectCount += 1
        onState?(.closed(reason))
    }
    func count(_ type: String) -> Int { sent.filter { $0["type"] as? String == type }.count }
    func event(_ object: [String: Any], binary: Bool = false) throws {
        let text = try encoded(object)
        if binary { onBinary?(Data(text.utf8)) }
        else { onText?(text) }
    }
    func open() { onState?(.open) }
    func close(_ reason: String?) { onState?(.closed(reason)) }
}

@MainActor
private enum Checks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw FixtureFailure(description: message) }
    }
    static func pause(_ seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }
    static func until(_ message: String, timeout: TimeInterval = 2,
                      _ predicate: () -> Bool) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        while !predicate() {
            try require(ProcessInfo.processInfo.systemUptime < deadline, "Timed out: \(message)")
            try await pause(0.01)
        }
    }
}

@MainActor
private final class Harness {
    let service: FakeService
    let socket = FakeSocket()
    let vm: AiChatViewModel

    init(service: FakeService? = nil, initialization: TimeInterval = 2,
         reply: TimeInterval = 2, heartbeat: TimeInterval = 0.04, silence: TimeInterval = 2) {
        let fakeService = service ?? FakeService()
        self.service = fakeService
        vm = AiChatViewModel(service: fakeService, ws: socket,
                             timeouts: AiChatTimeouts(initialization: initialization, reply: reply,
                                                      heartbeat: heartbeat, silence: silence))
    }
    func attempt() async throws {
        vm.start()
        try await Checks.until("first connection attempt") { self.socket.urls.count == 1 }
        try Checks.require(vm.isConnecting && !vm.isConnected, "Handshake must remain pending")
        try Checks.require(socket.urls.first?.path == "/ws/aiChat", "Wrong WebSocket endpoint")
        try Checks.require(socket.urls.first?.host == "ai-chat-fixture.invalid", "Unexpected endpoint host")
    }
    func acknowledge() throws {
        socket.open()
        try socket.event(["type": "init", "status": "success"])
        try Checks.require(vm.isConnected && !vm.isConnecting, "Successful init did not become ready")
    }
    func ready() async throws { try await attempt(); try acknowledge() }
    func send(_ text: String = "fixture question") throws {
        let before = socket.count("chat")
        vm.input = text
        vm.send()
        try Checks.require(vm.isSending && socket.count("chat") == before + 1, "Chat was not sent")
    }
    func chunk(_ text: String = "partial reply", binary: Bool = false) throws {
        try socket.event(["type": "chat", "role": "assistant", "isChunk": true, "message": text], binary: binary)
    }
    func failed(_ label: String) throws {
        try Checks.require(!vm.isSending && !vm.isConnected && !vm.isConnecting, "\(label): state still busy/connected")
        try Checks.require(vm.errorText?.isEmpty == false, "\(label): error was not exposed")
        try Checks.require(!vm.messages.contains(where: { $0.isStreaming }), "\(label): streaming flag survived")
    }
    func finish() { vm.teardown() }
}

@MainActor
private enum AiChatChecks {
    static func slowHandshake() async throws {
        let h = Harness()
        try await h.attempt()
        h.vm.input = "before handshake"
        h.vm.send()
        try await Checks.pause(0.35) // Longer than the previous fixed 250 ms init delay.
        try Checks.require(h.socket.sent.isEmpty, "Init/chat was sent before the actual handshake")
        h.socket.open()
        try Checks.require(h.socket.count("init") == 1 && !h.vm.isConnected, "Open must send init without becoming ready")
        let tenant = h.socket.sent.first?["tenant"] as? [String: Any]
        try Checks.require(tenant?["tenantId"] as? String == "1", "Init tenant ID must be a decimal string")
        try Checks.require(tenant?["modelId"] as? String == "model-1", "Init model ID did not match selection")
        h.vm.send()
        try Checks.require(h.socket.count("chat") == 0, "Chat escaped the init acknowledgement gate")
        try h.socket.event(["type": "init", "status": "success"])
        try Checks.require(h.vm.isConnected, "Init acknowledgement did not connect")
        h.finish()
    }

    static func chunksAndDuplicateSend() async throws {
        let h = Harness(reply: 0.2)
        try await h.ready()
        try h.send()
        h.vm.input = "duplicate Return key"
        h.vm.send()
        try Checks.require(h.socket.count("chat") == 1, "Repeated send produced duplicate requests")
        try Checks.require(h.vm.messages.filter { $0.role == .user }.count == 1, "Repeated send added a user message")
        try Checks.require(h.vm.input == "duplicate Return key", "Blocked send discarded the next draft")
        try h.socket.event(["type": "typing"])
        try h.chunk("Hello")
        try h.chunk(" 🌍", binary: true)
        try Checks.require(h.vm.messages.last?.text == "Hello 🌍" && h.vm.messages.last?.isStreaming == true,
                           "Text/binary chunks did not accumulate")
        try h.socket.event(["type": "chat_end", "status": "success"])
        try Checks.require(!h.vm.isSending && h.vm.isConnected && h.vm.messages.last?.isStreaming == false,
                           "chat_end did not finish the reply")
        try await Checks.pause(0.28)
        try Checks.require(h.vm.isConnected && h.vm.errorText == nil, "Completed reply left a live timeout")
        h.finish()
    }

    static func heartbeatCannotExtendReply() async throws {
        let h = Harness(reply: 0.2)
        try await h.ready()
        try h.send()
        var livePackets = 0
        for index in 0..<12 {
            if h.vm.isSending { livePackets += 1 }
            try h.socket.event(["type": index % 2 == 0 ? "heartbeat" : "pong", "status": "success"])
            try await Checks.pause(0.03)
        }
        try Checks.require(livePackets >= 3, "Fixture did not deliver heartbeats while waiting")
        try h.failed("Heartbeat-only reply")
        try Checks.require(h.vm.errorText?.contains("回复等待超时") == true, "Heartbeat-only wait did not hit reply timeout")
        try Checks.require(h.socket.count("ping") > 0, "Client heartbeat was not exercised")
        h.finish()
    }

    static func progressExtendsReply() async throws {
        let h = Harness(reply: 0.24)
        try await h.ready()
        try h.send()
        try await Checks.pause(0.14)
        try h.socket.event(["type": "typing"])
        try await Checks.pause(0.14)
        try Checks.require(h.vm.isSending && h.vm.errorText == nil, "Typing did not renew the reply deadline")
        try h.chunk("still progressing")
        try await Checks.pause(0.14)
        try Checks.require(h.vm.isSending, "A real chunk did not renew the reply deadline")
        try h.socket.event(["type": "chat_end", "status": "success"])
        h.finish()
    }

    static func partialFailure(_ kind: String) async throws {
        let h = Harness()
        try await h.ready()
        try h.send()
        try h.chunk()
        switch kind {
        case "error": try h.socket.event(["type": "error", "message": "fixture model error"])
        case "closed": h.socket.close("fixture disconnect")
        case "clean-close": h.socket.close(nil)
        case "failed-end": try h.socket.event(["type": "chat_end", "status": "error", "message": "fixture rejected end"])
        default: try h.socket.event(["type": "chat_end"])
        }
        try h.failed(kind)
        try Checks.require(h.vm.messages.last?.text == "partial reply", "\(kind): partial response was discarded")
        h.finish()
    }

    static func emptyEnd(_ whitespace: Bool) async throws {
        let h = Harness()
        try await h.ready()
        try h.send()
        if whitespace { try h.chunk(" \n\t ") }
        try h.socket.event(["type": "chat_end", "status": "success"])
        try h.failed("Empty successful end")
        try Checks.require(h.vm.errorText?.contains("未返回回复内容") == true, "Empty reply was treated as success")
        h.finish()
    }

    static func invalidInit() async throws {
        let h = Harness()
        try await h.attempt()
        h.socket.open()
        try h.socket.event(["type": "init"])
        try h.failed("Init missing status")
        h.finish()
    }

    static func initTimeout(_ open: Bool) async throws {
        let h = Harness(initialization: 0.15)
        try await h.attempt()
        let stale = h.socket.callbacks
        if open { h.socket.open() }
        try await Checks.until("initialization timeout") { !h.vm.isConnecting }
        try h.failed("Init timeout")
        try Checks.require(h.vm.errorText?.contains("准备超时") == true, "Wrong initialization timeout")
        let error = h.vm.errorText
        try stale.replayLateEvents()
        try Checks.require(h.vm.errorText == error && !h.vm.isConnected, "Late handshake revived a timed-out connection")
        h.finish()
    }

    static func ignoreLateCallbacks(_ teardown: Bool) async throws {
        let h = Harness()
        try await h.ready()
        try h.send()
        try h.chunk()
        let stale = h.socket.callbacks
        if teardown { h.vm.teardown() } else { h.vm.cancel() }
        let messages = h.vm.messages
        let status = h.vm.statusText
        let error = h.vm.errorText
        let count = h.socket.sent.count
        try stale.replayLateEvents()
        try await Checks.pause(0.06)
        try Checks.require(h.vm.messages == messages && h.vm.statusText == status && h.vm.errorText == error,
                           "Late callbacks mutated a cancelled/torn-down session")
        try Checks.require(h.socket.sent.count == count && !h.vm.isConnected && !h.vm.isSending,
                           "Late callback restarted a cancelled/torn-down session")
        try Checks.require(!h.vm.messages.contains(where: { $0.isStreaming }), "Cancellation left a streaming message")
        h.finish()
    }

    static func replacedConnectionIgnoresOldCallbacks() async throws {
        let h = Harness()
        try await h.ready()
        try h.send("old request")
        try h.chunk("old partial")
        let stale = h.socket.callbacks
        h.vm.cancel()
        h.vm.reconnect()
        try Checks.require(h.socket.urls.count == 2, "Reconnect did not create a replacement connection")
        try h.acknowledge()
        try h.send("new request")
        let messages = h.vm.messages
        let count = h.socket.sent.count
        try stale.replayLateEvents()
        try Checks.require(h.vm.isConnected && h.vm.isSending && h.vm.messages == messages && h.vm.errorText == nil,
                           "Old connection callbacks corrupted the replacement reply")
        try Checks.require(h.socket.sent.count == count, "Old open callback sent init on the replacement socket")
        try h.chunk("new answer")
        try h.socket.event(["type": "chat_end", "status": "success"])
        try Checks.require(h.vm.messages.last?.text == "new answer" && !h.vm.isSending, "Replacement reply failed")
        h.finish()
    }

    static func oldTenantModelsCannotWin() async throws {
        let service = FakeService()
        service.heldModelIds = [1, 2]
        let h = Harness(service: service)
        h.vm.start()
        try await Checks.until("old tenant model request") { service.pendingModels[1] != nil }
        h.vm.selectTenant(2)
        try await Checks.until("new tenant model request") { service.pendingModels[2] != nil }
        try service.resolveModels(2, [FakeService.model("new-model")])
        try await Checks.until("new tenant connection") { h.socket.urls.count == 1 }
        try h.acknowledge()
        try service.resolveModels(1, [FakeService.model("STALE-model")])
        try await Checks.pause(0.06)
        try Checks.require(h.vm.selectedTenantId == 2 && h.vm.selectedModelId == "new-model", "Old model response replaced the selection")
        try Checks.require(h.vm.models.map { $0.id } == ["new-model"] && h.socket.urls.count == 1 && h.vm.isConnected,
                           "Old model response replaced current models or reconnected")
        let tenant = h.socket.sent.first { $0["type"] as? String == "init" }?["tenant"] as? [String: Any]
        try Checks.require(tenant?["tenantId"] as? String == "2" && tenant?["modelId"] as? String == "new-model",
                           "New connection initialized the wrong tenant/model")
        h.finish()
    }

    static func cancelPendingLoad(_ tenants: Bool) async throws {
        let service = FakeService()
        service.holdTenants = tenants
        if !tenants { service.heldModelIds = [1] }
        let h = Harness(service: service)
        h.vm.start()
        try await Checks.until("held service request") {
            tenants ? service.pendingTenants != nil : service.pendingModels[1] != nil
        }
        h.vm.cancel()
        if tenants { try service.resolveTenants() }
        else { try service.resolveModels(1, [FakeService.model("late-model")]) }
        try await Checks.pause(0.06)
        try Checks.require(!h.vm.canCancel && h.socket.urls.isEmpty && h.vm.models.isEmpty,
                           "Cancelled service request started a connection or restored loading")
        try Checks.require(h.vm.statusText == "已取消" && h.vm.errorText == nil, "Late load changed cancellation feedback")
        h.finish()
    }

    static func cancelBeforeQueuedLoadsStart() async throws {
        let h = Harness()
        // No suspension is allowed between scheduling and cancellation: this
        // reproduces an old Task starting only after cancel invalidated it.
        h.vm.start()
        h.vm.cancel()
        try await Checks.pause(0.06)
        try Checks.require(h.service.tenantRequests == 0 && h.service.modelRequests.isEmpty,
                           "Cancelled start still invoked the service after yielding")
        try Checks.require(h.socket.urls.isEmpty && !h.vm.canCancel && h.vm.selectedTenantId == nil,
                           "Cancelled start restored a tenant, connection or loading state")
        try Checks.require(h.vm.statusText == "已取消" && h.vm.errorText == nil,
                           "Queued startup overwrote cancellation feedback")

        // With no tenant selected, reconnect queues another tenant-list load.
        h.vm.reconnect()
        h.vm.cancel()
        try await Checks.pause(0.06)
        try Checks.require(h.service.tenantRequests == 0 && h.socket.urls.isEmpty && !h.vm.canCancel,
                           "Cancelled reconnect still started its queued tenant request")
        try Checks.require(h.vm.statusText == "已取消" && h.vm.errorText == nil,
                           "Queued reconnect overwrote cancellation feedback")

        h.vm.refreshTenants()
        h.vm.cancel()
        try await Checks.pause(0.06)
        try Checks.require(h.service.tenantRequests == 0 && h.service.modelRequests.isEmpty && h.socket.urls.isEmpty,
                           "Cancelled explicit refresh escaped the queued-load generation gate")
        try Checks.require(!h.vm.canCancel && h.vm.statusText == "已取消" && h.vm.errorText == nil,
                           "Queued refresh restored loading or overwrote cancellation feedback")
        h.finish()
    }

    static func pendingTenantSwitchDuringListRefresh() async throws {
        let h = Harness()
        try await h.ready() // Tenant A = 1 is connected.
        h.service.holdTenants = true
        h.service.heldModelIds = [2]
        h.vm.refreshTenants()
        try await Checks.until("tenant-list refresh held in flight") { h.service.pendingTenants != nil }
        try Checks.require(h.vm.isConnected && h.vm.isLoadingTenants,
                           "Fixture did not keep tenant A ready during the held refresh")

        let navigation = NavigationState.shared
        let previousPage = navigation.selected
        let previousSection = navigation.expandedSection
        let disconnects = h.socket.disconnectCount
        let chats = h.socket.count("chat")
        navigation.openAiChat(tenantId: 2)
        h.vm.consumePendingTenant()
        // The old socket must detach synchronously, before B's model request
        // gets a chance to run and before another Return key can send to A.
        try Checks.require(h.vm.selectedTenantId == 2 && !h.vm.isConnected &&
                           h.socket.disconnectCount > disconnects,
                           "Pending tenant B did not immediately detach tenant A")
        h.vm.input = "must not go to tenant A"
        h.vm.send()
        try Checks.require(h.socket.count("chat") == chats && !h.vm.isSending,
                           "Send during tenant switch escaped through tenant A's socket")
        try await Checks.until("tenant B models while list refresh is still pending") {
            h.service.pendingModels[2] != nil
        }
        try Checks.require(h.service.pendingTenants != nil,
                           "Fixture lost the held list refresh before preparing tenant B")
        try h.service.resolveModels(2, [FakeService.model("model-for-B")])
        try await Checks.until("tenant B replacement connection") { h.socket.urls.count == 2 }
        try h.acknowledge()
        let initTenant = h.socket.sent.last { $0["type"] as? String == "init" }?["tenant"] as? [String: Any]
        try Checks.require(initTenant?["tenantId"] as? String == "2" &&
                           initTenant?["modelId"] as? String == "model-for-B",
                           "Replacement connection initialized tenant A instead of tenant B")

        try h.service.rejectTenants()
        try await Checks.until("old tenant-list refresh failure handled") { !h.vm.isLoadingTenants }
        try Checks.require(h.vm.selectedTenantId == 2 && h.vm.selectedModelId == "model-for-B" &&
                           h.vm.isConnected && h.socket.urls.count == 2 && h.socket.count("init") == 2,
                           "Failed list refresh restored tenant A or replaced tenant B's connection")
        try h.send("question for tenant B after refresh failure")
        let request = h.socket.sent.last { $0["type"] as? String == "chat" }
        try Checks.require(request?["tenantId"] as? String == "2" &&
                           request?["modelId"] as? String == "model-for-B" && h.socket.count("chat") == chats + 1,
                           "Failed list refresh routed a request back to tenant A")
        try h.chunk("answer from tenant B")
        try h.socket.event(["type": "chat_end", "status": "success"])
        h.finish()
        _ = navigation.takePendingAiChatTenantId()
        navigation.selected = previousPage
        navigation.expandedSection = previousSection
    }

    static func silenceTimeout() async throws {
        let h = Harness(heartbeat: 0.03, silence: 0.12)
        try await h.ready()
        try await Checks.until("silent connection timeout") { !h.vm.isConnected }
        try h.failed("Silent connection")
        try Checks.require(h.vm.errorText?.contains("长时间没有响应") == true, "Silence deadline did not expire")
        h.finish()
    }
}

@main
private enum AiChatFixture {
    @MainActor
    static func main() async {
        setbuf(stdout, nil)
        URLProtocol.registerClass(RejectNetworkProtocol.self)
        UserDefaults.standard.setVolatileDomain([
            "deploymentMode": "remote", "deploymentModeChosen": true,
            "serverURL": "https://ai-chat-fixture.invalid", "remoteServerURL": "https://ai-chat-fixture.invalid",
            "lastUsername": "AiChatFixture", "cloudProvider": 1
        ], forName: UserDefaults.argumentDomain)
        DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
            fputs("FAIL: Headless AI chat fixture exceeded 30 seconds\n", stderr)
            exit(124)
        }
        do {
            var count = 0
            func passed(_ label: String) { count += 1; print("PASS: \(label)") }
            try await AiChatChecks.slowHandshake(); passed("actual handshake gates init and send")
            try await AiChatChecks.chunksAndDuplicateSend(); passed("chunks/chat_end, duplicate Return and cancelled deadline")
            try await AiChatChecks.heartbeatCannotExtendReply(); passed("heartbeat/pong cannot extend reply timeout")
            try await AiChatChecks.progressExtendsReply(); passed("typing/chunks renew reply timeout")
            for kind in ["error", "closed", "clean-close", "failed-end", "missing-end-status"] {
                try await AiChatChecks.partialFailure(kind); passed("partial reply terminates on \(kind)")
            }
            try await AiChatChecks.emptyEnd(false); passed("empty chat_end fails")
            try await AiChatChecks.emptyEnd(true); passed("whitespace chat_end fails")
            try await AiChatChecks.invalidInit(); passed("init requires explicit success status")
            try await AiChatChecks.initTimeout(false); passed("slow handshake times out")
            try await AiChatChecks.initTimeout(true); passed("missing init acknowledgement times out")
            try await AiChatChecks.ignoreLateCallbacks(false); passed("cancel rejects late callbacks")
            try await AiChatChecks.ignoreLateCallbacks(true); passed("teardown rejects late callbacks")
            try await AiChatChecks.replacedConnectionIgnoresOldCallbacks(); passed("replacement connection rejects previous callbacks")
            try await AiChatChecks.oldTenantModelsCannotWin(); passed("old tenant model result cannot overwrite new tenant")
            try await AiChatChecks.cancelPendingLoad(true); passed("cancel rejects late tenant list")
            try await AiChatChecks.cancelPendingLoad(false); passed("cancel rejects late model list")
            try await AiChatChecks.cancelBeforeQueuedLoadsStart(); passed("same-turn cancellation invalidates queued start/reconnect/refresh")
            try await AiChatChecks.pendingTenantSwitchDuringListRefresh(); passed("pending tenant switch detaches old socket during failed list refresh")
            try await AiChatChecks.silenceTimeout(); passed("silent socket times out")
            try Checks.require(RejectNetworkProtocol.count == 0, "Unexpected real HTTP operation was attempted")
            print("PASS: \(count) headless AI chat checks; no HTTP/model requests")
            exit(0)
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}
