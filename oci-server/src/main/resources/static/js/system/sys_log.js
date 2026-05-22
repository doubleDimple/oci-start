let eventSource = null;
let logCount = 0;
let maxLogs = 1000; // 最大显示日志数

function connectSSE() {
    // 刚进页面，马上显示正在连接
    updateConnectionStatus('connecting');

    // 这里判断是不是开机日志页面
    const isBootLog = window.location.pathname.includes('openLogs');
    const url = '/system/streamLogs?isBootLog=' + isBootLog;

    eventSource = new EventSource(url);

    eventSource.onopen = function() {
        // 连接成功！
        updateConnectionStatus('connected');
    };

    eventSource.onmessage = function(event) {
        addLogEntry(event.data);
    };

    eventSource.onerror = function(error) {
        // 断线时提示未连接
        updateConnectionStatus('disconnected');
        eventSource.close();
        setTimeout(connectSSE, 5000);
    };
}

function addLogEntry(message) {
    const terminalContent = document.getElementById('terminal-content');
    const entry = document.createElement('div');
    entry.className = 'log-entry new';

    if (message.toLowerCase().includes('[success]')) {
        entry.classList.add('success-entry');
    } else if (message.toLowerCase().includes('[warn]') || message.toLowerCase().includes('warning')) {
        entry.classList.add('warn-entry');
    } else if (message.toLowerCase().includes('[error]') || message.toLowerCase().includes('error')) {
        entry.classList.add('error-entry');
    }

    message = message.replace(/\[(SUCCESS|ERROR|WARN|INFO)\]\s*/, '');
    entry.innerHTML = `<p>${message}</p>`;
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

function updateConnectionStatus(state) {
    var status = document.querySelector('.connection-status');

    if (state === 'connected') {
        status.className = 'connection-status connected';
        status.innerHTML = '<i class="fas fa-circle"></i><span>已连接实时流</span>';
    } else if (state === 'connecting') {
        status.className = 'connection-status disconnected'; // 复用断开的样式，但改个颜色
        status.innerHTML = '<i class="fas fa-circle" style="color: #f39c12;"></i><span>正在连接实时流...</span>';
    } else {
        status.className = 'connection-status disconnected';
        status.innerHTML = '<i class="fas fa-circle"></i><span>未连接</span>';
    }
}

function updateLogCount() {
    document.getElementById('log-count').textContent = logCount + ` log entries`;
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
    // 统计历史条数
    const existingEntries = document.querySelectorAll('#terminal-content .log-entry');
    logCount = existingEntries.length;
    updateLogCount();
    if (logCount > 0) {
        scrollToBottom();
    }

    connectSSE();

    updateCurrentTime();
    setInterval(updateCurrentTime, 1000);

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
});