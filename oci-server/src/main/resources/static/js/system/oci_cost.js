let costTrendChart = null;
let costPieCharts = {};
let costChartData = {};
let costFilterActive = false;
let costPagination = null;
const i18n = window.I18N;

/* ── Theme helpers ── */
function isDarkTheme() {
    return document.documentElement.dataset.theme !== 'light';
}

function getChartTheme() {
    const dark = isDarkTheme();
    return {
        bg:        dark ? '#1a1d27' : '#dfe3e8',
        axisColor: dark ? '#8892a4' : '#666666',
        splitLine: dark ? '#2a2d3a' : '#e5e7eb',
        legend:    dark ? '#e2e8f0' : '#333333',
        tooltip:   dark ? { bg: '#1a1d27', border: '#2a2d3a', textColor: '#e2e8f0' }
                        : { bg: '#ffffff', border: '#e0e0e0', textColor: '#333333' }
    };
}

$(function () {
    const chartDom = document.getElementById('costTrendChart');
    if (chartDom) {
        costTrendChart = echarts.init(chartDom);
    }

    // 初始化空趋势图
    const t = getChartTheme();
    costTrendChart.setOption({
        backgroundColor: t.bg,
        grid: { left: 50, right: 20, top: 40, bottom: 40 },
        xAxis: {
            type: "category",
            data: [],
            axisLine: { lineStyle: { color: t.axisColor } },
            axisTick: { show: false },
            axisLabel: { color: t.axisColor }
        },
        yAxis: {
            type: "value",
            axisLine: { lineStyle: { color: t.axisColor } },
            axisTick: { show: false },
            axisLabel: { color: t.axisColor },
            splitLine: { lineStyle: { color: t.splitLine } }
        },
        series: []
    });

    // 默认选中本月
    const monthBtn = $('.time-presets button[data-preset="month"]')[0];
    if (monthBtn) {
        selectCostTimePreset('month', monthBtn);
    }

    // 自适应
    window.addEventListener('resize', function () {
        if (costTrendChart) costTrendChart.resize();
        Object.values(costPieCharts).forEach(ch => ch.resize());
    });

    // 监听主题切换，重新渲染图表
    const observer = new MutationObserver(function () {
        if (costTrendChart && costChartData.days) {
            changeCostChart("all");
        }
    });
    observer.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme'] });
});

function formatDateYmd(date) {
    const y = date.getFullYear();
    const m = (date.getMonth() + 1).toString().padStart(2, '0');
    const d = date.getDate().toString().padStart(2, '0');
    return `${y}-${m}-${d}`;
}

function selectCostTimePreset(type, btn) {
    $('.time-presets button').removeClass('btn-primary').addClass('btn-outline');

    if (btn) {
        $(btn).removeClass('btn-outline').addClass('btn-primary');
    }

    const now = new Date();
    const $rangePicker = $('#costDateRangePicker');
    const $start = $('#costStartDate');
    const $end = $('#costEndDate');

    if (type === 'today') {
        $rangePicker.hide();
        const s = formatDateYmd(now);
        $start.val(s);
        $end.val(s);

    } else if (type === 'month') {
        $rangePicker.hide();
        const first = new Date(now.getFullYear(), now.getMonth(), 1);
        $start.val(formatDateYmd(first));
        $end.val(formatDateYmd(now));

    } else {
        $rangePicker.show();
    }
}

function onCostQuery() {
    const tenantId = $('#tenantIdParam').val();
    const startDate = $('#costStartDate').val();
    const endDate = $('#costEndDate').val();
    if (!startDate || !endDate) {
        return Swal.fire('warning', i18n.cost_plzTimeRange, 'warning');
    }

    showLoading("loading");

    $.ajax({
        url: "/cost/query",
        method: "POST",
        contentType: "application/json",
        headers: { "X-CSRF-TOKEN": $('#csrf_token').val() },
        data: JSON.stringify({ tenantId, startDate, endDate }),
        success: (res) => {
            hideLoading();
            if (!res || !res.success) {
                showError();
                return;
            }
            renderCostResult(res.data || []);
        },
        error: () => {
            hideLoading();
            showError();
        }
    });
}

