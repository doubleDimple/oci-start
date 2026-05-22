<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <title>Oracle Cloud 全球链路监控</title>

    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <script src="/js/common/jquery.min.js"></script>
    <link rel="stylesheet" href="/css/app/speed_test.css">
    <link rel="stylesheet" href="/css/common/loading.css">
</head>
<body>

<div class="layout">
    <main class="main-content">
    <div class="page-card">
        <div class="settings-container">
            <div class="page-header">
                <h1 class="page-title">
                    <i class="fas fa-globe-asia" style="color: var(--color-primary);"></i>
                    <span>${msg.get("speedTest.config")}</span>
                </h1>
            </div>

            <div class="dashboard-header">
                <div class="status-card user-ip">
                    <div class="card-label">${msg.get("speedTest.current")}</div>
                    <div class="card-value" id="client-ip">${msg.get("speedTest.testing")}</div>
                    <i class="fas fa-network-wired card-icon"></i>
                </div>
                <div class="status-card best-region">
                    <div class="card-label">${msg.get("speedTest.best")}</div>
                    <div class="card-value" id="best-region-display">--</div>
                    <i class="fas fa-trophy card-icon"></i>
                </div>
                <div class="status-card avg-latency">
                    <div class="card-label">${msg.get("speedTest.avg")}</div>
                    <div class="card-value" id="avg-latency-display">--</div>
                    <i class="fas fa-stopwatch card-icon"></i>
                </div>
            </div>

            <div class="rank-section" id="rank-section">
                <div class="rank-title">
                    <i class="fas fa-medal" style="color: var(--color-success)"></i>
                    ${msg.get("speedTest.top5")}
                </div>
                <div class="rank-list" id="rank-list">
                </div>
            </div>

            <div class="control-bar">
                <button type="button" class="btn btn-primary btn-glow" onclick="initTest()">
                    <i class="fas fa-bolt"></i> ${msg.get("speedTest.start")}
                </button>
            </div>

            <div class="region-grid" id="region-grid">
                <div style="color: var(--text-secondary); grid-column: 1/-1; text-align: center; padding: 40px;">
                    <i class="fas fa-circle-notch fa-spin"></i> loading...
                </div>
            </div>
        </div>
    </div><!-- /.page-card -->
    </main>
</div>

