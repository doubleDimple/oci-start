<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <input type="hidden" name="_csrf" value="${_csrf.token}">
    <title>VPS管理系统 - 租户管理</title>
    <script>(function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <script src="/js/common/chart.js"></script>
    <script src="/js/common/dropdown-menu.js"></script>
    <link rel="stylesheet" href="/css/app/tenant-list.css">
    <link rel="stylesheet" href="/css/common/dropdown-menu.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/common/custom-select.css">
    <script src="/js/common/jquery.min.js"></script>
    <style>
        .layout { padding-top: 0; }
        .main-content { margin-left: 0; padding: 20px 24px; background: var(--main-bg); }
    </style>

    <#include "common/pagination.ftl" />
</head>
<body>
<!-- 引入顶部导航栏 -->
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
        <div class="page-card">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-key"></i>
                <span>${msg.get("tenant.config")}</span>
            </h1>
            <!-- 搜索框组件 -->
            <div class="search-container">
                <form id="searchForm" action="/tenants/list" method="GET" class="search-form">
                    <div class="search-input-group">
                        <input type="text" id="searchKeyword" name="keyword" placeholder="${msg.get("tenant.searchName")}" value="${keyword!''}" class="search-input">
                        <button type="submit" class="btn btn-primary search-btn">
                            <i class="fas fa-search"></i>
                        </button>
                        <button type="button" id="clearSearch" class="btn btn-secondary clear-btn" style="display: ${(keyword?? && keyword != '')?string('inline-flex', 'none')}">
                            <i class="fas fa-times"></i>
                        </button>
                    </div>
                </form>
            </div>
            <div class="view-actions">
                <div class="view-toggle">
                    <button class="btn" id="spoilerToggleBtn" onclick="toggleAllSpoilers()" title="${msg.get('tenant.toggleName')}">
                        <i class="fas fa-eye" id="spoilerToggleIcon"></i>
                    </button>
                </div>
                <div class="btn-group">
                    <#if cloudType?? && cloudType == 1>
                        <#--<button class="btn btn-success" onclick="batchEnableIcmp()">
                            <i class="fas fa-shield-alt"></i>
                            <span>${messages.enableAllProtocols!'开启所有协议'}</span>
                        </button>-->
                        <a href="/tenants/addSpeed" class="btn btn-success">
                            <i class="fas fa-bolt"></i>
                            <span>${msg.get("tenant.apiImport")}</span>
                        </a>
                        <!-- 导出数据按钮 -->
                        <a href="javascript:void(0);" class="btn btn-primary" onclick="exportData()">
                            <i class="fas fa-download"></i>
                        <span>${msg.get("tenant.apiExport")}</span>
                        </a>

                        <!-- 导入数据按钮 -->
                        <a href="javascript:void(0);" class="btn btn-primary" onclick="importData()">
                            <i class="fas fa-upload"></i>
                        <span>${msg.get("tenant.tenantImport")}</span>
                        </a>
                        <!-- 批量检测按钮 -->
                        <button class="btn btn-primary" onclick="startAccountCheck()">
                        <i class="fas fa-check-circle"></i> ${msg.get("tenant.tenantCheck")}
                        </button>

                    <#elseif cloudType?? && cloudType == 2>
                        <a href="/tenants/addSpeed" class="btn btn-success">
                            <i class="fas fa-bolt"></i>
                            <span>${msg.get("tenant.apiImport")}</span>
                        </a>
                    </#if>

                </div>
            </div>
        </div>
        <!-- 添加搜索结果信息显示 -->
        <#if keyword?? && keyword != ''>
            <div class="search-results-info">
                <i class="fas fa-info-circle"></i>
                ${msg.get("tenant.showKeys")} "<span class="search-keyword">${keyword}</span>" ${msg.get("tenant.keyRes")}
                <a href="/tenants/list" class="clear-search-link">
                    <i class="fas fa-times-circle"></i> ${msg.get("tenant.cleanSearch")}
                </a>
            </div>
        </#if>

        <!-- Table View -->
        <div class="table-view">
            <table class="table" style="table-layout: fixed;">
                <colgroup>
                    <col style="width: 42px;">   <!-- # -->
                    <col style="width: 80px;">   <!-- 租户名 -->
                    <col style="width: 140px;">  <!-- 自定义名称 -->
                    <col style="width: 80px;">   <!-- 账号成本 -->
                    <col style="width: 80px;">   <!-- 存活天数 -->
                    <col style="width: 80px;">   <!-- 开机任务 -->
                    <col style="width: 80px;">   <!-- 主区域 -->
                    <col style="width: 70px;">   <!-- 是否多区 -->
                    <col style="width: 110px;">  <!-- 账号类型 -->
                    <col style="width: 100px;">  <!-- 实例操作 -->
                    <col style="width: 145px;">  <!-- 创建时间 -->
                    <col style="width: 80px;">   <!-- 账号状态 -->
                    <col style="width: 52px;">   <!-- 操作 -->
                </colgroup>
                <thead>
                <tr>
                    <th style="text-align: center;">#</th>
                    <th>${msg.get("tenant.name")}</th>
                    <th>${msg.get("tenant.defName")}</th>
                    <th>${msg.get("tenant.accountCost")}</th>
                    <th>${msg.get("tenant.activeDays")}</th>
                    <th>${msg.get("tenant.openTask")}</th>
                    <th>${msg.get("tenant.homeRegion")}</th>
                    <th>${msg.get("tenant.manyRegionFlag")}</th>
                    <th>${msg.get("tenant.type")}</th>
                    <th>${msg.get("tenant.create")}</th>
                    <th>${msg.get("tenant.createTime")!'创建时间'}</th>
                    <th>${msg.get("tenant.status")!'账号状态'}</th>
                    <th>${msg.get("tenant.action")}</th>
                </tr>
                </thead>
                <tbody id="tenant-table-body">
                <#list tenants as tenant>
                    <#assign rowIndex = currentPage * size + tenant?index + 1>
                    <tr class="parent-row" data-id="${tenant.id?c}">
                        <td class="col-center" style="color: var(--text-secondary); font-size: 12px;">${rowIndex}</td>
                        <#--<td class="col-center">
                            <#if tenant.emailEnable?? && tenant.emailEnable == 1>
                                <i class="fas fa-envelope email-icon-on" title="${msg.get('tenant.enabledEmail')!''}"></i>
                            <#else>
                                <i class="fas fa-envelope email-icon-off" title="${msg.get('tenant.startEmailServer')!''}"></i>
                            </#if>
                        </td>-->
                        <td class="col-name">
                            <#assign tn = (tenant.tenancyName)!''>
                            <#assign maskedTn = (tn?length > 2)?then(tn?substring(0,1) + '***' + tn?substring(tn?length - 1), (tn?length > 0)?then('***', ''))>
                            <span class="name-spoiler is-hidden" onclick="toggleSpoiler(this)" title="${tn}">
                                <span class="name-masked">${maskedTn}</span>
                                <span class="name-full">${tn}</span>
                            </span>
                        </td>
                        <td>
                            <#assign dn = (tenant.defName)!''>
                            <a class="cell-edit-link defname-cell" href="javascript:void(0);"
                               onclick="editCustomName('${tenant.id?c}', '${dn?js_string}')"
                               id="defName-${tenant.id?c}"
                               data-fullname="${dn}"
                               title="${dn}"></a>
                        </td>
                        <td>
                            <a class="cell-edit-link" href="javascript:void(0);"
                               onclick="editAccountCost('${tenant.id?c}', '${(tenant.accountCost!'')?js_string}')"
                               id="cost-${tenant.id?c}"
                               title="${msg.get("tenant.accountCost")}">${tenant.accountCost!''}</a>
                        </td>
                        <td class="col-center">
                            <span class="days-chip">${tenant.activeDays!'0'}</span>
                        </td>
                        <td>
                            <span class="status-badge ${tenant.openBootFlag?then('status-running', 'status-idle')}">
                                <#if tenant.openBootFlag>
                                    <i class="fas fa-circle-notch fa-spin" style="font-size:10px;"></i>
                                </#if>
                                ${tenant.openBootFlag?then('${msg.get("openBoot.task")}', '${msg.get("openBoot.noTask")}')}
                            </span>
                        </td>
                       <#-- <td class="col-secondary"><span class="truncate" onclick="toggleText(this)" data-fulltext="${tenant.userName!''}">${tenant.userName!''}</span></td>-->
                        <td class="col-code"><span class="truncate" onclick="toggleText(this)" data-fulltext="${tenant.region!''}">${tenant.region!''}</span></td>
                        <#--<td>
                            <span class="home-region-badge ${(tenant.hasChildren!false)?string('is-home','not-home')}">
                                ${(tenant.hasChildren!false)?string('${msg.get("tenant.yes")}', '${msg.get("tenant.no")}')}
                            </span>
                        </td>-->
                        <td>
                            <#assign isMultiRegion = false>
                            <#if (tenant.children)?? && (tenant.children?size > 0)>
                                <#if tenant.children?size == 1 && tenant.children[0].region == tenant.region>
                                    <#assign isMultiRegion = false>
                                <#else>
                                    <#assign isMultiRegion = true>
                                </#if>
                            </#if>

                            <span class="home-region-badge ${isMultiRegion?string('not-home','is-home')}">
                                ${isMultiRegion?string(msg.get("tenant.yes"), msg.get("tenant.no"))}
                            </span>
                        </td>
                        <td>
                            <#if tenant.accountTypeName != '${msg.get("tenant.unKnow")}'>
                                <a href="javascript:void(0);"
                                   class="account-type-link account-type-${(tenant.accountType!'unknown')?lower_case?replace('_', '-')}"
                                   onclick="showAccountDetail('${tenant.id?c}')"
                                   title="${msg.get("tenant.accountDetail")}">
                                    ${tenant.accountTypeName}
                                </a>
                            <#else>
                                <span class="account-type-text">
                                    ${(tenant.hasChildren!false)?string('${msg.get("tenant.simpleMoreRegion")}', '${msg.get("tenant.unKnow")}')}
                                </span>
                            </#if>
                        </td>
                        <td class="col-center">
                            <#if tenant.cloudType?? && tenant.cloudType == 1>
                                <a href="/tenants/bootPage?tenantId=${tenant.id?c}" class="btn-boot">
                                    <i class="fas fa-rocket"></i> ${msg.get("tenant.computer")}
                                </a>
                            <#else>
                                <span class="text-unsupported">—</span>
                            </#if>
                        </td>
                        <td class="col-secondary" style="white-space: nowrap; font-size: 12px;">${tenant.createdAtStr!''}</td>
                        <td class="col-center">
                            <#if (tenant.isActive!true)>
                                <span class="status-badge status-running" style="font-size:11px;">
                                    <i class="fas fa-check-circle" style="font-size:10px;"></i> ${msg.get("tenant.active")!'有效'}
                                </span>
                            <#else>
                                <span class="status-badge status-idle" style="font-size:11px;">
                                    <i class="fas fa-ban" style="font-size:10px;"></i> ${msg.get("tenant.inactive")!'失效'}
                                </span>
                            </#if>
                        </td>
                        <td class="actions-cell">
                            <div class="dropdown">
                                <!-- 主操作按钮（横向三个点） -->
                                <button class="dropdown-toggle btn">
                                    <i class="fas fa-ellipsis-h"></i>
                                </button>

                                <!-- 操作菜单 -->
                                <div class="dropdown-panel">
                                    <#if tenant.cloudType?? && tenant.cloudType == 1>
                                        <#assign transferred = (tenant.transferStatus!0) == 1>
                                        <#if !transferred>
                                        <#if tenant.supportAI?? && tenant.supportAI == 1>
                                            <a href="/ai/chat?tenantId=${tenant.id?c}" class="dropdown-item" title="${msg.get("tenant.ai")}">
                                                <i class="fas fa-cogs"></i><span>${msg.get("tenant.ai")}</span>
                                            </a>
                                        </#if>
                                            <a href="/tenants/bootPage?tenantId=${tenant.id?c}" class="dropdown-item">
                                                <i class="fas fa-plus"></i><span>${msg.get("detail.openBoot")}</span>
                                            </a>
                                        <button class="dropdown-item" onclick="handleUpdateAccountDetail('${tenant.id?c}')" title="${msg.get("tenant.update")}">
                                            <i class="fas fa-redo"></i><span>${msg.get("tenant.update")}</span>
                                        </button>

                                        <a href="/tenants/regionList?tenantId=${tenant.id?c}" class="dropdown-item" title="${msg.get("tenant.detail")}">
                                            <i class="fas fa-info-circle"></i><span>${msg.get("tenant.detail")}</span>
                                        </a>

                                        <a href="/tenants/regionSubList?tenantId=${tenant.id?c}" class="dropdown-item" title="${msg.get("tenant.regionSub")}">
                                            <i class="fas fa-globe"></i><span>${msg.get("tenant.regionSub")}</span>
                                        </a>

                                        <button class="dropdown-item" onclick="showUserManagement('${tenant.id?c}')" title="${msg.get("tenant.user")}">
                                            <i class="fas fa-users"></i><span>${msg.get("tenant.user")}</span>
                                        </button>

                                        <button class="dropdown-item" onclick="showTrafficAlert('${tenant.id?c}')" title="${msg.get("tenant.traffic")}">
                                            <i class="fas fa-bell"></i><span>${msg.get("tenant.traffic")}</span>
                                        </button>

                                        <a href="/monitor/homePage?tenantId=${tenant.id?c}" class="dropdown-item" title="${msg.get("tenant.trafficSearch")}">
                                            <i class="fas fa-chart-bar"></i><span>${msg.get("tenant.trafficSearch")}</span>
                                        </a>
                                        <button class="dropdown-item" onclick="showAuditLogs('${tenant.id?c}')" title="${msg.get("tenant.log")}">
                                            <i class="fas fa-clipboard-list"></i> ${msg.get("tenant.log")}
                                        </button>
                                        <a href="/cost/costPage?tenantId=${tenant.id?c}" class="dropdown-item" title="${msg.get("tenant.cost")}">
                                            <i class="fas fa-info-circle"></i><span>${msg.get("tenant.cost")}</span>
                                        </a>

                                        <button class="dropdown-item" onclick="exportDataByTenant('${tenant.id?c}')" title="${msg.get("tenant.export")}">
                                            <i class="fas fa-download"></i> ${msg.get("tenant.export")}
                                        </button>
                                        <button class="dropdown-item"
                                                onclick="handleEmailServiceAction('${tenant.id?c}', ${tenant.emailEnable!0})"
                                                title="${msg.get('tenant.emailServer')}">
                                            <i class="fas fa-envelope"></i>
                                            <span>${msg.get('tenant.emailServer')}</span>
                                        </button>
                                        <button class="dropdown-item" onclick="showSocialLoginModal('${tenant.id?c}', '${tenant.cloudType!1}')" title="${msg.get('tenant.socialLogin')!'社媒配置'}">
                                            <i class="fas fa-share-alt"></i><span>${msg.get('tenant.socialLogin')}</span>
                                        </button>
                                        <button class="dropdown-item" onclick="showQuotaModal('${tenant.id?c}')" title="查看配额">
                                            <i class="fas fa-chart-bar" style="color:#2563eb;"></i><span>查看配额</span>
                                        </button>
                                        <#else>
                                        <#-- 已转移：显示“转移详情”按钮 -->
                                            <#--<button class="dropdown-item" onclick="showTransferDetail('${tenant.id?c}', '${tenant.transferAmount!'0'}')" title="转移详情">
                                                <i class="fas fa-file-invoice-dollar"></i><span>转移详情</span>
                                            </button>-->
                                        </#if>
                                        <button class="dropdown-item" onclick="handleDelete('${tenant.id?c}')" title="${msg.get("tenant.deleteTenant")}">
                                            <i class="fas fa-trash"></i><span>${msg.get("tenant.deleteTenant")}</span>
                                        </button>
                                    <#elseif tenant.cloudType?? && tenant.cloudType == 2>
                                        <a href="/tenants/regionList?tenantId=${tenant.id?c}" class="dropdown-item" title="${msg.get("tenant.detailAccount")}">
                                            <i class="fas fa-info-circle"></i><span>${msg.get("tenant.detailAccount")}</span>
                                        </a>
                                        <button class="dropdown-item" onclick="handleDelete('${tenant.id?c}')" title="${msg.get("tenant.deleteTenant")}">
                                            <i class="fas fa-trash"></i><span>${msg.get("tenant.deleteTenant")}</span>
                                        </button>
                                    </#if>
                                </div>
                            </div>
                        </td>
                    </tr>
                </#list>
                </tbody>
            </table>
        </div>

                <@pagination
        url="/tenants/list"
        page=currentPage
        size=size
        totalPages=totalPages
        totalElements=totalElements
        textShow=msg.get("page.show")
        textItem=msg.get("page.item")
        textPrev=msg.get("page.prev")
        textNext=msg.get("page.next")
        textJump=msg.get("page.jump")
        textPage=msg.get("page.page")
        textTotal=msg.get("page.total")
        />
        </div><!-- /.page-card -->
    </main>
</div>
<!-- Modal Overlays -->
<div id="syncModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("tenant.ociSyncing")}</h3>
        </div>
        <div class="progress-container">
            <div id="progressBar" class="progress-bar"></div>
        </div>
        <div id="statusMessage" class="status-message syncing">
            <span class="loading-spinner"></span>
            <span id="statusText">${msg.get("tenant.ociSyncLoading")}</span>
        </div>
    </div>
</div>

<div id="checkStatusModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("tenant.checkStatus")}</h3>
        </div>
        <div id="checkStatusContent">
            <div id="checkStatusMessage" class="status-message syncing">
                <span class="loading-spinner"></span>
                <span id="checkStatusText">${msg.get("tenant.checking")}</span>
            </div>
            <div id="checkDetails" style="display: none; margin-top: 15px;">
                <h4 style="margin-bottom: 10px; font-size: 14px;">${msg.get("tenant.checkDetail")}:</h4>
                <div id="checkDetailsList"></div>
            </div>
        </div>
    </div>
</div>

<div id="editCustomNameModal" class="modal-overlay">
    <div class="modal-container edit-name-modal">
        <div class="modal-header">
            <h3 class="modal-title">
                <i class="fas fa-edit"></i>
                ${msg.get("tenant.editDefName")}
            </h3>
        </div>
        <div class="modal-content">
            <form class="edit-name-form">
                <div class="form-group">
                    <label for="customNameInput">${msg.get("tenant.defName")}</label>
                    <input type="text" id="customNameInput" placeholder="${msg.get("tenant.editDefName")}" maxlength="100">
                    <small style="color: var(--text-secondary); font-size: 12px; margin-top: 5px; display: block;">
                        ${msg.get("tenant.defNameLimit")}
                    </small>
                </div>
                <div class="form-actions">
                    <button type="button" class="btn btn-success" onclick="saveCustomName()">
                        <i class="fas fa-save"></i>
                        ${msg.get("common.save")}
                    </button>
                    <button type="button" class="btn btn-secondary" onclick="closeEditCustomNameModal()">
                        <i class="fas fa-times"></i>
                        ${msg.get("common.cancel")}
                    </button>
                </div>
            </form>
        </div>
    </div>
</div>

<div id="userManagementModal" class="modal-overlay">
    <div class="modal-container" style="max-width: 900px;">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("tenant.mgr")}</h3>
        </div>

        <!-- 标签页导航 -->
        <div class="user-management-tabs" style="display: flex; margin-bottom: 15px; background: var(--hover-bg); padding: 4px; border-radius: 2px;">
            <button class="user-tab active" data-tab="users" onclick="switchUserTab('users')">
                <i class="fas fa-users"></i>
                ${msg.get("tenant.mgrUser")}
            </button>
            <button class="user-tab" data-tab="notifications" onclick="switchUserTab('notifications')">
                <i class="fas fa-envelope"></i>
                ${msg.get("tenant.mgrNotifyEmail")}
            </button>
            <button class="user-tab" data-tab="mfa" onclick="switchUserTab('mfa')">
                <i class="fas fa-shield-alt"></i>
               ${msg.get("tenant.mgrMfa")}
            </button>
        </div>

        <!-- 用户列表标签页 -->
        <div id="usersTab" class="tab-content active">
            <div class="btn-group" style="margin-bottom: 15px;">
                <button class="btn btn-success" onclick="showAddUserForm()">
                    <i class="fas fa-plus"></i>
                    ${msg.get("tenant.mgrAddUser")}
                </button>
                <button class="btn btn-primary" onclick="refreshUserList()">
                    <i class="fas fa-sync"></i>
                    ${msg.get("tenant.mgrAddUserRefresh")}
                </button>
                <button class="btn btn-password-policy" onclick="showPasswordPolicyModal()">
                    <i class="fas fa-key"></i>
                    ${msg.get("tenant.mgrPassPolicy")}
                </button>
                <#--<button class="btn btn-warning" onclick="showResetPasswordModal()">
                    <i class="fas fa-unlock-alt"></i>
                    重置密码
                </button>-->
            </div>

            <!-- 添加用户表单 -->
            <div id="addUserForm" class="edit-rule-form" style="display: none;">
            </div>

            <div class="table-view" style="margin-top: 15px;">
                <table class="table">
                    <thead>
                    <tr>
                        <th>${msg.get("tenant.mgrDomain")}</th>
                        <th>${msg.get("login.username")}</th>
                        <th>${msg.get("email.address")}</th>
                        <th>${msg.get("tenant.mgrAccStatus")}</th>
                        <th>${msg.get("tenant.mgrcTime")}</th>
                        <th>${msg.get("tenant.mgrLastLoginTime")}</th>
                        <th style="width: 15%;">${msg.get("tenant.mgrAction")}</th>
                    </tr>
                    </thead>
                    <tbody id="userListTableBody">
                    <tr>
                        <td colspan="6" class="text-center">
                            <span class="loading-spinner"></span>
                            ${msg.get("common.loading")}
                        </td>
                    </tr>
                    </tbody>
                </table>
            </div>
        </div>

        <!-- 通知邮箱标签页 -->
        <div id="notificationsTab" class="tab-content" style="display: none;">
            <div class="btn-group" style="margin-bottom: 15px;">
                <button class="btn btn-success" onclick="showAddNotificationEmailForm()">
                    <i class="fas fa-plus"></i>
                    ${msg.get("tenant.mgrAddEmail")}
                </button>
                <button class="btn btn-primary" onclick="refreshNotificationRecipients()">
                    <i class="fas fa-sync"></i>
                    ${msg.get("tenant.mgrAddUserRefresh")}
                </button>
            </div>

            <!-- 通知邮箱信息区域 -->
            <#--<div id="notificationInfoSection" style="margin-bottom: 20px; padding: 15px; background-color: rgba(33, 150, 243, 0.05); border-radius: 4px; border-left: 4px solid var(--accent-blue);">
                <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 10px;">
                    <i class="fas fa-info-circle" style="color: var(--accent-blue);"></i>
                    <span style="font-weight: 500; color: var(--text-primary);">通知邮箱设置</span>
                </div>
                <div style="color: var(--text-secondary); font-size: 13px; line-height: 1.5;">
                    <p style="margin: 0 0 8px 0;">• 通知邮箱用于接收域级别的管理员通知，如用户创建、密码重置等</p>
                    <p style="margin: 0 0 8px 0;">• 支持添加多个邮箱地址，所有邮箱都会收到相同的通知</p>
                    <p style="margin: 0;">• 修改后立即生效，新的通知将发送到更新后的邮箱列表</p>
                </div>
            </div>-->

            <!-- 添加通知邮箱表单 -->
            <div id="addNotificationEmailForm" class="edit-rule-form" style="display: none;">
                <div class="form-group">
                    <label>${msg.get("domain.cfEmail")} <span style="color:var(--accent-red);">*</span></label>
                    <input type="email" id="notificationEmail" placeholder="${msg.get("email.plzAddress")}" required>
                </div>
                <div class="form-actions">
                    <button class="btn btn-primary" onclick="addNotificationEmail()">${msg.get("tenant.mgrAdd")}</button>
                    <button class="btn btn-danger" onclick="hideAddNotificationEmailForm()">${msg.get("common.cancel")}</button>
                </div>
            </div>

            <!-- 通知邮箱列表 -->
            <div class="table-view">
                <table class="table">
                    <thead>
                    <tr>
                        <th style="width: 60px;">${msg.get("index.donation.tableNo")}</th>
                        <th>${msg.get("domain.cfEmail")}</th>
                        <th style="width: 120px;">${msg.get("openBoot.status")}</th>
                        <th style="width: 100px;">${msg.get("tenant.mgrAction")}</th>
                    </tr>
                    </thead>
                    <tbody id="notificationRecipientsTableBody">
                    <tr>
                        <td colspan="4" class="text-center">
                            <span class="loading-spinner"></span>
                            ${msg.get("common.loading")}
                        </td>
                    </tr>
                    </tbody>
                </table>
            </div>

            <!-- 统计信息 -->
            <div id="notificationStats" style="margin-top: 15px; padding: 12px; background-color: var(--hover-bg); border-radius: 4px;">
                <div style="display: flex; align-items: center; gap: 15px; font-size: 13px; color: var(--text-secondary);">
                    <span><strong id="totalRecipients">0</strong> ${msg.get("tenant.mgrReceive")}</span>
                    <span id="domainStats"></span>
                </div>
            </div>
        </div>

        <!-- mfa管理 -->
        <div id="mfaTab" class="tab-content" style="display: none;">
            <div class="btn-group" style="margin-bottom: 15px;">
                <button class="btn btn-warning btn-icon" title="${msg.get("tenant.resetMfa")}" onclick="resetMfa()">
                    <i class="fas fa-key"></i>
                    ${msg.get("tenant.resetMfa")}
                </button>
                <button class="btn btn-success" onclick="enableEmailMFA()" id="enableMfaBtn">
                    <i class="fas fa-envelope"></i>
                    ${msg.get("tenant.startEmailMfa")}
                </button>
                <button class="btn btn-danger" onclick="disableEmailMFA()" id="disableMfaBtn">
                    <i class="fas fa-envelope-open"></i>
                    ${msg.get("tenant.closeEmailMfa")}
                </button>
                <button class="btn btn-primary" onclick="refreshMfaStatus()">
                    <i class="fas fa-sync"></i>
                    ${msg.get("vps.refresh")}
                </button>
            </div>

            <!-- MFA状态显示区域 -->
            <div id="mfaStatusSection" style="margin-bottom: 20px; padding: 15px; background-color: var(--hover-bg); border-radius: 4px;">
                <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 10px;">
                    <i class="fas fa-info-circle" style="color: var(--accent-blue);"></i>
                    <span style="font-weight: 500; color: var(--text-primary);">${msg.get("tenant.mfaStatus")}</span>
                </div>
                <div id="mfaStatusContent">
                    <div style="text-align: center; padding: 20px;">
                        <span class="loading-spinner"></span>
                        <span style="margin-left: 10px;">${msg.get("tenant.mfaLoading")}</span>
                    </div>
                </div>
            </div>

            <!-- MFA配置说明 -->
            <#--<div style="margin-top: 15px; padding: 12px; background-color: rgba(33, 150, 243, 0.1); border-radius: 4px;">
                <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 8px;">
                    <i class="fas fa-lightbulb" style="color: var(--accent-blue);"></i>
                    <span style="font-weight: 500; color: var(--accent-blue);">功能说明</span>
                </div>
                <ul style="margin: 0; padding-left: 20px; color: var(--text-secondary); font-size: 12px;">
                    <li>启用：为租户开启邮箱多因子认证功能</li>
                    <li>关闭：禁用租户的邮箱多因子认证功能</li>
                    <li>操作将应用于当前租户下的所有用户</li>
                    <li>建议在生产环境中启用MFA以提高安全性</li>
                </ul>
            </div>-->
        </div>
    </div>
