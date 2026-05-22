<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - SSH终端</title>
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
<#--
    <link href="https://fonts.googleapis.com/css2?family=Fira+Code:wght@400;500&display=swap" rel="stylesheet">
-->
    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@4.19.0/css/xterm.css" />
    <link rel="stylesheet" href="/css/sweetalert2.min.css">
    <script src="/js/sweetalert2.min.js"></script>

    <link rel="stylesheet" href="/css/common/loading.css">

    <!-- 使用你本地的 xterm 资源（保持你原有结构） -->
    <script src="/js/xterm.js"></script>
    <script src="/js/xterm-addon-fit.js"></script>
    <script src="/js/xterm-addon-web-links.js"></script>
    <script src="/js/xterm-addon-webgl.js" defer></script>
<#--
    <script src="https://cdn.jsdelivr.net/npm/xterm-addon-webgl@0.14.0/lib/xterm-addon-webgl.js"></script>
-->


    <link rel="stylesheet" href="/css/styles.css">
    <link rel="stylesheet" href="/css/app/ssh_tool.css">
</head>
<body>
<#--<#include "common/header.ftl">-->

<div class="loading-overlay"><div class="spinner"></div></div>

<div class="layout">
    <#--<#include "common/sidebar.ftl">-->

    <main class="main-content">

        <div class="folder-panel-trigger">
            <button id="openFolderBtn" class="folder-toggle-btn">
                <i class="fas fa-folder-open"></i>
            </button>
        </div>

        <div class="ssh-config-panel">
            <input type="hidden" name="${_csrf.parameterName}" value="${_csrf.token}"/>
            <div class="ssh-config-form">
                <div class="ssh-config-item">
                    <label class="ssh-config-label"><i class="fas fa-user"></i>用户名</label>
                    <input type="text" id="username" class="ssh-input" placeholder="请输入用户名">
                </div>
                <div class="ssh-config-item">
                    <label class="ssh-config-label"><i class="fas fa-network-wired"></i>主机地址</label>
                    <input type="text" id="host" class="ssh-input" placeholder="请输入主机地址">
                </div>
                <div class="ssh-config-item">
                    <label class="ssh-config-label"><i class="fas fa-door-open"></i>端口</label>
                    <input type="text" id="port" class="ssh-input" value="22" placeholder="SSH端口">
                </div>
                <div class="ssh-config-item">
                    <label class="ssh-config-label"><i class="fas fa-key"></i>密码</label>
                    <div class="password-container">
                        <input type="password" id="password" class="ssh-input" placeholder="请输入密码">
                        <button type="button" class="password-action-btn" onclick="togglePassword()" title="显示/隐藏密码">
                            <i class="fas fa-eye"></i>
                        </button>
                        <button type="button" class="password-action-btn" onclick="copyPassword()" title="复制密码">
                            <i class="fas fa-copy"></i>
                        </button>
                    </div>
                </div>
                <div class="ssh-config-item">
                    <div style="display:flex;gap:10px;align-items:center;">
                        <button id="saveConfigBtn" class="save-config-btn">
                            <i class="fas fa-save"></i> 保存
                        </button>
                        <button onclick="history.back()" class="save-config-btn">
                            <i class="fas fa-arrow-left"></i> 返回
                        </button>
                    </div>
                </div>
            </div>
        </div>

        <div class="terminal-wrapper">
            <div class="terminal-header">
                <div class="terminal-title">
                    <i class="fas fa-terminal"></i> SSH终端
                </div>

                <div class="terminal-controls">
                    <button id="connectBtn" class="btn-connect">
                        <i class="fas fa-plug"></i>连接
                    </button>
                    <button id="disconnectBtn" class="btn-disconnect" disabled>
                        <i class="fas fa-times"></i>断开
                    </button>
                    <div class="connection-status disconnected">
                        <i class="fas fa-circle"></i><span>未连接</span>
                    </div>

                    <!--  新增主题切换 -->
                    <select id="themeSelect" class="theme-select" title="终端主题">
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
                <span id="status-text">等待连接...</span>
            </div>
        </div>

    </main>
