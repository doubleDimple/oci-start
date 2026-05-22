<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 租户详情</title>
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>(function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">

    <!-- SweetAlert2 CSS -->
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <!-- SweetAlert2 JS -->
    <script src="/js/sweetalert2.min.js"></script>

<#--
    <script src="https://cdn.jsdelivr.net/npm/chart.js" defer></script>
-->

    <link rel="stylesheet" href="/css/app/tenant_region_list.css">
    <link rel="stylesheet" href="/css/common/dropdown-menu.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <script src="/js/common/jquery.min.js"></script>

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
                <span>${msg.get("detail.config")}</span>
            </h1>
            <div class="view-actions">
                <div class="view-toggle">
                    <button class="btn" id="spoilerToggleBtn" onclick="toggleAllSpoilers()" title="${msg.get('tenant.toggleName')}">
                        <i class="fas fa-eye" id="spoilerToggleIcon"></i>
                    </button>
                </div>
                <div class="btn-group">
                    <#--<a href="/tenants/add" class="btn btn-success">
                        <i class="fas fa-plus"></i>
                        <span>添加API</span>
                    </a>-->
                    <#--<button class="btn btn-success" onclick="batchEnableIcmp()">
                        <i class="fas fa-shield-alt"></i>
                        <span>开启ICMP</span>
                    </button>-->
                    <a href="/tenants/addSpeed" class="btn btn-success">
                        <i class="fas fa-bolt"></i>
                        <span>${msg.get("tenant.apiImport")}</span>
                    </a>
                    <!-- 导出数据按钮 -->
                    <#--<a href="javascript:void(0);" class="btn btn-primary" onclick="exportData()">
                        <i class="fas fa-download"></i>
                        <span>导出数据</span>
                    </a>

                    <!-- 导入数据按钮 &ndash;&gt;
                    <a href="javascript:void(0);" class="btn btn-primary" onclick="importData()">
                        <i class="fas fa-upload"></i>
                        <span>导入数据</span>
                    </a>-->
                    <!-- 批量检测按钮 -->
                    <#--<button class="btn btn-primary" onclick="startAccountCheck()">
                        <i class="fas fa-check-circle"></i> 账号批量检测
                    </button>-->
                </div>
            </div>
        </div>

        <!-- Table View -->
        <div class="table-view">
            <table class="table">
                <thead>
                <tr>
                    <th>${msg.get("tenant.nu")}</th>
                    <th>${msg.get("tenant.name")}</th>
                    <th>${msg.get("tenant.volumeName")}</th>
                    <th>${msg.get("tenant.openTask")}</th>
                    <th>${msg.get("aiModel.region")}</th>
                    <#--<th>抢机池</th>-->
                    <th>${msg.get("tenant.homeRegion")}</th>
                    <th>${msg.get("detail.sync")}</th>
                    <th>${msg.get("tenant.mgrcTime")}</th>
                    <th>${msg.get("detail.action")}</th>
                </tr>
                </thead>
                <tbody>
                <#list tenants as tenant>
                    <tr class="parent-row" data-id="${tenant.id?c}">
                        <td>${tenant_index + 1}</td>
                        <#--<td>
                            <#if tenant.hasChildren>
                                <i class="fas fa-caret-right expand-icon" onclick="toggleChildren(this, ${tenant.id?c})"></i>
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
                        <td><span class="truncate" onclick="toggleText(this)" data-fulltext="${tenant.defName!''}">${tenant.defName!''}</span></td>
                        <td>
                            <span class="truncate status-badge ${tenant.openBootFlag?then('status-running', 'status-idle')}"
                                  data-fulltext="${tenant.openBootFlag?then('${msg.get("openBoot.task")}', '${msg.get("openBoot.noTask")}')}">
                                ${tenant.openBootFlag?then('${msg.get("openBoot.task")}', '${msg.get("openBoot.noTask")}')}
                            </span>
                        </td>
                        <#--<td><span class="truncate" onclick="toggleText(this)" data-fulltext="${tenant.region!''}">${tenant.region!''}</span></td>-->
                        <td>
                            <#if tenant.cloudType?? && tenant.cloudType == 1>
                                <a href="/oci/list?tenantId=${tenant.id?c}" class="text-blue-500 hover:text-blue-700">
                                    <span class="truncate" data-fulltext="${tenant.region!''}">${tenant.region!''}</span>
                                </a>
                            <#elseif tenant.cloudType?? && tenant.cloudType == 2>
                                <a href="/other/instances/list?tenantId=${tenant.id?c}" class="text-blue-500 hover:text-blue-700">
                                    <span class="truncate" data-fulltext="${tenant.region!''}">${tenant.region!''}</span>
                                </a>
                            </#if>
                        </td>
                        <#--<td>
                            <#if tenant.openInsFlag?? && tenant.openInsFlag?matches("1")>
                                <a href="/boot/fullBootList?tenantId=${tenant.id?c}" class="text-blue-500 hover:text-blue-700">
                                    <span class="truncate" data-fulltext="${tenant.id!''}">
                                        <i class="fas fa-server text-green-500 mr-1"></i> 查看抢机
                                    </span>
                                </a>
                            <#else>
                                 <#if tenant.cloudType?? && tenant.cloudType == 1>
                                     <a href="/tenants/bootPage?tenantId=${tenant.id?c}" class="text-orange-500 hover:text-orange-700">
                                        <span class="truncate" data-fulltext="${tenant.id!''}">
                                            <i class="fas fa-plus-circle mr-1"></i> 添加抢机配置
                                        </span>
                                     </a>
                                 <#elseif tenant.cloudType?? && tenant.cloudType == 2>
                                     <a href="/tenants/gcpBootPage?tenantId=${tenant.id?c}" class="text-orange-500 hover:text-orange-700">
                                        <span class="truncate" data-fulltext="${tenant.id!''}">
                                            <i class="fas fa-plus-circle mr-1"></i> 添加抢机配置
                                        </span>
                                     </a>
                                 </#if>
                            </#if>
                        </td>-->
                        <td><span class="home-region-badge ${(tenant.isHomeRegion!false)?string('is-home','not-home')}">${(tenant.isHomeRegion!false)?string('${msg.get("tenant.yes")}','${msg.get("tenant.no")}')}</span></td>
                        <td>
                            <span class="status-badge ${(tenant.apiSynced!false)?string('status-running', 'status-offline')}">
                                ${(tenant.apiSynced!false)?string('${msg.get("detail.alreadySync")}', '${msg.get("detail.noSync")}')}
                            </span>
                        </td>
                        <td>${tenant.createdAt}</td>
                        <td class="actions-cell">
                            <div class="dropdown">
                                <!-- 主操作按钮 -->
                                <button class="btn btn-primary btn-icon dropdown-toggle">
                                    <i class="fas fa-ellipsis-h"></i>
                                </button>


                                <!-- 操作面板 -->
                                <div class="dropdown-panel">
                                    <#if tenant.cloudType?? && tenant.cloudType == 1>
                                        <#if tenant.supportAI?? && tenant.supportAI == 1>
                                            <a href="/ai/chat?tenantId=${tenant.id?c}" class="dropdown-item">
                                                <i class="fas fa-robot"></i><span>${msg.get("tenant.ai")}</span>
                                            </a>
                                        </#if>
                                        <button class="dropdown-item" onclick="handleSync('${tenant.id?c}')">
                                            <i class="fas fa-sync"></i><span>${msg.get("detail.sync")}</span>
                                        </button>
                                        <a href="/tenants/bootPage?tenantId=${tenant.id?c}" class="dropdown-item">
                                            <i class="fas fa-plus"></i><span>${msg.get("detail.openBoot")}</span>
                                        </a>
                                        <a href="/boot/fullBootList?tenantId=${tenant.id?c}" class="dropdown-item">
                                            <i class="fas fa-plus"></i><span>${msg.get("detail.findBoot")}</span>
                                        </a>
                                        <button class="dropdown-item" onclick="showBootVolumeManagement('${tenant.id?c}')">
                                            <i class="fas fa-hdd"></i><span>${msg.get("detail.diskDetail")}</span>
                                        </button>
                                        <button class="dropdown-item" onclick="showSecurityRules('${tenant.id?c}')">
                                            <i class="fas fa-shield-alt"></i><span>${msg.get("detail.rule")}</span>
                                        </button>
                                        <a href="/oci/list?tenantId=${tenant.id?c}" class="dropdown-item">
                                            <i class="fas fa-server"></i><span>${msg.get("sidebar.instance.list")}</span>
                                        </a>
                                        <button class="dropdown-item" onclick="showMysqlManagement('${tenant.id?c}')">
                                            <i class="fas fa-database"></i><span>${msg.get("detail.db")}</span>
                                        </button>
                                    <#elseif tenant.cloudType?? && tenant.cloudType == 2>
                                        <a href="/tenants/gcpBootPage?tenantId=${tenant.id?c}" class="dropdown-item">
                                            <i class="fas fa-plus"></i><span>${msg.get("detail.openBoot")}</span>
                                        </a>
                                        <button class="dropdown-item" onclick="handleSync('${tenant.id?c}')">
                                            <i class="fas fa-sync"></i><span>${msg.get("detail.sync")}</span>
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

<!-- 在现有的 modal overlays 部分添加 -->
<div id="securityRulesModal" class="modal-overlay security-rules-modal">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("detail.ruleConfig")}</h3>
        </div>

        <div class="security-rules-tabs">
            <button class="security-rules-tab active" data-tab="ingress">${msg.get("detail.ruleIn")}</button>
            <button class="security-rules-tab" data-tab="egress">${msg.get("detail.ruleOut")}</button>
        </div>

        <div id="rulesLoadingContainer" class="loading-container">
            <span class="loading-spinner"></span>
            <#--<span class="loading-text">正在加载安全规则...</span>-->
        </div>

        <button class="btn btn-success add-rule-btn" onclick="addNewRule()">
            <i class="fas fa-plus"></i>
            ${msg.get("detail.ruleAdd")}
        </button>

        <div id="editRuleForm" class="edit-rule-form" style="display: none;">
            <div class="form-group">
                <label>${msg.get("tecent.protocol")}</label>
                <select id="ruleProtocol">
                    <option value="all">${msg.get("detail.allProtocol")}</option>
                    <option value="tcp">TCP</option>
                    <option value="udp">UDP</option>
                    <option value="icmp">ICMP</option>
                </select>
            </div>
            <div class="form-group">
                <label>${msg.get("detail.source")} <span style="color: var(--accent-red);">*</span></label>
                <input type="text" id="ruleSource" placeholder="0.0.0.0/0" required>
            </div>
            <div class="form-group">
                <label for="rulePorts">${msg.get("tenant.portRange")} <span style="color: var(--accent-red);">*</span></label>
                <input type="text" id="rulePorts" placeholder="80,443 或 80-443">
            </div>
            <div class="form-actions">
                <button class="btn btn-primary" onclick="saveRule()">${msg.get("common.save")}</button>
                <button class="btn btn-danger" onclick="cancelEdit()">${msg.get("common.cancel")}</button>
            </div>
        </div>

        <table class="rules-table">
            <thead>
            <tr>
                <th>id</th>
                <th>${msg.get("detail.ruleType")}</th>
                <th>${msg.get("tecent.protocol")}</th>
                <th>${msg.get("detail.source")}</th>
                <th>${msg.get("tenant.portRange")}</th>
                <th>${msg.get("sub.action")}</th>
            </tr>
            </thead>
            <tbody id="rulesTableBody">
            </tbody>
        </table>
    </div>
