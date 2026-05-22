// 全局变量
let networkChart;
const networkData = {
    labels: [],
    uploadData: [],
    downloadData: []
};

// ==================== 图表初始化 ====================

function initNetworkChart() {
    const ctx = document.getElementById('networkChart');
    if (!ctx) {
        console.warn('networkChart 元素不存在');
        return;
    }

    networkChart = new Chart(ctx.getContext('2d'), {
        type: 'line',
        data: {
            labels: networkData.labels,
            datasets: [{
                label: '上传',
                data: networkData.uploadData,
                borderColor: '#3b82f6',
                backgroundColor: 'rgba(59,130,246,0.08)',
                fill: true,
                tension: 0.4,
                borderWidth: 2,
                pointRadius: 0,
                pointHoverRadius: 4
            }, {
                label: '下载',
                data: networkData.downloadData,
                borderColor: '#22c55e',
                backgroundColor: 'rgba(34,197,94,0.08)',
                fill: true,
                tension: 0.4,
                borderWidth: 2,
                pointRadius: 0,
                pointHoverRadius: 4
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            animation: { duration: 0 },
            interaction: { mode: 'index', intersect: false },
            scales: {
                y: {
                    beginAtZero: true,
                    grid:   { color: 'rgba(0,0,0,0.05)', drawBorder: false },
                    border: { color: '#e8ecf0', dash: [4,4] },
                    ticks:  { color: '#8a94a6', font: { size: 11 } },
                    title:  { display: true, text: 'KB/s', color: '#8a94a6', font: { size: 11 } }
                },
                x: {
                    grid:   { color: 'rgba(0,0,0,0.03)', drawBorder: false },
                    border: { color: '#e8ecf0' },
                    ticks:  { color: '#8a94a6', font: { size: 10 }, maxRotation: 0, maxTicksLimit: 8 }
                }
            },
            plugins: {
                legend: {
                    position: 'top',
                    labels: {
                        color: '#4b5563',
                        font: { size: 12 },
                        usePointStyle: true,
                        pointStyleWidth: 8,
                        boxHeight: 6,
                        padding: 16
                    }
                },
                tooltip: {
                    backgroundColor: '#ffffff',
                    borderColor: '#e8ecf0',
                    borderWidth: 1,
                    titleColor: '#1a2233',
                    bodyColor: '#8a94a6',
                    padding: 10
                }
            }
        }
    });
}

// ==================== 仪表盘数据更新 ====================

function updateGauge(elementId, value) {
    const gauge = document.getElementById(elementId);
    if (!gauge) return;

    value = Math.min(Math.max(0, value), 100);

    let color = value <= 60 ? '#22c55e' :
        value <= 80 ? '#f97316' :
            '#ef4444';

    gauge.style.background = `conic-gradient(
        ${color} ${value * 3.6}deg,
        #edf0f5 ${value * 3.6}deg
    )`;

    const gaugeValue = gauge.closest('.gauge-container').querySelector('.gauge-value');
    if (gaugeValue) {
        gaugeValue.textContent = Math.round(value) + '%';
        gaugeValue.style.color = color;
    }
}

function updateDashboardStatsAjax() {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000);

    fetch('/boot/dashboard-stats', {
        method: 'GET',
        headers: {
            'Content-Type': 'application/json',
            'X-Requested-With': 'XMLHttpRequest'
        },
        signal: controller.signal
    })
        .then(response => {
            clearTimeout(timeoutId);
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            return response.json();
        })
        .then(apiResponse => {
            if (apiResponse.success && apiResponse.data) {
                const data = apiResponse.data;

                // 使用 key-value 映射，key 对应 HTML 中的 id，value 对应后端字段
                const statsMap = {
                    'stat-api-total': data.totalApiCalls,      // 总API数
                    'stat-boot-instances': data.totalBootInstances, // 总Boot实例数
                    'stat-attempt-total': data.totalAttempts,  // 总抢机次数
                    'stat-attempt-success': data.successfulAttempts, // 抢机成功次数
                    'stat-attempt-fail': data.failCounts || 0  // [新增] 总抢机失败次数
                };

                // 遍历并安全更新 DOM
                Object.keys(statsMap).forEach(id => {
                    const element = document.getElementById(id);
                    if (element) {
                        const value = statsMap[id];
                        // 只有当值不为 undefined 或 null 时才更新
                        element.textContent = (value !== undefined && value !== null) ? value : '-';

                        // 简单的数值增长动画效果（可选）
                        if (element.textContent !== '-') {
                            element.classList.add('value-updated');
                            setTimeout(() => element.classList.remove('value-updated'), 500);
                        }
                    }
                });

                console.log('Dashboard stats synchronized successfully.');
            } else {
                console.error('Dashboard data error:', apiResponse.message);
            }
        })
        .catch(error => {
            clearTimeout(timeoutId);
            if (error.name === 'AbortError') {
                console.warn('Dashboard stats request timed out');
            } else {
                console.error('Failed to fetch dashboard stats:', error);
            }
        });
}

function updateMonitorStatsAjax() {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000);

    fetch('/monitor/stats', {
        method: 'GET',
        headers: {
            'Content-Type': 'application/json',
            'X-Requested-With': 'XMLHttpRequest'
        },
        signal: controller.signal
    })
        .then(response => {
            clearTimeout(timeoutId);
            if (!response.ok) throw new Error(`HTTP error! status: ${response.status}`);
            return response.json();
        })
        .then(apiResponse => {
            if (apiResponse.success && apiResponse.data) {
                const data = apiResponse.data;

                try {
                    // CPU信息更新
                    document.getElementById('cpuModel').textContent = data.cpuModel || 'unKnow';
                    document.getElementById('cpuPhysicalCount').textContent = (data.cpuPhysicalCount || '0') + ' C';
                    document.getElementById('cpuLogicalCount').textContent = (data.cpuLogicalCount || '0') + ' C';
                    document.getElementById('cpuFrequency').textContent = (data.cpuFrequency || '0') + ' GHz';
                    document.getElementById('cpuTemp').textContent = data.cpuTemperature > 0 ?
                        data.cpuTemperature.toFixed(1) + '°C' : 'N/A';
                    document.getElementById('cpuValue').textContent = Math.min(100, Math.round(data.cpuUsage)) + '%';
                    updateGauge('cpuGauge', Math.min(100, data.cpuUsage));

                    // 内存信息更新
                    const totalMemoryGB = data.totalMemory / 1024;
                    document.getElementById('memoryTitle').textContent =
                        '总内存: ' + totalMemoryGB.toFixed(1) + ' GB';
                    document.getElementById('memoryTotal').textContent =
                        formatSize(data.totalMemory * 1024 * 1024);
                    document.getElementById('memoryUsed').textContent =
                        formatSize(data.usedMemory * 1024 * 1024);
                    document.getElementById('memoryAvailable').textContent =
                        formatSize(data.availableMemory * 1024 * 1024);
                    document.getElementById('swapUsage').textContent =
                        data.swapUsed + 'MB / ' + data.swapTotal + 'MB';
                    document.getElementById('memoryValue').textContent =
                        Math.round(data.memoryUsage) + '%';
                    updateGauge('memoryGauge', data.memoryUsage);

                    // 系统信息更新
                    document.getElementById('hostname').textContent = data.hostname;
                    document.getElementById('osInfo').textContent = data.osName;
                    document.getElementById('osArch').textContent = data.osArch;

                    const maxUptime = 315360000 / 2;
                    const uptimePercentage = Math.min((data.systemUptime / maxUptime) * 100, 100);
                    const uptimeDays = Math.floor(data.systemUptime / 86400);

                    updateGauge('uptimeGauge', uptimePercentage);
                    document.getElementById('uptimePercentage').textContent = uptimeDays + '天';
                    document.getElementById('uptime').textContent = formatUptime(data.systemUptime);
                    document.getElementById('processCount').textContent = data.totalProcesses;
                    document.getElementById('threadCount').textContent = data.threadCount;

                    // 磁盘信息更新
                    document.getElementById('diskValue').textContent =
                        Math.round(data.diskUsage) + '%';
                    document.getElementById('diskTotal').textContent =
                        formatSize(data.diskTotal);
                    document.getElementById('diskUsed').textContent =
                        formatSize(data.diskUsed);
                    document.getElementById('diskFree').textContent =
                        formatSize(data.diskFree);
                    updateGauge('diskGauge', data.diskUsage);

                    // 网络信息更新
                    document.getElementById('uploadSpeed').textContent =
                        formatSpeed(data.uploadSpeed);
                    document.getElementById('downloadSpeed').textContent =
                        formatSpeed(data.downloadSpeed);
                    updateNetworkChart(data.uploadSpeed, data.downloadSpeed);
                    document.getElementById('totalUpload').textContent =
                        formatSize(data.totalUploadBytes);
                    document.getElementById('totalDownload').textContent =
                        formatSize(data.totalDownloadBytes);

                    // 更新时间戳
                    document.getElementById('last-update').textContent = data.timestamp;

                    console.log('监控数据更新成功');
                } catch (error) {
                    console.error('更新监控数据时出错:', error);
                }
            } else {
                console.error('监控数据返回错误:', apiResponse.message);
            }
        })
        .catch(error => {
            clearTimeout(timeoutId);
            if (error.name === 'AbortError') {
                console.warn('监控数据请求超时');
            } else {
                console.error('获取监控数据失败:', error);
            }
        });
}

