<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
    <meta name="tenant_id" content="${tenant.id?c}"/>
    <meta name="tenant_name" content="${tenant.defName!tenant.tenancyName}"/>
    <title>AI对话 - VPS管理系统</title>
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>(function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github.min.css" id="hljs-light">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css" id="hljs-dark" disabled>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
    <link rel="stylesheet" href="/css/app/chat.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/common/custom-select.css">
    <script src="/js/common/jquery.min.js"></script>
    <style>
        .layout { padding-top: 0; }
        .main-content { margin-left: 0; padding: 20px 24px; background: var(--bg); }
    </style>

</head>
<body>
<!-- 引入顶部导航栏 -->
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
        <div class="ai-chat-container">
            <div class="chat-header">
                <span class="tenant-badge">
                    <i class="fas fa-user-circle"></i>
                    ${tenant.defName!tenant.tenancyName}
                </span>

                <div class="model-selector">
                    <label for="modelSelect">模型:</label>
                    <div id="modelSelectorContainer">
                        <div class="models-loading">
                            <span class="loading-spinner"></span>
                            <span>正在加载可用模型...</span>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Chat Messages -->
            <div class="chat-messages" id="chatMessages">
                <div class="message ai">
                    <div class="message-avatar">
                        <i class="fas fa-robot"></i>
                    </div>
                    <div class="message-content">
                        <div>你好！我是AI助手，有什么可以帮助您的吗？</div>
                        <div class="message-time" id="welcomeTime"></div>
                    </div>
                </div>
            </div>
            <div class="typing-indicator" id="typingIndicator">
                <div class="message-avatar">
                    <i class="fas fa-robot"></i>
                </div>
                <div>
                    AI正在思考
                    <div class="typing-dots">
                        <div class="typing-dot"></div>
                        <div class="typing-dot"></div>
                        <div class="typing-dot"></div>
                    </div>
                </div>
            </div>

            <!-- Chat Input -->
            <div class="chat-input-container">
                <div class="chat-controls">
                    <div class="control-group">
                        <input type="checkbox" id="useHistory" checked>
                        <label for="useHistory">使用对话历史</label>
                    </div>

                    <button class="clear-chat-btn" onclick="clearChat()">
                        <i class="fas fa-trash"></i>
                        清空对话
                    </button>

                    <button class="close-session-btn" onclick="closeSession()">
                        <i class="fas fa-sign-out-alt"></i>
                        关闭会话
                    </button>

                    <div class="connection-status">
                        <div class="status-indicator" id="connectionStatus"></div>
                        <span id="connectionText">连接中...</span>
                    </div>
                </div>

                <div class="chat-input-wrapper">
                    <textarea
                            id="chatInput"
                            class="chat-input"
                            placeholder="输入您的问题..."
                            rows="1"
                            disabled
                    ></textarea>
                    <button id="sendBtn" class="chat-send-btn" onclick="sendMessage()" disabled>
                        <i class="fas fa-paper-plane"></i>
                    </button>
                </div>
            </div>
        </div>
    </main>
</div>

<!-- 在body结束前引入版本信息模块 -->
<#--
<#include "common/version_info.ftl">
-->
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/common/custom-select.js"></script>
<script src="/js/system/chat.js"></script>
<script>
    (function() {
        var t = document.documentElement.dataset.theme;
        document.getElementById('hljs-light').disabled = (t === 'dark');
        document.getElementById('hljs-dark').disabled  = (t !== 'dark');
    })();
</script>
</body>
</html>