</div>

<<#--!-- 添加用户管理模态框 &ndash;&gt;
<div id="userManagementModal" class="modal-overlay">
    <div class="modal-container" style="max-width: 800px;">
        <div class="modal-header">
            <h3 class="modal-title">用户管理</h3>
        </div>

        <div class="btn-group" style="margin-bottom: 15px;">
            <button class="btn btn-success" onclick="showAddUserForm()">
                <i class="fas fa-plus"></i>
                添加用户
            </button>
            <button class="btn btn-primary" onclick="refreshUserList()">
                <i class="fas fa-sync"></i>
                刷新列表
            </button>
        </div>

        <!-- 添加用户表单 &ndash;&gt;
        <div id="addUserForm" class="edit-rule-form" style="display: none;">
            <div class="form-group">
                <label>用户名 <span style="color: var(--accent-red);">*</span></label>
                <input type="text" id="newUsername" placeholder="请输入用户名" required>
            </div>
            <div class="form-group">
                <label>邮箱 <span style="color: var(--accent-red);">*</span></label>
                <input type="email" id="email" placeholder="请输入邮箱" required>
            </div>
            <div class="form-actions">
                <button class="btn btn-primary" onclick="createUser()">创建</button>
                <button class="btn btn-danger" onclick="hideAddUserForm()">取消</button>
            </div>
        </div>

        <!-- 用户列表表格 &ndash;&gt;
        <div class="table-view" style="margin-top: 15px;">
            <table class="table">
                <thead>
                <tr>
                    <th>用户名</th>
                    <th>邮箱</th>
                    <th>账号状态</th>
                    <th>创建时间</th>
                    <th>最后登录时间</th>
                    <th>操作</th>
                </tr>
                </thead>
                <tbody id="userListTableBody">
                <tr>
                    <td colspan="5" class="text-center">
                        <span class="loading-spinner"></span>
                        加载中...
                    </td>
                </tr>
                </tbody>
            </table>
        </div>
    </div>
