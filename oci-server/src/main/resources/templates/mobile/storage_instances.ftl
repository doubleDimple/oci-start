<#import "layout.ftl" as layout>
<@layout.page title="存储实例" activePage="tenants">

<style>
/* 实例卡片 */
.si-card {
    background:var(--mob-card);border:1px solid var(--mob-border);border-radius:12px;
    margin-bottom:12px;overflow:hidden;
}
.si-card-head { display:flex;align-items:center;gap:12px;padding:13px 14px 11px }
.si-db-icon {
    width:40px;height:40px;border-radius:10px;background:rgba(155,89,182,0.12);
    display:flex;align-items:center;justify-content:center;
    color:#9b59b6;font-size:18px;flex-shrink:0;
}
.si-head-info { flex:1;min-width:0 }
.si-name { font-size:14px;font-weight:700;color:var(--mob-text);overflow:hidden;text-overflow:ellipsis;white-space:nowrap }
.si-version { font-size:11px;color:var(--mob-text-muted);margin-top:2px }
.si-status-badge {
    padding:3px 9px;border-radius:20px;font-size:10px;font-weight:700;white-space:nowrap;flex-shrink:0;
}
.si-status-active   { background:rgba(67,181,129,0.15); color:#43b581 }
.si-status-creating { background:rgba(250,166,26,0.15);  color:#faa61a }
.si-status-failed   { background:rgba(240,71,71,0.15);   color:#f04747 }
.si-status-other    { background:rgba(114,118,125,0.12); color:#72767d }

/* 磁盘/规格 */
.si-stats {
    display:grid;grid-template-columns:1fr 1fr 1fr;gap:6px;padding:0 14px 12px;
}
.si-stat { background:var(--mob-bg);border-radius:8px;padding:8px 10px }
.si-stat-label { font-size:10px;color:var(--mob-text-muted);letter-spacing:0.3px }
.si-stat-value { font-size:13px;font-weight:700;color:var(--mob-text);margin-top:2px }

/* 账密/IP 行 */
.si-pass-row {
    display:flex;align-items:center;gap:8px;padding:7px 14px;
    border-top:1px solid var(--mob-border);
}
.si-pass-label { font-size:11px;color:var(--mob-text-muted);width:34px;flex-shrink:0;font-weight:600 }
.si-pass-val { flex:1;font-size:12px;font-family:monospace;color:var(--mob-text);word-break:break-all }
.si-pass-icon { border:none;background:none;padding:4px 6px;cursor:pointer;color:var(--mob-text-muted);font-size:13px;border-radius:4px;flex-shrink:0 }
.si-pass-icon:active { color:#9b59b6 }

/* 操作区 */
.si-actions {
    display:flex;flex-wrap:wrap;gap:8px;padding:10px 14px 14px;border-top:1px solid var(--mob-border);
}

/* 新建面板 */
.si-create-panel {
    background:var(--mob-card);border:1px solid rgba(155,89,182,0.3);border-radius:12px;
    padding:14px;margin-bottom:14px;
}
.si-create-title { font-size:13px;font-weight:700;color:var(--mob-text);margin-bottom:6px;display:flex;align-items:center;gap:6px }
.si-create-hint { font-size:11px;color:var(--mob-text-muted);margin-bottom:12px;line-height:1.5 }

/* 同步按钮区 */
.si-top-bar { display:flex;gap:8px;margin-bottom:14px }
</style>

<!-- 返回栏 -->
<div style="display:flex;align-items:center;gap:12px;margin-bottom:16px">
    <button onclick="history.back()" style="width:36px;height:36px;border-radius:50%;border:1.5px solid var(--mob-border);background:var(--mob-card);color:var(--mob-text);display:flex;align-items:center;justify-content:center;cursor:pointer;flex-shrink:0;padding:0">
        <i class="fas fa-chevron-left" style="font-size:13px"></i>
    </button>
    <div style="flex:1;min-width:0">
        <div style="font-size:16px;font-weight:700;color:var(--mob-text)">存储实例</div>
        <div style="font-size:11px;color:var(--mob-text-muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap" id="siTenantName">—</div>
    </div>
</div>

<!-- 操作栏 -->
<div class="si-top-bar">
    <button class="mob-btn mob-btn-outline mob-btn-sm" id="syncCloudBtn" style="flex:1" onclick="syncFromCloud(this)">
        <i class="fas fa-cloud-download-alt"></i> 从云端同步
    </button>
    <button class="mob-btn mob-btn-outline mob-btn-sm" style="flex:1" onclick="loadInstances()">
        <i class="fas fa-sync-alt"></i> 刷新
    </button>
</div>

<!-- 新建面板 -->
<div class="si-create-panel">
    <div class="si-create-title"><i class="fas fa-plus-circle" style="color:#9b59b6"></i>创建 MySQL 实例</div>
    <div class="si-create-hint">将在当前租户账号下申请一个 OCI MySQL HeatWave 免费实例（每账号限一个）。</div>
    <button class="mob-btn" style="width:100%;background:#9b59b6;color:#fff;border:none;font-weight:700" onclick="createMysql()">
        <i class="fas fa-database"></i> 立即创建
    </button>
</div>

<!-- 加载中 -->
<div class="mob-loading" id="siLoading"><div class="mob-spinner"></div><p>加载中...</p></div>
<!-- 实例列表 -->
<div id="siList" style="display:none"></div>

<!-- ══ 操作确认弹窗（通用） ══ -->
<div id="siConfirmModal" class="mob-center-overlay" style="display:none" onclick="closeSiConfirm(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-width:340px">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title" id="siConfirmTitle">确认操作</div>
            <button class="mob-sheet-close" onclick="closeSiConfirm()"><i class="fas fa-times"></i></button>
        </div>
        <div style="padding:16px 16px 8px">
            <p style="color:var(--mob-text);font-size:14px;line-height:1.6" id="siConfirmMsg">确认执行此操作吗？</p>
        </div>
        <div style="padding:8px 16px 20px;display:flex;gap:10px">
            <button class="mob-btn mob-btn-outline" style="flex:1" onclick="closeSiConfirm()">取消</button>
            <button class="mob-btn" id="siConfirmOkBtn" style="flex:1;background:#9b59b6;color:#fff;border:none" onclick="executeSiConfirm()">确认</button>
        </div>
    </div>
</div>

<script>
var _siTenantId   = '${tenantId}';
var _siTenantName = '${tenantName}';
var _siConfirmFn  = null;
</script>
<#noparse>
<script>
document.getElementById('siTenantName').textContent = _siTenantName || _siTenantId || '—';

/* ══ 加载实例列表 ══ */
async function loadInstances() {
    document.getElementById('siLoading').style.display = '';
    document.getElementById('siList').style.display = 'none';
    try {
        var res  = await fetch('/tenants/mysql-info?tenantId=' + encodeURIComponent(_siTenantId));
        var json = await res.json();
        renderInstances(json.data || json || []);
    } catch(e) {
        document.getElementById('siLoading').innerHTML = '<p style="color:#f04747;text-align:center">加载失败：' + e.message + '</p>';
    }
}

function getStatusClass(status) {
    if (!status) return 'si-status-other';
    var s = status.toUpperCase();
    if (s === 'ACTIVE') return 'si-status-active';
    if (s === 'CREATING' || s === 'UPDATING') return 'si-status-creating';
    if (s === 'FAILED') return 'si-status-failed';
    return 'si-status-other';
}

function renderInstances(list) {
    var loading = document.getElementById('siLoading');
    var listEl  = document.getElementById('siList');
    loading.style.display = 'none';
    listEl.style.display  = 'block';

    if (!list || list.length === 0) {
        listEl.innerHTML = '<div class="mob-empty"><i class="fas fa-database"></i><p>暂无存储实例</p></div>';
        return;
    }

    listEl.innerHTML = list.map(function(item) {
        var name    = escH(item.displayName || '未命名');
        var version = escH(item.dbVersion || '—');
        var status  = escH(item.dbStatus || item.lifecycleState || '—');
        var shape   = escH(item.shapeName || '—');
        var size    = item.dataStorageSizeInGBs || '—';
        var pass    = item.dbPassword || '';
        var id      = escH(String(item.id || ''));
        var statusClass = getStatusClass(item.dbStatus || item.lifecycleState);

        var user      = item.dbName || '';
        var credVal   = user ? (user + ' / ' + pass) : pass;
        var publicIp  = item.dbPublicUrl  || '';
        var privateIp = item.dbPrivateUrl || '';

        /* 公网IP 行：始终显示 */
        var publicIpRow;
        if (publicIp) {
            var port     = item.dbPort ? ':' + item.dbPort : '';
            var ipDisp   = escH(publicIp) + (port ? '<span style="color:#9b59b6;font-weight:700">' + escH(port) + '</span>' : '');
            var ipCopyVal = publicIp + (item.dbPort ? ':' + item.dbPort : '');
            publicIpRow = '<div class="si-pass-row">'
                + '<span class="si-pass-label">公网IP</span>'
                + '<span class="si-pass-val">' + ipDisp + '</span>'
                + '<button class="si-pass-icon" onclick="mobCopy(\'' + escH(ipCopyVal) + '\')" title="复制公网IP:端口"><i class="fas fa-copy"></i></button>'
                + '</div>';
        } else {
            publicIpRow = '<div class="si-pass-row">'
                + '<span class="si-pass-label">公网IP</span>'
                + '<span style="font-size:12px;color:var(--mob-text-muted);padding:0 4px">未绑定</span>'
                + '</div>';
        }

        /* 内网IP 行：有值才显示 */
        var privateIpRow = privateIp
            ? '<div class="si-pass-row">'
            +   '<span class="si-pass-label">内网IP</span>'
            +   '<span class="si-pass-val">' + escH(privateIp) + '</span>'
            +   '<button class="si-pass-icon" onclick="mobCopy(\'' + escH(privateIp) + '\')" title="复制内网IP"><i class="fas fa-copy"></i></button>'
            + '</div>'
            : '';

        /* 账密行 */
        var credRow = (pass || user)
            ? '<div class="si-pass-row">'
            +   '<span class="si-pass-label">账密</span>'
            +   '<span class="si-pass-val" id="siPass_' + id + '" data-pass="' + escH(credVal) + '">••••••••</span>'
            +   '<button class="si-pass-icon" onclick="siTogglePass(\'' + id + '\', this)" title="显示/隐藏"><i class="fas fa-eye"></i></button>'
            +   '<button class="si-pass-icon" onclick="mobCopy(\'' + escH(credVal) + '\')" title="复制账密"><i class="fas fa-copy"></i></button>'
            + '</div>'
            : '';

        return '<div class="si-card">'
            + '<div class="si-card-head">'
            +   '<div class="si-db-icon"><i class="fas fa-database"></i></div>'
            +   '<div class="si-head-info">'
            +     '<div class="si-name">' + name + '</div>'
            +     '<div class="si-version">MySQL ' + version + '</div>'
            +   '</div>'
            +   '<span class="si-status-badge ' + statusClass + '">' + status + '</span>'
            + '</div>'
            + '<div class="si-stats">'
            +   '<div class="si-stat"><div class="si-stat-label">SHAPE</div><div class="si-stat-value" style="font-size:11px">' + shape + '</div></div>'
            +   '<div class="si-stat"><div class="si-stat-label">DISK (GB)</div><div class="si-stat-value" style="color:#9b59b6">' + size + '</div></div>'
            +   '<div class="si-stat"><div class="si-stat-label">VERSION</div><div class="si-stat-value" style="color:#1abc9c">' + version + '</div></div>'
            + '</div>'
            + publicIpRow
            + privateIpRow
            + credRow
            + '<div class="si-actions">'
            +   '<button class="mob-btn mob-btn-outline mob-btn-sm" style="flex:1" onclick="syncSingleInstance(this, \'' + id + '\')">'
            +     '<i class="fas fa-sync"></i> 同步</button>'
            +   '<button class="mob-btn mob-btn-outline mob-btn-sm" style="flex:1;color:#faa61a;border-color:rgba(250,166,26,0.4)" onclick="resetAuth(\'' + id + '\')">'
            +     '<i class="fas fa-key"></i> 重置密码</button>'
            +   '<button class="mob-btn mob-btn-outline mob-btn-sm" style="flex:1;color:#5b8af0;border-color:rgba(91,138,240,0.4)" onclick="bindIp(\'' + id + '\')">'
            +     '<i class="fas fa-globe"></i> 绑定IP</button>'
            +   '<button class="mob-btn mob-btn-sm" style="flex:1;background:rgba(240,71,71,0.1);color:#f04747;border:1px solid rgba(240,71,71,0.3)" onclick="terminateInstance(\'' + id + '\', \'' + name + '\')">'
            +     '<i class="fas fa-trash-alt"></i> 终止</button>'
            + '</div>'
            + '</div>';
    }).join('');
}

/* ══ 密码切换 ══ */
function siTogglePass(id, btn) {
    var el = document.getElementById('siPass_' + id);
    if (!el) return;
    if (el.dataset.showing === '1') {
        el.textContent = '••••••••';
        el.dataset.showing = '0';
        btn.innerHTML = '<i class="fas fa-eye"></i>';
    } else {
        el.textContent = el.dataset.pass || '';
        el.dataset.showing = '1';
        btn.innerHTML = '<i class="fas fa-eye-slash"></i>';
    }
}

/* ══ 公共：带错误处理的请求（CSRF token 同时以 header + URL 参数两种方式发送）══ */
async function siPost(url, opts) {
    var csrfToken  = (document.querySelector('meta[name="_csrf"]')        || {}).content || '';
    var csrfHeader = (document.querySelector('meta[name="_csrf_header"]') || {}).content || 'X-CSRF-TOKEN';
    /* 1. URL 参数 _csrf（Servlet getParameter 能从 query string 读取）*/
    if (csrfToken) {
        url += (url.indexOf('?') >= 0 ? '&' : '?') + '_csrf=' + encodeURIComponent(csrfToken);
    }
    /* 2. 同时合并到 header */
    opts = opts || {};
    var h = opts.headers ? Object.assign({}, opts.headers) : {};
    h[csrfHeader] = csrfToken;
    opts.headers = h;
    var res = await fetch(url, opts);
    if (!res.ok) throw new Error('HTTP ' + res.status);
    return res.json();
}

/* ══ 从云端同步（直接调用）══ */
async function syncFromCloud(btn) {
    var orig = btn ? btn.innerHTML : '';
    if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> 同步中…'; }
    try {
        var json = await siPost('/tenants/sync-mysql?tenantId=' + encodeURIComponent(_siTenantId), { method: 'POST' });
        if (json.success) { mobToast(json.message || '同步完成', 'success'); loadInstances(); }
        else mobToast(json.message || '同步失败', 'error');
    } catch(e) { mobToast('同步请求失败：' + e.message, 'error'); }
    if (btn) { btn.disabled = false; btn.innerHTML = orig; }
}

/* ══ 单实例同步（直接调用）══ */
async function syncSingleInstance(btn, id) {
    var orig = btn ? btn.innerHTML : '';
    if (btn) { btn.disabled = true; btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i>'; }
    try {
        var json = await siPost('/tenants/sync-single-mysql?id=' + encodeURIComponent(id), { method: 'POST' });
        if (json.success) { mobToast('同步成功', 'success'); loadInstances(); }
        else mobToast(json.message || '同步失败', 'error');
    } catch(e) { mobToast('同步请求失败：' + e.message, 'error'); }
    if (btn) { btn.disabled = false; btn.innerHTML = orig; }
}

/* ══ 重置密码 ══ */
function resetAuth(id) {
    showSiConfirm('重置认证信息', '将重置此 MySQL 实例的管理员密码。操作不可撤销。', '#faa61a', async function() {
        try {
            var json = await siPost('/tenants/mysql-reset-auth?id=' + encodeURIComponent(id) + '&tenantId=' + encodeURIComponent(_siTenantId), { method: 'POST' });
            if (json.success) { mobToast('重置成功，请刷新查看新密码', 'success'); loadInstances(); }
            else mobToast(json.message || '重置失败', 'error');
        } catch(e) { mobToast('重置请求失败：' + e.message, 'error'); }
    });
}

/* ══ 绑定公网 IP ══ */
function bindIp(id) {
    showSiConfirm('绑定公网 IP', '将为此 MySQL 免费实例绑定一个公网 IP 地址。', '#5b8af0', async function() {
        try {
            var json = await siPost('/tenants/bind-public-ip?id=' + encodeURIComponent(id), { method: 'POST' });
            if (json.success) { mobToast(json.message || '绑定成功', 'success'); loadInstances(); }
            else mobToast(json.message || '绑定失败', 'error');
        } catch(e) { mobToast('绑定请求失败：' + e.message, 'error'); }
    });
}

/* ══ 终止实例 ══ */
function terminateInstance(id, name) {
    showSiConfirm('终止实例',
        '确认终止存储实例 ' + name + ' 吗？此操作不可恢复，所有数据将被销毁。',
        '#f04747',
        async function() {
            try {
                var json = await siPost('/tenants/mysql-action', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ action: 'delete', id: id })
                });
                if (json.success) { mobToast('终止请求已发送', 'success'); loadInstances(); }
                else mobToast(json.message || '操作失败', 'error');
            } catch(e) { mobToast('终止请求失败：' + e.message, 'error'); }
        }
    );
}

/* ══ 创建 MySQL ══ */
function createMysql() {
    showSiConfirm('创建 MySQL 实例',
        '将在当前租户下申请 OCI MySQL HeatWave 免费实例（需账号有可用配额）。',
        '#9b59b6', async function() {
            try {
                var json = await siPost('/tenants/mysql-create?tenantId=' + encodeURIComponent(_siTenantId), { method: 'POST' });
                if (json.success) { mobToast(json.message || '创建请求已提交', 'success'); loadInstances(); }
                else mobToast(json.message || '创建失败', 'error');
            } catch(e) { mobToast('创建请求失败：' + e.message, 'error'); }
        });
}

/* ══ 通用确认弹窗 ══ */
function showSiConfirm(title, msg, color, fn) {
    _siConfirmFn = fn;
    document.getElementById('siConfirmTitle').textContent = title;
    document.getElementById('siConfirmMsg').textContent   = msg;
    var btn = document.getElementById('siConfirmOkBtn');
    btn.style.background = color || '#9b59b6';
    btn.textContent = '确认';
    btn.disabled = false;
    document.getElementById('siConfirmModal').style.display = 'flex';
}

function closeSiConfirm(e) {
    if (e && e.target !== document.getElementById('siConfirmModal')) return;
    document.getElementById('siConfirmModal').style.display = 'none';
}

async function executeSiConfirm() {
    var btn = document.getElementById('siConfirmOkBtn');
    btn.disabled = true; btn.textContent = '处理中…';
    try {
        if (_siConfirmFn) await _siConfirmFn();
    } catch(e) {
        mobToast('请求异常：' + e.message, 'error');
    }
    btn.disabled = false;
    document.getElementById('siConfirmModal').style.display = 'none';
}

function escH(s) {
    if (!s) return '';
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function mobCopy(text) {
    if (!text) return;
    if (navigator.clipboard) { navigator.clipboard.writeText(text).then(function() { mobToast('已复制', 'success'); }); }
    else { var t = document.createElement('textarea'); t.value = text; document.body.appendChild(t); t.select(); document.execCommand('copy'); document.body.removeChild(t); mobToast('已复制', 'success'); }
}

function mobToast(msg, type) {
    var t = document.createElement('div');
    t.style.cssText = 'position:fixed;bottom:80px;left:50%;transform:translateX(-50%);background:'
        + (type==='error'?'#f04747':'#43b581')
        + ';color:#fff;padding:10px 20px;border-radius:20px;font-size:13px;z-index:9999;pointer-events:none;white-space:nowrap;box-shadow:0 4px 12px rgba(0,0,0,0.3)';
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(function() { t.remove(); }, 2800);
}

loadInstances();
</script>
</#noparse>

</@layout.page>
