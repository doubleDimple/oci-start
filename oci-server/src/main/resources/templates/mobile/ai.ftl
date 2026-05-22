<#import "layout.ftl" as layout>
<@layout.page title="${msg.get('mob.tab.ai')}" activePage="ai">

<!-- ═══ Section 1: Telegram AI 绑定 ═══ -->
<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px">
    <div style="font-size:15px;font-weight:600;color:var(--mob-text)">
        <i class="fas fa-comment" style="color:var(--mob-accent);margin-right:6px"></i>${msg.get('mob.ai.tg.title')}
    </div>
    <div style="display:flex;align-items:center;gap:8px;cursor:pointer" onclick="aiToggleAll()">
        <span style="font-size:12px;color:var(--mob-text-muted)" id="aiGlobalLabel">${msg.get('mob.ai.tg.global.off')}</span>
        <div class="ai-toggle-track" id="aiGlobalTrack"><div class="ai-toggle-thumb" id="aiGlobalThumb"></div></div>
    </div>
</div>
<div id="aiTgLoading" class="mob-loading"><div class="mob-spinner"></div><p>${msg.get('mob.loading')}</p></div>
<div id="aiTgList" style="display:none"></div>

<!-- ═══ Section 2: OCI 可用 AI 模型 ═══ -->
<div style="margin-top:24px;margin-bottom:10px;display:flex;align-items:center;justify-content:space-between">
    <div style="font-size:15px;font-weight:600;color:var(--mob-text)">
        <i class="fas fa-flask" style="color:var(--mob-accent);margin-right:6px"></i>${msg.get('mob.ai.models.title')}
    </div>
    <button class="mob-btn mob-btn-outline mob-btn-sm" id="aiLoadModelsBtn" onclick="aiLoadModelsClick()">
        <i class="fas fa-chevron-down"></i> ${msg.get('mob.ai.models.load')}
    </button>
</div>
<div id="aiModelLoading" style="display:none" class="mob-loading"><div class="mob-spinner"></div><p>${msg.get('mob.loading')}</p></div>
<div id="aiModelList" style="display:none">
    <!-- tenant cards -->
    <div id="aiTenantCards"></div>
    <!-- tenant pagination -->
    <div id="aiTenantPager" style="display:none;margin-top:12px">
        <div style="display:flex;align-items:center;justify-content:space-between;gap:8px">
            <button class="mob-btn mob-btn-outline mob-btn-sm" id="aiTenantPrevBtn" onclick="aiTenantPage(-1)">
                <i class="fas fa-chevron-left"></i> ${msg.get('mob.page.prev')}
            </button>
            <span id="aiTenantPageInfo" style="font-size:12px;color:var(--mob-text-muted)"></span>
            <button class="mob-btn mob-btn-outline mob-btn-sm" id="aiTenantNextBtn" onclick="aiTenantPage(1)">
                ${msg.get('mob.page.next')} <i class="fas fa-chevron-right"></i>
            </button>
        </div>
    </div>
</div>

<script>
var _aiI18n = {
    tgEmpty:    "${msg.get('mob.ai.tg.empty')}",
    tgLoadFail: "${msg.get('mob.ai.tg.load.fail')}",
    modelEmpty: "${msg.get('mob.ai.models.empty')}",
    globalOn:   "${msg.get('mob.ai.tg.global.on')}",
    globalOff:  "${msg.get('mob.ai.tg.global.off')}",
    enabled:    "${msg.get('mob.ai.status.enabled')}",
    disabled:   "${msg.get('mob.ai.status.disabled')}",
    deleteConfirmTitle: "${msg.get('mob.ai.delete.confirm')}",
    deleteConfirmMsg:   "${msg.get('mob.ai.delete.confirm.msg')}",
    enableModel:    "${msg.get('mob.ai.model.enable')}",
    enabling:       "${msg.get('mob.ai.model.enabling')}",
    enableOk:       "${msg.get('mob.ai.model.enable.ok')}",
    saveFail:       "${msg.get('mob.ai.save.fail')}",
    toggleFail:     "${msg.get('mob.ai.toggle.fail')}",
    deleteFail:     "${msg.get('mob.ai.delete.fail')}",
    batchToggleFail:"${msg.get('mob.ai.batch.toggle.fail')}",
    pageOf:         "${msg.get('mob.ai.page.of')}"
};
</script>
<#noparse>
<script>
/* ── constants ── */
var TENANT_PAGE_SIZE = 5;
var MODEL_PAGE_SIZE  = 5;