</div>
<!-- 检测结果模态框 -->
<div id="accountCheckModal" class="modal-overlay" style="display: none;">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("tenant.accountStatusRes")}</h3>
        </div>
        <div class="modal-body">
            <p id="accountCheckStatus">${msg.get("tenant.accountStatusLoading")}</p>
            <div id="accountCheckResult" style="display: none;">
                <p>${msg.get("tenant.accountTotal")}：<span id="totalAccounts"></span></p>
                <p>${msg.get("tenant.activeAccountTotal")}：<span id="activeAccounts"></span></p>
                <p>${msg.get("tenant.failAccountTotal")}：<span id="inactiveAccounts"></span></p>
                <h4>${msg.get("tenant.failAccountList")}：</h4>
                <ul id="inactiveAccountList"></ul>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-secondary" onclick="closeAccountCheckModal()">${msg.get("memo.btn.close")}</button>
        </div>
    </div>
</div>

<!-- 引导卷管理模态框 -->
<div id="bootVolumesModal" class="modal-overlay">
    <div class="modal-container boot-volumes-modal">
        <div class="modal-header">
            <h3 class="modal-title" id="modalTitle">${msg.get("tenant.volumeMgr")}</h3>
            <button class="close-btn" onclick="closeModal('bootVolumesModal')">&times;</button>
        </div>
        <div class="modal-content">
            <div class="loading-container" id="bootVolumesLoading">
                <span class="loading-spinner"></span>
                <span class="loading-text">${msg.get("tenant.volumeMgrLoad")}</span>
            </div>
            <div class="table-responsive">
                <table class="table table-compact">
                    <thead>
                    <tr>
                        <th>${msg.get("tenant.insName")}</th>
                        <th>${msg.get("tenant.volumeName")}</th>
                        <th>${msg.get("tenant.volumeSize")} (GB)</th>
                        <th>VPUs</th>
                        <th>${msg.get("tenant.mgrAction")}</th>
                    </tr>
                    </thead>
                    <tbody id="bootVolumesTable">
                    <!-- 数据加载时插入 -->
                    </tbody>
                </table>
            </div>
        </div>
    </div>
