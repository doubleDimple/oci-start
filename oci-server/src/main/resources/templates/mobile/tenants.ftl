<#import "layout.ftl" as layout>
<@layout.page title="${msg.get('mob.tab.tenants')}" activePage="tenants">

<!-- 工具栏 -->
<div style="display:flex;align-items:center;gap:8px;margin-bottom:10px">
    <div class="mob-search-wrap" style="flex:1;margin-bottom:0">
        <i class="fas fa-search mob-search-icon"></i>
        <input class="mob-search-input" id="tenantSearch" type="text"
               placeholder="${msg.get('mob.tenant.search.placeholder')}" oninput="filterTenants(this.value)">
    </div>
    <button class="mob-btn mob-btn-outline mob-btn-sm" id="btnToggleName" onclick="toggleNameMask()"
            style="flex-shrink:0;padding:0 10px;height:36px">
        <i class="fas fa-eye-slash" id="iconToggleName"></i>
    </button>
    <button class="mob-btn mob-btn-outline mob-btn-sm" onclick="batchCheckAccounts()"
            style="flex-shrink:0;padding:0 10px;height:36px">
        <i class="fas fa-shield-alt"></i>
    </button>
</div>

<!-- 加载占位 -->
<div id="tenantsLoading" class="mob-loading">
    <div class="mob-spinner"></div>
    <p>${msg.get('mob.loading')}</p>
</div>

<!-- 租户列表容器 -->
<div id="tenantsList" style="display:none;"></div>

<!-- ══════════════════════ SSE 弹窗 ══════════════════════ -->
<div id="sseModal" class="mob-center-overlay" style="display:none" onclick="closeSseModal(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-height:80vh">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title" id="sseModalTitle">${msg.get('mob.processing')}</div>
            <button class="mob-sheet-close" id="sseModalClose" onclick="closeSseModal()" disabled>
                <i class="fas fa-times"></i>
            </button>
        </div>
        <div id="sseProgressWrap" style="display:none;padding:0 16px 8px">
            <div style="background:var(--mob-bg);border-radius:6px;overflow:hidden;height:8px">
                <div id="sseProgressBar" style="height:8px;width:0%;background:linear-gradient(90deg,#1abc9c,#16a085);border-radius:4px;transition:width .3s"></div>
            </div>
            <div id="sseProgressText" style="font-size:12px;color:var(--mob-text-muted);margin-top:4px;text-align:center">${msg.get('mob.tenant.preparing')}</div>
        </div>
        <div id="sseLog"
             style="height:280px;overflow-y:auto;padding:12px 16px;font-size:12px;font-family:monospace;line-height:1.6;background:var(--mob-bg);margin:0 12px 12px;border-radius:8px;color:var(--mob-text);flex-shrink:0">
        </div>
    </div>
</div>

<!-- ══════════════════════ 批量检测结果弹窗 ══════════════════════ -->
<div id="checkResultModal" class="mob-center-overlay" style="display:none" onclick="closeCheckResult(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title">${msg.get('mob.tenant.check.result')}</div>
            <button class="mob-sheet-close" onclick="closeCheckResult()"><i class="fas fa-times"></i></button>
        </div>
        <div id="checkResultBody" style="padding:16px"></div>
    </div>
</div>

<!-- ══════════════════════ 删除确认弹窗 ══════════════════════ -->
<div id="deleteConfirmModal" class="mob-center-overlay" style="display:none" onclick="closeDeleteConfirm(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-width:340px">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title" style="color:#f04747">
                <i class="fas fa-exclamation-triangle" style="margin-right:6px"></i>确认删除
            </div>
            <button class="mob-sheet-close" onclick="closeDeleteConfirm()"><i class="fas fa-times"></i></button>
        </div>
        <div style="padding:16px 16px 8px">
            <p style="color:var(--mob-text);font-size:14px;line-height:1.6">
                确认删除租户 <strong id="deleteTenantName" style="color:#f04747"></strong> 吗？<br>
                <span style="color:var(--mob-text-muted);font-size:12px">此操作不可恢复，将删除该租户所有配置。</span>
            </p>
        </div>
        <div style="padding:8px 16px 20px;display:flex;gap:10px">
            <button class="mob-btn mob-btn-outline" style="flex:1" onclick="closeDeleteConfirm()">取消</button>
            <button class="mob-btn" id="deleteConfirmBtn"
                    style="flex:1;background:#f04747;color:#fff;border:none"
                    onclick="executeDeleteTenant()">确认删除</button>
        </div>
    </div>
</div>

