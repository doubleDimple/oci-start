<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <title>VPS管理系统 - 邮件管理</title>
    <script>(function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <script src="/js/common/jquery.min.js"></script>
    <link rel="stylesheet" href="/css/app/email.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/common/custom-select.css">
    <style>
        .layout { padding-top: 0; }
        .main-content { margin-left: 0; padding: 20px 24px; background: var(--bg); }
        .email-tab-bar { display: flex; gap: 4px; margin-bottom: 2px; border-bottom: 1px solid var(--card-border); padding-bottom: 0; }
        .email-tab { flex: 1; padding: 8px 12px; background: none; border: none; border-bottom: 2px solid transparent; cursor: pointer; font-size: 13px; color: var(--text-secondary); display: flex; align-items: center; justify-content: center; gap: 6px; transition: all 0.15s; margin-bottom: -1px; }
        .email-tab:hover { color: var(--text-primary); }
        .email-tab.active { color: var(--accent-blue, #1abc9c); border-bottom-color: var(--accent-blue, #1abc9c); font-weight: 600; }
        .tab-badge { display: inline-flex; align-items: center; justify-content: center; min-width: 18px; height: 18px; padding: 0 5px; border-radius: 9px; font-size: 11px; font-weight: 600; background: var(--accent-blue, #1abc9c); color: #fff; }
        .tab-badge-gray { background: var(--text-secondary); }
        .enable-inline-form { padding: 10px 12px; background: var(--hover-bg); border-top: 1px solid var(--card-border); }
        .enable-inline-form .form-row { display: flex; gap: 8px; align-items: center; }
        .enable-inline-form input { flex: 1; font-size: 13px; }
    </style>
</head>
<body>
<!-- 引入顶部导航栏 -->
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <!-- 引入侧边栏 -->
    <#--<#include "common/sidebar.ftl" />-->

    <!-- 主内容区域 -->
    <main class="main-content">
        <div class="page-card">
        <div class="email-management-container">
            <!-- 页面标题 -->
            <div class="page-header">
                <h1 class="page-title">
                    <i class="fas fa-envelope"></i>
                    <span>${msg.get("email.config")}</span>
                </h1>
                <button class="btn btn-primary" onclick="showEmailComposeModal()">
                    <i class="fas fa-edit"></i> ${msg.get("email.send")}
                </button>
            </div>

            <div class="content-grid">
                <!-- 左侧：租户邮件服务管理 -->
                <div class="settings-card">
                    <div class="settings-card-header">
                        <h3 class="settings-card-title">
                            <i class="fas fa-server"></i>
                            ${msg.get("email.availableTenant")}
                        </h3>
                        <button class="btn btn-sm btn-primary" onclick="refreshCurrentTab()">
                            <i class="fas fa-sync"></i> ${msg.get("email.refresh")}
                        </button>
                    </div>
                    <div class="settings-card-body">
                        <!-- Tab 切换 -->
                        <div class="email-tab-bar">
                            <button class="email-tab active" id="tab-btn-enabled" onclick="switchEmailTab('enabled')">
                                <i class="fas fa-check-circle"></i>
                                ${msg.get("email.tabEnabled")!'已开启'}
                                <span class="tab-badge" id="enabledCount">0</span>
                            </button>
                            <button class="email-tab" id="tab-btn-disabled" onclick="switchEmailTab('disabled')">
                                <i class="fas fa-plus-circle"></i>
                                ${msg.get("email.tabDisabled")!'未开启'}
                                <span class="tab-badge tab-badge-gray" id="disabledCount">0</span>
                            </button>
                        </div>
                        <!-- 搜索框 -->
                        <div style="padding: 8px 0 4px;">
                            <input type="text" id="tenantSearchInput" class="form-control"
                                   placeholder="${msg.get("email.searchTenant")!'搜索租户...'}"
                                   style="font-size:13px;"
                                   oninput="onTenantSearch(this.value)">
                        </div>

                        <!-- 已开启 Tab -->
                        <div id="tab-content-enabled">
                            <div id="tenantsList" class="tenant-list"></div>
                            <div class="pagination-container">
                                <div class="pagination-nav">
                                    <button class="page-btn" id="tenantPrevBtn" onclick="goToTenantPage(tenantCurrentPage - 1)">
                                        <i class="fas fa-chevron-left"></i>
                                    </button>
                                    <div id="tenantPageNumbers"></div>
                                    <button class="page-btn" id="tenantNextBtn" onclick="goToTenantPage(tenantCurrentPage + 1)">
                                        <i class="fas fa-chevron-right"></i>
                                    </button>
                                </div>
                                <div class="page-info" id="tenantPageInfo">共 0 个租户</div>
                            </div>
                        </div>

                        <!-- 未开启 Tab -->
                        <div id="tab-content-disabled" style="display:none;">
                            <div id="notEnabledTenantsList" class="tenant-list"></div>
                            <div class="pagination-container">
                                <div class="pagination-nav">
                                    <button class="page-btn" id="notEnabledPrevBtn" onclick="goToNotEnabledPage(notEnabledCurrentPage - 1)">
                                        <i class="fas fa-chevron-left"></i>
                                    </button>
                                    <div id="notEnabledPageNumbers"></div>
                                    <button class="page-btn" id="notEnabledNextBtn" onclick="goToNotEnabledPage(notEnabledCurrentPage + 1)">
                                        <i class="fas fa-chevron-right"></i>
                                    </button>
                                </div>
                                <div class="page-info" id="notEnabledPageInfo">共 0 个租户</div>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- 右侧：联系人管理 -->
                <div class="settings-card">
                    <div class="settings-card-header">
                        <h3 class="settings-card-title">
                            <i class="fas fa-address-book"></i>
                            ${msg.get("email.person")}
                        </h3>
                        <div class="header-actions">
                            <button class="btn btn-sm btn-success" onclick="showAddContactModal()">
                                <i class="fas fa-plus"></i> ${msg.get("email.addPerson")}
                            </button>
                            <button class="btn btn-sm btn-primary" onclick="refreshContacts()">
                                <i class="fas fa-sync"></i> ${msg.get("refresh")}
                            </button>
                        </div>
                    </div>
                    <div class="settings-card-body">
                        <div id="contactsList"></div>
                        <!-- 联系人分页 -->
                        <div class="pagination-container" id="contactsPagination">
                            <div class="pagination-nav">
                                <button class="page-btn" id="prevPageBtn" onclick="goToPage(currentPage - 1)">
                                    <i class="fas fa-chevron-left"></i>
                                </button>
                                <div id="pageNumbers">
                                </div>
                                <button class="page-btn" id="nextPageBtn" onclick="goToPage(currentPage + 1)">
                                    <i class="fas fa-chevron-right"></i>
                                </button>
                            </div>
                            <div class="page-info" id="contactsPageInfo">0 ${msg.get("email.personCount")}</div>
                        </div>
                    </div>
                </div>
            </div>

            <!-- 邮件发送记录 -->
            <div class="settings-card full-width-card">
                <div class="settings-card-header">
                    <h3 class="settings-card-title">
                        <i class="fas fa-history"></i>
                        ${msg.get("email.sendRecord")}
                    </h3>
                    <div class="header-actions">
                        <button class="btn btn-sm btn-danger" onclick="batchDeleteAllRecords()">
                            <i class="fas fa-trash"></i> ${msg.get("common.delete")}
                        </button>
                        <button class="btn btn-sm btn-primary" onclick="refreshRecords()">
                            <i class="fas fa-sync"></i> ${msg.get("email.refresh")}
                        </button>
                    </div>
                </div>
                <div class="settings-card-body">
                    <div id="emailRecords">
                    </div>
                    <!-- 记录分页 -->
                    <div class="pagination-container" id="emailRecordsPagination">
                        <div class="pagination-nav">
                            <button class="page-btn" id="emailRecordsPrevBtn" onclick="goToEmailRecordsPage(recordCurrentPage - 1)">
                                <i class="fas fa-chevron-left"></i>
                            </button>
                            <div id="emailRecordsPageNumbers">
                            </div>
                            <button class="page-btn" id="emailRecordsNextBtn" onclick="goToEmailRecordsPage(recordCurrentPage + 1)">
                                <i class="fas fa-chevron-right"></i>
                            </button>
                        </div>
                        <div class="page-info" id="emailRecordsPageInfo">0 ${msg.get("email.records")}</div>
                    </div>
                </div>
            </div>
        </div>
        </div><!-- /.page-card -->
    </main>
</div>

<!-- 邮件编写模态框 -->
<div class="modal" id="emailComposeModal">
    <div class="modal-content">
        <div class="modal-header">
            <h3 class="modal-title">
                <i class="fas fa-edit"></i>
                ${msg.get("email.edit")}
            </h3>
            <button class="modal-close" onclick="closeEmailComposeModal()">
                <i class="fas fa-times"></i>
            </button>
        </div>
        <div class="modal-body">
            <form id="emailComposeForm">
                <div class="form-row">
                    <label class="form-label">${msg.get("email.title")}</label>
                    <input type="text" class="form-control" id="composeSubject" placeholder="${msg.get("email.plzTitle")}">
                </div>
                <div class="form-row">
                    <label class="form-label">${msg.get("email.content")}</label>
                    <textarea class="form-control" id="composeContent" rows="10" placeholder="${msg.get("email.plzContent")}"></textarea>
                </div>
                <div class="form-row">
                    <label class="form-label">${msg.get("email.selectTenant")}</label>
                    <select class="form-control" id="composeTenantSelect"
                            data-custom-select data-placeholder="${msg.get("email.selectSenderEmail")}">
                    </select>
                </div>

                <!-- 收件人选择区域 -->
                <div class="recipients-section">
                    <h4 class="recipients-title">
                        <i class="fas fa-users"></i>
                        ${msg.get("email.receiverEmail")}
                    </h4>
                    <div class="recipient-controls">
                        <button type="button" class="btn btn-sm btn-primary" onclick="selectAllRecipients()">
                            <i class="fas fa-check-square"></i> ${msg.get("email.selectAll")}
                        </button>
                        <button type="button" class="btn btn-sm btn-secondary" onclick="unselectAllRecipients()">
                            <i class="fas fa-square"></i> ${msg.get("email.selectNo")}
                        </button>
                        <span class="selected-count">${msg.get("email.alreadySelect")}: <span id="selectedCount">0</span> ${msg.get("email.man")}</span>
                    </div>
                    <div id="recipientsList" class="recipients-list">
                    </div>
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-sm btn-primary" onclick="sendEmail()">
                <i class="fas fa-paper-plane"></i> ${msg.get("email.sendEmail")}
            </button>
            <button type="button" class="btn btn-sm btn-secondary" onclick="closeEmailComposeModal()">
                <i class="fas fa-times"></i> ${msg.get("common.cancel")}
            </button>
        </div>
    </div>
</div>

<!-- 邮件详情模态框 -->
<div class="modal" id="emailDetailsModal">
    <div class="modal-content">
        <div class="modal-header">
            <h3 class="modal-title">
                <i class="fas fa-envelope"></i>
                <span id="emailSubjectTitle">${msg.get("email.detail")}</span>
            </h3>
            <button class="modal-close" onclick="closeEmailDetailsModal()">
                <i class="fas fa-times"></i>
            </button>
        </div>
        <div class="modal-body">
            <div id="emailDetailInfo" class="email-detail-info">
                <!-- 邮件基本信息 -->
            </div>
            <div class="recipients-section">
                <h4 class="recipients-title">${msg.get("email.receiverList")}</h4>
                <div id="recipientsDetailList" class="recipients-list">
                </div>
                <div class="pagination-container" id="emailDetailPagination">
                    <div class="pagination-nav">
                        <button class="page-btn" id="emailDetailPrevBtn" onclick="goToDetailPage(detailCurrentPage - 1)">
                            <i class="fas fa-chevron-left"></i>
                        </button>
                        <div id="emailDetailPageNumbers">
                        </div>
                        <button class="page-btn" id="emailDetailNextBtn" onclick="goToDetailPage(detailCurrentPage + 1)">
                            <i class="fas fa-chevron-right"></i>
                        </button>
                    </div>
                    <div class="page-info" id="emailDetailPageInfo">${msg.get("email.zoroRecord")}</div>
                </div>
            </div>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-sm btn-secondary" onclick="closeEmailDetailsModal()">
                <i class="fas fa-times"></i> ${msg.get("memo.btn.close")}
            </button>
        </div>
    </div>
</div>

<!-- 添加联系人模态框 -->
<div class="modal" id="addContactModal">
    <div class="modal-content">
        <div class="modal-header">
            <h3 class="modal-title">
                <i class="fas fa-plus"></i>
                ${msg.get("email.addPerson")}
            </h3>
            <button class="modal-close" onclick="closeAddContactModal()">
                <i class="fas fa-times"></i>
            </button>
        </div>
        <div class="modal-body">
            <form id="addContactForm">
                <div class="form-row">
                    <label class="form-label">${msg.get("email.personName")}</label>
                    <input type="text" class="form-control" id="contactName" placeholder="${msg.get("email.plzPersonName")}">
                </div>
                <div class="form-row">
                    <label class="form-label">${msg.get("email.address")}</label>
                    <input type="email" class="form-control" id="contactEmail" placeholder="${msg.get("email.plzAddress")}">
                </div>
            </form>
        </div>
        <div class="modal-footer">
            <button type="button" class="btn btn-sm btn-primary" onclick="saveContact()">
                <i class="fas fa-save"></i> ${msg.get("common.save")}
            </button>
            <button type="button" class="btn btn-sm btn-secondary" onclick="closeAddContactModal()">
                <i class="fas fa-times"></i> ${msg.get("common.cancel")}
            </button>
        </div>
    </div>
</div>

<!-- 版本信息模块 -->
<#--
<#include "common/version_info.ftl">
-->
<script>
    window.I18N = {
        common_noData: "${msg.get('common.noData')?js_string}",
        common_available: "${msg.get('common.available')?js_string}",
        common_noAvailable: "${msg.get('common.noAvailable')?js_string}",
        common_plzInputGlobalRequired: "${msg.get('common.plzInputGlobalRequired')?js_string}",
        common_portRange: "${msg.get('common.portRange')?js_string}",
        common_saving: "${msg.get('common.saving')?js_string}",
        vpn_isDelete: "${msg.get('vpn.isDelete')?js_string}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        common_delete: "${msg.get('common.delete')?js_string}",
        email_selectSenderEmail: "${msg.get('email.selectSenderEmail')?js_string}",
        aiModel_tenant: "${msg.get('aiModel.tenant')?js_string}",
        email_noContentPerson: "${msg.get('email.noContentPerson')?js_string}",
        email_addFirstContentPerson: "${msg.get('email.addFirstContentPerson')?js_string}",
        email_formatError: "${msg.get('email.formatError')?js_string}",
        email_noSelectReceive: "${msg.get('email.noSelectReceive')?js_string}",
        email_sendTime: "${msg.get('email.sendTime')?js_string}",
        email_sender: "${msg.get('email.sender')?js_string}",
        email_content: "${msg.get('email.content')?js_string}",
        email_noEmailRecords: "${msg.get('email.noEmailRecords')?js_string}",
        email_noSendEmail: "${msg.get('email.noSendEmail')?js_string}",
        email_receiveNo: "${msg.get('email.receiveNo')?js_string}",
        email_success: "${msg.get('email.success')?js_string}",
        email_fail: "${msg.get('email.fail')?js_string}",
        email_deleteRecords: "${msg.get('email.deleteRecords')?js_string}",
        email_records: "${msg.get('email.records')?js_string}",
        email_noFindRecords: "${msg.get('email.noFindRecords')?js_string}",
        email_receivers: "${msg.get('email.receivers')?js_string}",
        email_personCount: "${msg.get('email.personCount')?js_string}",
        email_total: "${msg.get('email.total')?js_string}",
        email_one: "${msg.get('email.one')?js_string}",
        email_noTenant: "${msg.get('email.noTenant')?js_string}",
        email_noEmailServerTenant: "${msg.get('email.noEmailServerTenant')?js_string}",
        email_disEmailServer: "${msg.get('email.disEmailServer')?js_string}",
        vpn_edit: "${msg.get('vpn.edit')?js_string}"

    }
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/common/custom-select.js"></script>
<script src="/js/system/email.js"></script>

</body>
</html>