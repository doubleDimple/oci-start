<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 仪表盘</title>
    <#--<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">-->
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/common/fa-fix.css">
    <#--<script src="https://cdn.jsdelivr.net/npm/chart.js" defer></script>-->
    <script src="/js/common/chart.js" defer></script>
    <link rel="stylesheet" href="/css/app/dashboard.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <script>
        /* 防闪烁：CSS 加载前立即设置主题 */
        (function () {
            var t = localStorage.getItem('oci_theme') || 'dark';
            if (t === 'system') t = window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
            document.documentElement.dataset.theme = t;
        })();
    </script>
</head>
<body>


<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
    <div class="page-card">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-tachometer-alt"></i>
                <span>${msg.get('dashboard.page.title')}</span>
            </h1>
            <div id="last-update">
                <span id="lastUpdateValue">${msg.get('dashboard.status.loading')}</span>
            </div>
        </div>
        <!-- 在monitor-grid之前添加 -->
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon api"><i class="fas fa-sliders-h"></i></div>
                    <h3 class="stat-title">${msg.get('dashboard.stats.api.total')}</h3>
                </div>
                <p class="stat-value" id="stat-api-total">-</p>
            </div>

            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon boot"><i class="fas fa-microchip"></i></div>
                    <h3 class="stat-title">${msg.get('dashboard.stats.boot.instances')}</h3>
                </div>
                <p class="stat-value" id="stat-boot-instances">-</p>
            </div>

            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon total"><i class="fas fa-sync"></i></div>
                    <h3 class="stat-title">${msg.get('dashboard.stats.attempt.total')}</h3>
                </div>
                <p class="stat-value" id="stat-attempt-total">-</p>
            </div>

            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon success"><i class="fas fa-check-circle"></i></div>
                    <h3 class="stat-title">${msg.get('dashboard.stats.attempt.success')}</h3>
                </div>
                <p class="stat-value" id="stat-attempt-success">-</p>
            </div>

            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon fail"><i class="fas fa-times-circle"></i></div>
                    <h3 class="stat-title">${msg.get('dashboard.stats.attempt.fail')}</h3>
                </div>
                <p class="stat-value" id="stat-attempt-fail" style="color: var(--accent-red);">-</p>
            </div>
        </div>
        <!-- 系统监控卡片 -->
        <div class="monitor-grid">
            <!-- CPU监控卡片 -->
            <div class="monitor-card">
                <div class="monitor-header">
                    <div class="monitor-icon rotating">
                        <i class="fas fa-microchip"></i>
                    </div>
                    <div class="monitor-info">
                        <h3>${msg.get('dashboard.monitor.cpu.title')}</h3>
                        <span id="cpuModel" class="monitor-subtitle">${msg.get('dashboard.status.loading')}</span>
                    </div>
                </div>
                <div class="gauge-container">
                    <div class="gauge">
                        <div class="gauge-fill" id="cpuGauge"></div>
                    </div>
                    <div class="gauge-center">
                        <span class="gauge-value" id="cpuValue">0%</span>
                    </div>
                </div>
                <div class="monitor-details">
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.cpu.physical')}</span>
                        <span id="cpuPhysicalCount">-</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.cpu.logical')}</span>
                        <span id="cpuLogicalCount">-</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.cpu.temp')}</span>
                        <span id="cpuTemp">-</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.cpu.freq')}</span>
                        <span id="cpuFrequency">-</span>
                    </div>
                </div>
            </div>

            <!-- 内存监控卡片 -->
            <div class="monitor-card">
                <div class="monitor-header">
                    <div class="monitor-icon pulse">
                        <i class="fas fa-database"></i>
                    </div>
                    <div class="monitor-info">
                        <h3>${msg.get('dashboard.monitor.mem.title')}</h3>
                        <span id="memoryTitle" class="monitor-subtitle">${msg.get('dashboard.status.loading')}</span>
                    </div>
                </div>
                <div class="gauge-container">
                    <div class="gauge">
                        <div class="gauge-fill" id="memoryGauge"></div>
                    </div>
                    <div class="gauge-center">
                        <span class="gauge-value" id="memoryValue">0%</span>
                    </div>
                </div>
                <div class="monitor-details">
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.mem.total')}</span>
                        <span id="memoryTotal">-</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.mem.used')}</span>
                        <span id="memoryUsed">-</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.mem.available')}</span>
                        <span id="memoryAvailable">-</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.mem.swap')}</span>
                        <span id="swapUsage">-</span>
                    </div>
                </div>
            </div>

            <!-- 系统信息卡片 -->
            <!-- 修改系统信息卡片，添加仪表盘 -->
            <div class="monitor-card">
                <div class="monitor-header">
                    <div class="monitor-icon bounce">
                        <i class="fas fa-server"></i>
                    </div>
                    <div class="monitor-info">
                        <h3>${msg.get('dashboard.monitor.sys.title')}</h3>
                        <span id="hostname" class="monitor-subtitle">${msg.get('dashboard.status.loading')}</span>
                    </div>
                </div>
                <!-- 添加仪表盘容器 -->
                <div class="gauge-container">
                    <div class="gauge">
                        <div class="gauge-fill" id="uptimeGauge"></div>
                    </div>
                    <div class="gauge-center">
                        <span class="gauge-value" id="uptimePercentage">0%</span>
                    </div>
                </div>
                <div class="monitor-details">
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.sys.os')}</span>
                        <span id="osInfo">-</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.sys.arch')}</span>
                        <span id="osArch">-</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.sys.uptime')}</span>
                        <span id="uptime">-</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.sys.processes')}</span>
                        <span id="processCount">-</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.sys.threads')}</span>
                        <span id="threadCount">-</span>
                    </div>
                </div>
            </div>
            <!-- 网络监控卡片 -->
            <div class="monitor-card">
                <div class="monitor-header">
                    <div class="monitor-icon flash">
                        <i class="fas fa-network-wired"></i>
                    </div>
                    <div class="monitor-info">
                        <h3>${msg.get('dashboard.monitor.net.title')}</h3>
                        <span id="networkInterface" class="monitor-subtitle">${msg.get('dashboard.monitor.net.subtitle')}</span>
                    </div>
                </div>
                <div class="network-chart">
                    <canvas id="networkChart"></canvas>
                </div>
                <div class="monitor-details">
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.net.up')}</span>
                        <span id="uploadSpeed">0 KB/s</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.net.down')}</span>
                        <span id="downloadSpeed">0 KB/s</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.net.total_up')}</span>
                        <span id="totalUpload">-</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.net.total_down')}</span>
                        <span id="totalDownload">-</span>
                    </div>
                </div>
            </div>

            <!-- 磁盘监控卡片 -->
            <div class="monitor-card">
                <div class="monitor-header">
                    <div class="monitor-icon bounce">
                        <i class="fas fa-hdd"></i>
                    </div>
                    <div class="monitor-info">
                        <h3>${msg.get('dashboard.monitor.disk.title')}</h3>
                        <span id="diskInfo" class="monitor-subtitle">${msg.get('dashboard.monitor.disk.subtitle')}</span>
                    </div>
                </div>
                <div class="gauge-container">
                    <div class="gauge">
                        <div class="gauge-fill" id="diskGauge"></div>
                    </div>
                    <div class="gauge-center">
                        <span class="gauge-value" id="diskValue">0%</span>
                    </div>
                </div>
                <div class="monitor-details">
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.disk.total')}</span>
                        <span id="diskTotal">-</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.disk.used')}</span>
                        <span id="diskUsed">-</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.disk.free')}</span>
                        <span id="diskFree">-</span>
                    </div>
                    <div class="detail-item">
                        <span>${msg.get('dashboard.monitor.disk.io')}</span>
                        <span id="diskIO">-</span>
                    </div>
                </div>
            </div>
        </div>
    </div><!-- /.page-card -->
    </main>
</div>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/system/dashboard.js"></script>
</body>
</html>