<!-- ══════════════════════ 账号更新确认弹窗 ══════════════════════ -->
<div id="updateConfirmModal" class="mob-center-overlay" style="display:none" onclick="closeUpdateConfirm(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-width:340px">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title">
                <i class="fas fa-sync-alt" style="color:#1abc9c;margin-right:6px"></i>确认更新
            </div>
            <button class="mob-sheet-close" onclick="closeUpdateConfirm()"><i class="fas fa-times"></i></button>
        </div>
        <div style="padding:16px 16px 8px">
            <p style="color:var(--mob-text);font-size:14px;line-height:1.7">
                确认同步更新租户<br>
                <strong id="updateConfirmName" style="color:#1abc9c"></strong><br>
                <span style="color:var(--mob-text-muted);font-size:12px">将拉取最新账号状态和区域信息。</span>
            </p>
        </div>
        <div style="padding:8px 16px 20px;display:flex;gap:10px">
            <button class="mob-btn mob-btn-outline" style="flex:1" onclick="closeUpdateConfirm()">取消</button>
            <button class="mob-btn" style="flex:1;background:#1abc9c;color:#fff;border:none" onclick="executeUpdateAccount()">确认更新</button>
        </div>
    </div>
</div>

<!-- ══════════════════════ 租户操作菜单 Center Dialog ══════════════════════ -->
<div id="tenantMenuOverlay" class="mob-center-overlay" style="display:none" onclick="closeTenantMenu(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="width:92vw;max-width:380px;padding:0">
        <!-- 标题栏 -->
        <div class="mob-sheet-header" style="padding:14px 16px 12px">
            <div style="flex:1;min-width:0">
                <div class="mob-tn-info-name" id="tmTenantName" style="font-size:15px;line-height:1.3">—</div>
            </div>
            <span id="tmAccountType" style="display:inline-flex;align-items:center;gap:4px;font-size:10px;font-weight:700;padding:3px 9px;border-radius:20px;white-space:nowrap;flex-shrink:0;letter-spacing:0.2px;margin-right:6px">
                <i class="fas fa-id-badge"></i><span id="tmAccountTypeText">—</span>
            </span>
            <button class="mob-sheet-close" onclick="closeTenantMenu()" style="flex-shrink:0">
                <i class="fas fa-times"></i>
            </button>
        </div>
        <!-- 信息格 -->
        <div style="padding:8px 12px 12px">
            <div style="display:grid;grid-template-columns:1fr 1fr;gap:7px">
                <div style="background:rgba(26,188,156,0.08);border-radius:10px;padding:9px 11px">
                    <div style="font-size:10px;color:var(--mob-text-muted);margin-bottom:3px;letter-spacing:0.4px">激活天数</div>
                    <div style="font-size:16px;font-weight:700;color:#1abc9c"><span id="tmActiveDays">—</span></div>
                </div>
                <div style="background:rgba(91,138,240,0.08);border-radius:10px;padding:9px 11px">
                    <div style="font-size:10px;color:var(--mob-text-muted);margin-bottom:3px;letter-spacing:0.4px">主区域</div>
                    <div style="font-size:12px;font-weight:600;color:var(--mob-text);overflow:hidden;text-overflow:ellipsis;white-space:nowrap"><span id="tmRegion">—</span></div>
                </div>
                <div style="background:rgba(67,181,129,0.08);border-radius:10px;padding:9px 11px">
                    <div style="font-size:10px;color:var(--mob-text-muted);margin-bottom:3px;letter-spacing:0.4px">账号花费</div>
                    <div style="font-size:16px;font-weight:700;color:#43b581"><span id="tmCost">—</span></div>
                </div>
                <div style="background:rgba(250,166,26,0.08);border-radius:10px;padding:9px 11px">
                    <div style="font-size:10px;color:var(--mob-text-muted);margin-bottom:3px;letter-spacing:0.4px">定义名</div>
                    <div style="font-size:12px;font-weight:600;color:var(--mob-text);overflow:hidden;text-overflow:ellipsis;white-space:nowrap"><span id="tmDefName">—</span></div>
                </div>
            </div>
        </div>
        <div class="mob-sheet-divider"></div>
        <!-- 功能操作网格 -->
        <div class="mob-tn-action-grid" style="padding:12px 12px 20px">
            <button class="mob-tn-action-btn" onclick="openRegionSub()">
                <div class="mob-tn-action-icon" style="background:rgba(91,138,240,0.15);color:#5b8af0">
                    <i class="fas fa-globe"></i>
                </div>
                <span>区域订阅</span>
            </button>
            <button class="mob-tn-action-btn" onclick="openUserMgr()">
                <div class="mob-tn-action-icon" style="background:rgba(26,188,156,0.15);color:#1abc9c">
                    <i class="fas fa-users"></i>
                </div>
                <span>用户管理</span>
            </button>
            <button class="mob-tn-action-btn" onclick="openTrafficQuery()">
                <div class="mob-tn-action-icon" style="background:rgba(250,166,26,0.15);color:#faa61a">
                    <i class="fas fa-chart-bar"></i>
                </div>
                <span>流量查询</span>
            </button>
            <button class="mob-tn-action-btn" onclick="openAuditLog()">
                <div class="mob-tn-action-icon" style="background:rgba(155,89,182,0.15);color:#9b59b6">
                    <i class="fas fa-clipboard-list"></i>
                </div>
                <span>审计日志</span>
            </button>
            <button class="mob-tn-action-btn" onclick="openCostPage()">
                <div class="mob-tn-action-icon" style="background:rgba(67,181,129,0.15);color:#43b581">
                    <i class="fas fa-dollar-sign"></i>
                </div>
                <span>账号花费</span>
            </button>
        </div>
    </div>
