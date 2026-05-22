<#import "layout.ftl" as layout>
<@layout.page title="${msg.get('mob.tab.instances')}" activePage="instances">

<!-- 摘要统计栏 -->
<div class="mob-inst-stats">
    <div class="mob-inst-stat-card">
        <div class="mob-inst-stat-num" id="instStatTotal">0</div>
        <div class="mob-inst-stat-label">${msg.get('mob.inst.total')?replace(' {0}','')}</div>
    </div>
    <div class="mob-inst-stat-card mob-inst-stat-online">
        <div class="mob-inst-stat-num" id="instStatOnline">0</div>
        <div class="mob-inst-stat-label">${msg.get('mob.inst.ping.online')}</div>
    </div>
    <div class="mob-inst-stat-card mob-inst-stat-offline" id="instStatOfflineCard" onclick="instToggleOfflineFilter()">
        <div class="mob-inst-stat-num" id="instStatOffline">0</div>
        <div class="mob-inst-stat-label">${msg.get('mob.inst.ping.offline')}</div>
    </div>
</div>

<!-- 搜索 + 过滤栏 -->
<div class="mob-inst-toolbar">
    <div class="mob-search-wrap" style="flex:1;margin:0">
        <i class="fas fa-search mob-search-icon"></i>
        <input class="mob-search-input" id="instSearch" type="text"
               placeholder="${msg.get('mob.inst.search.placeholder')}"
               oninput="instFilter()">
    </div>
    <button class="mob-inst-ip-toggle" id="instIpToggleBtn" onclick="instToggleAllIp()" title="${msg.get('mob.inst.ip.show')}">
        <i class="fas fa-eye"></i>
    </button>
</div>

<!-- 加载占位 -->
<div id="instLoading" class="mob-loading">
    <div class="mob-spinner"></div>
    <p>${msg.get('mob.loading')}</p>
</div>

<!-- 实例列表 -->
<div id="instList" style="display:none;padding-bottom:80px"></div>

<!-- 统一确认弹框 -->
<div id="instConfirmOverlay" class="inst-probe-overlay" onclick="instConfirmCancel()">
    <div class="inst-probe-sheet" onclick="event.stopPropagation()">
        <div class="inst-probe-icon-wrap" id="instConfirmIconWrap">
            <i id="instConfirmIcon" class="fas fa-question-circle"></i>
        </div>
        <div class="inst-probe-title" id="instConfirmTitle"></div>
        <div class="inst-probe-msg"   id="instConfirmMsg"></div>
        <div class="inst-probe-btns">
            <button class="inst-probe-btn inst-probe-cancel" onclick="instConfirmCancel()">${msg.get('mob.common.cancel')}</button>
            <button class="inst-probe-btn inst-probe-ok"     id="instConfirmOkBtn" onclick="instConfirmOk()">${msg.get('mob.common.confirm')}</button>
        </div>
    </div>
</div>

