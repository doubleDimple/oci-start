
let csrfToken = document.querySelector('meta[name="_csrf"]').content;
let csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;
let currentPage = 1;
let pageSize = 10;
let totalPages = 0;
const i18n = window.I18N;
/** @type {{id:string,name:string,region?:string}[]} */
let parentTenants = [];
/** 当前弹窗选中的租户 id，空字符串 = 全局共享 */
let selectedTenantId = '';
/** 右侧租户列表分页（不含「全局共享」固定项） */
const TENANT_PAGE_SIZE = 7;
let tenantPageIndex = 0;

document.addEventListener('DOMContentLoaded', function() {

    // 侧边栏菜单展开/收起
    const navParents = document.querySelectorAll('.nav-parent');
    navParents.forEach(parent => {
        const parentLink = parent.querySelector('.nav-link');
        parentLink.addEventListener('click', (e) => {
            e.preventDefault();
            parent.classList.toggle('expanded');
        });
    });

    // 展开当前活动菜单
    const activeLink = document.querySelector('.nav-link.active');
    if (activeLink) {
        const parent = activeLink.closest('.nav-parent');
        if (parent) {
            parent.classList.add('expanded');
        }
    }

    loadParentTenants().finally(function() {
        loadProxyList(1);
    });

    document.querySelectorAll('.view-toggle .btn').forEach(btn => {
        btn.addEventListener('click', function() {
            switchView(this.getAttribute('data-view'));
        });
    });
});

function switchView(view) {
    const tableView = document.querySelector('.table-view');
    const gridView = document.querySelector('.grid-view');
    const buttons = document.querySelectorAll('.view-toggle .btn');

    buttons.forEach(btn => btn.classList.remove('active'));
    if (view === 'table') {
        buttons[0].classList.add('active');
        tableView.style.display = 'block';
        gridView.style.display = 'none';
    } else {
        buttons[1].classList.add('active');
        tableView.style.display = 'none';
        gridView.style.display = 'grid';
    }
    localStorage.setItem('preferredView', view);
}

function loadParentTenants() {
    return fetch('/tenants/listParentTenants', {
        method: 'GET',
        headers: {
            'Accept': 'application/json',
            [csrfHeaderName]: csrfToken
        }
    })
        .then(function(response) { return response.json(); })
        .then(function(data) {
            var list = Array.isArray(data) ? data : (data && data.data ? data.data : []);
            parentTenants = (list || []).map(function(t) {
                var id = t.id != null ? String(t.id) : '';
                var name = t.tenancyName || t.userName || t.tenantId || ('#' + id);
                return { id: id, name: name, region: t.region || '' };
            });
        })
        .catch(function(err) {
            console.warn('load parent tenants failed', err);
            parentTenants = [];
        });
}

function getTenantKeyword() {
    var searchEl = document.getElementById('tenantSearch');
    return searchEl ? (searchEl.value || '').trim().toLowerCase() : '';
}

/** 按搜索过滤后的父租户（不含全局） */
function getFilteredTenants() {
    var kw = getTenantKeyword();
    if (!kw) {
        return parentTenants.slice();
    }
    var out = [];
    for (var i = 0; i < parentTenants.length; i++) {
        var t = parentTenants[i];
        var hay = ((t.name || '') + ' ' + (t.region || '') + ' ' + (t.id || '')).toLowerCase();
        if (hay.indexOf(kw) >= 0) {
            out.push(t);
        }
    }
    return out;
}

/**
 * 渲染右侧可搜索 + 分页租户列表（全局共享固定在顶部，不占分页名额）
 * @param {string} selectedId 空字符串表示全局
 * @param {object} [opts]
 * @param {boolean} [opts.resetPage] 搜索时重置到第 1 页
 * @param {boolean} [opts.jumpToSelected] 打开编辑时跳到选中租户所在页
 */