function renderCostResult(list) {

    window._rawCostList = list;

    let total = 0, compute = 0, storage = 0, network = 0, other = 0;

    list.forEach((item) => {
        const c = Number(item.cost || 0);
        total += c;

        const t = (item.resourceType || '').toLowerCase();

        if (t === "instance") compute += c;
        else if (t === "boot-volume" || t === "block-volume") storage += c;
        else if (t === "vnic") network += c;
        else other += c;
    });
    animateNumber(document.getElementById("totalCost"), 0, total);
    animateNumber(document.getElementById("computeCost"), 0, compute);
    animateNumber(document.getElementById("storageCost"), 0, storage);
    animateNumber(document.getElementById("networkCost"), 0, network);
    animateNumber(document.getElementById("otherCost"), 0, other);


    // 饼图
    /*renderMiniPie("pie_total", total);
    renderMiniPie("pie_compute", compute);
    renderMiniPie("pie_storage", storage);
    renderMiniPie("pie_network", network);
    renderMiniPie("pie_other", other);*/

    // 构造折线图的数据
    costChartData = {
        days: [],
        compute: {},
        storage: {},
        network: {},
        other: {}
    };

    // 按日期累加
    list.forEach((item) => {
        const d = item.day;
        const c = Number(item.cost || 0);
        const t = (item.resourceType || "").toLowerCase();

        // 初始化
        if (!(d in costChartData.compute)) {
            costChartData.compute[d] = 0;
            costChartData.storage[d] = 0;
            costChartData.network[d] = 0;
            costChartData.other[d] = 0;
        }

        // 归类
        if (t === "instance") costChartData.compute[d] += c;
        else if (t === "boot-volume" || t === "block-volume") costChartData.storage[d] += c;
        else if (t === "vnic") costChartData.network[d] += c;
        else costChartData.other[d] += c;
    });

    // 日期排序
    const allDays = Object.keys(costChartData.compute)
        .sort((a, b) => new Date(a) - new Date(b));

    costChartData.days = allDays;

    // 渲染折线图
    changeCostChart("all");

    // 明细表（使用客户端分页）
    _initCostPagination();
    costPagination.setData(list);
}

function renderMiniPie(id, value) {
    const el = document.getElementById(id);
    if (!el) return;

    const percent = Math.min(value / 1000, 1);
    const chart = echarts.init(el);

    chart.setOption({
        series: [{
            type: "pie",
            radius: [18, 25],
            label: { show: false },
            data: [
                { value: percent, itemStyle: { color: "#4a73ff" } },
                { value: 1 - percent, itemStyle: { color: "#e0e0e0" } }
            ]
        }]
    });

    window.addEventListener("resize", () => chart.resize());
}