/* ── state ── */
var _aiTgConfigs  = [];
var _aiModelsData = [];
var _aiGlobalOn   = false;
var _tenantPage   = 0;          // current tenant page (0-based)
var _modelPages   = {};         // tenantGlobalIdx → model page (0-based)
var _openTenant   = -1;         // which tenant card is expanded (-1 = none)

/* ── CSRF ── */
function _csrf()  { return (document.querySelector('meta[name="_csrf"]')        || {}).content || ''; }
function _csrfH() { return (document.querySelector('meta[name="_csrf_header"]') || {}).content || 'X-CSRF-TOKEN'; }

/* ══ init ══ */
(function() { loadAiTgConfigs(); })();

/* ══════════════════════════════════════════
   Telegram AI 绑定
══════════════════════════════════════════ */
async function loadAiTgConfigs() {
    document.getElementById('aiTgLoading').style.display = '';
    document.getElementById('aiTgList').style.display = 'none';
    try {
        var res  = await fetch('/system/telegramAiConfigs', { headers: { [_csrfH()]: _csrf() } });
        _aiTgConfigs = await res.json();
        if (!Array.isArray(_aiTgConfigs)) _aiTgConfigs = [];
        renderAiTgList();
    } catch(e) {
        document.getElementById('aiTgLoading').innerHTML =
            '<p style="color:#f04747;text-align:center">' + _aiI18n.tgLoadFail + '</p>';
    }
}

function renderAiTgList() {
    document.getElementById('aiTgLoading').style.display = 'none';
    var listEl = document.getElementById('aiTgList');
    listEl.style.display = 'block';

    var hasEnabled = _aiTgConfigs.some(function(c){ return c.enabled; });
    _aiGlobalOn = hasEnabled;
    _updateGlobalSwitch(hasEnabled);

    if (_aiTgConfigs.length === 0) {
        listEl.innerHTML = '<div style="padding:20px 0;text-align:center">'
            + '<i class="fas fa-robot" style="font-size:32px;opacity:.25;display:block;margin-bottom:8px"></i>'
            + '<p style="color:var(--mob-text-muted);font-size:13px">' + _aiI18n.tgEmpty + '</p></div>';
        return;
    }

    listEl.innerHTML = _aiTgConfigs.map(function(c) {
        var name      = escHtmlSafe(c.modelName || c.modelId || '');
        var user      = escHtmlSafe(c.userName  || '');
        var region    = escHtmlSafe(c.region    || '');
        var provider  = escHtmlSafe(c.provider  || '');
        var isOn      = !!c.enabled;
        var meta      = [user, region, provider].filter(Boolean).join(' · ');
        return '<div class="mob-card" style="margin-bottom:10px">'
            + '<div class="mob-card-header" style="align-items:flex-start">'
            + '<span class="mob-dot ' + (isOn ? 'mob-dot-green' : 'mob-dot-gray') + '" style="margin-top:4px;flex-shrink:0"></span>'
            + '<div style="flex:1;min-width:0;margin-left:8px">'
            + '<div class="mob-card-title" style="font-size:14px">' + name + '</div>'
            + (meta ? '<div class="mob-card-subtitle" style="margin-top:2px">' + meta + '</div>' : '')
            + '<span style="display:inline-block;margin-top:4px;font-size:11px;padding:2px 8px;border-radius:10px;'
            + (isOn ? 'background:rgba(67,181,129,.15);color:#43b581' : 'background:rgba(114,118,125,.12);color:var(--mob-text-muted)')
            + '">' + (isOn ? _aiI18n.enabled : _aiI18n.disabled) + '</span>'
            + '</div>'
            + '<div style="display:flex;gap:6px;flex-shrink:0;margin-left:8px">'
            + '<button class="mob-btn mob-btn-outline mob-btn-sm" style="padding:0 10px;height:30px" onclick="aiToggleConfig(' + c.id + ',' + (!isOn) + ')">'
            + (isOn ? '<i class="fas fa-pause"></i>' : '<i class="fas fa-play"></i>') + '</button>'
            + '<button class="mob-btn mob-btn-outline mob-btn-sm" style="padding:0 10px;height:30px;color:#f04747;border-color:rgba(240,71,71,.4)" onclick="aiDeleteConfig(' + c.id + ')">'
            + '<i class="fas fa-trash"></i></button>'
            + '</div>'
            + '</div></div>';
    }).join('');
}