function renderTenantPicker(selectedId, opts) {
    opts = opts || {};
    selectedTenantId = selectedId == null ? '' : String(selectedId);
    var hidden = document.getElementById('tenantId');
    if (hidden) {
        hidden.value = selectedTenantId;
    }
    updateTenantSelectedLabel();

    var listEl = document.getElementById('tenantList');
    if (!listEl) return;

    var filtered = getFilteredTenants();
    var total = filtered.length;
    var totalPages = Math.max(1, Math.ceil(total / TENANT_PAGE_SIZE) || 1);

    if (opts.resetPage) {
        tenantPageIndex = 0;
    }
    if (opts.jumpToSelected && selectedTenantId) {
        var jumpIdx = -1;
        for (var j = 0; j < filtered.length; j++) {
            if (String(filtered[j].id) === String(selectedTenantId)) {
                jumpIdx = j;
                break;
            }
        }
        if (jumpIdx >= 0) {
            tenantPageIndex = Math.floor(jumpIdx / TENANT_PAGE_SIZE);
        }
    }
    if (tenantPageIndex >= totalPages) {
        tenantPageIndex = totalPages - 1;
    }
    if (tenantPageIndex < 0) {
        tenantPageIndex = 0;
    }

    var start = tenantPageIndex * TENANT_PAGE_SIZE;
    var pageItems = filtered.slice(start, start + TENANT_PAGE_SIZE);

    var html = '';
    // 全局共享固定置顶
    var globalLabel = i18n.vpn_tenant_global || '全局共享';
    var globalActive = !selectedTenantId ? ' is-active' : '';
    html += '<button type="button" class="tenant-item is-global' + globalActive + '" data-id="" onclick="selectTenant(\'\')">'
        + '<span class="tenant-item-radio"></span>'
        + '<span class="tenant-item-body">'
        + '<div class="tenant-item-name">' + escapeHtml(globalLabel) + '</div>'
        + '<div class="tenant-item-meta">fallback pool</div>'
        + '</span></button>';

    if (pageItems.length === 0) {
        html += '<div class="tenant-list-empty">'
            + '<i class="fas fa-search" style="margin-right:6px;"></i>'
            + escapeHtml(i18n.vpn_tenant_empty || '无匹配租户')
            + '</div>';
    } else {
        for (var i = 0; i < pageItems.length; i++) {
            var t = pageItems[i];
            var active = (selectedTenantId && String(selectedTenantId) === String(t.id)) ? ' is-active' : '';
            var meta = t.region ? escapeHtml(t.region) : ('#' + escapeHtml(t.id));
            html += '<button type="button" class="tenant-item' + active + '" data-id="' + escapeHtml(t.id)
                + '" onclick="selectTenant(\'' + String(t.id).replace(/'/g, '') + '\')">'
                + '<span class="tenant-item-radio"></span>'
                + '<span class="tenant-item-body">'
                + '<div class="tenant-item-name" title="' + escapeHtml(t.name) + '">' + escapeHtml(t.name) + '</div>'
                + '<div class="tenant-item-meta">' + meta + '</div>'
                + '</span></button>';
        }
    }

    listEl.innerHTML = html;
    renderTenantPager(tenantPageIndex + 1, totalPages, total);
}

function renderTenantPager(page, totalPages, totalItems) {
    var pager = document.getElementById('tenantPager');
    var info = document.getElementById('tenantPageInfo');
    var prev = document.getElementById('tenantPagePrev');
    var next = document.getElementById('tenantPageNext');
    if (!pager || !info) {
        console.warn('[vpn_proxy] tenantPager DOM missing');
        return;
    }

    // 始终显示分页条（即使只有 1 页），避免“像没做分页”
    pager.style.display = 'flex';
    var tpl = (i18n && i18n.vpn_tenant_page) ? i18n.vpn_tenant_page : '{0} / {1} · 共 {2} 个';
    info.textContent = tpl
        .replace('{0}', String(page))
        .replace('{1}', String(Math.max(1, totalPages)))
        .replace('{2}', String(totalItems));

    if (prev) {
        prev.disabled = page <= 1;
        prev.setAttribute('aria-disabled', page <= 1 ? 'true' : 'false');
    }
    if (next) {
        next.disabled = page >= totalPages || totalItems === 0;
        next.setAttribute('aria-disabled', (page >= totalPages || totalItems === 0) ? 'true' : 'false');
    }
}

function changeTenantPage(delta) {
    var filtered = getFilteredTenants();
    var totalPages = Math.max(1, Math.ceil(filtered.length / TENANT_PAGE_SIZE) || 1);
    var next = tenantPageIndex + delta;
    if (next < 0 || next >= totalPages) {
        return;
    }
    tenantPageIndex = next;
    renderTenantPicker(selectedTenantId, {});
}

function updateTenantSelectedLabel() {
    var el = document.getElementById('tenantSelectedLabel');
    var bar = document.getElementById('tenantSelectedBar');
    if (!el) return;
    if (!selectedTenantId) {
        el.textContent = i18n.vpn_tenant_global || '全局共享';
        el.classList.add('is-global');
        if (bar) bar.classList.remove('has-tenant');
        return;
    }
    var name = '';
    for (var i = 0; i < parentTenants.length; i++) {
        if (String(parentTenants[i].id) === String(selectedTenantId)) {
            name = parentTenants[i].name;
            break;
        }
    }
    el.textContent = name || ('#' + selectedTenantId);
    el.classList.remove('is-global');
    if (bar) bar.classList.add('has-tenant');
}

function selectTenant(id) {
    renderTenantPicker(id == null ? '' : String(id), {});
}

function onTenantSearchInput() {
    renderTenantPicker(selectedTenantId, { resetPage: true });
}

function fillTenantSelect(selectedId) {
    var searchEl = document.getElementById('tenantSearch');
    if (searchEl) {
        searchEl.value = '';
    }
    tenantPageIndex = 0;
    var id = selectedId == null ? '' : String(selectedId);
    renderTenantPicker(id, { jumpToSelected: !!id });
}

function loadProxyList(pageNum) {
    currentPage = pageNum;
    const requestData = {
        pageNumber: pageNum,
        pageSize: pageSize
    };

    fetch('/vpnProxy/pageList', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrfHeaderName]: csrfToken
        },
        body: JSON.stringify(requestData)
    })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                const pageData = data.data;
                totalPages = pageData.totalPages;
                renderTableView(pageData.content);
                //renderGridView(pageData.content);
                renderPagination(pageNum, totalPages);
            } else {
                Swal.fire({ title: '错误', text: data.message || '加载失败', icon: 'error' });
            }
        })
        .catch(error => {
            console.error('加载失败:', error);
            Swal.fire({ title: '错误', text: '加载失败', icon: 'error' });
        });
}