function changeCostChart(type) {
    if (!costTrendChart) return;

    const days = costChartData.days;
    const valuesOf = (map) => days.map(d => Number(map[d].toFixed(6)));

    const colors = {
        compute: "#4a73ff",
        storage: "#ff9f40",
        network: "#1abc9c",
        other: "#6b7280"
    };

    // 按钮样式
    const order = ["all", "compute", "storage", "network", "other"];
    const $btns = $('.chart-switch button');
    $btns.removeClass('btn-primary').addClass('btn-outline');
    const idx = order.indexOf(type);
    if (idx >= 0) $btns.eq(idx).removeClass('btn-outline').addClass('btn-primary');

    let series = [];

    if (type === "all") {
        series = [
            { name: i18n.cost_cal+" ", type: "line", smooth: true, symbol: "circle", itemStyle: { color: colors.compute },lineStyle: { width: 4.5 },  data: valuesOf(costChartData.compute) },
            { name: i18n.cost_save+" ", type: "line", smooth: true, symbol: "circle", itemStyle: { color: colors.storage },lineStyle: { width: 4.5 },  data: valuesOf(costChartData.storage) },
            { name: i18n.cost_net+" ", type: "line", smooth: true, symbol: "circle", itemStyle: { color: colors.network },lineStyle: { width: 4.5 },  data: valuesOf(costChartData.network) },
            { name: i18n.cost_other+" ", type: "line", smooth: true, symbol: "circle", itemStyle: { color: colors.other },lineStyle: { width: 4.5 },  data: valuesOf(costChartData.other) }
        ];
    } else {
        series = [
            {
                name: {
                    compute: i18n.cost_cal,
                    storage: i18n.cost_save,
                    network: i18n.cost_net,
                    other: i18n.cost_other
                }[type],
                type: "line",
                smooth: true,
                symbol: "circle",
                itemStyle: { color: colors[type] },
                lineStyle: { width: 4.5 },
                data: valuesOf(costChartData[type])
            }
        ];
    }

    const t = getChartTheme();
    costTrendChart.setOption({
        backgroundColor: t.bg,
        tooltip: {
            trigger: "axis",
            backgroundColor: t.tooltip.bg,
            borderColor: t.tooltip.border,
            textStyle: { color: t.tooltip.textColor }
        },
        legend: {
            show: type === "all",
            textStyle: { color: t.legend }
        },
        grid: { left: 50, right: 20, top: 50, bottom: 40 },
        xAxis: {
            type: "category",
            data: days,
            axisLine: { lineStyle: { color: t.axisColor } },
            axisTick: { show: false },
            axisLabel: { color: t.axisColor }
        },
        yAxis: {
            type: "value",
            name: "USD",
            nameTextStyle: { color: t.axisColor },
            axisLine: { lineStyle: { color: t.axisColor } },
            axisTick: { show: false },
            axisLabel: { color: t.axisColor },
            splitLine: { lineStyle: { color: t.splitLine } }
        },
        series
    });
}

function escapeHtml(str) {
    if (!str) return "";
    return String(str)
        .replace(/&/g, "&amp;")
        .replace(/</g, "&lt;")
        .replace(/>/g, "&gt;");
}

function animateNumber(el, from, to, duration = 800) {
    const frameRate = 60;
    const totalFrames = Math.round(duration / (1000 / frameRate));
    let currentFrame = 0;

    const diff = to - from;

    const timer = setInterval(() => {
        currentFrame++;
        const progress = currentFrame / totalFrames;

        // ease-out 效果
        const ease = 1 - Math.pow(1 - progress, 3);

        const value = from + diff * ease;

        el.textContent = "$" + value.toFixed(4);

        if (currentFrame >= totalFrames) {
            clearInterval(timer);
            el.textContent = "$" + to.toFixed(4); // 保证准确
        }
    }, 1000 / frameRate);
}

function _initCostPagination() {
    if (costPagination) return;
    costPagination = new ClientPagination({
        tbodyEl: '#costTableBody',
        paginationEl: '#costPagination',
        pageSize: 20,
        emptyHtml: `<tr><td colspan="5" style="text-align:center;color:var(--text-secondary);padding:16px;">${i18n.common_noData}</td></tr>`,
        renderRow: (item) => {
            const cost = Number(item.cost || 0);
            const cls = cost > 0 ? 'cost-positive' : '';
            return `<tr class="${cls}">
                <td class="col-date">${item.day}</td>
                <td>${escapeHtml(item.resourceType)}</td>
                <td>${escapeHtml(item.skuName)}</td>
                <td class="mono-text">${escapeHtml(item.resourceId)}</td>
                <td>$${cost.toFixed(6)}</td>
            </tr>`;
        }
    });
}

function toggleCostFilter() {
    costFilterActive = !costFilterActive;
    const btn = document.getElementById("togglePositiveFilter");
    if (costFilterActive) {
        btn.innerHTML = '<i class="fas fa-filter"></i> ' + i18n.cost_showAll;
        const filtered = window._rawCostList.filter(item => Number(item.cost || 0) > 0);
        costPagination.setData(filtered);
    } else {
        btn.innerHTML = '<i class="fas fa-filter"></i> ' + i18n.cost_costCondition;
        costPagination.setData(window._rawCostList);
    }
}

function showError(){
    Swal.fire({
        title: 'error',
        text: i18n.common_network_error,
        icon: 'error',
        confirmButtonColor: '#ff6b6b'
    });
}
