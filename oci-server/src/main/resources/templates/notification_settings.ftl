<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 通知设置</title>

<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="/css/all.min.css">

    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>

    <script src="/js/common/jquery.min.js"></script>

    <link rel="stylesheet" href="/css/app/notification_settings.css">
    <link rel="stylesheet" href="/css/app/ai_model_config.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/common/custom-select.css">
</head>
<body>

<!-- 引入顶部导航栏 -->
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <main class="main-content">
        <div id="sysZoneHidden" data-zone="${systemZone}"></div>
        <div class="settings-container">

            <div class="settings-section">
                <div class="section-title">
                    <i class="fas fa-clock"></i>
                    <span>${msg.get("notification.task")}</span>

                    <div class="current-time-display">
                        <button id="showClocksBtn" class="btn-time-clock">🕒 ${msg.get("notification.sysTime.diff")}</button>
                    </div>

                </div>

                <div id="clockPanel" class="clock-panel hidden">

                    <div class="clock-box">
                        <h4>${msg.get("notification.sysTime")}（<span id="sysZoneLabel"></span>）</h4>
                        <div class="flip-clock" id="flipSys"></div>
                    </div>

                    <div class="clock-box">
                        <h4>${msg.get("notification.chinaTime")}（Asia/Shanghai）</h4>
                        <div class="flip-clock" id="flipBj"></div>
                    </div>

                    <div class="clock-diff">
                        <span>${msg.get("notification.diffTime")}：<strong id="flipDiff"></strong></span>
                    </div>
                    <canvas id="nebulaCanvas" class="nebula-bg"></canvas>

                </div>


                <div class="settings-grid-single">
                    <div class="settings-card">
                        <div class="settings-card-header">
                            <div class="header-with-toggle">
                                <h3 class="settings-card-title">
                                    <i class="fas fa-calendar-check"></i> ${msg.get("notification.task.schedule")}
                                </h3>
                                <label class="switch">
                                    <input type="checkbox" id="taskEnabled" ${taskConfig.enabled?string('checked','')}>
                                    <span class="slider"></span>
                                </label>
                            </div>
                        </div>

                        <div class="settings-card-body">
                            <form id="taskForm" class="compact-form">
                                <div class="form-row">
                                    <label class="form-label">${msg.get("notification.executeTime")}</label>
                                    <div class="form-control-with-tip">

                                        <div class="hour-picker-container">
                                            <button type="button" class="hour-picker-btn" id="hourPickerBtn">
                                                <span id="hourPickerLabel">${taskConfig.executeHour?string("00")}:00</span>
                                                <i class="fas fa-chevron-down"></i>
                                            </button>

                                            <div class="hour-picker-dropdown" id="hourPickerDropdown">
                                                <div class="hour-picker-grid" id="hourPickerGrid">
                                                    <#list 0..23 as hour>
                                                        <div class="hour-item <#if taskConfig.executeHour == hour>active</#if>"
                                                             data-hour="${hour}">
                                                            ${hour?string("00")}
                                                        </div>
                                                    </#list>
                                                </div>
                                            </div>

                                            <input type="hidden" name="executeHour" id="executeHour"
                                                   value="${taskConfig.executeHour}">
                                        </div>

                                        <div class="form-tip">${msg.get("notification.everyDay")}</div>
                                    </div>
                                </div>

                                <div class="form-row">
                                    <label class="form-label">${msg.get("notification.project")}</label>

                                    <div class="form-control-with-tip">

                                        <div class="task-checkbox-group">
                                            <label class="task-checkbox-item">
                                                <input type="checkbox" name="enableAccountCheck"
                                                       <#if taskConfig.enableAccountCheck?? && taskConfig.enableAccountCheck>checked</#if>>
                                                <span>${msg.get("notification.account")}</span>
                                            </label>

                                            <label class="task-checkbox-item">
                                                <input type="checkbox" name="enableBootLog"
                                                       <#if taskConfig.enableBootLog?? && taskConfig.enableBootLog>checked</#if>>
                                                <span>${msg.get("notification.botLog")}</span>
                                            </label>
                                            <label class="task-checkbox-item">
                                                <input type="checkbox" name="enableCostCheck"
                                                       <#if taskConfig.enableCostCheck?? && taskConfig.enableCostCheck>checked</#if>>
                                                <span>${msg.get("notification.ociCost")}</span>
                                            </label>
                                        </div>

                                        <div class="form-tip">${msg.get("notification.selectTask")}</div>
                                    </div>
                                </div>


                                <div class="form-row">
                                    <label class="form-label">${msg.get("notification.secret")}</label>
                                    <div class="form-control-with-tip">
                                        <input type="text" class="form-control" name="notificationSecret"
                                               value="${taskConfig.notificationSecret!''}"
                                               placeholder="${msg.get("notification.secret.input")}">
                                        <div class="form-tip">${msg.get("notification.verifySource")}</div>
                                    </div>
                                </div>
                            </form>
                        </div>

                        <div class="settings-card-footer">
                            <button type="button" class="btn btn-sm btn-primary" onclick="updateTaskConfig(this)">
                                <i class="fas fa-save"></i> ${msg.get("notification.save")}
                            </button>
                        </div>
                    </div>
                </div>
            </div>

            <div class="settings-section" style="margin-top: 40px;">
                <div class="section-title">
                    <i class="fas fa-bell"></i>
                    <span>${msg.get("notification.channel")}</span>
                </div>

                <div class="settings-grid">

                    <!-- ========= Telegram 通知 ========= -->
                    <div class="settings-card">
                        <div class="settings-card-header">
                            <div class="header-with-toggle">
                                <h3 class="settings-card-title">
                                    <i class="fab fa-telegram"></i> ${msg.get("notification.tg")}
                                </h3>
                                <label class="switch">
                                    <input type="checkbox" ${telegramConfig.enabled?string('checked','')}>
                                    <span class="slider"></span>
                                </label>
                            </div>
                        </div>
                        <div class="settings-card-body">
                            <form id="telegramForm" class="compact-form">
                                <div class="form-row">
                                    <label class="form-label">Bot Token</label>
                                    <div class="form-control-with-tip">
                                        <input type="text" class="form-control" name="botToken"
                                               value="${telegramConfig.botToken!''}">
                                        <div class="form-tip">${msg.get("notification.tg.botFather")}</div>
                                    </div>
                                </div>

                                <div class="form-row-group">
                                    <div class="form-row">
                                        <label class="form-label">Chat ID</label>
                                        <div class="form-control-with-tip">
                                            <input type="text" class="form-control" name="chatId"
                                                   value="${telegramConfig.chatId!''}">
                                            <div class="form-tip">${msg.get("notification.tg.id")}</div>
                                        </div>
                                    </div>

                                    <div class="form-row">
                                        <label class="form-label">Chat Name</label>
                                        <div class="form-control-with-tip">
                                            <input type="text" class="form-control" name="chatName"
                                                   value="${telegramConfig.chatName!''}">
                                        </div>
                                    </div>
                                </div>
                            </form>
                        </div>

                        <div class="settings-card-footer">
                            <button type="button" class="btn btn-sm btn-info" onclick="testTgTalk()">
                                <i class="fas fa-paper-plane"></i>${msg.get("notification.tg.test")}
                            </button>
                            <button type="button" class="btn btn-sm btn-success" onclick="startTgRobot()">
                                <i class="fas fa-robot"></i>${msg.get("notification.tg.regBot")}
                            </button>
                            <button type="button" class="btn btn-sm btn-warning" onclick="openAiConfigModal()">
                                <i class="fas fa-brain"></i>${msg.get("notification.tg.upAI")}
                            </button>
                            <button type="button" class="btn btn-sm btn-primary" onclick="updateTelegramConfig()">
                                <i class="fas fa-save"></i>${msg.get("notification.save")}
                            </button>
                        </div>
                    </div>

                    <!-- ========= Telegram 代理 ========= -->
                    <div class="settings-card">
                        <div class="settings-card-header">
                            <div class="header-with-toggle">
                                <h3 class="settings-card-title">
                                    <i class="fas fa-globe"></i> ${msg.get("notification.tg.proxy")}
                                </h3>
                                <label class="switch">
                                    <input type="checkbox" <#if proxyConfig.enabled>checked</#if>>
                                    <span class="slider"></span>
                                </label>
                            </div>
                        </div>

                        <div class="settings-card-body">
                            <form id="proxyForm" class="compact-form">

                                <div class="form-row">
                                    <label class="form-label">${msg.get("notification.tg.proxyType")}</label>
                                    <select class="form-control" name="proxyType">
                                        <option value="HTTP" <#if proxyConfig.type=="HTTP">selected</#if>>HTTP</option>
                                        <option value="HTTPS" <#if proxyConfig.type=="HTTPS">selected</#if>>HTTPS</option>
                                        <option value="SOCKS5" <#if proxyConfig.type=="SOCKS5">selected</#if>>SOCKS5</option>
                                    </select>
                                    <div class="form-tip">HTTP/HTTPS/SOCKS5</div>
                                </div>

                                <div class="form-row-group">
                                    <div class="form-row">
                                        <label class="form-label">${msg.get("notification.tg.proxyAddress")}</label>
                                        <input type="text" class="form-control" name="proxyHost"
                                               value="${proxyConfig.host!''}">
                                        <div class="form-tip">${msg.get("notification.tg.inputYourAddressAndPort")}</div>
                                    </div>

                                    <div class="form-row">
                                        <label class="form-label">${msg.get("notification.tg.proxyPort")}</label>
                                        <input type="text" class="form-control" name="proxyPort"
                                               value="${proxyConfig.port?c}" maxlength="5">
                                    </div>
                                </div>

                            </form>
                        </div>

                        <div class="settings-card-footer">
                            <button class="btn btn-sm btn-info" onclick="testProxyConnection()">
                                <i class="fas fa-network-wired"></i>${msg.get("notification.tg.test")}
                            </button>
                            <button class="btn btn-sm btn-primary" onclick="updateProxyConfig()">
                                <i class="fas fa-save"></i>${msg.get("notification.save")}
                            </button>
                        </div>
                    </div>

                    <!-- ========= Bark ========= -->
                    <div class="settings-card">
                        <div class="settings-card-header">
                            <div class="header-with-toggle">
                                <h3 class="settings-card-title">
                                    <i class="fas fa-bell"></i> ${msg.get("notification.bk")}
                                </h3>
                                <label class="switch">
                                    <input type="checkbox" ${barkConfig.enabled?string('checked','')}>
                                    <span class="slider"></span>
                                </label>
                            </div>
                        </div>

                        <div class="settings-card-body">
                            <form id="barkForm" class="compact-form">
                                <div class="form-row">
                                    <label class="form-label">${msg.get("notification.bk.url")}</label>
                                    <input type="text" class="form-control" name="url"
                                           value="${barkConfig.url!''}">
                                </div>

                                <div class="form-row">
                                    <label class="form-label">${msg.get("notification.bk.devKey")}</label>
                                    <input type="text" class="form-control" name="deviceKey"
                                           value="${barkConfig.deviceKey!''}">
                                </div>
                            </form>
                        </div>

                        <div class="settings-card-footer">
                            <button class="btn btn-sm btn-info" onclick="testBark()">
                                <i class="fas fa-paper-plane"></i>${msg.get("notification.tg.test")}
                            </button>
                            <button class="btn btn-sm btn-primary" onclick="updateBarkConfig(this)">
                                <i class="fas fa-save"></i>${msg.get("notification.save")}
                            </button>
                        </div>
                    </div>

                    <!-- ========= 钉钉 ========= -->
                    <div class="settings-card">
                        <div class="settings-card-header">
                            <div class="header-with-toggle">
                                <h3 class="settings-card-title">
                                    <i class="fab fa-dingtalk"></i> ${msg.get("notification.dd")}
                                </h3>
                                <label class="switch">
                                    <input type="checkbox" ${dingTalkConfig.enabled?string('checked','')}>
                                    <span class="slider"></span>
                                </label>
                            </div>
                        </div>

                        <div class="settings-card-body">
                            <form id="dingTalkForm" class="compact-form">
                                <div class="form-row">
                                    <label class="form-label">Webhook</label>
                                    <input type="text" class="form-control" name="webhook"
                                           value="${dingTalkConfig.webhook!''}">
                                </div>

                                <div class="form-row">
                                    <label class="form-label">${msg.get("notification.dd.secret")}</label>
                                    <input type="text" class="form-control" name="secret"
                                           value="${dingTalkConfig.secret!''}">
                                </div>
                            </form>
                        </div>

                        <div class="settings-card-footer">
                            <button class="btn btn-sm btn-info" onclick="testDingTalk()">
                                <i class="fas fa-paper-plane"></i>${msg.get("notification.tg.test")}
                            </button>
                            <button class="btn btn-sm btn-primary" onclick="updateDingTalkConfig(this)">
                                <i class="fas fa-save"></i>${msg.get("notification.save")}
                            </button>
                        </div>
                    </div>

                    <!-- ========= 飞书 ========= -->
                    <div class="settings-card">
                        <div class="settings-card-header">
                            <div class="header-with-toggle">
                                <h3 class="settings-card-title">
                                    <i class="fas fa-comment"></i> ${msg.get("notification.fs")}
                                </h3>
                                <label class="switch">
                                    <input type="checkbox" ${feishuConfig.enabled?string('checked','')}>
                                    <span class="slider"></span>
                                </label>
                            </div>
                        </div>

                        <div class="settings-card-body">
                            <form id="feishuForm" class="compact-form">
                                <div class="form-row">
                                    <label class="form-label">Webhook</label>
                                    <input type="text" class="form-control" name="webhook"
                                           value="${feishuConfig.webhook!''}">
                                </div>

                                <div class="form-row">
                                    <label class="form-label">${msg.get("notification.fs.secret")}</label>
                                    <input type="text" class="form-control" name="secret"
                                           value="${feishuConfig.secret!''}">
                                </div>
                            </form>
                        </div>

                        <div class="settings-card-footer">
                            <button class="btn btn-sm btn-info" onclick="testFeishu()">
                                <i class="fas fa-paper-plane"></i>${msg.get("notification.tg.test")}
                            </button>
                            <button class="btn btn-sm btn-primary" onclick="updateFeishuConfig(this)">
                                <i class="fas fa-save"></i>${msg.get("notification.save")}
                            </button>
                        </div>
                    </div>

                </div>
            </div>

        </div>
    </main>