</div>

<!-- 区域订阅 / 用户管理 / 审计日志 已改为独立全页面，见 /m/region-sub、/m/user-mgr、/m/audit-log -->

<script>
var _tenantI18n = {
    empty:           "${msg.get('mob.tenant.empty')}",
    loadFail:        "${msg.get('mob.tenant.load.fail')}",
    regionsFail:     "${msg.get('mob.tenant.regions.load.fail')}",
    noRegions:       "${msg.get('mob.tenant.no.regions')}",
    regionCount:     "${msg.get('mob.tenant.region.count')}",
    instCount:       "${msg.get('mob.tenant.instance.count')}",
    boot:            "${msg.get('mob.tenant.boot')}",
    instances:       "${msg.get('mob.tenant.instances')}",
    updatePrefix:    "${msg.get('mob.tenant.update.prefix')}",
    batchCheck:      "${msg.get('mob.tenant.batch.check')}",
    updateOk:        "${msg.get('mob.tenant.update.success')}",
    updateFail:      "${msg.get('mob.tenant.update.fail')}",
    connErr:         "${msg.get('mob.tenant.connect.error')}",
    checkErr:        "${msg.get('mob.tenant.check.error')}",
    disconnect:      "${msg.get('mob.tenant.check.disconnect')}",
    complete:        "${msg.get('mob.tenant.check.complete')}",
    preparing:       "${msg.get('mob.tenant.preparing')}",
    checkDone:       "${msg.get('mob.tenant.check.done')}",
    checking:        "${msg.get('mob.tenant.checking')}",
    totalAccounts:   "${msg.get('mob.tenant.total.accounts')}",
    activeAccounts:  "${msg.get('mob.tenant.active.accounts')}",
    inactiveAccounts:"${msg.get('mob.tenant.inactive.accounts')}"
};
</script>
<#noparse>
<script>
var _allTenants  = [];
var _tenantMap   = {};     // id -> 租户对象，供菜单使用
var _nameMasked  = true;
var _sseSource   = null;
var _menuTenant  = null;
var _deleteTenantId = null;
var _menuIdFromUrl = new URLSearchParams(window.location.search).get('menuId');

/* 从子页面返回：用缓存数据立即弹窗，无需等待 API */
(function() {
    try {
        var raw = sessionStorage.getItem('mob_returnMenuData');
        if (!raw) return;
        sessionStorage.removeItem('mob_returnMenuData');
        var t = JSON.parse(raw);
        if (!t || !t.id) return;
        _menuTenant = t;
        document.getElementById('tmTenantName').textContent  = t.userName || '—';
        document.getElementById('tmActiveDays').textContent  = t.activeDays ? (t.activeDays + ' 天') : '—';
        document.getElementById('tmRegion').textContent      = t.region    || '—';
        document.getElementById('tmDefName').textContent     = t.defName   || '未设置';
        document.getElementById('tmCost').textContent        = t.accountCost ? ('$' + t.accountCost) : '—';
        document.getElementById('tmAccountTypeText').textContent = t.accountTypeName || '—';
        var typeEl = document.getElementById('tmAccountType');
        var typeName = t.accountTypeName || '';
        var color = '#72767d', bg = 'rgba(114,118,125,0.12)';
        if (/free/i.test(typeName))       { color = '#1abc9c'; bg = 'rgba(26,188,156,0.15)'; }
        else if (/pay|payg/i.test(typeName)) { color = '#5b8af0'; bg = 'rgba(91,138,240,0.15)'; }
        else if (/promo/i.test(typeName)) { color = '#9b59b6'; bg = 'rgba(155,89,182,0.15)'; }
        typeEl.style.color      = color;
        typeEl.style.background = bg;
        document.getElementById('tenantMenuOverlay').style.display = 'flex';
    } catch(e) {}
})();