function renderGridView(data) {
    const gridView = document.getElementById('gridView');
    if (!data || data.length === 0) {
        gridView.innerHTML = '';
        return;
    }

    let html = '';
    for (let i = 0; i < data.length; i++) {
        const record = data[i];
        const statusHtml = record.availableStatus === 1
            ? '<span class="status-badge status-running"><i class="fas fa-check-circle"></i> '+i18n.common_available+'</span>'
            : '<span class="status-badge status-offline"><i class="fas fa-times-circle"></i> '+i18n.common_noAvailable+'</span>';

        const username = record.proxyUsername || '-';
        const password = record.proxyPassword || '';
        const tenantLabel = formatTenantLabel(record);

        html += '<div class="instance-card">';
        html += '<div class="instance-card-header">';
        html += '<div class="instance-icon"><i class="fas fa-network-wired"></i></div>';
        html += '<div class="instance-title">';
        html += '<div class="instance-name">' + record.proxyType + '</div>';
        html += '<div class="instance-id">' + record.proxyHost + '</div>';
        html += '</div>';
        html += '</div>';
        html += '<div class="instance-content">';
        html += '<div class="instance-info-item"><span class="info-label">'+i18n.vpn_port+':</span><span class="info-value">' + record.proxyPort + '</span></div>';
        html += '<div class="instance-info-item"><span class="info-label">'+i18n.vpn_name+':</span><span class="info-value">' + username + '</span></div>';
        html += '<div class="instance-info-item"><span class="info-label">'+i18n.vpn_pass+':</span><span class="info-value"><span class="password-field" data-password="' + password + '" onclick="togglePassword(this)">********</span></span></div>';
        html += '<div class="instance-info-item"><span class="info-label">'+i18n.vpn_tenant+':</span><span class="info-value">' + tenantLabel + '</span></div>';
        html += '<div class="instance-info-item"><span class="info-label">'+i18n.vpn_status+':</span><span class="info-value">' + statusHtml + '</span></div>';
        html += '</div>';
        html += '<div class="instance-actions">';
        html += '<button class="btn btn-primary btn-icon" onclick="openEditModalFromRecord(' + record.id + ')"><i class="fas fa-edit"></i></button>';
        html += '<button class="btn btn-danger btn-icon" onclick="handleDelete(' + record.id + ')"><i class="fas fa-trash"></i></button>';
        html += '</div>';
        html += '</div>';
    }

    gridView.innerHTML = html;
}