</div>

<!-- AI配置模态框 -->
<div id="aiConfigModal" class="modal">
    <div class="modal-content ai-modal-wide">
        <div class="modal-header">
            <h3 class="modal-title"><i class="fas fa-brain"></i> ${msg.get("notification.tg.upAI")}</h3>
            <button class="modal-close" onclick="closeAiConfigModal()">&times;</button>
        </div>
        <div class="modal-body ai-modal-body">

            <!-- 租户选择栏 -->
            <div class="ai-filter-bar">
                <span class="ai-filter-label">${msg.get("notification.selectAiTenantName")}</span>
                <div class="ai-filter-select">
                    <select id="tenantSelect"
                            data-custom-select
                            data-placeholder="${msg.get("notification.plzSelectAiTenantName")}"
                            onchange="onTenantChange()">
                        <option value="">${msg.get("notification.plzSelectAiTenantName")}</option>
                    </select>
                </div>
                <div id="leftLoading" class="panel-spinner" style="display:none">
                    <i class="fas fa-spinner fa-spin"></i>
                </div>
            </div>

            <!-- 左右双面板 -->
            <div class="ai-grid">
                <!-- 左侧：可用 AI 模型 -->
                <div class="panel-card">
                    <div class="panel-header">
                        <h3 class="panel-title">
                            <i class="fas fa-robot"></i>
                            ${msg.get("notification.selectAiModel")}
                        </h3>
                    </div>
                    <div class="panel-body">
                        <div id="modelList">
                            <div class="empty-state">
                                <i class="fas fa-hand-point-up fa-2x"></i>
                                <p>${msg.get("notification.plzSelectAiTenantName")}</p>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- 右侧：已配置的模型 -->
                <div class="panel-card">
                    <div class="panel-header">
                        <h3 class="panel-title">
                            <i class="fas fa-cog"></i>
                            ${msg.get("notification.alreadyAiModel")}
                        </h3>
                        <div class="panel-actions">
                            <button class="btn btn-sm btn-secondary" onclick="loadCurrentAiConfigs()" title="${msg.get("notification.save")}">
                                <i class="fas fa-sync-alt"></i>
                            </button>
                        </div>
                    </div>
                    <div class="panel-body">
                        <div id="configList">
                            <div class="empty-state">
                                <i class="fas fa-spinner fa-spin fa-2x"></i>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

        </div>
    </div>
