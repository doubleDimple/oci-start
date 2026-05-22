<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
    <title>VPS管理系统 - API Token配置</title>
    <script>(function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <script src="/js/common/jquery.min.js"></script>
    <link rel="stylesheet" href="/css/app/notification_settings.css">
    <link rel="stylesheet" href="/css/app/api_token_config.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <style>
        .layout { padding-top: 0; }
        .main-content { margin-left: 0; padding: 20px 24px; background: var(--main-bg); }
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
                    <i class="fas fa-key"></i>
                    <span>${msg.get('token.page.title')}</span>
                </h1>
                <p class="page-description">${msg.get('token.page.description')}</p>
            </div>

            <!-- Token状态卡片 -->
            <div class="settings-grid">
                <!-- Token状态展示卡片 -->
                <div class="settings-card token-status-card">
                    <div class="settings-card-header">
                        <h3 class="settings-card-title">
                            <i class="fas fa-info-circle"></i>
                            ${msg.get('token.status.card.title')}
                        </h3>
                        <span class="token-status-badge ${tokenStatus.enabled?string('status-active', 'status-inactive')}">
                            ${tokenStatus.enabled?string(msg.get('token.status.enabled'), msg.get('token.status.disabled'))}
                        </span>
                    </div>
                    <div class="settings-card-body">
                        <div class="token-info-grid">
                            <div class="token-info-item">
                                <label>${msg.get('token.info.name')}</label>
                                <span>${tokenStatus.tokenName!msg.get('token.info.unset')}</span>
                            </div>
                            <div class="token-info-item">
                                <label>${msg.get('token.info.status')}</label>
                                <span>${tokenStatus.hasToken?string(msg.get('token.info.generated'), msg.get('token.info.not_generated'))}</span>
                            </div>
                            <#if tokenStatus.expiresAt??>
                                <div class="token-info-item">
                                    <label>${msg.get('token.info.expiry')}</label>
                                    <span>${tokenStatus.expiresAt}</span>
                                </div>
                                <div class="token-info-item">
                                    <label>${msg.get('token.info.days_left')}</label>
                                    <span class="${(tokenStatus.daysUntilExpiration < 7)?string('text-warning', '')}">${tokenStatus.daysUntilExpiration} ${msg.get('token.info.days')}</span>
                                </div>
                            </#if>
                            <#--<div class="token-info-item">
                                <label>Swagger访问</label>
                                <span>${tokenStatus.allowSwaggerAccess?string('允许', '禁止')}</span>
                            </div>-->
                            <div class="token-info-item full-width">
                                <label>${msg.get('token.info.description')}</label>
                                <span>${tokenStatus.description!msg.get('token.info.no_desc')}</span>
                            </div>

                            <!-- 新增：当前Token显示 -->
                            <#if tokenStatus.hasToken && tokenStatus.enabled>
                                <div class="token-info-item full-width">
                                    <label>${msg.get('token.info.current')}</label>
                                    <div class="token-value-container">
                                        <input type="text" id="currentToken" class="form-control token-input"
                                               value="${apiTokenConfig.tokenValue!''}" readonly>
                                        <button type="button" class="btn btn-sm btn-outline-primary" onclick="copyCurrentToken()">
                                            <i class="fas fa-copy"></i> ${msg.get('token.action.copy')}
                                        </button>
                                    </div>
                                </div>
                            </#if>


                        </div>
                    </div>
                </div>

                <!-- Token配置卡片 -->
                <div class="settings-card">
                    <div class="settings-card-header">
                        <h3 class="settings-card-title">
                            <i class="fas fa-cog"></i>
                            ${msg.get('token.config.card.title')}
                        </h3>
                    </div>
                    <div class="settings-card-body">
                        <form id="tokenConfigForm" class="compact-form">
                            <div class="form-row">
                                <label class="form-label">${msg.get('token.form.name')}</label>
                                <div class="form-control-with-tip">
                                    <input type="text" class="form-control" name="tokenName"
                                           value="${apiTokenConfig.tokenName!''}"
                                           placeholder="输入Token名称，如：生产环境API">
                                    <div class="form-tip">${msg.get('token.form.name.tip')}</div>
                                </div>
                            </div>
                            <div class="form-row">
                                <label class="form-label">${msg.get('token.form.expiry')}</label>
                                <div class="form-control-with-tip">
                                    <select class="form-control" name="expirationDays">
                                        <option value="7" ${(apiTokenConfig.expirationDays == 7)?string('selected', '')}>7${msg.get('token.info.days')}</option>
                                        <option value="30" ${(apiTokenConfig.expirationDays == 30)?string('selected', '')}>30${msg.get('token.info.days')}</option>
                                        <option value="90" ${(apiTokenConfig.expirationDays == 90)?string('selected', '')}>90${msg.get('token.info.days')}</option>
                                        <option value="180" ${(apiTokenConfig.expirationDays == 180)?string('selected', '')}>180${msg.get('token.info.days')}</option>
                                        <option value="365" ${(apiTokenConfig.expirationDays == 365)?string('selected', '')}>365${msg.get('token.info.days')}</option>
                                    </select>
                                    <div class="form-tip">${msg.get('token.form.expiry.tip')}</div>
                                </div>
                            </div>
                            <div class="form-row">
                                <label class="form-label">${msg.get('token.form.description')}</label>
                                <div class="form-control-with-tip">
                                    <textarea class="form-control" name="description" rows="3"
                                              placeholder="${msg.get('token.form.description.placeholder')}">${apiTokenConfig.description!''}</textarea>
                                    <div class="form-tip">${msg.get('token.form.description.tip')}</div>
                                </div>
                            </div>
                            <#--<div class="form-row">
                                <label class="form-label">Swagger访问权限</label>
                                <div class="form-control-with-tip">
                                    <label class="switch">
                                        <input type="checkbox" name="allowSwaggerAccess"
                                                ${apiTokenConfig.allowSwaggerAccess?string('checked', '')}>
                                        <span class="slider"></span>
                                    </label>
                                    <div class="form-tip">是否允许使用此Token访问Swagger API文档</div>
                                </div>
                            </div>-->
                        </form>
                    </div>
                    <div class="settings-card-footer">
                        <button type="button" class="btn btn-sm btn-success" onclick="generateToken()">
                            <i class="fas fa-key"></i> ${msg.get('token.action.generate')}
                        </button>
                        <button type="button" class="btn btn-sm btn-danger" onclick="revokeToken()"
                                <#if !tokenStatus.enabled>disabled</#if>>
                            <i class="fas fa-ban"></i> ${msg.get('token.action.revoke')}
                        </button>
                    </div>
                </div>

                <!-- API文档访问卡片 -->
                <div class="settings-card">
                    <div class="settings-card-header">
                        <h3 class="settings-card-title">
                            <i class="fas fa-book"></i>
                            ${msg.get('token.docs.card.title')}
                        </h3>
                    </div>
                    <div class="settings-card-body">
                        <div class="api-docs-info">
                            <p class="api-docs-description">
                                <i class="fas fa-info-circle"></i>
                                ${msg.get('token.docs.description')}
                            </p>
                            <div class="api-docs-links">
                                <a href="/swagger-ui/index.html" target="_blank" class="api-doc-link">
                                    <i class="fas fa-external-link-alt"></i>
                                    <span>${msg.get('token.docs.link.swagger')}</span>
                                </a>
                                <a href="/v3/api-docs" target="_blank" class="api-doc-link">
                                    <i class="fas fa-code"></i>
                                    <span>${msg.get('token.docs.link.json')}</span>
                                </a>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- API 使用说明卡片 -->
                <div class="settings-card usage-guide-card">
                    <div class="settings-card-header">
                        <h3 class="settings-card-title">
                            <i class="fas fa-code"></i>
                            ${msg.get('token.usage.card.title')}
                        </h3>
                    </div>
                    <div class="settings-card-body">
                        <div class="usage-methods">
                            <div class="usage-method">
                                <h5>
                                    <i class="fas fa-key"></i>
                                    ${msg.get('token.usage.method.header')}
                                    <button class="copy-code-btn" onclick="copyCode('Bearer {your_token}')">
                                        <i class="fas fa-copy"></i> ${msg.get('token.action.copy')}
                                    </button>
                                </h5>
                                <div class="method-code">Authorization: Bearer {your_token}</div>
                                <p class="method-description">${msg.get('token.usage.method.desc')}</p>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Token展示卡片（生成后显示） -->
                <div class="settings-card token-display-card" id="tokenDisplayCard" style="display: none;">
                    <div class="settings-card-header">
                        <h3 class="settings-card-title">
                            <i class="fas fa-eye"></i>
                            ${msg.get('token.usage.gen.value')}
                        </h3>
                        <#--<div class="token-warning">
                            <i class="fas fa-exclamation-triangle"></i>
                            请妥善保存，Token只显示一次
                        </div>-->
                    </div>
                    <div class="settings-card-body">
                        <div class="token-display">
                            <div class="token-value-container">
                                <input type="text" id="generatedToken" class="form-control token-input" readonly>
                                <button type="button" class="btn btn-sm btn-outline-primary" onclick="copyToken()">
                                    <i class="fas fa-copy"></i> ${msg.get('token.action.copy')}
                                </button>
                            </div>
                            <p style="margin-top: 10px; color: var(--text-secondary); font-size: 13px;">
                                <i class="fas fa-clock"></i>
                                ${msg.get('token.form.expiry')}：<span id="tokenExpirationInfo"></span>
                            </p>
                        </div>
                    </div>
                </div>
            </div>
        </div><!-- /.page-card -->
    </main>
</div>
<script>
    window.I18N = {
        // 登录与注册提示
        token_require_name: "${msg.get('token.require.name')}",
        token_confirm: "${msg.get('token.confirm')}",
        token_newAndOldTokenExpire: "${msg.get('token.newAndOldTokenExpire')}",
        token_genSuccess: "${msg.get('token.genSuccess')}",
        token_alreadyCopy: "${msg.get('token.alreadyCopy')}",
        token_delete: "${msg.get('token.delete')}",
        token_ApiCancel: "${msg.get('token.ApiCancel')}",
        token_ApiAlreadyCancel: "${msg.get('token.ApiAlreadyCancel')}",
        token_codeCopy: "${msg.get('token.codeCopy')}",
        token_genFail: "${msg.get('token.genFail')}",

    };
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/system/api_token_config.js"></script>
</body>
</html>