function _updateGlobalSwitch(on) {
    var track = document.getElementById('aiGlobalTrack');
    var thumb = document.getElementById('aiGlobalThumb');
    var label = document.getElementById('aiGlobalLabel');
    if (!track) return;
    track.style.background   = on ? '#43b581' : 'var(--mob-border)';
    thumb.style.transform    = on ? 'translateX(18px)' : 'translateX(0)';
    label.style.color        = on ? '#43b581' : 'var(--mob-text-muted)';
    label.textContent        = on ? _aiI18n.globalOn : _aiI18n.globalOff;
}

async function aiToggleAll() {
    var newState = !_aiGlobalOn;
    try {
        var res = await fetch('/system/batchToggleTelegramAiConfigs', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', [_csrfH()]: _csrf() },
            body: JSON.stringify({ enabled: newState })
        });
        if (!res.ok) throw new Error();
        await loadAiTgConfigs();
    } catch(e) { mobToast(_aiI18n.batchToggleFail, 'error'); }
}

async function aiToggleConfig(id, enabled) {
    try {
        var res = await fetch('/system/updateTelegramAiConfig', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', [_csrfH()]: _csrf() },
            body: JSON.stringify({ id: id, enabled: enabled })
        });
        if (!res.ok) throw new Error();
        await loadAiTgConfigs();
    } catch(e) { mobToast(_aiI18n.toggleFail, 'error'); }
}

async function aiDeleteConfig(id) {
    var ok = await mobConfirm(_aiI18n.deleteConfirmTitle, _aiI18n.deleteConfirmMsg);
    if (!ok) return;
    try {
        var res = await fetch('/system/deleteTelegramAiConfig/' + id, {
            method: 'DELETE', headers: { [_csrfH()]: _csrf() }
        });
        if (!res.ok) throw new Error();
        await loadAiTgConfigs();
    } catch(e) { mobToast(_aiI18n.deleteFail, 'error'); }
}

/* ══════════════════════════════════════════
   OCI 可用 AI 模型（分页）
══════════════════════════════════════════ */
function aiLoadModelsClick() {
    var btn = document.getElementById('aiLoadModelsBtn');
    if (btn) btn.style.display = 'none';
    loadAiModels();
}

async function loadAiModels() {
    document.getElementById('aiModelLoading').style.display = '';
    document.getElementById('aiModelList').style.display = 'none';
    try {
        var res = await fetch('/system/aiModels', { headers: { [_csrfH()]: _csrf() } });
        _aiModelsData = await res.json();
        if (!Array.isArray(_aiModelsData)) _aiModelsData = [];
        _tenantPage = 0;
        _modelPages = {};
        _openTenant = -1;
        renderTenantPage();
    } catch(e) {
        document.getElementById('aiModelLoading').innerHTML =
            '<p style="color:#f04747;text-align:center">' + _aiI18n.modelEmpty + '</p>';
    }
}