/* ══════════════ 加载 & 渲染 ══════════════ */
async function loadTenants() {
    try {
        const res  = await fetch('/m/api/tenants');
        const json = await res.json();
        if (!json.success && json.code !== 200) throw new Error(json.message || _tenantI18n.loadFail);
        _allTenants = json.data || [];
        renderTenants(_allTenants);
        // URL 参数方式兜底（旧链接兼容）
        if (_menuIdFromUrl && _tenantMap[String(_menuIdFromUrl)]) {
            _menuIdFromUrl = null;
            openTenantMenu(String(_menuIdFromUrl));
        }
    } catch(e) {
        document.getElementById('tenantsLoading').innerHTML =
            '<p style="color:#f04747">' + _tenantI18n.loadFail + ' ' + e.message + '</p>';
    }
}

function filterTenants(kw) {
    var q = kw.trim().toLowerCase();
    renderTenants(q ? _allTenants.filter(function(t) {
        return (t.userName||'').toLowerCase().includes(q)
            || (t.region||'').toLowerCase().includes(q)
            || (t.tenancy||'').toLowerCase().includes(q);
    }) : _allTenants);
}

function maskName(name) {
    if (!name) return '';
    if (name.length <= 2) return '***';
    return name[0] + '***' + name[name.length - 1];
}

function renderTenants(tenants) {
    var loading = document.getElementById('tenantsLoading');
    var list    = document.getElementById('tenantsList');

    if (tenants.length === 0) {
        loading.innerHTML = '<i class="fas fa-building" style="font-size:48px;opacity:0.3;display:block;text-align:center;margin-bottom:12px"></i>'
            + '<p style="text-align:center;color:#72767d">' + _tenantI18n.empty + '</p>';
        loading.style.display = '';
        list.style.display = 'none';
        return;
    }

    loading.style.display = 'none';
    list.style.display    = 'block';

    // 构建 id -> 对象字典，避免在 onclick 属性里内联 JSON
    _tenantMap = {};
    tenants.forEach(function(t) { _tenantMap[t.id] = t; });

    list.innerHTML = tenants.map(function(t) {
        var rawName  = t.userName || '';
        var dispName = _nameMasked ? maskName(rawName) : escHtml(rawName);
        var region   = escHtml(t.region || '');
        return '<div class="mob-tn-swipe-wrap" id="wrap-' + t.id + '">'
            + '<div class="mob-card mob-tn-card" id="card-' + t.id + '">'
            + '<div class="mob-card-header" style="cursor:default">'
            + '<div style="display:flex;align-items:center;flex:1;min-width:0;cursor:pointer" onclick="toggleTenant(\'' + t.id + '\')">'
            + '<span class="mob-dot mob-dot-green" style="flex-shrink:0"></span>'
            + '<div style="flex:1;min-width:0;margin-left:8px">'
            + '<div class="mob-card-title tenant-name-cell" data-raw="' + escHtml(rawName) + '" style="overflow:hidden;text-overflow:ellipsis;white-space:nowrap">'
            + dispName + '</div>'
            + '<div class="mob-card-subtitle">' + region + ' · ' + t.regionCount + _tenantI18n.regionCount + '</div>'
            + '</div>'
            + '<i class="fas fa-chevron-down mob-expand-icon mob-card-arrow" id="arrow-' + t.id + '" style="margin-left:6px;flex-shrink:0"></i>'
            + '</div>'
            + '<button class="mob-btn mob-btn-outline mob-btn-sm" style="flex-shrink:0;margin-left:6px;padding:0 10px;height:32px"'
            + ' onclick="updateTenantAccount(\'' + t.id + '\',\'' + escHtml(rawName) + '\')">'
            + '<i class="fas fa-sync-alt"></i></button>'
            + '<button class="mob-btn mob-btn-outline mob-btn-sm" style="flex-shrink:0;margin-left:4px;padding:0 10px;height:32px"'
            + ' onclick="openTenantMenu(\'' + t.id + '\')">'
            + '<i class="fas fa-ellipsis-h"></i></button>'
            + '</div>'
            + '<div class="mob-tenant-expand" id="expand-' + t.id + '">'
            + '<div class="mob-loading" id="region-loading-' + t.id + '"><div class="mob-spinner"></div></div>'
            + '<div id="region-list-' + t.id + '"></div>'
            + '</div>'
            + '</div>'
            // ── 左滑删除按钮 ──
            + '<button class="mob-tn-swipe-del" onclick="event.stopPropagation();confirmDeleteTenant(\'' + t.id + '\',\'' + escHtml(rawName) + '\')">'
            + '<i class="fas fa-trash-alt"></i><span>删除</span>'
            + '</button>'
            + '</div>';
    }).join('');

    // 初始化左滑
    document.querySelectorAll('.mob-tn-card').forEach(function(card) {
        initCardSwipe(card);
    });
}