</div>

<!-- 流量预警模态框 -->
<div id="trafficAlertModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("tenant.trafficAlert")}</h3>
        </div>
        <div class="modal-content">
            <!-- 添加启用流量统计开关 -->
            <div class="form-group" style="margin-bottom: 15px;">
                <div style="display: flex; align-items: center; gap: 8px;">
                    <input type="checkbox" id="enableTrafficStats" style="width: auto;">
                    <label>${msg.get("tenant.activeTraffic")}</label>
                </div>
                <small style="color: var(--text-secondary);">${msg.get("tenant.activeTrafficNotify")}</small>
            </div>

            <div class="form-group">
                <label>${msg.get("tenant.activeTrafficLimit")} (GB) <span style="color:var(--accent-red);">*</span></label>
                <div class="input-group">
                    <input type="number" id="alertThreshold" min="1" class="form-control" style="width: 100%; padding: 8px; border: 1px solid var(--card-border); border-radius: 4px;">
                </div>
                <small style="color: var(--text-secondary);">${msg.get("tenant.activeTrafficMothLimit")}</small>
            </div>

            <div class="form-group" style="margin-top: 15px;">
                <div style="display: flex; align-items: center; gap: 8px;">
                    <input type="checkbox" id="autoShutdown" style="width: auto;">
                    <label for="autoShutdown">${msg.get("tenant.activeAutoStopInstance")}</label>
                </div>
                <small style="color: var(--text-secondary);">${msg.get("tenant.activeAutoStopInstanceDes")}</small>
            </div>

            <#--<div class="form-group" style="margin-top: 15px;">
                <label>通知邮箱 <span style="color:var(--accent-red);">*</span></label>
                <input type="email" id="notificationEmail" class="form-control" style="width: 100%; padding: 8px; border: 1px solid var(--card-border); border-radius: 4px;">
                <small style="color: var(--text-secondary);">用于接收预警通知的邮箱地址</small>
            </div>-->

            <div class="form-actions" style="margin-top: 20px; display: flex; justify-content: flex-end; gap: 10px;">
                <button class="btn btn-success" onclick="saveTrafficAlert()">${msg.get("common.save")}</button>
                <button class="btn btn-danger" onclick="closeTrafficAlertModal()">${msg.get("common.cancel")}</button>
            </div>
        </div>
    </div>