/* 渲染当前租户分页 */
function renderTenantPage() {
    document.getElementById('aiModelLoading').style.display = 'none';
    document.getElementById('aiModelList').style.display = 'block';

    var total     = _aiModelsData.length;
    var totalPages = Math.ceil(total / TENANT_PAGE_SIZE) || 1;
    var start     = _tenantPage * TENANT_PAGE_SIZE;
    var pageTenants = _aiModelsData.slice(start, start + TENANT_PAGE_SIZE);

    var cardsEl  = document.getElementById('aiTenantCards');
    var pagerEl  = document.getElementById('aiTenantPager');
    var prevBtn  = document.getElementById('aiTenantPrevBtn');
    var nextBtn  = document.getElementById('aiTenantNextBtn');
    var pageInfo = document.getElementById('aiTenantPageInfo');

    if (total === 0) {
        cardsEl.innerHTML = '<div style="padding:20px 0;text-align:center">'
            + '<i class="fas fa-microchip" style="font-size:32px;opacity:.25;display:block;margin-bottom:8px"></i>'
            + '<p style="color:var(--mob-text-muted);font-size:13px">' + _aiI18n.modelEmpty + '</p></div>';
        pagerEl.style.display = 'none';
        return;
    }

    /* 展开状态：仅当展开的 globalIdx 在本页才保留，否则关闭 */
    var openInPage = pageTenants.some(function(_, i) { return start + i === _openTenant; });
    if (!openInPage) _openTenant = -1;

    cardsEl.innerHTML = pageTenants.map(function(tenant, localIdx) {
        var globalIdx = start + localIdx;
        var tName  = escHtmlSafe((tenant.tenantInfo || {}).userName || '');
        var models = tenant.models || [];
        var isOpen = (_openTenant === globalIdx);
        var modelsHtml = isOpen ? _buildModelsHtml(globalIdx, models) : '';

        return '<div class="mob-card" style="margin-bottom:10px">'
            + '<div class="mob-card-header" onclick="aiToggleTenant(' + globalIdx + ')" style="cursor:pointer">'
            + '<i class="fas fa-building" style="color:var(--mob-accent);margin-right:8px;flex-shrink:0"></i>'
            + '<div style="flex:1;font-weight:600;font-size:14px;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + tName + '</div>'
            + '<span style="font-size:12px;color:var(--mob-text-muted);margin-right:4px;flex-shrink:0">' + models.length + ' 个</span>'
            + '<i class="fas fa-chevron-' + (isOpen ? 'up' : 'down') + '" style="font-size:12px;flex-shrink:0"></i>'
            + '</div>'
            + '<div id="tenant-models-' + globalIdx + '" style="' + (isOpen ? '' : 'display:none') + '">'
            + modelsHtml
            + '</div>'
            + '</div>';
    }).join('');

    /* 分页控件 */
    pagerEl.style.display = totalPages > 1 ? '' : 'none';
    pageInfo.textContent  = (_tenantPage + 1) + ' / ' + totalPages;
    prevBtn.disabled      = _tenantPage === 0;
    nextBtn.disabled      = _tenantPage >= totalPages - 1;
}

