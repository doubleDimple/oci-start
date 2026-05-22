
// 全局变量
let currentAiMsgElement = null;
let currentRawContent = "";
let csrfToken, csrfHeaderName;
let websocket = null;
let isConnected = false;
let modelsLoaded = false;  // 添加这个变量
let tenantId;
let availableModels = [];

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', function() {
    tenantId = document.querySelector('meta[name="tenant_id"]')?.content || '';
    tenantName = document.querySelector('meta[name="tenant_name"]')?.content || '';
    csrfToken = document.querySelector('meta[name="_csrf"]').content;
    csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;
    // 设置欢迎消息时间
    document.getElementById('welcomeTime').textContent = formatTime(new Date());

    // 串行执行：先加载模型，成功后再连接WebSocket
    loadAvailableModels();

    // 绑定输入框事件
    const chatInput = document.getElementById('chatInput');
    chatInput.addEventListener('keydown', function(e) {
        if (e.key === 'Enter' && !e.shiftKey) {
            e.preventDefault();
            sendMessage();
        }
    });

    // 自动调整输入框高度
    chatInput.addEventListener('input', function() {
        this.style.height = 'auto';
        this.style.height = Math.min(this.scrollHeight, 120) + 'px';
    });

    // 初始化侧边栏
    initializeSidebar();
});

// 初始化侧边栏功能
function initializeSidebar() {
    // 获取所有父级菜单
    const navParents = document.querySelectorAll('.nav-parent');

    // 为每个父级菜单添加点击事件
    navParents.forEach(parent => {
        const parentLink = parent.querySelector('.nav-link');
        if (parentLink) {
            parentLink.addEventListener('click', (e) => {
                e.preventDefault();
                // 切换当前菜单的展开状态
                parent.classList.toggle('expanded');
            });
        }
    });

    // 找到当前活动的子菜单项，并展开其父级菜单
    const activeLink = document.querySelector('.nav-children .nav-link.active');
    if (activeLink) {
        const parent = activeLink.closest('.nav-parent');
        if (parent) {
            parent.classList.add('expanded');
        }
    }
}

// 异步加载可用模型
function loadAvailableModels() {
    const container = document.getElementById('modelSelectorContainer');

    fetch('/ai/models?tenantId=' + tenantId)
        .then(response => response.json())
        .then(data => {
            if (data.success && data.models && data.models.length > 0) {
                // 成功获取模型列表
                availableModels = data.models;
                modelsLoaded = true;
                renderModelSelector(data.models);

                // 模型加载成功后，才开始连接WebSocket
                connectWebSocket();
            } else {
                // 没有可用模型或获取失败
                const message = data.message || '暂无可用模型';
                renderNoModelsMessage(message);
                // 即使没有模型，也需要连接WebSocket以显示连接状态
                connectWebSocket();
            }
        })
        .catch(error => {
            console.error('加载模型列表失败:', error);
            renderNoModelsMessage('加载模型列表失败，请刷新页面重试');
            // 加载失败时也连接WebSocket
            connectWebSocket();
        });
}

// 渲染模型选择器
function renderModelSelector(models) {
    const container = document.getElementById('modelSelectorContainer');
    const select = document.createElement('select');
    select.id = 'modelSelect';
    select.className = 'model-selector select';

    models.forEach(model => {
        const option = document.createElement('option');
        option.value = model.id;
        option.textContent = model.displayName + ' (' + (model.version || 'latest') + ')';
        select.appendChild(option);
    });

    container.innerHTML = '';
    container.appendChild(select);

    // 初始化自定义下拉样式
    if (window.CustomSelect) {
        CustomSelect.init(select, { placeholder: '选择模型...' });
    }

    // 模型渲染完成后，如果WebSocket已连接，则更新状态
    if (isConnected) {
        updateConnectionStatus(true);
    }
}

