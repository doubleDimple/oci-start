<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OCI控制台管理系统 - VNC终端</title>
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <script>(function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/sweetalert2.min.css">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/clipboard.js/2.0.8/clipboard.min.js"></script>
    <script type="module" crossorigin="anonymous">
        import RFB from 'https://cdn.jsdelivr.net/npm/@novnc/novnc@1.4.0/core/rfb.js';
        window.RFB = RFB;
        window.noVNCReady = true;
        console.log('noVNC RFB模块加载完成');
        window.dispatchEvent(new CustomEvent('novnc-loaded'));
    </script>
    <link rel="stylesheet" href="/css/app/console_terminal.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <style>
        .layout { padding-top: 0; }
        .main-content { margin-left: 0; }
    </style>

</head>
<body>
<#--<#include "common/header.ftl">-->

<div class="loading-overlay">
    <div class="spinner"></div>
</div>

<div class="layout">
    <#--<#include "common/sidebar.ftl">-->

    <main class="main-content">
        <div class="console-config-panel">
            <input type="hidden" id="serverIpField" value="${serverIp!''}"/>
            <!-- Hidden inputs — JS still reads these -->
            <input type="text" id="instanceId" value="${instanceId!''}" style="display:none;">
            <input type="text" id="tenantId"   value="${tenantId!''}"   style="display:none;">
            <div class="console-config-form">
                <div class="console-config-item">
                    <label class="console-config-label">
                        <i class="fas fa-globe"></i>${msg.get("vnc.ip")}
                    </label>
                    <input type="text" id="displayName" class="console-input" placeholder="${msg.get("vnc.noIp")}" value="${instanceIp!''}" readonly>
                </div>
                <div class="console-config-item">
                    <div class="button-container">
                        <button id="createConnectionBtn" class="action-btn">
                            <i class="fas fa-plus"></i>
                            ${msg.get("vnc.createVnc")}
                        </button>
                        <button id="copyCommandBtn" class="action-btn copy" data-clipboard-target="#connectionCommand" style="display: none;">
                            <i class="fas fa-copy"></i>
                            ${msg.get("vnc.copy")}
                        </button>
                        <#--<button id="autoNetbootBtn" class="action-btn" style="background: #8a2be2;">
                            <i class="fas fa-magic"></i>
                            一键网络救援
                        </button>-->
                        <button id="rebootBtn" class="action-btn reboot">
                            <i class="fas fa-redo"></i>
                            ${msg.get("vnc.retry")}
                        </button>
                        <a href="javascript:history.back()" class="action-btn secondary">
                            <i class="fas fa-arrow-left"></i>
                            ${msg.get("common.rollback")}
                        </a>
                    </div>
                </div>
            </div>
        </div>

        <div id="connectionInfo" style="display:none;"><span id="connectionCommand"></span></div>

        <div class="vnc-wrapper">
            <div class="vnc-header">
                <div class="vnc-title">
                    <i class="fas fa-desktop"></i>
                    OCI-START  - VNC
                    <span class="connection-type-badge">HTML5 VNC</span>
                </div>
                <div class="vnc-controls">
                    <button id="fullscreenBtn" class="btn-fullscreen" disabled>
                        <i class="fas fa-expand"></i>
                        ${msg.get("vnc.fullScreen")}
                    </button>
                    <button id="disconnectBtn" class="btn-disconnect" disabled>
                        <i class="fas fa-times"></i>
                        ${msg.get("vnc.stop")}
                    </button>
                    <div class="connection-status disconnected">
                        <i class="fas fa-circle"></i>
                        <span>${msg.get("vnc.noConn")}</span>
                        <span class="connection-timeout-indicator" id="timeoutIndicator"></span>
                    </div>
                </div>
            </div>

            <div class="vnc-toolbar" id="vncToolbar" style="display: none;">
                <button id="ctrlAltDelBtn">${msg.get("vnc.quickRestart")}</button>
                <button id="scaleBtn">${msg.get("vnc.changeConfig")}</button>
                <button id="clipboardBtn">${msg.get("vnc.clipboard")}</button>
                <span class="auto-stop-notice">${msg.get("vnc.autoStop")}</span>
            </div>

            <div id="vnc-container">
                <div id="vnc-placeholder">
                    <div class="computer-icon-wrapper">
                        <i class="fas fa-desktop fa-3x"></i>
                    </div>
                    <#--<p>${msg.get("vnc.plzConn")}</p>
                    <p>${msg.get("vnc.supportHtml")}</p>-->
                </div>

                <div id="vnc-display" style="display: none;"></div>
                <div id="netboot-logs" style="display: none; width: 100%; height: 100%; background: #0d1117; color: #3fb950; font-family: 'Fira Code', Consolas, monospace; padding: 20px; font-size: 13px; overflow-y: auto; white-space: pre-wrap; line-height: 1.6; text-align: left; position: absolute; top: 0; left: 0; z-index: 10; box-sizing: border-box;">
                    <div style="color: #4d9eff; margin-bottom: 10px;">>_ 初始化网络救援模块...</div>
                </div>
            </div>

            <div class="vnc-footer">
                <span id="status-text">${msg.get("sysHelp.waitConn")}</span>
                <span id="connection-id"></span>
            </div>
        </div>
    </main>
</div>

<#--
<#include "common/version_info.ftl">
-->
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script>

    window.I18N = {
        common_noData: "${msg.get('common.noData')?js_string}",
        vnc_plzConn: "${msg.get('vnc.plzConn')?js_string}",
        vnc_supportHtml: "${msg.get('vnc.supportHtml')?js_string}",
        vnc_noConn: "${msg.get('vnc.noConn')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        vnc_copySucc: "${msg.get('vnc.copySucc')?js_string}",
        vnc_connCpyd: "${msg.get('vnc.connCpyd')?js_string}",
        vnc_conning: "${msg.get('vnc.conning')?js_string}",
        vnc_waitConn: "${msg.get('vnc.waitConn')?js_string}",
        vnc_plzConnTimeOut: "${msg.get('vnc.plzConnTimeOut')?js_string}",
        vnc_plzConnTimeOutOneMinute: "${msg.get('vnc.plzConnTimeOutOneMinute')?js_string}",
        vnc_connTimeOut: "${msg.get('vnc.connTimeOut')?js_string}",
        vnc_connStop: "${msg.get('vnc.connStop')?js_string}",
        vnc_connAlready: "${msg.get('vnc.connAlready')?js_string}",
        vnc_connAlreadySummary: "${msg.get('vnc.connAlreadySummary')?js_string}",
        vnc_wsConnStop: "${msg.get('vnc.wsConnStop')?js_string}",
        vnc_connAlreadyHtml: "${msg.get('vnc.connAlreadyHtml')?js_string}",
        vnc_noramlStop: "${msg.get('vnc.noramlStop')?js_string}",
        vnc_unKnow: "${msg.get('vnc.unKnow')?js_string}",
        vnc_vncConnStop: "${msg.get('vnc.vncConnStop')?js_string}",
        vnc_needPass: "${msg.get('vnc.needPass')?js_string}",
        vnc_plzPass: "${msg.get('vnc.plzPass')?js_string}",
        vnc_connect: "${msg.get('vnc.connect')?js_string}",
        vnc_connectFail: "${msg.get('vnc.connectFail')?js_string}",
        vnc_backFullScreen: "${msg.get('vnc.backFullScreen')?js_string}",
        vnc_screen: "${msg.get('vnc.screen')?js_string}",
        vnc_summary: "${msg.get('vnc.summary')?js_string}",
        vnc_sourSize: "${msg.get('vnc.sourSize')?js_string}",
        vnc_c: "${msg.get('vnc.c')?js_string}",
        vnc_plzConnVnc: "${msg.get('vnc.plzConnVnc')?js_string}",
        vnc_copySummary: "${msg.get('vnc.copySummary')?js_string}",
        vnc_sendConsole: "${msg.get('vnc.sendConsole')?js_string}",
        vnc_consoleStop: "${msg.get('vnc.consoleStop')?js_string}",
        vnc_resetGuid: "${msg.get('vnc.resetGuid')?js_string}",
        vnc_reseting: "${msg.get('vnc.reseting')?js_string}",
        vnc_resetSucc: "${msg.get('vnc.resetSucc')?js_string}",
        vnc_resetSuccSummary: "${msg.get('vnc.resetSuccSummary')?js_string}",
        vnc_resetSuccWaitSummary: "${msg.get('vnc.resetSuccWaitSummary')?js_string}",
        vnc_retry: "${msg.get('vnc.retry')?js_string}"


    }
    const i18n = window.I18N;
    let websocket;
    let connected = false;
    let instanceId = '${instanceId!''}';
    let ociInstanceId = '${ociInstanceId!''}';
    let tenantId = '${tenantId!''}';
    let instanceIp = '${instanceIp!''}';
    let connecting = false;
    let isDisconnecting = false;
    let currentConnectionId = null;
    let vncClient = null;
    let vncUrl = null;
    let websockifyPort = null;
    let serverIp = '';

    // 自动断开相关变量
    let inactivityTimer = null;
    let lastActivityTime = Date.now();
    let connectionTimeoutMs = 30 * 60 * 1000; // 10分钟
    let timeoutWarningMs = 29 * 60 * 1000; // 9分钟后警告
    let heartbeatInterval = null; // WebSocket心跳
    let connectionCheckInterval = null; // 连接检查

    // 复制功能初始化
    var clipboard = new ClipboardJS('#copyCommandBtn');

    clipboard.on('success', function(e) {
        Swal.fire({
            icon: 'success',
            title: i18n.vnc_copySucc,
            text: i18n.vnc_connCpyd,
            timer: 1500,
            showConfirmButton: false
        });
        e.clearSelection();
    });

    clipboard.on('error', function(e) {
        console.error('复制失败:', e);
    });

    // 等待noVNC加载的函数
    function waitForNoVNC() {
        return new Promise((resolve, reject) => {
            if (window.noVNCReady && window.RFB) {
                console.log('noVNC已准备就绪');
                resolve();
                return;
            }

            let timeout = setTimeout(() => {
                reject(new Error('error'));
            }, 15000);

            window.addEventListener('novnc-loaded', function() {
                clearTimeout(timeout);
                console.log('noVNC加载成功事件触发');
                resolve();
            }, { once: true });
        });
    }

    // 显示电脑图标加载动画
    function showVncLoading() {
        let placeholder = document.getElementById('vnc-placeholder');
        placeholder.classList.add('loading');
        /*placeholder.querySelector('p').textContent = i18n.vnc_conning;
        placeholder.querySelector('p:last-child').textContent = i18n.vnc_waitConn;*/
    }

    // 隐藏电脑图标加载动画
    function hideVncLoading() {
        var placeholder = document.getElementById('vnc-placeholder');
        placeholder.classList.remove('loading');
        placeholder.querySelector('p').textContent = i18n.vnc_plzConn;
        placeholder.querySelector('p:last-child').textContent = i18n.vnc_supportHtml;
    }

    // 重置非活动计时器
    function resetInactivityTimer() {
        lastActivityTime = Date.now();

        if (inactivityTimer) {
            clearTimeout(inactivityTimer);
        }

        if (connected) {
            inactivityTimer = setTimeout(() => {
                Swal.fire({
                    icon: 'warning',
                    title: i18n.vnc_plzConnTimeOut,
                    timer: 3000,
                    showConfirmButton: false
                });
                disconnectFromVnc();
            }, connectionTimeoutMs);

            // 9分钟后显示警告
            setTimeout(() => {
                if (connected && Date.now() - lastActivityTime > timeoutWarningMs) {
                    Swal.fire({
                        icon: 'warning',
                        title: i18n.vnc_plzConnTimeOutOneMinute,
                        text: i18n.vnc_connTimeOut,
                        timer: 5000,
                        showConfirmButton: false
                    });
                }
            }, timeoutWarningMs);
        }
    }

    function updateTimeoutIndicator() {
        if (!connected) return;

        const indicator = document.getElementById('timeoutIndicator');
        if (!indicator) return;

        const remainingTime = Math.max(0, connectionTimeoutMs - (Date.now() - lastActivityTime));
        const minutes = Math.floor(remainingTime / 60000);
        const seconds = Math.floor((remainingTime % 60000) / 1000);
        const timeText = minutes+`:`+ seconds.toString().padStart(2, '0');
        if (indicator.textContent !== timeText) {
            indicator.textContent = timeText;
        }

        if (remainingTime > 0) {
            setTimeout(updateTimeoutIndicator, 1000);
        }
    }

    function startHeartbeat() {
        if (heartbeatInterval) {
            clearInterval(heartbeatInterval);
        }

        heartbeatInterval = setInterval(() => {
            if (websocket && websocket.readyState === WebSocket.OPEN) {
                websocket.send(JSON.stringify({
                    type: 'heartbeat',
                    timestamp: Date.now()
                }));
                console.log('发送心跳包');
            } else {
                console.warn('WebSocket连接异常，停止心跳');
                stopHeartbeat();
            }
        }, 30000); // 每30秒发送一次心跳

        console.log('WebSocket心跳机制已启动');
    }

    // 停止心跳
    function stopHeartbeat() {
        if (heartbeatInterval) {
            clearInterval(heartbeatInterval);
            heartbeatInterval = null;
            console.log('WebSocket心跳机制已停止');
        }
    }

    // 连接状态检查 - 更加完善的检测
    function startConnectionCheck() {
        if (connectionCheckInterval) {
            clearInterval(connectionCheckInterval);
        }

        connectionCheckInterval = setInterval(() => {
            if (connected && websocket) {
                if (websocket.readyState !== WebSocket.OPEN) {
                    console.warn('WebSocket连接已断开，状态:', websocket.readyState);
                    Swal.fire({
                        icon: 'warning',
                        title: i18n.vnc_connStop,
                        timer: 3000,
                        showConfirmButton: false
                    });
                    disconnectFromVnc();
                } else {
                    // 连接正常，发送保活ping
                    websocket.send(JSON.stringify({
                        type: 'ping',
                        timestamp: Date.now()
                    }));
                }
            }
        }, 10000);

        console.log('连接状态检查已启动');
    }

    // 停止连接检查
    function stopConnectionCheck() {
        if (connectionCheckInterval) {
            clearInterval(connectionCheckInterval);
            connectionCheckInterval = null;
            console.log('连接状态检查已停止');
        }
    }

    // 监听用户活动
    function setupActivityListeners() {
        const events = ['mousedown', 'mousemove', 'keypress', 'scroll', 'touchstart', 'click'];

        events.forEach(event => {
            document.addEventListener(event, resetInactivityTimer, true);
        });

        // 特别监听VNC容器的活动
        const vncContainer = document.getElementById('vnc-container');
        if (vncContainer) {
            events.forEach(event => {
                vncContainer.addEventListener(event, resetInactivityTimer, true);
            });
        }
    }

    async function createVncConnection() {
        if (connecting) return;

        try {
            console.log('开始创建VNC连接，等待noVNC加载...');
            await waitForNoVNC();
            console.log('noVNC已加载完成，继续创建连接');
        } catch (error) {
            console.error('noVNC加载失败:', error);
            Swal.fire({
                icon: 'error',
                title: 'error'
            });
            return;
        }

        var instanceIdInput = document.getElementById('instanceId').value;
        var tenantIdInput = document.getElementById('tenantId').value;
        var displayName = instanceIp || 'VNC';

        if (!instanceIdInput || !tenantIdInput) {
            return;
        }

        connecting = true;
        showVncLoading();
        updateConnectionStatus('connecting', i18n.vnc_conning);

        if (websocket) {
            websocket.close();
        }

        var protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
        var wsHost = window.location.host;

        websocket = new WebSocket(protocol + wsHost + '/ws/console');

        websocket.onopen = function() {
            console.log('WebSocket连接已建立');
            startHeartbeat();
            websocket.send(JSON.stringify({
                type: 'create_connection',
                data: {
                    instanceId: instanceIdInput,
                    tenantId: tenantIdInput,
                    displayName: displayName,
                    connectionType: 'vnc'
                }
            }));
        };

        websocket.onmessage = function(event) {
            var data = JSON.parse(event.data);
            console.log('收到WebSocket消息:', data);

            // 处理心跳消息
            if (data.type === 'heartbeat') {
                // 收到服务器心跳，立即响应
                websocket.send(JSON.stringify({
                    type: 'heartbeat_response',
                    timestamp: Date.now()
                }));
                return;
            }

            // 处理心跳响应
            if (data.type === 'heartbeat_response') {
                console.log('收到心跳响应');
                return;
            }

            if (data.type === 'error') {
                console.error('收到错误消息:', data.message);
                Swal.fire({
                    icon: 'error',
                    title: 'error',
                    text: data.message
                });
                disconnectFromVnc();
            } else if (data.type === 'vnc_ready') {
                console.log('VNC连接就绪');
                connected = true;
                document.getElementById('createConnectionBtn').disabled = true;
                document.getElementById('disconnectBtn').disabled = false;
                document.getElementById('fullscreenBtn').disabled = false;
                document.getElementById('rebootBtn').disabled = false;
                document.getElementById('copyCommandBtn').style.display = 'flex';
                updateConnectionStatus('connected', i18n.vnc_connAlready);
                resetInactivityTimer();
                startConnectionCheck();

                if (data.command) {
                    updateConnectionInfo(data.command);
                }

                if (data.websockifyPort) {
                    websockifyPort = data.websockifyPort;
                    console.log('websockify端口:', websockifyPort);

                    setTimeout(() => {
                        connectToVncWebSocket(websockifyPort);
                    }, 1500);
                } else {
                    updateStatusText(i18n.vnc_connAlreadySummary);
                }

                hideVncLoading();
                connecting = false;

                if (data.connectionId) {
                    currentConnectionId = data.connectionId;
                    //document.getElementById('connection-id').textContent = '连接ID: ' + currentConnectionId;
                }
            } else if (data.type === 'output') {
                console.log("接收到输出: ", data.data);
            }
        };

        websocket.onclose = function(event) {
            console.log('WebSocket连接已关闭', event);
            console.log('关闭代码:', event.code, '原因:', event.reason);

            // 停止心跳和检查
            stopHeartbeat();
            stopConnectionCheck();

            if (!isDisconnecting) {
                Swal.fire({
                    icon: 'warning',
                    title: i18n.vnc_wsConnStop,
                    timer: 3000,
                    showConfirmButton: false
                });
                disconnectFromVnc();
            }
            hideVncLoading();
            connecting = false;
            isDisconnecting = false;
        };

        websocket.onerror = function(error) {
            console.error('WebSocket错误:', error);
            stopHeartbeat();
            stopConnectionCheck();
            disconnectFromVnc();
            hideVncLoading();
            connecting = false;
        };
    }

    function connectToVncWebSocket(port) {
        try {
            console.log('开始连接到websockify代理端口:', port);

            let protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
            let host = window.location.host;
            let wsUrl;

            if (protocol === 'ws://') {
                var hostIp = host.split(':')[0];
                wsUrl = protocol + hostIp + ':' + port + '/';
            } else {
                wsUrl = protocol + host + '/websockify/' + port;
            }

            console.log('连接VNC WebSocket URL:', wsUrl);

            document.getElementById('vnc-placeholder').style.display = 'none';
            document.getElementById('vnc-display').style.display = 'flex';
            document.getElementById('vncToolbar').style.display = 'flex';

            const vncDisplay = document.getElementById('vnc-display');
            vncDisplay.innerHTML = '';

            vncClient = new window.RFB(vncDisplay, wsUrl, {
                shared: true,
                repeaterID: '',
                wsProtocols: ['binary'],
                qualityLevel: 9,
                compressionLevel: 0
            });

            vncClient.scaleViewport = true;
            vncClient.resizeSession = false;


            // 事件监听器
            vncClient.addEventListener('connect', function(e) {
                console.log('VNC连接成功', e);
                updateStatusText(i18n.vnc_connAlreadyHtml);
                updateConnectionStatus('connected', i18n.vnc_connAlready);
                resetInactivityTimer();
                updateTimeoutIndicator();
            });

            vncClient.addEventListener('disconnect', function(e) {
                console.log('VNC连接断开', e);
                const reason = e.detail.clean ? i18n.vnc_noramlStop : (e.detail.reason || i18n.vnc_unKnow);
                updateStatusText(i18n.vnc_vncConnStop+': ' + reason);
                if (inactivityTimer) {
                    clearTimeout(inactivityTimer);
                    inactivityTimer = null;
                }
                stopConnectionCheck();
            });

            vncClient.addEventListener('credentialsrequired', function(e) {
                console.log('需要VNC凭据', e);
                Swal.fire({
                    title: i18n.vnc_needPass,
                    input: 'password',
                    inputPlaceholder: i18n.vnc_plzPass,
                    showCancelButton: true,
                    confirmButtonText: i18n.vnc_connect,
                    cancelButtonText: i18n.common_cancel
                }).then((result) => {
                    if (result.isConfirmed && result.value) {
                        vncClient.sendCredentials({ password: result.value });
                    } else {
                        vncClient.disconnect();
                    }
                });
            });

            vncClient.addEventListener('securityfailure', function(e) {
                console.error('VNC安全验证失败', e);
            });

            // 监听VNC客户端的鼠标和键盘事件来重置计时器
            vncDisplay.addEventListener('mousedown', resetInactivityTimer);
            vncDisplay.addEventListener('keydown', resetInactivityTimer);

        } catch (error) {
            console.error("VNC连接错误:", error);
            updateStatusText(i18n.vnc_connectFail+': ' + error.message);
            Swal.fire({
                icon: 'error',
                text: error.message
            });

            document.getElementById('vnc-placeholder').style.display = 'block';
            document.getElementById('vnc-display').style.display = 'none';
            document.getElementById('vncToolbar').style.display = 'none';
        } finally {
            hideVncLoading();
        }
    }

    function disconnectFromVnc() {
        console.log('断开VNC连接');

        // 清除所有计时器和检查
        if (inactivityTimer) {
            clearTimeout(inactivityTimer);
            inactivityTimer = null;
        }
        stopHeartbeat();
        stopConnectionCheck();

        if (websocket) {
            isDisconnecting = true;
            websocket.send(JSON.stringify({
                type: 'disconnect'
            }));
            websocket.close();
        }

        if (vncClient) {
            try {
                vncClient.disconnect();
            } catch (e) {
                console.error("断开VNC连接出错:", e);
            }
            vncClient = null;
        }

        connected = false;
        document.getElementById('createConnectionBtn').disabled = false;
        document.getElementById('disconnectBtn').disabled = true;
        document.getElementById('fullscreenBtn').disabled = true;
        document.getElementById('rebootBtn').disabled = true;
        document.getElementById('copyCommandBtn').style.display = 'none';
        updateConnectionStatus('disconnected', i18n.vnc_noConn);
        document.getElementById('connection-id').textContent = '';
        updateConnectionInfo('');

        document.getElementById('vnc-placeholder').style.display = 'block';
        document.getElementById('vnc-display').style.display = 'none';
        document.getElementById('vncToolbar').style.display = 'none';

        hideVncLoading();
    }

    function toggleFullscreen() {
        var vncContainer = document.getElementById('vnc-container');

        if (!document.fullscreenElement) {
            vncContainer.requestFullscreen().then(() => {
                document.getElementById('fullscreenBtn').innerHTML = '<i class="fas fa-compress"></i> '+i18n.vnc_backFullScreen;
            }).catch(err => {
                console.error('无法进入全屏模式:', err);
            });
        } else {
            document.exitFullscreen().then(() => {
                document.getElementById('fullscreenBtn').innerHTML = '<i class="fas fa-expand"></i> '+i18n.vnc_screen;
            });
        }
    }

    function sendCtrlAltDel() {
        if (vncClient) {
            vncClient.sendCtrlAltDel();
            resetInactivityTimer();
            Swal.fire({
                icon: 'info',
                title: 'Ctrl+Alt+Del',
                text: i18n.vnc_summary,
                timer: 1500,
                showConfirmButton: false
            });
        }
    }

    function toggleScale() {
        if (vncClient) {
            vncClient.scaleViewport = !vncClient.scaleViewport;
            var scaleBtn = document.getElementById('scaleBtn');
            if (vncClient.scaleViewport) {
                scaleBtn.textContent = i18n.vnc_sourSize;
                scaleBtn.classList.add('active');
            } else {
                scaleBtn.textContent = i18n.vnc_c;
                scaleBtn.classList.remove('active');
            }
            resetInactivityTimer();
        }
    }

    // 切换剪贴板面板
    function showClipboard() {
        if (!vncClient) {
            Swal.fire({
                icon: 'warning',
                title: i18n.vnc_noConn,
                text: i18n.vnc_plzConnVnc
            });
            return;
        }

        Swal.fire({
            title: '剪贴板操作',
            html: `
                <textarea id="clipboardText" placeholder="粘贴文本到这里，然后点击发送到终端执行"
                         style="width: 100%; height: 100px; margin-bottom: 10px; padding: 8px; border: 1px solid #ddd; border-radius: 4px; font-family: 'Fira Code', monospace;"></textarea>
                <div style="font-size: 12px; color: #666; margin-bottom: 10px;">
                     ` +i18n.vnc_copySummary+`
                </div>
            `,
            showCancelButton: true,
            confirmButtonText: i18n.vnc_sendConsole,
            cancelButtonText: i18n.vnc_consoleStop,
            width: '500px',
            preConfirm: () => {
                const text = document.getElementById('clipboardText').value;
                if (text.trim()) {
                    try {
                        for (let i = 0; i < text.length; i++) {
                            const char = text.charAt(i);
                            if (char === '\n') {
                                // 处理换行符
                                vncClient.sendKey(0xff0d, "Enter", true);
                                vncClient.sendKey(0xff0d, "Enter", false);
                            } else {
                                vncClient.sendKey(char.charCodeAt(0), char, true);
                                vncClient.sendKey(char.charCodeAt(0), char, false);
                            }
                        }
                        resetInactivityTimer();
                        return true;
                    } catch (e) {
                        Swal.showValidationMessage('error: ' + e.message);
                        return false;
                    }
                }
                return true;
            }
        }).then((result) => {
            if (result.isConfirmed) {
                const text = document.getElementById('clipboardText').value;
                if (text.trim()) {
                    console.log('文本已发送到VNC终端:', text);
                }
            }
        });
    }

    function rebootInstance() {
        var instanceIdInput = ociInstanceId;
        var tenantIdInput = document.getElementById('tenantId').value;

        if (!instanceIdInput || !tenantIdInput) {
            return;
        }

        Swal.fire({
            icon: 'warning',
            title: i18n.vnc_resetGuid,
            showCancelButton: true,
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel,
            confirmButtonColor: '#ff9800'
        }).then((result) => {
            if (result.isConfirmed) {
                document.getElementById('rebootBtn').disabled = true;
                document.getElementById('rebootBtn').innerHTML = '<i class="fas fa-spinner fa-spin"></i> '+i18n.vnc_reseting;

                const csrfToken = document.querySelector('input[name="_csrf"]').value;
                const csrfHeader = document.querySelector('meta[name="_csrf_header"]')?.content || 'X-CSRF-TOKEN';

                fetch('/oci/console/heavyNewRestart', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        [csrfHeader]: csrfToken
                    },
                    body: JSON.stringify({
                        instanceId: instanceIdInput,
                        tenantId: tenantIdInput
                    })
                })
                    .then(response => response.json())
                    .then(data => {
                        if (data.success) {
                            Swal.fire({
                                icon: 'success',
                                title: i18n.vnc_resetSucc,
                                text: i18n.vnc_resetSuccSummary,
                                timer: 1000,
                                showConfirmButton: true
                            });
                            updateStatusText(i18n.vnc_resetSuccWaitSummary);
                            resetInactivityTimer();
                        } else {
                            console.error('重启请求失败:', data.message);
                            /*Swal.fire({
                                icon: 'error',
                                title: 'error',
                                text: data.message || '重启操作失败，请稍后重试'
                            });*/
                        }
                    })
                    .catch(error => {
                        console.error('重启请求失败:', error);
                        Swal.fire({
                            icon: 'error',
                            title: 'error'
                        });
                    })
                    .finally(() => {
                        document.getElementById('rebootBtn').disabled = false;
                        document.getElementById('rebootBtn').innerHTML = '<i class="fas fa-redo"></i> '+i18n.vnc_retry;
                    });
            }
        });
    }

    function updateConnectionStatus(status, statusText) {
        var statusElement = document.querySelector('.connection-status');
        statusElement.className = 'connection-status ' + status;
/*
        statusElement.innerHTML = '<i class="fas fa-circle"></i><span>' + statusText + '</span><span class="connection-timeout-indicator" id="timeoutIndicator"></span>';
*/
        statusElement.innerHTML =
            '<i class="fas fa-circle"></i>' +
            '<span>' + statusText + '</span>' +
            '<span class="connection-timeout-indicator" id="timeoutIndicator" '
            + 'style="color:red;font-size:14px;font-weight:bold;margin-left:6px;"></span>';


        updateStatusText(statusText);
    }

    function updateStatusText(text) {
        var statusTextElement = document.getElementById('status-text');
        statusTextElement.textContent = text;
    }

    function updateConnectionInfo(command) {
        var infoElement = document.getElementById('connectionInfo');
        var commandElement = document.getElementById('connectionCommand');

        if (command) {
            commandElement.textContent = command;
            infoElement.style.display = 'flex';
        } else {
            infoElement.style.display = 'none';
        }
    }

    function showLoading() {
        document.querySelector('.loading-overlay').style.display = 'flex';
    }

    function hideLoading() {
        document.querySelector('.loading-overlay').style.display = 'none';
    }

    function initSidebar() {
        var navParents = document.querySelectorAll('.nav-parent');
        navParents.forEach(function(parent) {
            var parentLink = parent.querySelector('.nav-link');
            if (parentLink) {
                parentLink.addEventListener('click', function(e) {
                    e.preventDefault();
                    parent.classList.toggle('expanded');
                });
            }
        });

        var activeLink = document.querySelector('.nav-link.active');
        if (activeLink) {
            var parent = activeLink.closest('.nav-parent');
            if (parent) {
                parent.classList.add('expanded');
            }
        }
    }

    // 监听全屏状态变化
    document.addEventListener('fullscreenchange', function() {
        var fullscreenBtn = document.getElementById('fullscreenBtn');
        if (document.fullscreenElement) {
            fullscreenBtn.innerHTML = '<i class="fas fa-compress"></i> '+i18n.vnc_backFullScreen;
        } else {
            fullscreenBtn.innerHTML = '<i class="fas fa-expand"></i> '+i18n.vnc_screen;
        }
    });

    document.addEventListener('DOMContentLoaded', function() {
        console.log("页面已加载，初始化组件...");

        // 初始化侧边栏
        initSidebar();

        // 设置活动监听器
        setupActivityListeners();

        // 绑定事件
        document.getElementById('createConnectionBtn').addEventListener('click', createVncConnection);
        document.getElementById('disconnectBtn').addEventListener('click', disconnectFromVnc);
        document.getElementById('fullscreenBtn').addEventListener('click', toggleFullscreen);
        document.getElementById('rebootBtn').addEventListener('click', rebootInstance);
        document.getElementById('autoNetbootBtn').addEventListener('click', triggerAutoNetboot);

        // VNC工具栏事件
        document.getElementById('ctrlAltDelBtn').addEventListener('click', sendCtrlAltDel);
        document.getElementById('scaleBtn').addEventListener('click', toggleScale);
        document.getElementById('clipboardBtn').addEventListener('click', showClipboard);

        // 自动填充字段
        if (instanceId) {
            document.getElementById('instanceId').value = instanceId;
        }
        if (tenantId) {
            document.getElementById('tenantId').value = tenantId;
        }
    });

    // ================= 新增：Netboot 自动化前端逻辑 =================

    function triggerAutoNetboot() {
        var instanceIdInput = document.getElementById('instanceId').value;
        var tenantIdInput = document.getElementById('tenantId').value;
        var displayName = instanceIp || 'Netboot';

        if (!instanceIdInput || !tenantIdInput) {
            Swal.fire({icon: 'warning', title: '缺少实例ID或租户ID'});
            return;
        }

        Swal.fire({
            icon: 'warning',
            title: '确认执行一键网络救援？',
            html: '此操作将<b>强制重启</b>实例，并在底层截获引导流进入网络救援系统。<br><br><span style="color:#f78166">预计耗时 1-3 分钟，期间请勿关闭页面。</span>',
            showCancelButton: true,
            confirmButtonText: '确认执行',
            cancelButtonText: i18n.common_cancel,
            confirmButtonColor: '#8a2be2'
        }).then((result) => {
            if (result.isConfirmed) {
                executeAutoNetboot(instanceIdInput, tenantIdInput, displayName);
            }
        });
    }

    function executeAutoNetboot(instanceIdInput, tenantIdInput, displayName) {
        if (connecting) return;
        connecting = true;

        // 1. UI 切换到“极客日志”模式
        document.getElementById('vnc-placeholder').style.display = 'none';
        document.getElementById('vnc-display').style.display = 'none';
        var logBox = document.getElementById('netboot-logs');
        logBox.style.display = 'block';
        logBox.innerHTML = '<div style="color: #4d9eff; margin-bottom: 10px;">>_ 开始与后端建立劫持通道...</div>';

        updateConnectionStatus('connecting', '正在下发救援指令...');

        // 2. 锁定按钮
        document.getElementById('createConnectionBtn').disabled = true;
        document.getElementById('autoNetbootBtn').disabled = true;
        document.getElementById('disconnectBtn').disabled = false;

        if (websocket) { websocket.close(); }

        var protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
        var wsHost = window.location.host;
        websocket = new WebSocket(protocol + wsHost + '/ws/console');

        websocket.onopen = function() {
            startHeartbeat();
            // 发送我们在后端写好的路由指令 'auto_netboot'
            websocket.send(JSON.stringify({
                type: 'auto_netboot',
                data: {
                    instanceId: instanceIdInput,
                    tenantId: tenantIdInput,
                    displayName: displayName
                }
            }));
        };

        websocket.onmessage = function(event) {
            var data = JSON.parse(event.data);

            if (data.type === 'heartbeat') {
                websocket.send(JSON.stringify({ type: 'heartbeat_response', timestamp: Date.now() }));
                return;
            }
            if (data.type === 'heartbeat_response') return;

            if (data.type === 'error') {
                logBox.innerHTML += '<div style="color: #ff6b6b;">[error] ' + data.message + '</div>';
                logBox.scrollTop = logBox.scrollHeight; // 自动滚到底部
                disconnectFromVnc();
            } else if (data.type === 'output') {
                // 将后端的日志实时打印到网页的黑框里
                logBox.innerHTML += '<div>' + data.data.replace(/\r\n/g, '<br>') + '</div>';
                logBox.scrollTop = logBox.scrollHeight;
            }
        };

        websocket.onclose = function(event) {
            stopHeartbeat();
            stopConnectionCheck();
            connecting = false;
            document.getElementById('autoNetbootBtn').disabled = false;
        };

        websocket.onerror = function(error) {
            logBox.innerHTML += `<div style="color: #ff6b6b;">[系统] WebSocket连接发生错误，请检查网络或后端服务。</div>`;
            stopHeartbeat();
            connecting = false;
        };
    }
</script>
</body>
</html>