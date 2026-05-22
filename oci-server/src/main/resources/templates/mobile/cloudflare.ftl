<#import "layout.ftl" as layout>
<@layout.page title="域名" activePage="cloudflare">

<!-- ══════════════ Cloudflare 配置（折叠卡片） ══════════════ -->
<div class="mob-settings-section">
    <div class="mob-settings-section-header" onclick="mobSettingsToggle('cfConfig')">
        <div class="mob-settings-section-title">
            <i class="fas fa-cloud" style="color:#f38020"></i>
            域名配置
        </div>
        <div style="display:flex;align-items:center;gap:10px">
            <label class="mob-sf-toggle" onclick="event.stopPropagation()">
                <input type="checkbox" id="cfEnabled" <#if (cloudflareConfig.enabled)!false>checked</#if>>
                <span class="mob-sf-toggle-slider"></span>
            </label>
            <i class="fas fa-chevron-down mob-settings-arrow" id="arrowCfConfig"></i>
        </div>
    </div>
    <div class="mob-settings-body" id="cfConfig" style="display:none">
        <div class="mob-sf-row">
            <label class="mob-sf-label">API Token</label>
            <div style="position:relative">
                <input class="mob-sf-input" type="password" id="cfApiToken"
                       value="${(cloudflareConfig.apiToken)!''}"
                       placeholder="Cloudflare Global API Key 或 Token"
                       style="padding-right:40px">
                <button onclick="cfTogglePwd()" style="position:absolute;right:8px;top:50%;transform:translateY(-50%);background:none;border:none;color:var(--mob-text-muted);cursor:pointer;padding:4px">
                    <i class="fas fa-eye" id="cfApiTokenEye"></i>
                </button>
            </div>
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">Email</label>
            <input class="mob-sf-input" type="email" id="cfEmail"
                   value="${(cloudflareConfig.email)!''}"
                   placeholder="Cloudflare 账户邮箱">
        </div>
        <div style="display:flex;gap:8px;margin-top:12px">
            <button class="mob-btn mob-btn-primary" style="flex:1;justify-content:center" onclick="cfSaveConfig()">
                <i class="fas fa-save"></i> 保存
            </button>
            <button class="mob-btn mob-btn-outline" style="flex:1;justify-content:center" onclick="cfTestConn()">
                <i class="fas fa-plug"></i> 测试连接
            </button>
        </div>
    </div>
</div>

<!-- ══════════════ 域名选择器 ══════════════ -->
<div style="margin-bottom:12px">
    <div style="font-size:13px;font-weight:600;color:var(--mob-text);margin-bottom:8px">
        <i class="fas fa-globe" style="color:#f38020;margin-right:6px"></i>
        DNS 管理
    </div>
    <div class="mob-cf-zone-btn" onclick="cfOpenZonePicker()">
        <span class="mob-cf-zone-btn-icon"><i class="fas fa-globe"></i></span>
        <div style="flex:1;min-width:0">
            <div id="cfZoneBtnName" style="font-size:14px;font-weight:500;color:var(--mob-text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis">
                点击选择域名
            </div>
            <div id="cfZoneBtnSub" style="font-size:11px;color:var(--mob-text-muted);margin-top:1px">
                正在加载域名列表...
            </div>
        </div>
        <i class="fas fa-chevron-down" style="color:var(--mob-text-muted);font-size:13px;flex-shrink:0"></i>
    </div>
</div>

<!-- ══════════════ DNS 记录 ══════════════ -->
<div id="cfDnsSection" style="display:none">
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px">
        <div style="font-size:13px;font-weight:600;color:var(--mob-text)">
            <i class="fas fa-list" style="color:#7289da;margin-right:6px"></i>
            DNS 记录
            <span id="cfDnsInfo" style="font-size:11px;color:var(--mob-text-muted);font-weight:400;margin-left:4px"></span>
        </div>
        <button class="mob-btn mob-btn-primary" style="padding:4px 10px;font-size:12px" onclick="cfOpenAddRecord()">
            <i class="fas fa-plus"></i> 添加
        </button>
    </div>
    <div class="mob-search-wrap" style="margin-bottom:8px">
        <i class="fas fa-search mob-search-icon"></i>
        <input class="mob-search-input" id="cfDnsSearch" type="text"
               placeholder="搜索名称、内容、类型..."
               oninput="cfDnsSearchDelay(this.value)">
    </div>
    <div id="cfDnsLoading" style="display:none;text-align:center;padding:20px 0;color:var(--mob-text-muted)">
        <div class="mob-spinner" style="margin:0 auto 8px"></div><p>加载中...</p>
    </div>
    <div id="cfDnsList"></div>
    <div id="cfDnsPager" style="display:none;align-items:center;justify-content:center;gap:6px;padding:8px 0 4px;flex-wrap:wrap"></div>
