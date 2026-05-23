<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>资源监控看板 - VPS管理系统</title>
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>

    <script>(function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <link rel="stylesheet" href="/css/app/vps_list.css">

    <script src="/js/sweetalert2.min.js"></script>
    <script src="/js/common/jquery.min.js"></script>
</head>
<body>

<div class="layout">
    <main class="main-content">
        <div class="dashboard-container">

            <div class="stats-header">
                <div class="stat-card">
                    <div><h3>服务器总数</h3><div class="num">${totalElements!0}</div></div>
                    <i class="fas fa-server stat-icon"></i>
                </div>
                <div class="stat-card">
                    <div><h3>在线数量</h3><div class="num" id="ping-online-count">0</div></div>
                    <i class="fas fa-wifi stat-icon" style="color:var(--success)"></i>
                </div>
                <div class="stat-card" id="offline-filter-card" onclick="toggleOfflineFilter()">
                    <div><h3>离线数量</h3><div class="num" id="offline-count">0</div></div>
                    <i class="fas fa-heart-broken stat-icon" style="color:var(--danger)"></i>
                </div>
            </div>

            <div class="control-panel">
                <div class="control-left">
                    <div class="control-title">
                        <i class="fas fa-chart-line" style="color: var(--primary)"></i> 监控面板
                    </div>
                </div>

                <div class="control-right">
                    <div class="search-wrapper">
                        <input type="text" id="server-search" placeholder="搜索 IP、地区..." onkeyup="filterServers()">
                        <i class="fas fa-search"></i>
                    </div>

                    <button class="btn-tool" onclick="toggleGlobalIpVisibility()" id="btn-toggle-ip" title="切换 IP 显示状态">
                        <i class="fas fa-eye"></i> <span>显示 IP</span>
                    </button>

                    <button class="btn-tool" id="btn-latency-test" onclick="pingAllServers()" title="测试当前浏览器到各实例的延迟">
                        <i class="fas fa-bolt"></i> <span>延迟测试</span>
                    </button>

                    <div class="dropdown">
                        <button class="btn-tool" onclick="toggleTopDropdown(event)">
                            <i class="fas fa-cog"></i> 更多操作 <i class="fas fa-chevron-down" style="font-size:10px; margin-left:2px; opacity:0.6;"></i>
                        </button>

                        <div class="dropdown-menu" id="top-dropdown-menu">
                            <button class="dropdown-item" onclick="startAllTests()">
                                <i class="fas fa-play" style="color:var(--success)"></i> 开启自动 Ping
                            </button>
                            <button class="dropdown-item" onclick="stopAllTests()">
                                <i class="fas fa-stop" style="color:var(--danger)"></i> 停止自动 Ping
                            </button>
                            <button class="dropdown-item" onclick="manualPingTest()">
                                <i class="fas fa-bullseye" style="color:var(--primary)"></i> 手动 Ping 检测
                            </button>
                            <div class="dropdown-divider"></div>
                            <button class="dropdown-item" onclick="location.reload()">
                                <i class="fas fa-sync-alt" style="color:var(--gray)"></i> 刷新页面
                            </button>
                        </div>
                    </div>
                </div>
            </div>

            <div class="server-grid" id="server-grid-container">
                <#if instanceDetailsRes?? && instanceDetailsRes?size gt 0>
                    <#list instanceDetailsRes as instance>
                        <div class="server-card <#if instance.monitorInstalled!false>monitor-warning</#if> <#if instance.onLineEnable == 1>ping-online<#else>ping-offline</#if>"
                             id="card-${instance.id}"
                             data-token="${instance.instanceId}"
                             data-ping-status="${instance.onLineEnable}"
                             data-installed="${(instance.monitorInstalled!false)?c}"
                             data-last-beat="${(instance.lastHeartbeat?long)!0}">

                            <div class="card-body">
                                <div class="card-top">
                                    <div class="server-icon">
                                        <#if instance.cloudType == 1><img src="/images/oracle.png" alt="Oracle">
                                        <#elseif instance.cloudType == 2><img src="/images/google.png" alt="GCP">
                                        <#elseif instance.cloudType == 4><img src="/images/aws.png" alt="AWS">
                                        <#else><img src="/images/vps.png" alt="VPS"></#if>
                                    </div>
                                    <div class="server-info">
                                        <div class="server-ip-container" onclick="toggleCardIp('${instance.id}')" title="点击显示/隐藏 IP">
                                            <div class="server-ip masked" id="ip-txt-${instance.id}" data-real-ip="${instance.publicIps!'无IP'}">
                                                ${instance.publicIps!'无IP'}
                                            </div>
                                            <i class="fas fa-eye ip-eye"></i>
                                        </div>

                                        <div class="server-tags">
                                            <img class="flag-img" src="${instance.flagUrl!'/images/flags/xx.svg'}"
                                                 title="${instance.regionName!''}"
                                                 onerror="this.src='/images/flags/xx.svg'">

                                            <div class="tag"><i class="fas fa-map-marker-alt"></i> ${instance.regionName!""}</div>

                                            <div class="tag tag-uptime" style="display:none"><i class="fas fa-clock"></i> <span class="uptime-txt">--</span></div>
                                            <div class="tag tag-load" style="display:none"><i class="fas fa-tachometer-alt"></i> <span class="load-txt">--</span></div>
                                            <div class="tag tag-latency" id="pc-latency-${instance.id}" style="display:none"><i class="fas fa-bolt"></i> <span class="latency-val">--</span></div>
                                        </div>
                                    </div>
                                    <div class="status-badge"><#if instance.onLineEnable == 1>在线<#else>离线</#if></div>
                                </div>

                                <div class="metrics-area">
                                    <div class="metric-row">
                                        <div class="metric-label"><span>CPU</span><span class="cpu-txt">0%</span></div>
                                        <div class="progress"><div class="progress-bar cpu-bar" style="width: 0%; background: var(--success);"></div></div>
                                    </div>
                                    <div class="metric-row">
                                        <div class="metric-label"><span>内存</span><span class="mem-txt">0%</span></div>
                                        <div class="progress"><div class="progress-bar mem-bar" style="width: 0%; background: var(--primary);"></div></div>
                                    </div>
                                    <div class="metric-row">
                                        <div class="metric-label"><span>硬盘 <span class="disk-total-txt" style="font-size:10px;opacity:0.7"></span></span><span class="disk-percent-txt">0%</span></div>
                                        <div class="progress"><div class="progress-bar disk-bar" style="width: 0%; background: var(--purple);"></div></div>
                                    </div>
                                    <div class="net-stats">
                                        <div class="net-item"><i class="fas fa-arrow-down" style="color:var(--success)"></i> <span class="net-rx-txt">0 B/s</span></div>
                                        <div class="net-item"><i class="fas fa-arrow-up" style="color:var(--warning)"></i> <span class="net-tx-txt">0 B/s</span></div>
                                    </div>
                                </div>
                            </div>

                            <div class="card-actions">
                                <a href="/oci/terminal?instanceId=${instance.id}" target="biz-frame" class="btn-mini ssh-btn">
                                    <i class="fas fa-terminal"></i> SSH
                                </a>
                                <button class="btn-mini btn-install" onclick="installMonitor('${instance.id}')"
                                        <#if instance.monitorInstalled!false>style="display:none"</#if>>
                                    <i class="fas fa-download"></i> 安装
                                </button>
                                <button class="btn-mini danger" onclick="uninstallMonitor('${instance.id}')">
                                    <i class="fas fa-trash-alt"></i> 卸载
                                </button>
                            </div>
                        </div>
                    </#list>
                <#else>
                    <div style="grid-column: 1/-1; text-align:center; padding:60px; color:var(--gray);" id="no-data-msg">
                        <i class="fas fa-server" style="font-size:48px; margin-bottom:15px; opacity:0.2;"></i>
                        <p>暂无实例数据</p>
                    </div>
                </#if>
            </div>
        </div>
    </main>
</div>

<script>
    <#noparse>
    const lastHeartbeat = {};
    let ws = null;
    let isOfflineOnly = false;
    let isGlobalIpVisible = false;

    $(document).ready(function() {

        // 2. 初始化心跳
        $('.server-card').each(function() {
            const token = $(this).attr('data-token');
            const dbHeartbeat = $(this).attr('data-last-beat');
            if (token && dbHeartbeat && dbHeartbeat !== '0') {
                lastHeartbeat[token] = parseInt(dbHeartbeat);
            }
        });

        // 3. 点击任意位置关闭下拉菜单
        $(document).click(function(event) {
            if (!$(event.target).closest('.dropdown').length) {
                $('.dropdown').removeClass('active');
            }
        });

        checkAgentStatus();
        updatePingStats();
        initWebSocket();
        setInterval(checkAgentStatus, 3000);
        setTimeout(pingAllServers, 800);
    });

    // === 下拉菜单逻辑 ===
    function toggleTopDropdown(event) {
        event.stopPropagation();
        $(event.currentTarget).closest('.dropdown').toggleClass('active');
    }

    // === IP 显示/隐藏逻辑 ===
    function toggleGlobalIpVisibility() {
        isGlobalIpVisible = !isGlobalIpVisible;
        const btn = $('#btn-toggle-ip');

        if (isGlobalIpVisible) {
            btn.addClass('active');
            btn.find('i').attr('class', 'fas fa-eye-slash');
            btn.find('span').text('隐藏 IP');
            $('.server-ip').removeClass('masked');
        } else {
            btn.removeClass('active');
            btn.find('i').attr('class', 'fas fa-eye');
            btn.find('span').text('显示 IP');
            $('.server-ip').addClass('masked');
        }
    }

    function toggleCardIp(id) {
        const ipDiv = $(`#ip-txt-${id}`);
        ipDiv.toggleClass('masked');
    }

    // === 搜索逻辑 ===
    function filterServers() {
        const input = $('#server-search').val().toLowerCase().trim();
        const isFilterActive = $('#offline-filter-card').hasClass('active-filter');

        $('.server-card').each(function() {
            const card = $(this);
            // 搜索真实 IP (data-real-ip)
            const realIp = card.find('.server-ip').attr('data-real-ip') || '';
            const tags = card.find('.server-tags').text().toLowerCase();
            const isOffline = card.hasClass('ping-offline');

            const matchesSearch = realIp.toLowerCase().includes(input) || tags.includes(input);
            const matchesStatus = isFilterActive ? isOffline : true;

            if (matchesSearch && matchesStatus) {
                card.show();
            } else {
                card.hide();
            }
        });
    }

    function toggleOfflineFilter() {
        $('#offline-filter-card').toggleClass('active-filter');
        filterServers();
    }

    // === WebSocket & Metrics ===
    function initWebSocket() {
        const protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
        const url = protocol + window.location.host + '/ws/monitor';
        ws = new WebSocket(url);
        ws.onopen = function() { console.log("监控连接成功"); };
        ws.onmessage = function(event) {
            try {
                const data = JSON.parse(event.data);
                if (!data.token) return;
                updateMetrics(data);
                lastHeartbeat[data.token] = Date.now();
            } catch (e) { console.error(e); }
        };
        ws.onclose = function() { setTimeout(initWebSocket, 3000); };
    }

    function updateMetrics(data) {
        const token = data.token;
        const card = $(`.server-card[data-token="${token}"]`);
        if (card.length === 0) return;

        card.removeClass('monitor-warning');
        card.attr('data-installed', 'true');
        card.find('.btn-install').hide();

        const cpu = data.cpu.usage;
        card.find('.cpu-txt').text(cpu + '%');
        updateProgressBar(card.find('.cpu-bar'), cpu);

        if (data.cpu.load && data.cpu.load.length >= 1) {
            card.find('.tag-load').show();
            card.find('.load-txt').text(data.cpu.load[0]);
            card.find('.tag-load').attr('title', `负载: ${data.cpu.load.join(' / ')}`);
        }

        const memUsed = data.memory.used;
        const memTotal = data.memory.total;
        const memPercent = Math.round((memUsed / memTotal) * 100);
        card.find('.mem-txt').text(memPercent + '%');
        updateProgressBar(card.find('.mem-bar'), memPercent);

        if (data.disk) {
            const diskUsed = data.disk.used;
            const diskTotal = data.disk.total;
            const diskPercent = Math.round((diskUsed / diskTotal) * 100);
            card.find('.disk-percent-txt').text(diskPercent + '%');
            card.find('.disk-total-txt').text(`(${formatSize(diskTotal)})`);
            const diskBar = card.find('.disk-bar');
            diskBar.css('width', diskPercent + '%');
            if(diskPercent > 90) diskBar.css('background', 'var(--danger)');
            else diskBar.css('background', 'var(--purple)');
        }

        if (data.host && data.host.uptime) {
            card.find('.tag-uptime').show();
            card.find('.uptime-txt').text(formatUptime(data.host.uptime));
        }

        card.find('.net-rx-txt').text(formatSpeed(data.network.rx_rate));
        card.find('.net-tx-txt').text(formatSpeed(data.network.tx_rate));
    }

    function checkAgentStatus() {
        const now = Date.now();
        const timeout = 12000;
        $('.server-card').each(function() {
            const card = $(this);
            const token = card.attr('data-token');
            const pingStatus = card.attr('data-ping-status');
            const isInstalled = card.attr('data-installed');

            if (pingStatus == '0' || isInstalled === 'false') {
                card.removeClass('monitor-warning');
                return;
            }
            const lastTime = lastHeartbeat[token] || parseInt(card.attr('data-last-beat')) || 0;
            if (now - lastTime > timeout) {
                card.addClass('monitor-warning');
            } else {
                card.removeClass('monitor-warning');
            }
        });
    }

    // === 修复后的安装逻辑 ===
    function installMonitor(id) {
        Swal.fire({
            title: '安装监控探针',
            text: "将通过 SSH 连接服务器并安装 Agent。",
            icon: 'info',
            showCancelButton: true,
            confirmButtonColor: '#3b82f6',
            confirmButtonText: '开始安装',
            showLoaderOnConfirm: true,
            preConfirm: () => {
                const csrfToken = $("meta[name='_csrf']").attr("content");
                const csrfHeader = $("meta[name='_csrf_header']").attr("content");
                return $.ajax({
                    url: "/api/monitor/install",
                    type: "POST",
                    data: { vpsId: id },
                    beforeSend: function(xhr) { if(csrfHeader) xhr.setRequestHeader(csrfHeader, csrfToken); }
                }).then(response => {
                    // 修正点：使用 response.success
                    if (!response.success) throw new Error(response.message || "安装失败");
                    return response;
                }).catch(error => { Swal.showValidationMessage(`请求失败: ${error}`); });
            }
        }).then((result) => {
            if (result.isConfirmed) {
                Swal.fire('指令已发送', '探针上线后数据会自动刷新。', 'success');
                $(`#card-${id}`).attr('data-installed', 'true');
            }
        });
    }

    function uninstallMonitor(id) {
        Swal.fire({
            title: '停止监控?',
            text: "将卸载 Agent 服务。",
            icon: 'warning',
            showCancelButton: true,
            confirmButtonColor: '#ef4444',
            confirmButtonText: '停止'
        }).then((result) => {
            if (result.isConfirmed) {
                const csrfToken = $("meta[name='_csrf']").attr("content");
                const csrfHeader = $("meta[name='_csrf_header']").attr("content");
                $.post({
                    url: "/api/monitor/uninstall",
                    data: { vpsId: id },
                    beforeSend: function(xhr) { if(csrfHeader) xhr.setRequestHeader(csrfHeader, csrfToken); },
                    success: function(res) {
                        Swal.fire('已停止', '卸载指令已发送', 'success');
                        $(`#card-${id}`).attr('data-installed', 'false');
                        $(`#card-${id}`).removeClass('monitor-warning');
                        $(`#card-${id}`).find('.btn-install').show();
                    }
                });
            }
        });
    }

    function manualPingTest() {
        const csrfToken = $("meta[name='_csrf']").attr("content");
        const csrfHeader = $("meta[name='_csrf_header']").attr("content");
        Swal.fire({
            title: '正在检测中...',
            text: '正在向后端发送 Ping 指令，请稍候',
            icon: 'info',
            allowOutsideClick: false,
            showConfirmButton: false,
            didOpen: () => { Swal.showLoading(); }
        });
        $.ajax({
            url: '/vps/instances/ping',
            type: 'POST',
            beforeSend: function(xhr) { if(csrfHeader) xhr.setRequestHeader(csrfHeader, csrfToken); },
            success: function(res) { Swal.fire('指令已发送', 'Ping 测试将在后台执行', 'success'); },
            error: function() { Swal.fire('失败', '请求失败', 'error'); }
        });
    }

    function startAllTests() { sendRequest('/vps/instances/enablePing'); }
    function stopAllTests() { sendRequest('/vps/instances/disablePing'); }
    function sendRequest(url) {
        const csrfToken = $("meta[name='_csrf']").attr("content");
        const csrfHeader = $("meta[name='_csrf_header']").attr("content");
        $.ajax({
            url: url, type: 'POST',
            beforeSend: function(xhr) { if(csrfHeader) xhr.setRequestHeader(csrfHeader, csrfToken); },
            success: function(res) { Swal.fire('请求成功', '指令已发送', 'success'); }
        });
    }

    function updatePingStats() {
        const total = $('.server-card').length;
        const online = $('.server-card.ping-online').length;
        $('#ping-online-count').text(online);
        $('#offline-count').text(total - online);
    }

    function updateProgressBar(bar, percent) {
        bar.css('width', percent + '%');
        if(percent > 90) bar.css('background', 'var(--danger)');
        else if(percent > 70) bar.css('background', 'var(--warning)');
        else bar.css('background', 'var(--success)');
    }

    function formatUptime(seconds) {
        const d = Math.floor(seconds / (3600*24));
        const h = Math.floor(seconds % (3600*24) / 3600);
        if (d > 0) return d + "天";
        if (h > 0) return h + "小时";
        return Math.floor(seconds / 60) + "分";
    }
    function formatSize(mb) { return mb > 1024 ? (mb / 1024).toFixed(0) + 'G' : mb + 'M'; }
    function formatSpeed(bytes) {
        if (!bytes) return '0 B/s';
        const k = 1024, i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + ['B/s','KB/s','MB/s','GB/s'][i];
    }

    // === 延迟测试 ===
    let isLatencyTesting = false;

    async function pingAllServers() {
        if (isLatencyTesting) return;
        isLatencyTesting = true;
        const btn = $('#btn-latency-test');
        btn.addClass('active').find('span').text('测试中...');

        const tasks = [];
        $('.server-card').each(function() {
            const card = $(this);
            const ip = card.find('.server-ip').attr('data-real-ip');
            const id = card.attr('id').replace('card-', '');
            if (ip && ip !== '无IP') {
                tasks.push(pingSingleServer(ip, id));
            }
        });

        await Promise.all(tasks);

        isLatencyTesting = false;
        btn.removeClass('active').find('span').text('重测延迟');
    }

    async function pingSingleServer(ip, id) {
        const el = $(`#pc-latency-${id}`);
        if (!el.length) return;
        el.show().removeClass('lat-fast lat-mid lat-slow lat-timeout').addClass('lat-testing');
        el.find('.latency-val').text('...');

        let ms = await pingIpAddr(ip);
        if (ms === -1) ms = await pingIpAddr(ip);

        el.removeClass('lat-testing');
        if (ms === -1) {
            el.addClass('lat-timeout');
            el.find('.latency-val').text('超时');
        } else if (ms < 150) {
            el.addClass('lat-fast');
            el.find('.latency-val').text(ms + 'ms');
        } else if (ms < 300) {
            el.addClass('lat-mid');
            el.find('.latency-val').text(ms + 'ms');
        } else {
            el.addClass('lat-slow');
            el.find('.latency-val').text(ms + 'ms');
        }
    }

    async function pingIpAddr(ip) {
        const controller = new AbortController();
        const tid = setTimeout(() => controller.abort(), 5000);
        const start = performance.now();
        try {
            await fetch('http://' + ip, {
                method: 'HEAD', mode: 'no-cors', cache: 'no-cache',
                referrerPolicy: 'no-referrer', signal: controller.signal
            });
            clearTimeout(tid);
            return Math.round(performance.now() - start);
        } catch (e) {
            clearTimeout(tid);
            if (e.name === 'AbortError') return -1;
            return Math.round(performance.now() - start);
        }
    }
    </#noparse>
</script>

</body>
</html>