function renderPagination(currentPageNum, total) {
    const paginationDiv = document.getElementById('pagination');
    if (total <= 1) {
        paginationDiv.innerHTML = '';
        return;
    }

    let html = '';

    if (currentPageNum > 1) {
        html += '<button class="btn btn-secondary" onclick="loadProxyList(1)"><i class="fas fa-step-backward"></i></button>';
        html += '<button class="btn btn-secondary" onclick="loadProxyList(' + (currentPageNum - 1) + ')"><i class="fas fa-chevron-left"></i></button>';
    }

    for (let i = 1; i <= total; i++) {
        if (i === currentPageNum) {
            html += '<button class="btn active">' + i + '</button>';
        } else if (i <= 3 || i >= total - 2 || (i >= currentPageNum - 2 && i <= currentPageNum + 2)) {
            html += '<button class="btn" onclick="loadProxyList(' + i + ')">' + i + '</button>';
        } else if (i === 4 || i === total - 3) {
            html += '<span style="padding: 0 5px;">...</span>';
        }
    }

    if (currentPageNum < total) {
        html += '<button class="btn btn-secondary" onclick="loadProxyList(' + (currentPageNum + 1) + ')"><i class="fas fa-chevron-right"></i></button>';
        html += '<button class="btn btn-secondary" onclick="loadProxyList(' + total + ')"><i class="fas fa-step-forward"></i></button>';
    }

    paginationDiv.innerHTML = html;
}

function refreshProxyModalSelects() {
    if (typeof CustomSelect === 'undefined') return;
    CustomSelect.refresh(document.getElementById('proxyType'));
    CustomSelect.refresh(document.getElementById('availableStatus'));
    CustomSelect.refresh(document.getElementById('forceProxy'));
}

function openAddModal() {
    const modal = document.getElementById('proxyModal');
    document.getElementById('proxyForm').reset();
    document.getElementById('proxyId').value = '';
    document.getElementById('forceProxy').value = '0';
    document.getElementById('modalTitle').textContent = i18n.vpn_save || '新增代理';
    fillTenantSelect('');
    refreshProxyModalSelects();
    modal.style.display = 'flex';
    setTimeout(() => { modal.style.opacity = '1'; }, 50);
}

/** 列表缓存，编辑时取完整字段（含 tenantId） */
var proxyListCache = {};
/** 正在测试中的代理 id 集合 */
var testingProxyIds = {};
/** 是否正在一键全部测试 */
var isTestingAll = false;

function openEditModal(id, proxyType, proxyHost, proxyPort, proxyUsername, proxyPassword, availableStatus, tenantId, forceProxy) {
    const modal = document.getElementById('proxyModal');
    document.getElementById('proxyId').value = id;
    document.getElementById('proxyType').value = proxyType;
    document.getElementById('proxyHost').value = proxyHost;
    document.getElementById('proxyPort').value = proxyPort;
    document.getElementById('proxyUsername').value = proxyUsername || '';
    document.getElementById('proxyPassword').value = proxyPassword || '';
    document.getElementById('availableStatus').value = availableStatus;
    document.getElementById('forceProxy').value = forceProxy != null ? String(forceProxy) : '0';
    fillTenantSelect(tenantId != null && tenantId !== '' ? tenantId : '');
    document.getElementById('modalTitle').textContent = i18n.vpn_edit;
    refreshProxyModalSelects();
    modal.style.display = 'flex';
    setTimeout(() => { modal.style.opacity = '1'; }, 50);
}

