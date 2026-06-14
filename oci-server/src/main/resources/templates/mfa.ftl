<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - MFA管理</title>
    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <link rel="stylesheet" href="/css/app/mfa.css">
    <link rel="stylesheet" href="/css/common/loading.css">
</head>
<body>

<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <main class="main-content">
        <div class="form-section hidden" id="addKeySection">
            <h2 class="section-title">
                <i class="fas fa-plus-circle"></i>
                ${msg.get('mfa.form.add_title')}
            </h2>
            <form action="/save-secret" method="post" enctype="multipart/form-data" id="keyForm">
                <div class="form-group">
                    <label class="form-label" for="keyName">${msg.get('mfa.form.label_name')}:</label>
                    <input type="text" class="form-control" id="keyName" name="keyName" placeholder="${msg.get('mfa.form.placeholder_name')}">
                </div>
                <div class="form-group">
                    <label class="form-label" for="secretKey">${msg.get('mfa.form.label_secret')}:</label>
                    <input type="text" class="form-control" id="secretKey" name="secretKey" placeholder="${msg.get('mfa.form.placeholder_secret')}">
                </div>
                <div class="file-upload" id="uploadArea">
                    <label class="file-upload-btn">
                        <i class="fas fa-upload"></i> ${msg.get('mfa.form.upload_qr')}
                        <input type="file" id="qrCode" name="qrCode" accept="image/*">
                    </label>
                    <div id="fileName" class="file-name">${msg.get('mfa.form.no_file')}</div>
                    <img id="previewImage" class="preview-image" alt="QR Code preview">
                    <div class="paste-zone" id="pasteArea">
                        <i class="fas fa-clipboard"></i> ${msg.get('mfa.form.paste_tip')}
                    </div>
                </div>
                <div class="button-group">
                    <button type="submit" class="btn btn-primary"><i class="fas fa-save"></i> ${msg.get('mfa.action.save')}</button>
                    <button type="button" class="btn btn-cancel" onclick="toggleAddForm()"><i class="fas fa-times"></i> ${msg.get('mfa.action.cancel')}</button>
                </div>
            </form>
        </div>

        <div class="controls-section">
            <div class="search-container">
                <i class="fas fa-search" style="color: var(--text-secondary);"></i>
                <input type="text" class="search-input" id="searchInput" placeholder="${msg.get('mfa.search.placeholder')}" onkeyup="searchKeys()">
            </div>
            <div class="button-group">
                <button class="btn-add-toggle" onclick="toggleAddForm()">
                    <i class="fas fa-plus"></i> ${msg.get('mfa.action.add')}
                </button>
                <button class="export-btn" onclick="exportData()">
                    <i class="fas fa-download"></i> ${msg.get('mfa.action.export')}
                </button>
            </div>
        </div>

        <div class="form-section">
            <h2 class="section-title">
                <i class="fas fa-key"></i> ${msg.get('mfa.table.title')}
                <span style="font-size: 12px; font-weight: normal; color: var(--text-secondary); margin-left: auto;">
                    ${msg.get('mfa.table.total')} <span id="totalCount">0</span> ${msg.get('mfa.table.unit')}
                </span>
            </h2>
            <div class="table-wrapper">
                <table class="keys-table">
                    <thead>
                    <tr>
                        <th>${msg.get('mfa.table.col_name')}</th>
                        <th>${msg.get('mfa.table.col_issuer')}</th>
                        <th>${msg.get('mfa.table.col_secret')}</th>
                        <th>${msg.get('mfa.table.col_qr')}</th>
                        <th>${msg.get('mfa.table.col_otp')}</th>
                        <th>${msg.get('mfa.table.col_action')}</th>
                    </tr>
                    </thead>
                    <tbody id="keysTableBody">
                    <#if otpKeys?? && (otpKeys?size > 0)>
                        <#list otpKeys as otpKey>
                            <tr class="key-row" data-key-name="${otpKey.keyName}" data-issuer="${otpKey.issuer!'default'}">
                                <td class="key-name-cell">${otpKey.keyName}</td>
                                <td><span class="issuer-badge">${otpKey.issuer!'Default'}</span></td>
                                <td>
                                    <div class="secret-display" data-secret="${otpKey.secretKey}" data-tooltip="${msg.get('mfa.table.click_show')}" onclick="toggleSecretDisplay(this)">
                                        <span class="secret-hidden">••••••••••••</span>
                                        <i class="fas fa-eye secret-copy-icon"></i>
                                    </div>
                                </td>
                                <td>
                                    <img src="data:image/png;base64,${otpKey.qrCode}" class="qr-image" onclick="enlargeQrCode(this)">
                                </td>
                                <td>
                                    <div class="otp-container">
                                        <div class="otp-code-display loading" data-secret="${otpKey.secretKey}" onclick="copyToClipboard(this.textContent)">${msg.get('dashboard.status.loading')}</div>
                                        <div class="countdown-info">
                                            <span class="countdown-badge">30</span> <span>${msg.get('mfa.table.refresh_tip')}</span>
                                        </div>
                                    </div>
                                </td>
                                <td>
                                    <button class="action-btn" onclick="deleteKey('${otpKey.keyName}')"><i class="fas fa-trash"></i></button>
                                </td>
                            </tr>
                        </#list>
                    <#else>
                        <tr class="empty-row">
                            <td colspan="6">
                                <div class="empty-content">
                                    <div class="empty-icon"><i class="fas fa-key"></i></div>
                                    <div class="empty-title">${msg.get('mfa.table.empty')}</div>
                                </div>
                            </td>
                        </tr>
                    </#if>
                    </tbody>
                </table>
            </div>
        </div>
    </main>