</div>

<!-- 账号详情模态框 -->
<div id="accountDetailModal" class="modal-overlay">
    <div class="modal-container account-detail-modal">
        <div class="modal-header">
            <h3 class="modal-title">
                <i class="fas fa-user-circle"></i>
                ${msg.get("tenant.accountDes")}
            </h3>
            <button class="close-btn" onclick="closeAccountDetailModal()">&times;</button>
        </div>
        <div class="modal-content">
            <div id="accountDetailContent" class="simple-detail-content">
                <div class="detail-item">
                    <span class="detail-label">${msg.get("tenant.type")}：</span>
                    <span class="detail-value" id="accountTypeAndPlan">-</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">${msg.get("tenant.accountRegTime")}：</span>
                    <span class="detail-value" id="registerTime">-</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">${msg.get("tenant.accountSubNo")}：</span>
                    <span class="detail-value" id="subscriptionPlanNumber">-</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">${msg.get("domain.cfEmail")}：</span>
                    <span class="detail-value" id="emailAddress">-</span>
                </div>
                <div class="detail-item">
                    <span class="detail-label">${msg.get("tenant.accountRegAddress")}：</span>
                    <span class="detail-value" id="fullAddress">-</span>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- 租户密码策略设置模态框 -->
<div id="tenantPasswordPolicyModal" class="modal-overlay">
    <div class="modal-container" style="max-width: 500px;">
        <div class="modal-header">
            <h3 class="modal-title">
                <i class="fas fa-key"></i>
                ${msg.get("tenant.passPolicyConfig")}
            </h3>
            <button class="close-btn" onclick="closeTenantPasswordPolicyModal()">&times;</button>
        </div>
        <div class="modal-content">
            <div class="form-group" style="margin-bottom: 20px;">
                <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 15px;">
                    <input type="checkbox" id="enableTenantPasswordExpiry" style="width: auto;">
                    <label for="enableTenantPasswordExpiry" style="margin: 0; cursor: pointer;">
                        ${msg.get("tenant.activePassPolicy")}
                    </label>
                </div>
                <small style="color: var(--text-secondary); display: block; margin-left: 26px;">
                    ${msg.get("tenant.activePassPolicyDes")}
                </small>
            </div>

            <div id="tenantExpiryDaysSection" class="form-group" style="display: none;">
                <label for="tenantPasswordExpiryDays">${msg.get("tenant.passExoDay")}</label>
                <input type="number" id="tenantPasswordExpiryDays" min="1" max="365" value="120"
                       class="form-control" style="width: 100%; padding: 8px; border: 1px solid var(--card-border); border-radius: 4px;">
                <small style="color: var(--text-secondary); display: block; margin-top: 5px;">
                    ${msg.get("tenant.passExoDayDefault")}
                </small>
            </div>

            <div style="margin: 20px 0; padding: 15px; background-color: rgba(33, 150, 243, 0.1); border-radius: 4px;">
                <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 8px;">
                    <i class="fas fa-info-circle" style="color: var(--accent-blue);"></i>
                    <span style="font-weight: 500; color: var(--accent-blue);">${msg.get("tenant.passDes")}</span>
                </div>
                <ul style="margin: 0; padding-left: 20px; color: var(--text-secondary); font-size: 12px;">
                    <li>${msg.get("tenant.passDes1")}</li>
                    <li>${msg.get("tenant.passDes2")}</li>
                    <li>${msg.get("tenant.passDes3")}</li>
                    <li>${msg.get("tenant.passDes4")}</li>
                </ul>
            </div>

            <div class="form-actions" style="margin-top: 30px; display: flex; justify-content: flex-end; gap: 10px;">
                <button class="btn btn-success" onclick="saveTenantPasswordPolicy()">
                    <i class="fas fa-save"></i>
                    ${msg.get("common.save")}
                </button>
                <button class="btn btn-secondary" onclick="closeTenantPasswordPolicyModal()">
                    <i class="fas fa-times"></i>
                    ${msg.get("common.cancel")}
                </button>
            </div>
        </div>
    </div>
</div>

<div id="emailServiceModal" class="modal-overlay">
    <div class="modal-container" style="max-width: 500px;">
        <div class="modal-header">
            <h3 class="modal-title">
                <i class="fas fa-envelope"></i>
                ${msg.get("tenant.startEmailServer")}
            </h3>
            <button class="close-btn" onclick="closeEmailServiceModal()">&times;</button>
        </div>
        <div class="modal-content">
            <form class="email-service-form">
                <div class="form-group">
                    <label for="emailDomainInput">
                        ${msg.get("tenant.emailDomain")}
                        <span style="color:var(--accent-red);">*</span>
                        <i class="fas fa-info-circle info-icon"
                           onclick="toggleEmailInfo()"
                           title="${msg.get("tenant.emailDomainDes")}"
                           style="color: var(--accent-blue); cursor: pointer; margin-left: 8px;">
                        </i>
                    </label>
                    <input type="text"
                           id="emailDomainInput"
                           class="form-control"
                           placeholder=" example.com"
                           maxlength="100"
                           required>

                    <!-- 说明信息，默认隐藏 -->
                    <div id="emailInfoPanel"
                         style="display: none; margin-top: 15px; padding: 15px; background: var(--hover-bg); border-radius: 4px; border-left: 4px solid var(--accent-blue);">
                        <div style="font-size: 14px; line-height: 1.5; color: var(--text-secondary);">
                            <div style="margin-bottom: 8px;">
                                <i class="fas fa-check" style="color: var(--accent-green); margin-right: 8px;"></i>
                                ${msg.get("tenant.emailDomainDes1")}
                            </div>
                            <div style="margin-bottom: 8px;">
                                <i class="fas fa-check" style="color: var(--accent-green); margin-right: 8px;"></i>
                                ${msg.get("tenant.emailDomainDes2")}
                            </div>
                            <div>
                                <i class="fas fa-check" style="color: var(--accent-green); margin-right: 8px;"></i>
                                ${msg.get("tenant.emailDomainDes3")}
                            </div>
                        </div>
                    </div>
                </div>

                <div class="form-actions">
                    <button type="button" id="emailResetBtn" class="btn btn-warning"
                            style="display: none;" onclick="resetEmailEditMode()">
                        <i class="fas fa-edit"></i> ${msg.get("common.reset")}
                    </button>
                    <button type="button" class="btn btn-success" onclick="confirmEnableEmailService()">
                        <i class="fas fa-envelope"></i>
                        ${msg.get("tenant.startEmailServer")}
                    </button>
                    <button type="button" class="btn btn-secondary" onclick="closeEmailServiceModal()">
                        <i class="fas fa-times"></i>
                        ${msg.get("common.cancel")}
                    </button>
                </div>
            </form>
        </div>
    </div>
</div>