/* ══════════════ 名称隐藏切换 ══════════════ */
function toggleNameMask() {
    _nameMasked = !_nameMasked;
    var icon = document.getElementById('iconToggleName');
    icon.className = _nameMasked ? 'fas fa-eye-slash' : 'fas fa-eye';
    document.querySelectorAll('.tenant-name-cell').forEach(function(el) {
        var raw = el.dataset.raw || '';
        el.textContent = _nameMasked ? maskName(raw) : raw;
    });
}

/* ══════════════ 展开区域 ══════════════ */
async function toggleTenant(tenantId) {
    var expand = document.getElementById('expand-' + tenantId);
    var arrow  = document.getElementById('arrow-' + tenantId);
    var isOpen = expand.classList.contains('active');

    if (isOpen) {
        expand.classList.remove('active');
        arrow.classList.remove('rotated');
        return;
    }
    expand.classList.add('active');
    arrow.classList.add('rotated');

    var regionList = document.getElementById('region-list-' + tenantId);
    if (regionList.dataset.loaded) return;

    try {
        var res  = await fetch('/m/api/tenants/' + tenantId + '/regions');
        var json = await res.json();
        renderRegions(tenantId, json.data || []);
        regionList.dataset.loaded = '1';
    } catch(e) {
        document.getElementById('region-loading-' + tenantId).innerHTML =
            '<p style="color:#f04747;font-size:13px">' + _tenantI18n.regionsFail + '</p>';
    }
}

function renderRegions(tenantId, regions) {
    var loadingEl = document.getElementById('region-loading-' + tenantId);
    var listEl    = document.getElementById('region-list-' + tenantId);
    loadingEl.style.display = 'none';

    if (regions.length === 0) {
        listEl.innerHTML = '<p class="mob-card-subtitle" style="padding:8px 0">' + _tenantI18n.noRegions + '</p>';
        return;
    }
    listEl.innerHTML = regions.map(function(r) {
        var dotClass   = r.instanceCount > 0 ? 'mob-dot-green' : 'mob-dot-gray';
        var badgeClass = r.instanceCount > 0 ? 'mob-badge-green' : 'mob-badge-gray';
        var regionName = escHtml(r.region);
        return '<div class="mob-region-item">'
            + '<div class="mob-region-header">'
            + '<span class="mob-dot ' + dotClass + '"></span>'
            + '<span class="mob-region-name">' + regionName + '</span>'
            + '<span class="mob-badge ' + badgeClass + '">' + r.instanceCount + _tenantI18n.instCount + '</span>'
            + '</div>'
            + '<div class="mob-region-actions" style="flex-wrap:nowrap;gap:5px">'
            + '<button class="mob-btn mob-btn-sm" style="flex:1;min-width:0;background:#5b8af0;color:#fff;border:none;padding:7px 4px" onclick="showQuickBoot(\'' + r.id + '\', \'' + regionName + '\')">'
            + '<i class="fas fa-bolt"></i> ' + _tenantI18n.boot + '</button>'
            + '<button class="mob-btn mob-btn-sm" style="flex:1;min-width:0;background:rgba(67,181,129,0.15);color:#43b581;border:1px solid rgba(67,181,129,0.35);padding:7px 4px" onclick="showRegionInstances(\'' + r.id + '\', \'' + regionName + '\')">'
            + '<i class="fas fa-server"></i> ' + _tenantI18n.instances + '</button>'
            + '<button class="mob-btn mob-btn-sm" style="flex:1;min-width:0;background:rgba(26,188,156,0.12);color:#1abc9c;border:1px solid rgba(26,188,156,0.35);padding:7px 4px" onclick="openDiskInfo(\'' + r.id + '\', \'' + regionName + '\')">'
            + '<i class="fas fa-hdd"></i> 硬盘</button>'
            + '<button class="mob-btn mob-btn-sm" style="flex:1;min-width:0;background:rgba(240,71,71,0.1);color:#f04747;border:1px solid rgba(240,71,71,0.3);padding:7px 4px" onclick="openSecurityRules(\'' + r.id + '\', \'' + regionName + '\')">'
            + '<i class="fas fa-shield-alt"></i> 规则</button>'
            + '<button class="mob-btn mob-btn-sm" style="flex:1;min-width:0;background:rgba(155,89,182,0.12);color:#9b59b6;border:1px solid rgba(155,89,182,0.35);padding:7px 4px" onclick="openStorageInstances(\'' + r.id + '\', \'' + regionName + '\')">'
            + '<i class="fas fa-database"></i> 存储</button>'
            + '</div>'
            + '</div>';
    }).join('');
}