<script>
    const API = {
        GET_REGIONS: '/api/getOracleEndpoint',
        GET_IP: '/api/getCurrentIp'
    };
    document.addEventListener('DOMContentLoaded', () => {
        loadClientIp();
        loadRegionData();
    });
    async function loadClientIp() {
        try {
            const res = await fetch(API.GET_IP);
            const json = await res.json();
            if (json.success) {
                const rawData = json.data;
                const ipElem = document.getElementById('client-ip');

                if (rawData.includes('/')) {
                    const parts = rawData.split('/');
                    const ip = parts[0];
                    const location = parts[1];
                    ipElem.innerHTML = ip + ' <span style="font-size: 0.55em; color: var(--text-secondary); font-weight: 500; margin-left: 5px;">' + location + '</span>';
                } else {
                    ipElem.innerText = rawData.replace(/_/g, '.');
                }
            }
        } catch (e) {
            document.getElementById('client-ip').innerText = "error";
        }
    }

    let regionList = [];
    async function loadRegionData() {
        try {
            const res = await fetch(API.GET_REGIONS);
            const json = await res.json();

            if (json.success) {
                regionList = json.data.filter(r => r.endpoint);
                renderGrid(regionList);
                setTimeout(initTest, 500);
            } else {
                console.error("无法获取区域列表");
            }
        } catch (e) {
            console.error(e);
            document.getElementById('region-grid').innerHTML = '<div style="text-align:center;color:red">error</div>';
        }
    }
    function renderGrid(data) {
        const container = document.getElementById('region-grid');
        container.innerHTML = '';

        data.forEach(item => {
            const card = document.createElement('div');
            card.className = 'region-node';
            card.id = 'node-' + item.code;
            <#noparse>
            card.innerHTML = `
            <div class="node-header">
                <span class="node-name">${item.simpleName}</span>
                <span class="node-code">${item.code}</span>
            </div>
            <div class="latency-chart">
                <span class="latency-text" id="val-${item.code}">--</span>
                <span class="latency-unit">ms</span>
            </div>
            <div class="progress-track">
                <div class="progress-bar" id="bar-${item.code}"></div>
            </div>
        `;
            </#noparse>
            container.appendChild(card);
        });
    }

    async function initTest() {
        const bestDisplay = document.getElementById('best-region-display');
        const avgDisplay = document.getElementById('avg-latency-display');
        const rankSection = document.getElementById('rank-section');
        const rankListDom = document.getElementById('rank-list');
        let greenRegions = [];
        let totalLatency = 0;
        let successCount = 0;
        let minLatency = 9999;
        let bestRegion = '';

        if(bestDisplay) bestDisplay.innerText = 'loading...';
        if(avgDisplay) avgDisplay.innerText = '--';
        if(rankSection) rankSection.style.display = 'none';
        if(rankListDom) rankListDom.innerHTML = '';

        // 重置所有卡片为等待状态
        regionList.forEach(item => {
            const nodeVal = document.getElementById('val-' + item.code);
            const nodeBar = document.getElementById('bar-' + item.code);
            if(nodeVal) {
                nodeVal.innerText = '...';
                nodeVal.style.color = 'var(--text-secondary)';
                nodeVal.classList.remove('ping-fast', 'ping-mid', 'ping-slow');
            }
            if(nodeBar) {
                nodeBar.style.width = '0%';
                nodeBar.className = 'progress-bar';
            }
        });

        // 并行测速：所有区域同时开始，各自完成后立即更新
        const tasks = regionList.map(async (item) => {
            const nodeVal = document.getElementById('val-' + item.code);
            const nodeBar = document.getElementById('bar-' + item.code);
            const card = document.getElementById('node-' + item.code);

            if(card) card.style.borderColor = 'var(--color-primary)';

            let ms = await ping(item.endpoint);
            if (ms !== -1) {
                const retryMs = await ping(item.endpoint);
                if (retryMs !== -1 && retryMs < ms) ms = retryMs;
            }

            if(card) card.style.borderColor = '';

            if (ms !== -1 && nodeVal && nodeBar) {
                nodeVal.innerText = ms;
                const healthPercent = ms < 500 ? 100 - (ms / 500 * 100) : 5;
                nodeBar.style.width = healthPercent + '%';

                if (ms < 150) {
                    nodeVal.classList.add('ping-fast');
                    nodeBar.classList.add('bg-fast');
                    greenRegions.push({ name: item.simpleName, ms, code: item.code });
                    greenRegions.sort((a, b) => a.ms - b.ms);
                    const top5 = greenRegions.slice(0, 5);
                    rankSection.style.display = 'block';
                    rankListDom.innerHTML = top5.map(r =>
                        '<div class="rank-tag"><i class="fas fa-bolt"></i><span>' + r.name + '</span><span>' + r.ms + 'ms</span></div>'
                    ).join('');
                } else if (ms < 300) {
                    nodeVal.classList.add('ping-mid');
                    nodeBar.classList.add('bg-mid');
                } else {
                    nodeVal.classList.add('ping-slow');
                    nodeBar.classList.add('bg-slow');
                }

                totalLatency += ms;
                successCount++;

                if (ms < minLatency) {
                    minLatency = ms;
                    bestRegion = item.simpleName;
                    if(bestDisplay) bestDisplay.innerText = bestRegion + ' (' + minLatency + 'ms)';
                }

                if (avgDisplay) avgDisplay.innerText = Math.round(totalLatency / successCount) + 'ms';
            } else if (nodeVal) {
                nodeVal.innerText = 'timeOut';
                nodeVal.style.fontSize = '16px';
                nodeVal.style.color = 'var(--text-secondary)';
            }
        });

        await Promise.all(tasks);

        if(bestDisplay && bestRegion) bestDisplay.innerText = bestRegion + ' (' + minLatency + 'ms)';
    }

    async function ping(url) {
        const start = performance.now();
        try {
            await fetch(url, {
                method: 'HEAD',
                mode: 'no-cors',
                cache: 'no-cache',
                referrerPolicy: 'no-referrer'
            });
            const end = performance.now();
            return Math.round(end - start);
        } catch (e) {
            return -1;
        }
    }
</script>

</body>
</html>