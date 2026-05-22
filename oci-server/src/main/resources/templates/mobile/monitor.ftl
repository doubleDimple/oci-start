<#import "layout.ftl" as layout>
<@layout.page title="${msg.get('mob.tab.monitor')}" activePage="monitor">

<!-- 刷新间隔提示 -->
<div class="mob-monitor-refresh" id="monRefreshBar">
    <span id="monRefreshTip">${msg.get('mob.monitor.loading')}</span>
    <button class="mob-btn mob-btn-sm mob-btn-outline" onclick="loadMonitor()" style="padding:4px 10px;font-size:11px">
        <i class="fas fa-sync-alt"></i> ${msg.get('mob.common.refresh')}
    </button>
</div>

<!-- CPU + 内存 圆环 -->
<div class="mob-monitor-rings">
    <div class="mob-monitor-ring-card">
        <svg class="mob-ring-svg" viewBox="0 0 80 80">
            <circle cx="40" cy="40" r="32" fill="none" stroke="var(--mob-border)" stroke-width="7"/>
            <circle id="ringCpu" cx="40" cy="40" r="32" fill="none" stroke="var(--mob-primary)" stroke-width="7"
                    stroke-dasharray="201.06 201.06" stroke-dashoffset="201.06"
                    stroke-linecap="round" transform="rotate(-90 40 40)"/>
            <text x="40" y="43" text-anchor="middle" class="mob-ring-text" id="ringCpuText">-</text>
        </svg>
        <div class="mob-ring-label">${msg.get('mob.monitor.cpu.label')}</div>
    </div>
    <div class="mob-monitor-ring-card">
        <svg class="mob-ring-svg" viewBox="0 0 80 80">
            <circle cx="40" cy="40" r="32" fill="none" stroke="var(--mob-border)" stroke-width="7"/>
            <circle id="ringMem" cx="40" cy="40" r="32" fill="none" stroke="#7289da" stroke-width="7"
                    stroke-dasharray="201.06 201.06" stroke-dashoffset="201.06"
                    stroke-linecap="round" transform="rotate(-90 40 40)"/>
            <text x="40" y="43" text-anchor="middle" class="mob-ring-text" id="ringMemText">-</text>
        </svg>
        <div class="mob-ring-label">${msg.get('mob.monitor.mem.label')}</div>
    </div>
    <div class="mob-monitor-ring-card">
        <svg class="mob-ring-svg" viewBox="0 0 80 80">
            <circle cx="40" cy="40" r="32" fill="none" stroke="var(--mob-border)" stroke-width="7"/>
            <circle id="ringDisk" cx="40" cy="40" r="32" fill="none" stroke="#faa61a" stroke-width="7"
                    stroke-dasharray="201.06 201.06" stroke-dashoffset="201.06"
                    stroke-linecap="round" transform="rotate(-90 40 40)"/>
            <text x="40" y="43" text-anchor="middle" class="mob-ring-text" id="ringDiskText">-</text>
        </svg>
        <div class="mob-ring-label">${msg.get('mob.monitor.disk.label')}</div>
    </div>
</div>

<!-- 详情卡片：CPU -->
<div class="mob-card mob-monitor-detail-card">
    <div class="mob-monitor-section-title"><i class="fas fa-microchip"></i> ${msg.get('mob.monitor.cpu.label')}</div>
    <div class="mob-monitor-rows" id="monCpuDetail">
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.cpu.usage')}</span><span class="mob-monitor-val" id="monCpuUsage">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.cpu.model')}</span><span class="mob-monitor-val mob-monitor-val-sm" id="monCpuModel">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.cpu.physical')}</span><span class="mob-monitor-val" id="monCpuPhysical">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.cpu.logical')}</span><span class="mob-monitor-val" id="monCpuLogical">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.cpu.freq')}</span><span class="mob-monitor-val" id="monCpuFreq">-</span></div>
    </div>
</div>

<!-- 详情卡片：内存 -->
<div class="mob-card mob-monitor-detail-card">
    <div class="mob-monitor-section-title"><i class="fas fa-memory"></i> ${msg.get('mob.monitor.mem.label')}</div>
    <div class="mob-monitor-rows">
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.mem.usage')}</span><span class="mob-monitor-val" id="monMemUsage">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.mem.total')}</span><span class="mob-monitor-val" id="monMemTotal">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.mem.used')}</span><span class="mob-monitor-val" id="monMemUsed">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.mem.free')}</span><span class="mob-monitor-val" id="monMemFree">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">Swap</span><span class="mob-monitor-val" id="monSwap">-</span></div>
    </div>