</div>

<!-- 文件夹抽屉 -->
<!-- 文件夹模态框 -->
<div id="folderModal" class="folder-modal">
    <div class="folder-modal-content">
        <div class="folder-modal-header">
            <span><i class="fas fa-folder-tree"></i> 文件夹与实例</span>
            <button id="closeFolderModalBtn" class="folder-close-btn"><i class="fas fa-times"></i></button>
        </div>
        <div class="folder-modal-body">
            <div class="folder-left">
                <div id="folderTree" class="folder-tree"></div>
                <div class="folder-actions">
                    <button id="addFolderBtn" class="folder-action-btn"><i class="fas fa-plus"></i> 新建文件夹</button>
                    <button id="addInstanceBtn" class="folder-action-btn"><i class="fas fa-terminal"></i> 新建实例</button>
                </div>
            </div>
            <div class="folder-right">
                <div id="instanceList" class="instance-list">
                    <p class="empty-text">请选择一个文件夹以查看实例</p>
                </div>
            </div>
        </div>
    </div>
</div>


<!-- 右键菜单 -->
<div id="ctxMenu" class="ctx-menu">
    <div class="ctx-item" id="ctxCopy"><i class="fas fa-copy"></i> 复制所选</div>
    <div class="ctx-item" id="ctxPaste"><i class="fas fa-paste"></i> 粘贴剪贴板</div>
    <div class="ctx-sep"></div>
    <div class="ctx-item" id="ctxSelectAll"><i class="fas fa-i-cursor"></i> 全选</div>
</div>

