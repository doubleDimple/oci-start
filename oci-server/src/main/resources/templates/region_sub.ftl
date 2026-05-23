<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 区域订阅管理</title>
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="/css/all.min.css">

    <!-- SweetAlert2 CSS -->
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <!-- SweetAlert2 JS -->
    <script src="/js/sweetalert2.min.js"></script>

    <link rel="stylesheet" href="/css/app/region_sub.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <script src="/js/common/jquery.min.js"></script>

</head>
<body>
<!-- 引入顶部导航栏 -->
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
    <div class="page-card">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-globe"></i>
                <span>${msg.get("sub.region")} - ${tenant.userName}-${tenant.region}</span>
            </h1>
            <div class="view-actions">
                <div class="btn-group">
                    <button class="btn btn-success" onclick="refreshRegionSummary()">
                        <i class="fas fa-sync"></i>
                        <span>${msg.get("sub.refresh")}</span>
                    </button>
                    <button class="btn btn-primary" onclick="showAvailableRegions()">
                        <i class="fas fa-plus"></i>
                        <span>${msg.get("sub.subNewRegion")}</span>
                    </button>

                </div>
            </div>
        </div>

        <!-- 摘要信息 -->
        <div class="summary-cards">
            <div class="summary-card">
                <div class="summary-card-icon total">
                    <i class="fas fa-globe"></i>
                </div>
                <div class="summary-card-value" id="totalRegions">--</div>
                <div class="summary-card-label">${msg.get("sub.subTotalRegion")}</div>
            </div>
            <div class="summary-card">
                <div class="summary-card-icon subscribed">
                    <i class="fas fa-check-circle"></i>
                </div>
                <div class="summary-card-value" id="subscribedRegions">--</div>
                <div class="summary-card-label">${msg.get("sub.subAlreadyRegion")}</div>
            </div>
            <div class="summary-card">
                <div class="summary-card-icon unsubscribed">
                    <i class="fas fa-clock"></i>
                </div>
                <div class="summary-card-value" id="unsubscribedRegions">--</div>
                <div class="summary-card-label">${msg.get("sub.subNpRegion")}</div>
            </div>
        </div>

        <!-- 标签页 -->
        <div class="tabs">
            <button class="tab active" onclick="switchTab('subscribed')">
                <i class="fas fa-check-circle"></i>
                <span id="subAlreadyTitle">${msg.get("sub.subAlreadyRegion")}</span>
            </button>
            <button class="tab" onclick="switchTab('available')">
                <i class="fas fa-plus-circle"></i>
                ${msg.get("sub.subAvailableRegion")}
            </button>
        </div>

        <!-- 已订阅区域列表 -->
        <div id="subscribedTab" class="tab-content active">
            <div class="table-view">
                <table class="table">
                    <thead>
                    <tr>
                        <th>${msg.get("sub.regionFlag")}</th>
                        <th>${msg.get("sub.regionName")}</th>
                        <th>${msg.get("sub.regionStatus")}</th>
                        <th>${msg.get("sub.regionIsHome")}</th>
                        <th>${msg.get("sub.action")}</th>
                    </tr>
                    </thead>
                    <tbody id="subscribedRegionsTable">
                    <tr>
                        <td colspan="5" style="text-align: center; padding: 20px;">
                            <span class="loading-spinner"></span> Loading...
                        </td>
                    </tr>
                    </tbody>
                </table>
            </div>
        </div>

        <!-- 可订阅区域列表 -->
        <div id="availableTab" class="tab-content">
            <div class="batch-actions" id="batchActions">
                <div class="batch-count">
                    ${msg.get("mfa.form.selected")} <span id="selectedCount">0</span> ${msg.get("sub.noRegion")}
                </div>
                <div class="btn-group">
                    <button class="btn btn-success" onclick="batchSubscribeRegions()">
                        <i class="fas fa-plus"></i>
                        ${msg.get("sub.batchSub")}
                    </button>
                    <button class="btn btn-secondary" onclick="clearSelection()">
                        <i class="fas fa-times"></i>
                        ${msg.get("sub.cleanSelect")}
                    </button>
                </div>
            </div>

            <div class="table-view">
                <table class="table">
                    <thead>
                    <tr>
                        <th width="40">
                            <input type="checkbox" id="selectAll" onchange="toggleSelectAll()">
                        </th>
                        <th>${msg.get("sub.regionFlag")}</th>
                        <th>${msg.get("sub.regionName")}</th>
                        <th>${msg.get("sub.address")}</th>
                        <th>${msg.get("sub.action")}</th>
                    </tr>
                    </thead>
                    <tbody id="availableRegionsTable">
                    <tr>
                        <td colspan="5" style="text-align: center; padding: 20px;">
                            <span class="loading-spinner"></span>
                            ${msg.get("sub.clickTopRegion")}
                        </td>
                    </tr>
                    </tbody>
                </table>
            </div>
        </div>
    </div><!-- /.page-card -->
    </main>
</div>

<!-- 订阅进度模态框 -->
<div id="subscriptionModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("sub.regioning")}</h3>
        </div>
        <div class="progress-container">
            <div id="progressBar" class="progress-bar" style="width: 0%"></div>
        </div>
        <div id="statusMessage" class="status-message syncing">
            <span class="loading-spinner"></span>
            <span id="statusText">${msg.get("sub.subing")}... 0%</span>
        </div>
        <div id="subscriptionDetails" style="display: none; margin-top: 15px;">
            <h4 style="margin-bottom: 10px; font-size: 14px;">${msg.get("sub.subDetail")}:</h4>
            <div id="subscriptionDetailsList"></div>
        </div>
    </div>
</div>

<!-- 在body结束前引入版本信息模块 -->
<#--<#include "common/version_info.ftl">-->
<script>
    let currentTenantId = '${tenantId}';
    let subscribedRegions = 0;

    window.I18N = {
        sub_subConfirm: "${msg.get('sub.subConfirm')?js_string}",
        sub_subConfirmBatch: "${msg.get('sub.subConfirmBatch')?js_string}",
        sub_subing: "${msg.get('sub.subing')?js_string}",
        sub_regionDetail: "${msg.get('sub.regionDetail')?js_string}",
        sub_regionFlag: "${msg.get('sub.regionFlag')?js_string}",
        sub_regionLoading: "${msg.get('sub.regionLoading')?js_string}",
        common_network_error: "${msg.get('common.network.error')}",
        common_noData: "${msg.get('common.noData')?js_string}",
        common_available: "${msg.get('common.available')?js_string}",
        common_noAvailable: "${msg.get('common.noAvailable')?js_string}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        common_delete: "${msg.get('common.delete')?js_string}"

    }
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/system/region_sub.js"></script>
</body>
</html>