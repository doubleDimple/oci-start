<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
    <title>VPS管理系统 - VPN代理列表</title>
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>(function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <link rel="stylesheet" href="/css/app/vpn_proxy.css">
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
                    <th>${msg.get("vpn.status")}</th>
                    <th>${msg.get("vpn.action")}</th>
                </tr>
                </thead>
                <tbody id="tableBody">
                <tr>
                    <td colspan="7" style="text-align: center; padding: 30px;">
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

<!-- 新增/编辑模态框 -->
<div id="proxyModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h2 class="modal-title" id="modalTitle">${msg.get("vpn.save")}</h2>
            <button class="close-btn" onclick="closeProxyModal()">
                <i class="fas fa-times"></i>
            </button>
        </div>
        <div class="modal-content">
            <form id="proxyForm" onsubmit="handleSaveProxy(event)">
                <input type="hidden" id="proxyId" name="id">

                <div class="form-group">
                    <label for="proxyType">${msg.get("vpn.type")}:</label>
                    <select id="proxyType" name="proxyType" class="form-input" required
                            data-custom-select data-placeholder="${msg.get('vpn.selectType')}">
                        <option value="">${msg.get("vpn.selectType")}</option>
                        <option value="HTTP">HTTP</option>
                        <option value="HTTPS">HTTPS</option>
                        <#--<option value="SOCKS5">SOCKS5</option>
                        <option value="SOCKS4">SOCKS4</option>-->
                    </select>
                </div>

                <div class="form-group">
                    <label for="proxyHost">${msg.get("vpn.url")}:</label>
                    <input type="text" id="proxyHost" name="proxyHost" class="form-input" required placeholder="For example:192.168.1.1">
                </div>

                <div class="form-group">
                    <label for="proxyPort">${msg.get("vpn.port")}:</label>
                    <input type="number" id="proxyPort" name="proxyPort" class="form-input" required min="1" max="65535" placeholder="For example: 8080">
                </div>

                <div class="form-group">
                    <label for="proxyUsername">${msg.get("vpn.name")}:</label>
                    <input type="text" id="proxyUsername" name="proxyUsername" class="form-input" placeholder="${msg.get("vpn.noVerify")}">
                </div>

                <div class="form-group">
                    <label for="proxyPassword">${msg.get("vpn.pass")}:</label>
                    <input type="text" id="proxyPassword" name="proxyPassword" class="form-input" placeholder="${msg.get("vpn.noVerify")}">
                </div>

                <div class="form-group">
                    <label for="availableStatus">${msg.get("vpn.status")}:</label>
                    <select id="availableStatus" name="availableStatus" class="form-input" required
                            data-custom-select>
                        <option value="1">${msg.get("common.start")}</option>
                        <option value="0">${msg.get("common.stop")}</option>
                    </select>
                </div>

                <div class="modal-actions">
                    <button type="submit" class="btn btn-primary">${msg.get("common.save")}</button>
                    <button type="button" class="btn btn-secondary" onclick="closeProxyModal()">${msg.get("common.cancel")}</button>
                </div>
            </form>
        </div>
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
        vpn_edit: "${msg.get('vpn.edit')?js_string}"

    }
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/common/custom-select.js"></script>
<script src="/js/system/vpn_proxy.js"></script>
<script src="/js/common/dropdown-menu.js"></script>
</body>
</html>