// 渲染无模型消息
function renderNoModelsMessage(message) {
    const container = document.getElementById('modelSelectorContainer');
    container.innerHTML = '<div class="no-models-message"><i class="fas fa-exclamation-triangle"></i> ' + message + '</div>';
}

// 连接WebSocket
function connectWebSocket() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = protocol + '//' + window.location.host + '/ws/aiChat';

    try {
        websocket = new WebSocket(wsUrl);

        websocket.onopen = function(event) {
            console.log('WebSocket连接已建立');
            isConnected = true;
            updateConnectionStatus(true);

            // 获取当前选择的模型ID
            const modelSelect = document.getElementById('modelSelect');
            const selectedModelId = modelSelect ? modelSelect.value : (availableModels.length > 0 ? availableModels[0].id : '');

            // 发送初始化消息，包含modelId
            const initMessage = {
                type: 'init',
                tenant: {
                    tenantId: tenantId,
                    modelId: selectedModelId
                }
            };
            websocket.send(JSON.stringify(initMessage));
        };

        websocket.onmessage = function(event) {
            try {
                const message = JSON.parse(event.data);
                handleWebSocketMessage(message);
            } catch (error) {
                console.error('解析WebSocket消息失败:', error);
            }
        };

        websocket.onclose = function(event) {
            console.log('WebSocket连接已关闭:', event.code, event.reason);
            isConnected = false;
            updateConnectionStatus(false);

            // 尝试重连
            setTimeout(function() {
                if (!isConnected) {
                    console.log('尝试重新连接WebSocket...');
                    connectWebSocket();
                }
            }, 5000);
        };

        websocket.onerror = function(error) {
            console.error('WebSocket错误:', error);
            isConnected = false;
            updateConnectionStatus(false);
        };

    } catch (error) {
        console.error('创建WebSocket连接失败:', error);
        updateConnectionStatus(false);
    }
}

// 更新连接状态显示
function updateConnectionStatus(connected) {
    const statusIndicator = document.getElementById('connectionStatus');
    const connectionText = document.getElementById('connectionText');
    const chatInput = document.getElementById('chatInput');
    const sendBtn = document.getElementById('sendBtn');
    const closeSessionBtn = document.querySelector('.close-session-btn'); // 获取关闭会话按钮

    if (connected && modelsLoaded) {
        // 只有在连接成功且模型已加载时才可用输入
        statusIndicator.classList.add('connected');
        connectionText.textContent = '已连接';
        chatInput.disabled = false;
        sendBtn.disabled = false;

        // 启用关闭会话按钮
        if (closeSessionBtn) {
            closeSessionBtn.disabled = false;
            closeSessionBtn.classList.remove('disconnected');
        }
    } else {
        statusIndicator.classList.remove('connected');
        if (!connected) {
            connectionText.textContent = '连接断开';
        } else if (!modelsLoaded) {
            connectionText.textContent = '等待模型加载';
        }
        chatInput.disabled = true;
        sendBtn.disabled = true;

        // 在连接断开时禁用关闭会话按钮
        if (closeSessionBtn) {
            closeSessionBtn.disabled = !connected; // 只有在完全断开连接时才禁用
            if (!connected) {
                closeSessionBtn.classList.add('disconnected');
            }
        }
    }
}

