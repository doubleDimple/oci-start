
let myChart;
let selectedRegionId = "";
let selectedTimeRange = 'month';
let customStartDate = null;
let customEndDate = null;
let period = "1d"; // 默认按天

const i18n = window.I18N;

let totalAlertChart, ingressAlertChart, egressAlertChart;

let alertThresholdGB = 10240; // 默认10T

let selectedRegionIds = [];



document.addEventListener('DOMContentLoaded', async function() {

    // 侧边栏展开/收起逻辑
    const navParents = document.querySelectorAll('.nav-parent');
    navParents.forEach(parent => {
        const parentLink = parent.querySelector('.nav-link');
        if (parentLink && !parentLink.hasListener) {
            parentLink.addEventListener('click', (e) => {
                e.preventDefault();
                parent.classList.toggle('expanded');
            });
            parentLink.hasListener = true;
        }
    });
    // 自动展开当前激活项的父级
    const activeLink = document.querySelector('.nav-link.active');
    if (activeLink) {
        const parent = activeLink.closest('.nav-parent');
        if (parent) parent.classList.add('expanded');
    }

    initializeChart();
    await fetchTrafficAlertThreshold();
    await loadRegionsData();
    selectTimePreset('month');
    await loadTrafficData();

    totalAlertChart = echarts.init(document.getElementById('totalAlertChart'));
    ingressAlertChart = echarts.init(document.getElementById('ingressAlertChart'));
    egressAlertChart = echarts.init(document.getElementById('egressAlertChart'));

    initAlertChart(totalAlertChart, i18n.traffic_totalPer);
    initAlertChart(ingressAlertChart, i18n.traffic_inPer);
    initAlertChart(egressAlertChart, i18n.traffic_outPer);
});

function toggleRegionDropdown() {
    document.getElementById('regionOptions').classList.toggle('show');
}

// 点击外部关闭下拉
document.addEventListener('click', function(e) {
    const dropdown = document.getElementById('regionDropdown');
    if (!dropdown.contains(e.target)) {
        document.getElementById('regionOptions').classList.remove('show');
    }
});



function initAlertChart(chart, title) {
    chart.setOption({
        tooltip: {
            trigger: 'item',
            formatter: '{b}<br/>{c} GB ({d}%)'
        },
        legend: {
            top: 'bottom'
        },
        series: [
            {
                name: title,
                type: 'pie',
                radius: ['50%', '75%'],
                avoidLabelOverlap: false,
                label: {
                    show: true,
                    position: 'center',
                    formatter: '{d}%',
                    fontSize: 18,
                    fontWeight: 'bold'
                },
                emphasis: {
                    label: {
                        show: true,
                        fontSize: 20,
                        fontWeight: 'bold'
                    }
                },
                labelLine: { show: false },
                data: [
                    { value: 0, name: i18n.traffic_used },
                    { value: alertThresholdGB, name: i18n.traffic_surplus }
                ]
            }
        ]
    });
}

function loadTrafficAlertData(totalBytes, ingressBytes, egressBytes) {
    const totalUsedGB = (totalBytes / 1073741824).toFixed(2);
    const ingressUsedGB = (ingressBytes / 1073741824).toFixed(2);
    const egressUsedGB = (egressBytes / 1073741824).toFixed(2);

    updateAlertChart(totalAlertChart, totalUsedGB, alertThresholdGB);
    updateAlertChart(ingressAlertChart, ingressUsedGB, alertThresholdGB);
    updateAlertChart(egressAlertChart, egressUsedGB, alertThresholdGB);
}

function formatTBorGB(valueGB) {
    if (valueGB >= 1024) {
        return (valueGB / 1024).toFixed(2) + ' TB';
    } else {
        return valueGB.toFixed(2) + ' GB';
    }
}

function updateAlertChart(chart, usedGB, thresholdGB) {
    const remain = Math.max(thresholdGB - usedGB, 0).toFixed(2);
    chart.setOption({
        series: [
            {
                data: [
                    { value: usedGB, name: i18n.traffic_used },
                    { value: remain, name: i18n.traffic_surplus }
                ],
                label: {
                    formatter: ((usedGB / thresholdGB) * 100).toFixed(1)+`%`
                }
            }
        ]
    });
}