function openEditModalFromRecord(id) {
    var record = proxyListCache[id];
    if (!record) {
        Swal.fire({ title: 'error', text: 'record not found', icon: 'error' });
        return;
    }
    openEditModal(
        record.id,
        record.proxyType,
        record.proxyHost,
        record.proxyPort,
        record.proxyUsername || '',
        record.proxyPassword || '',
        record.availableStatus,
        record.tenantId,
        record.forceProxy
    );
}

function closeProxyModal() {
    const modal = document.getElementById('proxyModal');
    modal.style.opacity = '0';
    setTimeout(() => { modal.style.display = 'none'; }, 300);
}

function handleSaveProxy(event) {
    event.preventDefault();

    const proxyId = document.getElementById('proxyId').value;
    const proxyType = document.getElementById('proxyType').value;
    const proxyHost = document.getElementById('proxyHost').value;
    const proxyPort = document.getElementById('proxyPort').value;
    const proxyUsername = document.getElementById('proxyUsername').value;
    const proxyPassword = document.getElementById('proxyPassword').value;
    const availableStatus = document.getElementById('availableStatus').value;
    const forceProxy = document.getElementById('forceProxy').value;
    const tenantIdRaw = selectedTenantId || (document.getElementById('tenantId') && document.getElementById('tenantId').value) || '';

    if (!proxyType || !proxyHost || !proxyPort) {
        Swal.fire({ title: 'error', text: i18n.common_plzInputGlobalRequired, icon: 'warning', confirmButtonColor: '#ff9800' });
        return;
    }

    if (proxyPort < 1 || proxyPort > 65535) {
        Swal.fire({ title: 'error', text: i18n.common_portRange, icon: 'warning', confirmButtonColor: '#ff9800' });
        return;
    }

    const requestData = {
        id: proxyId ? parseInt(proxyId) : null,
        proxyType: proxyType,
        proxyHost: proxyHost,
        proxyPort: parseInt(proxyPort),
        proxyUsername: proxyUsername || null,
        proxyPassword: proxyPassword || null,
        availableStatus: parseInt(availableStatus),
        forceProxy: parseInt(forceProxy) === 1 ? 1 : 0,
        tenantId: tenantIdRaw ? parseInt(tenantIdRaw) : null
    };
    fetch('/vpnProxy/saveOrUpdate', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrfHeaderName]: csrfToken
        },
        body: JSON.stringify(requestData)
    })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                closeProxyModal();
                loadProxyList(1);
            } else {
                throw new Error(data.message || 'error');
            }
        })
        .catch(error => {
            Swal.fire({ title: 'error', text: error.message, icon: 'error', confirmButtonColor: '#ff6b6b' });
        });
}

function handleDelete(id) {
    Swal.fire({
        title: i18n.vpn_isDelete,
        //text: '此操作不可恢复。',
        icon: 'warning',
        showCancelButton: true,
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel,
        reverseButtons: true,
        confirmButtonColor: '#ff6b6b',
        cancelButtonColor: '#6c757d'
    }).then(result => {
        if (result.isConfirmed) {

            const requestData = { id: id };

            fetch('/vpnProxy/delete', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify(requestData)
            })
                .then(response => response.json())
                .then(data => {
                    if (data.success) {
                        loadProxyList(1)
                    } else {
                        throw new Error(data.message || 'error');
                    }
                })
                .catch(error => {
                    Swal.fire({ title: 'error', text: error.message, icon: 'error', confirmButtonColor: '#ff6b6b' });
                });
        }
    });
}

