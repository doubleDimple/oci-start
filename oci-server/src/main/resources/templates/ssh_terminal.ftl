<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - SSH终端</title>
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
<#--
    <link href="https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;500&display=swap" rel="stylesheet">
-->
    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@4.19.0/css/xterm.css" />
    <link rel="stylesheet" href="/css/sweetalert2.min.css">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>

    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/all.min.css">
    <script src="/js/xterm.js"></script>
    <script src="/js/xterm-addon-fit.js"></script>
    <script src="/js/xterm-addon-web-links.js"></script>
    <script src="/js/xterm-addon-webgl.js" defer></script>
<#--
    <script src="https://cdn.jsdelivr.net/npm/xterm-addon-webgl@0.14.0/lib/xterm-addon-webgl.js"></script>
-->


    <link rel="stylesheet" href="/css/app/ssh_terminal.css">
</head>
<body>
<#--<#include "common/header.ftl">-->


<div class="layout">
    <#--<#include "common/sidebar.ftl">-->

    <main class="main-content">

        <div class="ssh-config-panel">
            <div class="ssh-config-form">
                <div class="ssh-config-item">
                    <label class="ssh-config-label"><i class="fas fa-user"></i>${msg.get("ssh.user")}</label>
                    <input type="text" id="username" class="ssh-input" placeholder="${msg.get("ssh.user")}">
                </div>
                <div class="ssh-config-item">
                    <label class="ssh-config-label"><i class="fas fa-network-wired"></i>${msg.get("ssh.address")}</label>
                    <input type="text" id="host" class="ssh-input" placeholder="${msg.get("ssh.address")}">
                </div>
                <div class="ssh-config-item">
                    <label class="ssh-config-label"><i class="fas fa-door-open"></i>${msg.get("ssh.port")}</label>
                    <input type="text" id="port" class="ssh-input" value="22" placeholder="${msg.get("ssh.port")}">
                </div>
                <div class="ssh-config-item">
                    <label class="ssh-config-label"><i class="fas fa-key"></i>${msg.get("ssh.pass")}</label>
                    <div class="password-container">
                        <input type="password" id="password" class="ssh-input" placeholder="${msg.get("ssh.pass")}">
                        <button type="button" class="password-action-btn" onclick="togglePassword()" title="${msg.get("ssh.showOrHiddenPass")}">
                            <i class="fas fa-eye"></i>
                        </button>
                        <button type="button" class="password-action-btn" onclick="copyPassword()" title="${msg.get("ssh.copyPass")}">
                            <i class="fas fa-copy"></i>
                        </button>
                    </div>
                </div>
                <div class="ssh-config-item">
                    <div style="display:flex;gap:10px;align-items:center;">
                        <button id="saveConfigBtn" class="save-config-btn">
                            <i class="fas fa-save"></i> ${msg.get("common.save")}
                        </button>
                        <button onclick="history.back()" class="save-config-btn">
                            <i class="fas fa-arrow-left"></i> ${msg.get("common.rollback")}
                        </button>
                    </div>
                </div>
            </div>
        </div>

        <div class="terminal-wrapper">
            <div class="terminal-header">
                <div class="terminal-title">
                    <i class="fas fa-terminal"></i> ${msg.get("ssh.sshConsole")}
                </div>

                <div class="terminal-controls">
                    <button id="connectBtn" class="btn-connect">
                        <i class="fas fa-plug"></i>${msg.get("ssh.conn")}
                    </button>
                    <button id="disconnectBtn" class="btn-disconnect" disabled>
                        <i class="fas fa-times"></i>${msg.get("ssh.stop")}
                    </button>
                    <div class="connection-status disconnected">
                        <i class="fas fa-circle"></i><span>${msg.get("ssh.noConn")}</span>
                    </div>

                    <!--  新增主题切换 -->
                    <select id="themeSelect" class="theme-select" title="${msg.get("ssh.theme")}">
                        <option value="matrix">Matrix</option>
                        <option value="tokyonight">Tokyonight (Dark)</option>
                        <option value="dracula">Dracula</option>
                        <option value="solarizedLight">Solarized Light</option>
                        <option value="highContrast">High Contrast</option>
                    </select>
                </div>
            </div>

            <div id="terminal"></div>

            <div class="terminal-footer">
                <span id="status-text">${msg.get("ssh.waitConn")}</span>
            </div>
        </div>

    </main>
