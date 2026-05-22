<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 域名服务商配置</title>
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>(function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <script src="/js/common/jquery.min.js"></script>
    <link rel="stylesheet" href="/css/app/domain_settings.css">
    <link rel="stylesheet" href="/css/common/loading.css">
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
        <div class="page-card">
            <!-- 页面标题 -->
            <div class="page-header">
                <h1 class="page-title">
                    <i class="fas fa-globe"></i>
                    <span>${msg.get("domain.provider")}</span>
                </h1>
            </div>

            <!-- 设置卡片网格布局 -->
            <div class="provider-grid">
                <!-- Cloudflare 配置 -->
                <div class="settings-card" data-provider="cloudflare">
                    <div class="settings-card-header">
                        <div class="header-with-toggle">
                            <h3 class="settings-card-title">
                                <i class="fab fa-cloudflare" style="color: #f38020;"></i>
                                Cloudflare
                                <span class="status-badge status-disconnected">
                                    <i class="fas fa-circle"></i>
                                    ${cloudflareConfig.enabled?string('${msg.get("domain.conn")}', '${msg.get("domain.disConn")}')}
                                </span>
                            </h3>
                            <label class="switch">
                                <input type="checkbox" name="enabled" ${cloudflareConfig.enabled?string('checked', '')}>
                                <span class="slider"></span>
                            </label>
                        </div>
                    </div>
                    <div class="settings-card-body">
                        <form id="cloudflareForm" class="compact-form">
                            <div class="form-row">
                                <label class="form-label">API Key</label>
                                <div class="form-control-with-tip">
                                    <div class="password-input-wrapper">
                                        <input type="password" class="form-control" name="apiToken" id="apiTokenInput"
                                               value="${cloudflareConfig.apiToken!''}"
                                               placeholder="输入Cloudflare API Key">
                                        <div class="password-actions">
                                            <button type="button" class="password-btn" onclick="togglePasswordVisibility('apiTokenInput')" title="${msg.get("domain.showOrHidden")}">
                                                <i class="fas fa-eye" id="apiTokenInput-eye"></i>
                                            </button>
                                            <button type="button" class="password-btn" onclick="copyToClipboard('apiTokenInput')" title="${msg.get("domain.copy")}">
                                                <i class="fas fa-copy"></i>
                                            </button>
                                        </div>
                                    </div>
                                    <div class="form-tip">${msg.get("domain.cfConfigPath")}</div>
                                </div>
                            </div>
                            <div class="form-row">
                                <label class="form-label">${msg.get("domain.cfEmail")}</label>
                                <div class="form-control-with-tip">
                                    <input type="email" class="form-control" name="email"
                                           value="${cloudflareConfig.email!''}"
                                           placeholder="Cloudflare账户邮箱">
                                    <div class="form-tip">${msg.get("domain.cfVerify")}</div>
                                </div>
                            </div>
                        </form>
                    </div>
                    <div class="settings-card-footer">
                        <button type="button" class="btn btn-sm btn-info" onclick="testCloudflareConnection()">
                            <i class="fas fa-plug"></i> ${msg.get("ip.testConn")}
                        </button>
                        <button type="button" class="btn btn-sm btn-primary" onclick="saveCloudflareConfig()">
                            <i class="fas fa-save"></i> ${msg.get("notification.save")}
                        </button>
                    </div>
                </div>

                <!-- 腾讯云 EdgeOne 配置 -->
                <div class="settings-card" data-provider="edgeone">
                    <div class="settings-card-header">
                        <div class="header-with-toggle">
                            <h3 class="settings-card-title">
                                <i class="fab fa-qq" style="color: #00b9ff;"></i>
                                ${msg.get("domain.tencent")}
                                <span class="status-badge status-disconnected">
                    <i class="fas fa-circle"></i>
                    ${edgeOneConfig.enabled?string('${msg.get("domain.conn")}', '${msg.get("domain.disConn")}')}
                </span>
                            </h3>
                            <label class="switch">
                                <input type="checkbox" name="enabled" ${edgeOneConfig.enabled?string('checked', '')}>
                                <span class="slider"></span>
                            </label>
                        </div>
                    </div>
                    <div class="settings-card-body">
                        <form id="edgeOneForm" class="compact-form">
                            <div class="form-row">
                                <label class="form-label">SecretId <span style="color: #ff6b6b;">*</span></label>
                                <div class="form-control-with-tip">
                                    <div class="password-input-wrapper">
                                        <input type="password" class="form-control" name="secretId" id="secretIdInput"
                                               value="${edgeOneConfig.secretId!''}"
                                               placeholder="${msg.get("domain.tencentSecret")}">
                                        <div class="password-actions">
                                            <button type="button" class="password-btn" onclick="togglePasswordVisibility('secretIdInput')" title="${msg.get("domain.showOrHidden")}">
                                                <i class="fas fa-eye" id="secretIdInput-eye"></i>
                                            </button>
                                            <button type="button" class="password-btn" onclick="copyToClipboard('secretIdInput')" title="${msg.get("domain.copy")}">
                                                <i class="fas fa-copy"></i>
                                            </button>
                                        </div>
                                    </div>
                                    <div class="form-tip">${msg.get("domain.tencentConfigPath")}</div>
                                </div>
                            </div>
                            <div class="form-row">
                                <label class="form-label">SecretKey <span style="color: #ff6b6b;">*</span></label>
                                <div class="form-control-with-tip">
                                    <div class="password-input-wrapper">
                                        <input type="password" class="form-control" name="secretKey" id="secretKeyInput"
                                               value="${edgeOneConfig.secretKey!''}"
                                               placeholder="${msg.get("domain.tencentSecretKey")}">
                                        <div class="password-actions">
                                            <button type="button" class="password-btn" onclick="togglePasswordVisibility('secretKeyInput')" title="${msg.get("domain.showOrHidden")}">
                                                <i class="fas fa-eye" id="secretKeyInput-eye"></i>
                                            </button>
                                            <button type="button" class="password-btn" onclick="copyToClipboard('secretKeyInput')" title="${msg.get("domain.copy")}">
                                                <i class="fas fa-copy"></i>
                                            </button>
                                        </div>
                                    </div>
                                    <div class="form-tip">${msg.get("domain.apiSave")}</div>
                                </div>
                            </div>
                        </form>
                    </div>
                    <div class="settings-card-footer">
                        <button type="button" class="btn btn-sm btn-info" onclick="testEdgeOneConnection()">
                            <i class="fas fa-plug"></i> ${msg.get("ip.testConn")}
                        </button>
                        <button type="button" class="btn btn-sm btn-primary" onclick="saveEdgeOneConfig()">
                            <i class="fas fa-save"></i> ${msg.get("notification.save")}
                        </button>
                    </div>
                </div>

                <!-- 占位卡片 - 方便后续扩展其他服务商 -->
                <div class="coming-soon-card">
                    <i class="fas fa-plus-circle"></i>
                    <h4>${msg.get("domain.moreProvider")}</h4>
                    <small>${msg.get("domain.PlzStayTuned")}</small>
                </div>
            </div>
        </div><!-- /.page-card -->
    </main>
</div>

<!-- 版本信息模块 -->
<#--
<#include "common/version_info.ftl">
-->

<script>
    // 初始化页面
    document.addEventListener('DOMContentLoaded', function() {
        // 侧边栏菜单展开/收起
        const navParents = document.querySelectorAll('.nav-parent');
        navParents.forEach(parent => {
            const parentLink = parent.querySelector('.nav-link');
            if (parentLink) {
                parentLink.addEventListener('click', (e) => {
                    e.preventDefault();
                    parent.classList.toggle('expanded');
                });
            }
        });

        // 展开当前活动菜单
        const activeLink = document.querySelector('.nav-link.active');
        if (activeLink) {
            const parent = activeLink.closest('.nav-parent');
            if (parent) {
                parent.classList.add('expanded');
            }
        }

        // 根据初始状态更新状态标识
        const enabled = ${cloudflareConfig.enabled?string('true', 'false')};
        const hasApiToken = '${cloudflareConfig.apiToken!''}' !== '';

        if (enabled && hasApiToken) {
            updateStatus('cloudflare','connected');
        } else {
            updateStatus('cloudflare','disconnected');
        }

        const edgeOneEnabled = ${edgeOneConfig.enabled?string('true', 'false')};
        const hasEdgeOneSecretId = '${edgeOneConfig.secretId!''}' !== '';
        const hasEdgeOneSecretKey = '${edgeOneConfig.secretKey!''}' !== '';

        if (edgeOneEnabled && hasEdgeOneSecretId && hasEdgeOneSecretKey) {
            updateStatus('edgeone', 'connected');
        } else {
            updateStatus('edgeone', 'disconnected');
        }
    });

    window.I18N = {
        common_noData: "${msg.get('common.noData')?js_string}",
        common_available: "${msg.get('common.available')?js_string}",
        common_noAvailable: "${msg.get('common.noAvailable')?js_string}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        domain_conn: "${msg.get('domain.conn')?js_string}",
        domain_disConn: "${msg.get('domain.disConn')?js_string}",
        domain_connecting: "${msg.get('domain.connecting')?js_string}",
        domain_noDataCopy: "${msg.get('domain.noDataCopy')?js_string}",
        domain_copySuccess: "${msg.get('domain.copySuccess')?js_string}",
        common_plzInputGlobalRequired: "${msg.get('common.plzInputGlobalRequired')?js_string}",
        common_saving: "${msg.get('common.saving')?js_string}",
        domain_testing: "${msg.get('domain.testing')?js_string}",

    }
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/system/domain_settings.js"></script>

</body>
</html>