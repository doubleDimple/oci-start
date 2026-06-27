<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 监控管理</title>
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <script>function _getCsrfToken(){var i=document.querySelector('input[name="_csrf"]');if(i)return i.value;var m=document.querySelector('meta[name="_csrf"]');return m?(m.getAttribute('content')||''):''}</script>
    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/common/fa-fix.css">
    <link rel="stylesheet" href="/css/app/metrics_page2.css">
    <link rel="stylesheet" href="/css/common/loading.css">
</head>
<body>
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->


    <!-- 主内容区域 -->
    <main class="main-content">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-chart-line"></i>
                <span>监控管理</span>
            </h1>
            <div class="view-actions">
                <button id="refresh-btn" class="refresh-btn" onclick="manualRefresh()">
                    <i class="fas fa-sync-alt"></i>
                    <span>刷新</span>
                </button>
                <div class="view-toggle">
                    <button class="btn active" onclick="switchView('table')">
                        <i class="fas fa-list"></i>
                    </button>
                    <button class="btn" onclick="switchView('grid')">
                        <i class="fas fa-th-large"></i>
                    </button>
                </div>
            </div>
        </div>

        <!-- 表格视图 -->
        <div class="table-view">
            <table class="table">
                <thead>
                <tr>
                    <th>实例名称</th>
                    <th>IP地址</th>
                    <th>状态</th>
                    <th>CPU使用率</th>
                    <th>内存使用率</th>
                    <th>磁盘使用率</th>
                    <#--<th>上传速度</th>
                    <th>下载速度</th>-->
                    <th>总上传流量</th>
                    <th>总下载流量</th>
                    <th>最后更新</th>
                    <th>操作</th>
                </tr>
                </thead>
                <tbody>
                <#list servers as server>
                    <tr data-server-id="${server.serverId}">
                        <td>${server.serverId}</td>
                        <td>${server.serverIp!'--'}</td>
                        <td>
                            <div class="status-tag ${(server.online!false)?string('online', 'offline')}">
                                <i class="fas fa-circle"></i>
                                ${(server.online!false)?string('在线', '离线')}
                            </div>
                        </td>
                        <td>${server.cpuUsage}% (${server.cpuCores}核)</td>
                        <td>${server.memoryUsage}% (${server.totalMemory!0}GB)</td>
                        <td>${server.diskUsage}% (${server.totalDisk!0}GB)</td>
                        <#--<td>${server.uploadTraffic} MB/s</td>
                        <td>${server.downloadTraffic} MB/s</td>-->
                        <td>${server.totalUploadTraffic!'0MB'}</td>
                        <td>${server.totalDownloadTraffic!'0MB'}</td>
                        <!-- 其他列保持不变 -->
                        <td>${server.lastCheckTime!'-'}</td>
                        <td>
                            <button class="btn btn-danger" onclick="handleDelete('${server.serverId}')">
                                <i class="fas fa-trash"></i>
                                <span>删除</span>
                            </button>
                        </td>
                    </tr>
                </#list>
                </tbody>
            </table>
        </div>

        <!-- 卡片网格视图 -->
        <div class="grid-view">
            <#list servers as server>
                <div class="metric-card" data-server-id="${server.serverId}">
                    <div class="card-header">
                        <div class="instance-icon">
                            <i class="fas fa-server"></i>
                        </div>
                        <div class="instance-info">
                            <div class="instance-name">${server.serverId}</div>
                            <div class="instance-ip">${server.serverIp!'--'}</div>
                        </div>
                        <div class="status-tag ${(server.online!false)?string('online', 'offline')}">
                            <i class="fas fa-circle"></i>
                            ${(server.online!false)?string('在线', '离线')}
                        </div>
                    </div>

                    <div class="metric-content">
                        <!-- CPU使用率 -->
                        <div class="metric-item" data-metric="cpu">
                            <div class="metric-header">
                                <span class="metric-name">CPU利用率（${server.cpuCores}核）</span>
                                <span class="metric-value">${server.cpuUsage}%</span>
                            </div>
                            <div class="progress-bar">
                                <div class="progress-fill ${(server.cpuUsage gt 80)?string('danger',
                                (server.cpuUsage gt 60)?string('warning', ''))}"
                                     style="width: ${server.cpuUsage}%">
                                </div>
                            </div>
                        </div>

                        <!-- 内存使用率 -->
                        <div class="metric-item" data-metric="memory">
                            <div class="metric-header">
                                <span class="metric-name">内存使用（${server.totalMemory!0}GB）</span>
                                <span class="metric-value">${server.memoryUsage!0}%</span>
                            </div>
                            <div class="progress-bar">
                                <div class="progress-fill ${(server.memoryUsage gt 80)?string('danger',
                                (server.memoryUsage gt 60)?string('warning', ''))}"
                                     style="width: ${server.memoryUsage}%">
                                </div>
                            </div>
                        </div>

                        <!-- 磁盘使用率 -->
                        <div class="metric-item" data-metric="disk">
                            <div class="metric-header">
                                <span class="metric-name">磁盘使用（${server.totalDisk!0}GB）</span>
                                <span class="metric-value">${server.diskUsage!0}%</span>
                            </div>
                            <div class="progress-bar">
                                <div class="progress-fill ${(server.diskUsage gt 80)?string('danger',
                                (server.diskUsage gt 60)?string('warning', ''))}"
                                     style="width: ${server.diskUsage}%">
                                </div>
                            </div>
                        </div>

                        <!-- 网络速度 -->
                        <!-- 上传速度 -->
                        <#--<div class="metric-item" data-metric="upload">
                            <div class="metric-header">
                                <span class="metric-name">上传速度</span>
                                <span class="metric-value">${server.uploadTraffic} MB/s</span>
                            </div>
                            <div class="progress-bar">
                                <div class="progress-fill" style="width: 0%"></div>
                            </div>
                        </div>

                        <!-- 下载速度 &ndash;&gt;
                        <div class="metric-item" data-metric="download">
                            <div class="metric-header">
                                <span class="metric-name">下载速度</span>
                                <span class="metric-value">${server.downloadTraffic} MB/s</span>
                            </div>
                            <div class="progress-bar">
                                <div class="progress-fill" style="width: 0%"></div>
                            </div>
                        </div>-->

                        <!-- 总流量 -->
                        <div class="metric-item">
                            <div class="metric-header">
                                <span class="metric-name">总上传流量</span>
                                <span class="metric-value">${server.totalUploadTraffic!'0MB'}</span>
                            </div>
                        </div>

                        <div class="metric-item">
                            <div class="metric-header">
                                <span class="metric-name">总下载流量</span>
                                <span class="metric-value">${server.totalDownloadTraffic!'0MB'}</span>
                            </div>
                        </div>

                        <!-- 在最后更新时间前添加操作区域 -->
                        <div class="card-actions">
                            <button class="btn btn-danger" onclick="handleDelete('${server.serverId}')">
                                <i class="fas fa-trash"></i>
                                <span>删除</span>
                            </button>
                        </div>

                        <div class="last-update">
                            最后更新: ${server.lastCheckTime!'-'}
                        </div>
                    </div>
                </div>
            </#list>
        </div>
    </main>