</div>
<!-- 右键菜单 -->
<div id="ctxMenu" class="ctx-menu">
    <div class="ctx-item" id="ctxCopy"><i class="fas fa-copy"></i> ${msg.get("ssh.copySelect")}</div>
    <div class="ctx-item" id="ctxPaste"><i class="fas fa-paste"></i> ${msg.get("ssh.nt")}</div>
    <div class="ctx-sep"></div>
    <div class="ctx-item" id="ctxSelectAll"><i class="fas fa-i-cursor"></i> ${msg.get("ssh.allSelect")}</div>
</div>

<#--<#include "common/version_info.ftl">-->
<#--<script src="/js/common/request.js"></script>-->
<script src="/js/common/loading.js"></script>
<script>
    window.I18N = {
        ssh_welcome: "${msg.get('ssh.welcome')?js_string}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        ssh_conecting: "${msg.get('ssh.conecting')?js_string}",
        ssh_connected: "${msg.get('ssh.connected')?js_string}",
        ssh_connecStop: "${msg.get('ssh.connecStop')?js_string}",
        ssh_connecAlready: "${msg.get('ssh.connecAlready')?js_string}",
        ssh_connecWait: "${msg.get('ssh.connecWait')?js_string}",
        ssh_passBlank: "${msg.get('ssh.passBlank')?js_string}",
        ssh_passCopySucc: "${msg.get('ssh.passCopySucc')?js_string}",
        common_plzInputGlobalRequired: "${msg.get('common.plzInputGlobalRequired')?js_string}"


    }
    const i18n = window.I18N;
    var term, websocket, fitAddon, webglAddon;
    var connected = false;
    var instanceId = '${instanceId!''}';
    var connecting = false;
    var isDisconnecting = false;
    let selectedFolderId = null;

    // 终端主题（可扩展）
    const TerminalThemes = {
        tokyonight: {
            background: '#1a1b26', foreground: '#a9b1d6', cursor: '#c0caf5',
            black: '#15161e', red: '#f7768e', green: '#9ece6a', yellow: '#e0af68',
            blue: '#7aa2f7', magenta: '#bb9af7', cyan: '#7dcfff', white: '#a9b1d6',
            brightBlack: '#414868', brightRed: '#f7768e', brightGreen: '#9ece6a',
            brightYellow: '#e0af68', brightBlue: '#7aa2f7', brightMagenta: '#bb9af7',
            brightCyan: '#7dcfff', brightWhite: '#c0caf5'
        },
        dracula: {
            background: '#282a36', foreground: '#f8f8f2', cursor: '#f8f8f2',
            black: '#000000', red: '#ff5555', green: '#50fa7b', yellow: '#f1fa8c',
            blue: '#bd93f9', magenta: '#ff79c6', cyan: '#8be9fd', white: '#bbbbbb',
            brightBlack: '#555555', brightRed: '#ff5555', brightGreen: '#50fa7b',
            brightYellow: '#f1fa8c', brightBlue: '#bd93f9', brightMagenta: '#ff79c6',
            brightCyan: '#8be9fd', brightWhite: '#ffffff'
        },
        solarizedLight: {
            background: '#fdf6e3', foreground: '#657b83', cursor: '#657b83',
            black: '#073642', red: '#dc322f', green: '#859900', yellow: '#b58900',
            blue: '#268bd2', magenta: '#d33682', cyan: '#2aa198', white: '#eee8d5',
            brightBlack: '#002b36', brightRed: '#cb4b16', brightGreen: '#586e75',
            brightYellow: '#657b83', brightBlue: '#839496', brightMagenta: '#6c71c4',
            brightCyan: '#93a1a1', brightWhite: '#fdf6e3'
        },
        highContrast: {
            background: '#000000', foreground: '#ffffff', cursor: '#ffffff',
            black: '#000000', red: '#ff0000', green: '#00ff00', yellow: '#ffff00',
            blue: '#0088ff', magenta: '#ff00ff', cyan: '#00ffff', white: '#ffffff',
            brightBlack: '#7f7f7f', brightRed: '#ff4c4c', brightGreen: '#4cff4c',
            brightYellow: '#ffff4c', brightBlue: '#4c9dff', brightMagenta: '#ff4cff',
            brightCyan: '#4cffff', brightWhite: '#ffffff'
        },
        matrix: {
            background: '#000000', foreground: '#00ff00', cursor: '#00ff00',
            black: '#000000', red: '#ff0000', green: '#00ff00', yellow: '#ffff00',
            blue: '#00ffff', magenta: '#ff00ff', cyan: '#00ffff', white: '#ffffff',
            brightBlack: '#333333', brightRed: '#ff5555', brightGreen: '#00ff00',
            brightYellow: '#ffff55', brightBlue: '#55ffff', brightMagenta: '#ff55ff',
            brightCyan: '#55ffff', brightWhite: '#ffffff'
        }
    };

    document.addEventListener('DOMContentLoaded', function() {
        const navParents = document.querySelectorAll('.nav-parent');
        navParents.forEach(parent => {
            const parentLink = parent.querySelector('.nav-link');
            parentLink.addEventListener('click', (e) => {
                e.preventDefault();
                parent.classList.toggle('expanded');
            });
        });

        const activeLink = document.querySelector('.nav-link.active');
        if (activeLink) {
            const parent = activeLink.closest('.nav-parent');
            if (parent) {
                parent.classList.add('expanded');
            }
        }
    })

    function loadTree(focusId) {
        fetch('/ssh/folders/tree', { headers: { 'X-Requested-With': 'XMLHttpRequest' } })
            .then(r => r.json())
            .then(res => {
                if (!res.success || !res.data) return;
                const tree = document.getElementById('folderTree');
                render(res.data, tree);
                if (focusId) {
                    // 定位到刚创建的文件夹
                    const el = document.querySelector(`.folder-node[data-id="`+ focusId+`"]`);
                    if (el) el.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }
            });
    }


    function render(data, container) {
        container.innerHTML = '';

        data.forEach(n => {
            const nodeWrapper = document.createElement('div');
            nodeWrapper.className = 'folder-item';

            const hasChildren = n.children && n.children.length > 0;

            const toggleIcon = document.createElement('span');
            toggleIcon.className = hasChildren ? 'toggle-icon collapsed' : 'toggle-icon empty';
            toggleIcon.innerHTML = hasChildren ? '<i class="fas fa-chevron-right"></i>' : '';

            const nameSpan = document.createElement('span');
            nameSpan.className = 'folder-node';
            nameSpan.innerHTML = `<i class="fas fa-folder"></i> `+n.name;
            if (selectedFolderId === n.id) nameSpan.classList.add('selected');

            nameSpan.onclick = () => {
                selectedFolderId = n.id;
                document.querySelectorAll('.folder-node').forEach(el => el.classList.remove('selected'));
                nameSpan.classList.add('selected');
                loadInstances(n.id);
            };

            const childContainer = document.createElement('div');
            childContainer.className = 'folder-children';
            if (hasChildren) {
                render(n.children, childContainer);
                childContainer.style.display = 'none';
            }

            toggleIcon.onclick = (e) => {
                e.stopPropagation(); // 防止触发选中事件
                if (!hasChildren) return;
                const isCollapsed = toggleIcon.classList.contains('collapsed');
                toggleIcon.classList.toggle('collapsed', !isCollapsed);
                toggleIcon.classList.toggle('expanded', isCollapsed);
                toggleIcon.innerHTML = isCollapsed
                    ? '<i class="fas fa-chevron-down"></i>'
                    : '<i class="fas fa-chevron-right"></i>';
                childContainer.style.display = isCollapsed ? 'block' : 'none';
            };

            nodeWrapper.appendChild(toggleIcon);
            nodeWrapper.appendChild(nameSpan);
            container.appendChild(nodeWrapper);
            container.appendChild(childContainer);
        });
    }


    function getSavedThemeKey() {
        return localStorage.getItem('terminal.theme') || 'matrix';
    }

    function applyThemeByKey(key) {
        const th = TerminalThemes[key] || TerminalThemes['matrix'];
        term.setOption('theme', th);
        // 同步下拉选中状态
        const select = document.getElementById('themeSelect');
        if (select && select.value !== key) select.value = key;
        localStorage.setItem('terminal.theme', key);
    }
    function initTerminal() {
        term = new Terminal({
            cursorBlink: true,
            fontSize: 14,
            fontFamily: 'Fira Code, monospace',
            scrollback: 3000
        });

        fitAddon = new FitAddon.FitAddon();
        term.loadAddon(fitAddon);

        try {
            if (window.WebglAddon) {
                webglAddon = new WebglAddon.WebglAddon();
                term.loadAddon(webglAddon);
            }
        } catch (e) { /* ignore */ }

        term.loadAddon(new WebLinksAddon.WebLinksAddon());

        term.open(document.getElementById('terminal'));
        fitAddon.fit();

        // 应用主题
        applyThemeByKey(getSavedThemeKey());

        window.addEventListener('resize', resizeTerminal);

        term.onData(function(data) {
            if (connected && websocket) {
                websocket.send(JSON.stringify({ type: 'input', data: data }));
            }
        });

        window.addEventListener('paste', async (e) => {
            if (!connected || !websocket) return;
            const text = (e.clipboardData || window.clipboardData).getData('text');
            if (text) {
                websocket.send(JSON.stringify({ type: 'input', data: text }));
            }
        });
        term.writeln(i18n.ssh_welcome);
        term.writeln('');
    }

    function resizeTerminal() {
        if (!fitAddon) return;
        fitAddon.fit();
        if (connected && websocket) {
            const dims = fitAddon.proposeDimensions();
            if (dims && dims.cols && dims.rows) {
                websocket.send(JSON.stringify({
                    type: 'resize',
                    data: { cols: dims.cols, rows: dims.rows }
                }));
            }
        }
    }

    function saveConfiguration() {
        var username = document.getElementById('username').value;
        var host = document.getElementById('host').value;
        var port = document.getElementById('port').value;
        var password = document.getElementById('password').value;

        if (!username || !port || !instanceId) {
            Swal.fire(
                {
                    title: 'warning',
                    text: i18n.common_plzInputGlobalRequired,
                    icon: 'warning',
                    confirmButtonText: i18n.common_confirm
                });
            return;
        }

        Swal.fire({ title: 'loading', allowOutsideClick: false, showConfirmButton: false, didOpen: () => Swal.showLoading() });

        var csrfToken = document.querySelector('input[name="_csrf"]').value;
        var config = { instanceId: instanceId, username: username, port: port, password: password };

        fetch('/oci/ssh/config', {
            method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrfToken },
            body: JSON.stringify(config)
        })
            .then(r => r.ok ? r.json() : Promise.reject('HTTP ' + r.status))
            .then(data => {
                if (data.success) Swal.fire({ title: 'success', text: 'successful', icon: 'success', confirmButtonText: i18n.common_confirm });
                else Swal.fire({ title: 'error', text: data.message || 'error', icon: 'error', confirmButtonText: i18n.common_confirm });
            })
            .catch(err => Swal.fire({ title: 'error', text: 'error: ' + err, icon: 'error', confirmButtonText: i18n.common_confirm }));
    }

    function loadSshConfig() {
        if (!instanceId || instanceId.trim() === '') {
            return;
        }

        fetch('/oci/ssh/config/' + instanceId)
            .then(r => {
                if (!r.ok) throw new Error('HTTP ' + r.status);
                return r.json();
            })
            .then(data => {
                if (data.success && data.data) {
                    const cfg = data.data;
                    document.getElementById('username').value = cfg.username || '';
                    document.getElementById('host').value = cfg.host || '';
                    document.getElementById('port').value = cfg.port || '22';
                    document.getElementById('password').value = cfg.sshPassword || '';
                } else {
                    console.warn('未找到 SSH 配置或返回异常');
                }
            })
            .catch(err => console.error('加载SSH配置失败:', err));
    }

    function connectToSsh() {
        if (connecting) return;

        var host = document.getElementById('host').value;
        var username = document.getElementById('username').value;
        var port = document.getElementById('port').value;
        var password = document.getElementById('password').value;

        if (!host || !username || !port || !password) {
            term.writeln('\r\n\x1b[31m请填写完整的连接信息\x1b[0m');
            return;
        }

        connecting = true; showLoading();
        if (websocket) websocket.close();

        var protocol = location.protocol === 'https:' ? 'wss://' : 'ws://';
        websocket = new WebSocket(protocol + location.host + '/ws/ssh');

        websocket.onopen = function() {
            websocket.send(JSON.stringify({
                type: 'connect',
                data: { host: host, port: parseInt(port), username: username, password: password }
            }));
            updateConnectionStatus(true, i18n.ssh_conecting);
        };

        websocket.onmessage = function(event) {
            try {
                var msg = JSON.parse(event.data);
                if (msg.type === 'output') term.write(msg.data);
                else if (msg.type === 'error') {
                    term.writeln('\r\n\x1b[31m' + msg.message + '\x1b[0m');
                    disconnectFromSsh();
                }
            } catch (e) {
                term.write(event.data);
            }

            if (!connected) {
                connected = true;
                document.getElementById('connectBtn').disabled = true;
                document.getElementById('disconnectBtn').disabled = false;
                updateConnectionStatus(true, i18n.ssh_connected);
                resizeTerminal();
            }

            hideLoading(); connecting = false;
        };

        websocket.onclose = function() {
            if (!isDisconnecting) disconnectFromSsh();
            hideLoading(); connecting = false; isDisconnecting = false;
        };

        websocket.onerror = function() {
            term.writeln('\r\n\x1b[31mWebSocketerror\x1b[0m');
            disconnectFromSsh(); hideLoading(); connecting = false;
        };
    }

    function disconnectFromSsh() {
        if (websocket) { isDisconnecting = true; websocket.close(); }
        connected = false;
        document.getElementById('connectBtn').disabled = false;
        document.getElementById('disconnectBtn').disabled = true;
        updateConnectionStatus(false, i18n.ssh_connecStop);
        term.writeln('\r\n\x1b[33mconnect error\x1b[0m');
    }

    function updateConnectionStatus(isConnected, statusText) {
        var status = document.querySelector('.connection-status');
        status.className = isConnected ? 'connection-status connected' : 'connection-status disconnected';
        status.innerHTML = '<i class="fas fa-circle"></i><span>' + statusText + '</span>';
        document.getElementById('status-text').textContent = isConnected ? i18n.ssh_connecAlready : i18n.ssh_connecWait;
    }

    function initSidebar() {
        const navParents = document.querySelectorAll('.nav-parent');
        navParents.forEach(parent => {
            const parentLink = parent.querySelector('.nav-link');
            parentLink.addEventListener('click', (e) => {
                e.preventDefault();
                parent.classList.toggle('expanded');
            });
        });
        const activeLink = document.querySelector('.nav-link.active');
        if (activeLink) {
            const parent = activeLink.closest('.nav-parent');
            if (parent) {
                parent.classList.add('expanded');
            }
        }
    }

    function togglePassword() {
        var input = document.getElementById('password');
        var eye = document.querySelector('.password-action-btn i');
        if (input.type === 'password') { input.type = 'text'; eye.classList.remove('fa-eye'); eye.classList.add('fa-eye-slash'); }
        else { input.type = 'password'; eye.classList.remove('fa-eye-slash'); eye.classList.add('fa-eye'); }
    }
    function copyPassword() {
        var v = document.getElementById('password').value;
        if (!v) return Swal.fire({ title: 'warning', text: i18n.ssh_passBlank, icon: 'info', confirmButtonText: i18n.common_confirm });
        navigator.clipboard.writeText(v).then(() => Swal.fire({ title: 'success', text: i18n.ssh_passCopySucc, icon: 'success', timer: 1200, showConfirmButton: false }))
            .catch(err => Swal.fire({ title: 'warning', text: 'error：' + err, icon: 'error', confirmButtonText: i18n.common_confirm }));
    }

    (function initContextMenu(){
        const menu = document.getElementById('ctxMenu');
        const elTerminal = document.getElementById('terminal');

        function showMenu(x,y){ menu.style.display='block'; menu.style.left=x+'px'; menu.style.top=y+'px'; }
        function hideMenu(){ menu.style.display='none'; }

        elTerminal.addEventListener('contextmenu', function(e){
            e.preventDefault();
            showMenu(e.clientX, e.clientY);
        });
        window.addEventListener('click', hideMenu);
        window.addEventListener('blur', hideMenu);
        window.addEventListener('resize', hideMenu);

        document.getElementById('ctxCopy').onclick = function(){
            const text = term.getSelection();
            if (!text) return;
            navigator.clipboard.writeText(text).then(()=> {
                hideMenu();
                term.focus();
            });
        };
        document.getElementById('ctxPaste').onclick = async function(){
            hideMenu();
            if (!connected || !websocket) return;
            try {
                const text = await navigator.clipboard.readText();
                if (text) websocket.send(JSON.stringify({ type: 'input', data: text }));
            } catch(e){}
            term.focus();
        };
        document.getElementById('ctxSelectAll').onclick = function(){
            term.selectAll();
            hideMenu();
            term.focus();
        };

        // 兼容键盘：Ctrl+Insert 复制，Shift+Insert 粘贴（类 Windows 终端）
        window.addEventListener('keydown', async (e) => {
            if (e.ctrlKey && e.key === 'Insert') { // 复制
                const t = term.getSelection();
                if (t) await navigator.clipboard.writeText(t);
            } else if (e.shiftKey && e.key === 'Insert') { // 粘贴
                if (connected && websocket) {
                    try { const text = await navigator.clipboard.readText(); if (text) websocket.send(JSON.stringify({type:'input', data:text})); } catch(e){}
                }
            }
        });
    })();

    (function initThemeSelect(){
        const sel = document.getElementById('themeSelect');
        sel.value = getSavedThemeKey();
        sel.addEventListener('change', function(){
            applyThemeByKey(sel.value);
        });
    })();

    document.addEventListener('DOMContentLoaded', function() {
        initTerminal();
        loadSshConfig();
        initSidebar();

        document.getElementById('connectBtn').addEventListener('click', connectToSsh);
        document.getElementById('disconnectBtn').addEventListener('click', disconnectFromSsh);
        document.getElementById('saveConfigBtn').addEventListener('click', saveConfiguration);
    });
    window.addEventListener('load', function() {
        const sidebar = document.querySelector('.sidebar');
        if (sidebar) sidebar.style.zIndex = '2000';

        const termEl = document.getElementById('terminal');
        if (termEl) {
            termEl.style.zIndex = '1';
            termEl.style.pointerEvents = 'auto'; // 保留可交互
        }

        document.querySelectorAll('.nav-parent > .nav-link').forEach(link => {
            link.onclick = function(e) {
                e.preventDefault();
                const parent = link.closest('.nav-parent');
                if (parent) parent.classList.toggle('expanded');
            };
        });

        const active = document.querySelector('.nav-link.active');
        if (active) {
            const parent = active.closest('.nav-parent');
            if (parent) parent.classList.add('expanded');
        }

        console.log('✅ Sidebar interaction restored.');
    });

</script>
</body>
</html>