</div>

<script>
    window.I18N = {
        common_confirm: "${msg.get('common.confirm')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        notification_plzInputGlobalInfo: "${msg.get('notification.plzInputGlobalInfo')?js_string}",
        notification_tg_required: "${msg.get('notification.tg.required')?js_string}",
        common_confirmUpdate: "${msg.get('common.confirmUpdate')?js_string}",
        common_confirmUpdateSuccess: "${msg.get('common.confirmUpdateSuccess')?js_string}",
        common_confirmUpdateFail: "${msg.get('common.confirmUpdateFail')?js_string}",
        common_confirmFormatFail: "${msg.get('common.confirmFormatFail')?js_string}",
        common_saving: "${msg.get('common.saving')?js_string}",
        common_sendSuccess: "${msg.get('common.sendSuccess')?js_string}",
        common_sendFail: "${msg.get('common.sendFail')?js_string}",
        notification_save: "${msg.get('notification.save')?js_string}",
        common_testSuccess: "${msg.get('common.testSuccess')?js_string}",
        common_testFail: "${msg.get('common.testFail')?js_string}",
        notification_tg_isReg: "${msg.get('notification.tg.isReg')}",
        notification_tg_getAiModelFail: "${msg.get('notification.tg.getAiModelFail')?js_string}",
        notification_selectAiTenantName: "${msg.get('notification.selectAiTenantName')?js_string}",
        notification_plzSelectAiTenantName: "${msg.get('notification.plzSelectAiTenantName')?js_string}",
        notification_selectAiModel: "${msg.get('notification.selectAiModel')?js_string}",
        common_loadFail: "${msg.get('common.loadFail')?js_string}",
        notification_noGetAiModelTableAndRetry: "${msg.get('notification.noGetAiModelTableAndRetry')?js_string}",
        common_loadRetry: "${msg.get('common.loadRetry')?js_string}",
        notification_plzAiModel: "${msg.get('notification.plzAiModel')?js_string}",
        notification_aiModelInfoError: "${msg.get('notification.aiModelInfoError')?js_string}",
        notification_noAiConfig: "${msg.get('notification.noAiConfig')?js_string}",
        notification_addYourAiModel: "${msg.get('notification.addYourAiModel')?js_string}",
        notification_alreadyAiModel: "${msg.get('notification.alreadyAiModel')?js_string}",
        common_start: "${msg.get('common.start')?js_string}",
        common_stop: "${msg.get('common.stop')?js_string}",
        common_delete: "${msg.get('common.delete')?js_string}"
    };
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/common/custom-select.js"></script>
<script src="/js/common/time_clock_panel.js"></script>
<script src="/js/system/notification_settings.js"></script>
</body>
</html>
