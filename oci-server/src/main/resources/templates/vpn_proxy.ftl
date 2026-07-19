<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <title>VPS管理系统 - VPN代理列表</title>
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>(function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/common/fa-fix.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <link rel="stylesheet" href="/css/app/vpn_proxy.css?v=${.now?string('yyyyMMddHHmmss')}">
    <link rel="stylesheet" href="/css/common/dropdown-menu.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/common/custom-select.css">
</head>
<body>
<!-- 引入顶部导航栏 -->
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <!-- 引入侧边栏 -->
    <#--<#include "common/sidebar.ftl" />-->

    <main class="main-content">
        <div class="page-card">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-network-wired"></i>
                <span>${msg.get("vpn.table")}</span>
            </h1>
            <div class="view-actions">
                <div class="view-toggle">
                    <button class="btn active" data-view="table" title="${msg.get("vpn.table.view")}">
                        <i class="fas fa-list"></i>
                    </button>
                    <button class="btn" data-view="grid" title="${msg.get("vpn.table.card")}">
                        <i class="fas fa-th-large"></i>
                    </button>
                </div>
                <div class="btn-group">
                    <button class="btn btn-secondary" id="btnTestAll" onclick="handleTestAll()">
                        <i class="fas fa-network-wired"></i>
                        <span>${msg.get("vpn.testAll")}</span>
                    </button>
                    <button class="btn btn-primary" onclick="openAddModal()">
                        <i class="fas fa-plus"></i>
                        <span>${msg.get("vpn.save")}</span>
                    </button>
                </div>
            </div>
        </div>

        <div class="table-view">
            <table class="table">
                <thead>
                <tr>
                    <th>${msg.get("vpn.type")}</th>
                    <th>${msg.get("vpn.url")}</th>
                    <th>${msg.get("vpn.port")}</th>
                    <th>${msg.get("vpn.name")}</th>
                    <th>${msg.get("vpn.pass")}</th>
                    <th>${msg.get("vpn.tenant")}</th>
                    <th>${msg.get("vpn.force")}</th>
                    <th>${msg.get("vpn.connStatus")}</th>
                    <th>${msg.get("vpn.action")}</th>
                </tr>
                </thead>
                <tbody id="tableBody">
                <tr>
                    <td colspan="9" style="text-align: center; padding: 30px;">
                        <i class="fas fa-spinner fa-spin" style="font-size: 24px; color: var(--accent-blue); margin-right: 10px;"></i>
                        <span style="color: var(--text-secondary);">${msg.get("common.loading")}</span>
                    </td>
                </tr>
                </tbody>
            </table>
        </div>

        <div class="grid-view" id="gridView"></div>

        <div class="pagination" id="pagination"></div>
        </div><!-- /.page-card -->
    </main>
</div>

<!-- 新增/编辑模态框：左配置 / 右绑定租户 -->
<div id="proxyModal" class="modal-overlay">
    <div class="modal-container modal-container-wide">
        <div class="modal-header">
            <h2 class="modal-title" id="modalTitle">${msg.get("vpn.save")}</h2>
            <button type="button" class="close-btn" onclick="closeProxyModal()" aria-label="close">
                <i class="fas fa-times"></i>
            </button>
        </div>
        <form id="proxyForm" class="proxy-form" onsubmit="handleSaveProxy(event)">
            <input type="hidden" id="proxyId" name="id">
            <input type="hidden" id="tenantId" name="tenantId" value="">

            <div class="proxy-modal-split">
                <!-- 左侧：代理参数 -->
                <section class="proxy-pane proxy-pane-left">
                    <div class="pane-head">
                        <div class="pane-title">
                            <i class="fas fa-server"></i>
                            <span>${msg.get("vpn.pane.proxy")}</span>
                        </div>
                        <p class="pane-desc">${msg.get("vpn.pane.proxy.desc")}</p>
                    </div>

                    <div class="form-group">
                        <label for="proxyType">${msg.get("vpn.type")}</label>
                        <select id="proxyType" name="proxyType" class="form-input" required
                                data-custom-select data-placeholder="${msg.get('vpn.selectType')}">
                            <option value="">${msg.get("vpn.selectType")}</option>
                            <option value="HTTP">HTTP</option>
                            <option value="HTTPS">HTTPS</option>
                        </select>
                    </div>

                    <div class="form-row-2">
                        <div class="form-group">
                            <label for="proxyHost">${msg.get("vpn.url")}</label>
                            <input type="text" id="proxyHost" name="proxyHost" class="form-input" required
                                   placeholder="192.168.1.1 / 127.0.0.1">
                        </div>
                        <div class="form-group">
                            <label for="proxyPort">${msg.get("vpn.port")}</label>
                            <input type="number" id="proxyPort" name="proxyPort" class="form-input" required
                                   min="1" max="65535" placeholder="8080">
                        </div>
                    </div>

                    <div class="form-row-2">
                        <div class="form-group">
                            <label for="proxyUsername">${msg.get("vpn.name")}</label>
                            <input type="text" id="proxyUsername" name="proxyUsername" class="form-input"
                                   placeholder="${msg.get("vpn.noVerify")}">
                        </div>
                        <div class="form-group">
                            <label for="proxyPassword">${msg.get("vpn.pass")}</label>
                            <input type="text" id="proxyPassword" name="proxyPassword" class="form-input"
                                   placeholder="${msg.get("vpn.noVerify")}">
                        </div>
                    </div>

                    <div class="form-row-2">
                        <div class="form-group">
                            <label for="availableStatus">${msg.get("vpn.status")}</label>
                            <select id="availableStatus" name="availableStatus" class="form-input" required
                                    data-custom-select>
                                <option value="1">${msg.get("common.start")}</option>
                                <option value="0">${msg.get("common.stop")}</option>
                            </select>
                        </div>
                        <div class="form-group">
                            <label for="forceProxy">${msg.get("vpn.force")}</label>
                            <select id="forceProxy" name="forceProxy" class="form-input" required
                                    data-custom-select>
                                <option value="0">${msg.get("vpn.force.off")}</option>
                                <option value="1">${msg.get("vpn.force.on")}</option>
                            </select>
                            <div class="form-hint" style="margin-top:6px;font-size:12px;color:var(--text-secondary);">
                                ${msg.get("vpn.force.hint")}
                            </div>
                        </div>
                    </div>
                </section>

                <!-- 右侧：绑定租户 -->
                <section class="proxy-pane proxy-pane-right">
                    <div class="pane-head">
                        <div class="pane-title">
                            <i class="fas fa-link"></i>
                            <span>${msg.get("vpn.tenant")}</span>
                        </div>
                        <p class="pane-desc">${msg.get("vpn.tenant.hint")}</p>
                    </div>

                    <div class="tenant-selected-bar" id="tenantSelectedBar">
                        <i class="fas fa-shield-alt tenant-selected-icon"></i>
                        <div class="tenant-selected-text">
                            <span class="tenant-selected-label">${msg.get("vpn.tenant.current")}</span>
                            <span class="tenant-selected-value" id="tenantSelectedLabel">${msg.get("vpn.tenant.global")}</span>
                        </div>
                    </div>

                    <div class="tenant-search-wrap">
                        <i class="fas fa-search"></i>
                        <input type="text" id="tenantSearch" class="form-input tenant-search"
                               placeholder="${msg.get("vpn.tenant.search")}"
                               autocomplete="off" oninput="onTenantSearchInput()">
                    </div>

                    <div class="tenant-list" id="tenantList" role="listbox" aria-label="${msg.get("vpn.tenant")}">
                        <!-- JS 渲染：全局固定 + 分页租户 -->
                    </div>

                    <div class="tenant-pager" id="tenantPager">
                        <button type="button" class="tenant-pager-btn" id="tenantPagePrev" onclick="changeTenantPage(-1)" title="prev">
                            <i class="fas fa-chevron-left"></i>
                        </button>
                        <span class="tenant-pager-info" id="tenantPageInfo">1 / 1</span>
                        <button type="button" class="tenant-pager-btn" id="tenantPageNext" onclick="changeTenantPage(1)" title="next">
                            <i class="fas fa-chevron-right"></i>
                        </button>
                    </div>
                </section>
            </div>

            <div class="modal-actions">
                <button type="button" class="btn btn-secondary" onclick="closeProxyModal()">${msg.get("common.cancel")}</button>
                <button type="submit" class="btn btn-primary">
                    <i class="fas fa-save"></i>
                    <span>${msg.get("common.save")}</span>
                </button>
            </div>
        </form>
    </div>
</div>

<!-- 版本信息模块 -->
<#--<#include "common/version_info.ftl">-->
<script>
    window.I18N = {
        common_noData: "${msg.get('common.noData')?js_string}",
        common_available: "${msg.get('common.available')?js_string}",
        common_noAvailable: "${msg.get('common.noAvailable')?js_string}",
        vpn_port: "${msg.get('vpn.port')?js_string}",
        vpn_name: "${msg.get('vpn.name')?js_string}",
        vpn_pass: "${msg.get('vpn.pass')?js_string}",
        vpn_status: "${msg.get('vpn.status')?js_string}",
        common_plzInputGlobalRequired: "${msg.get('common.plzInputGlobalRequired')?js_string}",
        common_portRange: "${msg.get('common.portRange')?js_string}",
        common_saving: "${msg.get('common.saving')?js_string}",
        vpn_isDelete: "${msg.get('vpn.isDelete')?js_string}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        common_delete: "${msg.get('common.delete')?js_string}",
        common_network_error: "${msg.get('common.network.error')}",
        vpn_edit: "${msg.get('vpn.edit')?js_string}",
        vpn_save: "${msg.get('vpn.save')?js_string}",
        vpn_tenant: "${msg.get('vpn.tenant')?js_string}",
        vpn_tenant_global: "${msg.get('vpn.tenant.global')?js_string}",
        vpn_tenant_select: "${msg.get('vpn.tenant.select')?js_string}",
        vpn_tenant_search: "${msg.get('vpn.tenant.search')?js_string}",
        vpn_tenant_empty: "${msg.get('vpn.tenant.empty')?js_string}",
        vpn_tenant_page: "${msg.get('vpn.tenant.page')?js_string}",
        vpn_test: "${msg.get('vpn.test')?js_string}",
        vpn_testAll: "${msg.get('vpn.testAll')?js_string}",
        vpn_testing: "${msg.get('vpn.testing')?js_string}",
        vpn_test_ok: "${msg.get('vpn.test.ok')?js_string}",
        vpn_test_fail: "${msg.get('vpn.test.fail')?js_string}",
        vpn_testAll_done: "${msg.get('vpn.testAll.done')?js_string}",
        vpn_force: "${msg.get('vpn.force')?js_string}",
        vpn_force_on: "${msg.get('vpn.force.on')?js_string}",
        vpn_force_off: "${msg.get('vpn.force.off')?js_string}",
        vpn_force_hint: "${msg.get('vpn.force.hint')?js_string}"

    }
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/common/custom-select.js"></script>
<script src="/js/system/vpn_proxy.js?v=${.now?string('yyyyMMddHHmmss')}"></script>
<script src="/js/common/dropdown-menu.js"></script>
</body>
</html>