function togglePassword(element) {
    const password = element.getAttribute('data-password');
    if (element.textContent === '********') {
        element.textContent = password;
        element.style.userSelect = 'text';
    } else {
        element.textContent = '********';
        element.style.userSelect = 'none';
    }
}

function formatTenantLabel(record) {
    if (record.tenantId == null || record.tenantId === '') {
        return '<span style="color: var(--text-secondary);">' + (i18n.vpn_tenant_global || '全局共享') + '</span>';
    }
    var name = record.tenantName || ('#' + record.tenantId);
    return '<span style="color: #28a745;">' + escapeHtml(name) + '</span>';
}

function escapeHtml(str) {
    if (str == null) return '';
    return String(str)
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#39;');
}

function renderTableView(data) {
    const tbody = document.getElementById('tableBody');
    proxyListCache = {};
    if (!data || data.length === 0) {
        tbody.innerHTML = '<tr><td colspan="9" style="text-align: center; padding: 30px;">'
            + '<i class="fas fa-inbox" style="font-size: 24px; color: var(--text-secondary); margin-right: 10px;"></i>'
            + '<span style="color: var(--text-secondary);">'+i18n.common_noData+'</span></td></tr>';
        return;
    }

    let html = '';
    for (let i = 0; i < data.length; i++) {
        const record = data[i];
        proxyListCache[record.id] = record;
        const statusHtml = buildStatusHtml(record.id, record.availableStatus);
        const forceHtml = buildForceHtml(record.forceProxy);

        const username = record.proxyUsername || '-';
        const password = record.proxyPassword || '';
        const tenantLabel = formatTenantLabel(record);

        html += '<tr data-proxy-id="' + record.id + '">';
        html += '<td>' + record.proxyType + '</td>';
        html += '<td><span class="truncate" title="' + escapeHtml(record.proxyHost) + '">' + escapeHtml(record.proxyHost) + '</span></td>';
        html += '<td>' + record.proxyPort + '</td>';
        html += '<td><span class="truncate" title="' + escapeHtml(username) + '">' + escapeHtml(username) + '</span></td>';
        html += '<td><span class="password-field" data-password="' + escapeHtml(password) + '" onclick="togglePassword(this)">********</span></td>';
        html += '<td>' + tenantLabel + '</td>';
        html += '<td class="proxy-force-cell">' + forceHtml + '</td>';
        html += '<td class="proxy-status-cell" data-proxy-id="' + record.id + '">' + statusHtml + '</td>';
        html += '<td>';
        html += '  <div class="dropdown">';
        html += '    <button class="btn btn-primary btn-icon dropdown-toggle" onclick="handleDynamicToggle(this, event)">';
        html += '      <i class="fas fa-ellipsis-h"></i>';
        html += '    </button>';
        html += '    <div class="dropdown-panel">';
        html += '      <button class="dropdown-item" onclick="handleTestConnection(' + record.id + ')">';
        html += '        <i class="fas fa-plug"></i><span>' + (i18n.vpn_test || '测试') + '</span>';
        html += '      </button>';
        html += '      <button class="dropdown-item" onclick="toggleForceProxy(' + record.id + ')">';
        html += '        <i class="fas fa-shield-alt"></i><span>' + (i18n.vpn_force || '强制代理') + '</span>';
        html += '      </button>';
        html += '      <button class="dropdown-item" onclick="openEditModalFromRecord(' + record.id + ')">';
        html += '        <i class="fas fa-edit"></i><span>' + i18n.vpn_edit + '</span>';
        html += '      </button>';
        html += '      <button class="dropdown-item" onclick="handleDelete(' + record.id + ')">';
        html += '        <i class="fas fa-trash"></i><span>' + i18n.common_delete + '</span>';
        html += '      </button>';
        html += '    </div>';
        html += '  </div>';
        html += '</td>';
        html += '</tr>';
    }
    tbody.innerHTML = html;
}