</div>

<!-- 详情卡片：磁盘 -->
<div class="mob-card mob-monitor-detail-card">
    <div class="mob-monitor-section-title"><i class="fas fa-hdd"></i> ${msg.get('mob.monitor.disk.label')}</div>
    <div class="mob-monitor-rows">
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.disk.usage')}</span><span class="mob-monitor-val" id="monDiskUsage">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.disk.total')}</span><span class="mob-monitor-val" id="monDiskTotal">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.disk.used')}</span><span class="mob-monitor-val" id="monDiskUsed">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.disk.free')}</span><span class="mob-monitor-val" id="monDiskFree">-</span></div>
    </div>
</div>

<!-- 详情卡片：网络 -->
<div class="mob-card mob-monitor-detail-card">
    <div class="mob-monitor-section-title"><i class="fas fa-wifi"></i> ${msg.get('dashboard.monitor.net.title')!''}</div>
    <div class="mob-monitor-net-grid">
        <div class="mob-monitor-net-item mob-monitor-net-up">
            <div class="mob-monitor-net-icon"><i class="fas fa-arrow-up"></i></div>
            <div class="mob-monitor-net-speed" id="monNetUp">-</div>
            <div class="mob-monitor-net-lbl">${msg.get('mob.monitor.net.upload')}</div>
        </div>
        <div class="mob-monitor-net-item mob-monitor-net-down">
            <div class="mob-monitor-net-icon"><i class="fas fa-arrow-down"></i></div>
            <div class="mob-monitor-net-speed" id="monNetDown">-</div>
            <div class="mob-monitor-net-lbl">${msg.get('mob.monitor.net.download')}</div>
        </div>
    </div>
</div>

<!-- 详情卡片：系统 -->
<div class="mob-card mob-monitor-detail-card">
    <div class="mob-monitor-section-title"><i class="fas fa-desktop"></i> ${msg.get('dashboard.monitor.sys.title')!''}</div>
    <div class="mob-monitor-rows">
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.sys.os')}</span><span class="mob-monitor-val mob-monitor-val-sm" id="monOs">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.sys.arch')}</span><span class="mob-monitor-val" id="monArch">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.sys.hostname')}</span><span class="mob-monitor-val mob-monitor-val-sm" id="monHostname">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.sys.uptime')}</span><span class="mob-monitor-val" id="monUptime">-</span></div>
        <div class="mob-monitor-row"><span class="mob-monitor-lbl">${msg.get('mob.monitor.sys.proc')}</span><span class="mob-monitor-val" id="monProc">-</span></div>
    </div>
</div>

<script>
var _monI18n = {
    loading:    "${msg.get('mob.monitor.loading')}",
    loadFail:   "${msg.get('mob.monitor.load.fail')}",
    updatedAt:  "${msg.get('mob.monitor.updated.at')}",
    noSwap:     "${msg.get('mob.monitor.no.swap')}",
    cores:      "${msg.get('mob.monitor.cores')}",
    processes:  "${msg.get('mob.monitor.processes')}",
    day:        "${msg.get('mob.monitor.day')}",
    hour:       "${msg.get('mob.monitor.hour')}",
    min:        "${msg.get('mob.monitor.min')}"
};
</script>
<#noparse>
<script>
var _monTimer = null;

/* ── 格式化工具 ─────────────────────────── */
function fmtBytes(bytes) {
    if (bytes == null) return '-';
    if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + ' GB';
    if (bytes >= 1048576)    return (bytes / 1048576).toFixed(1) + ' MB';
    if (bytes >= 1024)       return (bytes / 1024).toFixed(1) + ' KB';
    return bytes + ' B';
}
function fmtMB(mb) {
    if (mb == null) return '-';
    if (mb >= 1024) return (mb / 1024).toFixed(1) + ' GB';
    return mb + ' MB';
}
function fmtUptime(sec) {
    if (!sec) return '-';
    var d = Math.floor(sec / 86400);
    var h = Math.floor((sec % 86400) / 3600);
    var m = Math.floor((sec % 3600) / 60);
    var parts = [];
    if (d > 0) parts.push(d + _monI18n.day);
    if (h > 0) parts.push(h + _monI18n.hour);
    parts.push(m + _monI18n.min);
    return parts.join(' ');
}
function fmtSpeed(kbps) {
    if (kbps == null) return '-';
    if (kbps >= 1024) return (kbps / 1024).toFixed(1) + ' MB/s';
    return kbps.toFixed(1) + ' KB/s';
}
function fmtPct(v) {
    return v != null ? v.toFixed(1) + '%' : '-';
}