</div>

<!-- ══════════════ 域名选择弹窗 ══════════════ -->
<div id="cfZoneSheet" class="mob-center-overlay" onclick="cfCloseZoneSheet(event)" style="display:none">
    <div class="mob-center-dialog" onclick="event.stopPropagation()">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title">选择域名</div>
            <button class="mob-sheet-close" onclick="cfCloseZoneSheet()"><i class="fas fa-times"></i></button>
        </div>
        <div style="padding:8px 16px;flex-shrink:0">
            <div class="mob-search-wrap">
                <i class="fas fa-search mob-search-icon"></i>
                <input class="mob-search-input" id="cfZoneSearch" type="text"
                       placeholder="搜索域名..." oninput="cfFilterZones(this.value)" autocomplete="off">
            </div>
            <div id="cfZoneSheetCount" style="font-size:11px;color:var(--mob-text-muted);margin-top:5px;text-align:center"></div>
        </div>
        <!-- 固定高度可滚动列表，域名再多也不撑满屏幕 -->
        <div id="cfZoneSheetList" style="height:340px;overflow-y:auto;padding:0"></div>
    </div>
</div>

<!-- ══════════════ DNS 记录编辑弹窗 ══════════════ -->
<div id="cfRecordSheet" class="mob-sheet-overlay" onclick="cfCloseRecordSheet(event)" style="display:none">
    <div class="mob-sheet" onclick="event.stopPropagation()">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title" id="cfRecordSheetTitle">添加 DNS 记录</div>
            <button class="mob-sheet-close" onclick="cfCloseRecordSheet()"><i class="fas fa-times"></i></button>
        </div>
        <div class="mob-sheet-body">
            <input type="hidden" id="cfRecordId">
            <div class="mob-sf-row">
                <label class="mob-sf-label">记录类型</label>
                <select class="mob-sf-input" id="cfRecordType">
                    <option>A</option><option>AAAA</option><option>CNAME</option>
                    <option>TXT</option><option>MX</option><option>NS</option>
                    <option>SRV</option><option>CAA</option>
                </select>
            </div>
            <div class="mob-sf-row">
                <label class="mob-sf-label">名称</label>
                <input class="mob-sf-input" type="text" id="cfRecordName" placeholder="@ 或子域名">
            </div>
            <div class="mob-sf-row">
                <label class="mob-sf-label">内容</label>
                <input class="mob-sf-input" type="text" id="cfRecordContent" placeholder="IP 地址或目标">
            </div>
            <div class="mob-sf-row">
                <label class="mob-sf-label">TTL</label>
                <select class="mob-sf-input" id="cfRecordTtl">
                    <option value="1">自动</option>
                    <option value="300">5 分钟</option>
                    <option value="600">10 分钟</option>
                    <option value="1800">30 分钟</option>
                    <option value="3600">1 小时</option>
                    <option value="86400">1 天</option>
                </select>
            </div>
            <div class="mob-sf-row" style="align-items:center">
                <label class="mob-sf-label">Proxied（橙云）</label>
                <label class="mob-sf-toggle" style="margin-left:auto">
                    <input type="checkbox" id="cfRecordProxied">
                    <span class="mob-sf-toggle-slider"></span>
                </label>
            </div>
        </div>
        <div class="mob-sheet-footer" style="display:flex;gap:8px">
            <button class="mob-btn mob-btn-outline" style="flex:1;justify-content:center" onclick="cfCloseRecordSheet()">取消</button>
            <button class="mob-btn mob-btn-primary" style="flex:1;justify-content:center" id="cfRecordSubmitBtn" onclick="cfSubmitRecord()">
                <i class="fas fa-save"></i> 保存
            </button>
        </div>
    </div>
</div>