</div>-->

<!-- 检测结果模态框 -->
<#--<div id="accountCheckModal" class="modal-overlay" style="display: none;">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">账号检测结果</h3>
        </div>
        <div class="modal-body">
            <p id="accountCheckStatus">正在检测，请稍候...</p>
            <div id="accountCheckResult" style="display: none;">
                <p>总账号数量：<span id="totalAccounts"></span></p>
                <p>正常账号数量：<span id="activeAccounts"></span></p>
                <p>异常账号数量：<span id="inactiveAccounts"></span></p>
                <h4>异常账号列表：</h4>
                <ul id="inactiveAccountList"></ul>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-secondary" onclick="closeAccountCheckModal()">关闭</button>
        </div>
    </div>
</div>-->

<!-- 引导卷管理模态框 -->
<div id="bootVolumesModal" class="modal-overlay">
    <div class="modal-container boot-volumes-modal resizable">
        <!-- 拖动手柄 -->
        <div class="resize-handle resize-handle-e" data-direction="e"></div>
        <div class="resize-handle resize-handle-s" data-direction="s"></div>
        <div class="resize-handle resize-handle-se" data-direction="se"></div>

        <div class="modal-header" style="display: flex; align-items: center; justify-content: space-between; border-bottom: 1px solid var(--card-border); padding-bottom: 15px;">
            <h3 class="modal-title" id="modalTitle" style="font-size: 18px; color: var(--text-primary);">
                <i class="fas fa-hdd" style="color: var(--accent-green); margin-right: 10px;"></i>
                ${msg.get("tenant.volumeMgr")}
            </h3>
            <button class="close-btn" onclick="closeModal('bootVolumesModal')" style="background: none; border: none; font-size: 20px; cursor: pointer; color: var(--text-secondary); width: 30px; height: 30px; display: flex; align-items: center; justify-content: center; border-radius: 50%; transition: all 0.2s;">&times;</button>
        </div>
        <div class="modal-content" style="flex: 1; overflow-y: auto; padding: 15px 0;">
            <div class="loading-container" id="bootVolumesLoading" style="display: none; padding: 30px;">
                <span class="loading-spinner"></span>
                <span class="loading-text">${msg.get("tenant.volumeMgrLoad")}</span>
            </div>
            <div class="table-responsive" style="display: none; overflow-x: hidden;">
                <table class="table table-compact" style="width: 100%;">
                    <thead>
                    <tr style="background-color: var(--surface-2);">
                        <th style="padding: 12px 15px; font-weight: 500; color: var(--text-secondary); text-align: left; position: sticky; top: 0; background: var(--surface-2);">${msg.get("tenant.insName")}</th>
                        <th style="padding: 12px 15px; font-weight: 500; color: var(--text-secondary); text-align: left; position: sticky; top: 0; background: var(--surface-2);">${msg.get("tenant.volumeName")}</th>
                        <th style="padding: 12px 15px; font-weight: 500; color: var(--text-secondary); text-align: center; position: sticky; top: 0; background: var(--surface-2);">${msg.get("tenant.volumeSize")} (GB)</th>
                        <th style="padding: 12px 15px; font-weight: 500; color: var(--text-secondary); text-align: center; position: sticky; top: 0; background: var(--surface-2);">VPUs</th>
                        <th style="padding: 12px 15px; font-weight: 500; color: var(--text-secondary); text-align: center; position: sticky; top: 0; background: var(--surface-2);">${msg.get("sub.action")}</th>
                    </tr>
                    </thead>
                    <tbody id="bootVolumesTable">
                    <!-- 数据加载时插入 -->
                    </tbody>
                </table>
            </div>
        </div>
        <div class="modal-footer" style="border-top: 1px solid var(--card-border); padding-top: 15px; display: flex; justify-content: flex-end;">
            <button class="btn btn-primary" onclick="closeModal('bootVolumesModal')" style="background-color: var(--accent-blue); color: white; border: none; border-radius: 4px; padding: 8px 16px; cursor: pointer;">
                ${msg.get("memo.btn.close")}
            </button>
        </div>
    </div>
