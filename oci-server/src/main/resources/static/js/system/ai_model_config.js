'use strict';

// ---------------------------------------------------------------------------
// Globals
// ---------------------------------------------------------------------------
var _csrfToken       = '';
var _csrfHeader      = '';
var _models          = [];          // models for selected tenant (left panel)
var _configs         = [];          // configured AI records from DB (right panel)
var _configuredModelIds = new Set();

var _modelPage       = 1;
var _configPage      = 1;
var PAGE_SIZE        = 6;
var _filterByTenant  = false;  // 关联租户开关状态

var i18n = window.I18N || {};

// ---------------------------------------------------------------------------
// XSS-escape helper
// ---------------------------------------------------------------------------
function esc(s) {
    if (s === null || s === undefined) { return ''; }
    return String(s)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

// ---------------------------------------------------------------------------
// Toast helper
// ---------------------------------------------------------------------------
function showToast(icon, title) {
    var Toast = Swal.mixin({
        toast: true,
        position: 'bottom-end',
        showConfirmButton: false,
        timer: 3000,
        timerProgressBar: true,
        didOpen: function(toast) {
            toast.addEventListener('mouseenter', Swal.stopTimer);
            toast.addEventListener('mouseleave', Swal.resumeTimer);
        }
    });
    Toast.fire({ icon: icon, title: title });
}

// ---------------------------------------------------------------------------
// DOMContentLoaded
// ---------------------------------------------------------------------------
document.addEventListener('DOMContentLoaded', function() {
    _csrfToken  = (document.querySelector('meta[name="_csrf"]')        || {}).content || '';
    _csrfHeader = (document.querySelector('meta[name="_csrf_header"]') || {}).content || '';

    var masterToggle = document.getElementById('masterToggle');
    if (masterToggle) {
        masterToggle.addEventListener('change', handleMasterToggle);
    }

    loadTenants();
    loadConfigs();
});

// ---------------------------------------------------------------------------
// Left panel — tenants + models
// ---------------------------------------------------------------------------
async function loadTenants() {
    try {
        var response = await fetch('/system/ai/tenants', {
            headers: { [_csrfHeader]: _csrfToken }
        });
        if (!response.ok) { throw new Error(i18n.common_loadFail || 'Load failed'); }

        var tenants = await response.json();
        var sel = document.getElementById('tenantSelect');
        if (!sel) { return; }

        // Remove all options except a blank placeholder
        sel.innerHTML = '<option value=""></option>';
        tenants.forEach(function(t) {
            var opt = document.createElement('option');
            opt.value       = esc(t.id);
            opt.textContent = t.name;
            sel.appendChild(opt);
        });

        if (window.CustomSelect) { CustomSelect.refresh(sel); }

    } catch (e) {
        console.error('loadTenants error', e);
        showToast('error', i18n.common_loadFail || 'Load failed');
    }
}

// Called by the tenant <select> onchange (or CustomSelect callback)
async function onTenantChange() {
    var sel = document.getElementById('tenantSelect');
    if (!sel) { return; }
    var tenantId = sel.value;

    var modelList = document.getElementById('modelList');
    var leftLoading = document.getElementById('leftLoading');

    _models     = [];
    _modelPage  = 1;

    if (!tenantId) {
        if (modelList) { modelList.innerHTML = ''; }
        renderModelPagination();
        return;
    }

    if (leftLoading) { leftLoading.style.display = 'block'; }
    if (modelList)   { modelList.innerHTML = ''; }

    try {
        var response = await fetch('/system/ai/modelsByTenant?tenantId=' + encodeURIComponent(tenantId), {
            headers: { [_csrfHeader]: _csrfToken }
        });
        if (!response.ok) { throw new Error(i18n.common_loadFail || 'Load failed'); }

        _models = await response.json();
        renderModels();
        // 若关联租户开关开着，同步刷新右侧列表
        if (_filterByTenant) { _configPage = 1; renderConfigs(); }

    } catch (e) {
        console.error('onTenantChange error', e);
        if (modelList) {
            modelList.innerHTML =
                '<div class="empty-state">' +
                '<i class="fas fa-exclamation-triangle"></i>' +
                '<p>' + esc(i18n.common_loadFail) + '</p>' +
                '</div>';
        }
        renderModelPagination();
    } finally {
        if (leftLoading) { leftLoading.style.display = 'none'; }
    }
}

function renderModels() {
    var container = document.getElementById('modelList');
    if (!container) { return; }

    if (!_models || _models.length === 0) {
        container.innerHTML =
            '<div class="empty-state">' +
            '<i class="fas fa-robot fa-2x"></i>' +
            '<p>' + esc(i18n.aiModel_noModelForTenant || i18n.aiModel_noModel) + '</p>' +
            '</div>';
        renderModelPagination();
        return;
    }

    var total      = _models.length;
    var totalPages = Math.ceil(total / PAGE_SIZE);
    if (_modelPage > totalPages) { _modelPage = totalPages; }
    if (_modelPage < 1)          { _modelPage = 1; }

    var start = (_modelPage - 1) * PAGE_SIZE;
    var end   = Math.min(start + PAGE_SIZE, total);
    var slice = _models.slice(start, end);

    var html = '';
    slice.forEach(function(model) {
        var isAdded = _configuredModelIds.has(model.id);
        var btnClass = isAdded ? 'btn-secondary' : 'btn-primary';
        var btnText  = isAdded
            ? esc(i18n.aiModel_alreadyAdded || '已添加')
            : esc(i18n.aiModel_addToConfig  || '添加配置');
        var btnDisabled = isAdded ? 'disabled' : '';

        html +=
            '<div class="model-card">' +
            '  <div class="model-card-body">' +
            '    <div class="model-card-name">' + esc(model.name) + '</div>' +
            '    <span class="badge badge-provider">' + esc(model.provider) + '</span>' +
            '  </div>' +
            '  <div class="model-card-footer">' +
            '    <button class="btn btn-sm ' + btnClass + '" ' + btnDisabled +
            '      onclick=\'addModelConfig(' + JSON.stringify(model) + ')\'>' +
            '      <i class="fas fa-plus"></i> ' + btnText +
            '    </button>' +
            '  </div>' +
            '</div>';
    });

    container.innerHTML = html;
    renderModelPagination();
}

function renderModelPagination() {
    var total      = _models ? _models.length : 0;
    var totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

    var pageInfo = document.getElementById('modelPageInfo');
    var prevBtn  = document.getElementById('modelPrevBtn');
    var nextBtn  = document.getElementById('modelNextBtn');
    var paginationEl = document.getElementById('modelPagination');

    if (pageInfo) { pageInfo.textContent = _modelPage + ' / ' + totalPages; }
    if (prevBtn)  { prevBtn.disabled  = (_modelPage <= 1); }
    if (nextBtn)  { nextBtn.disabled  = (_modelPage >= totalPages); }
    if (paginationEl) {
        paginationEl.style.display = (total > 0) ? '' : 'none';
    }
}

function changeModelPage(delta) {
    var total      = _models ? _models.length : 0;
    var totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
    _modelPage = Math.min(Math.max(1, _modelPage + delta), totalPages);
    renderModels();
}

async function addModelConfig(model) {
    try {
        var sel = document.getElementById('tenantSelect');
        var tenantId = sel ? sel.value : (model.tenantId || '');

        var configData = {
            tenantId:  tenantId,
            modelId:   model.id,
            modelName: model.name,
            provider:  model.provider,
            enabled:   true,
            cloudType: 1,
            userName:  model.userName || ''
        };

        var response = await fetch('/system/updateTelegramAiConfig', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [_csrfHeader]: _csrfToken
            },
            body: JSON.stringify(configData)
        });

        if (!response.ok) {
            var msg = await response.text();
            throw new Error(msg || 'Save failed');
        }

        showToast('success', i18n.aiModel_added || 'Added');
        await loadConfigs();
        renderModels();  // update button states

    } catch (e) {
        console.error('addModelConfig error', e);
        showToast('error', e.message || (i18n.common_loadFail || 'Error'));
    }
}