/* ── SVG 圆环更新 ───────────────────────── */
var CIRC = 201.06; // 2π×32
function setRing(ringId, textId, pct, warn, danger) {
    var ring = document.getElementById(ringId);
    var txt  = document.getElementById(textId);
    if (!ring || !txt) return;
    var offset = CIRC * (1 - Math.min(pct, 100) / 100);
    ring.style.strokeDashoffset = offset;
    var color = pct >= danger ? '#f04747' : (pct >= warn ? '#faa61a' : null);
    if (color) ring.style.stroke = color;
    txt.textContent = fmtPct(pct);
}

/* ── 数据加载 ───────────────────────────── */
async function loadMonitor() {
    document.getElementById('monRefreshTip').textContent = _monI18n.loading;
    try {
        var res = await fetch('/monitor/stats');
        var json = await res.json();
        if (!json.success && json.code !== 200) throw new Error(json.message || _monI18n.loadFail);
        var d = json.data || {};
        renderMonitor(d);
        var now = new Date();
        document.getElementById('monRefreshTip').textContent =
            _monI18n.updatedAt + ' ' + now.getHours() + ':' + String(now.getMinutes()).padStart(2,'0') + ':' + String(now.getSeconds()).padStart(2,'0');
    } catch (e) {
        document.getElementById('monRefreshTip').textContent = _monI18n.loadFail + ' ' + e.message;
    }
}

function renderMonitor(d) {
    // 圆环
    setRing('ringCpu',  'ringCpuText',  d.cpuUsage  || 0, 70, 90);
    setRing('ringMem',  'ringMemText',  d.memoryUsage || 0, 75, 90);
    setRing('ringDisk', 'ringDiskText', d.diskUsage || 0, 80, 95);

    // CPU
    document.getElementById('monCpuUsage').textContent   = fmtPct(d.cpuUsage);
    document.getElementById('monCpuModel').textContent   = d.cpuModel || '-';
    document.getElementById('monCpuPhysical').textContent = (d.cpuPhysicalCount || '-') + _monI18n.cores;
    document.getElementById('monCpuLogical').textContent  = (d.cpuLogicalCount  || '-') + _monI18n.cores;
    document.getElementById('monCpuFreq').textContent     = d.cpuFrequency ? d.cpuFrequency.toFixed(2) + ' GHz' : '-';

    // 内存
    document.getElementById('monMemUsage').textContent = fmtPct(d.memoryUsage);
    document.getElementById('monMemTotal').textContent = fmtMB(d.totalMemory);
    document.getElementById('monMemUsed').textContent  = fmtMB(d.usedMemory);
    document.getElementById('monMemFree').textContent  = fmtMB(d.availableMemory);
    document.getElementById('monSwap').textContent     = d.swapTotal
        ? fmtMB(d.swapUsed) + ' / ' + fmtMB(d.swapTotal) + ' (' + fmtPct(d.swapUsage) + ')'
        : _monI18n.noSwap;

    // 磁盘
    document.getElementById('monDiskUsage').textContent = fmtPct(d.diskUsage);
    document.getElementById('monDiskTotal').textContent = fmtBytes(d.diskTotal);
    document.getElementById('monDiskUsed').textContent  = fmtBytes(d.diskUsed);
    document.getElementById('monDiskFree').textContent  = fmtBytes(d.diskFree);

    // 网络
    document.getElementById('monNetUp').textContent   = fmtSpeed(d.uploadSpeed);
    document.getElementById('monNetDown').textContent = fmtSpeed(d.downloadSpeed);

    // 系统
    document.getElementById('monOs').textContent      = d.osName || '-';
    document.getElementById('monArch').textContent    = d.osArch || '-';
    document.getElementById('monHostname').textContent = d.hostname || '-';
    document.getElementById('monUptime').textContent  = fmtUptime(d.systemUptime);
    document.getElementById('monProc').textContent    = d.totalProcesses != null ? d.totalProcesses + _monI18n.processes : '-';
}

// 初始加载 + 每 5 秒自动刷新
loadMonitor();
_monTimer = setInterval(loadMonitor, 5000);
</script>
</#noparse>

</@layout.page>
