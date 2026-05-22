<#import "layout.ftl" as layout>
<@layout.page title="${msg.get('sysHelp.config')}" activePage="">

<style>
.msh-back { display:flex;align-items:center;gap:8px;margin-bottom:14px;color:var(--mob-accent);font-size:14px;font-weight:600;cursor:pointer;width:fit-content }
.msh-back i { font-size:13px }
.msh-info-card { background:var(--mob-card);border-radius:14px;padding:14px 16px;margin-bottom:14px;box-shadow:0 1px 4px rgba(0,0,0,.06) }
.msh-info-row { display:flex;flex-wrap:wrap;gap:10px }
.msh-info-item { flex:1;min-width:140px }
.msh-info-label { font-size:11px;color:var(--mob-text-muted);display:flex;align-items:center;gap:5px;margin-bottom:3px }
.msh-info-value { font-size:13px;font-weight:600;color:var(--mob-text) }
.msh-op-row { display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:14px }
.msh-op-btn { border:none;border-radius:14px;padding:16px 12px;cursor:pointer;display:flex;flex-direction:column;align-items:center;gap:8px;font-size:13px;font-weight:600;transition:opacity .15s }
.msh-op-btn:disabled { opacity:.5;cursor:not-allowed }
.msh-op-btn i { font-size:22px }
.msh-op-rescue { background:linear-gradient(135deg,#1abc9c,#16a085);color:#fff }
.msh-op-reset  { background:linear-gradient(135deg,#f04747,#c0392b);color:#fff }
.msh-conn-bar { display:flex;align-items:center;justify-content:space-between;background:var(--mob-card);border-radius:12px;padding:10px 14px;margin-bottom:10px;font-size:13px }
.msh-conn-status { display:flex;align-items:center;gap:7px }
.msh-conn-dot { width:8px;height:8px;border-radius:50%;background:#72767d;transition:background .3s }
.msh-conn-dot.connected { background:#43b581 }
.msh-terminal { background:#0d1117;border-radius:14px;overflow:hidden;margin-bottom:12px }
.msh-terminal-header { display:flex;align-items:center;justify-content:space-between;padding:10px 14px;border-bottom:1px solid #30363d }
.msh-terminal-title { color:#e6edf3;font-size:13px;font-weight:600;display:flex;align-items:center;gap:7px }
.msh-terminal-dots { display:flex;gap:5px }
.msh-terminal-dots span { width:10px;height:10px;border-radius:50% }
.msh-dot-red{background:#ff5f57}.msh-dot-yellow{background:#febc2e}.msh-dot-green{background:#28c840}
.msh-log-area { height:45vh;overflow-y:auto;padding:12px 14px;font-family:monospace;font-size:12px;line-height:1.7;color:#adbac7 }
.msh-log-line.success { color:#3fb950 }
.msh-log-line.error   { color:#f85149 }
.msh-log-line.warn    { color:#d29922 }
.msh-log-line.process { color:#79c0ff }
.msh-log-line.complete{ color:#56d364 }
.msh-terminal-footer { display:flex;align-items:center;justify-content:space-between;padding:9px 14px;border-top:1px solid #30363d;color:#6e7681;font-size:12px }
.msh-terminal-footer label { display:flex;align-items:center;gap:5px;cursor:pointer }
.msh-confirm-overlay { display:none;position:fixed;inset:0;background:rgba(0,0,0,.55);z-index:9600;align-items:center;justify-content:center }
.msh-confirm-overlay.show { display:flex }
.msh-confirm-card { width:calc(100% - 40px);max-width:360px;background:var(--mob-card);border-radius:16px;padding:20px;max-height:85vh;overflow-y:auto }
.msh-confirm-title { font-size:16px;font-weight:700;color:var(--mob-text);margin-bottom:12px }
.msh-confirm-steps { font-size:13px;color:var(--mob-text-muted);line-height:1.8;padding-left:16px;margin-bottom:12px }
.msh-confirm-warn { font-size:12px;color:#f04747;padding:10px;background:rgba(240,71,71,.08);border-radius:8px;line-height:1.6;margin-bottom:14px }
.msh-confirm-btns { display:flex;gap:10px }
.msh-confirm-cancel { flex:1;padding:11px;border-radius:10px;border:1px solid var(--mob-border);background:var(--mob-bg);color:var(--mob-text-muted);font-size:14px;font-weight:600;cursor:pointer }
.msh-confirm-ok { flex:1;padding:11px;border-radius:10px;border:none;background:var(--mob-accent,#1abc9c);color:#fff;font-size:14px;font-weight:600;cursor:pointer }
.msh-confirm-ok.danger { background:#f04747 }
</style>

<!-- 返回按钮 -->
<div class="msh-back" onclick="history.back()">
    <i class="fas fa-chevron-left"></i>${msg.get('common.rollback')}
</div>

<!-- 实例信息 -->
<div class="msh-info-card">
    <div class="msh-info-row">
        <div class="msh-info-item">
            <div class="msh-info-label"><i class="fas fa-server"></i>${msg.get('tenant.insName')}</div>
            <div class="msh-info-value">${instance.displayName!''}</div>
        </div>
        <div class="msh-info-item">
            <div class="msh-info-label"><i class="fas fa-network-wired"></i>${msg.get('sysHelp.ipAddress')}</div>
            <div class="msh-info-value">${instance.publicIps!''}</div>
        </div>
        <div class="msh-info-item">
            <div class="msh-info-label"><i class="fas fa-microchip"></i>${msg.get('machine.arch')}</div>
            <div class="msh-info-value">${instance.architecture!'Unknown'}</div>
        </div>
    </div>
</div>

<!-- 操作按钮 -->
<div class="msh-op-row">
    <button class="msh-op-btn msh-op-rescue" id="btnRescue" onclick="mshConfirm(1)">
        <i class="fas fa-medkit"></i>
        ${msg.get('sysHelp.osHelp')}
    </button>
    <button class="msh-op-btn msh-op-reset" id="btnReset" onclick="mshConfirm(2)">
        <i class="fas fa-hdd"></i>
        ${msg.get('sysHelp.resetDisk')}
    </button>
</div>

<!-- 连接状态栏 -->
<div class="msh-conn-bar">
    <div class="msh-conn-status">
        <span class="msh-conn-dot" id="mshConnDot"></span>
        <span id="mshConnText">${msg.get('sysHelp.noConn')}</span>
    </div>
    <span id="mshLogCount" style="color:var(--mob-text-muted);font-size:12px">0 ${msg.get('sysHelp.nlogs')}</span>
</div>

<!-- 终端日志 -->
<div class="msh-terminal">
    <div class="msh-terminal-header">
        <div class="msh-terminal-title">
            <i class="fas fa-terminal" style="color:#8b949e"></i>
            <span style="color:#e6edf3">${msg.get('sysHelp.console')}</span>
        </div>
        <div class="msh-terminal-dots">
            <span class="msh-dot-red"></span>
            <span class="msh-dot-yellow"></span>
            <span class="msh-dot-green"></span>
        </div>
    </div>
    <div class="msh-log-area" id="mshLogArea">
        <div class="msh-log-line">${msg.get('sysHelp.help1')}</div>
        <div class="msh-log-line">${msg.get('sysHelp.help2')}</div>
    </div>
    <div class="msh-terminal-footer">
        <label>
            <input type="checkbox" id="mshAutoScroll" checked>
            ${msg.get('sysHelp.autoNext')}
        </label>
        <button onclick="mshClearLogs()" style="background:none;border:none;color:#6e7681;font-size:12px;cursor:pointer">
            <i class="fas fa-trash-alt"></i>
        </button>
    </div>
</div>

<!-- 确认弹框 -->
<div id="mshConfirmOverlay" class="msh-confirm-overlay" onclick="mshCloseConfirm(event)">
    <div class="msh-confirm-card" onclick="event.stopPropagation()">
        <div class="msh-confirm-title" id="mshConfirmTitle"></div>
        <ol class="msh-confirm-steps" id="mshConfirmSteps"></ol>
        <div class="msh-confirm-warn">${msg.get('sysHelp.helpSummary7')}</div>
        <div class="msh-confirm-btns">
            <button class="msh-confirm-cancel" onclick="mshCloseConfirm()">${msg.get('common.cancel')}</button>
            <button class="msh-confirm-ok" id="mshConfirmOkBtn" onclick="mshStart()">${msg.get('common.confirm')}</button>
        </div>
    </div>
</div>

<input type="hidden" id="mshInstanceId" value="${instanceId!''}">

<script>
var _mshWs = null;
var _mshInProgress = false;
var _mshPendingType = 1;
var _mshLogCount = 0;
var _mshMaxLogs = 1000;

var MSH_I18N = {
    connected:    "${msg.get('sysHelp.alreadyConn')?js_string}",
    disconnected: "${msg.get('sysHelp.noConn')?js_string}",
    wsConnected:  "${msg.get('sysHelp.wsConnected')?js_string}",
    wsError:      "${msg.get('sysHelp.wsConnError')?js_string}",
    helpEnd:      "${msg.get('sysHelp.helpEnd')?js_string}",
    noClose:      "${msg.get('sysHelp.noClose')?js_string}",
    wsConError:   "${msg.get('sysHelp.wsConError')?js_string}",
    logs:         "${msg.get('sysHelp.nlogs')?js_string}",
    confirm:      "${msg.get('sysHelp.helpConfirm')?js_string}",
    rescueTitle:  "${msg.get('sysHelp.osHelp')?js_string}",
    resetTitle:   "${msg.get('sysHelp.resetDisk')?js_string}",
    steps1: [
        "${msg.get('sysHelp.helpSummary2')?js_string}",
        "${msg.get('sysHelp.helpSummary3')?js_string}",
        "${msg.get('sysHelp.helpSummary4')?js_string}",
        "${msg.get('sysHelp.helpSummary5')?js_string}",
        "${msg.get('sysHelp.helpSummary6')?js_string}"
    ],
    steps2: [
        "${msg.get('sysHelp.helpSummary8')?js_string}",
        "${msg.get('sysHelp.helpSummary9')?js_string}",
        "${msg.get('sysHelp.helpSummary10')?js_string}",
        "${msg.get('sysHelp.helpSummary11')?js_string}",
        "${msg.get('sysHelp.helpSummary12')?js_string}"
    ]
};

function mshConfirm(type) {
    _mshPendingType = type;
    var steps = type === 1 ? MSH_I18N.steps1 : MSH_I18N.steps2;
    document.getElementById('mshConfirmTitle').textContent = type === 1 ? MSH_I18N.rescueTitle : MSH_I18N.resetTitle;
    document.getElementById('mshConfirmSteps').innerHTML = steps.map(function(s) {
        return '<li>' + s + '</li>';
    }).join('');
    var okBtn = document.getElementById('mshConfirmOkBtn');
    okBtn.className = 'msh-confirm-ok' + (type === 2 ? ' danger' : '');
    document.getElementById('mshConfirmOverlay').classList.add('show');
}
function mshCloseConfirm(e) {
    if (e && e.target !== document.getElementById('mshConfirmOverlay')) return;
    document.getElementById('mshConfirmOverlay').classList.remove('show');
}
function mshStart() {
    mshCloseConfirm();
    if (!_mshWs || _mshWs.readyState !== WebSocket.OPEN) {
        mshConnect(function() { mshSend(_mshPendingType); });
    } else {
        mshSend(_mshPendingType);
    }
}
function mshConnect(cb) {
    var protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
    _mshWs = new WebSocket(protocol + window.location.host + '/ws/rescue');
    _mshWs.onopen = function() {
        mshSetConn(true);
        mshAddLog(MSH_I18N.wsConnected, 'info');
        if (cb) cb();
    };
    _mshWs.onmessage = function(ev) {
        var d = JSON.parse(ev.data);
        if (d.type === 'output') {
            mshAddLog(d.data, (d.messageType || 'info').toLowerCase());
        } else if (d.type === 'error') {
            mshAddLog(d.message, 'error');
            mshDone();
        } else if (d.type === 'heartbeat') {
            _mshWs.send(JSON.stringify({ type: 'heartbeat_response' }));
        }
    };
    _mshWs.onclose = function() {
        mshSetConn(false);
        mshAddLog(MSH_I18N.helpEnd, 'info');
        mshDone();
        if (_mshInProgress) setTimeout(mshConnect, 5000);
    };
    _mshWs.onerror = function() {
        mshSetConn(false);
        mshAddLog(MSH_I18N.wsError, 'error');
    };
}
function mshSend(type) {
    if (!_mshWs || _mshWs.readyState !== WebSocket.OPEN) {
        mshAddLog(MSH_I18N.wsConError, 'error'); return;
    }
    mshClearLogs();
    var instanceId = document.getElementById('mshInstanceId').value;
    _mshWs.send(JSON.stringify({ type: 'init', instanceId: instanceId, rescueType: type }));
    _mshInProgress = true;
    document.getElementById('btnRescue').disabled = true;
    document.getElementById('btnReset').disabled = true;
    mshAddLog(MSH_I18N.noClose, 'warn');
}
function mshDone() {
    _mshInProgress = false;
    document.getElementById('btnRescue').disabled = false;
    document.getElementById('btnReset').disabled = false;
}
function mshSetConn(on) {
    document.getElementById('mshConnDot').className = 'msh-conn-dot' + (on ? ' connected' : '');
    document.getElementById('mshConnText').textContent = on ? MSH_I18N.connected : MSH_I18N.disconnected;
}
function mshAddLog(msg, type) {
    var area = document.getElementById('mshLogArea');
    var div = document.createElement('div');
    div.className = 'msh-log-line ' + (type || '');
    msg = String(msg).replace(/\[(SUCCESS|ERROR|WARN|INFO|PROCESS|COMPLETE)\]\s*/i, '');
    div.textContent = msg;
    area.appendChild(div);
    _mshLogCount++;
    while (area.children.length > _mshMaxLogs) { area.removeChild(area.firstChild); _mshLogCount--; }
    document.getElementById('mshLogCount').textContent = _mshLogCount + ' ' + MSH_I18N.logs;
    if (document.getElementById('mshAutoScroll').checked) area.scrollTop = area.scrollHeight;
}
function mshClearLogs() {
    document.getElementById('mshLogArea').innerHTML = '';
    _mshLogCount = 0;
    document.getElementById('mshLogCount').textContent = '0 ' + MSH_I18N.logs;
}
</script>

</@layout.page>