// ---------------------------------------------------------------------------
// Right panel — configured records
// ---------------------------------------------------------------------------
async function loadConfigs() {
    try {
        var response = await fetch('/system/telegramAiConfigs', {
            headers: { [_csrfHeader]: _csrfToken }
        });
        if (!response.ok) { throw new Error(i18n.common_loadFail || 'Load failed'); }

        _configs = await response.json();
        _configuredModelIds = new Set(_configs.map(function(c) { return c.modelId; }));

        _configPage = 1;
        renderConfigs();

        // update master toggle
        var masterToggle = document.getElementById('masterToggle');
        if (masterToggle && _configs.length > 0) {
            var hasEnabled = _configs.some(function(c) { return c.enabled; });
            masterToggle.checked = hasEnabled;
        } else if (masterToggle) {
            masterToggle.checked = false;
        }

    } catch (e) {
        console.error('loadConfigs error', e);
        var container = document.getElementById('configList');
        if (container) {
            container.innerHTML =
                '<div class="empty-state">' +
                '<i class="fas fa-exclamation-triangle"></i>' +
                '<p>' + esc(i18n.common_loadFail) + '</p>' +
                '</div>';
        }
    }
}

/* 根据关联租户开关决定展示哪些配置 */
function getVisibleConfigs() {
    if (!_filterByTenant) { return _configs; }
    var sel = document.getElementById('tenantSelect');
    var tenantId = sel ? sel.value : '';
    if (!tenantId) { return _configs; }
    return _configs.filter(function(c) { return String(c.tenantId) === String(tenantId); });
}