<#--<#include "common/version_info.ftl">-->
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script>
    // ------------------------------
    // 变量与主题定义
    // ------------------------------
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

            // 判断是否有子节点
            const hasChildren = n.children && n.children.length > 0;

            // 创建图标区域
            const toggleIcon = document.createElement('span');
            toggleIcon.className = hasChildren ? 'toggle-icon collapsed' : 'toggle-icon empty';
            toggleIcon.innerHTML = hasChildren ? '<i class="fas fa-chevron-right"></i>' : '';

            // 文件夹名称
            const nameSpan = document.createElement('span');
            nameSpan.className = 'folder-node';
            nameSpan.innerHTML = `<i class="fas fa-folder"></i> `+n.name;
            if (selectedFolderId === n.id) nameSpan.classList.add('selected');

            // 点击文件夹高亮
            nameSpan.onclick = () => {
                selectedFolderId = n.id;
                document.querySelectorAll('.folder-node').forEach(el => el.classList.remove('selected'));
                nameSpan.classList.add('selected');
                loadInstances(n.id);
            };

            // 子容器
            const childContainer = document.createElement('div');
            childContainer.className = 'folder-children';
            if (hasChildren) {
                render(n.children, childContainer);
                childContainer.style.display = 'none';
            }

            // 点击 “>” 切换展开/折叠
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

    // ------------------------------
    // 初始化终端
    // ------------------------------
    function initTerminal() {
        term = new Terminal({
            cursorBlink: true,
            fontSize: 14,
            fontFamily: 'Fira Code, monospace',
            scrollback: 3000
        });

        fitAddon = new FitAddon.FitAddon();
        term.loadAddon(fitAddon);

        // 如存在 WebGL 插件则启用（更丝滑）
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

        // 真实终端：输入直接发送给后端，不做本地行编辑
        term.onData(function(data) {
            if (connected && websocket) {
                websocket.send(JSON.stringify({ type: 'input', data: data }));
            }
        });

        // 监听浏览器 paste 事件（Ctrl+V / 右键粘贴也能触发）
        window.addEventListener('paste', async (e) => {
            if (!connected || !websocket) return;
            const text = (e.clipboardData || window.clipboardData).getData('text');
            if (text) {
                websocket.send(JSON.stringify({ type: 'input', data: text }));
            }
        });

        // 初始文案
        term.writeln('欢迎使用 OCI-START 终端！请配置连接信息并点击连接按钮。');
        term.writeln('');
    }

    // 同步终端尺寸到后端（避免 vim/top 换行错位）
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

    // ------------------------------
    // 保存/加载 SSH 配置（保持你的逻辑）
    // ------------------------------
    function saveConfiguration() {
        var username = document.getElementById('username').value;
        var host = document.getElementById('host').value;
        var port = document.getElementById('port').value;
        var password = document.getElementById('password').value;

        if (!username || !port || !instanceId) {
            Swal.fire({ title: '警告', text: '请填写必要的配置信息', icon: 'warning', confirmButtonText: '确定' });
            return;
        }

        Swal.fire({ title: '保存中...', allowOutsideClick: false, showConfirmButton: false, didOpen: () => Swal.showLoading() });

        var csrfToken = document.querySelector('input[name="${_csrf.parameterName}"]').value;
        var config = { instanceId: instanceId, username: username, port: port, password: password };

        fetch('/oci/ssh/config', {
            method: 'POST', headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrfToken },
            body: JSON.stringify(config)
        })
            .then(r => r.ok ? r.json() : Promise.reject('HTTP ' + r.status))
            .then(data => {
                if (data.success) Swal.fire({ title: '成功', text: '配置保存成功', icon: 'success', confirmButtonText: '确定' });
                else Swal.fire({ title: '错误', text: data.message || '保存失败', icon: 'error', confirmButtonText: '确定' });
            })
            .catch(err => Swal.fire({ title: '错误', text: '保存失败: ' + err, icon: 'error', confirmButtonText: '确定' }));
    }

    function loadSshConfig() {
        // 安全检测 instanceId
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


    // ------------------------------
    // 连接 / 断开（保持你的协议 & 交互）
    // ------------------------------
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
            updateConnectionStatus(true, '正在连接...');
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
                updateConnectionStatus(true, '已连接');
                resizeTerminal(); // 首次连接立即同步尺寸
            }

            hideLoading(); connecting = false;
        };

        websocket.onclose = function() {
            if (!isDisconnecting) disconnectFromSsh();
            hideLoading(); connecting = false; isDisconnecting = false;
        };

        websocket.onerror = function() {
            term.writeln('\r\n\x1b[31mWebSocket连接错误\x1b[0m');
            disconnectFromSsh(); hideLoading(); connecting = false;
        };
    }

    function disconnectFromSsh() {
        if (websocket) { isDisconnecting = true; websocket.close(); }
        connected = false;
        document.getElementById('connectBtn').disabled = false;
        document.getElementById('disconnectBtn').disabled = true;
        updateConnectionStatus(false, '未连接');
        term.writeln('\r\n\x1b[33m连接已断开\x1b[0m');
    }

    function updateConnectionStatus(isConnected, statusText) {
        var status = document.querySelector('.connection-status');
        status.className = isConnected ? 'connection-status connected' : 'connection-status disconnected';
        status.innerHTML = '<i class="fas fa-circle"></i><span>' + statusText + '</span>';
        document.getElementById('status-text').textContent = isConnected ? '连接已建立' : '等待连接...';
    }

    function showLoading() {
        const overlay = document.querySelector('.loading-overlay');
        overlay.style.display = 'flex';
        overlay.style.pointerEvents = 'auto';
    }
    function hideLoading() {
        const overlay = document.querySelector('.loading-overlay');
        overlay.style.display = 'none';
        overlay.style.pointerEvents = 'none';
    }

    function initSidebar() {
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
    }

    // ------------------------------
    // 密码可见 / 复制（保持你的逻辑）
    // ------------------------------
    function togglePassword() {
        var input = document.getElementById('password');
        var eye = document.querySelector('.password-action-btn i');
        if (input.type === 'password') { input.type = 'text'; eye.classList.remove('fa-eye'); eye.classList.add('fa-eye-slash'); }
        else { input.type = 'password'; eye.classList.remove('fa-eye-slash'); eye.classList.add('fa-eye'); }
    }
    function copyPassword() {
        var v = document.getElementById('password').value;
        if (!v) return Swal.fire({ title: '提示', text: '密码为空', icon: 'info', confirmButtonText: '确定' });
        navigator.clipboard.writeText(v).then(() => Swal.fire({ title: '成功', text: '密码已复制', icon: 'success', timer: 1200, showConfirmButton: false }))
            .catch(err => Swal.fire({ title: '错误', text: '复制失败：' + err, icon: 'error', confirmButtonText: '确定' }));
    }

    // ------------------------------
    // 右键菜单：复制 / 粘贴 / 全选
    // ------------------------------
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

    // ------------------------------
    // 主题切换下拉
    // ------------------------------
    (function initThemeSelect(){
        const sel = document.getElementById('themeSelect');
        sel.value = getSavedThemeKey();
        sel.addEventListener('change', function(){
            applyThemeByKey(sel.value);
        });
    })();

    // ------------------------------
    // 启动
    // ------------------------------
    document.addEventListener('DOMContentLoaded', function() {
        initTerminal();
        loadSshConfig();
        initSidebar();

        document.getElementById('connectBtn').addEventListener('click', connectToSsh);
        document.getElementById('disconnectBtn').addEventListener('click', disconnectFromSsh);
        document.getElementById('saveConfigBtn').addEventListener('click', saveConfiguration);
    });

    // ===== 文件夹抽屉逻辑 =====
    document.addEventListener('DOMContentLoaded', function() {
        const modal = document.getElementById('folderModal');
        const openBtn = document.getElementById('openFolderBtn');
        const closeBtn = document.getElementById('closeFolderModalBtn');
        const addFolderBtn = document.getElementById('addFolderBtn');
        const addInstanceBtn = document.getElementById('addInstanceBtn');
        const instanceList = document.getElementById('instanceList');

        const csrfInput = document.querySelector('input[name="${_csrf.parameterName}"]');
        const csrfHeaderName = '${_csrf.headerName}';
        const csrfToken = csrfInput ? csrfInput.value : null;

        // 打开模态框
        openBtn.addEventListener('click', () => {
            modal.classList.add('show');
            loadTree();
        });

        // 关闭模态框
        closeBtn.addEventListener('click', () => modal.classList.remove('show'));

        // 点击文件夹加载实例
        function render(data, container) {
            container.innerHTML = '';

            data.forEach(n => {
                const nodeWrapper = document.createElement('div');
                nodeWrapper.className = 'folder-item';
                const nameSpan = document.createElement('span');
                nameSpan.className = 'folder-node';
                nameSpan.innerHTML = `<i class="fas fa-folder"></i> `+ n.name;+``;
                nameSpan.onclick = () => {
                    selectedFolderId = n.id;
                    document.querySelectorAll('.folder-node').forEach(el => el.classList.remove('selected'));
                    nameSpan.classList.add('selected');
                    loadInstances(n.id);
                };
                nodeWrapper.appendChild(nameSpan);
                container.appendChild(nodeWrapper);

                if (n.children && n.children.length > 0) {
                    const childContainer = document.createElement('div');
                    childContainer.className = 'folder-children';
                    render(n.children, childContainer);
                    container.appendChild(childContainer);
                }
            });
        }

        function loadTree() {
            fetch('/ssh/folders/tree')
                .then(r => r.json())
                .then(res => {
                    if (!res.success || !res.data) return;
                    const tree = document.getElementById('folderTree');
                    render(res.data, tree);
                });
        }

        // 加载实例列表
        function loadInstances(folderId) {
            fetch(`/ssh/folders/`+ folderId+`/instances`, { headers: { 'X-Requested-With': 'XMLHttpRequest' } })
                .then(r => r.json())
                .then(res => {
                    instanceList.innerHTML = '';
                    if (!res.success || !res.data || res.data.length === 0) {
                        instanceList.innerHTML = '<p class="empty-text">该文件夹下暂无实例</p>';
                        return;
                    }
                    res.data.forEach(inst => {
                        const card = document.createElement('div');
                        card.className = 'instance-card';
                        card.innerHTML = `
                        <h4>`+ inst.name+`</h4>
                        <p>主机: `+ inst.host+`</p>
                        <p>用户: `+ inst.username+`</p>
                        <p>端口: `+ inst.port+`</p>
                    `;
                        instanceList.appendChild(card);
                    });
                });
        }
    });

    const addInstanceBtn = document.getElementById('addInstanceBtn');

    addInstanceBtn.addEventListener('click', () => {
        if (!selectedFolderId) {
            Swal.fire('提示', '请先选择一个文件夹', 'info');
            return;
        }
        Swal.fire({
            title: '添加实例',
            html: `
            <input id="inst-name" class="swal2-input" placeholder="实例名称">
            <input id="inst-host" class="swal2-input" placeholder="主机地址">
            <input id="inst-user" class="swal2-input" placeholder="用户名">
            <input id="inst-port" class="swal2-input" placeholder="端口 (默认22)" value="22">
            <input id="inst-pass" class="swal2-input" type="password" placeholder="密码">
        `,
            focusConfirm: false,
            showCancelButton: true,
            confirmButtonText: '保存',
            cancelButtonText: '取消',
            preConfirm: () => {
                const name = document.getElementById('inst-name').value.trim();
                const host = document.getElementById('inst-host').value.trim();
                const user = document.getElementById('inst-user').value.trim();
                const port = document.getElementById('inst-port').value.trim() || '22';
                const pass = document.getElementById('inst-pass').value.trim();
                if (!name || !host || !user || !pass) {
                    Swal.showValidationMessage('请填写完整信息');
                    return false;
                }
                return { name, host, user, port, pass };
            }
        }).then(result => {
            if (result.isConfirmed) {
                createInstance(selectedFolderId, result.value);
            }
        });
    });

    function createInstance(folderId, inst) {
        fetch('/ssh/instances/create', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            },
            body: JSON.stringify({
                folderId: folderId,
                name: inst.name,
                host: inst.host,
                username: inst.user,
                port: parseInt(inst.port),
                password: inst.pass
            })
        })
            .then(r => r.json())
            .then(res => {
                if (res.success) {
                    Swal.fire('成功', '实例已创建', 'success');
                    loadInstances(folderId);
                } else {
                    Swal.fire('错误', res.message || '创建失败', 'error');
                }
            })
            .catch(() => Swal.fire('错误', '网络异常', 'error'));
    }

    function loadInstances(id) {
        fetch(`/ssh/folders/`+ id+`/instances`, {
            headers: { 'X-Requested-With': 'XMLHttpRequest' }
        })
            .then(r => r.json())
            .then(res => {
                if (res.success) {
                    Swal.fire('文件夹', `该文件夹下共有 `+ res.data.length+` 个实例`, 'info');
                }
            });
    }

    window.addEventListener('load', function() {
        // 保证 sidebar 在顶层
        const sidebar = document.querySelector('.sidebar');
        if (sidebar) sidebar.style.zIndex = '2000';

        // 如果 Xterm 存在，允许点击穿透
        const termEl = document.getElementById('terminal');
        if (termEl) {
            termEl.style.zIndex = '1';
            termEl.style.pointerEvents = 'auto'; // 保留可交互
        }

        // 确保侧边栏事件重新绑定（即使被覆盖）
        document.querySelectorAll('.nav-parent > .nav-link').forEach(link => {
            link.onclick = function(e) {
                e.preventDefault();
                const parent = link.closest('.nav-parent');
                if (parent) parent.classList.toggle('expanded');
            };
        });

        // 自动展开当前 active 菜单
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
