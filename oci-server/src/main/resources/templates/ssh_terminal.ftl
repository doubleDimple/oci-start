<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - SSH终端</title>
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <script>function _getCsrfToken(){var i=document.querySelector('input[name="_csrf"]');if(i)return i.value;var m=document.querySelector('meta[name="_csrf"]');return m?(m.getAttribute('content')||''):''}</script>
    <script>(function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();</script>

    <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/xterm@4.19.0/css/xterm.css" />
    <link rel="stylesheet" href="/css/sweetalert2.min.css">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/common/fa-fix.css">
    <script src="/js/xterm.js"></script>
    <script src="/js/xterm-addon-fit.js"></script>
    <script src="/js/xterm-addon-web-links.js"></script>
    <script src="/js/xterm-addon-webgl.js" defer></script>
    <link rel="stylesheet" href="/css/app/ssh_terminal.css">
</head>
<body>

<div class="layout">
    <main class="main-content">

        <!-- 配置面板 -->
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
                <div class="ssh-config-item" style="margin-left:auto;">
                    <label class="ssh-config-label" style="visibility:hidden">.</label>
                    <div style="display:flex;gap:8px;align-items:center;">
                        <button id="saveConfigBtn" class="save-config-btn">
                            <i class="fas fa-save"></i> ${msg.get("common.save")}
                        </button>
                        <button onclick="history.back()" class="save-config-btn" style="background:var(--text-secondary)">
                            <i class="fas fa-arrow-left"></i> ${msg.get("common.rollback")}
                        </button>
                    </div>
                </div>
            </div>
        </div>

        <!-- 终端区域 -->
        <div class="terminal-wrapper" id="terminalWrapper">

            <!-- 顶部工具栏 -->
            <div class="terminal-header">
                <div class="terminal-title">
                    <i class="fas fa-terminal"></i>
                    <span id="termTitle">${msg.get("ssh.sshConsole")}</span>
                </div>

                <div class="terminal-controls">
                    <!-- 连接 / 断开 / 状态 -->
                    <button id="connectBtn" class="btn-connect" title="连接 (Enter)">
                        <i class="fas fa-plug"></i>${msg.get("ssh.conn")}
                    </button>
                    <button id="reconnectBtn" class="tb-btn" title="重新连接" disabled>
                        <i class="fas fa-redo"></i>
                    </button>
                    <button id="disconnectBtn" class="btn-disconnect" disabled title="断开连接">
                        <i class="fas fa-times"></i>${msg.get("ssh.stop")}
                    </button>
                    <div class="connection-status disconnected" id="connStatus">
                        <i class="fas fa-circle"></i><span>${msg.get("ssh.noConn")}</span>
                    </div>

                    <div class="tb-divider"></div>

                    <!-- 实用操作 -->
                    <button class="tb-btn" id="clearBtn" title="清屏 (Ctrl+L)">
                        <i class="fas fa-eraser"></i>
                    </button>
                    <button class="tb-btn" id="copyCmdBtn" title="复制 SSH 连接命令">
                        <i class="fas fa-link"></i>
                    </button>
                    <button class="tb-btn" id="downloadLogBtn" title="下载终端日志">
                        <i class="fas fa-download"></i>
                    </button>

                    <div class="tb-divider"></div>

                    <!-- 字体大小 -->
                    <button class="tb-btn" id="fontDecBtn" title="减小字号 (Ctrl+-)">
                        <i class="fas fa-minus"></i>
                    </button>
                    <span class="font-size-label" id="fontSizeLabel">14px</span>
                    <button class="tb-btn" id="fontIncBtn" title="增大字号 (Ctrl+=)">
                        <i class="fas fa-plus"></i>
                    </button>

                    <div class="tb-divider"></div>

                    <!-- 主题 -->
                    <div class="select-wrapper">
                        <i class="fas fa-palette select-icon"></i>
                        <select id="themeSelect" class="tb-select" title="${msg.get("ssh.theme")}">
                            <option value="matrix">Matrix</option>
                            <option value="tokyonight">Tokyo Night</option>
                            <option value="dracula">Dracula</option>
                            <option value="nord">Nord</option>
                            <option value="monokai">Monokai</option>
                            <option value="solarizedLight">Solarized Light</option>
                            <option value="highContrast">High Contrast</option>
                        </select>
                    </div>

                    <div class="tb-divider"></div>

                    <!-- 全屏 -->
                    <button class="tb-btn" id="fullscreenBtn" title="全屏 (F11)">
                        <i class="fas fa-expand"></i>
                    </button>
                </div>
            </div>

            <!-- 搜索栏（默认隐藏，Ctrl+F 唤起） -->
            <div class="search-bar" id="searchBar">
                <i class="fas fa-search" style="color:#8892a4;font-size:12px;"></i>
                <input type="text" id="searchInput" class="search-input" placeholder="搜索终端内容...">
                <span class="search-count" id="searchCount"></span>
                <button class="search-nav-btn" id="searchPrev" title="上一个"><i class="fas fa-chevron-up"></i></button>
                <button class="search-nav-btn" id="searchNext" title="下一个"><i class="fas fa-chevron-down"></i></button>
                <button class="search-nav-btn" id="searchClose" title="关闭"><i class="fas fa-times"></i></button>
            </div>

            <div id="terminal"></div>

            <!-- 底部状态栏 -->
            <div class="terminal-footer">
                <span id="status-text">${msg.get("ssh.waitConn")}</span>
                <div class="footer-right">
                    <span class="footer-info" id="footerHost" style="display:none">
                        <i class="fas fa-server"></i> <span id="footerHostText"></span>
                    </span>
                    <span class="footer-sep" id="footerSep1" style="display:none">|</span>
                    <span class="footer-info" id="footerSize">
                        <i class="fas fa-expand-arrows-alt"></i> <span id="termSizeText">--</span>
                    </span>
                    <span class="footer-sep">|</span>
                    <span class="footer-info footer-hint">
                        <i class="fas fa-keyboard"></i> Ctrl+L 清屏 &nbsp;·&nbsp; F11 全屏 &nbsp;·&nbsp; 右键菜单
                    </span>
                </div>
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
    <div class="ctx-item" id="ctxClear"><i class="fas fa-eraser"></i> 清屏</div>
    <div class="ctx-sep"></div>
    <div class="ctx-item" id="ctxCopyCmd"><i class="fas fa-link"></i> 复制 SSH 命令</div>
    <div class="ctx-item" id="ctxDownload"><i class="fas fa-download"></i> 下载日志</div>
</div>

<script src="/js/common/loading.js"></script>
<script>
window.I18N = {
    ssh_welcome:                 "${msg.get('ssh.welcome')?js_string}",
    common_confirm:              "${msg.get('common.confirm')?js_string}",
    ssh_conecting:               "${msg.get('ssh.conecting')?js_string}",
    ssh_connected:               "${msg.get('ssh.connected')?js_string}",
    ssh_connecStop:              "${msg.get('ssh.connecStop')?js_string}",
    ssh_connecAlready:           "${msg.get('ssh.connecAlready')?js_string}",
    ssh_connecWait:              "${msg.get('ssh.connecWait')?js_string}",
    ssh_passBlank:               "${msg.get('ssh.passBlank')?js_string}",
    ssh_passCopySucc:            "${msg.get('ssh.passCopySucc')?js_string}",
    common_plzInputGlobalRequired: "${msg.get('common.plzInputGlobalRequired')?js_string}"
};
const i18n = window.I18N;

/* ── 全局状态 ── */
var term, websocket, fitAddon, webglAddon;
var connected    = false;
var connecting   = false;
var isDisconnecting = false;
var instanceId   = '${instanceId!''}';
var currentFontSize = parseInt(localStorage.getItem('terminal.fontSize') || '14', 10);
var outputBuffer = [];   // 用于「下载日志」

/* ── 终端主题 ── */
const TerminalThemes = {
    tokyonight: {
        background:'#1a1b26', foreground:'#a9b1d6', cursor:'#c0caf5',
        black:'#15161e', red:'#f7768e', green:'#9ece6a', yellow:'#e0af68',
        blue:'#7aa2f7', magenta:'#bb9af7', cyan:'#7dcfff', white:'#a9b1d6',
        brightBlack:'#414868', brightRed:'#f7768e', brightGreen:'#9ece6a',
        brightYellow:'#e0af68', brightBlue:'#7aa2f7', brightMagenta:'#bb9af7',
        brightCyan:'#7dcfff', brightWhite:'#c0caf5'
    },
    dracula: {
        background:'#282a36', foreground:'#f8f8f2', cursor:'#f8f8f2',
        black:'#000000', red:'#ff5555', green:'#50fa7b', yellow:'#f1fa8c',
        blue:'#bd93f9', magenta:'#ff79c6', cyan:'#8be9fd', white:'#bbbbbb',
        brightBlack:'#555555', brightRed:'#ff5555', brightGreen:'#50fa7b',
        brightYellow:'#f1fa8c', brightBlue:'#bd93f9', brightMagenta:'#ff79c6',
        brightCyan:'#8be9fd', brightWhite:'#ffffff'
    },
    nord: {
        background:'#2e3440', foreground:'#d8dee9', cursor:'#d8dee9',
        black:'#3b4252', red:'#bf616a', green:'#a3be8c', yellow:'#ebcb8b',
        blue:'#81a1c1', magenta:'#b48ead', cyan:'#88c0d0', white:'#e5e9f0',
        brightBlack:'#4c566a', brightRed:'#bf616a', brightGreen:'#a3be8c',
        brightYellow:'#ebcb8b', brightBlue:'#81a1c1', brightMagenta:'#b48ead',
        brightCyan:'#8fbcbb', brightWhite:'#eceff4'
    },
    monokai: {
        background:'#272822', foreground:'#f8f8f2', cursor:'#f8f8f0',
        black:'#272822', red:'#f92672', green:'#a6e22e', yellow:'#f4bf75',
        blue:'#66d9ef', magenta:'#ae81ff', cyan:'#a1efe4', white:'#f8f8f2',
        brightBlack:'#75715e', brightRed:'#f92672', brightGreen:'#a6e22e',
        brightYellow:'#f4bf75', brightBlue:'#66d9ef', brightMagenta:'#ae81ff',
        brightCyan:'#a1efe4', brightWhite:'#f9f8f5'
    },
    solarizedLight: {
        background:'#fdf6e3', foreground:'#657b83', cursor:'#657b83',
        black:'#073642', red:'#dc322f', green:'#859900', yellow:'#b58900',
        blue:'#268bd2', magenta:'#d33682', cyan:'#2aa198', white:'#eee8d5',
        brightBlack:'#002b36', brightRed:'#cb4b16', brightGreen:'#586e75',
        brightYellow:'#657b83', brightBlue:'#839496', brightMagenta:'#6c71c4',
        brightCyan:'#93a1a1', brightWhite:'#fdf6e3'
    },
    highContrast: {
        background:'#000000', foreground:'#ffffff', cursor:'#ffffff',
        black:'#000000', red:'#ff0000', green:'#00ff00', yellow:'#ffff00',
        blue:'#0088ff', magenta:'#ff00ff', cyan:'#00ffff', white:'#ffffff',
        brightBlack:'#7f7f7f', brightRed:'#ff4c4c', brightGreen:'#4cff4c',
        brightYellow:'#ffff4c', brightBlue:'#4c9dff', brightMagenta:'#ff4cff',
        brightCyan:'#4cffff', brightWhite:'#ffffff'
    },
    matrix: {
        background:'#000000', foreground:'#00ff00', cursor:'#00ff00',
        black:'#000000', red:'#ff0000', green:'#00ff00', yellow:'#ffff00',
        blue:'#00ffff', magenta:'#ff00ff', cyan:'#00ffff', white:'#ffffff',
        brightBlack:'#333333', brightRed:'#ff5555', brightGreen:'#00ff00',
        brightYellow:'#ffff55', brightBlue:'#55ffff', brightMagenta:'#ff55ff',
        brightCyan:'#55ffff', brightWhite:'#ffffff'
    }
};

/* ── 主题工具 ── */
function getSavedThemeKey() {
    return localStorage.getItem('terminal.theme') || 'matrix';
}
function applyThemeByKey(key) {
    const th = TerminalThemes[key] || TerminalThemes['matrix'];
    term.setOption('theme', th);
    const sel = document.getElementById('themeSelect');
    if (sel && sel.value !== key) sel.value = key;
    localStorage.setItem('terminal.theme', key);
}

/* ── 字体大小 ── */
function setFontSize(size) {
    size = Math.max(10, Math.min(24, size));
    currentFontSize = size;
    term.setOption('fontSize', size);
    document.getElementById('fontSizeLabel').textContent = size + 'px';
    localStorage.setItem('terminal.fontSize', size);
    setTimeout(resizeTerminal, 50);
}

/* ── 终端初始化 ── */
function initTerminal() {
    term = new Terminal({
        cursorBlink: true,
        fontSize: currentFontSize,
        fontFamily: 'Fira Code, Menlo, Consolas, monospace',
        scrollback: 5000,
        allowProposedApi: true
    });

    fitAddon = new FitAddon.FitAddon();
    term.loadAddon(fitAddon);

    try {
        if (window.WebglAddon) {
            webglAddon = new WebglAddon.WebglAddon();
            term.loadAddon(webglAddon);
        }
    } catch(e) {}

    term.loadAddon(new WebLinksAddon.WebLinksAddon());
    term.open(document.getElementById('terminal'));
    fitAddon.fit();

    document.getElementById('fontSizeLabel').textContent = currentFontSize + 'px';
    applyThemeByKey(getSavedThemeKey());
    updateTermSize();

    window.addEventListener('resize', () => { resizeTerminal(); updateTermSize(); });

    term.onData(data => {
        if (connected && websocket) websocket.send(JSON.stringify({ type:'input', data }));
    });

    // 缓存输出用于下载
    term.onWriteParsed = undefined; // xterm 4.x 无此事件，改用 onData buffer trick
    const origWrite = term.write.bind(term);
    term.write = function(data) {
        outputBuffer.push(typeof data === 'string' ? data : new TextDecoder().decode(data));
        origWrite(data);
    };

    window.addEventListener('paste', async (e) => {
        if (!connected || !websocket) return;
        const text = (e.clipboardData || window.clipboardData).getData('text');
        if (text) websocket.send(JSON.stringify({ type:'input', data: text }));
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
            websocket.send(JSON.stringify({ type:'resize', data:{ cols:dims.cols, rows:dims.rows } }));
        }
    }
    updateTermSize();
}

function updateTermSize() {
    if (!term) return;
    const el = document.getElementById('termSizeText');
    if (el) el.textContent = term.cols + ' × ' + term.rows;
}

/* ── 连接 / 断开 ── */
function connectToSsh() {
    if (connecting) return;
    var host     = document.getElementById('host').value.trim();
    var username = document.getElementById('username').value.trim();
    var port     = document.getElementById('port').value.trim();
    var password = document.getElementById('password').value;

    if (!host || !username || !port || !password) {
        term.writeln('\r\n\x1b[31m请填写完整的连接信息\x1b[0m');
        return;
    }

    connecting = true; showLoading();
    if (websocket) websocket.close();

    var protocol = location.protocol === 'https:' ? 'wss://' : 'ws://';
    websocket = new WebSocket(protocol + location.host + '/ws/ssh');

    websocket.onopen = () => {
        websocket.send(JSON.stringify({
            type:'connect', data:{ host, port:parseInt(port), username, password }
        }));
        updateConnectionStatus(true, i18n.ssh_conecting);
    };

    websocket.onmessage = (event) => {
        try {
            var msg = JSON.parse(event.data);
            if (msg.type === 'output') term.write(msg.data);
            else if (msg.type === 'error') {
                term.writeln('\r\n\x1b[31m' + msg.message + '\x1b[0m');
                disconnectFromSsh();
            }
        } catch(e) { term.write(event.data); }

        if (!connected) {
            connected = true;
            document.getElementById('connectBtn').disabled   = true;
            document.getElementById('reconnectBtn').disabled = false;
            document.getElementById('disconnectBtn').disabled = false;
            updateConnectionStatus(true, i18n.ssh_connected);
            // 显示 host 信息
            document.getElementById('footerHostText').textContent = username + '@' + host + ':' + port;
            document.getElementById('footerHost').style.display = '';
            document.getElementById('footerSep1').style.display = '';
            document.getElementById('termTitle').textContent = username + '@' + host;
            resizeTerminal();
        }
        hideLoading(); connecting = false;
    };

    websocket.onclose = () => {
        if (!isDisconnecting) disconnectFromSsh();
        hideLoading(); connecting = false; isDisconnecting = false;
    };
    websocket.onerror = () => {
        term.writeln('\r\n\x1b[31mWebSocket 连接错误\x1b[0m');
        disconnectFromSsh(); hideLoading(); connecting = false;
    };
}

function disconnectFromSsh() {
    if (websocket) { isDisconnecting = true; websocket.close(); websocket = null; }
    connected = false;
    document.getElementById('connectBtn').disabled   = false;
    document.getElementById('reconnectBtn').disabled = true;
    document.getElementById('disconnectBtn').disabled = true;
    document.getElementById('footerHost').style.display = 'none';
    document.getElementById('footerSep1').style.display = 'none';
    document.getElementById('termTitle').textContent = '${msg.get("ssh.sshConsole")?js_string}';
    updateConnectionStatus(false, i18n.ssh_connecStop);
    term.writeln('\r\n\x1b[33m● 连接已断开\x1b[0m');
}

function reconnectSsh() {
    disconnectFromSsh();
    setTimeout(connectToSsh, 400);
}

function updateConnectionStatus(isConnected, text) {
    var el = document.getElementById('connStatus');
    el.className = isConnected ? 'connection-status connected' : 'connection-status disconnected';
    el.innerHTML = '<i class="fas fa-circle"></i><span>' + text + '</span>';
    document.getElementById('status-text').textContent = isConnected ? i18n.ssh_connecAlready : i18n.ssh_connecWait;
}

/* ── 清屏 ── */
function clearTerminal() {
    if (term) term.clear();
}

/* ── 复制 SSH 命令 ── */
function copySshCommand() {
    var host     = document.getElementById('host').value.trim();
    var username = document.getElementById('username').value.trim();
    var port     = document.getElementById('port').value.trim();
    if (!host || !username) {
        Swal.fire({ title:'提示', text:'请先填写主机和用户名', icon:'info', confirmButtonText: i18n.common_confirm });
        return;
    }
    var cmd = 'ssh ' + username + '@' + host + (port && port !== '22' ? ' -p ' + port : '');
    navigator.clipboard.writeText(cmd).then(() => {
        Swal.fire({ title:'已复制', text: cmd, icon:'success', timer:1800, showConfirmButton:false });
    });
}

/* ── 下载日志 ── */
function downloadLog() {
    if (outputBuffer.length === 0) {
        Swal.fire({ title:'提示', text:'暂无终端输出内容', icon:'info', confirmButtonText: i18n.common_confirm });
        return;
    }
    // 去除 ANSI 转义序列
    var raw = outputBuffer.join('').replace(/\x1b\[[0-9;]*[mGKHFJABCDSTrlu]/g, '').replace(/\r\n/g,'\n').replace(/\r/g,'\n');
    var host = document.getElementById('host').value.trim() || 'terminal';
    var ts   = new Date().toISOString().replace(/[:.]/g,'-').slice(0,19);
    var blob = new Blob([raw], { type:'text/plain;charset=utf-8' });
    var a    = document.createElement('a');
    a.href   = URL.createObjectURL(blob);
    a.download = 'ssh-' + host + '-' + ts + '.txt';
    a.click();
}

/* ── 全屏 ── */
function toggleFullscreen() {
    var wrapper = document.getElementById('terminalWrapper');
    var icon    = document.querySelector('#fullscreenBtn i');
    if (!document.fullscreenElement) {
        wrapper.requestFullscreen().then(() => {
            wrapper.classList.add('fullscreen');
            icon.classList.replace('fa-expand','fa-compress');
            setTimeout(resizeTerminal, 100);
        }).catch(()=>{});
    } else {
        document.exitFullscreen().then(() => {
            wrapper.classList.remove('fullscreen');
            icon.classList.replace('fa-compress','fa-expand');
            setTimeout(resizeTerminal, 100);
        });
    }
}
document.addEventListener('fullscreenchange', () => {
    if (!document.fullscreenElement) {
        document.getElementById('terminalWrapper').classList.remove('fullscreen');
        var icon = document.querySelector('#fullscreenBtn i');
        if (icon) { icon.classList.remove('fa-compress'); icon.classList.add('fa-expand'); }
        setTimeout(resizeTerminal, 100);
    }
});

/* ── 密码 ── */
function togglePassword() {
    var input = document.getElementById('password');
    var eye   = document.querySelector('.password-action-btn i');
    if (input.type === 'password') { input.type='text'; eye.classList.replace('fa-eye','fa-eye-slash'); }
    else { input.type='password'; eye.classList.replace('fa-eye-slash','fa-eye'); }
}
function copyPassword() {
    var v = document.getElementById('password').value;
    if (!v) return Swal.fire({ title:'warning', text: i18n.ssh_passBlank, icon:'info', confirmButtonText: i18n.common_confirm });
    navigator.clipboard.writeText(v)
        .then(() => Swal.fire({ title:'success', text: i18n.ssh_passCopySucc, icon:'success', timer:1200, showConfirmButton:false }))
        .catch(err => Swal.fire({ title:'error', text:''+err, icon:'error', confirmButtonText: i18n.common_confirm }));
}

/* ── 保存配置 ── */
function saveConfiguration() {
    var username = document.getElementById('username').value.trim();
    var host     = document.getElementById('host').value.trim();
    var port     = document.getElementById('port').value.trim();
    var password = document.getElementById('password').value;
    if (!username || !port || !instanceId) {
        Swal.fire({ title:'warning', text: i18n.common_plzInputGlobalRequired, icon:'warning', confirmButtonText: i18n.common_confirm });
        return;
    }
    showLoading('loading');
    fetch('/oci/ssh/config', {
        method:'POST',
        headers:{ 'Content-Type':'application/json', 'X-CSRF-TOKEN': _getCsrfToken() },
        body: JSON.stringify({ instanceId, username, port, password })
    })
    .then(r => r.ok ? r.json() : Promise.reject('HTTP '+r.status))
    .then(data => {
        hideLoading();
        if (data.success) Swal.fire({ title:'success', text:'successful', icon:'success', timer:1200, showConfirmButton:false });
        else Swal.fire({ title:'error', text: data.message||'error', icon:'error', confirmButtonText: i18n.common_confirm });
    })
    .catch(err => { hideLoading(); Swal.fire({ title:'error', text:''+err, icon:'error', confirmButtonText: i18n.common_confirm }); });
}

function loadSshConfig() {
    if (!instanceId || instanceId.trim() === '') return;
    fetch('/oci/ssh/config/' + instanceId)
        .then(r => { if (!r.ok) throw new Error('HTTP '+r.status); return r.json(); })
        .then(data => {
            if (data.success && data.data) {
                var cfg = data.data;
                document.getElementById('username').value = cfg.username  || '';
                document.getElementById('host').value     = cfg.host      || '';
                document.getElementById('port').value     = cfg.port      || '22';
                document.getElementById('password').value = cfg.sshPassword || '';
            }
        })
        .catch(err => console.error('加载SSH配置失败:', err));
}

/* ── 搜索栏（简单文本高亮，xterm 4.x 不依赖 addon）── */
(function initSearch(){
    var bar  = document.getElementById('searchBar');
    var inp  = document.getElementById('searchInput');
    var cnt  = document.getElementById('searchCount');
    var matches = [], cur = -1;

    function openSearch(){
        bar.classList.add('open');
        inp.focus();
        inp.select();
    }
    function closeSearch(){
        bar.classList.remove('open');
        matches = []; cur = -1; cnt.textContent = '';
        if (term) { term.clearSelection(); term.focus(); }
    }
    document.getElementById('searchClose').onclick = closeSearch;
    document.getElementById('searchPrev').onclick  = () => navigate(-1);
    document.getElementById('searchNext').onclick  = () => navigate(1);

    inp.addEventListener('keydown', e => {
        if (e.key === 'Enter')  { e.shiftKey ? navigate(-1) : navigate(1); }
        if (e.key === 'Escape') closeSearch();
    });
    inp.addEventListener('input', doSearch);

    function doSearch(){
        matches = []; cur = -1;
        var q = inp.value;
        if (!q || !term) { cnt.textContent = ''; return; }
        // 简单：在 xterm buffer 中搜索行
        var total = term.buffer.active.length;
        for (var i = 0; i < total; i++) {
            var line = term.buffer.active.getLine(i);
            if (!line) continue;
            var txt = line.translateToString(true);
            if (txt.toLowerCase().includes(q.toLowerCase())) matches.push(i);
        }
        cnt.textContent = matches.length ? '1/' + matches.length : '无结果';
        if (matches.length) { cur = 0; scrollTo(matches[0]); }
    }
    function navigate(dir){
        if (!matches.length) return;
        cur = (cur + dir + matches.length) % matches.length;
        cnt.textContent = (cur+1) + '/' + matches.length;
        scrollTo(matches[cur]);
    }
    function scrollTo(line) {
        if (term) term.scrollToLine(line);
    }
    // 全局快捷键 Ctrl+F
    window.addEventListener('keydown', e => {
        if ((e.ctrlKey || e.metaKey) && e.key === 'f') {
            e.preventDefault(); openSearch();
        }
    });
})();

/* ── 右键菜单 ── */
(function initContextMenu(){
    var menu = document.getElementById('ctxMenu');
    var el   = document.getElementById('terminal');
    var showMenu = (x,y) => { menu.style.cssText += ';display:block;left:'+x+'px;top:'+y+'px'; };
    var hideMenu = ()     => { menu.style.display='none'; };

    el.addEventListener('contextmenu', e => { e.preventDefault(); showMenu(e.clientX, e.clientY); });
    window.addEventListener('click',  hideMenu);
    window.addEventListener('blur',   hideMenu);
    window.addEventListener('resize', hideMenu);

    document.getElementById('ctxCopy').onclick = () => {
        var t = term.getSelection(); if (t) navigator.clipboard.writeText(t);
        hideMenu(); term.focus();
    };
    document.getElementById('ctxPaste').onclick = async () => {
        hideMenu();
        if (!connected || !websocket) return;
        try { var t = await navigator.clipboard.readText(); if (t) websocket.send(JSON.stringify({type:'input',data:t})); } catch(e){}
        term.focus();
    };
    document.getElementById('ctxSelectAll').onclick = () => { term.selectAll(); hideMenu(); term.focus(); };
    document.getElementById('ctxClear').onclick     = () => { clearTerminal();  hideMenu(); term.focus(); };
    document.getElementById('ctxCopyCmd').onclick   = () => { copySshCommand(); hideMenu(); };
    document.getElementById('ctxDownload').onclick  = () => { downloadLog();    hideMenu(); };

    // 键盘快捷键
    window.addEventListener('keydown', async e => {
        if (e.ctrlKey && e.key === 'Insert') {
            var t = term.getSelection(); if (t) await navigator.clipboard.writeText(t);
        } else if (e.shiftKey && e.key === 'Insert') {
            if (connected && websocket) {
                try { var t = await navigator.clipboard.readText(); if (t) websocket.send(JSON.stringify({type:'input',data:t})); } catch(ex){}
            }
        } else if (e.ctrlKey && e.key === 'l') {
            e.preventDefault(); clearTerminal();
        } else if (e.key === 'F11') {
            e.preventDefault(); toggleFullscreen();
        } else if (e.ctrlKey && (e.key === '=' || e.key === '+')) {
            e.preventDefault(); setFontSize(currentFontSize + 1);
        } else if (e.ctrlKey && e.key === '-') {
            e.preventDefault(); setFontSize(currentFontSize - 1);
        }
    });
})();

/* ── 初始化 ── */
document.addEventListener('DOMContentLoaded', () => {
    initTerminal();
    loadSshConfig();

    document.getElementById('connectBtn').addEventListener('click',    connectToSsh);
    document.getElementById('reconnectBtn').addEventListener('click',  reconnectSsh);
    document.getElementById('disconnectBtn').addEventListener('click', disconnectFromSsh);
    document.getElementById('saveConfigBtn').addEventListener('click', saveConfiguration);
    document.getElementById('clearBtn').addEventListener('click',      clearTerminal);
    document.getElementById('copyCmdBtn').addEventListener('click',    copySshCommand);
    document.getElementById('downloadLogBtn').addEventListener('click',downloadLog);
    document.getElementById('fullscreenBtn').addEventListener('click', toggleFullscreen);
    document.getElementById('fontIncBtn').addEventListener('click',    () => setFontSize(currentFontSize + 1));
    document.getElementById('fontDecBtn').addEventListener('click',    () => setFontSize(currentFontSize - 1));

    var sel = document.getElementById('themeSelect');
    sel.value = getSavedThemeKey();
    sel.addEventListener('change', () => applyThemeByKey(sel.value));

    // 回车快速连接
    ['username','host','port','password'].forEach(id => {
        document.getElementById(id).addEventListener('keydown', e => {
            if (e.key === 'Enter') connectToSsh();
        });
    });
});
</script>
</body>
</html>