/* 关联租户开关切换 */
function onTenantLinkToggle() {
    var chk = document.getElementById('tenantLinkToggle');
    _filterByTenant = chk ? chk.checked : false;
    _configPage = 1;
    renderConfigs();
}

function renderConfigs() {
    var container = document.getElementById('configList');
    if (!container) { return; }

    var visible = getVisibleConfigs();

    if (!visible || visible.length === 0) {
        container.innerHTML =
            '<div class="empty-state">' +
            '<i class="fas fa-robot fa-2x"></i>' +
            '<p>' + esc(i18n.aiModel_noAvailableModel || i18n.aiModel_noModel) + '</p>' +
            '</div>';
        renderConfigPagination();
        return;
    }

    var total      = visible.length;
    var totalPages = Math.ceil(total / PAGE_SIZE);
    if (_configPage > totalPages) { _configPage = totalPages; }
    if (_configPage < 1)          { _configPage = 1; }

    var start = (_configPage - 1) * PAGE_SIZE;
    var end   = Math.min(start + PAGE_SIZE, total);
    var slice = visible.slice(start, end);

    var html = '';
    slice.forEach(function(config) {
        var isEnabled      = config.enabled;
        var statusClass    = isEnabled ? 'enabled' : 'disabled';
        var statusIcon     = isEnabled ? 'fa-check-circle' : 'fa-ban';
        var statusText     = isEnabled ? esc(i18n.common_start || '启用') : esc(i18n.common_stop || '禁用');
        var toggleBtnClass = isEnabled ? 'btn-outline-warning' : 'btn-outline-success';
        var toggleIcon     = isEnabled ? 'fa-pause-circle' : 'fa-play-circle';
        var toggleText     = isEnabled ? esc(i18n.common_stop || '禁用') : esc(i18n.common_start || '启用');
        var modelName      = esc(config.modelName || config.modelId);

        html +=
            '<div class="config-card ' + statusClass + '">' +
            '  <span class="config-card-title" title="' + modelName + '">' + modelName + '</span>' +
            '  <span class="badge-status ' + statusClass + '">' +
            '    <i class="fas ' + statusIcon + '"></i> ' + statusText +
            '  </span>' +
            '  <div class="config-card-actions">' +
            '    <button class="btn btn-sm ' + toggleBtnClass + '" ' +
            '      onclick="toggleConfig(' + config.id + ', ' + (!isEnabled) + ')">' +
            '      <i class="fas ' + toggleIcon + '"></i>' +
            '    </button>' +
            '    <button class="btn btn-sm btn-outline-danger" ' +
            '      onclick="deleteConfig(' + config.id + ')">' +
            '      <i class="fas fa-trash"></i>' +
            '    </button>' +
            '  </div>' +
            '</div>';
    });

    container.innerHTML = html;
    renderConfigPagination();
}

