<#import "layout.ftl" as layout>
<@layout.page title="${msg.get('mob.tab.boot')}" activePage="boot">

<style>
/* ── 子任务行 ────────────────────────────────── */
.mob-boot-detail-item {
    border-top: 1px solid var(--mob-border);
    padding: 8px 10px 8px 12px;
    display: block;   /* 覆盖 mobile-app.css 的 display:flex，让 di-row 撑满整行 */
}
.mob-boot-di-row {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
}
/* 内容区（name + badge），flex:1 撑满，⋮ 按钮始终在最右 */
.mob-boot-di-content {
    flex: 1;
    min-width: 0;
    display: flex;
    align-items: center;
    gap: 5px;
    overflow: hidden;
    position: relative;
}
.mob-boot-detail-name {
    flex: 1;
    min-width: 0;
    font-size: 13px;
    font-weight: 600;
    color: var(--mob-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}
/* 配置字段（如 1C/6G/50G），绝对居中不占 flex 空间 */
.mob-boot-di-cfg {
    position: absolute;
    left: 50%;
    transform: translateX(-50%);
    font-size: 11px;
    color: var(--mob-text-muted);
    white-space: nowrap;
    letter-spacing: .2px;
    pointer-events: none;
}
/* ⋮ 三点按钮（始终右对齐，不参与内容 flex） */
.mob-boot-dots-btn {
    background: none;
    border: none;
    width: 30px;
    height: 30px;
    border-radius: 6px;
    cursor: pointer;
    color: var(--mob-text-muted);
    font-size: 15px;
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    transition: background .15s;
}
.mob-boot-dots-btn:active,
.mob-boot-dots-btn.active { background: var(--mob-border); color: var(--mob-text); }

/* ── 展开信息面板 ────────────────────────────── */
.mob-boot-info-panel {
    margin-top: 8px;
    border: 1px solid var(--mob-border);
    border-radius: 9px;
    overflow: hidden;
    background: var(--mob-bg);
}
.mob-bip-row {
    display: flex;
    align-items: center;
    padding: 7px 10px;
    border-bottom: 1px solid var(--mob-border);
    gap: 6px;
}
.mob-bip-row:last-child { border-bottom: none; }
.mob-bip-label {
    font-size: 11px;
    color: var(--mob-text-muted);
    width: 34px;
    flex-shrink: 0;
    font-weight: 600;
}
.mob-bip-val {
    flex: 1;
    font-size: 12px;
    color: var(--mob-text);
    font-family: monospace;
    word-break: break-all;
    letter-spacing: .3px;
}
.mob-bip-icon {
    background: none; border: none; padding: 4px 6px; cursor: pointer;
    color: var(--mob-text-muted); font-size: 13px; border-radius: 4px;
    flex-shrink: 0; line-height: 1;
}
.mob-bip-icon:active { color: #1abc9c; }

/* 信息面板内的操作按钮行 */
.mob-bip-actions {
    display: flex;
    gap: 6px;
    padding: 8px 10px;
    border-top: 1px solid var(--mob-border);
    flex-wrap: wrap;
}

/* ── 状态标签 ────────────────────────────────── */
.mob-boot-status-badge {
    font-size: 10px; font-weight: 700; padding: 2px 7px;
    border-radius: 10px; white-space: nowrap;
}
.mob-boot-status-boot   { background: rgba(26,188,156,.15); color: #1abc9c; }
.mob-boot-status-booting{ background: rgba(250,166,26,.15);  color: #faa61a; }
.mob-boot-status-stop   { background: rgba(114,118,125,.12); color: #72767d; }

/* ── 编辑弹窗（屏幕中间）─────────────────────── */
.mob-boot-edit-overlay {
    display: none;
    position: fixed; inset: 0; z-index: 1000;
    background: rgba(0,0,0,.5);
    align-items: center; justify-content: center;
    padding: 16px;
}
.mob-boot-edit-sheet {
    width: 100%; max-width: 400px;
    background: var(--mob-card);
    border-radius: 16px;
    max-height: 90vh;
    overflow-y: auto;
    box-shadow: 0 8px 32px rgba(0,0,0,.35);
}
.mob-bef-header {
    display: flex; align-items: center; justify-content: space-between;
    padding: 14px 16px 10px;
    border-bottom: 1px solid var(--mob-border);
    position: sticky; top: 0; background: var(--mob-card); z-index: 1;
    border-radius: 16px 16px 0 0;
}
.mob-bef-title { font-size: 15px; font-weight: 700; color: var(--mob-text); }
.mob-bef-close {
    background: none; border: none; color: var(--mob-text-muted);
    font-size: 18px; cursor: pointer; padding: 4px 8px;
}
.mob-bef-body { padding: 12px 16px; }
.mob-bef-row { margin-bottom: 12px; }
.mob-bef-label { font-size: 12px; color: var(--mob-text-muted); margin-bottom: 4px; font-weight: 600; }
.mob-bef-input {
    width: 100%; box-sizing: border-box;
    background: var(--mob-bg); border: 1px solid var(--mob-border);
    border-radius: 8px; padding: 9px 12px;
    font-size: 14px; color: var(--mob-text); outline: none;
    -webkit-appearance: none;
}
.mob-bef-input:focus { border-color: #1abc9c; }
.mob-bef-footer {
    display: flex; gap: 10px; padding: 8px 16px 16px;
    border-top: 1px solid var(--mob-border);
}
</style>

<!-- 搜索框 -->
<div class="mob-search-wrap">
    <i class="fas fa-search mob-search-icon"></i>
    <input class="mob-search-input" id="bootSearch" type="text" placeholder="${msg.get('mob.boot.search.placeholder')}" oninput="filterBoots(this.value)">
</div>

<!-- 状态摘要 -->
<div class="mob-summary" id="bootSummary" style="display:none">
    <span>${msg.get('mob.boot.running')} <strong id="summaryRunning">0</strong></span>
    <span><strong id="summaryTotal">0</strong>${msg.get('mob.boot.total.tasks')}</span>
</div>

<!-- 加载占位 -->
<div id="bootLoading" class="mob-loading">
    <div class="mob-spinner"></div>
    <p>${msg.get('mob.loading')}</p>
</div>

<!-- 分组列表 -->
<div id="bootList" style="display:none;"></div>

<!-- ══ 编辑子任务弹窗 ══ -->
<div id="bootEditOverlay" class="mob-boot-edit-overlay" onclick="closeBootEdit(event)">
    <div class="mob-boot-edit-sheet" onclick="event.stopPropagation()">
        <div class="mob-bef-header">
            <span class="mob-bef-title"><i class="fas fa-edit" style="color:#1abc9c;margin-right:6px"></i>修改配置</span>
            <button class="mob-bef-close" onclick="closeBootEdit()"><i class="fas fa-times"></i></button>
        </div>
        <div class="mob-bef-body">
            <input type="hidden" id="befId">
            <div class="mob-bef-row">
                <div class="mob-bef-label">OCPU</div>
                <input class="mob-bef-input" id="befOcpu" type="number" min="1" step="1" placeholder="CPU 核数">
            </div>
            <div class="mob-bef-row">
                <div class="mob-bef-label">内存 (GB)</div>
                <input class="mob-bef-input" id="befMemory" type="number" min="1" step="1" placeholder="内存大小">
            </div>
            <div class="mob-bef-row">
                <div class="mob-bef-label">磁盘 (GB)</div>
                <input class="mob-bef-input" id="befDisk" type="number" min="1" step="1" placeholder="磁盘大小">
            </div>
            <div class="mob-bef-row">
                <div class="mob-bef-label">抢机间隔 (秒)</div>
                <input class="mob-bef-input" id="befLoopTime" type="number" min="1" step="1" placeholder="间隔秒数">
            </div>
            <div class="mob-bef-row">
                <div class="mob-bef-label">时间范围 <span style="color:var(--mob-text-muted);font-weight:400">(如 0-8，可留空)</span></div>
                <input class="mob-bef-input" id="befDayGap" type="text" placeholder="0-8">
            </div>
            <div class="mob-bef-row">
                <div class="mob-bef-label">Root 密码</div>
                <input class="mob-bef-input" id="befPassword" type="text" placeholder="密码">
            </div>
        </div>
        <div class="mob-bef-footer">
            <button class="mob-btn mob-btn-outline" style="flex:1" onclick="closeBootEdit()">取消</button>
            <button class="mob-btn" id="befSaveBtn" style="flex:1;background:#1abc9c;color:#fff;border:none" onclick="saveBootEdit()">保存</button>
        </div>
    </div>
</div>

<script>
var _bootI18n = {
    loadFail:          "${msg.get('mob.boot.load.fail')}",
    empty:             "${msg.get('mob.boot.empty')}",
    statusRunning:     "${msg.get('mob.boot.status.running')}",
    statusStopped:     "${msg.get('mob.boot.status.stopped')}",
    taskCount:         "${msg.get('mob.boot.task.count')}",
    groupRunning:      "${msg.get('mob.boot.group.running')}",
    stop:              "停止",
    start:             "启动",
    startAll:          "启动",
    details:           "${msg.get('mob.boot.details')}",
    deleteBtn:         "${msg.get('mob.boot.delete')}",
    noSubtasks:        "${msg.get('mob.boot.no.subtasks')}",
    loading:           "${msg.get('mob.loading')}",
    subtaskLoadFail:   "${msg.get('mob.boot.subtask.load.fail')}",
    startOk:           "${msg.get('mob.boot.start.ok')}",
    startFail:         "${msg.get('mob.boot.start.fail')}",
    stopOk:            "${msg.get('mob.boot.stop.ok')}",
    stopFail:          "${msg.get('mob.boot.stop.fail')}",
    deleteOk:          "${msg.get('mob.boot.delete.ok')}",
    deleteAllOk:       "${msg.get('mob.boot.delete.all.ok')}",
    deleteFail:        "${msg.get('mob.boot.delete.fail')}",
    confirmDeleteSingle:    "${msg.get('mob.boot.confirm.delete.single')}",
    confirmDeleteSingleMsg: "${msg.get('mob.boot.confirm.delete.single.msg')}",
    confirmDeleteAll:       "${msg.get('mob.boot.confirm.delete.all')}",
    confirmDeleteAllMsg:    "${msg.get('mob.boot.confirm.delete.all.msg')}",
    today:             "${msg.get('mob.boot.today')}",
    times:             "${msg.get('mob.boot.times')}",
    taskPrefix:        "${msg.get('mob.boot.task.prefix')}",
    requestFail:       "${msg.get('mob.common.request.fail')}",
    starting:          "${msg.get('mob.common.saving')}",
    stopping:          "${msg.get('mob.common.saving')}",
    deleting:          "${msg.get('mob.common.saving')}"
};
</script>
<#noparse>
<script>
/* ════════════════════════════════════════════════
   数据加载
   ════════════════════════════════════════════════ */
var _allBoots = [];
var _bootRunningCount = 0;

async function loadBoots() {
    try {
        var res = await fetch('/m/api/boot?size=200');
        var json = await res.json();
        if (!json.success && json.code !== 200) throw new Error(json.message || _bootI18n.loadFail);
        var data = json.data || {};
        _allBoots = data.list || [];
        _bootRunningCount = data.runningCount || 0;
        renderBoots(_allBoots, _bootRunningCount);
    } catch (e) {
        document.getElementById('bootLoading').innerHTML =
            '<p style="color:#f04747;text-align:center">' + _bootI18n.loadFail + ' ' + e.message + '</p>';
    }
}

function filterBoots(kw) {
    var q = kw.trim().toLowerCase();
    if (!q) { renderBoots(_allBoots, _bootRunningCount); return; }
    var filtered = _allBoots.filter(function(b) {
        return (b.tenancyName || b.userName || '').toLowerCase().includes(q)
            || (b.architecture || '').toLowerCase().includes(q);
    });
    var running = filtered.filter(function(b) { return b.status === 1; }).length;
    renderBoots(filtered, running);
}

/* ════════════════════════════════════════════════
   渲染：按 tenantId+architecture 分组
   ════════════════════════════════════════════════ */
function renderBoots(boots, runningCount) {
    document.getElementById('summaryRunning').textContent = runningCount;
    document.getElementById('summaryTotal').textContent = boots.length;
    document.getElementById('bootSummary').style.display = 'flex';
    document.getElementById('bootLoading').style.display = 'none';

    var list = document.getElementById('bootList');
    list.style.display = 'block';

    if (boots.length === 0) {
        list.innerHTML = '<div class="mob-empty"><i class="fas fa-bolt"></i><p>' + _bootI18n.empty + '</p></div>';
        return;
    }

    /* ── 分组 ── */
    var groups = {};
    boots.forEach(function(b) {
        var key = (b.tenantId || '') + '|' + (b.architecture || '');
        if (!groups[key]) groups[key] = { items: [], key: key };
        groups[key].items.push(b);
    });

    list.innerHTML = Object.keys(groups).map(function(key) {
        return renderGroup(key, groups[key].items);
    }).join('');
}

function renderGroup(key, items) {
    var first = items[0];
    var arch = first.architecture || '';
    var tenancyName = escHtml(first.tenancyName || first.userName || '');
    var runningInGroup = items.filter(function(b) { return b.status === 1; }).length;
    var groupId = 'grp_' + key.replace(/[^a-z0-9]/gi, '_');
    var hasRunning = runningInGroup > 0;
    var dotClass  = hasRunning ? 'mob-dot-green' : 'mob-dot-gray';
    var badgeClass = hasRunning ? 'mob-badge-green' : 'mob-badge-gray';
    var statusText = hasRunning ? _bootI18n.statusRunning : _bootI18n.statusStopped;
    var refId = first.id;

    return '<div class="mob-card mob-boot-group-card">'
        /* ── 标题行 ── */
        + '<div class="mob-card-header">'
        +   '<span class="mob-dot ' + dotClass + '"></span>'
        +   '<div style="flex:1;min-width:0">'
        +     '<div class="mob-card-title">' + tenancyName + '</div>'
        +     '<div class="mob-card-subtitle">'
        +       '<span class="mob-badge mob-badge-blue" style="margin-right:6px">' + arch + '</span>'
        +       items.length + _bootI18n.taskCount
        +       (hasRunning ? _bootI18n.groupRunning + ' <strong style="color:#43b581">' + runningInGroup + '</strong>' : '')
        +     '</div>'
        +   '</div>'
        +   '<span class="mob-badge ' + badgeClass + '">' + statusText + '</span>'
        + '</div>'
        /* ── 操作行（外层） ── */
        + '<div class="mob-boot-actions">'
        +   (hasRunning
        ?   '<button class="mob-btn mob-btn-stop mob-btn-sm" onclick="stopBoot(' + refId + ', this)">'
        +     '<i class="fas fa-stop"></i> ' + _bootI18n.stop + '</button>'
        :   '<button class="mob-btn mob-btn-primary mob-btn-sm" onclick="startBoot(' + refId + ', this)">'
        +     '<i class="fas fa-play"></i> ' + _bootI18n.startAll + '</button>')
        +   '<button class="mob-btn mob-btn-sm mob-btn-outline" onclick="toggleDetail(\'' + groupId + '\', ' + refId + ')">'
        +     '<i class="fas fa-list-ul"></i> ' + _bootI18n.details + '</button>'
        +   '<button class="mob-btn mob-btn-danger mob-btn-sm" onclick="deleteAllBoot(' + refId + ', this)">'
        +     '<i class="fas fa-trash-alt"></i> ' + _bootI18n.deleteBtn + '</button>'
        + '</div>'
        /* ── 详情展开区（懒加载）── */
        + '<div class="mob-boot-detail" id="' + groupId + '" style="display:none" data-boot-id="' + refId + '">'
        +   '<div class="mob-boot-detail-inner" id="' + groupId + '_inner">'
        +     '<div class="mob-loading" style="padding:16px"><div class="mob-spinner"></div></div>'
        +   '</div>'
        + '</div>'
        + '</div>';
}

/* ── 渲染单个子任务行（紧凑，信息折叠在 ⋮ 后面）── */
function renderDetailItem(b) {
    var isBooted  = b.status === 2;
    var isBooting = b.status === 1;
    var dotClass  = (isBooted || isBooting) ? 'mob-dot-green' : 'mob-dot-gray';
    var statusBadge = isBooted
        ? '<span class="mob-boot-status-badge mob-boot-status-boot">已开机</span>'
        : (isBooting
            ? '<span class="mob-boot-status-badge mob-boot-status-booting">开机中</span>'
            : '<span class="mob-boot-status-badge mob-boot-status-stop">未开机</span>');

    var regionName = escHtml(b.regionName || b.region || '');
    var defName    = escHtml(b.defName || '');
    var label      = defName || (regionName || (_bootI18n.taskPrefix + b.id));

    /* ── 展开信息面板内容 ── */
    var pass    = b.rootPassword || '';
    var os      = (b.operatingSystem || '') + (b.operatingSystemVersion ? ' ' + b.operatingSystemVersion : '');
    var cfg     = (b.ocpu || '-') + 'C / ' + (b.memory || '-') + 'G / ' + (b.disk || '-') + 'G';
    /* 紧凑行展示字段（显示 CPU / 内存 / 磁盘，如 1C/6G/50G） */
    var cfgBrief = (b.ocpu || b.memory || b.disk)
        ? escHtml((b.ocpu || '?') + 'C/' + (b.memory || '?') + 'G/' + (b.disk || '?') + 'G')
        : '';

    var infoRows = '';
    if (os) {
        infoRows += '<div class="mob-bip-row">'
            + '<span class="mob-bip-label">OS</span>'
            + '<span class="mob-bip-val">' + escHtml(os) + '</span>'
            + '</div>';
    }
    infoRows += '<div class="mob-bip-row">'
        + '<span class="mob-bip-label">配置</span>'
        + '<span class="mob-bip-val">' + escHtml(cfg) + '</span>'
        + '</div>'
        + '<div class="mob-bip-row">'
        + '<span class="mob-bip-label">次数</span>'
        + '<span class="mob-bip-val" style="font-size:11px">'
        +   '今日 <strong>' + (b.currentAttemptCount || 0) + '</strong>'
        +   ' · 昨日 <strong>' + (b.yesterdayAttemptCount || 0) + '</strong>'
        +   ' · 成功 <strong style="color:#43b581">' + (b.successCount || 0) + '</strong>'
        +   ' · 失败 <strong style="color:#f04747">' + (b.failCount || 0) + '</strong>'
        + '</span>'
        + '</div>';
    if (pass) {
        infoRows += '<div class="mob-bip-row">'
            + '<span class="mob-bip-label">密码</span>'
            + '<span class="mob-bip-val" id="bootPass_' + b.id + '" data-pass="' + escHtml(pass) + '">••••••••</span>'
            + '<button class="mob-bip-icon" onclick="bootTogglePass(' + b.id + ', this)" title="显示/隐藏"><i class="fas fa-eye"></i></button>'
            + '<button class="mob-bip-icon" onclick="bootCopyPass(' + b.id + ')" title="复制密码"><i class="fas fa-copy"></i></button>'
            + '</div>';
    }

    /* 操作按钮 */
    var toggleBtn = isBooting
        ? '<button class="mob-btn mob-btn-stop mob-btn-xs" onclick="stopBootSingle(' + b.id + ', this)"><i class="fas fa-stop"></i> ' + _bootI18n.stop + '</button>'
        : '<button class="mob-btn mob-btn-primary mob-btn-xs" onclick="startBootSingle(' + b.id + ', this)"><i class="fas fa-play"></i> ' + _bootI18n.start + '</button>';

    /* 序列化编辑用数据（转义单引号）*/
    var editData = escHtml(JSON.stringify({
        id:           b.id,
        ocpu:         b.ocpu,
        memory:       b.memory,
        disk:         b.disk,
        loopTime:     b.loopTime,
        rootPassword: b.rootPassword || '',
        dayGap:       b.dayGap || ''
    }));

    var infoPanel = '<div class="mob-boot-info-panel" id="bootInfo_' + b.id + '" style="display:none">'
        + infoRows
        + '<div class="mob-bip-actions">'
        +   toggleBtn
        +   ' <button class="mob-btn mob-btn-outline mob-btn-xs" onclick="openBootEdit(\'' + editData + '\')">'
        +     '<i class="fas fa-edit"></i> 修改</button>'
        +   ' <button class="mob-btn mob-btn-danger mob-btn-xs" onclick="deleteSingleBoot(' + b.id + ', this)">'
        +     '<i class="fas fa-trash-alt"></i></button>'
        + '</div>'
        + '</div>';

    return '<div class="mob-boot-detail-item" id="detail_' + b.id + '">'
        + '<div class="mob-boot-di-row">'
        +   '<span class="mob-dot ' + dotClass + '" style="flex-shrink:0"></span>'
        +   '<div class="mob-boot-di-content">'
        +     '<span class="mob-boot-detail-name">' + label + '</span>'
        +     (cfgBrief ? '<span class="mob-boot-di-cfg">' + cfgBrief + '</span>' : '')
        +     statusBadge
        +   '</div>'
        +   '<button class="mob-boot-dots-btn" id="dotBtn_' + b.id + '" onclick="toggleBootInfo(' + b.id + ')" title="详情">'
        +     '<i class="fas fa-ellipsis-v"></i>'
        +   '</button>'
        + '</div>'
        + infoPanel
        + '</div>';
}

/* ── ⋮ 展开/收起信息面板 ── */
function toggleBootInfo(bootId) {
    var panel = document.getElementById('bootInfo_' + bootId);
    var btn   = document.getElementById('dotBtn_' + bootId);
    if (!panel) return;
    var open = panel.style.display !== 'none';
    panel.style.display = open ? 'none' : 'block';
    if (btn) btn.classList.toggle('active', !open);
}

/* ── 密码显示切换 ── */
function bootTogglePass(bootId, btn) {
    var el = document.getElementById('bootPass_' + bootId);
    if (!el) return;
    var showing = el.dataset.showing === '1';
    if (showing) {
        el.textContent = '••••••••';
        el.dataset.showing = '0';
        btn.innerHTML = '<i class="fas fa-eye"></i>';
    } else {
        el.textContent = el.dataset.pass || '';
        el.dataset.showing = '1';
        btn.innerHTML = '<i class="fas fa-eye-slash"></i>';
    }
}

function bootCopyPass(bootId) {
    var el = document.getElementById('bootPass_' + bootId);
    if (!el) return;
    mobCopy(el.dataset.pass || '');
}

/* ════════════════════════════════════════════════
   编辑子任务
   ════════════════════════════════════════════════ */
function openBootEdit(dataStr) {
    var d = JSON.parse(dataStr);
    document.getElementById('befId').value       = d.id;
    document.getElementById('befOcpu').value     = d.ocpu || '';
    document.getElementById('befMemory').value   = d.memory || '';
    document.getElementById('befDisk').value     = d.disk || '';
    document.getElementById('befLoopTime').value = d.loopTime || '';
    document.getElementById('befDayGap').value   = d.dayGap || '';
    document.getElementById('befPassword').value = d.rootPassword || '';
    document.getElementById('bootEditOverlay').style.display = 'flex';
}

function closeBootEdit(e) {
    if (e && e.target !== document.getElementById('bootEditOverlay')) return;
    document.getElementById('bootEditOverlay').style.display = 'none';
}

async function saveBootEdit() {
    var id = document.getElementById('befId').value;
    if (!id) return;

    /* dayGap 格式校验（与 PC 一致） */
    var dayGap = document.getElementById('befDayGap').value.trim();
    if (dayGap) {
        var m = dayGap.match(/^(\d{1,2})-(\d{1,2})$/);
        if (!m) { mobToast('时间范围格式错误，示例：0-8', 'error'); return; }
        var s = parseInt(m[1]), e2 = parseInt(m[2]);
        if (s < 0 || s > 23 || e2 < 1 || e2 > 24 || s >= e2) {
            mobToast('时间范围数值超出范围或起始≥结束', 'error'); return;
        }
    }

    var btn = document.getElementById('befSaveBtn');
    btn.disabled = true; btn.textContent = '保存中…';

    var csrf = getCsrf();
    var headers = { 'Content-Type': 'application/json' };
    headers[csrf.header] = csrf.token;

    try {
        var res = await fetch('/boot/updateBoot', {
            method: 'POST',
            headers: headers,
            body: JSON.stringify({
                id:           id,
                ocpu:         parseInt(document.getElementById('befOcpu').value) || 0,
                memory:       parseInt(document.getElementById('befMemory').value) || 0,
                disk:         parseInt(document.getElementById('befDisk').value) || 0,
                loopTime:     parseInt(document.getElementById('befLoopTime').value) || 0,
                dayGap:       dayGap,
                rootPassword: document.getElementById('befPassword').value
            })
        });
        var json = await res.json();
        if (json.success || json.code === 200) {
            mobToast('保存成功', 'success');
            document.getElementById('bootEditOverlay').style.display = 'none';
            setTimeout(loadBoots, 600);
        } else {
            mobToast(json.message || '保存失败', 'error');
        }
    } catch (e) {
        mobToast(_bootI18n.requestFail, 'error');
    }
    btn.disabled = false; btn.textContent = '保存';
}

/* ════════════════════════════════════════════════
   展开/收起详情（懒加载子任务）
   ════════════════════════════════════════════════ */
async function toggleDetail(groupId, bootId) {
    var el = document.getElementById(groupId);
    if (!el) return;
    var isOpen = el.style.display !== 'none';
    if (isOpen) {
        el.style.display = 'none';
        return;
    }
    el.style.display = 'block';

    var inner = document.getElementById(groupId + '_inner');
    if (inner && inner.dataset.loaded) return;

    if (inner) {
        inner.innerHTML = '<div class="mob-loading" style="padding:16px"><div class="mob-spinner"></div><p>' + _bootI18n.loading + '</p></div>';
    }

    try {
        var res = await fetch('/m/api/boot/' + bootId + '/subtasks');
        var json = await res.json();
        var list = json.data || [];
        if (inner) {
            if (list.length === 0) {
                inner.innerHTML = '<p class="mob-card-subtitle" style="padding:8px 12px">' + _bootI18n.noSubtasks + '</p>';
            } else {
                inner.innerHTML = list.map(function(b) { return renderDetailItem(b); }).join('');
            }
            inner.dataset.loaded = '1';
        }
    } catch (e) {
        if (inner) {
            inner.innerHTML = '<p style="color:#f04747;font-size:13px;padding:8px 12px">' + _bootI18n.subtaskLoadFail + ' ' + e.message + '</p>';
        }
    }
}

/* ════════════════════════════════════════════════
   CSRF 工具
   ════════════════════════════════════════════════ */
function getCsrf() {
    var meta = document.querySelector('meta[name="_csrf"]');
    var headerMeta = document.querySelector('meta[name="_csrf_header"]');
    return {
        token: meta ? meta.getAttribute('content') : '',
        header: headerMeta ? headerMeta.getAttribute('content') : 'X-CSRF-TOKEN'
    };
}

async function apiPost(url, btn, loadingText) {
    if (btn) { btn.disabled = true; btn._orig = btn.innerHTML; btn.innerHTML = loadingText || '<i class="fas fa-spinner fa-spin"></i>'; }
    var c = getCsrf();
    var headers = { 'Content-Type': 'application/json' };
    headers[c.header] = c.token;
    var res = await fetch(url, { method: 'POST', headers: headers });
    return res.json();
}

/* ════════════════════════════════════════════════
   启动/停止（全组）
   ════════════════════════════════════════════════ */
async function startBoot(bootId, btn) {
    try {
        var json = await apiPost('/m/api/boot/' + bootId + '/start', btn, '<i class="fas fa-spinner fa-spin"></i>');
        if (json.success || json.code === 200) {
            mobToast(_bootI18n.startOk, 'success');
            setTimeout(loadBoots, 800);
        } else {
            mobToast(json.message || _bootI18n.startFail, 'error');
            if (btn) { btn.disabled = false; btn.innerHTML = btn._orig; }
        }
    } catch (e) {
        mobToast(_bootI18n.requestFail, 'error');
        if (btn) { btn.disabled = false; btn.innerHTML = btn._orig; }
    }
}

async function stopBoot(bootId, btn) {
    try {
        var json = await apiPost('/m/api/boot/' + bootId + '/stop', btn, '<i class="fas fa-spinner fa-spin"></i>');
        if (json.success || json.code === 200) {
            mobToast(_bootI18n.stopOk, 'success');
            setTimeout(loadBoots, 800);
        } else {
            mobToast(json.message || _bootI18n.stopFail, 'error');
            if (btn) { btn.disabled = false; btn.innerHTML = btn._orig; }
        }
    } catch (e) {
        mobToast(_bootI18n.requestFail, 'error');
        if (btn) { btn.disabled = false; btn.innerHTML = btn._orig; }
    }
}

/* ════════════════════════════════════════════════
   启动/停止（单个）
   ════════════════════════════════════════════════ */
async function startBootSingle(bootId, btn) {
    try {
        var json = await apiPost('/m/api/boot/' + bootId + '/start', btn, '<i class="fas fa-spinner fa-spin"></i>');
        if (json.success || json.code === 200) {
            mobToast(_bootI18n.startOk, 'success');
            setTimeout(loadBoots, 800);
        } else {
            mobToast(json.message || _bootI18n.startFail, 'error');
            if (btn) { btn.disabled = false; btn.innerHTML = btn._orig; }
        }
    } catch (e) {
        mobToast(_bootI18n.requestFail, 'error');
        if (btn) { btn.disabled = false; btn.innerHTML = btn._orig; }
    }
}

async function stopBootSingle(bootId, btn) {
    try {
        var json = await apiPost('/m/api/boot/' + bootId + '/stop', btn, '<i class="fas fa-spinner fa-spin"></i>');
        if (json.success || json.code === 200) {
            mobToast(_bootI18n.stopOk, 'success');
            setTimeout(loadBoots, 800);
        } else {
            mobToast(json.message || _bootI18n.stopFail, 'error');
            if (btn) { btn.disabled = false; btn.innerHTML = btn._orig; }
        }
    } catch (e) {
        mobToast(_bootI18n.requestFail, 'error');
        if (btn) { btn.disabled = false; btn.innerHTML = btn._orig; }
    }
}

/* ════════════════════════════════════════════════
   删除
   ════════════════════════════════════════════════ */
async function deleteSingleBoot(bootId, btn) {
    var ok = await mobConfirm(_bootI18n.confirmDeleteSingle, _bootI18n.confirmDeleteSingleMsg);
    if (!ok) return;
    try {
        var json = await apiPost('/m/api/boot/' + bootId + '/delete', btn, '<i class="fas fa-spinner fa-spin"></i>');
        if (json.success || json.code === 200) {
            mobToast(_bootI18n.deleteOk, 'success');
            setTimeout(loadBoots, 500);
        } else {
            mobToast(json.message || _bootI18n.deleteFail, 'error');
            if (btn) { btn.disabled = false; btn.innerHTML = btn._orig; }
        }
    } catch (e) {
        mobToast(_bootI18n.requestFail, 'error');
        if (btn) { btn.disabled = false; btn.innerHTML = btn._orig; }
    }
}

async function deleteAllBoot(bootId, btn) {
    var ok = await mobConfirm(_bootI18n.confirmDeleteAll, _bootI18n.confirmDeleteAllMsg);
    if (!ok) return;
    try {
        var json = await apiPost('/m/api/boot/' + bootId + '/deleteAll', btn, '<i class="fas fa-spinner fa-spin"></i>');
        if (json.success || json.code === 200) {
            mobToast(_bootI18n.deleteAllOk, 'success');
            setTimeout(loadBoots, 500);
        } else {
            mobToast(json.message || _bootI18n.deleteFail, 'error');
            if (btn) { btn.disabled = false; btn.innerHTML = btn._orig; }
        }
    } catch (e) {
        mobToast(_bootI18n.requestFail, 'error');
        if (btn) { btn.disabled = false; btn.innerHTML = btn._orig; }
    }
}

function escHtml(s) {
    if (!s) return '';
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

loadBoots();
</script>
</#noparse>

</@layout.page>
