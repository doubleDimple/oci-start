<#import "layout.ftl" as layout>
<@layout.page title="${msg.get('mob.tab.speedtest')}" activePage="speedtest">

<!-- 摘要统计栏 -->
<div class="mob-speed-stats">
    <div class="mob-speed-stat-card">
        <div class="mob-speed-stat-label">${msg.get('mob.speed.current.ip')}</div>
        <div class="mob-speed-stat-value" id="stClientIp">${msg.get('mob.speed.detecting')}</div>
    </div>
    <div class="mob-speed-stat-card">
        <div class="mob-speed-stat-label">${msg.get('mob.speed.best.region')}</div>
        <div class="mob-speed-stat-value" id="stBestRegion">--</div>
    </div>
    <div class="mob-speed-stat-card">
        <div class="mob-speed-stat-label">${msg.get('mob.speed.avg.latency')}</div>
        <div class="mob-speed-stat-value" id="stAvgLatency">--</div>
    </div>
    <div class="mob-speed-stat-card">
        <div class="mob-speed-stat-label">${msg.get('mob.speed.tested')}</div>
        <div class="mob-speed-stat-value" id="stProgress">0 / 0</div>
    </div>
</div>

<!-- Top5 极速区域 -->
<div class="mob-speed-top5" id="stTop5">
    <div class="mob-speed-top5-title">${msg.get('mob.speed.top5.title')}</div>
    <div class="mob-speed-top5-list" id="stTop5List"></div>
</div>

<!-- 操作栏 -->
<div class="mob-speed-control">
    <button class="mob-btn mob-btn-primary" id="stStartBtn" onclick="stInitTest()" style="flex:1">
        <i class="fas fa-play"></i> ${msg.get('mob.speed.start')}
    </button>
</div>

<!-- 节点网格 -->
<div class="mob-speed-grid" id="stGrid">
    <div style="grid-column:1/-1;text-align:center;padding:32px;color:var(--mob-text-muted)">
        <div class="mob-spinner"></div>
        <p style="margin-top:8px">${msg.get('mob.speed.loading')}</p>
    </div>
</div>

<script>
var _stI18n = {
    detecting:  "${msg.get('mob.speed.detecting')}",
    noNodes:    "${msg.get('mob.speed.no.nodes')}",
    loadFail:   "${msg.get('mob.speed.load.fail')}",
    testing:    "${msg.get('mob.speed.testing')}",
    retry:      "${msg.get('mob.speed.retry')}",
    start:      "${msg.get('mob.speed.start')}"
};
</script>
<#noparse>
<script>
var stRegionList = [];
var stTesting = false;

// 页面加载
document.addEventListener('DOMContentLoaded', function() {
    stLoadIp();
    stLoadRegions();
});

async function stLoadIp() {
    try {
        var res = await fetch('/api/getCurrentIp');
        var json = await res.json();
        if (json.success) {
            var raw = json.data;
            var ipElem = document.getElementById('stClientIp');
            if (raw.includes('/')) {
                var parts = raw.split('/');
                ipElem.textContent = parts[0];
            } else {
                ipElem.textContent = raw.replace(/_/g, '.');
            }
        }
    } catch (e) {
        document.getElementById('stClientIp').textContent = 'error';
    }
}

async function stLoadRegions() {
    try {
        var res = await fetch('/api/getOracleEndpoint');
        var json = await res.json();
        if (json.success) {
            stRegionList = json.data.filter(function(r) { return r.endpoint; });
            stRenderGrid(stRegionList);
            document.getElementById('stProgress').textContent = '0 / ' + stRegionList.length;
            setTimeout(stInitTest, 600);
        } else {
            document.getElementById('stGrid').innerHTML =
                '<div style="grid-column:1/-1;text-align:center;color:var(--mob-text-muted);padding:32px">' + _stI18n.noNodes + '</div>';
        }
    } catch (e) {
        document.getElementById('stGrid').innerHTML =
            '<div style="grid-column:1/-1;text-align:center;color:#f04747;padding:32px">' + _stI18n.loadFail + '</div>';
    }
}

function stRenderGrid(data) {
    var grid = document.getElementById('stGrid');
    grid.innerHTML = data.map(function(item) {
        return '<div class="mob-speed-node" id="stNode-' + item.code + '">'
            + '<div class="mob-speed-node-name">' + escHtmlSt(item.simpleName) + '</div>'
            + '<div class="mob-speed-node-code">' + escHtmlSt(item.code) + '</div>'
            + '<div>'
            + '<span class="mob-speed-node-ms" id="stVal-' + item.code + '">--</span>'
            + '<span class="mob-speed-node-unit"> ms</span>'
            + '</div>'
            + '<div class="mob-speed-track"><div class="mob-speed-bar" id="stBar-' + item.code + '"></div></div>'
            + '</div>';
    }).join('');
}