<!-- 审计日志模态框 -->
<div id="auditLogModal" class="modal-overlay">
    <div class="modal-container" style="max-width: 900px;">
        <div class="modal-header" style="display: flex; justify-content: space-between; align-items: center;">
            <h3 class="modal-title"><i class="fas fa-clipboard-list"></i> ${msg.get("tenant.log")}</h3>
            <button class="close-btn" onclick="closeAuditLogModal()">&times;</button>
        </div>

        <div class="modal-body">
            <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 10px;">
                <label style="font-size: 13px; color: var(--text-secondary);">${msg.get("tenant.startTime")}：</label>
                <input type="date" id="startDate" class="form-control" style="width: 150px;">
                <label style="font-size: 13px; color: var(--text-secondary);">${msg.get("tenant.endTime")}：</label>
                <input type="date" id="endDate" class="form-control" style="width: 150px;">
                <button class="btn btn-primary" onclick="searchAuditLogsByDate()">${msg.get("openBoot.search")}</button>
            </div>


            <div id="auditLogTableContainer" style="max-height: 500px; overflow-y: auto; border: 1px solid var(--card-border); border-radius: 4px;">
                <table id="auditLogTable" class="table table-striped" style="width: 100%;">
                    <thead>
                    <tr>
                        <th>${msg.get("tenant.nu")}</th>
                        <th>${msg.get("tenant.userName")}</th>
                        <th>${msg.get("tenant.sourceIp")}</th>
                        <th>${msg.get("tenant.eventType")}</th>
                        <th>${msg.get("tenant.env")}</th>
                        <th>${msg.get("tenant.eventTime")}</th>
                        <th>${msg.get("tenant.reps")}</th>
                    </tr>
                    </thead>
                    <tbody id="auditLogTableBody">
                    <tr><td colspan="7" class="text-center">${msg.get("common.loading")}</td></tr>
                    </tbody>
                </table>
            </div>

            <div style="text-align: center; margin-top: 10px;">
                <button id="loadMoreLogsBtn" class="btn btn-primary" style="display:none;" onclick="loadMoreAuditLogs()">${msg.get("tenant.loadMore")}</button>
            </div>
        </div>
    </div>
</div>

<div id="socialLoginModal" class="modal-overlay">
    <div class="modal-container" style="max-width: 800px;">
        <div class="modal-header">
            <h3 class="modal-title">
                <i class="fas fa-share-alt"></i>
                <span>${msg.get('tenant.socialConfig')}</span>
            </h3>
            <button class="close-btn" onclick="closeSocialLoginModal()">&times;</button>
        </div>

        <div class="modal-content">
            <div id="socialListView">
                <div class="btn-group" style="margin-bottom: 15px;">
                    <button class="btn btn-success" onclick="showAddSocialForm()">
                        <i class="fas fa-plus"></i> ${msg.get('tenant.addSocial')}
                    </button>
                    <button class="btn btn-primary" onclick="refreshSocialList()">
                        <i class="fas fa-sync"></i> ${msg.get('cf.syncList')}
                    </button>
                </div>

                <div class="table-view">
                    <table class="table">
                        <thead>
                        <tr>
                            <th>${msg.get('tenant.socialType')}</th>
                            <th>Client ID</th>
                            <th>${msg.get('tenant.redirectUrl')}</th>
                            <th>${msg.get('tenant.socialStatus')}</th>
                            <th>${msg.get('mfa.table.col_action')}</th>
                        </tr>
                        </thead>
                        <tbody id="socialListBody">
                        </tbody>
                    </table>
                </div>
            </div>

            <div id="socialEditView" style="display: none;">
                <form id="socialForm" onsubmit="return false;">
                    <input type="hidden" id="socialId">

                    <div class="form-group">
                        <label>${msg.get('tenant.socialType')} <span style="color:var(--accent-red);">*</span></label>
                        <select id="socialTypeSelect" class="form-control" data-custom-select>
                        </select>
                        <input type="text" id="socialTypeReadOnly" class="form-control" style="display:none; background:var(--hover-bg);" readonly>
                    </div>

                    <div class="form-group">
                        <label>Client ID <span style="color:var(--accent-red);">*</span></label>
                        <input type="text" id="socialClientId" class="form-control" required
                               style="width: 100%; padding: 8px; border: 1px solid var(--card-border); border-radius: 4px;">
                    </div>

                    <div class="form-group">
                        <label>Client Secret <span style="color:var(--accent-red);">*</span></label>
                        <div style="position: relative;">
                            <input type="text" id="socialClientSecret" class="form-control" required
                                   style="width: 100%; padding: 8px; border: 1px solid var(--card-border); border-radius: 4px;">
                        </div>
                    </div>

                    <div class="form-group" id="redirectUrlGroup" style="display: none;">
                        <label>${msg.get('tenant.redirectUrl')}</label>
                        <div style="display: flex; gap: 5px;">
                            <input type="text" id="socialRedirectUrl" class="form-control" readonly
                                   style="background: var(--hover-bg); color: var(--text-secondary);">
                            <button class="btn btn-info btn-sm" onclick="copyToClipboard('socialRedirectUrl', this)">
                                <i class="fas fa-copy"></i>
                            </button>
                        </div>
                        <small style="color: var(--text-secondary);">${msg.get("tenant.callBackDes")}</small>
                    </div>

                    <div class="form-actions" style="margin-top: 20px; display: flex; justify-content: flex-end; gap: 10px;">
                        <button class="btn btn-success" onclick="saveSocialConfig()">
                            <i class="fas fa-save"></i> ${msg.get('common.save')}
                        </button>
                        <button class="btn btn-secondary" onclick="hideSocialEditForm()">
                            <i class="fas fa-times"></i> ${msg.get('common.cancel')}
                        </button>
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>

<div id="transferModal" class="modal-overlay" style="display: none; align-items: center; justify-content: center; position: fixed; inset: 0; background: rgba(0,0,0,0.5); z-index: 9999;">
    <div class="modal-container" style="background: white; padding: 20px; border-radius: 8px; width: 100%; max-width: 350px;">
        <div class="modal-header" style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px;">
            <h3 style="margin: 0; font-size: 18px;"><i class="fas fa-exchange-alt"></i> ${msg.get("tenant.transfer")}</h3>
            <button onclick="closeTransferModal()" style="border: none; background: none; font-size: 20px; cursor: pointer;">&times;</button>
        </div>
        <div class="modal-content">
            <div style="margin-bottom: 15px; font-size: 13px; color: var(--text-secondary);">${msg.get("tenant.transferDes")}</div>
            <div class="form-group">
                <label style="display: block; margin-bottom: 5px; font-weight: 500;">${msg.get("tenant.transferAmount")}</label>
                <input type="number" id="transferAmount" class="form-control" placeholder="0.00" step="0.01">
            </div>
            <div style="margin-top: 20px; display: flex; justify-content: flex-end; gap: 10px;">
                <button class="btn btn-secondary" onclick="closeTransferModal()">${msg.get("common.cancel")}</button>
                <button class="btn btn-success" onclick="confirmTransfer()">${msg.get("common.save")}</button>
            </div>
        </div>
    </div>
</div>

<div id="transferDetailModal" class="modal-overlay" style="display: none;">
    <div class="modal-container" style="max-width: 350px;">
        <div class="modal-header">
            <h3 class="modal-title"><i class="fas fa-info-circle"></i> ${msg.get("tenant.transferInfo")}</h3>
            <button class="close-btn" onclick="closeModal('transferDetailModal')">&times;</button>
        </div>
        <div class="modal-content" style="padding: 20px; text-align: center;">
            <div style="font-size: 14px; color: var(--text-secondary); margin-bottom: 10px;">${msg.get("tenant.closed")}</div>
            <div style="font-size: 24px; font-weight: 600; color: var(--accent-green);">
                <span id="detailTransferAmount">0.00</span>
            </div>
            <div style="margin-top: 20px;">
                <button class="btn btn-secondary" onclick="closeModal('transferDetailModal')">${msg.get("memo.btn.close")}</button>
            </div>
        </div>
    </div>
</div>


<!-- 配额查看模态框 -->
<div id="quotaModal" class="modal-overlay" onclick="if(event.target===this)closeModal('quotaModal')">
    <div style="background:var(--surface);border:1px solid var(--card-border);border-radius:16px;box-shadow:0 24px 64px rgba(0,0,0,0.28);width:min(860px,96vw);max-height:90vh;display:flex;flex-direction:column;overflow:hidden;">

        <!-- Header -->
        <div style="display:flex;align-items:center;justify-content:space-between;padding:18px 24px;border-bottom:1px solid var(--card-border);background:var(--surface-2,var(--surface));flex-shrink:0;">
            <div style="display:flex;align-items:center;gap:10px;">
                <div style="width:36px;height:36px;border-radius:10px;background:linear-gradient(135deg,#2563eb,#60a5fa);display:flex;align-items:center;justify-content:center;flex-shrink:0;">
                    <i class="fas fa-chart-bar" style="color:#fff;font-size:15px;"></i>
                </div>
                <div>
                    <div style="font-size:15px;font-weight:700;color:var(--text-primary);">账号配额</div>
                    <div style="font-size:11px;color:var(--text-secondary);margin-top:2px;" id="quotaModalSubtitle">选择租户和服务后点击查询</div>
                </div>
            </div>
            <button onclick="closeModal('quotaModal')" style="background:none;border:none;cursor:pointer;width:30px;height:30px;border-radius:8px;display:flex;align-items:center;justify-content:center;color:var(--text-secondary);font-size:20px;line-height:1;" onmouseover="this.style.background='var(--hover-bg)'" onmouseout="this.style.background='none'">&times;</button>
        </div>

        <!-- Filter bar -->
        <div style="display:flex;align-items:flex-end;gap:12px;padding:16px 24px;border-bottom:1px solid var(--card-border);background:var(--surface-2,var(--surface));flex-shrink:0;flex-wrap:wrap;">
            <div style="flex:1;min-width:180px;">
                <div style="font-size:11px;font-weight:600;color:var(--text-secondary);margin-bottom:6px;letter-spacing:.4px;">租户</div>
                <select id="quotaTenantSelect" class="form-control" data-custom-select data-placeholder="选择租户...">
                </select>
            </div>
            <div style="flex:1;min-width:160px;">
                <div style="font-size:11px;font-weight:600;color:var(--text-secondary);margin-bottom:6px;letter-spacing:.4px;">服务类型</div>
                <select id="quotaServiceSelect" class="form-control" data-custom-select>
                    <option value="compute">计算 (Compute)</option>
                    <option value="block-storage">块存储 (Block Storage)</option>
                    <option value="object-storage">对象存储 (Object Storage)</option>
                </select>
            </div>
            <button onclick="doQuotaQuery()" id="quotaQueryBtn" class="btn btn-primary" style="height:38px;padding:0 20px;white-space:nowrap;flex-shrink:0;">
                <i class="fas fa-search"></i> 查询
            </button>
        </div>

        <!-- Results -->
        <div id="quotaContent" style="flex:1;overflow-y:auto;padding:20px 24px;">
            <div style="text-align:center;padding:60px 0;color:var(--text-secondary);">
                <i class="fas fa-chart-bar" style="font-size:36px;display:block;margin-bottom:12px;opacity:0.25;"></i>
                <div style="font-size:13px;">选择租户和服务类型，点击查询</div>
            </div>
        </div>
    </div>
