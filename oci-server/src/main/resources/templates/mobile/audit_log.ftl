<#import "layout.ftl" as layout>
<@layout.page title="审计日志" activePage="tenants">

<!-- 顶部返回栏 -->
<div style="display:flex;align-items:center;gap:12px;margin-bottom:16px">
    <button onclick="window.location.href='/m/tenants?menuId='+encodeURIComponent(_alTenantId)" style="width:36px;height:36px;border-radius:50%;border:1.5px solid var(--mob-border);background:var(--mob-card);color:var(--mob-text);display:flex;align-items:center;justify-content:center;cursor:pointer;flex-shrink:0;padding:0">
        <i class="fas fa-chevron-left" style="font-size:13px"></i>
    </button>
    <div style="flex:1;min-width:0">
        <div style="font-size:16px;font-weight:700;color:var(--mob-text)">审计日志</div>
        <div style="font-size:11px;color:var(--mob-text-muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap" id="alTenantName">—</div>
    </div>
</div>

<!-- 查询条件 -->
<div class="mob-card" style="margin-bottom:12px;padding:14px">
    <!-- 快速选择 -->
    <div style="font-size:11px;color:var(--mob-text-muted);margin-bottom:6px">快速选择</div>
    <div style="display:flex;gap:6px;flex-wrap:wrap;margin-bottom:10px" id="alQuickBtns">
        <button class="mob-al-quick-btn active" onclick="alSelectQuick(this,1)">近1天</button>
        <button class="mob-al-quick-btn" onclick="alSelectQuick(this,3)">近3天</button>
        <button class="mob-al-quick-btn" onclick="alSelectQuick(this,7)">近7天</button>
        <button class="mob-al-quick-btn" onclick="alSelectQuick(this,30)">近30天</button>
        <button class="mob-al-quick-btn" id="alCustomBtn" onclick="alSelectCustom(this)">自定义</button>
    </div>
    <!-- 自定义日期范围 -->
    <div id="alCustomDate" style="display:none;margin-bottom:10px">
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">
            <div>
                <div style="font-size:11px;color:var(--mob-text-muted);margin-bottom:4px">开始日期</div>
                <input type="date" id="alStartDate" class="mob-tf-input">
            </div>
            <div>
                <div style="font-size:11px;color:var(--mob-text-muted);margin-bottom:4px">结束日期</div>
                <input type="date" id="alEndDate" class="mob-tf-input">
            </div>
        </div>
    </div>
    <button class="mob-btn mob-btn-primary" style="width:100%" onclick="loadAuditLog()">
        <i class="fas fa-search" style="margin-right:6px"></i>查询
    </button>
</div>

<!-- 加载状态 -->
<div class="mob-loading" id="alLoading" style="display:none"><div class="mob-spinner"></div></div>

<!-- 结果列表 -->
<div id="alList"></div>

<!-- 下一页 -->
<div id="alNextWrap" style="display:none;text-align:center;padding:12px">
    <button class="mob-btn mob-btn-outline" onclick="loadNextPage()" style="width:80%">加载更多</button>
</div>

<style>
.mob-al-quick-btn {
    padding: 5px 12px;
    border-radius: 20px;
    border: 1.5px solid var(--mob-border);
    background: var(--mob-card);
    color: var(--mob-text-muted);
    font-size: 12px;
    cursor: pointer;
    transition: all .15s;
    white-space: nowrap;
}
.mob-al-quick-btn.active {
    background: #5b8af0;
    border-color: #5b8af0;
    color: #fff;
    font-weight: 600;
}
.mob-al-row {
    background: var(--mob-card);
    border-radius: 10px;
    padding: 12px 14px;
    margin-bottom: 8px;
    border: 1px solid var(--mob-border);
}
</style>

<script>
var _alTenantId   = '${tenantId!}';
var _alTenantName = '${tenantName!}';
var _alDays       = 1;
var _alNextToken  = null;
var _alMode       = 'quick'; // 'quick' | 'custom'
</script>
<#noparse>
<script>
document.getElementById('alTenantName').textContent = _alTenantName || '—';

/* ── 快速选择 / 自定义切换 ── */
function alSelectQuick(btn, days) {
    _alDays = days;
    _alMode = 'quick';
    document.querySelectorAll('.mob-al-quick-btn').forEach(function(b) { b.classList.remove('active'); });
    btn.classList.add('active');
    document.getElementById('alCustomDate').style.display = 'none';
}

function alSelectCustom(btn) {
    _alMode = 'custom';
    document.querySelectorAll('.mob-al-quick-btn').forEach(function(b) { b.classList.remove('active'); });
    btn.classList.add('active');
    document.getElementById('alCustomDate').style.display = '';
    // 默认：近7天
    var now  = new Date();
    var end  = now.toISOString().split('T')[0];
    var start = new Date(now - 7*24*3600*1000).toISOString().split('T')[0];
    if (!document.getElementById('alStartDate').value) document.getElementById('alStartDate').value = start;
    if (!document.getElementById('alEndDate').value)   document.getElementById('alEndDate').value   = end;
}

