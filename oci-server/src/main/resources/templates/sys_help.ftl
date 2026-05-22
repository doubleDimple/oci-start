<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 系统救援</title>
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
<#--
    <link href="https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;500&display=swap" rel="stylesheet">
-->
    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="/css/all.min.css">
    <script src="https://cdnjs.cloudflare.com/ajax/libs/sockjs-client/1.5.0/sockjs.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/stomp.js/2.3.3/stomp.min.js"></script>

    <!-- 添加 SweetAlert2 -->
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>

    <link rel="stylesheet" href="/css/app/sys_help.css">

    <link rel="stylesheet" href="/css/common/loading.css">
</head>
<body>
<!-- 引入顶部导航栏 -->
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
        <div class="control-panel">
            <h2>${msg.get("sysHelp.config")}</h2>
            <div class="control-panel-content">
                <div class="instance-info-card">
                    <div class="instance-info-row">
                        <div class="instance-info-item">
                            <span class="instance-info-label"><i class="fas fa-server"></i> ${msg.get("tenant.insName")}</span>
                            <span class="instance-info-value">${instance.displayName!''}</span>
                        </div>
                        <div class="instance-info-item">
                            <span class="instance-info-label"><i class="fas fa-fingerprint"></i> ${msg.get("sysHelp.instanceId")}</span>
                            <span class="instance-info-value" id="instanceId">${instanceId!''}</span>
                        </div>
                        <div class="instance-info-item">
                            <span class="instance-info-label"><i class="fas fa-network-wired"></i> ${msg.get("sysHelp.ipAddress")}</span>
                            <span class="instance-info-value">${instance.publicIps!''}</span>
                        </div>
                        <div class="instance-info-item">
                            <span class="instance-info-label"><i class="fas fa-microchip"></i> ${msg.get("machine.arch")}</span>
                            <span class="instance-info-value">${instance.architecture!'Unknown'}</span>
                        </div>
                    </div>
                </div>
                <div class="action-buttons">
                    <button class="btn btn-success" id="startRescueBtn">
                        <i class="fas fa-medkit"></i>
                        <span>${msg.get("sysHelp.osHelp")}</span>
                    </button>
                    <button class="btn btn-danger" id="resetDiskBtn">
                        <i class="fas fa-hdd"></i>
                        <span>${msg.get("sysHelp.resetDisk")}</span>
                    </button>
                </div>
            </div>
        </div>

        <div class="terminal-card">
            <div class="terminal-header">
                <h2 class="terminal-title">
                    <i class="fas fa-terminal"></i>
                    <span>${msg.get("sysHelp.console")}</span>
                    <span class="terminal-cursor"></span>
                </h2>
                <div class="connection-status disconnected">
                    <i class="fas fa-circle"></i>
                    <span>${msg.get("sysHelp.noConn")}</span>
                </div>
            </div>

            <div class="terminal-content" id="terminal-content">
                <div class="log-entry">${msg.get("sysHelp.help1")}</div>
                <div class="log-entry">${msg.get("sysHelp.help2")}</div>
            </div>

            <div class="terminal-footer">
                <div class="log-info">
                    <div class="log-stat">
                        <i class="fas fa-clock"></i>
                        <span id="current-time"></span>
                    </div>
                    <div class="log-stat">
                        <i class="fas fa-list"></i>
                        <span id="log-count">${msg.get("sysHelp.logs")}</span>
                    </div>
                </div>
                <div class="log-actions">
                    <label class="auto-scroll">
                        <input type="checkbox" id="auto-scroll" checked>
                        <span>${msg.get("sysHelp.autoNext")}</span>
                    </label>
                    <span id="connection-status">${msg.get("sysHelp.waitConn")}</span>
                </div>
            </div>
        </div>
    </main>