<#noparse>
<script>
/* ── 状态 ────────────────────────────────── */
var _cfAllZones      = [];
var _cfFilteredZones = [];
var _cfSelZoneId     = null;
var _cfSelZoneName   = '';
var _cfDnsPage       = 1;
var _cfDnsSize       = 20;
var _cfDnsTotal      = 0;
var _cfDnsTotalPages = 0;
var _cfDnsSearchKw   = '';
var _cfDnsTimer      = null;
var _cfZonesLoaded   = false;
/* 用 ID 索引 DNS 记录，避免在 onclick 里嵌入 JSON */
var _cfDnsMap        = {};

/* ── 折叠区域 ────────────────────────────── */
function mobSettingsToggle(id) {
    var body  = document.getElementById(id);
    var arrow = document.getElementById('arrow' + id.charAt(0).toUpperCase() + id.slice(1));
    var open  = body.style.display !== 'none';
    body.style.display = open ? 'none' : 'block';
    if (arrow) arrow.style.transform = open ? '' : 'rotate(180deg)';
}

/* ── API Token 显/隐 ─────────────────────── */
function cfTogglePwd() {
    var inp = document.getElementById('cfApiToken');
    var eye = document.getElementById('cfApiTokenEye');
    var p   = inp.type === 'password';
    inp.type = p ? 'text' : 'password';
    eye.className = p ? 'fas fa-eye-slash' : 'fas fa-eye';
}

/* ── 配置保存 / 测试 ─────────────────────── */
function cfSaveConfig() {
    var csrf = document.querySelector('meta[name="_csrf"]');
    fetch('/api/system/updateCloudflareConfig', {
        method: 'POST',
        headers: {'Content-Type':'application/json','X-CSRF-TOKEN': csrf ? csrf.content : ''},
        body: JSON.stringify({
            apiToken: document.getElementById('cfApiToken').value.trim(),
            email:    document.getElementById('cfEmail').value.trim(),
            enabled:  document.getElementById('cfEnabled').checked
        })
    }).then(function(r) {
        if (r.ok) mobToast('保存成功','success');
        else r.text().then(function(t){ mobToast('保存失败: '+t,'error'); });
    }).catch(function(){ mobToast('网络错误','error'); });
}

function cfTestConn() {
    var csrf = document.querySelector('meta[name="_csrf"]');
    mobToast('测试中...','info');
    fetch('/api/system/testCloudflareConnection', {
        method: 'POST',
        headers: {'Content-Type':'application/json','X-CSRF-TOKEN': csrf ? csrf.content : ''},
        body: JSON.stringify({
            apiToken: document.getElementById('cfApiToken').value.trim(),
            email:    document.getElementById('cfEmail').value.trim(),
            enabled:  true
        })
    }).then(function(r) {
        if (!r.ok) return r.text().then(function(t){ mobToast('失败: '+t,'error'); });
        return r.json().then(function(j) {
            var ok = j && (j.success===true || j.connected===true || j.status==='success');
            mobToast(ok ? '连接成功！' : '连接失败：'+(j.message||'请检查配置'), ok?'success':'error');
        });
    }).catch(function(){ mobToast('网络错误','error'); });
}

/* ── 加载域名列表 ────────────────────────── */
async function cfLoadZones() {
    _cfZonesLoaded = false;
    document.getElementById('cfZoneBtnSub').textContent = '正在加载域名列表...';
    try {
        var res  = await fetch('/dns/cloudflare/api/zones');
        var json = await res.json();
        if (!json.success) throw new Error(json.message||'加载失败');
        _cfAllZones      = json.data || [];
        _cfFilteredZones = _cfAllZones.slice();
        _cfZonesLoaded   = true;
        document.getElementById('cfZoneBtnSub').innerHTML = '共 <b>'+_cfAllZones.length+'</b> 个域名，点击选择';
    } catch(e) {
        document.getElementById('cfZoneBtnSub').textContent = '加载失败: '+e.message;
    }
}

/* ── 域名弹窗 ────────────────────────────── */
function cfOpenZonePicker() {
    _cfFilteredZones = _cfAllZones.slice();
    document.getElementById('cfZoneSearch').value = '';
    document.getElementById('cfZoneSheet').style.display = 'flex';
    cfRenderZoneSheet();
    setTimeout(function(){ document.getElementById('cfZoneSearch').focus(); }, 200);
}

function cfCloseZoneSheet(e) {
    if (!e || e.target === document.getElementById('cfZoneSheet'))
        document.getElementById('cfZoneSheet').style.display = 'none';
}