<style>
/* ── 统计栏 ── */
.mob-inst-stats {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 8px;
    padding: 12px 16px 0;
}
.mob-inst-stat-card {
    background: var(--mob-card);
    border-radius: 10px;
    padding: 10px 8px;
    text-align: center;
    border: 1px solid var(--mob-border);
}
.mob-inst-stat-card.mob-inst-stat-online { border-color: rgba(67,181,129,0.35); }
.mob-inst-stat-card.mob-inst-stat-offline { border-color: rgba(240,71,71,0.35); cursor: pointer; }
.mob-inst-stat-card.mob-inst-stat-offline.active { background: rgba(240,71,71,0.1); border-color: #f04747; }
.mob-inst-stat-num { font-size: 22px; font-weight: 700; color: var(--mob-text); }
.mob-inst-stat-online .mob-inst-stat-num { color: #43b581; }
.mob-inst-stat-offline .mob-inst-stat-num { color: #f04747; }
.mob-inst-stat-label { font-size: 11px; color: var(--mob-text-muted); margin-top: 2px; }

/* ── 工具栏 ── */
.mob-inst-toolbar {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 10px 16px;
}
.mob-inst-ip-toggle {
    width: 38px; height: 38px;
    border-radius: 10px;
    border: 1px solid var(--mob-border);
    background: var(--mob-card);
    color: var(--mob-text-muted);
    cursor: pointer;
    display: flex; align-items: center; justify-content: center;
    font-size: 15px;
    flex-shrink: 0;
    transition: all 0.2s;
}
.mob-inst-ip-toggle.active { background: rgba(var(--mob-accent-rgb,26,188,156),0.15); color: var(--mob-accent); border-color: var(--mob-accent); }

/* ── 实例卡片 ── */
.mob-inst-card {
    background: var(--mob-card);
    border-radius: 12px;
    border: 1px solid var(--mob-border);
    margin: 0 16px 10px;
    overflow: hidden;
    transition: border-color 0.3s;
}
.mob-inst-card.ping-offline { opacity: 0.85; }
.mob-inst-card.ping-offline .mob-inst-flag { filter: grayscale(70%); }
.mob-inst-card.monitor-warning { border-color: rgba(245,158,11,0.6); }

/* 卡片头部 */
.mob-inst-card-head {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 14px 14px 10px;
}
/* 租户名标签 */
.mob-inst-tenant-tag {
    display: flex; align-items: center; gap: 3px;
    font-size: 10px; color: var(--mob-text-muted);
    font-weight: 600; letter-spacing: 0.2px;
    margin-bottom: 3px;
}
.mob-inst-cloud-icon img {
    width: 38px; height: 38px;
    border-radius: 8px;
    background: var(--mob-bg);
    padding: 3px;
    border: 1px solid var(--mob-border);
    object-fit: contain;
}
.mob-inst-head-info { flex: 1; overflow: hidden; }
.mob-inst-name {
    font-size: 14px; font-weight: 600;
    color: var(--mob-text);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}
.mob-inst-region-row {
    display: flex; align-items: center; gap: 5px;
    margin-top: 3px;
}
.mob-inst-flag {
    width: 16px; height: 16px;
    border-radius: 50%;
    object-fit: cover;
    border: 1px solid rgba(255,255,255,0.15);
}
.mob-inst-region-txt { font-size: 11px; color: var(--mob-text-muted); }
.mob-inst-region-inline {
    flex-shrink: 0;
    max-width: 72px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}
.mob-inst-ping-badge {
    font-size: 10px; font-weight: 600;
    padding: 2px 7px;
    border-radius: 10px;
    flex-shrink: 0;
    margin-left: auto;
}
.mob-inst-ping-badge.online { background: rgba(67,181,129,0.18); color: #43b581; }
.mob-inst-ping-badge.offline { background: rgba(240,71,71,0.15); color: #f04747; }

/* IP 行 */
.mob-inst-ip-row {
    display: flex; align-items: center; gap: 6px;
    padding: 0 14px 8px;
    cursor: pointer;
}
.mob-inst-ip-txt {
    font-size: 13px; font-weight: 600; font-family: monospace;
    color: var(--mob-text); flex: 1;
}
.mob-inst-ip-eye { font-size: 11px; color: var(--mob-text-muted); }
.mob-inst-ip-copy {
    font-size: 11px;
    padding: 2px 8px;
    border-radius: 6px;
    border: 1px solid var(--mob-border);
    background: transparent;
    color: var(--mob-text-muted);
    cursor: pointer;
}

/* 标签行 */
.mob-inst-tags {
    display: flex; align-items: center; gap: 5px;
    flex-wrap: wrap;
    padding: 0 14px 10px;
}
.mob-inst-tag {
    font-size: 11px; padding: 2px 7px;
    border-radius: 5px; background: var(--mob-bg);
    color: var(--mob-text-muted);
    border: 1px solid var(--mob-border);
}
.mob-inst-tag.arch-arm { background: rgba(67,181,129,0.12); color: #43b581; border-color: rgba(67,181,129,0.3); }
.mob-inst-tag.arch-amd { background: rgba(59,130,246,0.12); color: #3b82f6; border-color: rgba(59,130,246,0.3); }
.mob-inst-state-dot { width: 7px; height: 7px; border-radius: 50%; display: inline-block; flex-shrink: 0; }
.mob-inst-state-dot.running { background: #43b581; }
.mob-inst-state-dot.starting { background: #f0b429; }
.mob-inst-state-dot.stopped { background: #72767d; }

/* 监控指标区 */
.mob-inst-metrics {
    padding: 8px 14px 10px;
    border-top: 1px dashed var(--mob-border);
}
.mob-inst-metric-row { margin-bottom: 6px; }
.mob-inst-metric-label {
    display: flex; justify-content: space-between;
    font-size: 10px; color: var(--mob-text-muted);
    margin-bottom: 3px; font-weight: 500;
}
.mob-inst-progress { height: 4px; background: var(--mob-border); border-radius: 3px; overflow: hidden; }
.mob-inst-progress-bar { height: 100%; width: 0%; transition: width 0.5s ease; border-radius: 3px; }
.mob-inst-net-row {
    display: flex; justify-content: space-between;
    margin-top: 6px;
}
.mob-inst-net-item { font-size: 11px; color: var(--mob-text-muted); display: flex; align-items: center; gap: 3px; }
.mob-inst-net-val { font-weight: 600; color: var(--mob-text); font-family: monospace; }
.mob-inst-uptime { font-size: 10px; color: var(--mob-text-muted); text-align: right; margin-top: 4px; }

/* 操作行 */
.mob-inst-actions {
    display: flex; gap: 6px;
    padding: 8px 14px;
    border-top: 1px solid var(--mob-border);
    background: rgba(0,0,0,0.06);
    flex-wrap: wrap;
}
.mob-inst-action-btn {
    font-size: 11px; font-weight: 500;
    padding: 5px 10px;
    border-radius: 7px;
    border: 1px solid var(--mob-border);
    background: transparent;
    color: var(--mob-text-muted);
    cursor: pointer;
    display: flex; align-items: center; gap: 4px;
    transition: all 0.2s;
}
.mob-inst-action-btn.start { border-color: rgba(67,181,129,0.4); color: #43b581; }
.mob-inst-action-btn.stop  { border-color: rgba(240,71,71,0.4);  color: #f04747; }
.mob-inst-action-btn.install   { border-color: rgba(59,130,246,0.4); color: #3b82f6; }
.mob-inst-action-btn.uninstall { border-color: rgba(245,158,11,0.4); color: #f0b429; }
.mob-inst-action-btn:disabled { opacity: 0.5; cursor: not-allowed; }

/* ── 探针确认弹框 (独立命名，避免全局CSS冲突) ── */
.inst-probe-overlay {
    display: none;
    position: fixed; inset: 0;
    background: rgba(0,0,0,0.55);
    z-index: 99999;
    align-items: center; justify-content: center;
}
.inst-probe-overlay.show { display: flex; }
.inst-probe-sheet {
    width: calc(100% - 48px); max-width: 320px;
    background: var(--mob-card, #fff);
    border-radius: 16px;
    padding: 28px 20px 20px;
    text-align: center;
    box-shadow: 0 8px 32px rgba(0,0,0,0.25);
}
.inst-probe-icon-wrap {
    width: 56px; height: 56px;
    border-radius: 50%;
    display: flex; align-items: center; justify-content: center;
    margin: 0 auto 14px;
    font-size: 26px;
}
.inst-probe-icon-wrap.install   { background: rgba(59,130,246,0.12); color: #3b82f6; }
.inst-probe-icon-wrap.uninstall { background: rgba(245,158,11,0.12);  color: #f0b429; }
.inst-probe-title {
    font-size: 16px; font-weight: 700;
    color: var(--mob-text, #111); margin-bottom: 8px;
}
.inst-probe-msg {
    font-size: 13px; color: var(--mob-text-muted, #666);
    line-height: 1.6; margin-bottom: 22px;
}
.inst-probe-btns { display: flex; gap: 10px; }
.inst-probe-btn {
    flex: 1; padding: 11px 0;
    border-radius: 12px; border: none;
    font-size: 14px; font-weight: 600;
    cursor: pointer;
}
.inst-probe-cancel {
    background: var(--mob-bg, #f5f5f5);
    color: var(--mob-text-muted, #666);
    border: 1px solid var(--mob-border, #ddd);
}
.inst-probe-ok { color: #fff; }
.inst-probe-ok.install   { background: #3b82f6; }
.inst-probe-ok.uninstall { background: #f0b429; }

</style>

<script>
var _instI18n = {
    loadFail:         "${msg.get('mob.inst.load.fail')}",
    empty:            "${msg.get('mob.inst.empty')}",
    stateRunning:     "${msg.get('mob.inst.state.running')}",
    stateStarting:    "${msg.get('mob.inst.state.starting')}",
    stateStopped:     "${msg.get('mob.inst.state.stopped')}",
    stop:             "${msg.get('mob.inst.action.stop')}",
    start:            "${msg.get('mob.inst.action.start')}",
    busy:             "${msg.get('mob.inst.action.busy')}",
    noIp:             "${msg.get('mob.inst.no.ip')}",
    copy:             "${msg.get('mob.inst.copy')}",
    startSending:     "${msg.get('mob.inst.start.sending')}",
    stopSending:      "${msg.get('mob.inst.stop.sending')}",
    actionSent:       "${msg.get('mob.inst.action.sent')}",
    actionFail:       "${msg.get('mob.inst.action.fail')}",
    networkError:     "${msg.get('mob.inst.network.error')}",
    unnamed:          "${msg.get('mob.inst.unnamed')}",
    pingOnline:       "${msg.get('mob.inst.ping.online')}",
    pingOffline:      "${msg.get('mob.inst.ping.offline')}",
    probeInstall:     "${msg.get('mob.inst.probe.install')}",
    probeUninstall:   "${msg.get('mob.inst.probe.uninstall')}",
    probeInstalling:  "${msg.get('mob.inst.probe.installing')}",
    probeInstallOk:   "${msg.get('mob.inst.probe.install.ok')}",
    probeInstallFail: "${msg.get('mob.inst.probe.install.fail')}",
    probeUninstallOk: "${msg.get('mob.inst.probe.uninstall.ok')}",
    probeUninstFail:  "${msg.get('mob.inst.probe.uninstall.fail')}",
    installConfirm:   "${msg.get('mob.inst.probe.install.confirm')}",
    uninstallConfirm: "${msg.get('mob.inst.probe.uninstall.confirm')}",
    ipShow:           "${msg.get('mob.inst.ip.show')}",
    ipHide:           "${msg.get('mob.inst.ip.hide')}"
};
</script>
<#noparse>
<script>
var _allInstances   = [];
var _isGlobalIpShow = false;

function maskInstName(name) {
    if (!name) return '';
    if (name.length <= 2) return name[0] + '*';
    return name[0] + '***' + name[name.length - 1];
}

function maskIp(ip) {
    if (!ip) return '';
    var parts = ip.split('.');
    if (parts.length === 4) return parts[0] + '.' + parts[1] + '.*.*';
    var mid = Math.ceil(ip.length / 2);
    return ip.substring(0, mid) + '***';
}
var _isOfflineOnly  = false;
var _ws             = null;
var _lastHeartbeat  = {};
var _confirmCallback = null;

/* ── 统一确认弹框 ── */
function instShowConfirm(type, title, msg, onOk) {
    _confirmCallback = onOk;
    var overlay  = document.getElementById('instConfirmOverlay');
    var iconWrap = document.getElementById('instConfirmIconWrap');
    var icon     = document.getElementById('instConfirmIcon');
    var okBtn    = document.getElementById('instConfirmOkBtn');
    document.getElementById('instConfirmTitle').textContent = title;
    document.getElementById('instConfirmMsg').textContent   = msg;
    iconWrap.className = 'inst-probe-icon-wrap ' + type;
    icon.className = type === 'install' ? 'fas fa-download' : 'fas fa-trash-alt';
    okBtn.className = 'inst-probe-btn inst-probe-ok ' + type;
    overlay.classList.add('show');
}
function instConfirmOk() {
    document.getElementById('instConfirmOverlay').classList.remove('show');
    if (_confirmCallback) { var cb = _confirmCallback; _confirmCallback = null; cb(); }
}
function instConfirmCancel() {
    document.getElementById('instConfirmOverlay').classList.remove('show');
    _confirmCallback = null;
}

/* ── 页面入口 ── */
document.addEventListener('DOMContentLoaded', function() {
    loadInstances();
    initWs();
});

/* ── 加载实例列表 ── */
async function loadInstances() {
    try {
        var res  = await fetch('/m/api/instances?size=200');
        var json = await res.json();
        if (!json.success && json.code !== 200) throw new Error(json.message || _instI18n.loadFail);
        var data = json.data || {};
        _allInstances = data.list || [];
        renderInstances(_allInstances);
    } catch (e) {
        document.getElementById('instLoading').innerHTML =
            '<p style="color:#f04747;text-align:center">' + _instI18n.loadFail + ' ' + escH(e.message) + '</p>';
    }
}

/* ── 过滤 ── */
function instFilter() {
    var kw = document.getElementById('instSearch').value.trim().toLowerCase();
    var list = _allInstances.filter(function(i) {
        if (_isOfflineOnly && i.onLineEnable !== 0) return false;
        if (!kw) return true;
        return (i.displayName  || '').toLowerCase().includes(kw)
            || (i.publicIps    || '').toLowerCase().includes(kw)
            || (i.regionName   || '').toLowerCase().includes(kw)
            || (i.tenancyName  || i.userName || '').toLowerCase().includes(kw)
            || (i.architecture || '').toLowerCase().includes(kw);
    });
    renderCards(list);
}

function instToggleOfflineFilter() {
    _isOfflineOnly = !_isOfflineOnly;
    var card = document.getElementById('instStatOfflineCard');
    if (_isOfflineOnly) card.classList.add('active');
    else                card.classList.remove('active');
    instFilter();
}

/* ── 渲染 ── */
function renderInstances(instances) {
    var total   = instances.length;
    var online  = instances.filter(function(i) { return i.onLineEnable === 1; }).length;
    var offline = total - online;
    document.getElementById('instStatTotal').textContent  = total;
    document.getElementById('instStatOnline').textContent  = online;
    document.getElementById('instStatOffline').textContent = offline;
    document.getElementById('instLoading').style.display  = 'none';
    renderCards(instances);
}

function renderCards(instances) {
    var list = document.getElementById('instList');
    list.style.display = 'block';

    if (instances.length === 0) {
        list.innerHTML = '<div class="mob-empty"><i class="fas fa-server"></i><p>' + _instI18n.empty + '</p></div>';
        return;
    }

    list.innerHTML = instances.map(function(inst) {
        var id        = inst.id || '';
        var iid       = escH(inst.instanceId || '');
        var state     = (inst.state || '').toUpperCase();
        var isRunning = state === 'RUNNING';
        var isProv    = state === 'PROVISIONING' || state === 'STARTING';
        var isOnline  = inst.onLineEnable === 1;
        var installed = inst.monitorInstalled === true;

        var dotClass  = isRunning ? 'running' : (isProv ? 'starting' : 'stopped');
        var stateText = isRunning ? _instI18n.stateRunning : (isProv ? _instI18n.stateStarting : _instI18n.stateStopped);

        var region    = escH(inst.regionName || '');
        var arch      = (inst.architecture || '').toUpperCase();
        var ocpus     = inst.ocpus || '?';
        var mem       = inst.memoryInGBs || '?';
        var ip        = inst.publicIps || '';
        var flagUrl   = escH(inst.flagUrl || '/images/flags/xx.svg');
        var tenRaw    = inst.tenancyName || inst.userName || '';
        var tenDisp   = maskInstName(tenRaw);

        /* 云平台图标 */
        var cloudSrc = '/images/vps.png';
        if (inst.cloudType === 1)      cloudSrc = '/images/oracle.png';
        else if (inst.cloudType === 2) cloudSrc = '/images/google.png';
        else if (inst.cloudType === 4) cloudSrc = '/images/aws.png';

        /* 操作按钮 */
        var stateBtn = '';
        if (isRunning) {
            stateBtn = '';
        } else if (isProv) {
            stateBtn = '<button class="mob-inst-action-btn" disabled>'
                     + '<i class="fas fa-spinner fa-spin"></i> ' + _instI18n.busy + '</button>';
        } else {
            stateBtn = '<button class="mob-inst-action-btn start" onclick="instAction(\'' + iid + '\',\'start\')">'
                     + '<i class="fas fa-play-circle"></i> ' + _instI18n.start + '</button>';
        }

        /* 探针按钮 */
        var probeBtn = '';
        if (id) {
            if (!installed) {
                probeBtn = '<button class="mob-inst-action-btn install" id="probeInstBtn-' + escH(id+'') + '" onclick="instInstallProbe(\'' + escH(id+'') + '\')">'
                         + '<i class="fas fa-download"></i> ' + _instI18n.probeInstall + '</button>';
            } else {
                probeBtn = '<button class="mob-inst-action-btn uninstall" id="probeUninstBtn-' + escH(id+'') + '" onclick="instUninstallProbe(\'' + escH(id+'') + '\')">'
                         + '<i class="fas fa-trash-alt"></i> ' + _instI18n.probeUninstall + '</button>';
            }
        }

        /* 租户名（左上角，默认隐藏中间字符） */
        var tenantTagHtml = tenRaw
            ? '<div class="mob-inst-tenant-tag">'
            +   '<i class="fas fa-user" style="font-size:9px;opacity:0.45"></i>'
            +   '<span class="mob-inst-tenant-name" data-raw="' + escH(tenRaw) + '">' + escH(tenDisp) + '</span>'
            + '</div>'
            : '';

        /* IP 行：IP + 眼睛 + 复制 + ping badge */
        var pingBadge = '<span class="mob-inst-ping-badge ' + (isOnline ? 'online' : 'offline') + '">'
                      +   (isOnline ? _instI18n.pingOnline : _instI18n.pingOffline)
                      + '</span>';
        var ipHeadHtml = ip
            ? '<div class="mob-inst-ip-row" style="padding:0;margin:0" onclick="instToggleIp(\'' + escH(id+'') + '\')">'
            +   '<span class="mob-inst-ip-txt" id="ipTxt-' + escH(id+'') + '" data-ip="' + escH(ip) + '" data-shown="0">' + escH(maskIp(ip)) + '</span>'
            +   '<i class="fas fa-eye mob-inst-ip-eye"></i>'
            +   '<button class="mob-inst-ip-copy" onclick="event.stopPropagation();mobCopy(\'' + escH(ip) + '\')">'
            +     '<i class="fas fa-copy"></i>'
            +   '</button>'
            +   pingBadge
            + '</div>'
            : '<div style="font-size:12px;color:var(--mob-text-muted);display:flex;align-items:center;gap:6px">' + _instI18n.noIp + pingBadge + '</div>';

        var archClass = arch === 'ARM' ? 'arch-arm' : (arch === 'AMD' ? 'arch-amd' : '');

        return '<div class="mob-inst-card ' + (isOnline ? 'ping-online' : 'ping-offline') + '" id="instCard-' + escH(id+'') + '" data-token="' + iid + '" data-installed="' + (installed?'true':'false') + '">'
            /* 头部 */
            + '<div class="mob-inst-card-head">'
            +   '<div class="mob-inst-cloud-icon"><img src="' + escH(cloudSrc) + '" onerror="this.src=\'/images/vps.png\'"></div>'
            +   '<div class="mob-inst-head-info">'
            +     tenantTagHtml
            +     ipHeadHtml
            +   '</div>'
            + '</div>'
            /* 标签行：国旗 + 区域 + 状态 + 架构 + 规格 */
            + '<div class="mob-inst-tags">'
            +   '<img class="mob-inst-flag" src="' + flagUrl + '" onerror="this.src=\'/images/flags/xx.svg\'">'
            +   (region ? '<span class="mob-inst-region-txt mob-inst-region-inline">' + region + '</span>' : '')
            +   '<span class="mob-inst-state-dot ' + dotClass + '" style="margin-left:auto"></span>'
            +   '<span class="mob-inst-tag">' + stateText + '</span>'
            +   (arch ? '<span class="mob-inst-tag ' + archClass + '">' + arch + '</span>' : '')
            +   '<span class="mob-inst-tag">' + ocpus + 'C · ' + mem + 'G</span>'
            + '</div>'
            /* 监控指标 (默认显示空进度条，WebSocket 更新) */
            + '<div class="mob-inst-metrics" id="instMetrics-' + escH(id+'') + '">'
            +   '<div class="mob-inst-metric-row">'
            +     '<div class="mob-inst-metric-label"><span>CPU</span><span class="icpu-txt">--</span></div>'
            +     '<div class="mob-inst-progress"><div class="mob-inst-progress-bar icpu-bar" style="background:#43b581"></div></div>'
            +   '</div>'
            +   '<div class="mob-inst-metric-row">'
            +     '<div class="mob-inst-metric-label"><span>MEM</span><span class="imem-txt">--</span></div>'
            +     '<div class="mob-inst-progress"><div class="mob-inst-progress-bar imem-bar" style="background:#3b82f6"></div></div>'
            +   '</div>'
            +   '<div class="mob-inst-metric-row">'
            +     '<div class="mob-inst-metric-label"><span>DISK</span><span class="idisk-txt">--</span></div>'
            +     '<div class="mob-inst-progress"><div class="mob-inst-progress-bar idisk-bar" style="background:#8b5cf6"></div></div>'
            +   '</div>'
            +   '<div class="mob-inst-net-row">'
            +     '<div class="mob-inst-net-item"><i class="fas fa-arrow-down" style="color:#43b581"></i> <span class="inet-rx">--</span></div>'
            +     '<div class="mob-inst-net-item"><i class="fas fa-arrow-up" style="color:#f0b429"></i> <span class="inet-tx">--</span></div>'
            +     '<div class="mob-inst-net-item" style="font-size:10px"><i class="fas fa-clock" style="opacity:0.5"></i> <span class="iuptime-txt"></span></div>'
            +   '</div>'
            + '</div>'
            /* 操作 */
            + '<div class="mob-inst-actions">'
            +   stateBtn
            +   probeBtn
            + '</div>'
            + '</div>';
    }).join('');

    /* 初始化 IP 显示状态（全局已展开时恢复明文） */
    if (_isGlobalIpShow) {
        document.querySelectorAll('.mob-inst-ip-txt').forEach(function(el) {
            el.textContent = el.dataset.ip || '';
            el.dataset.shown = '1';
        });
    }
}

/* ── IP 显示切换（单卡） ── */
function instToggleIp(id) {
    var el = document.getElementById('ipTxt-' + id);
    if (!el) return;
    if (el.dataset.shown === '1') {
        el.textContent = maskIp(el.dataset.ip || '');
        el.dataset.shown = '0';
    } else {
        el.textContent = el.dataset.ip || '';
        el.dataset.shown = '1';
    }
}

function instToggleAllIp() {
    _isGlobalIpShow = !_isGlobalIpShow;
    var btn = document.getElementById('instIpToggleBtn');
    if (_isGlobalIpShow) {
        btn.classList.add('active');
        btn.title = _instI18n.ipHide;
        btn.innerHTML = '<i class="fas fa-eye-slash"></i>';
        document.querySelectorAll('.mob-inst-ip-txt').forEach(function(el) {
            el.textContent = el.dataset.ip || '';
            el.dataset.shown = '1';
        });
        document.querySelectorAll('.mob-inst-tenant-name').forEach(function(el) {
            el.textContent = el.dataset.raw || '';
        });
    } else {
        btn.classList.remove('active');
        btn.title = _instI18n.ipShow;
        btn.innerHTML = '<i class="fas fa-eye"></i>';
        document.querySelectorAll('.mob-inst-ip-txt').forEach(function(el) {
            el.textContent = maskIp(el.dataset.ip || '');
            el.dataset.shown = '0';
        });
        document.querySelectorAll('.mob-inst-tenant-name').forEach(function(el) {
            el.textContent = maskInstName(el.dataset.raw || '');
        });
    }
}

/* ── 实例操作 ── */
async function instAction(instanceId, action) {
    var csrf = document.querySelector('meta[name="_csrf"]');
    var csrfToken = csrf ? csrf.getAttribute('content') : '';
    var url  = action === 'start' ? '/startInstance' : '/stopInstance';
    var hint = action === 'start' ? _instI18n.startSending : _instI18n.stopSending;
    try {
        mobToast(hint, 'info');
        var res = await fetch(url, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrfToken },
            body: JSON.stringify({ instanceId: instanceId })
        });
        var json = await res.json();
        if (json.success) {
            mobToast(_instI18n.actionSent, 'success');
            setTimeout(loadInstances, 3000);
        } else {
            mobToast(json.message || _instI18n.actionFail, 'error');
        }
    } catch (e) {
        mobToast(_instI18n.networkError + ' ' + e.message, 'error');
    }
}

/* ── 探针安装 / 卸载 ── */
async function instInstallProbe(id) {
    instShowConfirm('install', _instI18n.probeInstall, _instI18n.installConfirm, function() { _doInstallProbe(id); });
}
async function _doInstallProbe(id) {
    var btn = document.getElementById('probeInstBtn-' + id);
    if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> ' + _instI18n.probeInstalling; }
    var csrf = document.querySelector('meta[name="_csrf"]');
    var csrfToken = csrf ? csrf.getAttribute('content') : '';
    try {
        var fd = new FormData();
        fd.append('vpsId', id);
        var res  = await fetch('/api/monitor/install', { method: 'POST', headers: { 'X-CSRF-TOKEN': csrfToken }, body: fd });
        var json = await res.json();
        if (json.success) {
            mobToast(_instI18n.probeInstallOk, 'success');
            var card = document.getElementById('instCard-' + id);
            if (card) card.setAttribute('data-installed', 'true');
            /* 换成卸载按钮 */
            if (btn) {
                btn.id        = 'probeUninstBtn-' + id;
                btn.className = 'mob-inst-action-btn uninstall';
                btn.disabled  = false;
                btn.setAttribute('onclick', 'instUninstallProbe(\'' + id + '\')');
                btn.innerHTML = '<i class="fas fa-trash-alt"></i> ' + _instI18n.probeUninstall;
            }
        } else {
            mobToast((json.message || _instI18n.probeInstallFail), 'error');
            if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fas fa-download"></i> ' + _instI18n.probeInstall; }
        }
    } catch (e) {
        mobToast(_instI18n.probeInstallFail + ' ' + e.message, 'error');
        if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fas fa-download"></i> ' + _instI18n.probeInstall; }
    }
}

async function instUninstallProbe(id) {
    instShowConfirm('uninstall', _instI18n.probeUninstall, _instI18n.uninstallConfirm, function() { _doUninstallProbe(id); });
}
async function _doUninstallProbe(id) {
    var btn = document.getElementById('probeUninstBtn-' + id);
    if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i>'; }
    var csrf = document.querySelector('meta[name="_csrf"]');
    var csrfToken = csrf ? csrf.getAttribute('content') : '';
    try {
        var fd = new FormData();
        fd.append('vpsId', id);
        var res  = await fetch('/api/monitor/uninstall', { method: 'POST', headers: { 'X-CSRF-TOKEN': csrfToken }, body: fd });
        var json = await res.json();
        if (json.success) {
            mobToast(_instI18n.probeUninstallOk, 'success');
            var card = document.getElementById('instCard-' + id);
            if (card) {
                card.setAttribute('data-installed', 'false');
                card.classList.remove('monitor-warning');
            }
            /* 换成安装按钮 */
            if (btn) {
                btn.id        = 'probeInstBtn-' + id;
                btn.className = 'mob-inst-action-btn install';
                btn.disabled  = false;
                btn.setAttribute('onclick', 'instInstallProbe(\'' + id + '\')');
                btn.innerHTML = '<i class="fas fa-download"></i> ' + _instI18n.probeInstall;
            }
        } else {
            mobToast((json.message || _instI18n.probeUninstFail), 'error');
            if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fas fa-trash-alt"></i> ' + _instI18n.probeUninstall; }
        }
    } catch (e) {
        mobToast(_instI18n.probeUninstFail + ' ' + e.message, 'error');
        if (btn) { btn.disabled = false; btn.innerHTML = '<i class="fas fa-trash-alt"></i> ' + _instI18n.probeUninstall; }
    }
}

/* ── WebSocket 监控 ── */
function initWs() {
    var protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
    var url = protocol + window.location.host + '/ws/monitor';
    _ws = new WebSocket(url);
    _ws.onopen    = function() {};
    _ws.onmessage = function(e) {
        try {
            var data = JSON.parse(e.data);
            if (!data.token) return;
            _lastHeartbeat[data.token] = Date.now();
            instUpdateMetrics(data);
        } catch (ex) {}
    };
    _ws.onclose = function() { setTimeout(initWs, 4000); };
    setInterval(instCheckHeartbeat, 5000);
}

function instUpdateMetrics(data) {
    var card = document.querySelector('.mob-inst-card[data-token="' + data.token + '"]');
    if (!card) return;

    card.classList.remove('monitor-warning');
    card.setAttribute('data-installed', 'true');

    var id = card.id.replace('instCard-', '');

    /* CPU */
    var cpu = data.cpu ? data.cpu.usage : 0;
    var cpuTxt = card.querySelector('.icpu-txt');
    var cpuBar = card.querySelector('.icpu-bar');
    if (cpuTxt) cpuTxt.textContent = cpu + '%';
    if (cpuBar) { cpuBar.style.width = cpu + '%'; cpuBar.style.background = cpu > 90 ? '#f04747' : cpu > 70 ? '#f0b429' : '#43b581'; }

    /* MEM */
    if (data.memory) {
        var memPct = Math.round((data.memory.used / data.memory.total) * 100);
        var memTxt = card.querySelector('.imem-txt');
        var memBar = card.querySelector('.imem-bar');
        if (memTxt) memTxt.textContent = memPct + '%';
        if (memBar) { memBar.style.width = memPct + '%'; memBar.style.background = memPct > 90 ? '#f04747' : memPct > 70 ? '#f0b429' : '#3b82f6'; }
    }

    /* DISK */
    if (data.disk) {
        var diskPct = Math.round((data.disk.used / data.disk.total) * 100);
        var diskTxt = card.querySelector('.idisk-txt');
        var diskBar = card.querySelector('.idisk-bar');
        if (diskTxt) diskTxt.textContent = diskPct + '% (' + fmtSize(data.disk.total) + ')';
        if (diskBar) { diskBar.style.width = diskPct + '%'; diskBar.style.background = diskPct > 90 ? '#f04747' : '#8b5cf6'; }
    }

    /* Network */
    if (data.network) {
        var rxEl = card.querySelector('.inet-rx');
        var txEl = card.querySelector('.inet-tx');
        if (rxEl) rxEl.textContent = fmtSpeed(data.network.rx_rate);
        if (txEl) txEl.textContent = fmtSpeed(data.network.tx_rate);
    }

    /* Uptime */
    if (data.host && data.host.uptime) {
        var uptEl = card.querySelector('.iuptime-txt');
        if (uptEl) uptEl.textContent = fmtUptime(data.host.uptime);
    }

    /* 隐藏安装探针按钮（已在线说明已安装） */
    var instBtn = document.getElementById('probeInstBtn-' + id);
    if (instBtn) {
        instBtn.id        = 'probeUninstBtn-' + id;
        instBtn.className = 'mob-inst-action-btn uninstall';
        instBtn.setAttribute('onclick', 'instUninstallProbe(\'' + id + '\')');
        instBtn.innerHTML = '<i class="fas fa-trash-alt"></i> ' + _instI18n.probeUninstall;
    }
}

function instCheckHeartbeat() {
    var now     = Date.now();
    var timeout = 12000;
    document.querySelectorAll('.mob-inst-card').forEach(function(card) {
        var token    = card.getAttribute('data-token');
        var installed= card.getAttribute('data-installed') === 'true';
        if (!installed) { card.classList.remove('monitor-warning'); return; }
        var last = _lastHeartbeat[token] || 0;
        if (now - last > timeout) card.classList.add('monitor-warning');
        else                       card.classList.remove('monitor-warning');
    });
}

/* ── 工具函数 ── */
function fmtUptime(sec) {
    var d = Math.floor(sec / 86400);
    var h = Math.floor(sec % 86400 / 3600);
    if (d > 0) return d + 'd';
    if (h > 0) return h + 'h';
    return Math.floor(sec / 60) + 'm';
}
function fmtSize(mb) { return mb > 1024 ? (mb/1024).toFixed(0) + 'G' : mb + 'M'; }
function fmtSpeed(bytes) {
    if (!bytes) return '0B/s';
    var k = 1024, i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ['B/s','KB/s','MB/s','GB/s'][i];
}
function escH(s) {
    if (!s) return '';
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
        .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}

</script>
</#noparse>

</@layout.page>
