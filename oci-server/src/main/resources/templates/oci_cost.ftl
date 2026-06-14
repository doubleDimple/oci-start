<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 费用统计</title>
    <input type="hidden" id="tenantIdParam" value="${tenantId!''}">
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/echarts@5.4.3/dist/echarts.min.js" defer></script>
    <link rel="stylesheet" href="/css/app/oci_cost.css">
    <link rel="stylesheet" href="/css/common/client-pagination.css">
    <script src="/js/common/jquery.min.js"></script>
    <script src="/js/common/loading.js"></script>
    <link rel="stylesheet" href="/css/common/loading.css">
</head>
<body>
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <main class="main-content">
    <div class="page-card">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-dollar-sign"></i>
                <span>${msg.get("cost.total")}</span>
            </h1>
        </div>

        <!-- 查询条件区域（无区域下拉，只按租户+时间段） -->
        <div class="filter-controls">

            <!-- 时间范围选择 -->
            <div class="filter-item">
                <label class="filter-label">${msg.get("cost.timeRange")}：</label>
                <div class="time-presets">
                    <button class="btn btn-outline" data-preset="today"
                            onclick="selectCostTimePreset('today', this)">${msg.get("cost.today")}</button>
                    <button class="btn btn-outline" data-preset="month"
                            onclick="selectCostTimePreset('month', this)">${msg.get("cost.month")}</button>
                    <button class="btn btn-outline" data-preset="custom"
                            onclick="selectCostTimePreset('custom', this)">${msg.get("cost.def")}</button>
                </div>
                <div class="date-range-picker" id="costDateRangePicker" style="display: none;">
                    <input type="date" id="costStartDate" class="form-control" onchange="validateCostDateRange()">
                    <span>${msg.get("cost.to")}</span>
                    <input type="date" id="costEndDate" class="form-control" onchange="validateCostDateRange()">
                </div>
            </div>

            <div class="filter-item">
                <button class="btn btn-success" onclick="onCostQuery()">
                    <i class="fas fa-search"></i> ${msg.get("cost.query")}
                </button>
            </div>

            <div class="filter-item return-btn-container">
                <button class="btn btn-outline" onclick="window.history.back()">
                    <i class="fas fa-arrow-left"></i> ${msg.get("cost.back")}
                </button>
            </div>
        </div>

        <!-- 统计卡片：总费用 / 计算 / 存储 / 网络 -->
        <div class="stats-cards">
            <div class="stat-card">
                <div class="stat-icon"><i class="fas fa-coins"></i></div>
                <div class="stat-content">
                    <h3>${msg.get("cost.totalCost")}</h3>
                    <div class="stat-value" id="totalCost">$0.0000</div>
                </div>
                <#--<div class="stat-pie" id="pie_total">
                    <div class="pie-text"></div>
                </div>-->
            </div>
            <div class="stat-card">
                <div class="stat-icon"><i class="fas fa-server"></i></div>
                <div class="stat-content">
                    <h3>${msg.get("cost.cal")}</h3>
                    <div class="stat-value" id="computeCost">$0.0000</div>
                </div>
                <#--<div class="stat-pie" id="pie_compute">
                    <div class="pie-text"></div>
                </div>-->
            </div>
            <div class="stat-card">
                <div class="stat-icon"><i class="fas fa-hdd"></i></div>
                <div class="stat-content">
                    <h3>${msg.get("cost.save")}</h3>
                    <div class="stat-value" id="storageCost">$0.0000</div>
                </div>
                <#--<div class="stat-pie" id="pie_storage">
                    <div class="pie-text"></div>
                </div>-->
            </div>
            <div class="stat-card">
                <div class="stat-icon"><i class="fas fa-network-wired"></i></div>
                <div class="stat-content">
                    <h3>${msg.get("cost.net")}</h3>
                    <div class="stat-value" id="networkCost">$0.0000</div>
                </div>
                <#--<div class="stat-pie" id="pie_network">
                    <div class="pie-text"></div>
                </div>-->
            </div>
            <div class="stat-card">
                <div class="stat-content">
                    <h3>${msg.get("cost.other")}</h3>
                    <div class="stat-value" id="otherCost">$0.0000</div>
                </div>
                <#--<div class="stat-pie" id="pie_other">
                    <div class="pie-text"></div>
                </div>-->
            </div>

        </div>

        <!-- 费用趋势图 -->
        <div class="card trend-card">
            <div class="card-header text-center">
                <h3 class="card-title">${msg.get("cost.everyDayCost")}</h3>
            </div>
            <#--<div class="chart-switch" style="margin-top:10px;">
                <button class="btn btn-outline" onclick="changeCostChart('all')">全部</button>
                <button class="btn btn-outline" onclick="changeCostChart('compute')">计算</button>
                <button class="btn btn-outline" onclick="changeCostChart('storage')">存储</button>
                <button class="btn btn-outline" onclick="changeCostChart('network')">网络</button>
                <button class="btn btn-outline" onclick="changeCostChart('other')">其他</button>
            </div>-->
            <div class="card-body">
                <div id="costTrendChart" style="width: 100%; height: 400px;"></div>
            </div>
        </div>

        <!-- 费用明细表 -->
        <div class="card cost-table-card">
            <div class="card-header">
                <#--<h3 class="card-title">费用明细</h3>-->

                <button class="btn btn-outline" id="togglePositiveFilter" onclick="toggleCostFilter()">
                    <i class="fas fa-filter"></i> ${msg.get("cost.costCondition")}
                </button>
            </div>

            <div class="card-body">
                <table class="data-table cost-detail-table">
                    <thead>
                    <tr>
                        <th>${msg.get("cost.day")}</th>
                        <th>${msg.get("cost.resourceType")}</th>
                        <th>${msg.get("cost.skuName")}</th>
                        <th>${msg.get("cost.resourceId")}</th>
                        <th>${msg.get("cost.cost")}</th>
                    </tr>
                    </thead>
                    <tbody id="costTableBody">
                    <tr>
                        <td colspan="5" style="text-align:center;color:var(--text-secondary);">${msg.get("cost.plzTimeRange")}</td>
                    </tr>
                    </tbody>
                </table>
            </div>
            <!-- 客户端分页 -->
            <div id="costPagination"></div>
        </div>

    </div><!-- /.page-card -->
    </main>
</div>

<script>
    window.I18N = {
        common_saving: "${msg.get('common.saving')?js_string}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        common_delete: "${msg.get('common.delete')?js_string}",
        cost_plzTimeRange: "${msg.get('cost.plzTimeRange')?js_string}",
        common_noData: "${msg.get('common.noData')?js_string}",
        cost_cal: "${msg.get('cost.cal')?js_string}",
        cost_save: "${msg.get('cost.save')?js_string}",
        cost_net: "${msg.get('cost.net')?js_string}",
        cost_other: "${msg.get('cost.other')?js_string}",
        cost_showAll: "${msg.get('cost.showAll')?js_string}",
        cost_costCondition: "${msg.get('cost.costCondition')?js_string}",
        common_network_error: "${msg.get('common.network.error')?js_string}"

    }
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/client-pagination.js"></script>
<script src="/js/system/oci_cost.js"></script>
</body>
</html>