</div>

<!-- 在body结束前引入版本信息模块 -->
<#--<#include "common/version_info.ftl">-->
<script>

    window.I18N = {
        common_noData: "${msg.get('common.noData')?js_string}",
        tenant_icmpNoPort: "${msg.get('tenant.icmpNoPort')?js_string}",
        tenant_portRange: "${msg.get('tenant.portRange')?js_string}",
        tenant_checkFail: "${msg.get('tenant.checkFail')?js_string}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        common_save: "${msg.get('common.save')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        common_delete: "${msg.get('common.delete')?js_string}",
        common_network_error: "${msg.get('common.network.error')?js_string}",
        memo_btn_close: "${msg.get('memo.btn.close')?js_string}",
        login_reset_title: "${msg.get('login.reset.title')?js_string}",
        tenant_deleteUser: "${msg.get('tenant.deleteUser')?js_string}",
        page_prev: "${msg.get('header.page.prev')?js_string}",
        page_next: "${msg.get('header.page.next')?js_string}",
        tenant_loadGroup: "${msg.get('tenant.loadGroup')?js_string}",
        tenant_addUserDefaultRegion: "${msg.get('tenant.addUserDefaultRegion')?js_string}",
        login_username: "${msg.get('login.username')?js_string}",
        login_username_placeholder: "${msg.get('login.username.placeholder')?js_string}",
        login_password: "${msg.get('login.password')?js_string}",
        email_address: "${msg.get('email.address')?js_string}",
        tenant_userGroup: "${msg.get('tenant.userGroup')?js_string}",
        tenant_selectUserGroup: "${msg.get('tenant.selectUserGroup')?js_string}",
        tenant_emailName: "${msg.get('tenant.emailName')?js_string}",
        email_plzAddress: "${msg.get('email.plzAddress')?js_string}",
        common_plzInputGlobalRequired: "${msg.get('common.plzInputGlobalRequired')?js_string}",
        tenant_addUserSuccess: "${msg.get('tenant.addUserSuccess')?js_string}",
        tenant_motice: "${msg.get('tenant.motice')?js_string}",
        tenant_passOnceDes: "${msg.get('tenant.passOnceDes')?js_string}",
        tenant_copyAndSave: "${msg.get('tenant.copyAndSave')?js_string}",
        tenant_copyPass: "${msg.get('tenant.copyPass')?js_string}",
        tenant_copyPass: "${msg.get('tenant.copySucc')?js_string}",
        tenant_rpc: "${msg.get('tenant.resetPassConfirm')?js_string}",
        tenant_loginUser: "${msg.get('tenant.loginUser')?js_string}",
        tenant_cy: "${msg.get('token.action.copy')?js_string}",
        tenant_tp: "${msg.get('tenant.tmpPass')?js_string}",
        tenant_rt: "${msg.get('tenant.resetTime')?js_string}",
        tenant_fls: "${msg.get('tenant.firstLoginSummary')?js_string}",
        tenant_rs: "${msg.get('login.reset.success')?js_string}",
        tenant_kw: "${msg.get('tenant.know')?js_string}",
        tenant_clu: "${msg.get('tenant.confirmLoginUser')?js_string}",
        tenant_ec: "${msg.get('tenant.exportCheck')?js_string}",
        tenant_ecs: "${msg.get('tenant.exportCheckSummary')?js_string}",
        tenant_ecs2: "${msg.get('tenant.exportCheckSummary2')?js_string}",
        tenant_cad: "${msg.get('tenant.cad')?js_string}",
        tenant_rp: "${msg.get('tenant.rp')?js_string}",
        tenant_cg: "${msg.get('tenant.cg')?js_string}",
        tenant_rcg: "${msg.get('tenant.rcg')?js_string}",
        tenant_rcgh: "${msg.get('tenant.rcgh')?js_string}",
        tenant_rcghs: "${msg.get('tenant.rcghs')?js_string}",
        tenant_nac: "${msg.get('tenant.nac')?js_string}",
        tenant_cs: "${msg.get('tenant.cs')?js_string}",
        tenant_ada: "${msg.get('tenant.ada')?js_string}",
        tenant_adt: "${msg.get('tenant.adt')?js_string}",
        tenant_accountTotal: "${msg.get('tenant.accountTotal')?js_string}",
        tenant_activeAccountTotal: "${msg.get('tenant.activeAccountTotal')?js_string}",
        tenant_failAccountTotal: "${msg.get('tenant.failAccountTotal')?js_string}",
        sys_saveUpdate: "${msg.get('sys.saveUpdate')?js_string}",
        tenant_uv: "${msg.get('tenant.uv')?js_string}",
        tenant_un: "${msg.get('tenant.un')?js_string}",
        tenant_triala: "${msg.get('tenant.triala')?js_string}",
        tenant_pa: "${msg.get('tenant.pa')?js_string}",
        tenant_fat: "${msg.get('tenant.fa')?js_string}",
        tenant_crm: "${msg.get('tenant.confirmResetMfa')?js_string}",
        tenant_crrms: "${msg.get('tenant.confirmResetMfaSummary')?js_string}",
        tenant_pev: "${msg.get('tenant.plzEffValue')?js_string}",
        tenant_apn: "${msg.get('tenant.ap')?js_string}",
        tenant_acy: "${msg.get('tenant.acy')?js_string}",
        tenant_acbs: "${msg.get('tenant.acbs')?js_string}",
        tenant_pag: "${msg.get('tenant.pag')?js_string}",
        tenant_unset: "${msg.get('token.info.unset')?js_string}",
        tenant_lppy: "${msg.get('tenant.loadingPassPolicy')?js_string}",
        tenant_nppy: "${msg.get('tenant.noPassPolicy')?js_string}",
        tenant_cds: "${msg.get('tenant.checkDays')?js_string}",
        tenant_nfppy: "${msg.get('tenant.noFindPassPolicy')?js_string}",
        tenant_cppy: "${msg.get('tenant.cuPassPolicy')?js_string}",
        tenant_enabled: "${msg.get('token.status.enabled')?js_string}",
        tenant_stop: "${msg.get('tenant.stop')?js_string}",
        tenant_expireDay: "${msg.get('tenant.expireDay')?js_string}",
        tenant_expireDayForever: "${msg.get('tenant.expireDayForever')?js_string}",
        tenant_policy: "${msg.get('tenant.policy')?js_string}",
        tenant_normal: "${msg.get('tenant.normal')?js_string}",
        email_formatError: "${msg.get('email.formatError')?js_string}",
        delete_title: "${msg.get('mfa.confirm.delete_title')?js_string}",
        tenant_deleteSum: "${msg.get('tenant.deleteSum')?js_string}",
        tenant_confirmStartEmailMfa: "${msg.get('tenant.confirmStartEmailMfa')?js_string}",
        tenant_confirmStopEmailMfa: "${msg.get('tenant.confirmStopEmailMfa')?js_string}",
        tenant_mfaLoading: "${msg.get('tenant.mfaLoading')?js_string}",
        tenant_emailVerify: "${msg.get('tenant.emailVerify')?js_string}",
        tenant_smsVerify: "${msg.get('tenant.smsVerify')?js_string}",
        tenant_mfaVerify: "${msg.get('tenant.mfaVerify')?js_string}",
        tenant_plzEmailDomain: "${msg.get('tenant.plzEmailDomain')?js_string}",
        tenant_domainFormatError: "${msg.get('tenant.domainFormatError')?js_string}",
        tenant_emailSuccess: "${msg.get('tenant.emailSuccess')?js_string}",
        tenant_clickHide: "${msg.get('tenant.clickHide')?js_string}",
        tenant_clickShow: "${msg.get('tenant.clickShow')?js_string}",
        tenant_plzStartTime: "${msg.get('tenant.plzStartTime')?js_string}",
        tenant_plzStartTime1: "${msg.get('tenant.plzStartTime1')?js_string}",
        tenant_plzStartTime2: "${msg.get('tenant.plzStartTime2')?js_string}",
        common_loading: "${msg.get('common.loading')?js_string}",
        openBoot_nDetailData: "${msg.get('openBoot.nDetailData')?js_string}",
        common_edit: "${msg.get('common.edit')?js_string}",
        common_start: "${msg.get('common.start')?js_string}",
        common_stop: "${msg.get('common.stop')?js_string}",
        tenant_editCost: "${msg.get('tenant.accountCost')?js_string}",



        vpn_edit: "${msg.get('vpn.edit')?js_string}",
        tenant_editDefName: "${msg.get('tenant.editDefName')?js_string}",
        openBoot_task: "${msg.get('openBoot.task')?js_string}",
        openBoot_noTask: "${msg.get('openBoot.noTask')?js_string}",
        tenant_yes: "${msg.get('tenant.yes')?js_string}",
        tenant_no2: "${msg.get('tenant.no')?js_string}",
        tenant_simpleMoreRegion: "${msg.get('tenant.simpleMoreRegion')?js_string}",
        tenant_unKnow: "${msg.get('tenant.unKnow')?js_string}",
        tenant_accountDetail: "${msg.get('tenant.accountDetail')?js_string}",
        tenant_computer: "${msg.get('tenant.computer')?js_string}",
        tenant_active: "${msg.get('tenant.active')?js_string}",
        tenant_inactive: "${msg.get('tenant.inactive')?js_string}",
        tenant_ai: "${msg.get('tenant.ai')?js_string}",
        detail_openBoot: "${msg.get('detail.openBoot')?js_string}",
        tenant_update: "${msg.get('tenant.update')?js_string}",
        tenant_detail: "${msg.get('tenant.detail')?js_string}",
        tenant_regionSub: "${msg.get('tenant.regionSub')?js_string}",
        tenant_user: "${msg.get('tenant.user')?js_string}",
        tenant_traffic: "${msg.get('tenant.traffic')?js_string}",
        tenant_trafficSearch: "${msg.get('tenant.trafficSearch')?js_string}",
        tenant_log: "${msg.get('tenant.log')?js_string}",
        tenant_cost: "${msg.get('tenant.cost')?js_string}",
        tenant_export: "${msg.get('tenant.export')?js_string}",
        tenant_emailServer: "${msg.get('tenant.emailServer')?js_string}",
        tenant_socialLogin: "${msg.get('tenant.socialLogin')?js_string}",
        tenant_deleteTenant: "${msg.get('tenant.deleteTenant')?js_string}",
        tenant_detailAccount: "${msg.get('tenant.detailAccount')?js_string}",
        tenant_unsupported: "—"
    }

    /* ═══════════════════════════════════════════════
       AJAX pagination for tenant list
    ═══════════════════════════════════════════════ */
    var _tlCurrentPage = ${currentPage};
    var _tlCurrentSize = ${size};
    var _tlCurrentKeyword = '${(keyword!'')?js_string}';
    var _tlCurrentCloudType = ${cloudType!1};
    var _tlAjaxLoading = false;

    function tlEsc(str) {
        if (str == null) return '';
        return String(str)
            .replace(/&/g,'&amp;')
            .replace(/</g,'&lt;')
            .replace(/>/g,'&gt;')
            .replace(/"/g,'&quot;')
            .replace(/'/g,'&#39;');
    }

    function tlMaskName(name) {
        if (!name) return '';
        if (name.length > 2) return name.charAt(0) + '***' + name.charAt(name.length - 1);
        return '***';
    }

    // 汉字计2个字符，超过 maxVisualLen 时截断并加省略号
    function tlTruncateName(str, maxVisualLen) {
        if (!str) return '';
        var len = 0;
        var i = 0;
        for (; i < str.length; i++) {
            len += str.charCodeAt(i) > 0x7F ? 2 : 1;
            if (len > maxVisualLen) break;
        }
        return i < str.length ? str.slice(0, i) + '...' : str;
    }

    function tlRenderRows(tenants, currentPage, pageSize) {
        var i18n = window.I18N;
        if (!tenants || tenants.length === 0) {
            return '<tr><td colspan="13" style="text-align:center;padding:40px;color:var(--text-secondary);">' + tlEsc(i18n.common_noData) + '</td></tr>';
        }
        var html = '';
        tenants.forEach(function(t, idx) {
            var seqNo = currentPage * pageSize + idx + 1;
            var tn = t.tenancyName || '';
            var maskedTn = tlMaskName(tn);
            var dn = t.defName || '';
            var isActive = t.active !== false && t.isActive !== false;
            var hasChildren = t.hasChildren === true;
            var openBootFlag = t.openBootFlag === true;
            var cloudType = t.cloudType || 1;
            var transferred = (t.transferStatus || 0) === 1;
            var supportAI = (t.supportAI || 0) === 1;
            var createdAt = t.createdAtStr || t.createdAt || '';
            var accountTypeName = t.accountTypeName || '';
            var accountType = t.accountType || 'unknown';
            var emailEnable = t.emailEnable || 0;
            var activeDays = t.activeDays || '0';
            var accountCost = t.accountCost || '';
            var region = t.region || '';
            var id = t.idStr || String(t.id);

            // Status badge (openBootFlag)
            var openBootBadge = openBootFlag
                ? '<span class="status-badge status-running"><i class="fas fa-circle-notch fa-spin" style="font-size:10px;"></i> ' + tlEsc(i18n.openBoot_task) + '</span>'
                : '<span class="status-badge status-idle">' + tlEsc(i18n.openBoot_noTask) + '</span>';

            // hasChildren badge
            var childrenBadge = hasChildren
                ? '<span class="home-region-badge is-home">' + tlEsc(i18n.tenant_yes) + '</span>'
                : '<span class="home-region-badge not-home">' + tlEsc(i18n.tenant_no2) + '</span>';

            // Account type cell
            var accountTypeCell = '';
            if (accountTypeName && accountTypeName !== i18n.tenant_unKnow) {
                var atClass = 'account-type-' + accountType.toLowerCase().replace(/_/g, '-');
                accountTypeCell = '<a href="javascript:void(0);" class="account-type-link ' + atClass + '" onclick="showAccountDetail(\'' + id + '\')" title="' + tlEsc(i18n.tenant_accountDetail) + '">' + tlEsc(accountTypeName) + '</a>';
            } else {
                accountTypeCell = '<span class="account-type-text">' + tlEsc(hasChildren ? i18n.tenant_simpleMoreRegion : i18n.tenant_unKnow) + '</span>';
            }

            // Boot button
            var bootCell = cloudType === 1
                ? '<a href="/tenants/bootPage?tenantId=' + id + '" class="btn-boot"><i class="fas fa-rocket"></i> ' + tlEsc(i18n.tenant_computer) + '</a>'
                : '<span class="text-unsupported">' + tlEsc(i18n.tenant_unsupported) + '</span>';

            // isActive badge
            var activeBadge = isActive
                ? '<span class="status-badge status-running" style="font-size:11px;"><i class="fas fa-check-circle" style="font-size:10px;"></i> ' + tlEsc(i18n.tenant_active) + '</span>'
                : '<span class="status-badge status-idle" style="font-size:11px;"><i class="fas fa-ban" style="font-size:10px;"></i> ' + tlEsc(i18n.tenant_inactive) + '</span>';

            // Dropdown items
            var dropdownItems = '';
            if (cloudType === 1) {
                if (!transferred) {
                    if (supportAI) {
                        dropdownItems += '<a href="/ai/chat?tenantId=' + id + '" class="dropdown-item" title="' + tlEsc(i18n.tenant_ai) + '"><i class="fas fa-cogs"></i><span>' + tlEsc(i18n.tenant_ai) + '</span></a>';
                    }
                    dropdownItems += '<a href="/tenants/bootPage?tenantId=' + id + '" class="dropdown-item"><i class="fas fa-plus"></i><span>' + tlEsc(i18n.detail_openBoot) + '</span></a>';
                    dropdownItems += '<button class="dropdown-item" onclick="handleUpdateAccountDetail(\'' + id + '\')" title="' + tlEsc(i18n.tenant_update) + '"><i class="fas fa-redo"></i><span>' + tlEsc(i18n.tenant_update) + '</span></button>';
                    dropdownItems += '<a href="/tenants/regionList?tenantId=' + id + '" class="dropdown-item" title="' + tlEsc(i18n.tenant_detail) + '"><i class="fas fa-info-circle"></i><span>' + tlEsc(i18n.tenant_detail) + '</span></a>';
                    dropdownItems += '<a href="/tenants/regionSubList?tenantId=' + id + '" class="dropdown-item" title="' + tlEsc(i18n.tenant_regionSub) + '"><i class="fas fa-globe"></i><span>' + tlEsc(i18n.tenant_regionSub) + '</span></a>';
                    dropdownItems += '<button class="dropdown-item" onclick="showUserManagement(\'' + id + '\')" title="' + tlEsc(i18n.tenant_user) + '"><i class="fas fa-users"></i><span>' + tlEsc(i18n.tenant_user) + '</span></button>';
                    dropdownItems += '<button class="dropdown-item" onclick="showTrafficAlert(\'' + id + '\')" title="' + tlEsc(i18n.tenant_traffic) + '"><i class="fas fa-bell"></i><span>' + tlEsc(i18n.tenant_traffic) + '</span></button>';
                    dropdownItems += '<a href="/monitor/homePage?tenantId=' + id + '" class="dropdown-item" title="' + tlEsc(i18n.tenant_trafficSearch) + '"><i class="fas fa-chart-bar"></i><span>' + tlEsc(i18n.tenant_trafficSearch) + '</span></a>';
                    dropdownItems += '<button class="dropdown-item" onclick="showAuditLogs(\'' + id + '\')" title="' + tlEsc(i18n.tenant_log) + '"><i class="fas fa-clipboard-list"></i> ' + tlEsc(i18n.tenant_log) + '</button>';
                    dropdownItems += '<a href="/cost/costPage?tenantId=' + id + '" class="dropdown-item" title="' + tlEsc(i18n.tenant_cost) + '"><i class="fas fa-info-circle"></i><span>' + tlEsc(i18n.tenant_cost) + '</span></a>';
                    dropdownItems += '<button class="dropdown-item" onclick="exportDataByTenant(\'' + id + '\')" title="' + tlEsc(i18n.tenant_export) + '"><i class="fas fa-download"></i> ' + tlEsc(i18n.tenant_export) + '</button>';
                    dropdownItems += '<button class="dropdown-item" onclick="handleEmailServiceAction(\'' + id + '\',' + emailEnable + ')" title="' + tlEsc(i18n.tenant_emailServer) + '"><i class="fas fa-envelope"></i><span>' + tlEsc(i18n.tenant_emailServer) + '</span></button>';
                    dropdownItems += '<button class="dropdown-item" onclick="showSocialLoginModal(\'' + id + '\',\'' + cloudType + '\')" title="' + tlEsc(i18n.tenant_socialLogin) + '"><i class="fas fa-share-alt"></i><span>' + tlEsc(i18n.tenant_socialLogin) + '</span></button>';
                    dropdownItems += '<button class="dropdown-item" onclick="showQuotaModal(\'' + id + '\')" title="查看配额"><i class="fas fa-chart-bar" style="color:#2563eb;"></i><span>查看配额</span></button>';
                }
                dropdownItems += '<button class="dropdown-item" onclick="handleDelete(\'' + id + '\')" title="' + tlEsc(i18n.tenant_deleteTenant) + '"><i class="fas fa-trash"></i><span>' + tlEsc(i18n.tenant_deleteTenant) + '</span></button>';
            } else if (cloudType === 2) {
                dropdownItems += '<a href="/tenants/regionList?tenantId=' + id + '" class="dropdown-item" title="' + tlEsc(i18n.tenant_detailAccount) + '"><i class="fas fa-info-circle"></i><span>' + tlEsc(i18n.tenant_detailAccount) + '</span></a>';
                dropdownItems += '<button class="dropdown-item" onclick="handleDelete(\'' + id + '\')" title="' + tlEsc(i18n.tenant_deleteTenant) + '"><i class="fas fa-trash"></i><span>' + tlEsc(i18n.tenant_deleteTenant) + '</span></button>';
            }

            html += '<tr class="parent-row" data-id="' + id + '">' +
                '<td class="col-center" style="color:var(--text-secondary);font-size:12px;">' + seqNo + '</td>' +
                '<td class="col-name"><span class="name-spoiler is-hidden" onclick="toggleSpoiler(this)" title="' + tlEsc(tn) + '"><span class="name-masked">' + tlEsc(maskedTn) + '</span><span class="name-full">' + tlEsc(tn) + '</span></span></td>' +
                '<td><a class="cell-edit-link defname-cell" href="javascript:void(0);" onclick="editCustomName(\'' + id + '\',\'' + tlEsc(dn).replace(/'/g,"\\'") + '\')" id="defName-' + id + '" data-fullname="' + tlEsc(dn) + '" title="' + tlEsc(dn) + '">' + tlEsc(tlTruncateName(dn, 14)) + '</a></td>' +
                '<td><a class="cell-edit-link" href="javascript:void(0);" onclick="editAccountCost(\'' + id + '\',\'' + tlEsc(accountCost).replace(/'/g,"\\'") + '\')" id="cost-' + id + '" title="' + tlEsc(i18n.tenant_editCost) + '">' + tlEsc(accountCost) + '</a></td>' +
                '<td class="col-center"><span class="days-chip">' + tlEsc(activeDays) + '</span></td>' +
                '<td>' + openBootBadge + '</td>' +
                '<td class="col-code"><span class="truncate" onclick="toggleText(this)" data-fulltext="' + tlEsc(region) + '">' + tlEsc(region) + '</span></td>' +
                '<td>' + childrenBadge + '</td>' +
                '<td>' + accountTypeCell + '</td>' +
                '<td class="col-center">' + bootCell + '</td>' +
                '<td class="col-secondary" style="white-space:nowrap;font-size:12px;">' + tlEsc(createdAt) + '</td>' +
                '<td class="col-center">' + activeBadge + '</td>' +
                '<td class="actions-cell"><div class="dropdown"><button class="dropdown-toggle btn" onclick="handleDynamicToggle(this, event)"><i class="fas fa-ellipsis-h"></i></button><div class="dropdown-panel">' + dropdownItems + '</div></div></td>' +
            '</tr>';
        });
        return html;
    }

    function tlUpdatePaginationUI(currentPage, totalPages) {
        document.querySelectorAll('.page-btn').forEach(function(btn) {
            var onclick = btn.getAttribute('onclick') || '';
            var m = onclick.match(/gotoPage\((\d+)/);
            if (m) btn.classList.toggle('active', parseInt(m[1]) === currentPage);
        });
        document.querySelectorAll('.prev-btn').forEach(function(b) {
            b.disabled = currentPage <= 0;
            b.classList.toggle('disabled', currentPage <= 0);
            b.setAttribute('onclick', 'gotoPage(' + (currentPage - 1) + ', \'/tenants/list\')');
        });
        document.querySelectorAll('.next-btn').forEach(function(b) {
            b.disabled = currentPage >= totalPages - 1;
            b.classList.toggle('disabled', currentPage >= totalPages - 1);
            b.setAttribute('onclick', 'gotoPage(' + (currentPage + 1) + ', \'/tenants/list\')');
        });
        var jumpInput = document.getElementById('jumpPageInput');
        if (jumpInput) jumpInput.value = currentPage + 1;
        var pageInfoEl = document.querySelector('.page-info');
        if (pageInfoEl) {
            var strongs = pageInfoEl.querySelectorAll('strong');
            if (strongs[0]) strongs[0].textContent = currentPage + 1;
            if (strongs[1]) strongs[1].textContent = totalPages;
        }
        var totalEl = document.querySelector('.total-text strong');
        if (totalEl) { /* kept from server render */ }
    }

    function tlLoadPage(page, size, keyword, cloudType) {
        if (_tlAjaxLoading) return;
        _tlAjaxLoading = true;
        var tbody = document.getElementById('tenant-table-body');
        if (tbody) tbody.style.opacity = '0.4';

        var params = new URLSearchParams();
        params.set('page', page);
        params.set('size', size);
        params.set('cloudType', cloudType || _tlCurrentCloudType);
        if (keyword) params.set('keyword', keyword);

        var csrfToken = document.querySelector('meta[name="_csrf"]').getAttribute('content');
        fetch('/tenants/list/json?' + params.toString(), {
            headers: { 'X-CSRF-TOKEN': csrfToken }
        })
        .then(function(r) { return r.json(); })
        .then(function(data) {
            _tlCurrentPage = data.currentPage;
            _tlCurrentSize = data.size;
            _tlCurrentKeyword = keyword || '';

            if (tbody) {
                tbody.innerHTML = tlRenderRows(data.content, data.currentPage, data.size);
                tbody.style.opacity = '1';
            }
            // 将本页租户数据合并到 tenantsData，使 showAccountDetail 可查到
            if (data.content) {
                data.content.forEach(function(t) {
                    var key = t.idStr || String(t.id);
                    window.tenantsData[key] = t;
                });
            }
            tlUpdatePaginationUI(data.currentPage, data.totalPages);

            // Sync URL
            var newParams = new URLSearchParams();
            newParams.set('page', data.currentPage);
            newParams.set('size', data.size);
            newParams.set('cloudType', _tlCurrentCloudType);
            if (_tlCurrentKeyword) newParams.set('keyword', _tlCurrentKeyword);
            history.pushState({}, '', '/tenants/list?' + newParams.toString());

            // Reset spoiler state
            if (typeof _allTenantSpoilersVisible !== 'undefined') {
                _allTenantSpoilersVisible = false;
                var icon = document.getElementById('spoilerToggleIcon');
                if (icon) { icon.className = 'fas fa-eye'; }
            }
        })
        .catch(function(e) {
            console.error('租户列表加载失败', e);
            if (tbody) tbody.style.opacity = '1';
        })
        .finally(function() { _tlAjaxLoading = false; });
    }

    // Override pagination.ftl functions
    function gotoPage(targetPage, url) {
        var size = parseInt(document.getElementById('pageSizeSelect').value) || _tlCurrentSize;
        if (targetPage < 0) return;
        tlLoadPage(targetPage, size, _tlCurrentKeyword, _tlCurrentCloudType);
    }

    function jumpToPage(url) {
        var input = document.getElementById('jumpPageInput');
        var targetPage = parseInt(input.value) - 1;
        var size = parseInt(document.getElementById('pageSizeSelect').value) || _tlCurrentSize;
        if (isNaN(targetPage) || targetPage < 0) return;
        tlLoadPage(targetPage, size, _tlCurrentKeyword, _tlCurrentCloudType);
    }

    function changePageSize(newSize, url, currentPage) {
        document.getElementById('pageSizeSelect').value = newSize;
        var label = document.getElementById('pageSizeBtnLabel');
        if (label) label.textContent = newSize;
        _tlCurrentSize = newSize;
        tlLoadPage(0, newSize, _tlCurrentKeyword, _tlCurrentCloudType);
    }

    // 将租户数据转换为JavaScript对象
    window.tenantsData = {
        <#list tenants as tenant>
        "${tenant.id?c}": {
            id: "${tenant.id?c}",
            idStr: "${tenant.id?c}",
            tenancyName: "${tenant.tenancyName!''}",
            userName: "${tenant.userName!''}",
            accountTypeName: "${tenant.accountTypeName!''}",
            accountType: "${tenant.accountType!''}",
            createdAtStr: "${tenant.createdAtStr!''}",
            <#if tenant.registerDetail??>
            registerDetail: {
                accountType: "${tenant.registerDetail.accountType!''}",
                planType: "${tenant.registerDetail.planType!''}",
                upgradeState: "${tenant.registerDetail.upgradeState!''}",
                registerTime: "${tenant.registerDetail.registerTime?string("yyyy-MM-dd HH:mm:ss")!''}",
                firstName: "${tenant.registerDetail.firstName!''}",
                lastName: "${tenant.registerDetail.lastName!''}",
                emailAddress: "${tenant.registerDetail.emailAddress!''}",
                subscriptionPlanNumber: "${tenant.registerDetail.subscriptionPlanNumber!''}",
                country: "${tenant.registerDetail.country!''}",
                city: "${tenant.registerDetail.city!''}",
                line1: "${tenant.registerDetail.line1!''}",
                postalCode: "${tenant.registerDetail.postalCode!''}"
            }
            <#else>
            registerDetail: null
            </#if>
        }<#if tenant_has_next>,</#if>
        </#list>
    };

    // 初始FTL渲染行：对自定义名称列应用截断规则
    document.addEventListener('DOMContentLoaded', function() {
        document.querySelectorAll('a.defname-cell[data-fullname]').forEach(function(el) {
            var full = el.getAttribute('data-fullname') || '';
            el.textContent = tlTruncateName(full, 14);
        });
    });
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/common/custom-select.js"></script>
<script src="/js/system/tenant_list.js"></script>
</body>
</html>