<#import "layout.ftl" as layout>
<@layout.page title="安全规则" activePage="tenants">

<style>
/* Tab */
.sr-tab-bar { display:flex;gap:2px;background:rgba(118,118,128,0.12);border-radius:11px;padding:2px;margin-bottom:14px }
.sr-tab-btn { flex:1;padding:8px 4px;border-radius:9px;border:none;font-size:13px;font-weight:600;cursor:pointer;transition:all .22s;background:transparent;color:rgba(60,60,67,0.6) }
html[data-theme="dark"] .sr-tab-btn { color:rgba(235,235,245,0.55) }
.sr-tab-btn.active { background:#fff;color:#5b8af0;box-shadow:0 1px 4px rgba(0,0,0,0.13) }
html[data-theme="dark"] .sr-tab-btn.active { background:rgba(255,255,255,0.14);color:#5b8af0;box-shadow:0 1px 4px rgba(0,0,0,0.3) }

/* 规则卡片 */
.sr-card {
    background:var(--mob-card);border:1px solid var(--mob-border);border-radius:12px;
    margin-bottom:10px;overflow:hidden;
}
.sr-card-head { display:flex;align-items:center;gap:10px;padding:12px 14px 10px }
.sr-proto-badge {
    padding:3px 10px;border-radius:20px;font-size:11px;font-weight:700;
    background:rgba(91,138,240,0.15);color:#5b8af0;white-space:nowrap;flex-shrink:0;
}
.sr-card-info { flex:1;min-width:0 }
.sr-card-main { font-size:13px;font-weight:600;color:var(--mob-text);overflow:hidden;text-overflow:ellipsis;white-space:nowrap }
.sr-card-sub  { font-size:11px;color:var(--mob-text-muted);margin-top:2px }
.sr-card-del {
    width:32px;height:32px;border-radius:8px;border:1.5px solid rgba(240,71,71,0.35);
    background:rgba(240,71,71,0.08);color:#f04747;display:flex;align-items:center;
    justify-content:center;cursor:pointer;flex-shrink:0;font-size:13px;
}

/* 添加规则区 */
.sr-add-panel {
    background:var(--mob-card);border:1px solid var(--mob-border);border-radius:12px;
    padding:14px;margin-bottom:14px;
}
.sr-add-title { font-size:13px;font-weight:700;color:var(--mob-text);margin-bottom:12px;display:flex;align-items:center;gap:6px }
.sr-field { margin-bottom:10px }
.sr-field-label { font-size:11px;color:var(--mob-text-muted);margin-bottom:4px;font-weight:600 }
.sr-input {
    width:100%;box-sizing:border-box;background:var(--mob-bg);border:1px solid var(--mob-border);
    border-radius:8px;padding:9px 12px;font-size:13px;color:var(--mob-text);outline:none;
    -webkit-appearance:none;
}
.sr-input:focus { border-color:#5b8af0 }
.sr-select {
    width:100%;box-sizing:border-box;background:var(--mob-bg);border:1px solid var(--mob-border);
    border-radius:8px;padding:9px 12px;font-size:13px;color:var(--mob-text);outline:none;
    appearance:none;-webkit-appearance:none;
    background-image:url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='12' viewBox='0 0 12 12'%3E%3Cpath fill='%2372767d' d='M6 8L1 3h10z'/%3E%3C/svg%3E");
    background-repeat:no-repeat;background-position:right 12px center;padding-right:30px;
}
.sr-select:focus { border-color:#5b8af0 }
.sr-add-row { display:flex;gap:8px }
.sr-add-row .sr-field { flex:1;margin-bottom:0 }

/* 删除确认弹窗 */
</style>

<!-- 返回栏 -->
<div style="display:flex;align-items:center;gap:12px;margin-bottom:16px">
    <button onclick="history.back()" style="width:36px;height:36px;border-radius:50%;border:1.5px solid var(--mob-border);background:var(--mob-card);color:var(--mob-text);display:flex;align-items:center;justify-content:center;cursor:pointer;flex-shrink:0;padding:0">
        <i class="fas fa-chevron-left" style="font-size:13px"></i>
    </button>
    <div style="flex:1;min-width:0">
        <div style="font-size:16px;font-weight:700;color:var(--mob-text)">安全规则</div>
        <div style="font-size:11px;color:var(--mob-text-muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap" id="srTenantName">—</div>
    </div>
</div>

<!-- Tab 切换 -->
<div class="sr-tab-bar">
    <button id="tabIngress" class="sr-tab-btn active" onclick="switchTab('ingress')">
        <i class="fas fa-arrow-down" style="margin-right:4px"></i>入站规则
    </button>
    <button id="tabEgress" class="sr-tab-btn" onclick="switchTab('egress')">
        <i class="fas fa-arrow-up" style="margin-right:4px"></i>出站规则
    </button>
</div>

<!-- 添加规则面板 -->
<div class="sr-add-panel">
    <div class="sr-add-title"><i class="fas fa-plus-circle" style="color:#5b8af0"></i>添加规则</div>
    <div class="sr-add-row">
        <div class="sr-field">
            <div class="sr-field-label">协议</div>
            <select class="sr-select" id="srProto">
                <option value="all">ALL</option>
                <option value="tcp">TCP</option>
                <option value="udp">UDP</option>
                <option value="icmp">ICMP</option>
            </select>
        </div>
        <div class="sr-field">
            <div class="sr-field-label">端口范围</div>
            <input class="sr-input" id="srPorts" type="text" placeholder="如 80 或 8080-9090">
        </div>
    </div>
    <div class="sr-field" style="margin-top:10px">
        <div class="sr-field-label" id="srCidrLabel">来源 CIDR</div>
        <input class="sr-input" id="srCidr" type="text" placeholder="如 0.0.0.0/0">
    </div>
    <button class="mob-btn" style="width:100%;margin-top:10px;background:#5b8af0;color:#fff;border:none;font-weight:700" onclick="addRule()">
        <i class="fas fa-plus"></i> 添加规则
    </button>
</div>

<!-- 加载中 -->
<div class="mob-loading" id="srLoading"><div class="mob-spinner"></div><p>加载中...</p></div>
<!-- 规则列表 -->
<div id="srList" style="display:none"></div>

<!-- ══ 删除确认弹窗 ══ -->
<div id="srDelModal" class="mob-center-overlay" style="display:none" onclick="closeSrDel(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-width:340px">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title" style="color:#f04747"><i class="fas fa-exclamation-triangle" style="margin-right:6px"></i>确认删除</div>
            <button class="mob-sheet-close" onclick="closeSrDel()"><i class="fas fa-times"></i></button>
        </div>
        <div style="padding:16px 16px 8px">
            <p style="color:var(--mob-text);font-size:14px;line-height:1.6">
                确认删除该安全规则吗？<br>
                <span style="color:var(--mob-text-muted);font-size:12px">此操作将立即生效且不可恢复。</span>
            </p>
        </div>
        <div style="padding:8px 16px 20px;display:flex;gap:10px">
            <button class="mob-btn mob-btn-outline" style="flex:1" onclick="closeSrDel()">取消</button>
            <button class="mob-btn" id="srDelConfirmBtn" style="flex:1;background:#f04747;color:#fff;border:none" onclick="confirmSrDel()">确认删除</button>
        </div>
    </div>
</div>

<script>
var _srTenantId   = '${tenantId}';
var _srTenantName = '${tenantName}';
var _srTab        = 'ingress';
var _srDelId      = null;
</script>
<#noparse>
<script>
document.getElementById('srTenantName').textContent = _srTenantName || _srTenantId || '—';

function switchTab(tab) {
    _srTab = tab;
    document.getElementById('tabIngress').classList.toggle('active', tab === 'ingress');
    document.getElementById('tabEgress').classList.toggle('active',  tab === 'egress');
    document.getElementById('srCidrLabel').textContent = tab === 'ingress' ? '来源 CIDR' : '目标 CIDR';
    loadRules();
}

/* ══ 加载规则 ══ */
async function loadRules() {
    document.getElementById('srLoading').style.display = '';
    document.getElementById('srList').style.display = 'none';
    try {
        var res  = await fetch('/tenants/security-rules?tenantId=' + encodeURIComponent(_srTenantId) + '&type=' + _srTab);
        var json = await res.json();
        renderRules(json.data || json || []);
    } catch(e) {
        document.getElementById('srLoading').innerHTML = '<p style="color:#f04747;text-align:center">加载失败：' + e.message + '</p>';
    }
}

var _protoColors = { tcp:'#1abc9c', udp:'#faa61a', icmp:'#9b59b6', all:'#5b8af0' };

function renderRules(rules) {
    var loading = document.getElementById('srLoading');
    var list    = document.getElementById('srList');
    loading.style.display = 'none';
    list.style.display    = 'block';

    if (!rules || rules.length === 0) {
        list.innerHTML = '<div class="mob-empty"><i class="fas fa-shield-alt"></i><p>暂无规则</p></div>';
        return;
    }

    list.innerHTML = rules.map(function(r) {
        var proto = (r.protocol || 'all').toLowerCase();
        var color = _protoColors[proto] || '#5b8af0';
        var cidr  = escH(_srTab === 'ingress' ? (r.source || r.cidr || '—') : (r.destination || r.cidr || '—'));
        var ports = escH(r.ports || r.portRange || 'ALL');
        return '<div class="sr-card">'
            + '<div class="sr-card-head">'
            +   '<span class="sr-proto-badge" style="background:rgba(' + hexToRgb(color) + ',.15);color:' + color + '">' + proto.toUpperCase() + '</span>'
            +   '<div class="sr-card-info">'
            +     '<div class="sr-card-main">' + cidr + '</div>'
            +     '<div class="sr-card-sub">端口：' + ports + '</div>'
            +   '</div>'
            +   '<button class="sr-card-del" onclick="openSrDel(\'' + escH(r.id || '') + '\')">'
            +     '<i class="fas fa-trash-alt"></i>'
            +   '</button>'
            + '</div>'
            + '</div>';
    }).join('');
}

function hexToRgb(hex) {
    var m = hex.match(/^#([\da-f]{2})([\da-f]{2})([\da-f]{2})$/i);
    if (!m) return '91,138,240';
    return parseInt(m[1],16) + ',' + parseInt(m[2],16) + ',' + parseInt(m[3],16);
}

/* ══ 添加规则 ══ */
async function addRule() {
    var proto = document.getElementById('srProto').value;
    var ports = document.getElementById('srPorts').value.trim();
    var cidr  = document.getElementById('srCidr').value.trim();
    if (!cidr) { mobToast('请填写 CIDR', 'error'); return; }

    var body = {
        tenantId:    _srTenantId,
        type:        _srTab,
        protocol:    proto,
        ports:       ports || 'ALL',
    };
    if (_srTab === 'ingress') body.source      = cidr;
    else                     body.destination = cidr;

    var csrf = getCsrf();
    try {
        var res  = await fetch('/tenants/security-rules', {
            method: 'POST',
            headers: Object.assign({ 'Content-Type': 'application/json' }, csrf),
            body: JSON.stringify(body)
        });
        var json = await res.json();
        if (json.success || json.code === 200 || json.id) {
            mobToast('添加成功', 'success');
            document.getElementById('srCidr').value  = '';
            document.getElementById('srPorts').value = '';
            loadRules();
        } else {
            mobToast(json.message || '添加失败', 'error');
        }
    } catch(e) {
        mobToast('请求异常：' + e.message, 'error');
    }
}

/* ══ 删除 ══ */
function openSrDel(id) {
    _srDelId = id;
    document.getElementById('srDelModal').style.display = 'flex';
}

function closeSrDel(e) {
    if (e && e.target !== document.getElementById('srDelModal')) return;
    document.getElementById('srDelModal').style.display = 'none';
}

async function confirmSrDel() {
    if (!_srDelId) return;
    var btn = document.getElementById('srDelConfirmBtn');
    btn.disabled = true; btn.textContent = '删除中…';
    var csrf = getCsrf();
    try {
        var res  = await fetch('/tenants/security-rules/' + encodeURIComponent(_srDelId), {
            method: 'DELETE',
            headers: csrf
        });
        if (res.ok) {
            mobToast('删除成功', 'success');
            document.getElementById('srDelModal').style.display = 'none';
            loadRules();
        } else {
            var json = await res.json().catch(function() { return {}; });
            mobToast(json.message || '删除失败', 'error');
        }
    } catch(e) {
        mobToast('请求异常：' + e.message, 'error');
    }
    btn.disabled = false; btn.textContent = '确认删除';
}

function getCsrf() {
    var t = (document.querySelector('meta[name="_csrf"]') || {}).content || '';
    var h = (document.querySelector('meta[name="_csrf_header"]') || {}).content || 'X-CSRF-TOKEN';
    return { [h]: t };
}

function escH(s) {
    if (!s) return '';
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
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

loadRules();
</script>
</#noparse>

</@layout.page>
