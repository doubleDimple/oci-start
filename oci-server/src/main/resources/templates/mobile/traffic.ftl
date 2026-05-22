<#import "layout.ftl" as layout>
<@layout.page title="流量查询" activePage="traffic">

<style>
/* ── 自定义下拉 ───────── */
.mob-csel-wrap { position:relative }
.mob-csel-trigger {
    display:flex;align-items:center;justify-content:space-between;
    padding:9px 12px;border-radius:8px;border:1.5px solid var(--mob-border);
    background:var(--mob-surface);color:var(--mob-text);font-size:13px;
    cursor:pointer;user-select:none;min-height:38px
}
.mob-csel-trigger .mob-csel-arrow { transition:transform .2s;color:var(--mob-text-muted);font-size:11px;margin-left:8px;flex-shrink:0 }
.mob-csel-trigger.open .mob-csel-arrow { transform:rotate(180deg) }
.mob-csel-trigger .mob-csel-val { flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap }
.mob-csel-panel {
    display:none;position:absolute;top:calc(100% + 4px);left:0;right:0;
    background:var(--mob-surface);border:1.5px solid var(--mob-border);
    border-radius:10px;box-shadow:0 6px 24px rgba(0,0,0,0.18);z-index:200;
    max-height:240px;overflow-y:auto
}
.mob-csel-panel.open { display:block }
.mob-csel-option {
    display:flex;align-items:center;gap:10px;padding:11px 14px;
    font-size:13px;color:var(--mob-text);cursor:pointer;transition:background .12s
}
.mob-csel-option:hover { background:rgba(91,138,240,0.08) }
.mob-csel-option.selected { background:rgba(91,138,240,0.12);color:#5b8af0;font-weight:600 }
.mob-csel-option .mob-csel-check {
    width:18px;height:18px;border-radius:4px;border:1.5px solid var(--mob-border);
    display:flex;align-items:center;justify-content:center;flex-shrink:0;font-size:11px
}
.mob-csel-option.selected .mob-csel-check { background:#5b8af0;border-color:#5b8af0;color:#fff }
html[data-theme="light"] .mob-csel-trigger { background:#fff }
html[data-theme="light"] .mob-csel-panel { background:#fff }

/* ── 统计卡片（一行横排）───── */
.mob-tf-stat4 {
    display:flex;gap:8px;margin-bottom:12px;
    overflow-x:auto;padding-bottom:2px;
    -webkit-overflow-scrolling:touch;scrollbar-width:none
}
.mob-tf-stat4::-webkit-scrollbar { display:none }
.mob-tf-stat4-card {
    background:var(--mob-card);border-radius:12px;padding:10px 8px;
    display:flex;flex-direction:column;align-items:center;text-align:center;
    flex:1;min-width:76px;
    border:1px solid var(--mob-border)
}
.mob-tf-stat4-icon { font-size:15px;margin-bottom:5px }
.mob-tf-stat4-val  { font-size:12px;font-weight:700;color:var(--mob-text);line-height:1.2;white-space:nowrap }
.mob-tf-stat4-lbl  { font-size:10px;color:var(--mob-text-muted);margin-top:2px;white-space:nowrap }

/* ── 组合圆环图 ───── */
.mob-tf-donut-card {
    background:var(--mob-card);border-radius:12px;padding:14px;margin-bottom:12px;
    border:1px solid var(--mob-border)
}
.mob-tf-donut-svg  { transform:rotate(-90deg);display:block }
.mob-tf-donut-ctr  {
    position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);
    text-align:center;line-height:1.3;pointer-events:none
}
.mob-tf-donut-row  { display:flex;align-items:center;justify-content:space-between;margin-bottom:8px }
.mob-tf-donut-row:last-child { margin-bottom:0 }
.mob-tf-donut-dot  { width:10px;height:10px;border-radius:2px;display:inline-block;margin-right:5px;flex-shrink:0 }

/* ── 趋势图 canvas ───── */
.mob-tf-chart-card {
    background:var(--mob-card);border-radius:12px;padding:12px;margin-bottom:12px;
    border:1px solid var(--mob-border)
}
.mob-tf-chart-title { font-size:13px;font-weight:700;color:var(--mob-text);margin-bottom:10px }
.mob-tf-chart-legend { display:flex;gap:12px;margin-bottom:8px;flex-wrap:wrap }
.mob-tf-legend-dot  { display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:4px }
.mob-tf-legend-item { font-size:11px;color:var(--mob-text-muted);display:flex;align-items:center }

/* ── 实例圆环卡片 ───── */
.mob-tf-ins-wrap {
    background:var(--mob-card);border-radius:12px;padding:12px;margin-bottom:12px;
    border:1px solid var(--mob-border)
}
.mob-tf-ins-grid { display:grid;grid-template-columns:1fr 1fr;gap:10px }
.mob-tf-ins-ring-card {
    background:var(--mob-bg);border-radius:10px;padding:12px 8px;
    display:flex;flex-direction:column;align-items:center;
    border:1px solid var(--mob-border)
}
.mob-tf-ins-ring-svg { transform:rotate(-90deg);display:block }
</style>

<!-- 返回按钮 -->
<#if tenantId?has_content>
<div style="display:flex;align-items:center;gap:12px;margin-bottom:16px">
    <button onclick="window.location.href='/m/tenants?menuId='+encodeURIComponent(_tfTenantId)" style="width:36px;height:36px;border-radius:50%;border:1.5px solid var(--mob-border);background:var(--mob-card);color:var(--mob-text);display:flex;align-items:center;justify-content:center;cursor:pointer;flex-shrink:0;padding:0">
        <i class="fas fa-chevron-left" style="font-size:13px"></i>
    </button>
    <div style="flex:1;min-width:0">
        <div style="font-size:16px;font-weight:700;color:var(--mob-text)">流量查询</div>
    </div>
</div>
</#if>

<!-- 查询条件 -->
<div class="mob-card" style="margin-bottom:12px">
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:10px">
        <div>
            <div style="font-size:11px;color:var(--mob-text-muted);margin-bottom:4px">开始日期</div>
            <input type="date" id="tfStartDate" class="mob-tf-input" value="">
        </div>
        <div>
            <div style="font-size:11px;color:var(--mob-text-muted);margin-bottom:4px">结束日期</div>
            <input type="date" id="tfEndDate" class="mob-tf-input" value="">
        </div>
    </div>
    <div style="margin-bottom:10px">
        <div style="font-size:11px;color:var(--mob-text-muted);margin-bottom:4px">统计粒度</div>
        <div style="display:flex;gap:6px">
            <button class="mob-tf-period-btn active" data-period="ONE_DAY" onclick="selectPeriod(this)">日</button>
            <button class="mob-tf-period-btn" data-period="ONE_HOUR" onclick="selectPeriod(this)">小时</button>
            <button class="mob-tf-period-btn" data-period="FIVE_MINUTES" onclick="selectPeriod(this)">5分钟</button>
        </div>
    </div>
    <div id="regionSelectorWrap" style="display:none;margin-bottom:10px">
        <div style="font-size:11px;color:var(--mob-text-muted);margin-bottom:4px">区域筛选（可多选）</div>
        <div class="mob-csel-wrap" id="tfRegionSelWrap">
            <div class="mob-csel-trigger" id="tfRegionTrigger" onclick="tfToggleSel()">
                <span class="mob-csel-val" id="tfRegionLabel">全部区域</span>
                <i class="fas fa-chevron-down mob-csel-arrow"></i>
            </div>
            <div class="mob-csel-panel" id="tfRegionPanel"></div>
        </div>
    </div>
    <button class="mob-btn mob-btn-primary" style="width:100%" onclick="queryTraffic()">
        <i class="fas fa-search" style="margin-right:6px"></i>查询流量
    </button>
</div>

<!-- 加载状态 -->
<div id="tfLoading" class="mob-loading" style="display:none">
    <div class="mob-spinner"></div>
    <p>查询中…</p>
</div>

<!-- ── 统计卡片（一行）── -->
<div class="mob-tf-stat4" id="tfStat4" style="display:none">
    <div class="mob-tf-stat4-card">
        <div class="mob-tf-stat4-icon" style="color:#5b8af0"><i class="fas fa-chart-area"></i></div>
        <div class="mob-tf-stat4-val" id="tfTotalTraffic">0 B</div>
        <div class="mob-tf-stat4-lbl">总流量</div>
    </div>
    <div class="mob-tf-stat4-card">
        <div class="mob-tf-stat4-icon" style="color:#43b581"><i class="fas fa-arrow-down"></i></div>
        <div class="mob-tf-stat4-val" style="color:#43b581" id="tfInTraffic">0 B</div>
        <div class="mob-tf-stat4-lbl">入站</div>
    </div>
    <div class="mob-tf-stat4-card">
        <div class="mob-tf-stat4-icon" style="color:#f04747"><i class="fas fa-arrow-up"></i></div>
        <div class="mob-tf-stat4-val" style="color:#f04747" id="tfOutTraffic">0 B</div>
        <div class="mob-tf-stat4-lbl">出站</div>
    </div>
    <div class="mob-tf-stat4-card">
        <div class="mob-tf-stat4-icon" style="color:#e67e22"><i class="fas fa-bell"></i></div>
        <div class="mob-tf-stat4-val" style="color:#e67e22" id="tfThreshold">—</div>
        <div class="mob-tf-stat4-lbl">阈值</div>
    </div>
</div>

<!-- ── 组合圆环图（阈值使用量）── -->
<div class="mob-tf-donut-card" id="tfDonutCard" style="display:none">
    <div class="mob-tf-chart-title" style="margin-bottom:14px">
        <i class="fas fa-circle-notch" style="margin-right:6px;color:#5b8af0"></i>阈值使用量
    </div>
    <div style="display:flex;align-items:center;gap:18px">
        <!-- SVG 圆环 -->
        <div style="position:relative;width:110px;height:110px;flex-shrink:0">
            <svg class="mob-tf-donut-svg" width="110" height="110" viewBox="0 0 36 36">
                <!-- 底层轨道 -->
                <circle cx="18" cy="18" r="15.9" fill="none" stroke="rgba(128,128,128,0.12)" stroke-width="4.2"/>
                <!-- 入站弧（绿） -->
                <circle id="donutArcIn" cx="18" cy="18" r="15.9" fill="none" stroke="#43b581" stroke-width="4.2"
                    stroke-dasharray="0 100" stroke-dashoffset="0" stroke-linecap="butt"
                    style="transition:stroke-dasharray .7s ease,stroke-dashoffset .7s ease"/>
                <!-- 出站弧（红） -->
                <circle id="donutArcOut" cx="18" cy="18" r="15.9" fill="none" stroke="#f04747" stroke-width="4.2"
                    stroke-dasharray="0 100" stroke-dashoffset="0" stroke-linecap="butt"
                    style="transition:stroke-dasharray .7s ease,stroke-dashoffset .7s ease"/>
            </svg>
            <div class="mob-tf-donut-ctr">
                <div id="donutPctLabel" style="font-size:16px;font-weight:800;color:#43b581;line-height:1">0%</div>
                <div style="font-size:9px;color:var(--mob-text-muted);margin-top:2px">已使用</div>
            </div>
        </div>
        <!-- 数值面板 -->
        <div style="flex:1;min-width:0">
            <div class="mob-tf-donut-row">
                <span style="font-size:12px;color:var(--mob-text-muted);display:flex;align-items:center">
                    <span class="mob-tf-donut-dot" style="background:#43b581"></span>入站
                </span>
                <span id="donutInVal" style="font-size:12px;font-weight:700;color:#43b581">—</span>
            </div>
            <div class="mob-tf-donut-row">
                <span style="font-size:12px;color:var(--mob-text-muted);display:flex;align-items:center">
                    <span class="mob-tf-donut-dot" style="background:#f04747"></span>出站
                </span>
                <span id="donutOutVal" style="font-size:12px;font-weight:700;color:#f04747">—</span>
            </div>
            <div class="mob-tf-donut-row" style="border-top:1px solid var(--mob-border);padding-top:8px;margin-top:4px">
                <span style="font-size:11px;color:var(--mob-text-muted)">预警阈值</span>
                <span id="donutThreshVal" style="font-size:11px;font-weight:600;color:#e67e22">—</span>
            </div>
            <div class="mob-tf-donut-row">
                <span style="font-size:11px;color:var(--mob-text-muted)">剩余容量</span>
                <span id="donutRemVal" style="font-size:11px;color:var(--mob-text-muted)">—</span>
            </div>
        </div>
    </div>
</div>

<!-- ── 流量趋势折线图 ── -->
<div class="mob-tf-chart-card" id="tfTrendCard" style="display:none">
    <div class="mob-tf-chart-title"><i class="fas fa-chart-line" style="margin-right:6px;color:#5b8af0"></i>流量趋势</div>
    <div class="mob-tf-chart-legend">
        <span class="mob-tf-legend-item"><span class="mob-tf-legend-dot" style="background:#43b581"></span>入站</span>
        <span class="mob-tf-legend-item"><span class="mob-tf-legend-dot" style="background:#f04747"></span>出站</span>
        <span class="mob-tf-legend-item"><span class="mob-tf-legend-dot" style="background:#5b8af0"></span>总计</span>
    </div>
    <canvas id="tfTrendCanvas" style="width:100%;display:block"></canvas>
</div>

<!-- ── 实例流量 ── -->
<div class="mob-tf-ins-wrap" id="tfInstanceSection" style="display:none">
    <div class="mob-tf-chart-title">
        <i class="fas fa-server" style="margin-right:6px;color:#5b8af0"></i>实例流量
        <span style="font-size:10px;color:var(--mob-text-muted);font-weight:400;margin-left:6px">外圈=总量 中圈=入站 内圈=出站</span>
    </div>
    <div class="mob-tf-ins-grid" id="tfInstanceList"></div>
</div>

<script>
var _tfTenantId = '${tenantId!}';
var _tfPeriod   = 'ONE_DAY';
var _tfThreshGB = 10240; // default 10TB in GB
</script>
<#noparse>
<script>
(function() {
    /* ── 日期初始化 ── */
    var now   = new Date();
    var end   = now.toISOString().split('T')[0];
    var start = new Date(now - 7*24*3600*1000).toISOString().split('T')[0];
    document.getElementById('tfStartDate').value = start;
    document.getElementById('tfEndDate').value   = end;

    window.selectPeriod = function(btn) {
        document.querySelectorAll('.mob-tf-period-btn').forEach(function(b) { b.classList.remove('active'); });
        btn.classList.add('active');
        _tfPeriod = btn.dataset.period;
    };

    /* ── 区域多选 ── */
    var _tfSelRegions = [];
    var _tfAllRegions = [];

    function tfBuildPanel() {
        var panel = document.getElementById('tfRegionPanel');
        var allSel = _tfSelRegions.length === 0;
        var html = '<div class="mob-csel-option' + (allSel ? ' selected' : '') + '" onclick="tfSelectAll()">'
            + '<span class="mob-csel-check">' + (allSel ? '<i class="fas fa-check"></i>' : '') + '</span>'
            + '全部区域</div>';
        _tfAllRegions.forEach(function(r) {
            var sel = _tfSelRegions.indexOf(r.id) >= 0;
            html += '<div class="mob-csel-option' + (sel ? ' selected' : '') + '" onclick="tfToggleRegion(\'' + r.id.replace(/'/g,"\\'") + '\')">'
                + '<span class="mob-csel-check">' + (sel ? '<i class="fas fa-check"></i>' : '') + '</span>'
                + escHtml(r.label) + '</div>';
        });
        panel.innerHTML = html;
    }
    function tfUpdateLabel() {
        var label = document.getElementById('tfRegionLabel');
        if (_tfSelRegions.length === 0) label.textContent = '全部区域';
        else if (_tfSelRegions.length === 1) {
            var r = _tfAllRegions.find(function(x){ return x.id === _tfSelRegions[0]; });
            label.textContent = r ? r.label : '1 个区域';
        } else {
            label.textContent = '已选 ' + _tfSelRegions.length + ' 个区域';
        }
    }
    window.tfToggleSel = function() {
        var trigger = document.getElementById('tfRegionTrigger');
        var panel   = document.getElementById('tfRegionPanel');
        var open = panel.classList.toggle('open');
        trigger.classList.toggle('open', open);
    };
    window.tfSelectAll = function() { _tfSelRegions = []; tfUpdateLabel(); tfBuildPanel(); };
    window.tfToggleRegion = function(id) {
        var idx = _tfSelRegions.indexOf(id);
        if (idx >= 0) _tfSelRegions.splice(idx, 1);
        else          _tfSelRegions.push(id);
        tfUpdateLabel(); tfBuildPanel();
    };
    document.addEventListener('click', function(e) {
        var wrap = document.getElementById('tfRegionSelWrap');
        if (wrap && !wrap.contains(e.target)) {
            document.getElementById('tfRegionPanel').classList.remove('open');
            document.getElementById('tfRegionTrigger').classList.remove('open');
        }
    });

    if (_tfTenantId) {
        fetch('/m/api/tenants/' + encodeURIComponent(_tfTenantId) + '/regions').then(function(r) { return r.json(); })
        .then(function(json) {
            var regions = json.data || [];
            if (regions.length > 1) {
                _tfAllRegions = regions.map(function(r) {
                    return { id: r.id || r.tenantId || '', label: r.region || r.regionName || r.tenantId || '' };
                });
                tfBuildPanel();
                document.getElementById('regionSelectorWrap').style.display = '';
            }
        }).catch(function() {});
    }

    /* ── 预警阈值 ── */
    function fetchThreshold() {
        var parentId = _tfTenantId || '';
        return fetch('/monitor/api/traffic/alert?tenantId=' + encodeURIComponent(parentId))
            .then(function(r) { return r.json(); })
            .then(function(result) {
                _tfThreshGB = (result.data && result.data.threshold) ? result.data.threshold : 10240;
                document.getElementById('tfThreshold').textContent = fmtGB(_tfThreshGB * 1024 * 1024 * 1024);
            }).catch(function() {
                _tfThreshGB = 10240;
                document.getElementById('tfThreshold').textContent = fmtGB(_tfThreshGB * 1024 * 1024 * 1024);
            });
    }

    /* ── 查询 ── */
    window.queryTraffic = async function() {
        var startDate = document.getElementById('tfStartDate').value;
        var endDate   = document.getElementById('tfEndDate').value;
        if (!startDate || !endDate) { mobTfToast('请选择日期范围', 'warn'); return; }

        document.getElementById('tfLoading').style.display         = '';
        document.getElementById('tfStat4').style.display           = 'none';
        document.getElementById('tfDonutCard').style.display       = 'none';
        document.getElementById('tfTrendCard').style.display       = 'none';
        document.getElementById('tfInstanceSection').style.display = 'none';

        try {
            var csrf = (document.querySelector('meta[name="_csrf"]')||{}).content||'';
            var body = { period: _tfPeriod, startDate: startDate, endDate: endDate };
            if (_tfSelRegions && _tfSelRegions.length > 0) body.tenantIds = _tfSelRegions;
            else if (_tfTenantId)                          body.tenantIds = [_tfTenantId];

            await fetchThreshold();

            var res  = await fetch('/monitor/api/instances/traffic', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
                body: JSON.stringify(body)
            });
            var data = await res.json();
            renderTraffic(Array.isArray(data) ? data : (data.data || []));
        } catch(e) {
            document.getElementById('tfLoading').style.display = 'none';
            document.getElementById('tfInstanceList').innerHTML =
                '<p style="text-align:center;color:#f04747;padding:24px">查询失败: ' + escHtml(e.message) + '</p>';
            document.getElementById('tfInstanceSection').style.display = '';
        }
    };

    /* ── 渲染 ── */
    function renderTraffic(list) {
        document.getElementById('tfLoading').style.display = 'none';

        if (!list || list.length === 0) {
            document.getElementById('tfInstanceSection').style.display = '';
            document.getElementById('tfInstanceList').innerHTML =
                '<div style="text-align:center;padding:40px 0">'
                + '<i class="fas fa-chart-bar" style="font-size:48px;opacity:0.2;display:block;margin-bottom:12px"></i>'
                + '<p style="color:var(--mob-text-muted)">暂无流量数据</p></div>';
            return;
        }

        /* 1. 汇总 */
        var totalIn = 0, totalOut = 0;
        list.forEach(function(item) {
            totalIn  += Number(item.ingressBytes)  || 0;
            totalOut += Number(item.egressBytes)   || 0;
        });
        var totalAll = totalIn + totalOut;

        document.getElementById('tfTotalTraffic').textContent = fmtGB(totalAll);
        document.getElementById('tfInTraffic').textContent    = fmtGB(totalIn);
        document.getElementById('tfOutTraffic').textContent   = fmtGB(totalOut);
        document.getElementById('tfStat4').style.display      = '';

        /* 2. 组合圆环图 */
        var threshBytes = _tfThreshGB * 1024 * 1024 * 1024;
        updateDonut(totalIn, totalOut, threshBytes);

        /* 3. 趋势折线图 —— timePoint 按粒度截取不同精度 */
        var hasTrend = list.some(function(i) { return i.timePoint; });
        if (hasTrend) {
            var bucket = {};
            list.forEach(function(item) {
                if (!item.timePoint) return;
                var ts = String(item.timePoint).replace(' ', 'T'); // 统一 ISO 格式
                var tp;
                if (_tfPeriod === 'ONE_DAY') {
                    tp = ts.substring(0, 10);          // YYYY-MM-DD
                } else if (_tfPeriod === 'ONE_HOUR') {
                    tp = ts.substring(0, 13);          // YYYY-MM-DDTHH
                } else {
                    tp = ts.substring(0, 16);          // YYYY-MM-DDTHH:mm
                }
                if (!bucket[tp]) bucket[tp] = { in: 0, out: 0 };
                bucket[tp].in  += Number(item.ingressBytes) || 0;
                bucket[tp].out += Number(item.egressBytes)  || 0;
            });
            var times    = Object.keys(bucket).sort();
            var inSeries = times.map(function(t) { return bucket[t].in;  });
            var outSeries= times.map(function(t) { return bucket[t].out; });
            var totSeries= times.map(function(t) { return bucket[t].in + bucket[t].out; });
            document.getElementById('tfTrendCard').style.display = '';
            setTimeout(function() {
                drawTrendChart('tfTrendCanvas', times, inSeries, outSeries, totSeries);
            }, 80);
        }

        /* 4. 实例圆环图（3 同心环：外=总蓝 中=入绿 内=出红） */
        var grouped = {};
        list.forEach(function(item) {
            var id = item.instanceId || item.displayName || 'unknown';
            if (!grouped[id]) {
                grouped[id] = { in: 0, out: 0,
                    name: item.instanceName || item.displayName || id,
                    ip: item.publicIps || item.publicIp || '',
                    region: item.region || '',
                    state: item.state || '' };
            }
            grouped[id].in  += Number(item.ingressBytes) || 0;
            grouped[id].out += Number(item.egressBytes)  || 0;
        });

        var maxTot = 0;
        Object.keys(grouped).forEach(function(id) {
            maxTot = Math.max(maxTot, grouped[id].in + grouped[id].out);
        });

        // 计算同心环 stroke-dasharray（各圆周长不同需分别计算）
        function ringDash(pct, r) {
            var circ = 2 * Math.PI * r;
            var fill = circ * Math.min(100, pct) / 100;
            return fill.toFixed(2) + ' ' + (circ - fill).toFixed(2);
        }

        var insHtml = '';
        Object.keys(grouped).forEach(function(id, idx) {
            var g      = grouped[id];
            var total  = g.in + g.out;
            var totPct = maxTot > 0 ? total  / maxTot * 100 : 0;
            var inPct  = maxTot > 0 ? g.in   / maxTot * 100 : 0;
            var outPct = maxTot > 0 ? g.out  / maxTot * 100 : 0;
            var stateOk = g.state === 'RUNNING' || g.state === 'running';
            var sub = [g.ip, g.region].filter(Boolean).join(' · ');

            insHtml += '<div class="mob-tf-ins-ring-card">'
                // 3 同心环 SVG
                + '<div style="position:relative;width:84px;height:84px;margin-bottom:8px">'
                + '<svg class="mob-tf-ins-ring-svg" width="84" height="84" viewBox="0 0 36 36">'
                // 外环轨道 + 填充（总量，蓝）
                + '<circle cx="18" cy="18" r="15.9" fill="none" stroke="rgba(128,128,128,0.1)" stroke-width="2.8"/>'
                + '<circle cx="18" cy="18" r="15.9" fill="none" stroke="#5b8af0" stroke-width="2.8"'
                +   ' stroke-dasharray="' + ringDash(totPct, 15.9) + '" stroke-linecap="round"'
                +   ' style="transition:stroke-dasharray .7s ease"/>'
                // 中环轨道 + 填充（入站，绿）
                + '<circle cx="18" cy="18" r="11.2" fill="none" stroke="rgba(128,128,128,0.1)" stroke-width="2.8"/>'
                + '<circle cx="18" cy="18" r="11.2" fill="none" stroke="#43b581" stroke-width="2.8"'
                +   ' stroke-dasharray="' + ringDash(inPct, 11.2) + '" stroke-linecap="round"'
                +   ' style="transition:stroke-dasharray .7s ease"/>'
                // 内环轨道 + 填充（出站，红）
                + '<circle cx="18" cy="18" r="6.5" fill="none" stroke="rgba(128,128,128,0.1)" stroke-width="2.8"/>'
                + '<circle cx="18" cy="18" r="6.5" fill="none" stroke="#f04747" stroke-width="2.8"'
                +   ' stroke-dasharray="' + ringDash(outPct, 6.5) + '" stroke-linecap="round"'
                +   ' style="transition:stroke-dasharray .7s ease"/>'
                + '</svg>'
                // 中心状态点
                + '<div style="position:absolute;top:50%;left:50%;transform:translate(-50%,-50%);'
                +   'width:7px;height:7px;border-radius:50%;background:' + (stateOk ? '#43b581' : '#aaa') + '"></div>'
                + '</div>'
                // 实例名
                + '<div style="font-size:11px;font-weight:700;color:var(--mob-text);text-align:center;'
                +   'overflow:hidden;text-overflow:ellipsis;white-space:nowrap;width:100%;margin-bottom:3px">'
                + escHtml(g.name) + '</div>'
                // 副标题
                + (sub ? '<div style="font-size:9px;color:var(--mob-text-muted);text-align:center;'
                +   'overflow:hidden;text-overflow:ellipsis;white-space:nowrap;width:100%;margin-bottom:6px">'
                + escHtml(sub) + '</div>' : '<div style="margin-bottom:6px"></div>')
                // 3 行数值
                + '<div style="font-size:10px;width:100%">'
                + '<div style="display:flex;justify-content:space-between;margin-bottom:2px">'
                +   '<span style="color:#5b8af0">总</span><span style="color:var(--mob-text)">' + fmtGB(total) + '</span></div>'
                + '<div style="display:flex;justify-content:space-between;margin-bottom:2px">'
                +   '<span style="color:#43b581">入</span><span style="color:var(--mob-text)">' + fmtGB(g.in)  + '</span></div>'
                + '<div style="display:flex;justify-content:space-between">'
                +   '<span style="color:#f04747">出</span><span style="color:var(--mob-text)">' + fmtGB(g.out) + '</span></div>'
                + '</div>'
                + '</div>';
        });
        document.getElementById('tfInstanceList').innerHTML = insHtml;
        document.getElementById('tfInstanceSection').style.display = '';
    }

    /* ── 组合圆环图更新 ── */
    function updateDonut(totalIn, totalOut, threshBytes) {
        var inPct   = threshBytes > 0 ? Math.min(100, totalIn  / threshBytes * 100) : 0;
        var outPct  = threshBytes > 0 ? Math.min(100, totalOut / threshBytes * 100) : 0;
        var usedPct = Math.min(100, inPct + outPct);

        var arcIn  = document.getElementById('donutArcIn');
        var arcOut = document.getElementById('donutArcOut');
        var pctLbl = document.getElementById('donutPctLabel');

        if (arcIn) {
            arcIn.style.strokeDasharray  = inPct.toFixed(2) + ' ' + (100 - inPct).toFixed(2);
            arcIn.style.strokeDashoffset = '0';
        }
        if (arcOut) {
            arcOut.style.strokeDasharray  = outPct.toFixed(2) + ' ' + (100 - outPct).toFixed(2);
            arcOut.style.strokeDashoffset = (-inPct).toFixed(2);
        }
        if (pctLbl) {
            pctLbl.textContent = usedPct.toFixed(1) + '%';
            pctLbl.style.color = usedPct >= 90 ? '#f04747' : usedPct >= 70 ? '#e67e22' : '#43b581';
        }

        var totalAll = totalIn + totalOut;
        document.getElementById('donutInVal').textContent    = fmtGB(totalIn);
        document.getElementById('donutOutVal').textContent   = fmtGB(totalOut);
        document.getElementById('donutThreshVal').textContent = fmtGB(threshBytes);
        document.getElementById('donutRemVal').textContent   = fmtGB(Math.max(0, threshBytes - totalAll));
        document.getElementById('tfDonutCard').style.display = '';
    }

    /* ── 趋势折线图 (Canvas) ── */
    function drawTrendChart(canvasId, times, inSeries, outSeries, totSeries) {
        var canvas = document.getElementById(canvasId);
        if (!canvas) return;
        var dpr = window.devicePixelRatio || 1;
        // 读取 canvas 自身的 CSS 宽度（已设 width:100%），避免把父 padding 算进去
        var W   = canvas.offsetWidth || (canvas.parentElement.clientWidth - 24);
        var H   = 160;
        canvas.width  = W * dpr;
        canvas.height = H * dpr;
        canvas.style.height = H + 'px'; // 不覆盖 width:100%

        var ctx = canvas.getContext('2d');
        ctx.scale(dpr, dpr);
        // 裁剪防止溢出
        ctx.save();
        ctx.beginPath();
        ctx.rect(0, 0, W, H);
        ctx.clip();

        var pad = { t: 12, r: 8, b: 28, l: 46 };
        var cW  = W - pad.l - pad.r;
        var cH  = H - pad.t - pad.b;

        var allVals = inSeries.concat(outSeries).concat(totSeries);
        var maxV = Math.max.apply(null, allVals) || 1;

        var isDark = document.documentElement.getAttribute('data-theme') !== 'light';
        var gridColor  = isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.07)';
        var labelColor = isDark ? 'rgba(255,255,255,0.45)' : 'rgba(0,0,0,0.45)';

        ctx.clearRect(0, 0, W, H);

        /* grid + y labels */
        ctx.strokeStyle = gridColor;
        ctx.lineWidth   = 1;
        ctx.fillStyle   = labelColor;
        ctx.font        = (9 * dpr / dpr) + 'px sans-serif';
        ctx.textAlign   = 'right';
        for (var g = 0; g <= 4; g++) {
            var gy = pad.t + cH - (g / 4) * cH;
            ctx.beginPath(); ctx.moveTo(pad.l, gy); ctx.lineTo(pad.l + cW, gy); ctx.stroke();
            ctx.fillText(fmtGBShort(maxV * g / 4), pad.l - 3, gy + 3);
        }

        /* x labels - 用 measureText 测实际宽度，保证标签边缘不重叠 */
        ctx.textAlign = 'center';
        var lblMargin    = 6;   // 相邻标签之间最小留白（像素）
        var lastLblRight = -999; // 上一个已绘标签的右边缘
        for (var xi = 0; xi < times.length; xi++) {
            var xPos = pad.l + (times.length > 1 ? xi / (times.length - 1) : 0.5) * cW;
            var t = String(times[xi] || '');
            var lbl;
            if (_tfPeriod === 'ONE_DAY') {
                lbl = t.substring(5, 10);                               // MM-DD
            } else if (_tfPeriod === 'ONE_HOUR') {
                lbl = t.substring(5, 10) + ' ' + t.substring(11, 13);  // MM-DD HH
            } else {
                lbl = t.substring(11, 16);                              // HH:mm
            }
            var lblW     = ctx.measureText(lbl).width;
            var lblLeft  = xPos - lblW / 2;
            var lblRight = xPos + lblW / 2;
            if (lblLeft < lastLblRight + lblMargin) continue; // 会重叠，跳过
            if (lblRight > pad.l + cW + 2) continue;          // 超出右边界，跳过
            ctx.fillText(lbl, xPos, H - 5);
            lastLblRight = lblRight;
        }

        /* draw series */
        var series = [
            { data: inSeries,  color: '#43b581' },
            { data: outSeries, color: '#f04747' },
            { data: totSeries, color: '#5b8af0' }
        ];
        series.forEach(function(s) {
            if (!s.data || s.data.length < 2) return;
            ctx.strokeStyle = s.color;
            ctx.lineWidth   = 2;
            ctx.lineJoin    = 'round';
            ctx.beginPath();
            s.data.forEach(function(v, i) {
                var x = pad.l + (i / (s.data.length - 1)) * cW;
                var y = pad.t + cH - (v / maxV) * cH;
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            });
            ctx.stroke();
        });
        ctx.restore();
    }

    /* ── 格式化 ── */
    function fmtGB(bytes) {
        if (!bytes || bytes === 0) return '0 B';
        var units = ['B','KB','MB','GB','TB'];
        var i = 0, v = bytes;
        while (v >= 1024 && i < units.length - 1) { v /= 1024; i++; }
        return v.toFixed(2) + ' ' + units[i];
    }
    function fmtGBShort(bytes) {
        if (!bytes || bytes === 0) return '0';
        if (bytes >= 1099511627776) return (bytes/1099511627776).toFixed(1) + 'T';
        if (bytes >= 1073741824)    return (bytes/1073741824).toFixed(1) + 'G';
        if (bytes >= 1048576)       return (bytes/1048576).toFixed(1) + 'M';
        if (bytes >= 1024)          return (bytes/1024).toFixed(1) + 'K';
        return bytes.toFixed(0) + 'B';
    }

    function escHtml(s) {
        if (!s) return '';
        return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    }

    function mobTfToast(msg, type) {
        var t = document.createElement('div');
        t.style.cssText = 'position:fixed;bottom:80px;left:50%;transform:translateX(-50%);background:'
            + (type==='error'||type==='warn'?'#faa61a':'#43b581')
            + ';color:#fff;padding:10px 20px;border-radius:20px;font-size:13px;z-index:9999;white-space:nowrap;box-shadow:0 4px 12px rgba(0,0,0,0.3)';
        t.textContent = msg;
        document.body.appendChild(t);
        setTimeout(function() { t.remove(); }, 2500);
    }

    if (_tfTenantId) {
        document.addEventListener('DOMContentLoaded', function() { queryTraffic(); });
    }
})();
</script>
</#noparse>

</@layout.page>
