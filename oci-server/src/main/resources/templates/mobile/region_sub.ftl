<#import "layout.ftl" as layout>
<@layout.page title="区域订阅" activePage="tenants">

<!-- 顶部返回栏 -->
<div style="display:flex;align-items:center;gap:12px;margin-bottom:16px">
    <button onclick="window.location.href='/m/tenants?menuId='+encodeURIComponent(_rsTenantId)" style="width:36px;height:36px;border-radius:50%;border:1.5px solid var(--mob-border);background:var(--mob-card);color:var(--mob-text);display:flex;align-items:center;justify-content:center;cursor:pointer;flex-shrink:0;padding:0">
        <i class="fas fa-chevron-left" style="font-size:13px"></i>
    </button>
    <div style="flex:1;min-width:0">
        <div style="font-size:16px;font-weight:700;color:var(--mob-text)">区域订阅</div>
        <div style="font-size:11px;color:var(--mob-text-muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap" id="rsTenantName">—</div>
    </div>
</div>

<style>
.rs-tab-bar { display:flex;gap:2px;background:rgba(118,118,128,0.12);border-radius:11px;padding:2px;margin-bottom:14px }
.rs-tab-btn { flex:1;padding:8px 4px;border-radius:9px;border:none;font-size:13px;font-weight:600;cursor:pointer;transition:all .22s cubic-bezier(.34,1.26,.64,1);background:transparent;color:rgba(60,60,67,0.6) }
html[data-theme="dark"] .rs-tab-btn { color:rgba(235,235,245,0.55) }
.rs-tab-btn.active { background:#fff;color:#1abc9c;box-shadow:0 1px 4px rgba(0,0,0,0.13),0 1px 2px rgba(0,0,0,0.08) }
html[data-theme="dark"] .rs-tab-btn.active { background:rgba(255,255,255,0.14);color:#1abc9c;box-shadow:0 1px 4px rgba(0,0,0,0.3) }
</style>

<!-- Tab 切换 -->
<div class="rs-tab-bar">
    <button id="tabBtnSubscribed" class="rs-tab-btn active" onclick="switchTab('subscribed')">
        <i class="fas fa-check-circle" style="margin-right:4px"></i>已订阅
    </button>
    <button id="tabBtnAvailable" class="rs-tab-btn" onclick="switchTab('available')">
        <i class="fas fa-plus-circle" style="margin-right:4px"></i>可订阅
    </button>
</div>

<!-- 已订阅区域 -->
<div id="tabSubscribed">
    <div class="mob-loading" id="subLoading"><div class="mob-spinner"></div></div>
    <div id="subList"></div>
</div>

<!-- 可订阅区域 -->
<div id="tabAvailable" style="display:none">
    <div id="batchBar" style="display:none;align-items:center;gap:8px;margin-bottom:10px;padding:10px;background:var(--mob-card);border-radius:10px">
        <span style="flex:1;font-size:13px;color:var(--mob-text)">已选 <strong id="selCount">0</strong> 个</span>
        <button class="mob-btn mob-btn-outline mob-btn-sm" onclick="clearSel()">清空</button>
        <button class="mob-btn mob-btn-sm" onclick="batchSubscribe()" style="background:#1abc9c;color:#fff;border:none">批量订阅</button>
    </div>
    <div class="mob-loading" id="availLoading"><div class="mob-spinner"></div></div>
    <div id="availList"></div>
</div>

<!-- 订阅进度弹窗 -->
<div id="subProgressModal" class="mob-center-overlay" style="display:none" onclick="event.stopPropagation()">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-width:340px">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title"><i class="fas fa-globe" style="color:#5b8af0;margin-right:6px"></i>订阅中</div>
        </div>
        <div id="subProgressBody" style="padding:16px;font-size:13px;line-height:1.8;max-height:300px;overflow-y:auto"></div>
        <div style="padding:0 16px 16px">
            <button id="subProgressClose" class="mob-btn" style="width:100%;background:#1abc9c;color:#fff;border:none" onclick="closeSubProgress()" disabled>完成</button>
        </div>
    </div>
</div>

<script>
var _rsTenantId   = '${tenantId!}';
var _rsTenantName = '${tenantName!}';
var _selectedKeys = [];
</script>
<#noparse>
<script>
document.getElementById('rsTenantName').textContent = _rsTenantName || '—';

/* ══ Tab 切换 ══ */
function switchTab(tab) {
    var isSubscribed = tab === 'subscribed';
    document.getElementById('tabSubscribed').style.display  = isSubscribed ? '' : 'none';
    document.getElementById('tabAvailable').style.display   = isSubscribed ? 'none' : '';
    document.getElementById('tabBtnSubscribed').classList.toggle('active', isSubscribed);
    document.getElementById('tabBtnAvailable').classList.toggle('active', !isSubscribed);
    if (!isSubscribed && document.getElementById('availList').innerHTML === '') loadAvailable();
}

/* ══ 已订阅区域 ══ */
async function loadSubscribed() {
    document.getElementById('subLoading').style.display = '';
    document.getElementById('subList').innerHTML = '';
    try {
        var res  = await fetch('/tenants/subscribed-regions-data?tenantId=' + encodeURIComponent(_rsTenantId));
        var data = await res.json();
        renderSubscribed(data);
    } catch(e) {
        document.getElementById('subLoading').style.display = 'none';
        document.getElementById('subList').innerHTML = '<p style="color:#f04747;text-align:center;padding:20px">加载失败: ' + escHtml(e.message) + '</p>';
    }
}

function renderSubscribed(regions) {
    document.getElementById('subLoading').style.display = 'none';
    if (!regions || regions.length === 0) {
        document.getElementById('subList').innerHTML =
            '<p style="text-align:center;color:var(--mob-text-muted);padding:32px 0">暂无已订阅区域</p>';
        return;
    }
    document.getElementById('subList').innerHTML = regions.map(function(r) {
        var status = r.status && r.status.value ? r.status.value : 'UNKNOWN';
        var isReady = status === 'READY';
        var statusColor = isReady ? '#43b581' : '#faa61a';
        var isHome = r.isHomeRegion;
        return '<div class="mob-card" style="margin-bottom:10px;padding:14px">'
            + '<div style="display:flex;align-items:center;gap:10px">'
            + '<div style="flex:1;min-width:0">'
            + '<div style="font-size:14px;font-weight:700;color:var(--mob-text)">'
            + escHtml(r.regionName || r.regionKey)
            + (isHome ? ' <span style="font-size:10px;color:#faa61a;background:rgba(250,166,26,0.1);padding:1px 6px;border-radius:10px">主区</span>' : '')
            + '</div>'
            + '<div style="font-size:11px;color:var(--mob-text-muted);margin-top:2px">' + escHtml(r.regionKey) + '</div>'
            + '</div>'
            + '<div style="display:flex;align-items:center;gap:8px">'
            + '<span style="font-size:12px;font-weight:700;color:' + statusColor + '">' + status + '</span>'
            + (!isReady ? '<button class="mob-btn mob-btn-outline mob-btn-sm" style="padding:0 8px;height:28px" onclick="checkStatus(\'' + escHtml(r.regionKey) + '\')" title="刷新状态"><i class="fas fa-sync-alt"></i></button>' : '')
            + '</div>'
            + '</div>'
            + '</div>';
    }).join('');
}

async function checkStatus(regionKey) {
    var csrf = (document.querySelector('meta[name="_csrf"]')||{}).content||'';
    try {
        var res  = await fetch('/tenants/check-subscription-status?tenantId=' + encodeURIComponent(_rsTenantId) + '&regionKey=' + encodeURIComponent(regionKey), {
            headers: { 'X-CSRF-TOKEN': csrf }
        });
        await res.json();
        loadSubscribed();
    } catch(e) { rsToast('刷新失败: ' + e.message, 'error'); }
}

/* ══ 可订阅区域 ══ */
async function loadAvailable() {
    document.getElementById('availLoading').style.display = '';
    document.getElementById('availList').innerHTML = '';
    _selectedKeys = [];
    updateBatchBar();
    try {
        var res  = await fetch('/tenants/unsubscribed-regions?tenantId=' + encodeURIComponent(_rsTenantId));
        var data = await res.json();
        renderAvailable(data);
    } catch(e) {
        document.getElementById('availLoading').style.display = 'none';
        document.getElementById('availList').innerHTML = '<p style="color:#f04747;text-align:center;padding:20px">加载失败: ' + escHtml(e.message) + '</p>';
    }
}

function renderAvailable(regions) {
    document.getElementById('availLoading').style.display = 'none';
    if (!regions || regions.length === 0) {
        document.getElementById('availList').innerHTML =
            '<p style="text-align:center;color:var(--mob-text-muted);padding:32px 0">所有区域均已订阅</p>';
        return;
    }
    document.getElementById('availList').innerHTML = regions.map(function(r) {
        var key  = escHtml(r.key || r.regionKey || '');
        var name = escHtml(r.name || r.regionName || key);
        var cn   = escHtml(r.cnName || '');
        return '<div class="mob-card" style="margin-bottom:8px;padding:12px 14px">'
            + '<div style="display:flex;align-items:center;gap:10px">'
            + '<input type="checkbox" id="chk-' + key + '" value="' + key + '"'
            + ' onchange="toggleSel(\'' + key + '\')" style="width:18px;height:18px;accent-color:#1abc9c;flex-shrink:0">'
            + '<div style="flex:1;min-width:0">'
            + '<div style="font-size:14px;font-weight:600;color:var(--mob-text)">' + name + (cn ? ' <span style="font-size:11px;color:var(--mob-text-muted)">(' + cn + ')</span>' : '') + '</div>'
            + '<div style="font-size:11px;color:var(--mob-text-muted);margin-top:1px">' + key + '</div>'
            + '</div>'
            + '<button class="mob-btn mob-btn-sm" style="flex-shrink:0;background:rgba(91,138,240,0.15);color:#5b8af0;border:none;padding:0 12px;height:30px"'
            + ' onclick="subscribeSingle(\'' + key + '\')"><i class="fas fa-plus"></i> 订阅</button>'
            + '</div>'
            + '</div>';
    }).join('');
}

function toggleSel(key) {
    var idx = _selectedKeys.indexOf(key);
    if (idx >= 0) _selectedKeys.splice(idx, 1);
    else _selectedKeys.push(key);
    updateBatchBar();
}

function clearSel() {
    _selectedKeys = [];
    document.querySelectorAll('#availList input[type=checkbox]').forEach(function(c) { c.checked = false; });
    updateBatchBar();
}

function updateBatchBar() {
    var bar = document.getElementById('batchBar');
    bar.style.display = _selectedKeys.length > 0 ? 'flex' : 'none';
    document.getElementById('selCount').textContent = _selectedKeys.length;
}

async function subscribeSingle(key) {
    await performSubscribe([key]);
}

async function batchSubscribe() {
    if (_selectedKeys.length === 0) return;
    await performSubscribe(_selectedKeys.slice());
}

async function performSubscribe(keys) {
    var csrf = (document.querySelector('meta[name="_csrf"]')||{}).content||'';
    document.getElementById('subProgressBody').innerHTML = '<div style="color:var(--mob-text-muted)">正在订阅 ' + keys.length + ' 个区域…</div>';
    document.getElementById('subProgressClose').disabled = true;
    document.getElementById('subProgressModal').style.display = 'flex';
    try {
        var res  = await fetch('/tenants/subscribe-regions', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
            body: JSON.stringify({ tenantId: _rsTenantId, regionKeys: keys })
        });
        var json = await res.json();
        var details = json.details || [];
        document.getElementById('subProgressBody').innerHTML = details.map(function(d) {
            var icon = d.success ? '<i class="fas fa-check-circle" style="color:#43b581"></i>' : '<i class="fas fa-times-circle" style="color:#f04747"></i>';
            return '<div style="margin-bottom:6px">' + icon + ' <strong>' + escHtml(d.regionKey) + '</strong>: ' + escHtml(d.message || '') + '</div>';
        }).join('') || '<div>' + escHtml(json.message || '操作完成') + '</div>';
        document.getElementById('subProgressClose').disabled = false;
    } catch(e) {
        document.getElementById('subProgressBody').innerHTML = '<div style="color:#f04747">订阅失败: ' + escHtml(e.message) + '</div>';
        document.getElementById('subProgressClose').disabled = false;
    }
}

function closeSubProgress() {
    document.getElementById('subProgressModal').style.display = 'none';
    loadSubscribed();
    document.getElementById('availList').innerHTML = '';
    if (document.getElementById('tabAvailable').style.display !== 'none') loadAvailable();
}

/* ══ 工具 ══ */
function escHtml(s) {
    if (!s) return '';
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function rsToast(msg, type) {
    var t = document.createElement('div');
    t.style.cssText = 'position:fixed;bottom:80px;left:50%;transform:translateX(-50%);background:'
        + (type==='error'?'#f04747':'#43b581')
        + ';color:#fff;padding:10px 20px;border-radius:20px;font-size:13px;z-index:9999;white-space:nowrap;box-shadow:0 4px 12px rgba(0,0,0,0.3)';
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(function() { t.remove(); }, 2800);
}

if (_rsTenantId) loadSubscribed();
</script>
</#noparse>

</@layout.page>