// 处理WebSocket消息
function handleWebSocketMessage(message) {
    switch (message.type) {
        case 'init':
            if (message.status === 'success') {
                console.log('初始化成功:', message.message);
            } else {
                console.error('初始化失败:', message.message);
                showErrorMessage('初始化失败: ' + message.message);
            }
            break;

        case 'chat':
            // 收到消息片段或完整消息
            if (message.role === 'assistant') {
                if (message.isChunk) {
                    // 如果是流式片段
                    handleChatChunk(message.message);
                } else {
                    // 如果是完整消息（兜底原逻辑）
                    hideTypingIndicator();
                    addMessage('ai', message.message);
                }
            }
            break;

        case 'chat_end':
            hideTypingIndicator();
            if (currentAiMsgElement) {
                currentAiMsgElement.classList.remove('typing-active');
            }
            currentAiMsgElement = null;
            currentRawContent = "";
            break;

        case 'typing':
            showTypingIndicator();
            break;

        case 'error':
            hideTypingIndicator();
            showErrorMessage(message.message);
            break;

        case 'pong':
        case 'heartbeat':
            // 心跳响应，无需处理
            break;

        case 'system':
            // 系统消息，记录但不显示
            console.log('系统消息:', message.message);
            break;

        case 'close_session':
            if (message.status === 'success') {
                console.log('服务器确认关闭会话:', message.message);
            }
            break;

        default:
            console.log('未知消息类型:', message.type, message);
    }
}

// 发送消息
function sendMessage() {
    if (!isConnected) {
        Swal.fire({
            title: '连接异常',
            text: 'WebSocket连接断开，请刷新页面重试',
            icon: 'error',
            confirmButtonColor: '#ef4444'
        });
        return;
    }

    const chatInput = document.getElementById('chatInput');
    const message = chatInput.value.trim();

    console.log('准备发送消息:', message);  // 调试日志

    if (!message) {
        return;
    }

    // 检查是否选择了模型
    const modelSelect = document.getElementById('modelSelect');
    if (!modelSelect || !modelSelect.value) {
        Swal.fire({
            title: '请选择模型',
            text: '请先选择一个AI模型',
            icon: 'warning',
            confirmButtonColor: '#3b82f6'
        });
        return;
    }

    currentAiMsgElement = null;
    currentRawContent = "";

    // 添加用户消息到界面
    addMessage('user', message);

    // 清空输入框
    chatInput.value = '';
    chatInput.style.height = 'auto';

    // 显示正在输入指示器
    showTypingIndicator();

    // 发送消息到WebSocket，
    const chatMessage = {
        type: 'chat',
        message: message,
        modelId: modelSelect.value,
        tenantId: tenantId,
        useHistory: document.getElementById('useHistory').checked
    };

    console.log('发送WebSocket消息:', chatMessage);
    websocket.send(JSON.stringify(chatMessage));
}

// 添加消息到聊天区域
function addMessage(type, content) {
    console.log('添加消息:', type, content);

    const messagesContainer = document.getElementById('chatMessages');
    const messageElement = document.createElement('div');
    messageElement.className = 'message ' + type;

    const avatar = type === 'user' ?
        '<i class="fas fa-user"></i>' :
        '<i class="fas fa-robot"></i>';

    // 确保内容不为空
    const safeContent = content || '';

    // 处理消息内容
    let processedContent;
    if (type === 'ai') {
        // AI消息需要解析Markdown
        processedContent = parseMarkdown(safeContent);
    } else {
        // 用户消息只需要转义HTML
        processedContent = escapeHtml(safeContent);
    }

    messageElement.innerHTML =
        '<div class="message-avatar">' +
        avatar +
        '</div>' +
        '<div class="message-content">' +
        '<div class="markdown-content">' + processedContent + '</div>' +
        '<div class="message-time">' + formatTime(new Date()) + '</div>' +
        '</div>';

    messagesContainer.appendChild(messageElement);

    // 如果是AI消息，应用代码高亮
    if (type === 'ai') {
        // 找到所有代码块并应用高亮
        const codeBlocks = messageElement.querySelectorAll('pre code');
        codeBlocks.forEach(block => {
            // 应用highlight.js
            hljs.highlightElement(block);

            // 添加复制按钮
            const pre = block.parentElement;
            const wrapper = document.createElement('div');
            wrapper.className = 'code-block-wrapper';
            pre.parentNode.insertBefore(wrapper, pre);
            wrapper.appendChild(pre);

            const copyBtn = document.createElement('button');
            copyBtn.className = 'copy-code-btn';
            copyBtn.innerHTML = '<i class="fas fa-copy"></i> 复制';
            copyBtn.onclick = function() {
                copyCodeToClipboard(block.textContent, copyBtn);
            };
            wrapper.appendChild(copyBtn);
        });
    }

    scrollToBottom();
}

