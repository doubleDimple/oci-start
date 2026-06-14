<!DOCTYPE html>
<html lang="zh">

<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <title>VPS管理系统 - ARM架构区域监控</title>
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>(function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/leaflet.min.css" />
    <script src="/js/leaflet.min.js"></script>
    <link rel="stylesheet" href="/css/app/arm_records.css">
    <link rel="stylesheet" href="/css/common/dropdown-menu.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <style>
        .layout { padding-top: 0; }
        .main-content { margin-left: 0; padding: 20px 24px; background: var(--db-bg); }
    </style>
</head>

<body>
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <main class="main-content">
    <div class="page-card">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-globe"></i>
                <span>${msg.get('arm.page.title')}</span>
            </h1>
            <div id="last-update">
                <span>${msg.get('dashboard.status.loading')}</span>
            </div>
        </div>

        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon">
                        <i class="fas fa-map-marker-alt"></i>
                    </div>
                    <h3 class="stat-title">${msg.get('arm.stats.total.regions')}</h3>
                </div>
                <p class="stat-value" id="total-regions">--</p>
            </div>

            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon pulse">
                        <i class="fas fa-microchip"></i>
                    </div>
                    <h3 class="stat-title">${msg.get('arm.stats.open.arm')}</h3>
                </div>
                <p class="stat-value" id="open-arm-regions">--</p>
            </div>

            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon">
                        <i class="fas fa-bell"></i>
                    </div>
                    <h3 class="stat-title">${msg.get('arm.stats.today.new')}</h3>
                </div>
                <p class="stat-value" id="today-new-regions">--</p>
            </div>
        </div>

        <div class="region-card">
            <div class="card-header">
                <div class="card-icon pulse">
                    <i class="fas fa-globe"></i>
                </div>
                <div class="card-info">
                    <h3>${msg.get('arm.map.count')}: <span class="arm-counter" id="map-arm-count">0</span></h3>
                </div>
                <!-- 添加切换按钮 -->
                <div class="map-toggle-buttons">
                    <button class="toggle-btn active" id="btn-arm-regions">${msg.get('arm.map.toggle.all')}</button>
                    <button class="toggle-btn" id="btn-my-regions">${msg.get('arm.map.toggle.mine')}</button>
                </div>
                <button class="toggle-map-btn" id="toggleMapBtn" onclick="toggleMapVisibility()">
                    <i class="fas fa-map" id="toggleMapIcon"></i>
                    <span id="toggleMapText">${msg.get('arm.map.show')}</span>
                </button>
            </div>
            <div id="world-map-wrapper" style="display:none; margin-top:12px;">
                <div id="world-map"></div>
            </div>
        </div>

        <div class="region-card">
            <div class="card-header">
                <div class="card-icon">
                    <i class="fas fa-list"></i>
                </div>
            </div>

            <div class="filter-bar">
                <div class="search-box">
                    <i class="fas fa-search"></i>
                    <input type="text" id="region-search" placeholder="${msg.get('arm.filter.search.placeholder')}" />
                </div>

                <!-- Hidden selects keep JS compatibility -->
                <select id="continent-filter" style="display:none;">
                    <option value="all">${msg.get('arm.filter.continent.all')}</option>
                    <option value="asia">${msg.get('arm.filter.continent.asia')}</option>
                    <option value="europe">${msg.get('arm.filter.continent.europe')}</option>
                    <option value="america-north">${msg.get('arm.filter.continent.north_america')}</option>
                    <option value="america-south">${msg.get('arm.filter.continent.south_america')}</option>
                    <option value="middle-east">${msg.get('arm.filter.continent.me_africa')}</option>
                </select>
                <select id="status-filter" style="display:none;">
                    <option value="all">${msg.get('arm.filter.status.all')}</option>
                    <option value="open">${msg.get('arm.filter.status.open')}</option>
                    <option value="closed">${msg.get('arm.filter.status.closed')}</option>
                </select>

                <!-- Custom filter dropdowns -->
                <div class="filter-dropdown" id="continent-filter-wrapper">
                    <button class="filter-dropdown-btn" id="continent-filter-btn" onclick="toggleFilterDropdown('continent-filter', event)">
                        <span id="continent-filter-label">${msg.get('arm.filter.continent.all')}</span>
                        <i class="fas fa-chevron-down"></i>
                    </button>
                    <div class="filter-dropdown-panel" id="continent-filter-panel" style="display:none;">
                        <div class="filter-option active" data-value="all" onclick="selectFilterOption('continent-filter', 'all', this)">${msg.get('arm.filter.continent.all')}</div>
                        <div class="filter-option" data-value="asia" onclick="selectFilterOption('continent-filter', 'asia', this)">${msg.get('arm.filter.continent.asia')}</div>
                        <div class="filter-option" data-value="europe" onclick="selectFilterOption('continent-filter', 'europe', this)">${msg.get('arm.filter.continent.europe')}</div>
                        <div class="filter-option" data-value="america-north" onclick="selectFilterOption('continent-filter', 'america-north', this)">${msg.get('arm.filter.continent.north_america')}</div>
                        <div class="filter-option" data-value="america-south" onclick="selectFilterOption('continent-filter', 'america-south', this)">${msg.get('arm.filter.continent.south_america')}</div>
                        <div class="filter-option" data-value="middle-east" onclick="selectFilterOption('continent-filter', 'middle-east', this)">${msg.get('arm.filter.continent.me_africa')}</div>
                    </div>
                </div>

                <div class="filter-dropdown" id="status-filter-wrapper">
                    <button class="filter-dropdown-btn" id="status-filter-btn" onclick="toggleFilterDropdown('status-filter', event)">
                        <span id="status-filter-label">${msg.get('arm.filter.status.all')}</span>
                        <i class="fas fa-chevron-down"></i>
                    </button>
                    <div class="filter-dropdown-panel" id="status-filter-panel" style="display:none;">
                        <div class="filter-option active" data-value="all" onclick="selectFilterOption('status-filter', 'all', this)">${msg.get('arm.filter.status.all')}</div>
                        <div class="filter-option" data-value="open" onclick="selectFilterOption('status-filter', 'open', this)">${msg.get('arm.filter.status.open')}</div>
                        <div class="filter-option" data-value="closed" onclick="selectFilterOption('status-filter', 'closed', this)">${msg.get('arm.filter.status.closed')}</div>
                    </div>
                </div>
            </div>

            <div class="table-responsive">
                <table class="arm-regions-table">
                    <thead>
                    <tr>
                        <th>${msg.get('arm.table.status')}</th>
                        <th>${msg.get('arm.table.region.code')}</th>
                        <th>${msg.get('arm.table.region.name')}</th>
                        <th>${msg.get('arm.table.arch.type')}</th>
                        <th>${msg.get('arm.table.release.time')}</th>
                        <th>${msg.get('arm.table.total.instances')}</th>
                        <th>${msg.get('arm.table.month.instances')}</th>
                        <th>${msg.get('arm.table.last.release')}</th>
                    </tr>
                    </thead>
                    <tbody id="arm-regions-tbody">
                    </tbody>
                </table>
            </div>

            <div class="pagination" id="regions-pagination"></div>
        </div>
    </div><!-- /.page-card -->
    </main>
</div>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/system/arm_records.js"></script>
</body>
</html>