function formatSize(bytes) {
    if (bytes === 0) return '0 B';
    const k = 1024;
    const sizes = ['B', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(2)) + ' ' + sizes[i];
}

function formatSpeed(speed) {
    if (speed < 1024) {
        return speed.toFixed(2) + ' KB/s';
    } else {
        return (speed / 1024).toFixed(2) + ' MB/s';
    }
}

function formatUptime(seconds) {
    const years = Math.floor(seconds / (86400 * 365));
    const days = Math.floor((seconds % (86400 * 365)) / 86400);
    const hours = Math.floor((seconds % 86400) / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);

    let result = [];
    if (years > 0) result.push(years + 'year');
    if (days > 0) result.push(days + 'day');
    if (hours > 0) result.push(hours + 'hour');
    if (minutes > 0) result.push(minutes + 'min');

    return result.join(' ') || '0min';
}

function updateNetworkChart(uploadSpeed, downloadSpeed) {
    const now = new Date();
    const timeStr = now.toLocaleTimeString('zh-CN', {
        hour12: false,
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit'
    });

    networkData.labels.push(timeStr);
    networkData.uploadData.push(uploadSpeed);
    networkData.downloadData.push(downloadSpeed);

    if (networkData.labels.length > 30) {
        networkData.labels.shift();
        networkData.uploadData.shift();
        networkData.downloadData.shift();
    }

    if (networkChart) {
        networkChart.update('none');
    }
}

function initializeMenu() {
    const navParents = document.querySelectorAll('.nav-parent');
    navParents.forEach(parent => {
        const parentLink = parent.querySelector('.nav-link');
        if (parentLink) {
            parentLink.addEventListener('click', () => {
                parent.classList.toggle('expanded');
            });
        }
    });

    const activeLink = document.querySelector('.nav-link.active');
    if (activeLink) {
        const parent = activeLink.closest('.nav-parent');
        if (parent) {
            parent.classList.add('expanded');
        }
    }
}

document.addEventListener('DOMContentLoaded', () => {
    initNetworkChart();
    initializeMenu();
    updateMonitorStatsAjax();
    updateDashboardStatsAjax();

    setInterval(updateMonitorStatsAjax, 20000);
    setInterval(updateDashboardStatsAjax, 60000);
});
window.addEventListener('beforeunload', () => {
    if (networkChart) {
        networkChart.destroy();
    }
});