/* 构建某租户下的模型列表 HTML（含分页） */
function _buildModelsHtml(globalIdx, models) {
    var page      = _modelPages[globalIdx] || 0;
    var total     = models.length;
    var totalPages = Math.ceil(total / MODEL_PAGE_SIZE) || 1;
    var start     = page * MODEL_PAGE_SIZE;
    var pageModels = models.slice(start, start + MODEL_PAGE_SIZE);
    var tenantId  = ((_aiModelsData[globalIdx] || {}).tenantInfo || {}).tenantId || '';

    if (total === 0) {
        return '<p style="font-size:12px;color:var(--mob-text-muted);text-align:center;padding:12px">暂无可用模型</p>';
    }

    var rows = pageModels.map(function(m) {
        var mName  = escHtmlSafe(m.name || m.modelName || '');
        var mProv  = escHtmlSafe(m.provider || '');
        /* 把 model 信息 JSON 编码后传给按钮，避免引号冲突 */
        var mData  = encodeURIComponent(JSON.stringify({
            id: m.id, name: m.name || m.modelName, provider: m.provider, tenantId: tenantId
        }));
        return '<div style="display:flex;align-items:center;gap:8px;padding:8px 0;border-bottom:1px solid var(--mob-border)">'
            + '<div style="flex:1;min-width:0">'
            + '<div style="font-size:13px;font-weight:500;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + mName + '</div>'
            + (mProv ? '<div style="font-size:11px;color:var(--mob-text-muted)">' + mProv + '</div>' : '')
            + '</div>'
            + '<button class="mob-btn mob-btn-outline mob-btn-sm" style="flex-shrink:0;font-size:11px;white-space:nowrap" '
            + 'onclick="aiEnableModel(this,\'' + mData + '\')">'
            + '<i class="fas fa-plug"></i> ' + _aiI18n.enableModel + '</button>'
            + '</div>';
    }).join('');

    var pager = '';
    if (totalPages > 1) {
        pager = '<div style="display:flex;align-items:center;justify-content:space-between;padding:8px 0">'
            + '<button class="mob-btn mob-btn-outline mob-btn-sm" ' + (page === 0 ? 'disabled' : '')
            + ' onclick="aiModelPage(' + globalIdx + ',-1)">'
            + '<i class="fas fa-chevron-left"></i></button>'
            + '<span style="font-size:12px;color:var(--mob-text-muted)">' + (page+1) + ' / ' + totalPages + '</span>'
            + '<button class="mob-btn mob-btn-outline mob-btn-sm" ' + (page >= totalPages-1 ? 'disabled' : '')
            + ' onclick="aiModelPage(' + globalIdx + ',1)">'
            + '<i class="fas fa-chevron-right"></i></button>'
            + '</div>';
    }

    return '<div style="padding:0 4px">' + rows + pager + '</div>';
}

/* 展开 / 折叠租户 */
function aiToggleTenant(globalIdx) {
    _openTenant = (_openTenant === globalIdx) ? -1 : globalIdx;
    if (_modelPages[globalIdx] === undefined) _modelPages[globalIdx] = 0;
    renderTenantPage();
}

/* 租户翻页 */
function aiTenantPage(dir) {
    var total = Math.ceil(_aiModelsData.length / TENANT_PAGE_SIZE) || 1;
    _tenantPage = Math.max(0, Math.min(_tenantPage + dir, total - 1));
    _openTenant = -1;
    renderTenantPage();
}

/* 模型翻页 */
function aiModelPage(globalIdx, dir) {
    var models = (_aiModelsData[globalIdx] || {}).models || [];
    var total  = Math.ceil(models.length / MODEL_PAGE_SIZE) || 1;
    _modelPages[globalIdx] = Math.max(0, Math.min((_modelPages[globalIdx] || 0) + dir, total - 1));
    renderTenantPage();
}

/* 启用模型 */
async function aiEnableModel(btn, encodedData) {
    var m = JSON.parse(decodeURIComponent(encodedData));
    var orig = btn.innerHTML;
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i>';
    try {
        var res = await fetch('/system/updateTelegramAiConfig', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', [_csrfH()]: _csrf() },
            body: JSON.stringify({
                tenantId:  m.tenantId,
                modelId:   m.id,
                modelName: m.name,
                provider:  m.provider,
                enabled:   true,
                cloudType: 1
            })
        });
        if (!res.ok) throw new Error(await res.text());
        mobToast(_aiI18n.enableOk, 'success');
        await loadAiTgConfigs();
    } catch(e) {
        mobToast(_aiI18n.saveFail, 'error');
    } finally {
        btn.disabled = false;
        btn.innerHTML = orig;
    }
}
</script>
</#noparse>

<style>
.ai-toggle-track {
    width: 40px; height: 22px; border-radius: 11px;
    background: var(--mob-border); position: relative; transition: background .25s; cursor: pointer;
}
.ai-toggle-thumb {
    position: absolute; top: 3px; left: 3px;
    width: 16px; height: 16px; border-radius: 50%;
    background: #fff; box-shadow: 0 1px 3px rgba(0,0,0,.3); transition: transform .25s;
}
</style>

</@layout.page>
