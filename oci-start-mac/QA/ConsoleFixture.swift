import Foundation
import JavaScriptCore
@testable import OciStart

/// Execute the production canvas script against local DOM/timer/RFB fakes.
/// Only dynamic import is replaced. No browser, URLSession, WebSocket, CDN or cloud request runs.
/// Link alongside a QA main after the Debug build; call consoleOfflineChecks().
enum ConsoleFixtureFailure: Error, LocalizedError {
    case failed(String)
    var errorDescription: String? {
        switch self { case .failed(let message): return "Console fixture: " + message }
    }
}

func consoleOfflineChecks() throws -> [String] {
    guard let context = JSContext() else { throw ConsoleFixtureFailure.failed("JavaScriptCore unavailable") }
    var exception: String?
    var passed: [String] = []
    context.exceptionHandler = { _, value in exception = value?.toString() }
    func evaluate(_ script: String) throws -> JSValue? {
        exception = nil
        let value = context.evaluateScript(script)
        if let error = exception { throw ConsoleFixtureFailure.failed(error) }
        return value
    }
    func check(_ name: String, _ expression: String) throws {
        guard try evaluate(expression)?.toBool() == true else { throw ConsoleFixtureFailure.failed(name) }
        passed.append(name)
    }
    func settle() throws {
        for _ in 0..<16 { _ = try evaluate("void 0") }
    }
    func command(_ kind: String, epoch: String = "e1", _ fields: [String: Any] = [:]) throws -> Bool {
        var object = fields
        object["pageID"] = "fixture"
        object["kind"] = kind
        object["epoch"] = epoch
        let data = try JSONSerialization.data(withJSONObject: object)
        guard let json = String(data: data, encoding: .utf8) else { return false }
        return try evaluate("window.__nativeConsole.receive(\(json))")?.toBool() == true
    }

    _ = try evaluate(#"""
    var __events=[],__rfbs=[],__imports=0,__timers=new Map(),__frames=new Map(),__id=0;
    var __handlers={},__mounts=[],__resizeDisposed=false;
    var window=globalThis,location={protocol:'http:'};
    window.webkit={messageHandlers:{vnc:{postMessage:event=>__events.push(event)}}};
    window.addEventListener=()=>{};window.removeEventListener=()=>{};
    var __host={append(target){__mounts.push(target);},addEventListener(name,callback){__handlers[name]=callback;}};
    var document={
      body:{style:{backgroundColor:'#fafafa'}},
      getElementById(){return __host;},
      createElement(){return{removed:false,remove(){this.removed=true;},querySelector(){return{setAttribute(){}};}};}
    };
    function getComputedStyle(){return{backgroundColor:'#fafafa'};}
    function ResizeObserver(){this.observe=()=>{};this.disconnect=()=>{__resizeDisposed=true;};}
    function setTimeout(callback){const id=++__id;__timers.set(id,callback);return id;}
    function clearTimeout(id){__timers.delete(id);}
    function requestAnimationFrame(callback){const id=++__id;__frames.set(id,callback);return id;}
    function cancelAnimationFrame(id){__frames.delete(id);}
    function __frame(){const item=__frames.entries().next().value;if(item){__frames.delete(item[0]);item[1]();}}
    function __drain(){for(let i=0;i<2000&&__frames.size;i++)__frame();}
    function URL(value){
      const match=/^(wss?:)\/\/([^/#]+)([^#]*)(#.*)?$/.exec(value);
      if(!match)throw Error('offline invalid URL');
      this.protocol=match[1];this.hostname=match[2];
      this.username=match[2].includes('@')?'forbidden':'';
      this.password='';this.hash=match[4]||'';
    }
    class FixtureRFB{
      constructor(target,url){
        this.target=target;this.url=url;this.listeners=new Map();
        this.keys=[];this.ctrl=0;this.credentials=[];this.closes=0;
        this.viewOnly=false;this.scaleViewport=false;this.resizeSession=false;__rfbs.push(this);
      }
      addEventListener(name,callback){if(!this.listeners.has(name))this.listeners.set(name,new Set());this.listeners.get(name).add(callback);}
      removeEventListener(name,callback){this.listeners.get(name)?.delete(callback);}
      emit(name,detail={}){for(const callback of [...(this.listeners.get(name)||[])])callback({detail});}
      disconnect(){this.closes++;}
      focus(){}
      blur(){}
      sendCredentials(value){this.credentials.push({...value});}
      sendCtrlAltDel(){if(this.viewOnly)throw Error('readonly');this.ctrl++;}
      sendKey(key,code,down){if(this.viewOnly)throw Error('readonly');this.keys.push({key,code,down});}
      clipboardPasteFrom(){throw Error('Send text must not call clipboardPasteFrom');}
    }
    function __offlineImport(url){
      if(url!=='https://cdn.jsdelivr.net/npm/@novnc/novnc@1.4.0/core/rfb.js')throw Error('unexpected runtime');
      __imports++;return Promise.resolve({default:FixtureRFB});
    }
    """#)

    let html = InstanceNoVNCHTML.page(pageID: "fixture")
    guard let start = html.range(of: "<script>"), let end = html.range(of: "</script>", range: start.upperBound..<html.endIndex) else {
        throw ConsoleFixtureFailure.failed("Missing production script")
    }
    let production = String(html[start.upperBound..<end.lowerBound])
    guard production.components(separatedBy: "import(moduleURL)").count == 2 else {
        throw ConsoleFixtureFailure.failed("Runtime loader seam changed; update the fixture explicitly")
    }
    _ = try evaluate(production.replacingOccurrences(of: "import(moduleURL)", with: "__offlineImport(moduleURL)"))
    try check("Mounting does not import the engine or open RFB", "__imports===0&&__rfbs.length===0")
    try check("Readiness carries the page identity", "__events.length===1&&__events[0].kind==='bridgeReady'&&__events[0].pageID==='fixture'")
    try check("Other page identities cannot issue commands", "window.__nativeConsole.receive({pageID:'other',kind:'prepare'})===false&&__imports===0")
    guard try command("prepare", ["requestID":"prepare-1"]) else { throw ConsoleFixtureFailure.failed("prepare rejected") }
    try settle()
    try check("Preparation loads only the pinned engine", "__imports===1&&__rfbs.length===0&&__events.some(e=>e.kind==='runtimeReady'&&e.requestID==='prepare-1')")
    guard try command("connect", ["url":"ws://fixture.invalid:19000/","scale":false,"viewOnly":false,"active":true]) else {
        throw ConsoleFixtureFailure.failed("connect rejected")
    }
    try settle()
    try check("RFB construction is not connection success", "__rfbs.length===1&&!__events.some(e=>e.kind==='connected')")
    guard try command("ctrlAltDel") == false else { throw ConsoleFixtureFailure.failed("Input before RFB connect") }
    _ = try evaluate("__rfbs[0].emit('connect')")
    guard try command("ctrlAltDel") else { throw ConsoleFixtureFailure.failed("Connected CtrlAltDel rejected") }
    try check("CtrlAltDel uses the public RFB API", "__rfbs[0].ctrl===1")
    guard try command("presentation", ["scale":true,"viewOnly":true,"active":true]) else { throw ConsoleFixtureFailure.failed("presentation rejected") }
    try check("Fit scales locally without resizing the guest", "__rfbs[0].scaleViewport===true&&__rfbs[0].resizeSession===false")
    guard try command("ctrlAltDel") == false, try command("text", ["requestID":"ro","text":"blocked"]) == false else {
        throw ConsoleFixtureFailure.failed("Readonly input accepted")
    }
    passed.append("Readonly blocks shortcut and text input")
    _ = try command("presentation", ["scale":false,"viewOnly":false,"active":false])
    guard try command("ctrlAltDel") == false else { throw ConsoleFixtureFailure.failed("Modal leaked physical input") }
    guard try command("text", ["requestID":"unicode","text":"A\r\n你🙂"]) else { throw ConsoleFixtureFailure.failed("Unicode text rejected") }
    _ = try evaluate("__drain()")
    try check("Unicode keysyms, keyup pairs and single CRLF return",
              "JSON.stringify(__rfbs[0].keys.map(k=>[k.key,k.down]))===JSON.stringify([[65,true],[65,false],[65293,true],[65293,false],[0x01004f60,true],[0x01004f60,false],[0x0101f642,true],[0x0101f642,false]])&&__rfbs[0].keys.every(k=>k.code===undefined)")
    try check("Text restores paused input and reports a receipt",
              "__rfbs[0].viewOnly===true&&__events.some(e=>e.kind==='textFinished'&&e.requestID==='unicode'&&e.sent===true)")
    _ = try evaluate("var __before=__rfbs[0].keys.length")
    guard try command("text", ["requestID":"bad-control","text":"prefix\u{0000}suffix"]) == false else {
        throw ConsoleFixtureFailure.failed("Unsupported control text accepted")
    }
    try check("Whole text is validated before any prefix is sent", "__rfbs[0].keys.length===__before")
    guard try command("text", ["requestID":"oversize","text":String(repeating:"x",count:65537)]) == false else {
        throw ConsoleFixtureFailure.failed("Oversized text accepted")
    }
    passed.append("UTF16 text limit is enforced")
    let literal = "\";globalThis.__injected=1;//\n$(never-execute)</script>\u{0060}"
    guard try command("text", ["requestID":"literal","text":literal]) else { throw ConsoleFixtureFailure.failed("Literal text rejected") }
    _ = try evaluate("__drain()")
    try check("Script delimiters and shell syntax remain text", "typeof __injected==='undefined'&&__events.some(e=>e.kind==='textFinished'&&e.requestID==='literal'&&e.sent===true)")
    _ = try evaluate("__before=__rfbs[0].keys.length")
    guard try command("text", ["requestID":"cancel","text":String(repeating:"x",count:130)]) else { throw ConsoleFixtureFailure.failed("Batch rejected") }
    _ = try evaluate("__frame()")
    try check("Each frame sends at most 64 key pairs", "__rfbs[0].keys.length===__before+128")
    _ = try command("cancelText")
    _ = try evaluate("__drain()")
    try check("Cancel stops remaining batches and reports a partial result",
              "__rfbs[0].keys.length===__before+128&&__events.filter(e=>e.kind==='textFinished'&&e.requestID==='cancel'&&e.sent===false).length===1")
    _ = try command("text", ["requestID":"replaced","text":String(repeating:"y",count:130)])
    _ = try evaluate("__frame();__before=__rfbs[0].keys.length")
    _ = try command("connect", epoch:"e2", ["url":"ws://fixture.invalid:19000/","scale":false,"viewOnly":false,"active":true])
    try settle()
    _ = try evaluate("__drain();__rfbs[0].emit('connect')")
    try check("Recreation discards old targets, callbacks and pending text",
              "__rfbs.length===2&&__rfbs[0].target.removed&&__rfbs[0].closes===1&&__rfbs[0].keys.length===__before&&!__events.some(e=>e.kind==='connected'&&e.epoch==='e2')")
    guard try command("ctrlAltDel", epoch:"e1") == false else { throw ConsoleFixtureFailure.failed("Old epoch accepted") }
    _ = try evaluate("__rfbs[1].emit('credentialsrequired',{types:['username','password','target']})")
    guard try command("credentials", epoch:"e2", ["values":["username":"fixture-user","password":"fixture-password","target":"fixture-target"]]) else {
        throw ConsoleFixtureFailure.failed("Requested credentials rejected")
    }
    guard try command("credentials", epoch:"e2", ["values":["password":"duplicate"]]) == false else {
        throw ConsoleFixtureFailure.failed("Duplicate credentials accepted")
    }
    try check("Requested credential fields are submitted once", "__rfbs[1].credentials.length===1&&__rfbs[1].credentials[0].target==='fixture-target'")
    _ = try evaluate("__rfbs[1].emit('connect')")
    _ = try command("touch", epoch:"e2", ["deadline":0.1])
    _ = try evaluate("var __prevented=false,__stopped=false;__handlers.keydown({preventDefault(){__prevented=true;},stopImmediatePropagation(){__stopped=true;}})")
    try check("First input after idle expiry is blocked before RFB",
              "__prevented&&__stopped&&__rfbs[1].closes===1&&__events.some(e=>e.kind==='idleExpired'&&e.epoch==='e2')")
    _ = try evaluate("window.__nativeConsole.dispose()")
    try check("Disposal rejects work and removes RFB listeners",
              "window.__nativeConsole.receive({pageID:'fixture',kind:'prepare',requestID:'late'})===false&&__resizeDisposed&&__rfbs.every(r=>[...r.listeners.values()].every(set=>set.size===0))")

    let bridge = ConsoleCanvasBridge()
    var deliveries = 0
    bridge.onEvent = { _ in deliveries += 1 }
    bridge.receive(["pageID":"other","kind":"connected"])
    guard deliveries == 0 else { throw ConsoleFixtureFailure.failed("Native bridge accepted another page") }
    bridge.receive(["pageID":bridge.pageID,"kind":"connected"])
    guard deliveries == 1 else { throw ConsoleFixtureFailure.failed("Native bridge rejected its own page") }
    var noViewAccepted = true
    bridge.send(["kind":"prepare"]) { noViewAccepted = $0 }
    guard !noViewAccepted else { throw ConsoleFixtureFailure.failed("Native bridge accepted work without a canvas") }
    passed.append("Native bridge checks page identity and missing-canvas receipt")
    return passed
}