function cfFilterZones(kw) {
    var q = kw.trim().toLowerCase();
    _cfFilteredZones = q
        ? _cfAllZones.filter(function(z){ return (z.name||'').toLowerCase().includes(q); })
        : _cfAllZones.slice();
    cfRenderZoneSheet();
}

function cfRenderZoneSheet() {
    var el    = document.getElementById('cfZoneSheetList');
    var count = document.getElementById('cfZoneSheetCount');
    var list  = _cfFilteredZones;

    if (!_cfZonesLoaded) {
        el.innerHTML = '<div style="text-align:center;padding:30px 0;color:var(--mob-text-muted)"><div class="mob-spinner" style="margin:0 auto 10px"></div><p>加载中...</p></div>';
        count.textContent = '';
        return;
    }
    count.textContent = list.length + ' 个域名' + (list.length < _cfAllZones.length ? '（已过滤）' : '');
    if (!list.length) {
        el.innerHTML = '<div class="mob-empty"><i class="fas fa-search"></i><p>未找到匹配域名</p></div>';
        return;
    }
    el.innerHTML = list.map(function(z) {
        var active  = z.status === 'active';
        var sel     = z.id === _cfSelZoneId;
        var initial = (z.name || '?').charAt(0).toUpperCase();
        return '<div class="mob-cf-zone-row'+(sel?' mob-cf-zone-row-sel':'')+'" onclick="cfSelectZone(\''+z.id+'\',\''+escCf(z.name)+'\')">'
            + '<div class="mob-cf-zone-avatar">'+initial+'</div>'
            + '<div style="flex:1;min-width:0">'
            +   '<div class="mob-cf-zone-name">'+escCf(z.name||z.id)+'</div>'
            +   '<div class="mob-cf-zone-meta">'
            +     '<span class="mob-badge '+(active?'mob-badge-green':'mob-badge-gray')+'">'+escCf(z.status||'unknown')+'</span>'
            +     ((z.plan&&z.plan.name) ? '<span class="mob-cf-zone-plan">'+escCf(z.plan.name)+'</span>' : '')
            +   '</div>'
            + '</div>'
            + (sel ? '<i class="fas fa-check-circle" style="color:#1abc9c;font-size:18px;flex-shrink:0"></i>'
                   : '<i class="fas fa-chevron-right" style="color:var(--mob-text-muted);font-size:12px;flex-shrink:0"></i>')
            + '</div>';
    }).join('');
}

function cfSelectZone(zoneId, zoneName) {
    _cfSelZoneId   = zoneId;
    _cfSelZoneName = zoneName;
    document.getElementById('cfZoneBtnName').textContent = zoneName;
    document.getElementById('cfZoneBtnSub').textContent  = '点击切换域名';
    document.getElementById('cfZoneSheet').style.display = 'none';
    document.getElementById('cfDnsSection').style.display = 'block';
    _cfDnsPage = 1; _cfDnsSearchKw = '';
    document.getElementById('cfDnsSearch').value = '';
    cfLoadDns();
}

/* ── DNS 记录加载 ────────────────────────── */
async function cfLoadDns() {
    document.getElementById('cfDnsLoading').style.display = 'block';
    document.getElementById('cfDnsList').innerHTML = '';
    document.getElementById('cfDnsPager').style.display = 'none';
    var url = '/dns/cloudflare/api/zones/' + encodeURIComponent(_cfSelZoneId)
            + '/records?page=' + _cfDnsPage + '&size=' + _cfDnsSize;
    try {
        var res  = await fetch(url);
        var json = await res.json();
        if (!json.success) throw new Error(json.message||'加载失败');
        var data = json.data || {};
        var recs = data.content || [];
        _cfDnsTotal      = data.totalElements || recs.length;
        _cfDnsTotalPages = data.totalPages    || 1;
        // 存入 map
        _cfDnsMap = {};
        recs.forEach(function(r){ if(r.id) _cfDnsMap[r.id] = r; });
        // 前端关键词过滤（当前页内）
        if (_cfDnsSearchKw) {
            var q = _cfDnsSearchKw.toLowerCase();
            recs = recs.filter(function(r) {
                return (r.name||'').toLowerCase().includes(q)
                    || (r.content||'').toLowerCase().includes(q)
                    || (r.type||'').toLowerCase().includes(q);
            });
        }
        document.getElementById('cfDnsLoading').style.display = 'none';
        cfRenderDns(recs);
        cfRenderDnsPager();
    } catch(e) {
        document.getElementById('cfDnsLoading').style.display = 'none';
        document.getElementById('cfDnsList').innerHTML =
            '<div class="mob-empty"><i class="fas fa-exclamation-circle" style="color:#f04747"></i>'
            + '<p style="color:#f04747">'+escCf(e.message)+'</p></div>';
    }
}