function renderConfigPagination() {
    var total      = getVisibleConfigs().length;
    var totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));

    var pageInfo = document.getElementById('configPageInfo');
    var prevBtn  = document.getElementById('configPrevBtn');
    var nextBtn  = document.getElementById('configNextBtn');
    var paginationEl = document.getElementById('configPagination');

    if (pageInfo) { pageInfo.textContent = _configPage + ' / ' + totalPages; }
    if (prevBtn)  { prevBtn.disabled  = (_configPage <= 1); }
    if (nextBtn)  { nextBtn.disabled  = (_configPage >= totalPages); }
    if (paginationEl) {
        paginationEl.style.display = (total > 0) ? '' : 'none';
    }
}

function changeConfigPage(delta) {
    var total      = _configs ? _configs.length : 0;
    var totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
    _configPage = Math.min(Math.max(1, _configPage + delta), totalPages);
    renderConfigs();
}

async function toggleConfig(id, enabled) {
    try {
        var response = await fetch('/system/updateTelegramAiConfig', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [_csrfHeader]: _csrfToken
            },
            body: JSON.stringify({ id: id, enabled: enabled })
        });

        if (!response.ok) {
            var msg = await response.text();
            throw new Error(msg || 'Toggle failed');
        }

        await loadConfigs();

    } catch (e) {
        console.error('toggleConfig error', e);
        showToast('error', e.message || (i18n.common_loadFail || 'Error'));
    }
}

async function deleteConfig(id) {
    try {
        var result = await Swal.fire({
            title: i18n.aiModel_delete_title || i18n.common_delete || 'Delete?',
            icon: 'warning',
            showCancelButton: true,
            confirmButtonColor: '#2196f3',
            cancelButtonColor: '#ff6b6b',
            confirmButtonText: i18n.common_confirm || 'Confirm',
            cancelButtonText:  i18n.common_cancel  || 'Cancel'
        });

        if (!result.isConfirmed) { return; }

        var response = await fetch('/system/deleteTelegramAiConfig/' + id, {
            method: 'DELETE',
            headers: { [_csrfHeader]: _csrfToken }
        });

        if (!response.ok) {
            var msg = await response.text();
            throw new Error(msg || 'Delete failed');
        }

        showToast('success', i18n.aiModel_deleteSuccess || 'Deleted');
        await loadConfigs();
        renderModels();  // clear "已添加" state if model is no longer configured

    } catch (e) {
        console.error('deleteConfig error', e);
        showToast('error', e.message || (i18n.common_loadFail || 'Error'));
    }
}

async function handleMasterToggle() {
    var masterToggle = document.getElementById('masterToggle');
    if (!masterToggle) { return; }

    var isEnabled = masterToggle.checked;

    try {
        var result = await Swal.fire({
            title:  isEnabled ? i18n.aiModel_enableAllAi  : i18n.aiModel_disableAllAi,
            text:   isEnabled ? i18n.aiModel_exeAllAi     : i18n.aiModel_exeDisAllAi,
            icon: 'question',
            showCancelButton: true,
            confirmButtonColor: '#2196f3',
            cancelButtonColor: '#ff6b6b',
            confirmButtonText: i18n.common_confirm || 'Confirm',
            cancelButtonText:  i18n.common_cancel  || 'Cancel'
        });

        if (!result.isConfirmed) {
            masterToggle.checked = !isEnabled;
            return;
        }

        var response = await fetch('/system/batchToggleTelegramAiConfigs', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [_csrfHeader]: _csrfToken
            },
            body: JSON.stringify({ enabled: isEnabled })
        });

        if (!response.ok) {
            var msg = await response.text();
            throw new Error(msg || 'Batch toggle failed');
        }

        showToast('success', isEnabled
            ? (i18n.aiModel_enableAllAi  || 'All enabled')
            : (i18n.aiModel_disableAllAi || 'All disabled'));

        await loadConfigs();

    } catch (e) {
        masterToggle.checked = !isEnabled;
        console.error('handleMasterToggle error', e);
        showToast('error', e.message || (i18n.common_loadFail || 'Error'));
    }
}