function parseMarkdown(content) {
    // 配置marked选项
    marked.setOptions({
        highlight: function(code, lang) {
            // 如果指定了语言，使用highlight.js进行高亮
            if (lang && hljs.getLanguage(lang)) {
                try {
                    return hljs.highlight(code, { language: lang }).value;
                } catch (e) {
                    console.error('代码高亮失败:', e);
                }
            }
            // 如果没有指定语言，尝试自动检测
            try {
                return hljs.highlightAuto(code).value;
            } catch (e) {
                console.error('自动代码高亮失败:', e);
            }
            // 如果高亮失败，返回转义后的代码
            return escapeHtml(code);
        },
        breaks: true,  // 支持换行
        gfm: true,     // 支持GitHub风格的Markdown
        tables: true,  // 支持表格
        sanitize: false // 不要过滤HTML（我们自己处理安全性）
    });

    // 解析Markdown
    try {
        return marked.parse(content);
    } catch (error) {
        console.error('Markdown解析失败:', error);
        // 如果解析失败，返回转义后的纯文本
        return escapeHtml(content);
    }
}
function copyCodeToClipboard(code, button) {
    // 创建临时文本区域
    const textarea = document.createElement('textarea');
    textarea.value = code;
    textarea.style.position = 'fixed';
    textarea.style.top = '-9999px';
    document.body.appendChild(textarea);

    try {
        // 选择并复制文本
        textarea.select();
        document.execCommand('copy');

        // 更新按钮状态
        const originalHTML = button.innerHTML;
        button.innerHTML = '<i class="fas fa-check"></i> 已复制';
        button.style.background = '#10b981';

        // 2秒后恢复原状
        setTimeout(() => {
            button.innerHTML = originalHTML;
            button.style.background = '#24292e';
        }, 2000);
    } catch (error) {
        console.error('复制失败:', error);
        Swal.fire({
            title: '复制失败',
            text: '请手动选择并复制代码',
            icon: 'error',
            confirmButtonColor: '#ef4444'
        });
    } finally {
        // 清理临时元素
        document.body.removeChild(textarea);
    }
}

// 显示正在输入指示器
function showTypingIndicator() {
    const indicator = document.getElementById('typingIndicator');
    indicator.style.display = 'flex';
    scrollToBottom();
}

// 隐藏正在输入指示器
function hideTypingIndicator() {
    const indicator = document.getElementById('typingIndicator');
    indicator.style.display = 'none';
}

// 显示错误消息
function showErrorMessage(errorText) {
    addMessage('ai', '抱歉，出现了一些问题：' + errorText);
}

// 清空对话
function clearChat() {
    Swal.fire({
        title: '确认清空对话',
        text: '确定要清空所有对话记录吗？',
        icon: 'question',
        showCancelButton: true,
        confirmButtonColor: '#ef4444',
        cancelButtonColor: '#3b82f6',
        confirmButtonText: '清空',
        cancelButtonText: '取消',
        allowOutsideClick: false,
        allowEscapeKey: false
    }).then((result) => {
        if (result.isConfirmed) {
            const messagesContainer = document.getElementById('chatMessages');
            messagesContainer.innerHTML =
                '<div class="message ai">' +
                '<div class="message-avatar">' +
                '<i class="fas fa-robot"></i>' +
                '</div>' +
                '<div class="message-content">' +
                '<div>对话已清空，有什么可以帮助您的吗？</div>' +
                '<div class="message-time">' + formatTime(new Date()) + '</div>' +
                '</div>' +
                '</div>';

            // 发送清空指令到后端
            if (isConnected) {
                websocket.send(JSON.stringify({ type: 'clear' }));
            }
        }
    });
}