function cfDnsSearchDelay(kw) {
    clearTimeout(_cfDnsTimer);
    _cfDnsSearchKw = kw.trim();
    _cfDnsPage = 1;
    _cfDnsTimer = setTimeout(cfLoadDns, 400);
}

var _TC = {A:'#43b581',AAAA:'#1abc9c',CNAME:'#7289da',TXT:'#faa61a',MX:'#f38020',NS:'#99aab5'};

function cfRenderDns(recs) {
    var el = document.getElementById('cfDnsList');
    if (!recs || !recs.length) {
        el.innerHTML = '<div class="mob-empty"><i class="fas fa-list"></i><p>暂无 DNS 记录</p></div>';
        return;
    }
    document.getElementById('cfDnsInfo').textContent = '— ' + _cfSelZoneName + '（共 '+_cfDnsTotal+' 条）';
    el.innerHTML = recs.map(function(r) {
        var tc = _TC[r.type] || '#99aab5';
        return '<div class="mob-cf-dns-card">'
            + '<div style="display:flex;align-items:center;gap:8px">'
            +   '<span class="mob-cf-dns-type" style="background:'+tc+'22;color:'+tc+';border-color:'+tc+'44">'+escCf(r.type||'')+'</span>'
            +   '<div style="flex:1;min-width:0">'
            +     '<div style="font-size:13px;font-weight:500;color:var(--mob-text);white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'
            +       escCf(r.name||'')+(r.proxied?'&nbsp;<span class="mob-cf-proxied">橙云</span>':'')
            +     '</div>'
            +     '<div style="font-size:11px;color:var(--mob-text-muted);white-space:nowrap;overflow:hidden;text-overflow:ellipsis">'
            +       escCf(r.content||'')+'&nbsp;·&nbsp;TTL:'+(r.ttl===1?'自动':(r.ttl||''))
            +     '</div>'
            +   '</div>'
            +   '<div style="display:flex;gap:4px;flex-shrink:0">'
            +     '<button class="mob-cf-act-btn mob-cf-act-edit" onclick="cfOpenEditRecord(\''+escCf(r.id||'')+'\')"><i class="fas fa-pencil"></i></button>'
            +     '<button class="mob-cf-act-btn mob-cf-act-del"  onclick="cfDeleteRecord(\''+escCf(r.id||'')+'\')"><i class="fas fa-trash"></i></button>'
            +   '</div>'
            + '</div>'
            + '</div>';
    }).join('');
}

function cfRenderDnsPager() {
    var pager = document.getElementById('cfDnsPager');
    if (_cfDnsTotalPages <= 1) { pager.style.display = 'none'; return; }
    pager.style.display = 'flex';
    var s = Math.max(1, _cfDnsPage-2), e = Math.min(_cfDnsTotalPages, s+4);
    if (e-s<4) s = Math.max(1,e-4);
    var b = '<button class="mob-pager-btn" '+(_cfDnsPage<=1?'disabled':'')+' onclick="cfDnsGo('+(_cfDnsPage-1)+')"><i class="fas fa-chevron-left"></i></button>';
    if (s>1) b += '<button class="mob-pager-btn" onclick="cfDnsGo(1)">1</button><span style="color:var(--mob-text-muted);line-height:30px">…</span>';
    for (var i=s;i<=e;i++) b += '<button class="mob-pager-btn'+(i===_cfDnsPage?' active':'')+'" onclick="cfDnsGo('+i+')">'+i+'</button>';
    if (e<_cfDnsTotalPages) b += '<span style="color:var(--mob-text-muted);line-height:30px">…</span><button class="mob-pager-btn" onclick="cfDnsGo('+_cfDnsTotalPages+')">'+_cfDnsTotalPages+'</button>';
    b += '<button class="mob-pager-btn" '+(_cfDnsPage>=_cfDnsTotalPages?'disabled':'')+' onclick="cfDnsGo('+(_cfDnsPage+1)+')"><i class="fas fa-chevron-right"></i></button>';
    pager.innerHTML = b;
}