</div>
<div id="qrModal" class="modal">
    <div class="modal-content">
        <span class="close-modal" onclick="closeModal()">&times;</span>
        <img id="modalImage" src="" alt="Enlarged QR Code">
    </div>
</div>

<script src="/js/sweetalert2.min.js"></script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script>
    window.mfaI18n = {
        selected: "${msg.get('mfa.form.selected')!''}",
        noFile: "${msg.get('mfa.form.no_file')!''}",
        autoExtract: "${msg.get('mfa.form.auto_extract')!''}",
        placeholderSecret: "${msg.get('mfa.form.placeholder_secret')!''}",
        requireName: "${msg.get('mfa.form.require_name')!''}",
        requireSecret: "${msg.get('mfa.form.require_secret')!''}",
        saving: "${msg.get('mfa.action.saving')!''}",
        copySuccess: "${msg.get('mfa.msg.copy_success')!''}",
        copyFail: "${msg.get('mfa.msg.copy_fail')!''}",
        clickCopy: "${msg.get('mfa.table.click_copy')!''}",
        clickShow: "${msg.get('mfa.table.click_show')!''}",
        loading: "${msg.get('dashboard.status.loading')!''}",
        error: "Error",
        exportHeaderName: "${msg.get('mfa.table.col_name')!''}",
        exportHeaderIssuer: "${msg.get('mfa.table.col_issuer')!''}",
        exportHeaderSecret: "${msg.get('mfa.table.col_secret')!''}",
        exportSuccess: "${msg.get('mfa.msg.export_success')!''}",
        exportFail: "${msg.get('mfa.msg.export_fail')!''}",
        confirmDeleteTitle: "${msg.get('mfa.confirm.delete_title')!''}",
        confirmDeleteText: "${msg.get('mfa.confirm.delete_text')!''}",
        deleteWarning: "${msg.get('mfa.confirm.delete_warning')!''}",
        deleting: "${msg.get('mfa.status.deleting')!''}",
        deleteSuccess: "${msg.get('mfa.msg.delete_success')!''}",
        deleteFail: "${msg.get('mfa.status.deleteFail')!''}",
        btnConfirm: "${msg.get('mfa.action.confirm')!'确定'}",
        btnCancel: "${msg.get('mfa.action.cancel')!'取消'}",
        sessionTimeout: "${msg.get('mfa.msg.session_timeout')!''}"
    };

    window.toggleAddForm = function() {
        const section = document.getElementById('addKeySection');
        if (section) {
            if (section.classList.contains('hidden')) {
                section.classList.remove('hidden');
                section.scrollIntoView({ behavior: 'smooth', block: 'start' });
            } else {
                section.classList.add('hidden');
            }
        }
    };
</script>
<script src="/js/system/mfa.js"></script>
</body>
</html>