// 滚动到底部
function scrollToBottom() {
    const messagesContainer = document.getElementById('chatMessages');
    messagesContainer.scrollTop = messagesContainer.scrollHeight;
}

// 格式化时间
function formatTime(date) {
    return date.toLocaleString('zh-CN', {
        hour: '2-digit',
        minute: '2-digit',
        second: '2-digit'
    });
}

function escapeHtml(text) {
    if (!text) return '';

    const str = String(text);
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

// 页面卸载时关闭WebSocket连接
window.addEventListener('beforeunload', function() {
    if (websocket) {
        websocket.close();
    }
});

// 关闭会话
function closeSession() {
    Swal.fire({
        title: '确认关闭会话',
        text: '关闭会话将断开WebSocket连接并清空所有对话记录，确定要关闭吗？',
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#ef4444',
        cancelButtonColor: '#3b82f6',
        confirmButtonText: '关闭会话',
        cancelButtonText: '取消',
        allowOutsideClick: false,
        allowEscapeKey: false
    }).then((result) => {
        if (result.isConfirmed) {
            // 发送关闭会话消息到后端
            if (isConnected && websocket) {
                websocket.send(JSON.stringify({
                    type: 'close_session',
                    reason: 'user_requested'
                }));
            }

            // 主动关闭WebSocket连接
            if (websocket) {
                websocket.close(1000, 'Session closed by user');
                websocket = null;
            }

            // 重置连接状态
            isConnected = false;
            modelsLoaded = false;

            // 更新UI状态
            updateConnectionStatus(false);

            // 清空对话记录
            const messagesContainer = document.getElementById('chatMessages');
            messagesContainer.innerHTML = '';

            // 清空输入框
            const chatInput = document.getElementById('chatInput');
            chatInput.value = '';
            chatInput.style.height = 'auto';

            // 重置模型选择器
            const container = document.getElementById('modelSelectorContainer');
            container.innerHTML = '<div class="models-loading"><span class="loading-spinner"></span><span>会话已关闭</span></div>';

            // 显示成功消息
            Swal.fire({
                title: '会话已关闭',
                text: '如需重新开始对话，请刷新页面',
                icon: 'success',
                confirmButtonColor: '#3b82f6',
                confirmButtonText: '确定'
            });
        }
    });
}

function handleChatChunk(content) {
    // 1. 如果是第一块数据，先隐藏思考动画并创建气泡
    if (!currentAiMsgElement) {
        hideTypingIndicator();
        currentAiMsgElement = createStreamingBubble();
        currentRawContent = "";
    }

    // 2. 累加原始文本
    currentRawContent += content;

    // 3. 实时解析 Markdown 并渲染
    // 注意：这里使用内部的 markdown-content 容器
    const contentDiv = currentAiMsgElement.querySelector('.markdown-content');
    contentDiv.innerHTML = parseMarkdown(currentRawContent);

    // 4. 处理代码块高亮
    const codeBlocks = contentDiv.querySelectorAll('pre code');
    codeBlocks.forEach(block => {
        if (!block.classList.contains('hljs')) { // 避免重复渲染
            hljs.highlightElement(block);
        }
    });

    // 5. 滚动到底部
    scrollToBottom();
}

/**
 * 创建一个空的流式消息气泡
 */
function createStreamingBubble() {
    const messagesContainer = document.getElementById('chatMessages');
    const messageElement = document.createElement('div');
    messageElement.className = 'message ai typing-active';

    const avatar = '<i class="fas fa-robot"></i>';

    messageElement.innerHTML =
        '<div class="message-avatar">' + avatar + '</div>' +
        '<div class="message-content">' +
        '<div class="markdown-content"></div>' +
        '<div class="message-time">' + formatTime(new Date()) + '</div>' +
        '</div>';

    messagesContainer.appendChild(messageElement);
    return messageElement;
}