function cfDnsGo(p) {
    if (p<1||p>_cfDnsTotalPages) return;
    _cfDnsPage = p; cfLoadDns();
}

/* ── DNS CRUD ────────────────────────────── */
function cfOpenAddRecord() {
    document.getElementById('cfRecordSheetTitle').textContent = '添加 DNS 记录';
    document.getElementById('cfRecordId').value      = '';
    document.getElementById('cfRecordType').value    = 'A';
    document.getElementById('cfRecordName').value    = '';
    document.getElementById('cfRecordContent').value = '';
    document.getElementById('cfRecordTtl').value     = '1';
    document.getElementById('cfRecordProxied').checked = false;
    document.getElementById('cfRecordSubmitBtn').innerHTML = '<i class="fas fa-plus"></i> 添加';
    document.getElementById('cfRecordSheet').style.display = 'flex';
}

function cfOpenEditRecord(recordId) {
    var r = _cfDnsMap[recordId];
    if (!r) { mobToast('记录不存在','error'); return; }
    document.getElementById('cfRecordSheetTitle').textContent = '编辑 DNS 记录';
    document.getElementById('cfRecordId').value      = r.id || '';
    document.getElementById('cfRecordType').value    = r.type || 'A';
    document.getElementById('cfRecordName').value    = r.name || '';
    document.getElementById('cfRecordContent').value = r.content || '';
    var ttlSel = document.getElementById('cfRecordTtl');
    ttlSel.value = String(r.ttl || 1);
    if (!ttlSel.value) ttlSel.value = '1';
    document.getElementById('cfRecordProxied').checked = !!r.proxied;
    document.getElementById('cfRecordSubmitBtn').innerHTML = '<i class="fas fa-save"></i> 保存';
    document.getElementById('cfRecordSheet').style.display = 'flex';
}

function cfCloseRecordSheet(e) {
    if (!e || e.target === document.getElementById('cfRecordSheet'))
        document.getElementById('cfRecordSheet').style.display = 'none';
}

async function cfSubmitRecord() {
    var csrf = document.querySelector('meta[name="_csrf"]');
    var rid  = document.getElementById('cfRecordId').value.trim();
    var name = document.getElementById('cfRecordName').value.trim();
    var cont = document.getElementById('cfRecordContent').value.trim();
    if (!name) { mobToast('请输入记录名称','error'); return; }
    if (!cont) { mobToast('请输入记录内容','error'); return; }
    var type = document.getElementById('cfRecordType').value;
    var payload = {
        zoneId: _cfSelZoneId, type: type, recordType: type,
        name: name, recordName: name, content: cont,
        ttl: parseInt(document.getElementById('cfRecordTtl').value)||1,
        proxied: document.getElementById('cfRecordProxied').checked
    };
    try {
        var res = await fetch(
            rid ? '/dns/cloudflare/api/records/'+encodeURIComponent(rid) : '/dns/cloudflare/api/records',
            { method: rid?'PUT':'POST',
              headers: {'Content-Type':'application/json','X-CSRF-TOKEN': csrf?csrf.content:''},
              body: JSON.stringify(payload) }
        );
        var json = await res.json();
        if (json.success || json.code===200) {
            mobToast(rid?'更新成功':'添加成功','success');
            cfCloseRecordSheet(); cfLoadDns();
        } else { mobToast(json.message||'操作失败','error'); }
    } catch(e) { mobToast('网络错误','error'); }
}

async function cfDeleteRecord(recordId) {
    if (!recordId) return;
    var ok = await mobConfirm('确定删除该 DNS 记录吗？','删除后无法恢复。');
    if (!ok) return;
    var csrf = document.querySelector('meta[name="_csrf"]');
    try {
        var res = await fetch('/dns/cloudflare/api/records/'+encodeURIComponent(recordId),
            { method:'DELETE', headers:{'X-CSRF-TOKEN': csrf?csrf.content:''} });
        var json = await res.json();
        if (json.success||json.code===200) { mobToast('已删除','success'); cfLoadDns(); }
        else { mobToast(json.message||'删除失败','error'); }
    } catch(e) { mobToast('网络错误','error'); }
}

/* ── 工具 ─────────────────────────────────── */
function escCf(s) {
    return s==null?'':String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;')
        .replace(/"/g,'&quot;').replace(/'/g,'&#39;');
}

/* ── 初始化 ─────────────────────────────────── */
cfLoadZones();
</script>
</#noparse>

</@layout.page>