/* ══════════════ 左滑删除 ══════════════ */
var _SWIPE_THRESHOLD = 40;
var _SWIPE_WIDTH     = 80;

function initCardSwipe(card) {
    var startX, startY, isDragging = false, isOpen = false;

    card.addEventListener('touchstart', function(e) {
        startX = e.touches[0].clientX;
        startY = e.touches[0].clientY;
        isDragging = false;
        card.style.transition = 'none';
    }, { passive: true });

    card.addEventListener('touchmove', function(e) {
        var dx = e.touches[0].clientX - startX;
        var dy = e.touches[0].clientY - startY;
        if (!isDragging && Math.abs(dy) > Math.abs(dx)) return;
        if (Math.abs(dx) > 5) isDragging = true;
        if (!isDragging) return;
        var base  = isOpen ? -_SWIPE_WIDTH : 0;
        var moved = Math.max(-_SWIPE_WIDTH, Math.min(0, base + dx));
        card.style.transform = 'translateX(' + moved + 'px)';
    }, { passive: true });

    card.addEventListener('touchend', function(e) {
        if (!isDragging) return;
        card.style.transition = '';
        var dx  = e.changedTouches[0].clientX - startX;
        var base = isOpen ? -_SWIPE_WIDTH : 0;
        var net  = base + dx;
        if (net < -_SWIPE_THRESHOLD) {
            closeAllCardSwipes(card);
            card.style.transform = 'translateX(-' + _SWIPE_WIDTH + 'px)';
            isOpen = true;
        } else {
            card.style.transform = 'translateX(0)';
            isOpen = false;
        }
    }, { passive: true });

    card._swipeClose = function() {
        card.style.transition = '';
        card.style.transform  = 'translateX(0)';
        isOpen = false;
    };
}

function closeAllCardSwipes(except) {
    document.querySelectorAll('.mob-tn-card').forEach(function(c) {
        if (c !== except && c._swipeClose) c._swipeClose();
    });
}

document.addEventListener('touchstart', function(e) {
    if (!e.target.closest('.mob-tn-swipe-wrap')) closeAllCardSwipes(null);
}, { passive: true });

/* ══════════════ 删除租户 ══════════════ */
function confirmDeleteTenant(id, name) {
    _deleteTenantId = id;
    document.getElementById('deleteTenantName').textContent = name;
    document.getElementById('deleteConfirmModal').style.display = 'flex';
    closeAllCardSwipes(null);
}

function closeDeleteConfirm(e) {
    if (e && e.target !== document.getElementById('deleteConfirmModal')) return;
    document.getElementById('deleteConfirmModal').style.display = 'none';
    _deleteTenantId = null;
}

async function executeDeleteTenant() {
    if (!_deleteTenantId) return;
    var btn = document.getElementById('deleteConfirmBtn');
    btn.disabled = true;
    btn.textContent = '删除中…';
    try {
        var res  = await fetch('/tenants/deleteApi?tenantId=' + encodeURIComponent(_deleteTenantId));
        var json = await res.json();
        document.getElementById('deleteConfirmModal').style.display = 'none';
        _deleteTenantId = null;
        if (json.success) {
            mobToast('删除成功', 'success');
            loadTenants();
        } else {
            mobToast(json.message || '删除失败', 'error');
        }
    } catch(e) {
        mobToast('删除异常: ' + e.message, 'error');
    }
    btn.disabled = false;
    btn.textContent = '确认删除';
}

/* ══════════════ 三点菜单 ══════════════ */
function openTenantMenu(id) {
    var t = _tenantMap[id];
    if (!t) return;
    _menuTenant = t;
    document.getElementById('tmTenantName').textContent   = t.userName || '—';
    document.getElementById('tmActiveDays').textContent   = t.activeDays ? (t.activeDays + ' 天') : '—';
    document.getElementById('tmRegion').textContent       = t.region    || '—';
    document.getElementById('tmDefName').textContent      = t.defName   || '未设置';
    document.getElementById('tmCost').textContent         = t.accountCost ? ('$' + t.accountCost) : '—';

    // 账号类型 badge
    var typeName = t.accountTypeName || '—';
    document.getElementById('tmAccountTypeText').textContent = typeName;
    var typeEl = document.getElementById('tmAccountType');
    var color = '#72767d', bg = 'rgba(114,118,125,0.12)';
    if (/free/i.test(typeName))  { color = '#1abc9c'; bg = 'rgba(26,188,156,0.15)'; }
    else if (/pay|payg/i.test(typeName)) { color = '#5b8af0'; bg = 'rgba(91,138,240,0.15)'; }
    else if (/promo/i.test(typeName))    { color = '#9b59b6'; bg = 'rgba(155,89,182,0.15)'; }
    typeEl.style.color      = color;
    typeEl.style.background = bg;

    document.getElementById('tenantMenuOverlay').style.display = 'flex';
}