async function stInitTest() {
    if (stTesting) return;
    stTesting = true;
    var btn = document.getElementById('stStartBtn');
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> ' + _stI18n.testing;

    // 重置
    document.getElementById('stBestRegion').textContent = '--';
    document.getElementById('stAvgLatency').textContent = '--';
    document.getElementById('stTop5').style.display = 'none';
    document.getElementById('stTop5List').innerHTML = '';

    stRegionList.forEach(function(item) {
        var valEl = document.getElementById('stVal-' + item.code);
        var barEl = document.getElementById('stBar-' + item.code);
        var nodeEl = document.getElementById('stNode-' + item.code);
        if (valEl) { valEl.textContent = '--'; valEl.className = 'mob-speed-node-ms'; }
        if (barEl) { barEl.style.width = '0%'; barEl.className = 'mob-speed-bar'; }
        if (nodeEl) { nodeEl.className = 'mob-speed-node testing'; }
    });

    var completedCount = 0;
    var totalLatency   = 0;
    var successCount   = 0;
    var minLatency     = 9999;
    var bestRegion     = '';
    var greenRegions   = [];

    document.getElementById('stProgress').textContent = '0 / ' + stRegionList.length;

    // 并行测试所有节点
    await Promise.all(stRegionList.map(async function(item) {
        var valEl  = document.getElementById('stVal-'  + item.code);
        var barEl  = document.getElementById('stBar-'  + item.code);
        var nodeEl = document.getElementById('stNode-' + item.code);

        if (valEl) valEl.textContent = '...';

        var ms = await stPing(item.endpoint);
        if (ms !== -1) {
            var ms2 = await stPing(item.endpoint);
            if (ms2 !== -1 && ms2 < ms) ms = ms2;
        }

        if (nodeEl) nodeEl.classList.remove('testing');
        completedCount++;
        document.getElementById('stProgress').textContent = completedCount + ' / ' + stRegionList.length;

        if (ms !== -1 && valEl && barEl) {
            valEl.textContent = ms;
            var pct = ms < 500 ? (100 - ms / 500 * 100) : 5;
            barEl.style.width = pct + '%';

            if (ms < 150) {
                valEl.classList.add('mob-ms-fast');
                barEl.classList.add('mob-bar-fast');
                greenRegions.push({ name: item.simpleName, ms: ms });
                greenRegions.sort(function(a, b) { return a.ms - b.ms; });
                var top5 = greenRegions.slice(0, 5);
                document.getElementById('stTop5').style.display = 'block';
                document.getElementById('stTop5List').innerHTML = top5.map(function(r) {
                    return '<span class="mob-speed-top5-tag">' + escHtmlSt(r.name) + ' ' + r.ms + 'ms</span>';
                }).join('');
            } else if (ms < 300) {
                valEl.classList.add('mob-ms-mid');
                barEl.classList.add('mob-bar-mid');
            } else {
                valEl.classList.add('mob-ms-slow');
                barEl.classList.add('mob-bar-slow');
            }

            totalLatency += ms;
            successCount++;
            if (ms < minLatency) {
                minLatency = ms;
                bestRegion = item.simpleName;
                document.getElementById('stBestRegion').textContent = bestRegion;
            }
            document.getElementById('stAvgLatency').textContent = Math.round(totalLatency / successCount) + 'ms';
        } else if (valEl) {
            valEl.textContent = 'timeout';
            valEl.style.fontSize = '12px';
            valEl.style.color = 'var(--mob-text-muted)';
        }
    }));

    stTesting = false;
    btn.disabled = false;
    btn.innerHTML = '<i class="fas fa-redo"></i> ' + _stI18n.retry;
}

async function stPing(url) {
    var controller = new AbortController();
    var tid = setTimeout(function() { controller.abort(); }, 5000);
    var start = performance.now();
    try {
        await fetch(url, {
            method: 'HEAD', mode: 'no-cors', cache: 'no-cache',
            referrerPolicy: 'no-referrer', signal: controller.signal
        });
        clearTimeout(tid);
        return Math.round(performance.now() - start);
    } catch (e) {
        clearTimeout(tid);
        return -1;
    }
}

function escHtmlSt(s) {
    if (!s) return '';
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
</script>
</#noparse>

</@layout.page>
