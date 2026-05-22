let eventSource = null;
let logCount = 0;
let maxLogs = 1000;

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

    message = message.replace(/\[(SUCCESS|ERROR|WARN|INFO)\]\s*/, '').trim();
    entry.textContent = message;
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
        status.innerHTML = '<i class="fas fa-circle"></i><span>connected</span>';
    } else if (state === 'connecting') {
        status.className = 'connection-status disconnected';
        status.innerHTML = '<i class="fas fa-circle" style="color: #f39c12;"></i><span>connecting...</span>';
    } else {
        status.className = 'connection-status disconnected';
        status.innerHTML = '<i class="fas fa-circle"></i><span>disable connect</span>';
    }
}

function updateLogCount() {
    document.getElementById('log-count').textContent = logCount + ' log entries';
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
    const existingEntries = document.querySelectorAll('#terminal-content .log-entry');
    logCount = existingEntries.length;
    updateLogCount();
    if (logCount > 0) {
        scrollToBottom();
    }

    connectSSE();

    updateCurrentTime();
    setInterval(updateCurrentTime, 1000);
});