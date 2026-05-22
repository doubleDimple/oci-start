<#import "layout.ftl" as layout>
<@layout.page title="硬盘信息" activePage="tenants">

<style>
.di-back-bar { display:flex;align-items:center;gap:12px;margin-bottom:16px }
.di-back-btn { width:36px;height:36px;border-radius:50%;border:1.5px solid var(--mob-border);background:var(--mob-card);color:var(--mob-text);display:flex;align-items:center;justify-content:center;cursor:pointer;flex-shrink:0;padding:0 }
.di-volume-card {
    background:var(--mob-card);border:1px solid var(--mob-border);border-radius:12px;
    margin-bottom:12px;overflow:hidden;
}
.di-volume-head {
    display:flex;align-items:center;gap:10px;padding:11px 14px 10px;
}
.di-vol-icon {
    width:36px;height:36px;border-radius:9px;background:rgba(26,188,156,0.12);
    display:flex;align-items:center;justify-content:center;
    color:#1abc9c;font-size:16px;flex-shrink:0;
}
.di-vol-info { flex:1;min-width:0 }
/* ── 名称行：名称（可截断）+ 右侧 size·vpu ── */
.di-vol-name-row { display:flex;align-items:center;gap:6px }
.di-vol-name {
    flex:1;min-width:0;
    font-size:14px;font-weight:700;color:var(--mob-text);
    overflow:hidden;text-overflow:ellipsis;white-space:nowrap;
}
.di-vol-meta {
    flex-shrink:0;font-size:12px;font-weight:700;color:#1abc9c;white-space:nowrap;
}
.di-vol-inst { font-size:11px;color:var(--mob-text-muted);margin-top:3px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap }
.di-volume-actions { display:flex;gap:8px;padding:8px 14px 12px;border-top:1px solid var(--mob-border) }