</div>
<#--<#include "common/version_info.ftl">-->
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script>

    window.I18N = {
        common_noData: "${msg.get('common.noData')?js_string}",
        sysHelp_wsConnected: "${msg.get('sysHelp.wsConnected')?js_string}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        sysHelp_helpEnd: "${msg.get('sysHelp.helpEnd')?js_string}",
        sysHelp_wsConnError: "${msg.get('sysHelp.wsConnError')?js_string}",
        sysHelp_helpSummary1: "${msg.get('sysHelp.helpSummary1')?js_string}",
        sysHelp_helpSummary2: "${msg.get('sysHelp.helpSummary2')?js_string}",
        sysHelp_helpSummary3: "${msg.get('sysHelp.helpSummary3')?js_string}",
        sysHelp_helpSummary4: "${msg.get('sysHelp.helpSummary4')?js_string}",
        sysHelp_helpSummary5: "${msg.get('sysHelp.helpSummary5')?js_string}",
        sysHelp_helpSummary6: "${msg.get('sysHelp.helpSummary6')?js_string}",
        sysHelp_helpSummary7: "${msg.get('sysHelp.helpSummary7')?js_string}",
        sysHelp_helpSummary8: "${msg.get('sysHelp.helpSummary8')?js_string}",
        sysHelp_helpSummary9: "${msg.get('sysHelp.helpSummary9')?js_string}",
        sysHelp_helpSummary10: "${msg.get('sysHelp.helpSummary10')?js_string}",
        sysHelp_helpSummary11: "${msg.get('sysHelp.helpSummary11')?js_string}",
        sysHelp_helpSummary12: "${msg.get('sysHelp.helpSummary12')?js_string}",
        sysHelp_helpConfirm: "${msg.get('sysHelp.helpConfirm')?js_string}",
        sysHelp_noClose: "${msg.get('sysHelp.noClose')?js_string}",
        sysHelp_wsConError: "${msg.get('sysHelp.wsConError')?js_string}",
        sysHelp_start: "${msg.get('sysHelp.start')?js_string}",
        sysHelp_starting: "${msg.get('sysHelp.starting')?js_string}",
        sysHelp_finish: "${msg.get('sysHelp.finish')?js_string}",
        sysHelp_alreadyConn: "${msg.get('sysHelp.alreadyConn')?js_string}",
        sysHelp_notConn: "${msg.get('sysHelp.notConn')?js_string}",
        sysHelp_everyConn: "${msg.get('sysHelp.everyConn')?js_string}",
        sysHelp_connClose: "${msg.get('sysHelp.connClose')?js_string}",
        sysHelp_nlogs: "${msg.get('sysHelp.nlogs')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}"

    }

    const i18n = window.I18N;
    let stompClient = null;
    let logCount = 0;
    let maxLogs = 1000;
    let websocket = null;
    let rescueInProgress = false;

    function connectWebSocket() {
        const protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
        const host = window.location.host;
        websocket = new WebSocket(protocol + host + '/ws/rescue');

        websocket.onopen = function() {
            updateConnectionStatus(true);
            addLogEntry(i18n.sysHelp_wsConnected, "info");
        };

        websocket.onmessage = function(event) {
            const data = JSON.parse(event.data);
            if (data.type === "output") {
                addLogEntry(data.data, data.messageType.toLowerCase());
            } else if (data.type === "error") {
                addLogEntry(data.message, "error");
                rescueCompleted();
            } else if (data.type === "heartbeat") {
                websocket.send(JSON.stringify({
                    type: "heartbeat_response"
                }));
            }
        };

        websocket.onclose = function() {
            updateConnectionStatus(false);
            addLogEntry(i18n.sysHelp_helpEnd, "info");
            rescueCompleted();

            if (rescueInProgress) {
                setTimeout(connectWebSocket, 5000);
            }
        };

        websocket.onerror = function(error) {
            console.error('WebSocket错误:', error);
            updateConnectionStatus(false);
            addLogEntry(i18n.sysHelp_wsConnError, "error");
        };
    }

    // 修改后的startRescue函数
    function startRescue(type) {
        let htmlContent = `
        <div style="text-align: left; margin-bottom: 20px;">
            <p style="margin-bottom: 10px;">`+i18n.sysHelp_helpSummary1+`</p>
            <ol style="padding-left: 20px;">
                <li>`+i18n.sysHelp_helpSummary2+`</li>
                <li>`+i18n.sysHelp_helpSummary3+`</li>
                <li>`+i18n.sysHelp_helpSummary4+`</li>
                <li>`+i18n.sysHelp_helpSummary5+`</li>
                <li>`+i18n.sysHelp_helpSummary6+`</li>
            </ol>
        </div>
        <div style="text-align: left; color: var(--accent-red); margin-top: 10px;">
            `+i18n.sysHelp_helpSummary7+`
        </div>
    `;

        // 根据 type 修改内容
        if (type === 2) {
            htmlContent = `
            <div style="text-align: left; margin-bottom: 20px;">
                <p style="margin-bottom: 10px;">`+i18n.sysHelp_helpSummary1+`</p>
                <ol style="padding-left: 20px;">
                    <li>`+i18n.sysHelp_helpSummary8+`</li>
                    <li>`+i18n.sysHelp_helpSummary9+`</li>
                    <li>`+i18n.sysHelp_helpSummary10+`</li>
                    <li>`+i18n.sysHelp_helpSummary11+`</li>
                    <li>`+i18n.sysHelp_helpSummary12+`</li>
                </ol>
            </div>
            <div style="text-align: left; color: var(--accent-red); margin-top: 10px;">
                `+i18n.sysHelp_helpSummary7+`
            </div>
        `;
        }


        Swal.fire({
            title: i18n.sysHelp_helpConfirm,
            html: htmlContent,
            icon: 'warning',
            showCancelButton: true,
            confirmButtonColor: '#1abc9c',
            cancelButtonColor: '#6c757d',
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel,
            width: '600px'
        }).then((result) => {
            if (result.isConfirmed) {
                if (!websocket || websocket.readyState !== WebSocket.OPEN) {
                    connectWebSocket();
                    setTimeout(() => sendStartCommand(type), 1000);
                } else {
                    sendStartCommand(type);
                }
            }
        });
    }

    function sendStartCommand(type) {
        if (websocket && websocket.readyState === WebSocket.OPEN) {
            const instanceId = document.getElementById('instanceId').textContent;
            clearLogs();
            websocket.send(JSON.stringify({
                type: "init",
                instanceId: instanceId,
                rescueType: type
            }));
            document.getElementById('startRescueBtn').disabled = true;
            rescueInProgress = true;
            addLogEntry(i18n.sysHelp_noClose, "info");
        } else {
            addLogEntry(i18n.sysHelp_wsConError, "error");
        }
    }

    function rescueCompleted() {
        document.getElementById('startRescueBtn').disabled = false;
        rescueInProgress = false;
    }

    function addLogEntry(message, type = "info") {
        const terminalContent = document.getElementById('terminal-content');
        const entry = document.createElement('div');
        entry.className = 'log-entry new';

        if (type === "success" || message.toLowerCase().includes('[success]')) {
            entry.classList.add('success-entry');
        } else if (type === "warn" || message.toLowerCase().includes('[warn]') || message.toLowerCase().includes('warning')) {
            entry.classList.add('warn-entry');
        } else if (type === "error" || message.toLowerCase().includes('[error]') || message.toLowerCase().includes('error')) {
            entry.classList.add('error-entry');
        } else if (type === "process" || message.toLowerCase().includes(i18n.sysHelp_start) || message.toLowerCase().includes(i18n.sysHelp_starting)) {
            entry.classList.add('process-entry');
        } else if (type === "complete" || message.toLowerCase().includes(i18n.sysHelp_finish)) {
            entry.classList.add('complete-entry');
        }

        message = message.replace(/\[(SUCCESS|ERROR|WARN|INFO|PROCESS|COMPLETE)\]\s*/i, '');
        entry.innerHTML = message;
        terminalContent.appendChild(entry);

        logCount++;
        while (terminalContent.children.length > maxLogs) {
            terminalContent.removeChild(terminalContent.firstChild);
            logCount--;
        }

        updateLogCount();

        if (document.getElementById('auto-scroll').checked) {
            scrollToBottom();
        }

        setTimeout(() => entry.classList.remove('new'), 300);
    }

    function updateConnectionStatus(connected) {
        var status = document.querySelector('.connection-status');
        status.className = 'connection-status ' + (connected ? 'connected' : 'disconnected');
        status.innerHTML = '<i class="fas fa-circle"></i>' +
            '<span>' + (connected ? ''+i18n.sysHelp_alreadyConn+'' : ''+i18n.sysHelp_notConn+'') + '</span>';
        document.getElementById('connection-status').textContent = connected ? i18n.sysHelp_everyConn : i18n.sysHelp_connClose;
    }

    function updateLogCount() {
        document.getElementById('log-count').textContent = logCount + " "+i18n.sysHelp_nlogs;
    }

    function scrollToBottom() {
        const terminalContent = document.getElementById('terminal-content');
        terminalContent.scrollTop = terminalContent.scrollHeight;
    }

    function clearLogs() {
        const terminalContent = document.getElementById('terminal-content');
        terminalContent.innerHTML = '';
        logCount = 0;
        updateLogCount();
    }

    function updateCurrentTime() {
        const timeElement = document.getElementById('current-time');
        const now = new Date();
        timeElement.textContent = now.toLocaleTimeString();
    }
    document.addEventListener('DOMContentLoaded', function() {
        updateCurrentTime();
        setInterval(updateCurrentTime, 1000);
        document.getElementById('startRescueBtn').addEventListener('click', function() {
            startRescue(1);
        });

        document.getElementById('resetDiskBtn').addEventListener('click', function() {
            startRescue(2);
        });

        // 初始化侧边栏
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
    });
</script>
</body>
</html>