// 初始化图表
function initializeChart() {
    myChart = echarts.init(document.getElementById('trafficWaveChart'));
    myChart.setOption({
        grid: {
            left: '0%',
            right: '0%',
            bottom: '10%',
            top: '15%',
            containLabel: true
        },
        tooltip: { trigger: 'axis' },
        legend: { data: [i18n.traffic_in, i18n.traffic_out, i18n.traffic_total] },
        xAxis: {
            type: 'category',
            boundaryGap: false,
            data: []
        },
        yAxis: {
            type: 'value',
            name: i18n.traffic_flow+' (GB)'
        },
        series: [
            { name: i18n.traffic_in, type: 'line', smooth: true, data: [] },
            { name: i18n.traffic_out, type: 'line', smooth: true, data: [] },
            { name: i18n.traffic_total, type: 'line', smooth: true, data: [] }
        ]
    });
    window.addEventListener('resize', () => myChart.resize());
}


// 加载区域
async function loadRegionsData() {
    try {
        const parentId = document.getElementById('tenantIdParam').value || '';
        const response = await fetch('/tenants/listRegions?parentId=' + encodeURIComponent(parentId), {
            headers: { 'X-CSRF-TOKEN': document.getElementById('csrf_token').value }
        });
        if (!response.ok) throw new Error('error');
        const regions = await response.json();

        const optionsDiv = document.getElementById('regionOptions');
        optionsDiv.innerHTML = '';

        regions.forEach(region => {
            const label = document.createElement('label');
            label.innerHTML = `
                <input type="checkbox" value="`+ region.id+`" onchange="updateSelectedRegions()">
                <span>`+region.region || ''+i18n.aiModel_region+'' + region.id +`</span>
            `;
            optionsDiv.appendChild(label);
        });
    } catch (e) {
        showError('error');
    }
}

function updateSelectedRegions() {
    const checked = Array.from(document.querySelectorAll('#regionOptions input:checked'));
    selectedRegionIds = checked.map(input => input.value);

    const selectedNames = checked.map(input => input.nextElementSibling.textContent);
    let displayText = '';

    if (selectedNames.length === 0) {
        displayText = i18n.openBoot_selectRegion;
    } else if (selectedNames.length <= 2) {
        displayText = '<div>' + selectedNames.join('</div><div>') + '</div>';
    } else {
        displayText = '<div>' + selectedNames.slice(0, 2).join('</div><div>') +
            '</div><div>+' + (selectedNames.length - 2) + '</div>';
    }

    document.getElementById('regionSelectedText').innerHTML = displayText;
}

// 选择时间预设（btnEl 可选；如果未传，会自动找对应按钮）
function selectTimePreset(preset, btnEl) {
    selectedTimeRange = preset;

    // 清空 active
    document.querySelectorAll('.time-presets button').forEach(btn => btn.classList.remove('active'));

    // 若未传 btnEl，则通过 data-preset 寻找对应按钮
    if (!btnEl) {
        btnEl = document.querySelector(`.time-presets button[data-preset="`+ preset+`"]`);
    }
    if (btnEl && btnEl.classList) {
        btnEl.classList.add('active');
    }

    const picker = document.getElementById('dateRangePicker');
    if (preset === 'custom') {
        picker.style.display = 'flex';
        const today = new Date();
        const lastMonth = new Date(today);
        lastMonth.setMonth(today.getMonth() - 1);
        document.getElementById('startDate').value = formatDate(lastMonth);
        document.getElementById('endDate').value = formatDate(today);

        customStartDate = lastMonth;
        customEndDate = today;
    } else {
        picker.style.display = 'none';
    }
}

function formatDate(date) {
    return date.toISOString().split('T')[0];
}