</div>

<div id="mysqlManagementModal" class="modal-overlay">
    <div class="modal-container" style="max-width: 1100px; width: 95%;min-height: 40vh;">
        <div class="modal-header" style="display: flex; justify-content: space-between; align-items: center;">
            <h3 class="modal-title">
                <i class="fas fa-database" style="color: var(--accent-blue); margin-right: 8px;"></i>${msg.get("detail.dbDetail")}
            </h3>
            <div style="display: flex; gap: 10px;">
                <button class="btn btn-success" onclick="createMysql()">
                    <i class="fas fa-plus"></i> ${msg.get("detail.createMysql")}
                </button>
                <button class="btn btn-primary" onclick="syncMysqlFromCloud()">
                    <i class="fas fa-sync"></i> ${msg.get("detail.syncMysql")}
                </button>
                <button class="close-btn" onclick="closeModal('mysqlManagementModal')">&times;</button>
            </div>
        </div>

        <div id="mysqlLoading" class="loading-container" style="display: none; padding: 30px;">
            <span class="loading-spinner"></span><span class="loading-text">${msg.get("detail.syncMysqlLoading")}</span>
        </div>

        <div id="mysqlContent" style="padding: 10px 0;">
            <div id="mysqlInstanceList" class="table-view" style="margin-bottom: 0; border: none;">
            </div>
        </div>
    </div>