/* 编辑弹窗 */
.di-edit-row { margin-bottom:14px }
.di-edit-label { font-size:12px;color:var(--mob-text-muted);margin-bottom:5px;font-weight:600 }
.di-edit-input {
    width:100%;box-sizing:border-box;background:var(--mob-bg);border:1px solid var(--mob-border);
    border-radius:8px;padding:10px 12px;font-size:14px;color:var(--mob-text);outline:none;
    -webkit-appearance:none;
}
.di-edit-input:focus { border-color:#1abc9c }

/* VPU 滑块 */
.di-vpu-slider-row { display:flex;align-items:center;gap:10px }
.di-vpu-slider {
    flex:1;-webkit-appearance:none;appearance:none;height:6px;border-radius:3px;
    background:linear-gradient(to right,#1abc9c 0%,#1abc9c var(--pct,0%),var(--mob-border) var(--pct,0%),var(--mob-border) 100%);
    outline:none;cursor:pointer;
}
.di-vpu-slider::-webkit-slider-thumb {
    -webkit-appearance:none;width:20px;height:20px;border-radius:50%;
    background:#1abc9c;cursor:pointer;box-shadow:0 2px 6px rgba(26,188,156,.5);
}
.di-vpu-slider::-moz-range-thumb {
    width:20px;height:20px;border-radius:50%;border:none;
    background:#1abc9c;cursor:pointer;
}
.di-vpu-val-badge {
    min-width:36px;text-align:center;font-size:15px;font-weight:700;
    color:#1abc9c;
}
</style>

<!-- 返回栏 -->
<div class="di-back-bar">
    <button class="di-back-btn" onclick="history.back()"><i class="fas fa-chevron-left" style="font-size:13px"></i></button>
    <div style="flex:1;min-width:0">
        <div style="font-size:16px;font-weight:700;color:var(--mob-text)">硬盘信息</div>
        <div style="font-size:11px;color:var(--mob-text-muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap" id="diTenantName">—</div>
    </div>
    <button class="mob-btn mob-btn-outline mob-btn-sm" onclick="loadVolumes()" style="flex-shrink:0">
        <i class="fas fa-sync-alt"></i>
    </button>
</div>

<!-- 加载中 -->
<div class="mob-loading" id="diLoading"><div class="mob-spinner"></div><p>加载中...</p></div>
<!-- 列表 -->
<div id="diList" style="display:none"></div>

<!-- ══ 编辑 VPU 弹窗 ══ -->
<div id="diEditModal" class="mob-center-overlay" style="display:none" onclick="closeDiEdit(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-width:360px">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title"><i class="fas fa-hdd" style="color:#1abc9c;margin-right:6px"></i>编辑磁盘</div>
            <button class="mob-sheet-close" onclick="closeDiEdit()"><i class="fas fa-times"></i></button>
        </div>
        <div style="padding:14px 16px 0">
            <div class="di-edit-row">
                <div class="di-edit-label">磁盘名称</div>
                <input class="di-edit-input" id="diEditName" type="text" placeholder="输入磁盘名称">
            </div>
            <div class="di-edit-row">
                <div class="di-edit-label">VPUs / GB <span style="color:var(--mob-text-muted);font-weight:400">(0 ~ 120，每档 +10)</span></div>
                <div class="di-vpu-slider-row">
                    <input class="di-vpu-slider" id="diVpuSlider" type="range" min="0" max="120" step="10" value="0"
                           oninput="onVpuSlider(this.value)">
                    <span class="di-vpu-val-badge" id="diVpuValBadge">0</span>
                </div>
            </div>
        </div>
        <div style="padding:8px 16px 20px;display:flex;gap:10px">
            <button class="mob-btn mob-btn-outline" style="flex:1" onclick="closeDiEdit()">取消</button>
            <button class="mob-btn" id="diEditSaveBtn" style="flex:1;background:#1abc9c;color:#fff;border:none" onclick="saveDiEdit()">保存</button>
        </div>
    </div>
</div>

<!-- ══ 删除确认弹窗 ══ -->
<div id="diDelModal" class="mob-center-overlay" style="display:none" onclick="closeDiDel(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-width:340px">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title" style="color:#f04747"><i class="fas fa-exclamation-triangle" style="margin-right:6px"></i>确认删除</div>
            <button class="mob-sheet-close" onclick="closeDiDel()"><i class="fas fa-times"></i></button>
        </div>
        <div style="padding:16px 16px 8px">
            <p style="color:var(--mob-text);font-size:14px;line-height:1.6">
                确认删除磁盘 <strong id="diDelName" style="color:#f04747"></strong> 吗？<br>
                <span style="color:var(--mob-text-muted);font-size:12px">此操作不可恢复。</span>
            </p>
        </div>
        <div style="padding:8px 16px 20px;display:flex;gap:10px">
            <button class="mob-btn mob-btn-outline" style="flex:1" onclick="closeDiDel()">取消</button>
            <button class="mob-btn" id="diDelConfirmBtn" style="flex:1;background:#f04747;color:#fff;border:none" onclick="confirmDelete()">确认删除</button>
        </div>
    </div>
</div>

<script>
var _diTenantId   = '${tenantId}';
var _diTenantName = '${tenantName}';
var _diEditId     = null;
var _diDelId      = null;
var _diEditVpu    = 0;
</script>
<#noparse>
<script>
document.getElementById('diTenantName').textContent = _diTenantName || _diTenantId || '—';

/* ══ 加载磁盘列表 ══ */
async function loadVolumes() {
    document.getElementById('diLoading').style.display = '';
    document.getElementById('diList').style.display = 'none';
    try {
        var res  = await fetch('/tenants/boot-volumes?tenantId=' + encodeURIComponent(_diTenantId));
        var json = await res.json();
        renderVolumes(json.data || json || []);
    } catch(e) {
        document.getElementById('diLoading').innerHTML = '<p style="color:#f04747;text-align:center">加载失败：' + e.message + '</p>';
    }
}

function renderVolumes(vols) {
    var loading = document.getElementById('diLoading');
    var list    = document.getElementById('diList');
    loading.style.display = 'none';
    list.style.display    = 'block';

    if (!vols || vols.length === 0) {
        list.innerHTML = '<div class="mob-empty"><i class="fas fa-hdd"></i><p>暂无磁盘数据</p></div>';
        return;
    }

    list.innerHTML = vols.map(function(v) {
        var name      = escH(v.displayName || v.volumeName || '未命名');
        var attached  = !!(v.instanceName);          // 已挂载
        var instLine  = attached
            ? '<i class="fas fa-server" style="opacity:.5;font-size:10px;margin-right:3px"></i>' + escH(v.instanceName)
            : '<i class="fas fa-unlink" style="opacity:.4;font-size:10px;margin-right:3px"></i>未挂载';
        var size      = v.sizeInGBs != null ? v.sizeInGBs : '—';
        var vpus      = v.vpusPerGB != null ? v.vpusPerGB : '—';
        var metaText  = size + 'G · VPU ' + vpus;
        var vid       = escH(v.id || '');

        /* 未挂载才可删除 */
        var delDisabled = attached
            ? 'disabled title="已挂载，不可删除" style="opacity:0.35;cursor:not-allowed"'
            : 'onclick="openDiDel(\'' + vid + '\', \'' + name + '\')"';

        return '<div class="di-volume-card">'
            + '<div class="di-volume-head">'
            +   '<div class="di-vol-icon"><i class="fas fa-hdd"></i></div>'
            +   '<div class="di-vol-info">'
            +     '<div class="di-vol-name-row">'
            +       '<span class="di-vol-name">' + name + '</span>'
            +       '<span class="di-vol-meta">' + escH(metaText) + '</span>'
            +     '</div>'
            +     '<div class="di-vol-inst">' + instLine + '</div>'
            +   '</div>'
            + '</div>'
            + '<div class="di-volume-actions">'
            +   '<button class="mob-btn mob-btn-outline mob-btn-sm" style="flex:1" onclick="openDiEdit(\'' + vid + '\', \'' + name + '\', ' + (v.vpusPerGB || 0) + ')">'
            +     '<i class="fas fa-edit"></i> 编辑</button>'
            +   '<button class="mob-btn mob-btn-sm" style="flex:0.7;background:rgba(240,71,71,0.1);color:#f04747;border:1px solid rgba(240,71,71,0.3)" ' + delDisabled + '>'
            +     '<i class="fas fa-trash-alt"></i> 删除</button>'
            + '</div>'
            + '</div>';
    }).join('');
}

/* ══ VPU 滑块 ══ */
function onVpuSlider(val) {
    _diEditVpu = parseInt(val) || 0;
    document.getElementById('diVpuValBadge').textContent = _diEditVpu;
    /* 渐变进度色 */
    var pct = (_diEditVpu / 120 * 100).toFixed(1) + '%';
    document.getElementById('diVpuSlider').style.setProperty('--pct', pct);
}

/* ══ 编辑弹窗 ══ */
function openDiEdit(id, name, vpus) {
    _diEditId  = id;
    _diEditVpu = parseInt(vpus) || 0;
    document.getElementById('diEditName').value = name;
    var slider = document.getElementById('diVpuSlider');
    slider.value = _diEditVpu;
    onVpuSlider(_diEditVpu);
    document.getElementById('diEditModal').style.display = 'flex';
}

function closeDiEdit(e) {
    if (e && e.target !== document.getElementById('diEditModal')) return;
    document.getElementById('diEditModal').style.display = 'none';
}

async function saveDiEdit() {
    if (!_diEditId) return;
    var btn  = document.getElementById('diEditSaveBtn');
    var name = document.getElementById('diEditName').value.trim();
    btn.disabled = true; btn.textContent = '保存中…';
    var csrf = getCsrfToken();
    try {
        var res  = await fetch('/tenants/update-volumes/' + encodeURIComponent(_diEditId), {
            method: 'PUT',
            headers: Object.assign({ 'Content-Type': 'application/json' }, csrf),
            body: JSON.stringify({ displayName: name, vpusPerGB: _diEditVpu, tenantId: _diTenantId })
        });
        var json = await res.json();
        if (json.success || json.code === 200) {
            mobToast('保存成功', 'success');
            closeDiEdit();
            loadVolumes();
        } else {
            mobToast(json.message || '保存失败', 'error');
        }
    } catch(e) {
        mobToast('请求异常：' + e.message, 'error');
    }
    btn.disabled = false; btn.textContent = '保存';
}

/* ══ 删除弹窗 ══ */
function openDiDel(id, name) {
    _diDelId = id;
    document.getElementById('diDelName').textContent = name;
    document.getElementById('diDelModal').style.display = 'flex';
}

function closeDiDel(e) {
    if (e && e.target !== document.getElementById('diDelModal')) return;
    document.getElementById('diDelModal').style.display = 'none';
}

async function confirmDelete() {
    if (!_diDelId) return;
    var btn = document.getElementById('diDelConfirmBtn');
    btn.disabled = true; btn.textContent = '删除中…';
    var csrf = getCsrfToken();
    try {
        var res  = await fetch('/tenants/delete-volume/' + encodeURIComponent(_diDelId), {
            method: 'DELETE',
            headers: Object.assign({ 'Content-Type': 'application/json' }, csrf),
            body: JSON.stringify({ tenantId: _diTenantId })
        });
        var json = await res.json();
        if (json.success || json.code === 200) {
            mobToast('删除成功', 'success');
            document.getElementById('diDelModal').style.display = 'none';
            loadVolumes();
        } else {
            mobToast(json.message || '删除失败', 'error');
        }
    } catch(e) {
        mobToast('请求异常：' + e.message, 'error');
    }
    btn.disabled = false; btn.textContent = '确认删除';
}

function getCsrfToken() {
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

loadVolumes();
</script>
</#noparse>

</@layout.page>