</div>

<#--<#include "common/version_info.ftl">-->
</body>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script>
    // 视图切换功能
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

        localStorage.setItem('metricsPreferredView', view);
    }

    // 手动刷新功能
    function manualRefresh() {
        const refreshBtn = document.getElementById('refresh-btn');
        const refreshIcon = refreshBtn.querySelector('i');
        refreshIcon.classList.add('spinning');

        updateMetrics().finally(() => {
            setTimeout(() => {
                refreshIcon.classList.remove('spinning');
            }, 1000);
        });
    }

    // 更新进度条颜色
    function getProgressBarClass(value) {
        if (value > 80) return 'danger';
        if (value > 60) return 'warning';
        return '';
    }

    // 格式化时间
    function formatDateTime(date) {
        return new Date(date).toLocaleString('zh-CN', {
            year: 'numeric',
            month: '2-digit',
            day: '2-digit',
            hour: '2-digit',
            minute: '2-digit',
            second: '2-digit'
        });
    }

    // 更新表格行数据
    function updateTableRow(server) {
        const row = document.querySelector(`tr[data-server-id="`+server.serverId+`"]`);
        if (!row) return;

        // 更新状态
        const statusCell = row.querySelector('td:nth-child(3)');
        let status = '';
        if(server.online) {
            status = '<div class="status-tag online"><i class="fas fa-circle"></i>在线</div>';
        } else {
            status = '<div class="status-tag offline"><i class="fas fa-circle"></i>离线</div>';
        }
        statusCell.innerHTML = status;

        // 更新使用率
        row.querySelector('td:nth-child(4)').textContent = server.cpuUsage+`% (`+server.cpuCores+`核)`;
        row.querySelector('td:nth-child(5)').textContent = server.memoryUsage`% (`+server.totalMemory+`GB)`;
        row.querySelector('td:nth-child(6)').textContent = server.diskUsage`% (`+server.totalDisk +`GB)`;

        // 更新网络数据
        row.querySelector('td:nth-child(7)').textContent = server.uploadTraffic + ` MB/s`;
        row.querySelector('td:nth-child(8)').textContent = server.downloadTraffic +` MB/s`;
        row.querySelector('td:nth-child(9)').textContent = server.totalUploadTraffic || '0MB';
        row.querySelector('td:nth-child(10)').textContent = server.totalDownloadTraffic || '0MB';

        // 更新时间
        row.querySelector('td:nth-child(11)').textContent = formatDateTime(server.lastCheckTime);
    }

    // 更新卡片数据
    function updateCard(server) {
        const card = document.querySelector(`.metric-card[data-server-id="`+server.serverId+`"]`);
        if (!card) return;

        // 更新状态标签
        const statusTag = card.querySelector('.status-tag');
        if(server.online) {
            statusTag.className = 'status-tag online';
            statusTag.innerHTML = '<i class="fas fa-circle"></i>在线';
        } else {
            statusTag.className = 'status-tag offline';
            statusTag.innerHTML = '<i class="fas fa-circle"></i>离线';
        }

        // 更新CPU使用率
        updateMetricItem(card, 'cpu', server.cpuUsage, `CPU利用率（`+server.cpuCores+`核）`);

        // 更新内存使用率
        updateMetricItem(card, 'memory', server.memoryUsage, `内存使用（`+ server.totalMemory+`GB）`);

        // 更新磁盘使用率
        updateMetricItem(card, 'disk', server.diskUsage, `磁盘使用（`+server.totalDisk+`GB）`);

        // 更新网络速度
        updateMetricItem(card, 'upload', server.uploadTraffic, '上传速度', 'MB/s', true);
        updateMetricItem(card, 'download', server.downloadTraffic, '下载速度', 'MB/s', true);

        // 更新总流量
        updateSimpleMetric(card, '总上传流量', server.totalUploadTraffic || '0MB');
        updateSimpleMetric(card, '总下载流量', server.totalDownloadTraffic || '0MB');

        // 更新最后更新时间
        card.querySelector('.last-update').textContent = `最后更新: `+formatDateTime(server.lastCheckTime) +``;
    }

    // 更新指标项
    function updateMetricItem(card, metricType, value, label, unit = '%', isNetwork = false) {
        const item = card.querySelector('[data-metric="' + metricType + '"]');
        if (!item) return;

        const nameSpan = item.querySelector('.metric-name');
        const valueSpan = item.querySelector('.metric-value');
        const progressFill = item.querySelector('.progress-fill');

        nameSpan.textContent = label;
        valueSpan.textContent = value + unit;

        if (isNetwork) {
            // 网络速度使用0-1000MB/s的范围
            const numValue = parseFloat(value) || 0;
            const percentage = Math.min((numValue / 1000) * 100, 100);
            progressFill.style.width = percentage + '%';
        } else {
            progressFill.style.width = value + '%';
            progressFill.className = 'progress-fill ' + getProgressBarClass(value);
        }
    }

    // 更新简单指标（无进度条）
    function updateSimpleMetric(card, label, value) {
        const items = card.querySelectorAll('.metric-item');
        items.forEach(item => {
            const nameSpan = item.querySelector('.metric-name');
            if (nameSpan && nameSpan.textContent === label) {
                item.querySelector('.metric-value').textContent = value;
            }
        });
    }

    // 更新所有指标数据
    async function updateMetrics() {
        try {
            const response = await fetch('/api/metrics/status');
            if (!response.ok) throw new Error('Network response was not ok');

            const data = await response.json();

            data.forEach(server => {
                updateTableRow(server);
                updateCard(server);
            });

            // 更新页面最后更新时间
            document.querySelector('.page-header').setAttribute(
                'data-last-update',
                formatDateTime(new Date())
            );

        } catch (error) {
            console.error('Failed to update metrics:', error);
        }
    }

    // 侧边栏展开/折叠功能
    function initializeSidebar() {
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
    }

    // 页面初始化
    document.addEventListener('DOMContentLoaded', function() {
        // 初始化侧边栏
        initializeSidebar();

        // 恢复上次视图选择
        const preferredView = localStorage.getItem('metricsPreferredView') || 'table';
        switchView(preferredView);

        // 立即进行首次更新
        updateMetrics();

        // 设置自动更新间隔（5秒）
        setInterval(updateMetrics, 5000);
    });

    // 在窗口大小改变时调整布局
    window.addEventListener('resize', function() {
        const width = window.innerWidth;
        if (width <= 768) {
            document.querySelector('.sidebar').style.display = 'none';
            document.querySelector('.main-content').style.marginLeft = '0';
        } else {
            document.querySelector('.sidebar').style.display = 'block';
            document.querySelector('.main-content').style.marginLeft = '200px';
        }
    });

    function handleDelete(serverId) {
        if (!confirm('确定要删除此监控实例吗？此操作不可恢复。')) {
            return;
        }

        // 显示加载状态
        const buttons = document.querySelectorAll('button[onclick="handleDelete(\'' + serverId + '\')"]');
        buttons.forEach(btn => {
            btn.disabled = true;
            btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> 删除中...';
        });

        const xhr = new XMLHttpRequest();
        xhr.open('GET', '/api/metrics/deleteMetrics?serverId=' + serverId, true);

        // 设置CSRF令牌
        const token = _getCsrfToken();
        xhr.setRequestHeader('X-CSRF-TOKEN', token);

        xhr.onload = function() {
            if (xhr.status === 200) {
                // 删除成功，移除对应的表格行和卡片
                const tableRow = document.querySelector('tr[data-server-id="' + serverId + '"]');
                const card = document.querySelector('.metric-card[data-server-id="' + serverId + '"]');

                if (tableRow) {
                    tableRow.style.animation = 'fadeOut 0.3s ease';
                    setTimeout(() => tableRow.remove(), 300);
                }
                if (card) {
                    card.style.animation = 'fadeOut 0.3s ease';
                    setTimeout(() => card.remove(), 300);
                }
            } else {
                alert('删除失败，请重试');
                // 恢复按钮状态
                buttons.forEach(btn => {
                    btn.disabled = false;
                    btn.innerHTML = '<i class="fas fa-trash"></i><span>删除</span>';
                });
            }
        };

        xhr.onerror = function() {
            alert('删除失败，请重试');
            // 恢复按钮状态
            buttons.forEach(btn => {
                btn.disabled = false;
                btn.innerHTML = '<i class="fas fa-trash"></i><span>删除</span>';
            });
        };

        xhr.send();
    }
</script>
</html>