</div>
<!-- 在body结束前引入版本信息模块 -->
<#--<#include "common/version_info.ftl">-->
<script>
    window.I18N = {
        common_noData: "${msg.get('common.noData')?js_string}",
        common_available: "${msg.get('common.available')?js_string}",
        common_noAvailable: "${msg.get('common.noAvailable')?js_string}",
        common_plzInputGlobalRequired: "${msg.get('common.plzInputGlobalRequired')?js_string}",
        common_loading: "${msg.get('common.loading')?js_string}",
        common_portRange: "${msg.get('common.portRange')?js_string}",
        common_saving: "${msg.get('common.saving')?js_string}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        common_delete: "${msg.get('common.delete')?js_string}",
        detail_netError: "${msg.get('detail.netError')?js_string}",
        detail_syncSuccess: "${msg.get('detail.syncSuccess')?js_string}",
        tenant_icmpNoPort: "${msg.get('tenant.icmpNoPort')?js_string}",
        detail_openAll: "${msg.get('detail.openAll')?js_string}",
        tenant_portRange: "${msg.get('tenant.portRange')?js_string}",
        detail_icmpNoNeed: "${msg.get('detail.icmpNoNeed')?js_string}",
        detail_openAllInCloud: "${msg.get('detail.openAllInCloud')?js_string}",
        detail_loadRuleFail: "${msg.get('detail.loadRuleFail')?js_string}",
        page_prev: "${msg.get('header.page.prev')?js_string}",
        detail_to: "${msg.get('detail.to')?js_string}",
        detail_pageTotal: "${msg.get('detail.pageTotal')?js_string}",
        detail_pageTotal2: "${msg.get('detail.pageTotal2')?js_string}",
        detail_pageTotal3: "${msg.get('detail.pageTotal3')?js_string}",
        detail_resetSize: "${msg.get('detail.resetSize')?js_string}",
        detail_noVolume: "${msg.get('detail.noVolume')?js_string}",
        detail_noConnIns: "${msg.get('detail.noConnIns')?js_string}",
        detail_update: "${msg.get('detail.update')?js_string}",
        common_delete: "${msg.get('common.delete')?js_string}",
        page_next: "${msg.get('header.page.next')?js_string}",
        tenant_uv: "${msg.get('tenant.uv')?js_string}",
        tenant_un: "${msg.get('tenant.un')?js_string}",
        detail_allProtocol: "${msg.get('detail.allProtocol')?js_string}",
        tenant_delete_title: "${msg.get('mfa.confirm.delete_title')?js_string}",
        detail_dbName: "${msg.get('detail.dbName')?js_string}",
        detail_dbv: "${msg.get('detail.dbv')?js_string}",
        detail_dbs: "${msg.get('detail.dbs')?js_string}",
        detail_dbpn: "${msg.get('detail.dbpn')?js_string}",
        detail_dbup: "${msg.get('detail.dbup')?js_string}",
        detail_dbsku: "${msg.get('detail.dbsku')?js_string}",
        detail_dbsave: "${msg.get('detail.dbsave')?js_string}",
        tenant_action: "${msg.get('tenant.action')?js_string}",
        detail_dbNo: "${msg.get('detail.dbNo')?js_string}",
        detail_dbNoP: "${msg.get('detail.dbNoP')?js_string}",
        detail_dbNoU: "${msg.get('detail.dbNoU')?js_string}",
        detail_dbSync: "${msg.get('detail.dbSync')?js_string}",
        detail_dbUpdate: "${msg.get('detail.dbUpdate')?js_string}",
        detail_dbResetPass: "${msg.get('detail.dbResetPass')?js_string}",
        detail_bindPublicIp: "${msg.get('detail.bindPublicIp')?js_string}",
        detail_termDb: "${msg.get('detail.termDb')?js_string}",
        detail_copy_success: "${msg.get('mfa.msg.copy_success')?js_string}",
        detail_DbReset: "${msg.get('detail.DbReset')?js_string}",
        detail_temRun: "${msg.get('detail.temRun')?js_string}",
        detail_tem: "${msg.get('detail.tem')?js_string}",
        detail_deleteAlert: "${msg.get('detail.deleteAlert')?js_string}",
        detail_deleteConfirm: "${msg.get('detail.deleteConfirm')?js_string}",
        detail_requestDbResource: "${msg.get('detail.requestDbResource')?js_string}",
        detail_requestDbResourceSuccess: "${msg.get('detail.requestDbResourceSuccess')?js_string}",
        detail_createDb: "${msg.get('detail.createDb')?js_string}",
        detail_createDbFree: "${msg.get('detail.createDbFree')?js_string}",
        detail_mysqlLoading: "${msg.get('detail.mysqlLoading')?js_string}",
        detail_mysqlSend: "${msg.get('detail.mysqlSend')?js_string}",
        detail_mysqlCreating: "${msg.get('detail.mysqlCreating')?js_string}",
        detail_mysqlCreatLimit: "${msg.get('detail.mysqlCreatLimit')?js_string}",
        detail_mysqlResetPass: "${msg.get('detail.mysqlResetPass')?js_string}",
        detail_mysqlResetPassSum: "${msg.get('detail.mysqlResetPassSum')?js_string}",
        common_network_error: "${msg.get('common.network.error')}"

    }
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/system/tenant_region_list.js"></script>
<script src="/js/common/dropdown-menu.js"></script>
</body>
</html>