function validateDateRange() {
    const startVal = document.getElementById('startDate').value;
    const endVal = document.getElementById('endDate').value;
    if (!startVal || !endVal) return;

    customStartDate = new Date(startVal);
    customEndDate = new Date(endVal);

    if (customStartDate > customEndDate) {
        return showError(i18n.traffic_checkTime);
    }
    // 最长 3 个月限制（前端兜底）
    const threeMonthsAgo = new Date();
    threeMonthsAgo.setMonth(threeMonthsAgo.getMonth() - 3);
    if (customStartDate < threeMonthsAgo) {
        console.error('查询时间范围不能超过3个月')
        return showError(i18n.traffic_checkTime2);
    }
}

function onQuery() {
    if (selectedRegionIds.length === 0) {
        showError(i18n.traffic_selectRegion);
        return;
    }
    if (selectedTimeRange === 'custom') {
        const startVal = document.getElementById('startDate').value;
        const endVal = document.getElementById('endDate').value;
        if (!startVal || !endVal) {
            showError(i18n.traffic_checkTime3);
            return;
        }
    }
    loadTrafficData();
}


// 计算请求时间
function getStartDate() {
    if (selectedTimeRange === 'custom') return formatDate(customStartDate);
    if (selectedTimeRange === 'today') return formatDate(new Date());
    const today = new Date();
    return formatDate(new Date(today.getFullYear(), today.getMonth(), 1));
}
function getEndDate() {
    if (selectedTimeRange === 'custom') return formatDate(customEndDate);
    return formatDate(new Date());
}

// 拉取并更新
async function loadTrafficData() {
    if (selectedRegionIds.length === 0) return;

    showLoading('loading');

    const requestData = {
        tenantIds: selectedRegionIds,
        startDate: getStartDate(),
        endDate: getEndDate(),
        period: period
    };

    try {
        await fetchTrafficAlertThreshold();

        myChart.showLoading({ text: 'loading' });
        const res = await fetchWithCsrf('/monitor/api/instances/traffic', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(requestData)
        });
        if (!res.ok) throw new Error('error：' + res.status);
        const data = await res.json();
        updateChartAndStats(data);
    } catch (e) {
        console.error(e);
        updateChartAndStats([]);
        showError('error');
    } finally {
        hideLoading();
        myChart.hideLoading();
    }
}

// 更新图表 & 统计卡片
function updateChartAndStats(data) {
    if (!Array.isArray(data) || data.length === 0) {
        resetAllCharts();
        return;
    }

    // 合并同一时间点的流量（所有实例/所有 vnic）
    const bucket = {};
    let totalIngress = 0, totalEgress = 0;

    data.forEach(item => {
        const time = item.timePoint;
        if (!bucket[time]) bucket[time] = { ingress: 0, egress: 0 };
        const inB = Number(item.ingressBytes) || 0;
        const egB = Number(item.egressBytes) || 0;
        bucket[time].ingress += inB;
        bucket[time].egress += egB;
        totalIngress += inB;
        totalEgress += egB;
    });

    const times = Object.keys(bucket).sort();
    const ingressSeries = times.map(t => (bucket[t].ingress / 1073741824).toFixed(2)); // 1024^3
    const egressSeries = times.map(t => (bucket[t].egress / 1073741824).toFixed(2));
    const totalSeries = times.map((t, i) => (parseFloat(ingressSeries[i]) + parseFloat(egressSeries[i])));

    myChart.setOption({
        xAxis: { data: times },
        series: [
            { name: i18n.traffic_in, data: ingressSeries },
            { name: i18n.traffic_out, data: egressSeries },
            { name: i18n.traffic_total, data: totalSeries }
        ]
    });

    document.getElementById('totalTraffic').textContent = formatGB(totalIngress + totalEgress);
    document.getElementById('ingressTraffic').textContent = formatGB(totalIngress);
    document.getElementById('egressTraffic').textContent = formatGB(totalEgress);
    loadTrafficAlertData(totalIngress + totalEgress, totalIngress, totalEgress);
    renderInstanceCharts(data);
}