/** 强制代理护盾：橙=强制，绿=非强制 */
function buildForceHtml(forceProxy) {
    var forced = forceProxy === 1 || forceProxy === true || forceProxy === '1';
    if (forced) {
        return '<span class="proxy-force-badge is-force" title="' + escapeHtml(i18n.vpn_force_on || '强制') + '">'
            + '<i class="fas fa-shield-alt"></i> '
            + escapeHtml(i18n.vpn_force_on || '强制')
            + '</span>';
    }
    return '<span class="proxy-force-badge is-optional" title="' + escapeHtml(i18n.vpn_force_off || '非强制') + '">'
        + '<i class="fas fa-shield-alt"></i> '
        + escapeHtml(i18n.vpn_force_off || '非强制')
        + '</span>';
}

/** 操作菜单：切换强制代理 */
function toggleForceProxy(id) {
    var record = proxyListCache[id];
    if (!record) {
        return;
    }
    var next = (record.forceProxy === 1 || record.forceProxy === true || record.forceProxy === '1') ? 0 : 1;
    var requestData = {
        id: record.id,
        proxyType: record.proxyType,
        proxyHost: record.proxyHost,
        proxyPort: record.proxyPort,
        proxyUsername: record.proxyUsername || null,
        proxyPassword: record.proxyPassword || null,
        availableStatus: record.availableStatus != null ? record.availableStatus : 1,
        forceProxy: next,
        tenantId: record.tenantId != null ? record.tenantId : null
    };
    fetch('/vpnProxy/saveOrUpdate', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrfHeaderName]: csrfToken
        },
        body: JSON.stringify(requestData)
    })
        .then(function(response) { return response.json(); })
        .then(function(data) {
            if (!data.success) {
                throw new Error(data.message || 'error');
            }
            record.forceProxy = next;
            loadProxyList(currentPage);
        })
        .catch(function(error) {
            Swal.fire({ title: 'error', text: error.message, icon: 'error', confirmButtonColor: '#ff6b6b' });
        });
}

function buildStatusHtml(id, availableStatus) {
    if (testingProxyIds[id]) {
        return '<span class="status-badge status-pending">'
            + '<i class="fas fa-spinner fa-spin"></i> '
            + (i18n.vpn_testing || '测试中…')
            + '</span>';
    }
    if (availableStatus === 1) {
        return '<span class="status-badge status-running"><i class="fas fa-check-circle"></i> '
            + (i18n.vpn_test_ok || i18n.common_available || '通畅') + '</span>';
    }
    return '<span class="status-badge status-offline"><i class="fas fa-times-circle"></i> '
        + (i18n.vpn_test_fail || i18n.common_noAvailable || '不通') + '</span>';
}

function updateRowStatus(id, availableStatus, testing) {
    if (testing) {
        testingProxyIds[id] = true;
    } else {
        delete testingProxyIds[id];
        if (proxyListCache[id]) {
            proxyListCache[id].availableStatus = availableStatus;
        }
    }
    var cell = document.querySelector('.proxy-status-cell[data-proxy-id="' + id + '"]');
    if (!cell) return;
    if (testing) {
        cell.innerHTML = '<span class="status-badge status-pending">'
            + '<i class="fas fa-spinner fa-spin"></i> '
            + (i18n.vpn_testing || '测试中…')
            + '</span>';
        return;
    }
    cell.innerHTML = buildStatusHtml(id, availableStatus);
}

function handleTestConnection(id) {
    if (!id || testingProxyIds[id] || isTestingAll) {
        return;
    }
    updateRowStatus(id, null, true);
    fetch('/vpnProxy/testConnection', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrfHeaderName]: csrfToken
        },
        body: JSON.stringify({ id: id })
    })
        .then(function(response) { return response.json(); })
        .then(function(data) {
            if (!data.success) {
                throw new Error(data.message || '测试失败');
            }
            var payload = data.data || {};
            var connected = !!payload.connected;
            var status = payload.availableStatus != null
                ? payload.availableStatus
                : (connected ? 1 : 0);
            updateRowStatus(id, status, false);
        })
        .catch(function(error) {
            delete testingProxyIds[id];
            var cached = proxyListCache[id];
            updateRowStatus(id, cached ? cached.availableStatus : 0, false);
            Swal.fire({
                title: 'error',
                text: error.message || (i18n.common_network_error || '网络错误'),
                icon: 'error',
                confirmButtonColor: '#ff6b6b'
            });
        });
}