function closeTenantMenu(e) {
    if (e && e.target !== document.getElementById('tenantMenuOverlay')) return;
    document.getElementById('tenantMenuOverlay').style.display = 'none';
}

/* ── 新功能跳转 ── */
function openDiskInfo(tenantId, tenantName) {
    window.location.href = '/m/disk-info?tenantId=' + encodeURIComponent(tenantId)
        + '&tenantName=' + encodeURIComponent(tenantName || '');
}
function openSecurityRules(tenantId, tenantName) {
    window.location.href = '/m/security-rules?tenantId=' + encodeURIComponent(tenantId)
        + '&tenantName=' + encodeURIComponent(tenantName || '');
}
function openStorageInstances(tenantId, tenantName) {
    window.location.href = '/m/storage-instances?tenantId=' + encodeURIComponent(tenantId)
        + '&tenantName=' + encodeURIComponent(tenantName || '');
}

function _saveReturnMenu() {
    if (_menuTenant && _menuTenant.id) {
        sessionStorage.setItem('mob_returnMenuData', JSON.stringify(_menuTenant));
    }
}

/* ── 区域订阅（新页面） ── */
function openRegionSub() {
    _saveReturnMenu(); closeTenantMenu();
    window.location.href = '/m/region-sub?tenantId=' + encodeURIComponent(_menuTenant.id)
        + '&tenantName=' + encodeURIComponent(_menuTenant.userName || '');
}

/* ── 用户管理（新页面） ── */
function openUserMgr() {
    _saveReturnMenu(); closeTenantMenu();
    window.location.href = '/m/user-mgr?tenantId=' + encodeURIComponent(_menuTenant.id)
        + '&tenantName=' + encodeURIComponent(_menuTenant.userName || '');
}

/* ── 流量查询（跳转新页面） ── */
function openTrafficQuery() {
    _saveReturnMenu(); closeTenantMenu();
    window.location.href = '/m/traffic?tenantId=' + encodeURIComponent(_menuTenant.id);
}

/* ── 审计日志（新页面） ── */
function openAuditLog() {
    _saveReturnMenu(); closeTenantMenu();
    window.location.href = '/m/audit-log?tenantId=' + encodeURIComponent(_menuTenant.id)
        + '&tenantName=' + encodeURIComponent(_menuTenant.userName || '');
}

/* ── 账号花费（跳转新页面） ── */
function openCostPage() {
    _saveReturnMenu(); closeTenantMenu();
    window.location.href = '/m/cost?tenantId=' + encodeURIComponent(_menuTenant.id);
}

/* ══════════════ SSE 弹窗公共工具 ══════════════ */
function openSseModal(title, showProgress) {
    document.getElementById('sseModalTitle').textContent = title;
    document.getElementById('sseLog').innerHTML = '';
    document.getElementById('sseModalClose').disabled = true;
    document.getElementById('sseProgressWrap').style.display = showProgress ? '' : 'none';
    if (showProgress) {
        document.getElementById('sseProgressBar').style.width = '0%';
        document.getElementById('sseProgressText').textContent = _tenantI18n.preparing;
    }
    document.getElementById('sseModal').style.display = 'flex';
}

function sseLog(msg) {
    var el = document.getElementById('sseLog');
    el.innerHTML += '<span>▶ ' + escHtml(String(msg)) + '</span><br>';
    el.scrollTop = el.scrollHeight;
}

function sseFinish() {
    if (_sseSource) { _sseSource.close(); _sseSource = null; }
    document.getElementById('sseModalClose').disabled = false;
    document.getElementById('sseModalTitle').textContent += _tenantI18n.complete;
}

function closeSseModal(e) {
    if (e && e.target !== document.getElementById('sseModal')) return;
    if (document.getElementById('sseModalClose').disabled) return;
    if (_sseSource) { _sseSource.close(); _sseSource = null; }
    document.getElementById('sseModal').style.display = 'none';
}

/* ══════════════ 单租户账号更新（SSE） ══════════════ */
var _updateTenantId = null, _updateTenantName = null;

function updateTenantAccount(tenantId, name) {
    _updateTenantId   = tenantId;
    _updateTenantName = name;
    document.getElementById('updateConfirmName').textContent = name;
    document.getElementById('updateConfirmModal').style.display = 'flex';
}

