<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 系统日志</title>
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <script>(function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/common/fa-fix.css">

    <link rel="stylesheet" href="/css/app/sys_log.css">
    <link rel="stylesheet" href="/css/common/loading.css">
</head>
<body>
<!-- 引入顶部导航栏 -->
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-terminal"></i>
                <span>${msg.get("syslog.log")}</span>
            </h1>
            <div>
                <button class="btn btn-info" onclick="clearLogs()">
                    <i class="fas fa-trash"></i>
                    <span>${msg.get("syslog.clearLog")}</span>
                </button>
                <a href="javascript:history.back()" class="btn btn-primary">
                    <i class="fas fa-arrow-left"></i>
                    <span>${msg.get("syslog.back")}</span>
                </a>
            </div>
        </div>

        <div class="terminal-card">
            <div class="terminal-header">
                <h2 class="terminal-title">
                    <i class="fas fa-terminal"></i>
                    <span>${msg.get("syslog.console")}</span>
                    <span class="terminal-cursor"></span>
                </h2>
                <div class="connection-status disconnected">
                    <i class="fas fa-circle"></i>
                    <span>${msg.get("syslog.noConn")}</span>
                </div>
            </div>

            <div class="terminal-content" id="terminal-content">
                <#if logLines?? && logLines?size gt 0>
                    <#list logLines as line>
                        <div class="log-entry"><p>${line?trim?html}</p></div>
                    </#list>
                </#if>
            </div>

            <div class="terminal-footer">
                <div class="log-info">
                    <div class="log-stat">
                        <i class="fas fa-clock"></i>
                        <span id="current-time"></span>
                    </div>
                    <div class="log-stat">
                        <i class="fas fa-list"></i>
                        <span id="log-count">${msg.get("syslog.noLog")}</span>
                    </div>
                </div>
                <div class="log-actions">
                    <label class="auto-scroll">
                        <input type="checkbox" id="auto-scroll" checked>
                        <span>${msg.get("syslog.autoConsole")}</span>
                    </label>
                    <span id="connection-status">${msg.get("syslog.everyTimeUpdate")}</span>
                </div>
            </div>
        </div>
    </main>
</div>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/system/sys_log.js"></script>
</body>
</html>