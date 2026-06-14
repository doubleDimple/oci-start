<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 流量监控</title>
    <input type="hidden" id="tenantIdParam" value="${tenantId!''}">
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/echarts@5.4.3/dist/echarts.min.js"></script>
    <link rel="stylesheet" href="/css/app/oci_monitor.css">
    <script src="/js/common/jquery.min.js"></script>
    <script src="/js/common/loading.js"></script>
    <link rel="stylesheet" href="/css/common/loading.css">

</head>
<body>
<#--<#include "common/version_info.ftl">-->
<#--<#--<#include "common/header.ftl" />-->-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <main class="main-content">
    <div class="page-card">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-chart-line"></i>
                <span>${msg.get("traffic.config")}</span>
            </h1>
        </div>

        <div class="filter-controls">
            <!-- 区域选择 -->
            <div class="multi-select-container" id="regionDropdown">
                <div class="multi-select-display" onclick="toggleRegionDropdown()">
                    <span id="regionSelectedText">${msg.get("openBoot.selectRegion")}</span>
                    <i class="fas fa-chevron-down"></i>
                </div>
                <div class="multi-select-options" id="regionOptions">
                </div>
            </div>

            <!-- 时间范围选择 -->
            <div class="filter-item">
                <label class="filter-label">${msg.get("cost.timeRange")}：</label>
                <div class="time-presets">
                    <!-- 增加 data-preset 属性；显式传 this 时也能用 -->
                    <button class="btn btn-outline" data-preset="today" onclick="selectTimePreset('today', this)">${msg.get("cost.today")}</button>
                    <button class="btn btn-outline" data-preset="month" onclick="selectTimePreset('month', this)">${msg.get("cost.month")}</button>
                    <button class="btn btn-outline" data-preset="custom" onclick="selectTimePreset('custom', this)">${msg.get("cost.def")}</button>
                </div>
                <div class="date-range-picker" id="dateRangePicker" style="display: none;">
                    <input type="date" id="startDate" class="form-control" onchange="validateDateRange()">
                    <span>${msg.get("cost.to")}</span>
                    <input type="date" id="endDate" class="form-control" onchange="validateDateRange()">
                </div>
            </div>

            <div class="filter-item">
                <button class="btn btn-success" onclick="onQuery()">
                    <i class="fas fa-search"></i> ${msg.get("cost.query")}
                </button>
            </div>

            <div class="filter-item return-btn-container">
                <button class="btn btn-outline" onclick="window.history.back()">
                    <i class="fas fa-arrow-left"></i> ${msg.get("cost.back")}
                </button>
            </div>
        </div>

        <!-- 统计卡片 -->
        <div class="stats-cards">
            <div class="stat-card">
                <div class="stat-icon"><i class="fas fa-chart-area"></i></div>
                <div class="stat-content">
                    <h3>${msg.get("traffic.total")}</h3>
                    <div class="stat-value" id="totalTraffic">0 GB</div>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon"><i class="fas fa-arrow-down"></i></div>
                <div class="stat-content">
                    <h3>${msg.get("traffic.in")}</h3>
                    <div class="stat-value" id="ingressTraffic">0 GB</div>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon"><i class="fas fa-arrow-up"></i></div>
                <div class="stat-content">
                    <h3>${msg.get("traffic.out")}</h3>
                    <div class="stat-value" id="egressTraffic">0 GB</div>
                </div>
            </div>
            <div class="stat-card">
                <div class="stat-icon" style="color:var(--accent-red);"><i class="fas fa-bell"></i></div>
                <div class="stat-content">
                    <h3>${msg.get("traffic.monitor")}</h3>
                    <div class="stat-value" id="thresholdTraffic">10 TB</div>
                </div>
            </div>
        </div>

        <div class="alert-charts-container">
            <div class="alert-chart-card">
                <h3 class="chart-title">${msg.get("traffic.totalPer")}</h3>
                <div id="totalAlertChart" class="alert-chart"></div>
            </div>
            <div class="alert-chart-card">
                <h3 class="chart-title">${msg.get("traffic.inPer")}</h3>
                <div id="ingressAlertChart" class="alert-chart"></div>
            </div>
            <div class="alert-chart-card">
                <h3 class="chart-title">${msg.get("traffic.outPer")}</h3>
                <div id="egressAlertChart" class="alert-chart"></div>
            </div>
        </div>

        <!-- 流量趋势图 -->
        <div class="card">
            <div class="card-header text-center">
                <h3 class="card-title">${msg.get("traffic.trends")}</h3>
            </div>
            <div class="card-body">
                <div id="trafficWaveChart" style="width: 100%; height: 400px;"></div>
            </div>
        </div>

        <div class="instance-charts-container">
            <h3 class="section-title">${msg.get("traffic.insTrends")}</h3>
            <div id="instanceCharts" class="instance-charts"></div>
        </div>

    </div><!-- /.page-card -->
    </main>
</div>
<script>
    window.I18N = {
        common_noData: "${msg.get('common.noData')?js_string}",
        common_plzInputGlobalRequired: "${msg.get('common.plzInputGlobalRequired')?js_string}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        common_delete: "${msg.get('common.delete')?js_string}",
        common_network_error: "${msg.get('common.network.error')?js_string}",
        traffic_totalPer: "${msg.get('traffic.totalPer')?js_string}",
        traffic_inPer: "${msg.get('traffic.inPer')?js_string}",
        traffic_outPer: "${msg.get('traffic.outPer')?js_string}",
        traffic_used: "${msg.get('traffic.used')?js_string}",
        traffic_surplus: "${msg.get('traffic.surplus')?js_string}",
        traffic_in: "${msg.get('traffic.in')?js_string}",
        traffic_out: "${msg.get('traffic.out')?js_string}",
        traffic_total: "${msg.get('traffic.total')?js_string}",
        traffic_flow: "${msg.get('traffic.flow')?js_string}",
        aiModel_region: "${msg.get('aiModel.region')?js_string}",
        openBoot_selectRegion: "${msg.get('openBoot.selectRegion')?js_string}",
        traffic_checkTime: "${msg.get('traffic.checkTime')?js_string}",
        traffic_checkTime2: "${msg.get('traffic.checkTime2')?js_string}",
        traffic_checkTime3: "${msg.get('traffic.checkTime3')?js_string}",
        traffic_selectRegion: "${msg.get('traffic.selectRegion')?js_string}",
        vpn_edit: "${msg.get('vpn.edit')?js_string}"

    }
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/system/oci_monitor.js"></script>
</body>
</html>
