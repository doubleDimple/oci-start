<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
    <title>VPS管理系统 - 系统设置</title>
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>(function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">

    <!-- SweetAlert2 CSS -->
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <!-- SweetAlert2 JS -->
    <script src="/js/sweetalert2.min.js"></script>

<#--
    <script src="https://cdn.jsdelivr.net/npm/chart.js" defer></script>
-->
    <script src="/js/common/jquery.min.js"></script>
    <link rel="stylesheet" href="/css/app/system_settings.css">
    <link rel="stylesheet" href="/css/common/loading.css">
</head>
<body>
<!-- 引入顶部导航栏 -->
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
        <div class="settings-container">
            <!-- 页面标题 -->
            <div class="page-header">
                <h1 class="page-title">
                    <i class="fas fa-cogs"></i>
                    <span>${msg.get("sys.config")}</span>
                </h1>
            </div>

            <!-- 设置卡片网格布局 -->
            <div class="settings-grid">
                <!-- 账号安全设置 -->
                <div class="settings-card">
                    <div class="settings-card-header">
                        <h3 class="settings-card-title">
                            <i class="fas fa-shield-alt"></i>
                            ${msg.get("sys.security")}
                        </h3>
                    </div>
                    <div class="settings-card-body">
                        <form id="passwordForm" class="compact-form">
                            <!-- 当前账号信息 -->
                            <div class="form-row">
                                <label class="form-label">${msg.get("sys.currentUser")}</label>
                                <input type="text" class="form-control" value="${currentUsername}" disabled>
                            </div>
                            <div class="form-row">
                                <label class="form-label">Logo</label>
                                <div class="form-control-with-tip">
                                    <div style="display: flex; gap: 8px;">
                                        <input type="text"
                                               class="form-control"
                                               id="siteLogoInput"
                                               value="${siteLogoName!'OCI-START'}"
                                               placeholder="OCI-START">
                                        <button type="button"
                                                class="btn btn-sm btn-info"
                                                onclick="saveLogoNameOnly(this)">
                                            <i class="fas fa-check"></i>
                                            ${msg.get("common.save")}
                                        </button>
                                    </div>
                                </div>
                            </div>
                            <!-- 原密码验证 -->
                            <div class="form-row">
                                <label class="form-label">${msg.get("sys.currentPass")}</label>
                                <div class="form-control-with-tip">
                                    <input type="password" class="form-control" name="currentPassword" placeholder="${msg.get("sys.plzCurrentPass")}">
                                    <div class="form-tip">${msg.get("sys.verifyCurrentPass")}</div>
                                </div>
                            </div>
                            <!-- 用户名修改 -->
                            <div class="form-row">
                                <label class="form-label">${msg.get("sys.newUser")}</label>
                                <div class="form-control-with-tip">
                                    <input type="text" class="form-control" name="newUsername" placeholder="${msg.get("sys.inputNewUser")}">
                                    <div class="form-tip">${msg.get("sys.userBlank")}</div>
                                </div>
                            </div>
                            <!-- 密码修改 -->
                            <div class="form-row">
                                <label class="form-label">${msg.get("sys.newPass")}</label>
                                <div class="form-control-with-tip">
                                    <input type="password" class="form-control" name="newPassword" placeholder="${msg.get("sys.inputNewPass")}">
                                    <div class="form-tip">${msg.get("sys.passBlank")}</div>
                                </div>
                            </div>
                            <div class="form-row">
                                <label class="form-label">${msg.get("sys.confirmNewPass")}</label>
                                <input type="password" class="form-control" name="confirmPassword" placeholder="${msg.get("sys.secondInputNewPass")}">
                            </div>
                        </form>
                    </div>
                    <div class="settings-card-footer">
                        <button type="button" class="btn btn-sm btn-primary" onclick="updateAccount()">
                            <i class="fas fa-save"></i>
                            ${msg.get("sys.saveUpdate")}
                        </button>
                    </div>
                </div>

                <!-- GitHub OAuth配置 -->
                <div class="settings-card">
                    <div class="settings-card-header">
                        <div class="header-with-toggle">
                            <h3 class="settings-card-title">
                                <i class="fab fa-github"></i>
                                ${msg.get("sys.githubLogin")}
                            </h3>
                            <label class="switch">
                                <input type="checkbox" id="githubEnabled" name="enabled" ${githubConfig.enabled?string('checked', '')}>
                                <span class="slider"></span>
                            </label>
                        </div>
                    </div>
                    <div class="settings-card-body">
                        <form id="githubForm" class="compact-form">
                            <div class="form-row">
                                <label class="form-label">${msg.get("sys.githubUser")}</label>
                                <div class="form-control-with-tip">
                                    <div style="display: flex; gap: 8px;">
                                        <input type="text"
                                               class="form-control github-username-input"
                                               name="githubUsername"
                                               value="${(githubConfig.username)!''}"
                                               placeholder="${msg.get("sys.inputGithubUser")}"
                                               style="flex: 1;">
                                        <button type="button"
                                                class="btn btn-sm btn-info github-fetch-btn">
                                            <i class="fas fa-search"></i>
                                            ${msg.get("sys.githubId")}
                                        </button>
                                    </div>
                                </div>
                            </div>
                            <div class="form-row">
                                <label class="form-label">GitHub ID</label>
                                <input type="text"
                                       class="form-control github-id-input"
                                       name="githubId"
                                       value="${(githubConfig.githubId)!''}"
                                       readonly>
                                <div class="form-tip">${msg.get("sys.githubIdAuto")}</div>
                            </div>
                            <div class="form-row">
                                <label class="form-label">Client ID</label>
                                <input type="text" class="form-control" name="clientId"
                                       value="${githubConfig.clientId!''}"
                                       placeholder="${msg.get("sys.inputGithubIdClientId")}">
                                <div class="form-tip">${msg.get("sys.githubIdClientId")}</div>
                            </div>
                            <div class="form-row">
                                <label class="form-label">Client Secret</label>
                                <input type="password" class="form-control" name="clientSecret"
                                       value="${githubConfig.clientSecret!''}"
                                       placeholder="Client Secret">
                            </div>
                            <div class="form-row">
                                <label class="form-label">${msg.get("sys.githubWebHook")}</label>
                                <div class="form-control-with-tip">
                                    <input type="text" class="form-control" name="redirectUri"
                                           value="${githubConfig.redirectUri!''}"
                                           placeholder="http(s)://your-domain/api/github/callback">
                                    <div class="form-tip">${msg.get("sys.githubAppWebHookAddress")}</div>
                                </div>
                            </div>
                        </form>
                    </div>
                    <div class="settings-card-footer">
                        <button type="button" class="btn btn-sm btn-primary" onclick="updateGithubConfig(this)">
                            <i class="fas fa-save"></i>
                            ${msg.get("sys.githubSave")}
                        </button>
                    </div>
                </div>
                <div class="settings-card">
                    <div class="settings-card-header">
                        <div class="header-with-toggle">
                            <h3 class="settings-card-title">
                                <i class="fab fa-google"></i>
                                ${msg.get("sys.googleLogin")}
                            </h3>
                            <label class="switch">
                                <input type="checkbox" id="googleEnabled" name="enabled" ${(googleConfig.enabled!false)?string('checked', '')}>
                                <span class="slider"></span>
                            </label>
                        </div>
                    </div>
                    <div class="settings-card-body">
                        <form id="googleForm" class="compact-form">
                            <div class="form-row">
                                <label class="form-label">
                                    ${msg.get("sys.googleUser")}
                                    <span style="color: var(--accent-red);">*</span>
                                </label>
                                <div class="form-control-with-tip">
                                    <input type="text" class="form-control" name="googleEmail"
                                           value="${(googleConfig.email)!''}"
                                           placeholder="${msg.get("sys.inputGoogleEmail")}">
                                    <div class="form-tip">
                                        ${msg.get("sys.googleEmailTip")}
                                    </div>
                                </div>
                            </div>
                            <div class="form-row">
                                <label class="form-label">Client ID</label>
                                <input type="text" class="form-control" name="clientId"
                                       value="${(googleConfig.clientId)!''}"
                                       placeholder="${msg.get("sys.inputGoogleClientId")}">
                                <div class="form-tip">${msg.get("sys.googleClientIdTip")}</div>
                            </div>
                            <div class="form-row">
                                <label class="form-label">Client Secret</label>
                                <input type="password" class="form-control" name="clientSecret"
                                       value="${(googleConfig.clientSecret)!''}"
                                       placeholder="Client Secret">
                            </div>
                            <div class="form-row">
                                <label class="form-label">${msg.get("sys.githubWebHook")}</label>
                                <div class="form-control-with-tip">
                                    <input type="text" class="form-control" name="redirectUri"
                                           value="${(googleConfig.redirectUri)!''}"
                                           placeholder="http(s)://your-domain/api/google/callback">
                                    <div class="form-tip">${msg.get("sys.googleRedirectUriTip")}</div>
                                </div>
                            </div>
                        </form>
                    </div>
                    <div class="settings-card-footer">
                        <button type="button" class="btn btn-sm btn-primary" onclick="updateGoogleConfig(this)">
                            <i class="fas fa-save"></i>
                            ${msg.get("sys.githubSave")}
                        </button>
                    </div>
                </div>
                <!-- MFA配置 -->
                <div class="settings-card">
                    <div class="settings-card-header">
                        <div class="header-with-toggle">
                            <h3 class="settings-card-title">
                                <i class="fas fa-shield-alt"></i>
                                ${msg.get("sys.mfaVerify")}
                            </h3>
                            <label class="switch">
                                <input type="checkbox" id="mfaEnabled" name="enabled" ${mfaConfig.enabled?string('checked', '')}>
                                <span class="slider"></span>
                            </label>
                        </div>
                    </div>
                    <div class="settings-card-body">
                        <form id="mfaForm" class="compact-form">
                            <div class="form-row">
                                <label class="form-label">${msg.get("sys.appName")}</label>
                                <div class="form-control-with-tip">
                                    <input type="text" class="form-control" name="issuer"
                                           value="${mfaConfig.issuer!''}"
                                           placeholder="${msg.get("sys.thirdDeviceAppName")}">
                                    <div class="form-tip">${msg.get("sys.thirdAppName")}</div>
                                </div>
                            </div>
                            <#if mfaConfig.secretKey??>
                                <div class="form-row">
                                    <label class="form-label">${msg.get("sys.qrCode")}</label>
                                    <div style="text-align: center; padding: 10px;">
                                        <img src="data:image/png;base64,${mfaConfig.qrCode}" alt="MFA QR Code" style="max-width: 200px;">
                                    </div>
                                    <div class="form-tip">${msg.get("sys.googleDeviceScanQrCode")}</div>
                                </div>
                                <div class="form-row">
                                    <label class="form-label">${msg.get("sys.mfaSecret")}</label>
                                    <div class="form-control-with-tip">
                                        <input type="text" class="form-control" value="${mfaConfig.secretKey}" readonly>
                                        <div class="form-tip">${msg.get("sys.inputSecret")}</div>
                                    </div>
                                </div>
                                <!-- MFA验证输入框 -->
                                <div class="form-row">
                                    <label class="form-label">${msg.get("sys.verifyMfaCode")}</label>
                                    <div class="form-control-with-tip">
                                        <div style="display: flex; gap: 8px;">
                                            <input type="text"
                                                   class="form-control mfa-code-input"
                                                   id="mfaVerificationCode"
                                                   placeholder="${"sys.inputSixMfaCode"}"
                                                   maxlength="6"
                                                   pattern="[0-9]{6}"
                                                   style="flex: 1;">
                                            <button type="button"
                                                    class="btn btn-sm btn-info mfa-verify-btn"
                                                    onclick="verifyMfaCode(this)">
                                                <i class="fas fa-check"></i>
                                                ${msg.get("sys.executeMfaVerify")}
                                            </button>
                                        </div>
                                        <div class="form-tip">${msg.get("sys.inputDeviceCode")}</div>
                                    </div>
                                </div>
                            </#if>
                        </form>
                    </div>
                    <div class="settings-card-footer">
                        <button type="button" class="btn btn-sm btn-primary" onclick="updateMfaConfig(this)">
                            <i class="fas fa-save"></i>
                            ${msg.get("sys.mfaSave")}
                        </button>
                        <button type="button" class="btn btn-sm btn-info" onclick="regenerateMfaSecret(this)">
                            <i class="fas fa-refresh"></i>
                            ${msg.get("sys.secondGenMfaSecret")}
                        </button>
                        <#if mfaConfig.secretKey??>
                            <button type="button" class="btn btn-sm btn-danger" onclick="deleteMfaConfig(this)">
                                <i class="fas fa-trash"></i>
                                ${msg.get("sys.deleteMfa")}
                            </button>
                        </#if>
                    </div>
                </div>
                <!-- Cloudflare Turnstile 配置 -->
                <div class="settings-card">
                    <div class="settings-card-header">
                        <div class="header-with-toggle">
                            <h3 class="settings-card-title">
                                <i class="fas fa-shield-virus"></i>
                                ${msg.get("sys.turnstile")}
                            </h3>
                            <label class="switch">
                                <input type="checkbox" id="turnstileEnabled" name="enabled" ${(turnstileConfig.enabled!false)?string('checked', '')}>
                                <span class="slider"></span>
                            </label>
                        </div>
                    </div>
                    <div class="settings-card-body">
                        <form id="turnstileForm" class="compact-form">
                            <div class="form-row">
                                <label class="form-label">${msg.get("sys.turnstileSiteKey")}</label>
                                <div class="form-control-with-tip">
                                    <input type="text" class="form-control" name="siteKey"
                                           value="${(turnstileConfig.siteKey)!''}"
                                           placeholder="${msg.get("sys.turnstileSiteKeyPlaceholder")}">
                                    <div class="form-tip">${msg.get("sys.turnstileSiteKeyTip")}</div>
                                </div>
                            </div>
                            <div class="form-row">
                                <label class="form-label">${msg.get("sys.turnstileSecretKey")}</label>
                                <div class="form-control-with-tip">
                                    <input type="password" class="form-control" name="secretKey"
                                           value="${(turnstileConfig.secretKey)!''}"
                                           placeholder="${msg.get("sys.turnstileSecretKeyPlaceholder")}">
                                    <div class="form-tip">${msg.get("sys.turnstileSecretKeyTip")}</div>
                                </div>
                            </div>
                        </form>
                    </div>
                    <div class="settings-card-footer">
                        <button type="button" class="btn btn-sm btn-primary" onclick="updateTurnstileConfig(this)">
                            <i class="fas fa-save"></i>
                            ${msg.get("sys.turnstileSave")}
                        </button>
                    </div>
                </div>
            </div>
        </div>
    </main>
</div>

<!-- 版本信息模块 -->
<#--<#include "common/version_info.ftl">-->
<script>
    window.I18N = {
        common_network_error: "${msg.get('common.network.error')}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        sys_plzGetGithubId: "${msg.get('sys.plzGetGithubId')?js_string}",
        notification_plzInputGlobalInfo: "${msg.get('notification.plzInputGlobalInfo')?js_string}",
        common_confirmUpdate: "${msg.get('common.confirmUpdate')?js_string}",
        common_saving: "${msg.get('common.saving')?js_string}",
        sys_githubSave: "${msg.get('sys.githubSave')?js_string}",
        sys_plzGetGithubUser: "${msg.get('sys.plzGetGithubUser')?js_string}",
        sys_loading: "${msg.get('sys.loading')?js_string}",
        sys_githubUserSuccess: "${msg.get('sys.githubUserSuccess')?js_string}",
        sys_githubUserNotFund: "${msg.get('sys.githubUserNotFund')?js_string}",
        sys_plzCurrentPass: "${msg.get('sys.plzCurrentPass')?js_string}",
        sys_noEdit: "${msg.get('sys.noEdit')?js_string}",
        sys_passNoMatch: "${msg.get('sys.passNoMatch')?js_string}",
        sys_confirmMfa: "${msg.get('sys.confirmMfa')?js_string}",
        sys_disMfa: "${msg.get('sys.disMfa')?js_string}",
        sys_mfaEditSuccess: "${msg.get('sys.mfaEditSuccess')?js_string}",
        sys_mfaSecondGen: "${msg.get('sys.mfaSecondGen')?js_string}",
        sys_mfaSecondGenAndRefreshDevice: "${msg.get('sys.mfaSecondGenAndRefreshDevice')?js_string}",
        sys_mfaSecondSecret: "${msg.get('sys.mfaSecondSecret')?js_string}",
        verify_code_placeholder: "${msg.get('login.verify.code.placeholder')?js_string}",
        common_confirmFormatFail: "${msg.get('common.confirmFormatFail')?js_string}",
        sys_verifying: "${msg.get('sys.verifying')?js_string}",
        sys_mfaVerifySuccess: "${msg.get('sys.mfaVerifySuccess')?js_string}",
        sys_mfaVerifyFail: "${msg.get('sys.mfaVerifyFail')?js_string}",
        sys_checkDevCode: "${msg.get('sys.checkDevCode')?js_string}",
        sys_confirmMfaDelete: "${msg.get('sys.confirmMfaDelete')?js_string}",
        mfa_status_deleting: "${msg.get('mfa.status.deleting')?js_string}",
        sys_deleteMfa: "${msg.get('sys.deleteMfa')?js_string}",
        sys_ociStartVerify: "${msg.get('sys.ociStartVerify')?js_string}",
        sys_turnstile: "${msg.get('sys.turnstile')?js_string}",
        sys_turnstileSave: "${msg.get('sys.turnstileSave')?js_string}",
        sys_turnstileConfirmEnable: "${msg.get('sys.turnstileConfirmEnable')?js_string}",
        sys_turnstileDisable: "${msg.get('sys.turnstileDisable')?js_string}",
        sys_turnstilePlzFillKeys: "${msg.get('sys.turnstilePlzFillKeys')?js_string}",
        common_error: "${msg.get('common.error')?js_string}",
        common_success: "${msg.get('common.success')?js_string}",
        common_update_fail: "${msg.get('common.updateFail')?js_string}",
        common_loading: "${msg.get('common.loading')?js_string}",
        common_processing: "${msg.get('common.processing')?js_string}",
        common_submitting: "${msg.get('common.submitting')?js_string}",
        request_default_fail: "${msg.get('request.defaultFail')?js_string}",
        request_action_fail: "${msg.get('request.actionFail')?js_string}",
        request_operation_fail: "${msg.get('request.operationFail')?js_string}",
        request_network_or_server_error: "${msg.get('request.networkOrServerError')?js_string}",
        request_invalid_response_title: "${msg.get('request.invalidResponseTitle')?js_string}",
        request_invalid_response_message: "${msg.get('request.invalidResponseMessage')?js_string}",
        request_fail_title: "${msg.get('request.failTitle')?js_string}",
        request_service_error_title: "${msg.get('request.serviceErrorTitle')?js_string}",
        request_timeout_title: "${msg.get('request.timeoutTitle')?js_string}",
        request_timeout_message: "${msg.get('request.timeoutMessage')?js_string}",
        request_offline_title: "${msg.get('request.offlineTitle')?js_string}",
        request_offline_message: "${msg.get('request.offlineMessage')?js_string}",
        request_network_title: "${msg.get('request.networkTitle')?js_string}",
        request_network_message: "${msg.get('request.networkMessage')?js_string}",
        request_network_message_short: "${msg.get('request.networkMessageShort')?js_string}",
        request_success_title: "${msg.get('request.successTitle')?js_string}",
        request_success_message: "${msg.get('request.successMessage')?js_string}",
        request_http_400_suffix: "${msg.get('request.http400Suffix')?js_string}",
        request_http_401_suffix: "${msg.get('request.http401Suffix')?js_string}",
        request_http_403_suffix: "${msg.get('request.http403Suffix')?js_string}",
        request_http_404_suffix: "${msg.get('request.http404Suffix')?js_string}",
        request_http_408_suffix: "${msg.get('request.http408Suffix')?js_string}",
        request_http_409_suffix: "${msg.get('request.http409Suffix')?js_string}",
        request_http_413_suffix: "${msg.get('request.http413Suffix')?js_string}",
        request_http_429_suffix: "${msg.get('request.http429Suffix')?js_string}",
        request_http_5xx_suffix: "${msg.get('request.http5xxSuffix')?js_string}",
        request_http_generic_suffix: "${msg.get('request.httpGenericSuffix')?js_string}",
        request_form_missing: "${msg.get('request.formMissing')?js_string}",
        request_form_missing_with_id: "${msg.get('request.formMissingWithId')?js_string}",
        sys_githubIdFail: "${msg.get('sys.githubIdFail')?js_string}",
        sys_accountUpdateFail: "${msg.get('sys.accountUpdateFail')?js_string}",
        sys_mfaUpdateFail: "${msg.get('sys.mfaUpdateFail')?js_string}",
        sys_mfaCodeInputMissing: "${msg.get('sys.mfaCodeInputMissing')?js_string}",
        sys_mfaVerifyRequestFail: "${msg.get('sys.mfaVerifyRequestFail')?js_string}",
        sys_mfaVerifyPassed: "${msg.get('sys.mfaVerifyPassed')?js_string}",
        sys_mfaRegenerateFail: "${msg.get('sys.mfaRegenerateFail')?js_string}",
        sys_mfaDeleteFail: "${msg.get('sys.mfaDeleteFail')?js_string}",
        sys_googleUpdateFail: "${msg.get('sys.googleUpdateFail')?js_string}",
        sys_logoUpdateFail: "${msg.get('sys.logoUpdateFail')?js_string}",
        sys_turnstileUpdateFail: "${msg.get('sys.turnstileUpdateFail')?js_string}",
    }
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/system/system_settings.js"></script>
</body>
</html>