function closeUpdateConfirm(e) {
    if (e && e.target !== document.getElementById('updateConfirmModal')) return;
    document.getElementById('updateConfirmModal').style.display = 'none';
    _updateTenantId = _updateTenantName = null;
}

function executeUpdateAccount() {
    if (!_updateTenantId) return;
    var tenantId = _updateTenantId, name = _updateTenantName;
    document.getElementById('updateConfirmModal').style.display = 'none';
    _updateTenantId = _updateTenantName = null;

    var csrf = (document.querySelector('meta[name="_csrf"]') || {}).content || '';
    openSseModal(_tenantI18n.updatePrefix + name, false);

    var url = '/tenants/updateTenant?tenantId=' + encodeURIComponent(tenantId)
            + (csrf ? '&_csrf=' + encodeURIComponent(csrf) : '');
    _sseSource = new EventSource(url);

    _sseSource.addEventListener('progress', function(e) { sseLog(e.data); });
    _sseSource.addEventListener('success',  function() {
        sseLog(_tenantI18n.updateOk);
        sseFinish();
        setTimeout(loadTenants, 600);
    });
    _sseSource.addEventListener('error',    function() { sseLog(_tenantI18n.updateFail); sseFinish(); });
    _sseSource.onerror = function() {
        if (_sseSource && _sseSource.readyState === EventSource.CLOSED) return;
        sseLog(_tenantI18n.connErr); sseFinish();
    };
}

/* ══════════════ 批量账号检测（SSE + 进度条） ══════════════ */
function batchCheckAccounts() {
    openSseModal(_tenantI18n.batchCheck, true);
    var total = 0, processed = 0;
    _sseSource = new EventSource('/tenants/checkAccountsStream');

    _sseSource.addEventListener('start', function(e) {
        try {
            var d = JSON.parse(e.data);
            total = d.total || 0;
            sseLog(d.message || e.data);
            document.getElementById('sseProgressText').textContent = d.message || _tenantI18n.preparing;
        } catch(_) { sseLog(e.data); }
    });
    _sseSource.addEventListener('progress', function(e) {
        processed++;
        sseLog(e.data);
        if (total > 0) {
            var pct = Math.min(100, Math.floor(processed / total * 100));
            document.getElementById('sseProgressBar').style.width = pct + '%';
            document.getElementById('sseProgressText').textContent =
                _tenantI18n.checking + ' ' + pct + '% (' + processed + '/' + total + ')';
        }
    });
    _sseSource.addEventListener('complete', function(e) {
        sseFinish();
        document.getElementById('sseProgressBar').style.width = '100%';
        document.getElementById('sseProgressText').textContent = _tenantI18n.checkDone;
        try { showCheckResult(JSON.parse(e.data)); } catch(_) {}
    });
    _sseSource.addEventListener('error', function(e) {
        sseLog(_tenantI18n.checkErr); sseFinish();
    });
    _sseSource.onerror = function() {
        if (_sseSource && _sseSource.readyState === EventSource.CLOSED) return;
        sseLog(_tenantI18n.disconnect); sseFinish();
    };
}

function showCheckResult(result) {
    var total  = result.totalAccounts    || 0;
    var active = result.activeAccounts   || 0;
    var fail   = result.inactiveAccounts || 0;
    var items  = [
        { label: _tenantI18n.totalAccounts,     value: total,  color: '#5b8af0' },
        { label: _tenantI18n.activeAccounts,    value: active, color: '#43b581' },
        { label: _tenantI18n.inactiveAccounts,  value: fail,   color: '#f04747' }
    ];
    document.getElementById('checkResultBody').innerHTML =
        '<div style="display:grid;grid-template-columns:repeat(3,1fr);gap:10px;text-align:center">'
        + items.map(function(it) {
            return '<div style="background:var(--mob-bg);border-radius:10px;padding:14px 8px">'
                + '<div style="font-size:28px;font-weight:700;color:' + it.color + '">' + it.value + '</div>'
                + '<div style="font-size:12px;color:var(--mob-text-muted);margin-top:4px">' + it.label + '</div>'
                + '</div>';
        }).join('')
        + '</div>';
    document.getElementById('sseModal').style.display        = 'none';
    document.getElementById('checkResultModal').style.display = 'flex';
}

function closeCheckResult(e) {
    if (e && e.target !== document.getElementById('checkResultModal')) return;
    document.getElementById('checkResultModal').style.display = 'none';
}

/* ══════════════ 工具 ══════════════ */
function escHtml(s) {
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

loadTenants();
</script>
</#noparse>

</@layout.page>