async function loadAuditLog() {
    _alNextToken = null;
    document.getElementById('alList').innerHTML = '';
    document.getElementById('alNextWrap').style.display = 'none';
    await fetchAuditLog(false);
}

async function loadNextPage() {
    await fetchAuditLog(true);
}

async function fetchAuditLog(append) {
    document.getElementById('alLoading').style.display = '';
    var csrf = (document.querySelector('meta[name="_csrf"]')||{}).content||'';
    try {
        var body = { tenantId: _alTenantId };
        if (_alMode === 'custom') {
            var s = document.getElementById('alStartDate').value;
            var e = document.getElementById('alEndDate').value;
            if (!s || !e) { alToast('请选择开始和结束日期', 'error'); document.getElementById('alLoading').style.display = 'none'; return; }
            if (s > e)    { alToast('开始日期不能晚于结束日期', 'error'); document.getElementById('alLoading').style.display = 'none'; return; }
            body.startDate = s;
            body.endDate   = e;
        } else {
            body.days = _alDays;
        }
        if (_alNextToken) body.pageToken = _alNextToken;

        var res  = await fetch('/tenants/audit/log', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
            body: JSON.stringify(body)
        });
        var json = await res.json();
        document.getElementById('alLoading').style.display = 'none';

        if (!json.success && json.code !== 200) {
            document.getElementById('alList').innerHTML =
                '<p style="color:#f04747;text-align:center;padding:24px">' + escHtml(json.message || '查询失败') + '</p>';
            return;
        }

        var pageResult = json.data || {};
        var items = pageResult.data || [];
        _alNextToken = pageResult.nextPageToken || null;

        renderAuditLog(items, append);
        document.getElementById('alNextWrap').style.display = _alNextToken ? '' : 'none';
    } catch(e) {
        document.getElementById('alLoading').style.display = 'none';
        if (!append) {
            document.getElementById('alList').innerHTML =
                '<p style="color:#f04747;text-align:center;padding:24px">查询失败: ' + escHtml(e.message) + '</p>';
        } else {
            alToast('加载失败: ' + e.message, 'error');
        }
    }
}

function renderAuditLog(items, append) {
    if (!append && (!items || items.length === 0)) {
        document.getElementById('alList').innerHTML =
            '<div style="text-align:center;padding:40px 0">'
            + '<i class="fas fa-clipboard-list" style="font-size:48px;opacity:0.2;display:block;margin-bottom:12px"></i>'
            + '<p style="color:var(--mob-text-muted)">暂无审计日志</p></div>';
        return;
    }
    var html = (items || []).map(function(log) {
        var isOk     = (log.responseStatus || '').startsWith('2') || log.responseStatus === 'OK';
        var time     = log.eventTime ? String(log.eventTime).substring(0, 19).replace('T', ' ') : '—';
        var typeStr  = escHtml(log.eventType || '—');
        var user     = escHtml(log.userName || '—');
        var ip       = escHtml(log.ipAddress || '');
        var status   = escHtml(log.responseStatus || '');
        var stColor  = isOk ? '#43b581' : (log.responseStatus ? '#f04747' : 'var(--mob-text-muted)');
        return '<div class="mob-al-row">'
            + '<div style="display:flex;align-items:flex-start;justify-content:space-between;gap:8px">'
            + '<div style="flex:1;min-width:0">'
            + '<div style="font-size:13px;font-weight:700;color:var(--mob-text);overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + typeStr + '</div>'
            + '<div style="font-size:11px;color:var(--mob-text-muted);margin-top:3px">'
            + '<i class="fas fa-user" style="margin-right:3px"></i>' + user
            + (ip ? ' &nbsp;·&nbsp; <i class="fas fa-map-marker-alt" style="margin-right:3px"></i>' + ip : '')
            + '</div>'
            + '<div style="font-size:11px;color:var(--mob-text-muted);margin-top:2px"><i class="fas fa-clock" style="margin-right:3px"></i>' + time + '</div>'
            + '</div>'
            + (status ? '<span style="font-size:11px;font-weight:700;color:' + stColor + ';flex-shrink:0">' + status + '</span>' : '')
            + '</div>'
            + '</div>';
    }).join('');

    if (append) {
        document.getElementById('alList').insertAdjacentHTML('beforeend', html);
    } else {
        document.getElementById('alList').innerHTML = html;
    }
}

/* ══ 工具 ══ */
function escHtml(s) {
    if (!s) return '';
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function alToast(msg, type) {
    var t = document.createElement('div');
    t.style.cssText = 'position:fixed;bottom:80px;left:50%;transform:translateX(-50%);background:'
        + (type==='error'?'#f04747':'#43b581')
        + ';color:#fff;padding:10px 20px;border-radius:20px;font-size:13px;z-index:9999;white-space:nowrap;box-shadow:0 4px 12px rgba(0,0,0,0.3)';
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(function() { t.remove(); }, 2800);
}

if (_alTenantId) loadAuditLog();
</script>
</#noparse>

</@layout.page>