function formatGB(bytes) {
    return (bytes / 1073741824).toFixed(2) + ' GB';
}

function fetchWithCsrf(url, options) {
    const token = document.getElementById('csrf_token').value;
    options.headers = { ...options.headers, 'X-CSRF-TOKEN': token };
    return fetch(url, options);
}

function showError(message){
    Swal.fire({
        title: 'error',
        text: message,
        icon: 'error',
        confirmButtonColor: '#ff6b6b'
    });
}

async function fetchTrafficAlertThreshold() {
    const parentId = document.getElementById('tenantIdParam').value || '';
    try {
        const res = await fetch(`/monitor/api/traffic/alert?tenantId=`+encodeURIComponent(parentId));
        const result = await res.json();
        alertThresholdGB = result.data?.threshold || 10240;
        document.getElementById('thresholdTraffic').textContent = formatTBorGB(alertThresholdGB);
    } catch (e) {
        console.error('⚠️ 预警阈值加载失败，使用默认10T', e);
        alertThresholdGB = 10240;
        document.getElementById('thresholdTraffic').textContent = formatTBorGB(alertThresholdGB);
    }
}

function renderInstanceCharts(data) {
    const container = $("#instanceCharts");
    container.empty();
    if (!data || data.length === 0) return;

    // 按实例ID分组
    const grouped = {};
    data.forEach(item => {
        if (!grouped[item.instanceId]) {
            grouped[item.instanceId] = [];
        }
        grouped[item.instanceId].push(item);
    });

    Object.keys(grouped).forEach(instanceId => {
        const list = grouped[instanceId].sort((a, b) => new Date(a.timePoint) - new Date(b.timePoint));
        const first = list[0];

        // 卡片
        const card = $(`
            <div class="instance-card">
                <div class="instance-header">
                    <div><strong>`+ first.instanceName+`</strong></div>
                    <div>IP: `+ first.publicIp+`</div>
                </div>
                <div id="chart-`+ instanceId+`" class="instance-chart"></div>
            </div>
        `);
        container.append(card);

        const times = list.map(i => i.timePoint.split(" ")[0]);

        const ingress = list.map(i => (i.ingressBytes / 1024 / 1024).toFixed(2));
        const egress = list.map(i => (i.egressBytes / 1024 / 1024).toFixed(2));

        const chart = echarts.init(document.getElementById(`chart-`+instanceId));
        chart.setOption({
            tooltip: {
                trigger: 'axis',
                axisPointer: { type: 'shadow' }
            },
            legend: { data: [i18n.traffic_in+' (MB)', i18n.traffic_out+' (MB)'] },
            grid: {
                left: '0%',
                right: '0%',
                bottom: '10%',
                top: '15%',
                containLabel: true
            },
            xAxis: {
                type: 'category',
                data: times,
                axisLabel: { rotate: 45 }
            },
            yAxis: {
                type: 'value',
                name: i18n.traffic_flow+' (MB)'
            },
            series: [
                { name: i18n.traffic_in+' (MB)', type: 'bar', barGap: 0, barMaxWidth: 40, data: ingress },
                { name: i18n.traffic_out+' (MB)', type: 'bar', barMaxWidth: 40, data: egress }
            ]
        });

        // 自适应
        window.addEventListener('resize', () => chart.resize());
    });
}

function resetAllCharts() {
    // 折线图
    myChart.setOption({
        xAxis: { data: [] },
        series: [
            { data: [] },
            { data: [] },
            { data: [] }
        ]
    });

    // 统计卡片
    document.getElementById('totalTraffic').textContent = '0 GB';
    document.getElementById('ingressTraffic').textContent = '0 GB';
    document.getElementById('egressTraffic').textContent = '0 GB';

    // 饼图
    updateAlertChart(totalAlertChart, 0, alertThresholdGB);
    updateAlertChart(ingressAlertChart, 0, alertThresholdGB);
    updateAlertChart(egressAlertChart, 0, alertThresholdGB);

    // 实例趋势清空
    document.getElementById('instanceCharts').innerHTML = '';
}