/**
 * 一键全部测试：先拉全量 id，再逐条探测（实时更新当前页状态，结果落库）
 */
function handleTestAll() {
    if (isTestingAll) {
        return;
    }
    isTestingAll = true;
    var btn = document.getElementById('btnTestAll');
    if (btn) {
        btn.disabled = true;
        btn.classList.add('disabled');
    }

    // 当前页先显示测试中
    Object.keys(proxyListCache).forEach(function(id) {
        updateRowStatus(id, null, true);
    });

    fetch('/vpnProxy/pageList', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrfHeaderName]: csrfToken
        },
        body: JSON.stringify({ pageNum: 1, pageSize: 1000 })
    })
        .then(function(response) { return response.json(); })
        .then(function(data) {
            if (!data.success) {
                throw new Error(data.message || '加载代理列表失败');
            }
            var list = (data.data && data.data.content) ? data.data.content : [];
            if (!list.length) {
                throw new Error(i18n.common_noData || '暂无数据');
            }
            var ok = 0;
            var fail = 0;
            // 逐条串行，保证实时刷新且避免单请求过长
            return list.reduce(function(chain, item) {
                return chain.then(function() {
                    var id = item.id;
                    if (proxyListCache[id]) {
                        updateRowStatus(id, null, true);
                    }
                    return fetch('/vpnProxy/testConnection', {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                            [csrfHeaderName]: csrfToken
                        },
                        body: JSON.stringify({ id: id })
                    })
                        .then(function(resp) { return resp.json(); })
                        .then(function(res) {
                            if (!res.success) {
                                fail++;
                                if (proxyListCache[id]) {
                                    updateRowStatus(id, 0, false);
                                }
                                return;
                            }
                            var payload = res.data || {};
                            var connected = !!payload.connected;
                            var status = payload.availableStatus != null
                                ? payload.availableStatus
                                : (connected ? 1 : 0);
                            if (connected) {
                                ok++;
                            } else {
                                fail++;
                            }
                            if (proxyListCache[id]) {
                                updateRowStatus(id, status, false);
                            }
                        })
                        .catch(function() {
                            fail++;
                            if (proxyListCache[id]) {
                                updateRowStatus(id, 0, false);
                            }
                        });
                });
            }, Promise.resolve()).then(function() {
                return { total: list.length, ok: ok, fail: fail };
            });
        })
        .then(function(summary) {
            testingProxyIds = {};
            var tpl = i18n.vpn_testAll_done || '全部测试完成：共 {0} 条，通 {1}，不通 {2}';
            var msg = tpl
                .replace('{0}', String(summary.total))
                .replace('{1}', String(summary.ok))
                .replace('{2}', String(summary.fail));
            loadProxyList(currentPage);
            Swal.fire({
                title: i18n.vpn_testAll || '一键全部测试',
                text: msg,
                icon: 'success',
                confirmButtonColor: '#28a745'
            });
        })
        .catch(function(error) {
            testingProxyIds = {};
            loadProxyList(currentPage);
            Swal.fire({
                title: 'error',
                text: error.message || (i18n.common_network_error || '网络错误'),
                icon: 'error',
                confirmButtonColor: '#ff6b6b'
            });
        })
        .finally(function() {
            isTestingAll = false;
            if (btn) {
                btn.disabled = false;
                btn.classList.remove('disabled');
            }
        });
}

// 暴露到全局，保证内联 onclick 可用
window.changeTenantPage = changeTenantPage;
window.selectTenant = selectTenant;
window.onTenantSearchInput = onTenantSearchInput;
window.renderTenantPicker = renderTenantPicker;
window.handleTestConnection = handleTestConnection;
window.handleTestAll = handleTestAll;
window.toggleForceProxy = toggleForceProxy;
