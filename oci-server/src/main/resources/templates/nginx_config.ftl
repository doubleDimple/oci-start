<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Nginx管理</title>
    <script>(function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/app/nginx_config.css">
    <style>
        /* SweetAlert2 弹窗内嵌表单样式 — 走主题变量,亮/暗模式都对齐其他页面。
           Swal 自身的弹窗背景由 swal2-popup 控制,这里只覆盖输入控件颜色 */
        .swal2-popup .ssl-form-group { margin-bottom: 16px; }
        .swal2-popup .ssl-form-label { display: block; margin-bottom: 6px; font-weight: 500; font-size: 13px; color: var(--text-primary); }
        .swal2-popup .ssl-form-input,
        .swal2-popup .ssl-form-select {
            width: 100%; padding: 10px 12px;
            border: 1px solid var(--card-border); border-radius: 6px;
            font-size: 13px; background: var(--surface-2); color: var(--text-primary);
            box-sizing: border-box; transition: border-color 0.2s;
        }
        .swal2-popup .ssl-form-input:focus,
        .swal2-popup .ssl-form-select:focus {
            outline: none; border-color: var(--accent-green);
            box-shadow: 0 0 0 2px rgba(63,185,80,0.18);
        }
        /* Proxy 目标行(SweetAlert 内) */
        .swal2-popup .proxy-target-item {
            border: 1px solid var(--card-border); border-radius: 8px; padding: 14px;
            margin-bottom: 10px; background: var(--surface-2);
        }
        /* 兼容旧代码引用的 ssl-btn — 现在统一走主题色 */
        .ssl-btn {
            display: inline-flex; align-items: center; gap: 6px;
            padding: 8px 14px; border: none; border-radius: 6px;
            font-size: 13px; font-weight: 500; cursor: pointer;
            transition: opacity 0.2s, background 0.2s; text-decoration: none;
        }
        .ssl-btn:disabled { opacity: 0.5; cursor: not-allowed; }
        .ssl-btn:hover:not(:disabled) { opacity: 0.88; }
        .ssl-btn-primary   { background: var(--accent-green); color: #fff; }
        .ssl-btn-secondary { background: var(--hover-bg);     color: var(--text-primary); border: 1px solid var(--card-border); }
        .ssl-btn-danger    { background: var(--accent-red);   color: #fff; }
        .ssl-btn-warning   { background: var(--accent-orange);color: #fff; }
    </style>
</head>
<body>
<#--<#include "common/header.ftl" />-->
<div class="layout">
<#--<#include "common/sidebar.ftl" />-->
<main class="main-content">
<div class="page-card">

    <!-- 页面标题 -->
    <div class="page-header">
        <h1 class="page-title">
            <i class="fas fa-server"></i>
            <span>${msg.get('nginx.page.title')}</span>
        </h1>
        <div class="view-actions">
            <button class="btn btn-secondary" onclick="checkOpenRestyStatus()">
                <i class="fas fa-sync-alt"></i>
                <span>${msg.get('nginx.btn.checkService')}</span>
            </button>
        </div>
    </div>

    <!-- OpenResty 状态提示 -->
    <div id="openrestyStatus" class="openresty-status-bar" style="display:none;"></div>

    <!-- Tab 导航 -->
    <div class="nginx-tabs">
        <button class="nginx-tab-btn active" data-tab="certificates" onclick="switchTab(this)">
            <i class="fas fa-certificate"></i>
            ${msg.get('nginx.tab.cert')}
        </button>
        <button class="nginx-tab-btn" data-tab="proxy" onclick="switchTab(this)">
            <i class="fas fa-exchange-alt"></i>
            ${msg.get('nginx.tab.proxy')}
        </button>
        <button class="nginx-tab-btn" data-tab="nginx" onclick="switchTab(this)">
            <i class="fas fa-code"></i>
            ${msg.get('nginx.tab.config')}
        </button>
    </div>

    <!-- SSL证书管理 -->
    <div id="certificates" class="nginx-tab-content active">
        <div class="tab-actions">
            <button class="btn btn-success" onclick="showRequestCertModal()">
                <i class="fas fa-plus"></i>
                ${msg.get('nginx.btn.requestCert')}
            </button>
            <button class="btn btn-secondary" onclick="refreshCertList()">
                <i class="fas fa-sync-alt"></i>
                ${msg.get('nginx.btn.refreshCert')}
            </button>
        </div>
        <table class="nginx-table">
            <thead>
            <tr>
                <th>${msg.get('nginx.col.domain')}</th>
                <th>${msg.get('nginx.col.certType')}</th>
                <th>${msg.get('nginx.col.status')}</th>
                <th>${msg.get('nginx.col.issueDate')}</th>
                <th>${msg.get('nginx.col.expireDate')}</th>
                <th>${msg.get('nginx.col.autoRenew')}</th>
                <th>${msg.get('nginx.col.actions')}</th>
            </tr>
            </thead>
            <tbody id="certTableBody">
                <tr><td colspan="7"><div class="empty-state"><i class="fas fa-spinner fa-spin"></i><p>${msg.get('nginx.loading')}</p></div></td></tr>
            </tbody>
        </table>
    </div>

    <!-- 反向代理配置 -->
    <div id="proxy" class="nginx-tab-content">
        <div class="tab-actions">
            <button class="btn btn-success" onclick="showAddProxyModal()">
                <i class="fas fa-plus"></i>
                ${msg.get('nginx.btn.addProxy')}
            </button>
            <button class="btn btn-secondary" onclick="refreshProxyList()">
                <i class="fas fa-sync-alt"></i>
                ${msg.get('nginx.btn.refreshProxy')}
            </button>
            <button class="btn btn-warning" onclick="switchTab(document.querySelector('[data-tab=nginx]'))">
                <i class="fas fa-eye"></i>
                ${msg.get('nginx.btn.viewConfig')}
            </button>
        </div>
        <table class="nginx-table">
            <thead>
            <tr>
                <th>${msg.get('nginx.col.domain')}</th>
                <th>${msg.get('nginx.col.target')}</th>
                <th>${msg.get('nginx.col.sslStatus')}</th>
                <th>${msg.get('nginx.col.configStatus')}</th>
                <th>${msg.get('nginx.col.createTime')}</th>
                <th>${msg.get('nginx.col.actions')}</th>
            </tr>
            </thead>
            <tbody id="proxyTableBody">
                <tr><td colspan="6"><div class="empty-state"><i class="fas fa-spinner fa-spin"></i><p>${msg.get('nginx.loading')}</p></div></td></tr>
            </tbody>
        </table>
    </div>

    <!-- Nginx配置管理 -->
    <div id="nginx" class="nginx-tab-content">
        <!-- 配置状态 -->
        <div class="config-status-bar pending" id="configStatus">
            <i class="fas fa-exclamation-triangle"></i>
            <span>${msg.get('nginx.config.pendingChanges')}</span>
        </div>
        <div class="tab-actions">
            <button class="btn btn-warning" onclick="testNginxConfig()">
                <i class="fas fa-vial"></i>
                ${msg.get('nginx.btn.testConfig')}
            </button>
            <button class="btn btn-success" onclick="applyNginxConfig()" id="applyBtn">
                <i class="fas fa-check"></i>
                ${msg.get('nginx.btn.applyConfig')}
            </button>
            <button class="btn btn-secondary" onclick="refreshConfigDiff()">
                <i class="fas fa-sync-alt"></i>
                ${msg.get('nginx.btn.refreshDiff')}
            </button>
            <button class="btn btn-secondary" onclick="reloadNginxConfig()">
                <i class="fas fa-redo"></i>
                ${msg.get('nginx.btn.reload')}
            </button>
        </div>
        <!-- 配置文件对比 -->
        <div class="diff-container" id="diffContainer">
            <div class="diff-panel">
                <div class="diff-panel-header">
                    <span><i class="fas fa-file-code"></i> ${msg.get('nginx.diff.current')}</span>
                    <button class="copy-btn" onclick="copyDiffContent('currentConfigContent', this)">
                        <i class="fas fa-copy"></i> ${msg.get('nginx.diff.copy')}
                    </button>
                </div>
                <pre class="diff-content" id="currentConfigContent">${msg.get('nginx.loading')}</pre>
            </div>
            <div class="diff-panel">
                <div class="diff-panel-header">
                    <span><i class="fas fa-file-alt"></i> ${msg.get('nginx.diff.latest')}</span>
                    <button class="copy-btn" onclick="copyDiffContent('latestConfigContent', this)">
                        <i class="fas fa-copy"></i> ${msg.get('nginx.diff.copy')}
                    </button>
                </div>
                <pre class="diff-content" id="latestConfigContent">${msg.get('nginx.loading')}</pre>
            </div>
        </div>
    </div>

</div><!-- /.page-card -->
</main>
</div>
<!-- 在body结束前引入版本信息模块 -->
<#--<#include "common/version_info.ftl">-->
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script>
    /* JS 端 i18n 字典,通过 window.I18N.<key> 访问 */
    window.I18N = {
        common_confirm: "${msg.get('common.confirm')?js_string}",
        common_cancel:  "${msg.get('common.cancel')?js_string}",
        nginx_loading:  "${msg.get('nginx.loading')?js_string}",
        nginx_openresty_notInstalled: "${msg.get('nginx.openresty.notInstalled')?js_string}",
        nginx_openresty_notRunning:   "${msg.get('nginx.openresty.notRunning')?js_string}",
        nginx_openresty_guide:        "${msg.get('nginx.openresty.guide')?js_string}",
        nginx_openresty_recheck:      "${msg.get('nginx.openresty.recheck')?js_string}",
        nginx_openresty_start:        "${msg.get('nginx.openresty.start')?js_string}",
        nginx_guide_title:        "${msg.get('nginx.guide.title')?js_string}",
        nginx_guide_step1_title:  "${msg.get('nginx.guide.step1.title')?js_string}",
        nginx_guide_step1_desc:   "${msg.get('nginx.guide.step1.desc')?js_string}",
        nginx_guide_step2_title:  "${msg.get('nginx.guide.step2.title')?js_string}",
        nginx_guide_step2_altCurl:"${msg.get('nginx.guide.step2.altCurl')?js_string}",
        nginx_guide_step3_title:  "${msg.get('nginx.guide.step3.title')?js_string}",
        nginx_guide_step4_title:  "${msg.get('nginx.guide.step4.title')?js_string}",
        nginx_guide_notes:        "${msg.get('nginx.guide.notes')?js_string}",
        nginx_guide_note1:        "${msg.get('nginx.guide.note1')?js_string}",
        nginx_guide_note2:        "${msg.get('nginx.guide.note2')?js_string}",
        nginx_guide_note3:        "${msg.get('nginx.guide.note3')?js_string}",
        nginx_guide_copy:         "${msg.get('nginx.guide.copy')?js_string}",
        nginx_guide_close:        "${msg.get('nginx.guide.close')?js_string}",
        nginx_guide_copied:       "${msg.get('nginx.guide.copied')?js_string}",
        nginx_guide_docker_title:    "${msg.get('nginx.guide.docker.title')?js_string}",
        nginx_guide_docker_desc:     "${msg.get('nginx.guide.docker.desc')?js_string}",
        nginx_guide_docker_appHint:  "${msg.get('nginx.guide.docker.appHint')?js_string}",
        nginx_modal_create:        "${msg.get('nginx.modal.create')?js_string}",
        nginx_modal_save:          "${msg.get('nginx.modal.save')?js_string}",
        nginx_modal_cancel:        "${msg.get('nginx.modal.cancel')?js_string}",
        nginx_modal_confirmDelete: "${msg.get('nginx.modal.confirmDelete')?js_string}",
        nginx_modal_delete:        "${msg.get('nginx.modal.delete')?js_string}",
        nginx_modal_creating:      "${msg.get('nginx.modal.creating')?js_string}",
        nginx_modal_creatingDesc:  "${msg.get('nginx.modal.creatingDesc')?js_string}",
        nginx_modal_updating:      "${msg.get('nginx.modal.updating')?js_string}",
        nginx_modal_proxy_add:     "${msg.get('nginx.modal.proxy.add')?js_string}",
        nginx_modal_proxy_edit:    "${msg.get('nginx.modal.proxy.edit')?js_string}",
        nginx_modal_proxy_deleteConfirm: "${msg.get('nginx.modal.proxy.deleteConfirm')?js_string}",
        nginx_modal_cert_request:  "${msg.get('nginx.modal.cert.request')?js_string}",
        nginx_modal_cert_requestSuccess: "${msg.get('nginx.modal.cert.requestSuccess')?js_string}",
        nginx_modal_cert_requestSuccessDesc: "${msg.get('nginx.modal.cert.requestSuccessDesc')?js_string}",
        nginx_modal_cert_requestFail: "${msg.get('nginx.modal.cert.requestFail')?js_string}",
        nginx_modal_cert_deleteConfirm: "${msg.get('nginx.modal.cert.deleteConfirm')?js_string}",
        nginx_modal_ssl_title:     "${msg.get('nginx.modal.ssl.title')?js_string}",
        nginx_modal_ssl_start:     "${msg.get('nginx.modal.ssl.start')?js_string}",
        nginx_modal_ssl_success:   "${msg.get('nginx.modal.ssl.success')?js_string}",
        nginx_modal_ssl_fail:      "${msg.get('nginx.modal.ssl.fail')?js_string}",
        nginx_toast_success:        "${msg.get('nginx.toast.success')?js_string}",
        nginx_toast_error:          "${msg.get('nginx.toast.error')?js_string}",
        nginx_toast_createSuccess:  "${msg.get('nginx.toast.createSuccess')?js_string}",
        nginx_toast_createSuccessDesc: "${msg.get('nginx.toast.createSuccessDesc')?js_string}",
        nginx_toast_createFail:     "${msg.get('nginx.toast.createFail')?js_string}",
        nginx_toast_updateSuccess:  "${msg.get('nginx.toast.updateSuccess')?js_string}",
        nginx_toast_updateFail:     "${msg.get('nginx.toast.updateFail')?js_string}",
        nginx_toast_deleteSuccess:  "${msg.get('nginx.toast.deleteSuccess')?js_string}",
        nginx_toast_deleteFail:     "${msg.get('nginx.toast.deleteFail')?js_string}",
        nginx_toast_testPassed:     "${msg.get('nginx.toast.testPassed')?js_string}",
        nginx_toast_testFailed:     "${msg.get('nginx.toast.testFailed')?js_string}",
        nginx_toast_applySuccess:   "${msg.get('nginx.toast.applySuccess')?js_string}",
        nginx_toast_applyFail:      "${msg.get('nginx.toast.applyFail')?js_string}",
        nginx_toast_reloadSuccess:  "${msg.get('nginx.toast.reloadSuccess')?js_string}",
        nginx_toast_reloadFail:     "${msg.get('nginx.toast.reloadFail')?js_string}"
    };
</script>
<script>
    let certificateList = [];
    // 页面加载时初始化
    document.addEventListener('DOMContentLoaded', function() {
        // 监听域名输入框变化
        const serverNameInput = document.getElementById('serverName');
        if (serverNameInput) {
            serverNameInput.addEventListener('blur', updateSslPaths);
        }
        // 获取所有父级菜单
        const navParents = document.querySelectorAll('.nav-parent');
        navParents.forEach(parent => {
            const parentLink = parent.querySelector('.nav-link');
            parentLink.addEventListener('click', (e) => {
                e.preventDefault();
                parent.classList.toggle('expanded');
            });
        });
        // 找到当前活动的子菜单项，并展开其父级菜单
        const activeLink = document.querySelector('.nav-link.active');
        if (activeLink) {
            const parent = activeLink.closest('.nav-parent');
            if (parent) {
                parent.classList.add('expanded');
            }
        }
        // 初始化数据
        loadInitialData();
        checkOpenRestyStatus();
    });
    // 获取CSRF Token
    function getCsrfToken() {
        const csrfMeta = document.querySelector('meta[name="_csrf"]');
        return csrfMeta ? csrfMeta.getAttribute('content') : '';
    }
    function getCsrfHeader() {
        const csrfHeaderMeta = document.querySelector('meta[name="_csrf_header"]');
        return csrfHeaderMeta ? csrfHeaderMeta.getAttribute('content') : 'X-CSRF-TOKEN';
    }
    // 标签切换功能
    function switchTab(btnEl) {
        const tabName = btnEl.getAttribute('data-tab');
        document.querySelectorAll('.nginx-tab-content').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.nginx-tab-btn').forEach(b => b.classList.remove('active'));
        document.getElementById(tabName).classList.add('active');
        btnEl.classList.add('active');
        switch(tabName) {
            case 'proxy':       loadProxyList();   break;
            case 'certificates':loadCertList();    break;
            case 'nginx':       loadConfigDiff();  break;
        }
    }
    // 初始化数据加载
    function loadInitialData() {
        loadCertList();
        loadProxyList();
        loadConfigDiff();
    }
    // =================== 反向代理配置功能 ===================

    function addProxy() {
        showProxyConfigModal({
            mode: 'create'
        });
    }
    function toggleSslConfig() {
        const enableSsl = document.getElementById('enableSsl').value;
        const sslSection = document.getElementById('sslConfigSection');
        sslSection.style.display = enableSsl === 'yes' ? 'block' : 'none';
        if (enableSsl === 'yes') {
            updateSslPaths();
        }
    }
    function updateSslPaths() {
        const serverName = document.getElementById('serverName').value;
        const enableSsl = document.getElementById('enableSsl').value;
        if (serverName && enableSsl === 'yes') {
            // 根据域名自动获取证书列表
            loadCertificatesForDomain(serverName);
        }
    }
    /**
     * 根据域名获取匹配的证书列表
     */
    function loadCertificatesForDomain(domain, selectedCertId) {
        if (!domain) {
            return;
        }
        const loadingEl = document.getElementById('certificateLoading');
        const infoEl = document.getElementById('certificateInfo');
        const infoTextEl = document.getElementById('certificateInfoText');
        if (loadingEl) loadingEl.style.display = 'block';
        if (infoEl) infoEl.style.display = 'none';
        fetch('/ssl/certificates/match?domain=' + encodeURIComponent(domain), {
            method: 'GET',
            headers: {
                [getCsrfHeader()]: getCsrfToken()
            }
        })
            .then(response => response.json())
            .then(data => {
                if (loadingEl) loadingEl.style.display = 'none';
                if (data.success && data.data && data.data.length > 0) {
                    populateCertificateOptions(data.data, selectedCertId);
                } else {
                    resetCertificateOptions();
                    if (infoEl) infoEl.style.display = 'none';
                }
            })
            .catch(error => {
                if (loadingEl) loadingEl.style.display = 'none';
                console.error('加载证书失败:', error);
                resetCertificateOptions();
            });
    }
    /**
     * 重置证书选项为默认状态
     */
    function resetCertificateOptions() {
        const selectEl = document.getElementById('sslKeyFile');
        if (!selectEl) return;
        selectEl.innerHTML = '<option value="">-- 请选择证书 --</option><option value="upload">上传证书文件</option>';
    }
    /**
     * 填充证书选项到下拉框
     */
    function populateCertificateOptions(certificates, selectedCertId) {
        const selectEl = document.getElementById('sslKeyFile');
        if (!selectEl) return;
        // 清空现有选项
        selectEl.innerHTML = '';
        // 添加默认选项
        const defaultOption = document.createElement('option');
        defaultOption.value = '';
        defaultOption.textContent = '-- 请选择证书 --';
        selectEl.appendChild(defaultOption);
        // 添加匹配的证书选项
        certificates.forEach((cert) => {
            const option = document.createElement('option');
            option.value = cert.id;
            option.textContent = cert.domain || cert.name;
            option.setAttribute('data-cert-path', cert.certPath || '');
            option.setAttribute('data-key-path', cert.keyPath || '');
            // 如果有选中的证书ID，设置为选中状态
            if (selectedCertId && cert.id == selectedCertId) {
                option.selected = true;
            }
            selectEl.appendChild(option);
        });
        // 添加上传选项
        const uploadOption = document.createElement('option');
        uploadOption.value = 'upload';
        uploadOption.textContent = '上传证书文件';
        selectEl.appendChild(uploadOption);
        // 触发change事件以填充证书路径
        if (selectedCertId || certificates.length > 0) {
            handleCertificateChange();
        }
    }
    /**
     * 当证书选择改变时的处理
     */
    function handleCertificateChange() {
        const selectEl = document.getElementById('sslKeyFile');
        if (!selectEl) return;
        const selectedValue = selectEl.value;
        const selectedOption = selectEl.options[selectEl.selectedIndex];
        const certPathInput = document.getElementById('sslCertPath');
        const keyPathInput = document.getElementById('sslKeyPath');
        const uploadCertBtn = document.getElementById('uploadCertBtn');
        const uploadKeyBtn = document.getElementById('uploadKeyBtn');
        if (selectedValue === 'upload') {
            // 选择上传,清空路径,显示上传按钮
            certPathInput.value = '';
            keyPathInput.value = '';
            certPathInput.readOnly = false;
            keyPathInput.readOnly = false;
            if (uploadCertBtn) uploadCertBtn.style.display = 'block';
            if (uploadKeyBtn) uploadKeyBtn.style.display = 'block';
        } else if (selectedValue) {
            // 选择了证书,从后端返回的数据中获取路径
            const certPath = selectedOption.getAttribute('data-cert-path');
            const keyPath = selectedOption.getAttribute('data-key-path');
            if (certPath && keyPath) {
                certPathInput.value = certPath;
                keyPathInput.value = keyPath;
                certPathInput.readOnly = true;
                keyPathInput.readOnly = true;
                if (uploadCertBtn) uploadCertBtn.style.display = 'none';
                if (uploadKeyBtn) uploadKeyBtn.style.display = 'none';
            }
        } else {
            // 未选择,清空路径
            certPathInput.value = '';
            keyPathInput.value = '';
            certPathInput.readOnly = false;
            keyPathInput.readOnly = false;
            if (uploadCertBtn) uploadCertBtn.style.display = 'none';
            if (uploadKeyBtn) uploadKeyBtn.style.display = 'none';
        }
    }
    function showAddProxyModal() {
        showProxyConfigModal({
            mode: 'create'
        });
    }
    function addProxyTarget() {
        const targetsContainer = document.getElementById('proxyTargets');
        const targetItem = document.createElement('div');
        targetItem.className = 'proxy-target-item';
        targetItem.style.cssText = 'border: 1px solid #e5e7eb; border-radius: 8px; padding: 15px; margin-bottom: 12px; background: #f9fafb;';
        targetItem.innerHTML = `
        <div style="display: grid; grid-template-columns: auto 1fr 1fr 1fr auto; gap: 12px; align-items: center;">
            <!-- 启用滑块 -->
            <div style="display: flex; align-items: center; gap: 8px;">
                <label class="toggle-switch">
                    <input type="checkbox" class="target-enabled" checked>
                    <span class="toggle-slider"></span>
                </label>
                <span style="font-size: 12px; color: #6b7280;">启用</span>
            </div>
            <div>
                <label class="ssl-form-label" style="margin-bottom: 4px; font-size: 12px;">路径</label>
                <input type="text" class="target-path ssl-form-input" value="/" style="padding: 8px;">
            </div>
            <div>
                <label class="ssl-form-label" style="margin-bottom: 4px; font-size: 12px;">目标地址</label>
                <input type="text" class="target-url ssl-form-input" placeholder="http://127.0.0.1:8080" style="padding: 8px;">
            </div>
            <div>
                <label class="ssl-form-label" style="margin-bottom: 4px; font-size: 12px;">Host参数</label>
                <select class="target-host ssl-form-select" style="padding: 8px;">
                    <option value="">默认</option>
                    <option value="$host">$host</option>
                    <option value="$http_host">$http_host</option>
                    <option value="$host:$proxy_port">$host:$proxy_port</option>
                    <option value="$host:$server_port">$host:$server_port</option>
                </select>
            </div>
            <button type="button" class="ssl-btn ssl-btn-danger" onclick="removeProxyTarget(this)" style="padding: 6px 8px; font-size: 11px;">
                <i class="fas fa-trash"></i>
            </button>
        </div>
    `;
        targetsContainer.appendChild(targetItem);
    }
    function removeProxyTarget(button) {
        const targetItems = document.querySelectorAll('.proxy-target-item');
        if (targetItems.length > 1) {
            button.closest('.proxy-target-item').remove();
        } else {
            Swal.showValidationMessage('至少需要保留一个代理目标');
        }
    }
    function uploadCertFile() {
        Swal.fire({
            icon: 'info',
            title: '文件上传功能',
            text: '证书文件上传功能开发中，请先手动输入文件路径'
        });
    }
    function uploadKeyFile() {
        Swal.fire({
            icon: 'info',
            title: '文件上传功能',
            text: '私钥文件上传功能开发中，请先手动输入文件路径'
        });
    }
    function createProxyConfig(config) {
        Swal.fire({
            title: window.I18N.nginx_modal_creating,
            html: window.I18N.nginx_modal_creatingDesc,
            allowOutsideClick: false,
            didOpen: () => {
                Swal.showLoading();
            }
        });
        fetch('/ssl/proxy/create', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [getCsrfHeader()]: getCsrfToken()
            },
            body: JSON.stringify(config)
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    Swal.fire({
                        icon: 'success',
                        title: window.I18N.nginx_toast_createSuccess,
                        text: window.I18N.nginx_toast_createSuccessDesc,
                        timer: 3000
                    });
                    loadProxyList();
                    updateConfigStatus('pending');
                } else {
                    throw new Error(data.message);
                }
            })
            .catch(error => {
                Swal.fire({
                    icon: 'error',
                    title: window.I18N.nginx_toast_createFail,
                    text: error.message || window.I18N.nginx_toast_createFail
                });
            });
    }
    function editProxy(proxyId) {
        // 首先获取当前配置
        fetch('/ssl/proxy/' + proxyId, {
            method: 'GET',
            headers: {
                [getCsrfHeader()]: getCsrfToken()
            }
        })
            .then(response => response.json())
            .then(data => {
                if (!data.success) {
                    throw new Error(data.message);
                }
                showProxyConfigModal({
                    mode: 'edit',
                    proxyId: proxyId,
                    config: data.data
                });
            })
            .catch(error => {
                Swal.fire({
                    icon: 'error',
                    title: window.I18N.nginx_toast_error,
                    text: error.message
                });
            });
    }
    function updateProxyConfig(config) {
        Swal.fire({
            title: window.I18N.nginx_modal_updating,
            allowOutsideClick: false,
            didOpen: () => {
                Swal.showLoading();
            }
        });
        fetch('/ssl/proxy/' + config.id, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                [getCsrfHeader()]: getCsrfToken()
            },
            body: JSON.stringify(config)
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    Swal.fire({
                        icon: 'success',
                        title: window.I18N.nginx_toast_updateSuccess,
                        timer: 2000
                    });
                    loadProxyList();
                    updateConfigStatus('pending');
                } else {
                    throw new Error(data.message);
                }
            })
            .catch(error => {
                Swal.fire({
                    icon: 'error',
                    title: window.I18N.nginx_toast_updateFail,
                    text: error.message
                });
            });
    }
    function showProxyConfigModal(options) {
        const mode = options.mode || 'create';
        const proxyId = options.proxyId;
        const config = options.config || {};

        // 设置默认值
        const currentConfig = {
            domain: config.domain || '',
            protocol: config.protocol || 'http',
            targetHost: config.targetHost || '',
            targetPort: config.targetPort || '',
            enableSsl: config.enableSsl || false,
            enableWebSocket: config.enableWebSocket || false,
            sslCertificateId: config.sslCertificateId || null,
            listenIp: '0.0.0.0',
            listenPort: 443,
            httpToHttps: true,
            redirectPort: 80
        };

        // 解析customConfig中的targets信息（如果有）
        let targets = [];
        try {
            if (config.customConfig) {
                const customData = JSON.parse(config.customConfig);
                if (customData.targets) {
                    targets = customData.targets;
                }
                // 从customConfig中提取额外配置
                if (customData.listenIp) currentConfig.listenIp = customData.listenIp;
                if (customData.listenPort) currentConfig.listenPort = customData.listenPort;
                if (customData.httpToHttps !== undefined) currentConfig.httpToHttps = customData.httpToHttps;
                if (customData.redirectPort) currentConfig.redirectPort = customData.redirectPort;
            }
        } catch (e) {
            // 忽略解析错误
        }

        // 如果没有targets，构建一个默认target
        if (targets.length === 0) {
            if (mode === 'edit' && currentConfig.targetHost) {
                // 编辑模式：从基本配置构建
                targets = [{
                    enabled: true,
                    path: '/',
                    url: currentConfig.protocol + '://' + currentConfig.targetHost + ':' + currentConfig.targetPort,
                    websocket: currentConfig.enableWebSocket,
                    cors: true,
                    host: ''
                }];
            } else {
                // 新增模式：空的默认target
                targets = [{
                    enabled: true,
                    path: '/',
                    url: '',
                    websocket: true,
                    cors: true,
                    host: ''
                }];
            }
        }

        // 构建targets的HTML
        let targetsHtml = '';
        targets.forEach((target, index) => {
            const showDeleteBtn = index > 0 ? '' : 'visibility: hidden;';
            targetsHtml += '<div class="proxy-target-item" style="border: 1px solid #e5e7eb; border-radius: 8px; padding: 15px; margin-bottom: 12px; background: #f9fafb;">' +
                '<div style="display: grid; grid-template-columns: auto 1fr 1fr 1fr auto; gap: 16px; align-items: center;">' +
                '<div style="display: flex; flex-direction: column; align-items: center;">' +
                '<label style="font-size: 11px; color: #6b7280; margin-bottom: 6px; font-weight: 500;">启用</label>' +
                '<label class="toggle-switch">' +
                '<input type="checkbox" class="target-enabled"' + (target.enabled ? ' checked' : '') + '>' +
                '<span class="toggle-slider"></span>' +
                '</label>' +
                '</div>' +
                '<div>' +
                '<label class="ssl-form-label" style="margin-bottom: 4px; font-size: 12px;">路径</label>' +
                '<input type="text" class="target-path ssl-form-input" value="' + (target.path || '/') + '" style="padding: 8px;">' +
                '</div>' +
                '<div>' +
                '<label class="ssl-form-label" style="margin-bottom: 4px; font-size: 12px;">目标地址</label>' +
                '<input type="text" class="target-url ssl-form-input" value="' + (target.url || '') + '" placeholder="http://127.0.0.1:8080" style="padding: 8px;">' +
                '</div>' +
                '<div>' +
                '<label class="ssl-form-label" style="margin-bottom: 4px; font-size: 12px;">Host参数</label>' +
                '<select class="target-host ssl-form-select" style="padding: 8px;">' +
                '<option value=""' + (target.host === '' ? ' selected' : '') + '>默认</option>' +
                '<option value="$host"' + (target.host === '$host' ? ' selected' : '') + '>$host</option>' +
                '<option value="$http_host"' + (target.host === '$http_host' ? ' selected' : '') + '>$http_host</option>' +
                '<option value="$host:$proxy_port"' + (target.host === '$host:$proxy_port' ? ' selected' : '') + '>$host:$proxy_port</option>' +
                '<option value="$host:$server_port"' + (target.host === '$host:$server_port' ? ' selected' : '') + '>$host:$server_port</option>' +
                '</select>' +
                '</div>' +
                '<div style="display: flex; flex-direction: column; align-items: center; justify-content: flex-end; height: 100%;">' +
                '<button type="button" class="ssl-btn ssl-btn-danger" onclick="removeProxyTarget(this)" style="padding: 8px 10px; font-size: 12px; margin-top: 24px; white-space: nowrap;">' +
                '<i class="fas fa-trash"></i> 删除' +
                '</button>' +
                '</div>' +
                '</div>' +
                '</div>';
        });

        // 构建证书选择器的HTML
        let certSelectHtml = '<option value="">-- 请选择证书 --</option><option value="upload">上传证书文件</option>';

        // 使用传统字符串拼接构建表单 HTML（兼容所有环境）
        let htmlContent = '<div style="text-align: left; max-height: 600px; overflow-y: auto;">' +
            '<!-- 两列布局：基础配置 和 证书配置 -->' +
            '<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 30px; margin-bottom: 20px;">' +
            '<!-- 左侧：基础配置 -->' +
            '<div>' +
            '<h4 style="margin: 0 0 15px 0; color: #374151; padding-bottom: 10px; border-bottom: 2px solid #e5e7eb;">基础配置</h4>' +
            '<div class="ssl-form-group">' +
            '<label class="ssl-form-label">转发类型</label>' +
            '<select id="proxyType" class="ssl-form-select">' +
            '<option value="http"' + (currentConfig.protocol === 'http' ? ' selected' : '') + '>HTTP</option>' +
            '<option value="https"' + (currentConfig.protocol === 'https' ? ' selected' : '') + '>HTTPS</option>' +
            '</select>' +
            '</div>' +
            '<div class="ssl-form-group">' +
            '<label class="ssl-form-label">监听IP</label>' +
            '<input type="text" id="listenIp" class="ssl-form-input" value="' + currentConfig.listenIp + '" placeholder="留空或 0.0.0.0">' +
            '</div>' +
            '<div class="ssl-form-group">' +
            '<label class="ssl-form-label">监听端口</label>' +
            '<input type="number" id="listenPort" class="ssl-form-input" value="' + currentConfig.listenPort + '" placeholder="443">' +
            '</div>' +
            '<div class="ssl-form-group">' +
            '<label class="ssl-form-label">监听域名</label>' +
            '<input type="text" id="serverName" class="ssl-form-input" value="' + currentConfig.domain + '" placeholder="例如: api.example.com" required onchange="updateSslPaths()">' +
            '</div>' +
            '<div class="ssl-form-group">' +
            '<label class="ssl-form-label">开启SSL</label>' +
            '<select id="enableSsl" class="ssl-form-select" onchange="toggleSslConfig()">' +
            '<option value="no"' + (!currentConfig.enableSsl ? ' selected' : '') + '>否</option>' +
            '<option value="yes"' + (currentConfig.enableSsl ? ' selected' : '') + '>是</option>' +
            '</select>' +
            '</div>' +
            '</div>' +
            '<!-- 右侧：证书配置 -->' +
            '<div id="sslConfigSection">' +
            '<h4 style="margin: 0 0 15px 0; color: #374151; padding-bottom: 10px; border-bottom: 2px solid #e5e7eb;">证书配置</h4>' +
            '<div class="ssl-form-group">' +
            '<label class="ssl-form-label">选择证书文件 <span style="color: #ef4444;">*</span></label>' +
            '<select id="sslKeyFile" class="ssl-form-select" onchange="handleCertificateChange()" required>' +
            certSelectHtml +
            '</select>' +
            '<div id="certificateInfo" style="display: none; margin-top: 8px; padding: 8px 12px; background: #f0f9ff; border-radius: 6px; font-size: 12px; color: #0369a1;">' +
            '<i class="fas fa-info-circle"></i> <span id="certificateInfoText"></span>' +
            '</div>' +
            '<div id="certificateLoading" style="display: none; margin-top: 8px; color: #6b7280; font-size: 12px;">' +
            '<i class="fas fa-spinner fa-spin"></i> 正在加载匹配的证书...' +
            '</div>' +
            '</div>' +
            '<div class="ssl-form-group">' +
            '<label class="ssl-form-label">证书文件路径 <span style="color: #ef4444;">*</span></label>' +
            '<div style="display: flex; gap: 8px;">' +
            '<input type="text" id="sslCertPath" class="ssl-form-input" placeholder="/path/to/cert.pem" style="flex: 1;" required>' +
            '<button type="button" class="ssl-btn ssl-btn-secondary" onclick="uploadCertFile()" id="uploadCertBtn" style="padding: 8px 12px; font-size: 12px; display: none;">上传</button>' +
            '</div>' +
            '</div>' +
            '<div class="ssl-form-group">' +
            '<label class="ssl-form-label">私钥文件路径 <span style="color: #ef4444;">*</span></label>' +
            '<div style="display: flex; gap: 8px;">' +
            '<input type="text" id="sslKeyPath" class="ssl-form-input" placeholder="/path/to/private.key" style="flex: 1;" required>' +
            '<button type="button" class="ssl-btn ssl-btn-secondary" onclick="uploadKeyFile()" id="uploadKeyBtn" style="padding: 8px 12px; font-size: 12px; display: none;">上传</button>' +
            '</div>' +
            '</div>' +
            '<div style="display: grid; grid-template-columns: 1fr 1fr; gap: 10px;">' +
            '<div class="ssl-form-group">' +
            '<label class="ssl-form-label">HTTP跳转HTTPS</label>' +
            '<select id="httpToHttps" class="ssl-form-select">' +
            '<option value="yes"' + (currentConfig.httpToHttps ? ' selected' : '') + '>是</option>' +
            '<option value="no"' + (!currentConfig.httpToHttps ? ' selected' : '') + '>否</option>' +
            '</select>' +
            '</div>' +
            '<div class="ssl-form-group">' +
            '<label class="ssl-form-label">跳转端口</label>' +
            '<input type="number" id="redirectPort" class="ssl-form-input" placeholder="80" value="' + currentConfig.redirectPort + '">' +
            '</div>' +
            '</div>' +
            '</div>' +
            '</div>' +
            '<!-- 代理目标配置 -->' +
            '<div style="border-top: 2px solid #e5e7eb; padding-top: 20px;">' +
            '<div style="display: flex; justify-content: space-between; align-items: center; margin-bottom: 15px;">' +
            '<h4 style="margin: 0; color: #374151;">代理目标配置</h4>' +
            /*'<button type="button" class="ssl-btn ssl-btn-primary" onclick="addProxyTarget()" style="padding: 6px 12px; font-size: 12px;">' +
            '<i class="fas fa-plus"></i> 添加目标' +
            '</button>' +*/
            '</div>' +
            '<div id="proxyTargets">' +
            targetsHtml +
            '</div>' +
            '<div style="margin-top: 10px; padding: 8px 12px; background: #f0f9ff; border-radius: 6px; font-size: 12px; color: #0369a1;">' +
            '<i class="fas fa-info-circle"></i> WebSocket支持和跨域支持已默认启用' +
            '</div>' +
            '</div>' +
            '</div>';

        Swal.fire({
            title: mode === 'create' ? window.I18N.nginx_modal_proxy_add : window.I18N.nginx_modal_proxy_edit,
            html: htmlContent,
            showCancelButton: true,
            confirmButtonText: mode === 'create' ? window.I18N.nginx_modal_create : window.I18N.nginx_modal_save,
            cancelButtonText: window.I18N.nginx_modal_cancel,
            confirmButtonColor: '#10b981',
            width: '1100px',
            customClass: {
                popup: 'swal-wide-popup'
            },
            didOpen: () => {
                // 新增和编辑都调用证书加载逻辑
                if (currentConfig.enableSsl && currentConfig.domain) {
                    // 如果是编辑模式且有证书ID，加载证书列表后自动选中
                    loadCertificatesForDomain(currentConfig.domain, currentConfig.sslCertificateId);
                } else {
                    // 创建模式：隐藏SSL配置
                    toggleSslConfig();
                }
            },
            preConfirm: () => {
                return collectProxyConfig(mode, proxyId);
            }
        }).then((result) => {
            if (result.isConfirmed) {
                if (mode === 'create') {
                    createProxyConfig(result.value);
                } else {
                    updateProxyConfig(result.value);
                }
            }
        });
    }
    function collectProxyConfig(mode, proxyId) {
        const serverName = document.getElementById('serverName').value;
        const enableSsl = document.getElementById('enableSsl').value === 'yes';
        const targets = [];
        // 收集代理目标配置
        const targetItems = document.querySelectorAll('.proxy-target-item');
        targetItems.forEach(item => {
            const target = {
                enabled: item.querySelector('.target-enabled').checked,
                path: item.querySelector('.target-path').value,
                url: item.querySelector('.target-url').value,
                websocket: true,
                cors: true,
                host: item.querySelector('.target-host').value
            };
            targets.push(target);
        });
        // 验证必填字段
        if (!serverName) {
            Swal.showValidationMessage('请填写监听域名');
            return false;
        }
        const validTargets = targets.filter(t => t.enabled && t.url);
        if (validTargets.length === 0) {
            Swal.showValidationMessage('请至少配置一个有效的代理目标');
            return false;
        }
        // 解析第一个有效目标的URL
        const firstTarget = validTargets[0];
        let targetHost = '';
        let targetPort = 80;
        let protocol = 'http';
        try {
            const url = new URL(firstTarget.url);
            protocol = url.protocol.replace(':', '');
            targetHost = url.hostname;
            targetPort = url.port ? parseInt(url.port) : (protocol === 'https' ? 443 : 80);
        } catch (e) {
            Swal.showValidationMessage('代理目标地址格式不正确，请使用完整URL（如：http://127.0.0.1:8080）');
            return false;
        }
        // 构建后端需要的数据格式
        const config = {
            domain: serverName,
            targetHost: targetHost,
            targetPort: targetPort,
            protocol: protocol,
            enableSsl: enableSsl,
            enableWebSocket: firstTarget.websocket || false
        };
        // 如果是编辑模式，添加ID
        if (mode === 'edit' && proxyId) {
            config.id = proxyId;
        }
        // 如果启用SSL，添加证书相关信息
        if (enableSsl) {
            const sslKeyFile = document.getElementById('sslKeyFile').value;
            const sslCertPath = document.getElementById('sslCertPath').value;
            const sslKeyPath = document.getElementById('sslKeyPath').value;
            if (!sslCertPath || sslCertPath.trim() === '') {
                Swal.showValidationMessage('开启SSL时必须填写证书文件路径');
                return false;
            }
            if (!sslKeyPath || sslKeyPath.trim() === '') {
                Swal.showValidationMessage('开启SSL时必须填写私钥文件路径');
                return false;
            }
            if (!sslKeyFile || sslKeyFile === '') {
                Swal.showValidationMessage('开启SSL时必须选择证书');
                return false;
            }
            if (sslKeyFile !== 'upload') {
                config.sslCertificateId = parseInt(sslKeyFile);
            }
        }
        // 如果有多个目标，将所有目标信息存储到customConfig中
        if (validTargets.length > 1) {
            config.customConfig = JSON.stringify({
                targets: validTargets,
                listenIp: document.getElementById('listenIp').value || '0.0.0.0',
                listenPort: parseInt(document.getElementById('listenPort').value),
                httpToHttps: document.getElementById('httpToHttps').value === 'yes',
                redirectPort: parseInt(document.getElementById('redirectPort').value)
            });
        }
        return config;
    }
    function deleteProxy(proxyId) {
        Swal.fire({
            title: window.I18N.nginx_modal_confirmDelete,
            text: window.I18N.nginx_modal_proxy_deleteConfirm,
            icon: 'warning',
            showCancelButton: true,
            confirmButtonText: window.I18N.nginx_modal_delete,
            cancelButtonText: window.I18N.nginx_modal_cancel,
            confirmButtonColor: '#ef4444'
        }).then((result) => {
            if (result.isConfirmed) {
                // 调用删除API
                fetch(`/ssl/proxy/`+proxyId, {
                    method: 'DELETE',
                    headers: {
                        [getCsrfHeader()]: getCsrfToken()
                    }
                })
                    .then(response => response.json())
                    .then(data => {
                        if (data.success) {
                            Swal.fire({
                                icon: 'success',
                                title: window.I18N.nginx_toast_deleteSuccess,
                                timer: 2000,
                                showConfirmButton: false
                            });
                            loadProxyList();
                            updateConfigStatus('pending');
                        }
                    })
                    .catch(error => {
                        Swal.fire({
                            icon: 'error',
                            title: window.I18N.nginx_toast_deleteFail,
                            text: error.message
                        });
                    });
            }
        });
    }
    function applySslConfig(proxyId) {
        Swal.fire({
            title: window.I18N.nginx_modal_ssl_title,
            html: `
                <div style="text-align: left;">
                    <p style="margin-bottom: 20px; color: #6b7280;">为此域名自动申请并配置SSL证书</p>
                    <div class="ssl-form-group">
                        <label class="ssl-form-label">邮箱地址</label>
                        <input type="email" id="sslEmail" class="ssl-form-input" placeholder="admin@example.com">
                    </div>
                    <div class="ssl-form-group">
                        <label style="display: flex; align-items: center; gap: 8px;">
                            <input type="checkbox" id="autoRenewSsl" checked>
                            <span>启用自动续期</span>
                        </label>
                    </div>
                </div>
            `,
            showCancelButton: true,
            confirmButtonText: window.I18N.nginx_modal_ssl_start,
            cancelButtonText: window.I18N.nginx_modal_cancel,
            confirmButtonColor: '#10b981'
        }).then((result) => {
            if (result.isConfirmed) {
                fetch(`/ssl/proxy/`+ proxyId+`/ssl?email=` + encodeURIComponent(document.getElementById('sslEmail').value), {
                    method: 'POST',
                    headers: {
                        [getCsrfHeader()]: getCsrfToken()
                    }
                })
                    .then(res => res.json())
                    .then(data => {
                        if (data.success) {
                            Swal.fire(window.I18N.nginx_toast_success, window.I18N.nginx_modal_ssl_success, 'success');
                            loadProxyList();
                            loadCertList();
                        } else {
                            throw new Error(data.message);
                        }
                    })
                    .catch(err => Swal.fire(window.I18N.nginx_toast_error, window.I18N.nginx_modal_ssl_fail + ': ' + err.message, 'error'));
            }
        });
    }
    function fixProxyConfig(proxyId) {
        Swal.fire({
            title: '修复配置错误',
            text: '系统将自动检测并修复配置问题',
            icon: 'question',
            showCancelButton: true,
            confirmButtonText: '开始修复',
            cancelButtonText: window.I18N.nginx_modal_cancel
        }).then((result) => {
            if (result.isConfirmed) {
                fetch(`/ssl/proxy/`+ proxyId+`/fix`, {
                    method: 'POST',
                    headers: {
                        [getCsrfHeader()]: getCsrfToken()
                    }
                })
                    .then(res => res.json())
                    .then(data => {
                        if (data.success) {
                            Swal.fire('成功', '配置修复成功', 'success');
                            loadProxyList();
                            updateConfigStatus('pending');
                        } else {
                            throw new Error(data.message);
                        }
                    })
                    .catch(err => Swal.fire('错误', '配置修复失败: ' + err.message, 'error'));
            }
        });
    }
    function refreshProxyList() {
        loadProxyList();
        Swal.fire({
            icon: 'success',
            title: '列表已刷新',
            timer: 1500,
            showConfirmButton: false
        });
    }
    function previewNginxConfig() {
        // 切换到Nginx配置标签
        switchTab('nginx');
    }
    function loadProxyList() {
        fetch('/ssl/proxy/list', {
            method: 'GET',
            headers: {
                [getCsrfHeader()]: getCsrfToken()
            }
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    updateProxyTable(data.data.content || []);
                } else {
                    console.error('加载代理列表失败:', data.message);
                    showEmptyProxyTable();
                }
            })
            .catch(error => {
                console.error('加载代理列表出错:', error);
                showEmptyProxyTable();
            });
    }
    // =================== SSL证书管理功能 ===================
    function showRequestCertModal() {
        Swal.fire({
            title: '申请SSL证书',
            html: '<div style="text-align: left;">' +
                '<div class="ssl-form-group">' +
                '<label class="ssl-form-label">证书类型</label>' +
                '<select id="certType" class="ssl-form-select" onchange="toggleCertTypeOptions()">' +
                '<option value="LETS_ENCRYPT">Let\'s Encrypt (免费，90天有效期)</option>' +
                '</select>' +
                '</div>' +
                '<div class="ssl-form-group">' +
                '<label class="ssl-form-label">域名</label>' +
                '<input type="text" id="certDomain" class="ssl-form-input" placeholder="example.com 或 *.example.com">' +
                '<small style="color: #6b7280;">支持通配符域名</small>' +
                '</div>' +
                '<div class="ssl-form-group">' +
                '<label class="ssl-form-label">邮箱地址 (可选)</label>' +
                '<input type="email" id="certEmail" class="ssl-form-input" placeholder="admin@example.com">' +
                '<small style="color: #6b7280;">用于接收证书通知和紧急联系</small>' +
                '</div>' +
                '<div class="ssl-form-group">' +
                '<label class="ssl-form-label">DNS服务商</label>' +
                '<select id="dnsProvider" class="ssl-form-select" onchange="toggleDnsProviderConfig()">' +
                '<option value="CLOUDFLARE">Cloudflare DNS</option>' +
                '</select>' +
                '</div>' +
                '<!-- Cloudflare DNS配置 -->' +
                '<div id="cloudflareDnsConfig">' +
                '<div style="background: #f0f9ff; padding: 12px; border-radius: 6px; margin-bottom: 15px;">' +
                '<div style="display: flex; align-items: center; gap: 8px; margin-bottom: 8px;">' +
                '<i class="fas fa-info-circle" style="color: #0ea5e9;"></i>' +
                '<strong>Cloudflare DNS API配置</strong>' +
                '</div>' +
                '<p style="margin: 0; font-size: 13px; color: #0369a1;">' +
                '系统将使用已配置的Cloudflare API自动添加验证记录' +
                '</p>' +
                '</div>' +
                '</div>' +
                '<div class="ssl-form-group">' +
                '<label style="display: flex; align-items: center; gap: 8px;">' +
                '<input type="checkbox" id="certAutoRenew" checked>' +
                '<span>启用自动续期</span>' +
                '</label>' +
                '<small style="color: #6b7280;">Let\'s Encrypt将在到期前7天自动续期</small>' +
                '</div>' +
                '</div>',
            showCancelButton: true,
            confirmButtonText: '开始申请',
            cancelButtonText: window.I18N.nginx_modal_cancel,
            confirmButtonColor: '#10b981',
            width: '600px',
            preConfirm: function() {
                return validateAndCollectCertData();
            }
        }).then(function(result) {
            if (result.isConfirmed) {
                requestCertificate(result.value);
            }
        });
    }
    function toggleCertTypeOptions() {
        const certType = document.getElementById('certType').value;
        const letsencryptOptions = document.getElementById('letsencryptOptions');
        const cloudflareOptions = document.getElementById('cloudflareOptions');
        if (certType === 'LETS_ENCRYPT') {
            letsencryptOptions.style.display = 'block';
            cloudflareOptions.style.display = 'none';
        } else if (certType === 'CLOUDFLARE') {
            letsencryptOptions.style.display = 'none';
            cloudflareOptions.style.display = 'block';
        }
    }
    // 切换验证方式
    function toggleValidationMethod() {
        const validation = document.getElementById('certValidation').value;
        const dnsConfig = document.getElementById('dnsValidationConfig');
        if (validation === 'DNS') {
            dnsConfig.style.display = 'block';
        } else {
            dnsConfig.style.display = 'none';
        }
    }
    // 切换DNS提供商配置
    function toggleDnsProviderConfig() {
        const provider = document.getElementById('dnsProvider').value;
        // 隐藏所有配置区域
        const configDivs = ['cloudflareDnsConfig'];
        configDivs.forEach(id => {
            const element = document.getElementById(id);
            if (element) element.style.display = 'none';
        });
        // 显示对应的配置区域
        let configId = null;
        switch(provider) {
            case 'CLOUDFLARE':
                configId = 'cloudflareDnsConfig';
                break;
        }
        if (configId) {
            const element = document.getElementById(configId);
            if (element) element.style.display = 'block';
        }
    }
    function validateAndCollectCertData() {
        const domain = document.getElementById('certDomain').value;
        const email = document.getElementById('certEmail').value;
        const dnsProvider = document.getElementById('dnsProvider').value;
        const autoRenew = document.getElementById('certAutoRenew').checked;
        if (!domain) {
            Swal.showValidationMessage('请填写域名');
            return false;
        }
        const certData = {
            domain: domain,
            certificateType: 'LETS_ENCRYPT',
            email: email,
            dnsProvider: dnsProvider,
            autoRenew: autoRenew
        };
        return certData;
    }
    function requestCertificate(certData) {
        Swal.fire({
            title: '正在申请证书...',
            html: '<div style="text-align: left;">' +
                '<div style="margin-bottom: 10px;">域名: <strong>' + certData.domain + '</strong></div>' +
                '<div style="margin-bottom: 10px;">证书类型: <strong>LETS_ENCRYPT</strong></div>' +
                '<div style="margin-bottom: 20px;">状态: <span id="certProgress">初始化...</span></div>' +
                '<div style="background: #f8fafc; padding: 10px; border-radius: 6px; font-family: monospace; font-size: 12px; max-height: 200px; overflow-y: auto;" id="certLogs"></div>' +
                '</div>',
            allowOutsideClick: false,
            showConfirmButton: false,
            width: '600px'
        });
        fetch('/ssl/certificates/request', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [getCsrfHeader()]: getCsrfToken()
            },
            body: JSON.stringify(certData)
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    // 模拟日志输出
                    const logsEl = document.getElementById('certLogs');
                    const progressEl = document.getElementById('certProgress');
                    const logs = [
                        '[INFO] 开始申请Let\'s Encrypt证书...',
                        '[INFO] 验证域名所有权...',
                        '[INFO] 创建DNS验证记录...',
                        '[INFO] 等待DNS传播...',
                        '[INFO] DNS验证通过',
                        '[INFO] 生成证书请求...',
                        '[INFO] 清理DNS记录...',
                        '[SUCCESS] Let\'s Encrypt证书申请成功！'
                    ];
                    let i = 0;
                    const interval = setInterval(() => {
                        if (i < logs.length) {
                            logsEl.innerHTML += logs[i] + '\n';
                            logsEl.scrollTop = logsEl.scrollHeight;
                            if (i === 0) progressEl.textContent = '验证中...';
                            else if (i === 3) progressEl.textContent = '等待验证...';
                            else if (i === 5) progressEl.textContent = '生成证书...';
                            else if (i === 7) {
                                progressEl.textContent = '完成';
                                clearInterval(interval);
                                setTimeout(() => {
                                    Swal.fire({
                                        icon: 'success',
                                        title: '证书申请成功',
                                        text: 'SSL证书已成功申请并部署',
                                        timer: 3000
                                    });
                                    loadCertList();
                                }, 1000);
                            }
                            i++;
                        }
                    }, 800);
                } else {
                    Swal.fire({
                        icon: 'error',
                        title: '证书申请失败',
                        text: data.message || '申请过程中出现错误'
                    });
                }
            })
            .catch(error => {
                Swal.fire({
                    icon: 'error',
                    title: '证书申请失败',
                    text: '网络错误或服务器异常'
                });
            });
    }
    function renewCert(certId) {
        Swal.fire({
            title: '确认续期证书',
            text: '确定要手动续期此证书吗？',
            icon: 'question',
            showCancelButton: true,
            confirmButtonText: '开始续期',
            cancelButtonText: window.I18N.nginx_modal_cancel,
            confirmButtonColor: '#10b981'
        }).then((result) => {
            if (result.isConfirmed) {
                fetch(`/ssl/certificates/`+ certId+`/renew`, {
                    method: 'POST',
                    headers: {
                        [getCsrfHeader()]: getCsrfToken()
                    }
                })
                    .then(res => res.json())
                    .then(data => {
                        if (data.success) {
                            Swal.fire('成功', '证书续期成功', 'success');
                            loadCertList();
                        } else {
                            throw new Error(data.message);
                        }
                    })
                    .catch(err => Swal.fire('错误', '续期失败: ' + err.message, 'error'));
            }
        });
    }
    function deleteCert(certId) {
        Swal.fire({
            title: '确认删除证书',
            html: `
            <div style="text-align: left;">
                <p style="margin-bottom: 15px;">删除此证书将执行以下操作：</p>
                <ul style="margin-left: 20px; color: #6b7280;">
                    <li>撤销Let's Encrypt证书（如果适用）</li>
                    <li>删除本地证书文件</li>
                    <li>删除数据库记录</li>
                    <li>相关的HTTPS配置可能失效</li>
                </ul>
                <div style="margin-top: 15px; padding: 12px; background: #fee2e2; border-radius: 6px; border-left: 4px solid #ef4444;">
                    <strong style="color: #991b1b;">⚠️ 警告：此操作不可逆</strong>
                </div>
            </div>
        `,
            icon: 'warning',
            showCancelButton: true,
            confirmButtonText: window.I18N.nginx_modal_delete,
            cancelButtonText: window.I18N.nginx_modal_cancel,
            confirmButtonColor: '#ef4444',
            cancelButtonColor: '#6b7280',
            width: '500px'
        }).then((result) => {
            if (result.isConfirmed) {
                fetch(`/ssl/certificates/`+certId, {
                    method: 'DELETE',
                    headers: {
                        [getCsrfHeader()]: getCsrfToken()
                    }
                })
                    .then(res => res.json())
                    .then(data => {
                        if (data.success) {
                            Swal.fire('成功', '证书删除成功', 'success');
                            loadCertList();
                            updateConfigStatus('pending');
                        } else {
                            throw new Error(data.message);
                        }
                    })
                    .catch(err => Swal.fire('错误', '删除失败: ' + err.message, 'error'));
            }
        });
    }
    function toggleAutoRenew(certId, checkbox) {
        const isEnabled = checkbox.checked;
        fetch(`/ssl/certificates/`+ certId+`/auto-renew`, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                [getCsrfHeader()]: getCsrfToken()
            },
            body: JSON.stringify({ enabled: isEnabled })
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    const statusText = isEnabled ? '启用' : '禁用';
                    checkbox.nextElementSibling.textContent = statusText;
                    Swal.fire({
                        icon: 'success',
                        title: `自动续期已`+statusText,
                        timer: 1500,
                        showConfirmButton: false
                    });
                }
            })
            .catch(error => {
                // 恢复复选框状态
                checkbox.checked = !isEnabled;
                Swal.fire({
                    icon: 'error',
                    title: '操作失败',
                    text: error.message
                });
            });
    }
    function refreshCertList() {
        loadCertList();
        Swal.fire({
            icon: 'success',
            title: '状态已刷新',
            timer: 1500,
            showConfirmButton: false
        });
    }
    function loadCertList() {
        fetch('/ssl/certificates/list', {
            method: 'GET',
            headers: {
                [getCsrfHeader()]: getCsrfToken()
            }
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    updateCertTable(data.data.content || []);
                } else {
                    console.error('加载证书列表失败:', data.message);
                    showEmptyCertTable();
                }
            })
            .catch(error => {
                console.error('加载证书列表出错:', error);
                showEmptyCertTable();
            });
    }
    function updateProxyTable(proxies) {
        const tbody = document.getElementById('proxyTableBody');
        if (proxies.length === 0) {
            showEmptyProxyTable();
            return;
        }
        tbody.innerHTML = proxies.map(proxy => {
            const sslCls = proxy.sslStatus === 'CONFIGURED' ? 'active' :
                proxy.sslStatus === 'PENDING' ? 'pending' : 'inactive';
            const cfgCls = proxy.configStatus === 'APPLIED' ? 'active' :
                proxy.configStatus === 'PENDING' ? 'pending' : 'warning';
            return '<tr>' +
                '<td><span class="domain-text">' + proxy.domain + '</span></td>' +
                '<td>' + proxy.protocol + '://' + proxy.targetHost + ':' + proxy.targetPort + '</td>' +
                '<td><span class="status-badge ' + sslCls + '">' + getSslStatusText(proxy.sslStatus) + '</span></td>' +
                '<td><span class="status-badge ' + cfgCls + '">' + getConfigStatusText(proxy.configStatus) + '</span></td>' +
                '<td>' + formatDate(proxy.createTime) + '</td>' +
                '<td>' +
                '<div class="btn-group">' +
                '<button class="btn btn-secondary" style="padding:5px 10px;font-size:12px;" onclick="editProxy(' + proxy.id + ')" title="编辑"><i class="fas fa-edit"></i></button>' +
                '<button class="btn btn-danger" style="padding:5px 10px;font-size:12px;" onclick="deleteProxy(' + proxy.id + ')" title="删除"><i class="fas fa-trash"></i></button>' +
                '</div>' +
                '</td>' +
                '</tr>';
        }).join('');
    }
    function updateCertTable(certificates) {
        const tbody = document.getElementById('certTableBody');
        if (certificates.length === 0) {
            showEmptyCertTable();
            return;
        }
        tbody.innerHTML = certificates.map(cert => {
            const statusCls = cert.status === 'VALID' ? 'active' :
                cert.status === 'PENDING' ? 'pending' : 'warning';
            const certTypeDisplay = cert.certificateType === 'CLOUDFLARE' ? 'Cloudflare Origin CA' : "Let's Encrypt";
            return '<tr>' +
                '<td><span class="domain-text">' + cert.domain + '</span></td>' +
                '<td>' + certTypeDisplay + '</td>' +
                '<td><span class="status-badge ' + statusCls + '">' + getCertStatusText(cert.status) + '</span></td>' +
                '<td>' + (cert.issueDate ? formatDate(cert.issueDate) : '-') + '</td>' +
                '<td>' + (cert.expireDate ? formatDate(cert.expireDate) : '-') + '</td>' +
                '<td>' +
                '<label class="auto-renew-label">' +
                '<input type="checkbox" ' + (cert.autoRenew ? 'checked' : '') + ' onclick="toggleAutoRenew(' + cert.id + ', this)">' +
                '<span>' + (cert.autoRenew ? '已启用' : '已禁用') + '</span>' +
                '</label>' +
                '</td>' +
                '<td>' +
                '<div class="btn-group">' +
                '<button class="btn btn-secondary" style="padding:5px 10px;font-size:12px;" onclick="renewCert(' + cert.id + ')" title="续期"><i class="fas fa-sync"></i></button>' +
                '<button class="btn btn-secondary" style="padding:5px 10px;font-size:12px;" onclick="downloadCertificate(' + cert.id + ',\'' + cert.domain + '\')" title="下载"><i class="fas fa-download"></i></button>' +
                '<button class="btn btn-danger" style="padding:5px 10px;font-size:12px;" onclick="deleteCert(' + cert.id + ')" title="删除"><i class="fas fa-trash"></i></button>' +
                '</div>' +
                '</td>' +
                '</tr>';
        }).join('');
    }
    function showEmptyProxyTable() {
        document.getElementById('proxyTableBody').innerHTML =
            '<tr><td colspan="6"><div class="empty-state"><i class="fas fa-server"></i><h3>暂无反向代理配置</h3><p>点击"添加反向代理"创建第一个配置</p></div></td></tr>';
    }
    function showEmptyCertTable() {
        document.getElementById('certTableBody').innerHTML =
            '<tr><td colspan="7"><div class="empty-state"><i class="fas fa-certificate"></i><h3>暂无SSL证书</h3><p>点击"申请新证书"创建第一个证书</p></div></td></tr>';
    }
    function getSslStatusText(status) {
        //NOT_CONFIGURED, CONFIGURED, PENDING, ERROR
        switch(status) {
            case 'CONFIGURED': return '已配置';
            case 'PENDING': return '配置中';
            case 'NOT_CONFIGURED': return '未配置';
            case 'ERROR': return '配置失败';
            default: return '未配置';
        }
    }
    function getConfigStatusText(status) {
        switch(status) {
            case 'APPLIED': return '已应用';
            case 'PENDING': return '待应用';
            case 'ERROR': return '配置错误';
            default: return '未知';
        }
    }
    function getCertStatusText(status) {
        switch(status) {
            case 'VALID': return '有效';
            case 'PENDING': return '申请中';
            case 'EXPIRED': return '已过期';
            case 'EXPIRING': return '即将过期';
            default: return '未知';
        }
    }
    function formatDate(dateString) {
        if (!dateString) return '-';
        const date = new Date(dateString);
        return date.getFullYear() + '-' +
            String(date.getMonth() + 1).padStart(2, '0') + '-' +
            String(date.getDate()).padStart(2, '0') + ' ' +
            String(date.getHours()).padStart(2, '0') + ':' +
            String(date.getMinutes()).padStart(2, '0');
    }
    // =================== Nginx配置管理功能 ===================
    function applyNginxConfig() {
        Swal.fire({
            title: '确认应用新配置？',
            text: '系统将先测试配置，通过后再应用并重载 Nginx',
            icon: 'question',
            showCancelButton: true,
            confirmButtonText: '确认应用',
            cancelButtonText: window.I18N.nginx_modal_cancel,
            confirmButtonColor: '#10b981'
        }).then(result => {
            if (!result.isConfirmed) return;

            // 第一步：获取 latest 配置 ID
            fetch('/ssl/nginx/latest', {
                method: 'GET',
                headers: { [getCsrfHeader()]: getCsrfToken() }
            })
                .then(res => res.json())
                .then(data => {
                    if (!data.success || !data.data) throw new Error('无法获取最新配置');
                    const latestId = data.data.id;

                    // 第二步：先测试
                    return fetch(`/ssl/nginx/`+ latestId+`/test`, {
                        method: 'POST',
                        headers: { [getCsrfHeader()]: getCsrfToken() }
                    })
                        .then(testRes => testRes.json())
                        .then(testData => {
                            if (!testData.success) {
                                throw new Error('配置测试失败：' + (testData.message || '语法错误'));
                            }

                            // 第三步：测试通过，应用配置
                            return fetch(`/ssl/nginx/`+ latestId+`/apply`, {
                                method: 'POST',
                                headers: { [getCsrfHeader()]: getCsrfToken() }
                            });
                        })
                        .then(applyRes => applyRes.json())
                        .then(applyData => {
                            if (!applyData.success) {
                                throw new Error('应用配置失败：' + applyData.message);
                            }

                            // 第四步：重载 Nginx
                            return fetch('/ssl/nginx/reload', {
                                method: 'POST',
                                headers: { [getCsrfHeader()]: getCsrfToken() }
                            });
                        });
                })
                .then(reloadRes => reloadRes.json())
                .then(reloadData => {
                    if (reloadData.success) {
                        Swal.fire('成功', '配置已应用并重载', 'success');
                        updateConfigStatus('success');
                        loadConfigDiff(); // 刷新状态
                    } else {
                        throw new Error('重载失败：' + reloadData.message);
                    }
                })
                .catch(err => {
                    Swal.fire('错误', err.message, 'error');
                });
        });
    }
    function executeNginxConfigUpdate() {
        Swal.fire({
            title: '正在应用配置...',
            html: `
            <div style="text-align: left;">
                <div id="applyProgress">准备中...</div>
                <div style="background: #f8fafc; padding: 10px; border-radius: 6px; font-family: monospace; font-size: 12px; max-height: 200px; overflow-y: auto; margin-top: 10px;" id="applyLogs"></div>
            </div>
        `,
            allowOutsideClick: false,
            showConfirmButton: false,
            width: '600px'
        });
        fetch('/ssl/nginx/latest', {
            method: 'GET',
            headers: {
                [getCsrfHeader()]: getCsrfToken()
            }
        })
            .then(response => response.json())
            .then(data => {
                if (data.success && data.data) {
                    return applyConfigById(data.data.id);
                } else {
                    throw new Error('无法获取最新配置');
                }
            })
            .catch(error => {
                Swal.fire({
                    icon: 'error',
                    title: '应用失败',
                    text: error.message
                });
            });
    }
    function applyConfigById(configId) {
        updateApplyProgress('正在应用配置...', '开始应用nginx配置');
        return fetch(`/ssl/nginx/`+ configId+`/apply`, {
            method: 'POST',
            headers: {
                [getCsrfHeader()]: getCsrfToken()
            }
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    updateApplyProgress('配置测试中...', '配置文件已更新，正在测试语法');
                    return testAndReloadNginx(configId);
                } else {
                    throw new Error(data.message);
                }
            });
    }
    function testAndReloadNginx(configId) {
        return fetch(`/ssl/nginx/`+ configId+`/test`, {
            method: 'POST',
            headers: {
                [getCsrfHeader()]: getCsrfToken()
            }
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    updateApplyProgress('重载nginx...', '配置测试通过，正在重载nginx');
                    return fetch('/ssl/nginx/reload', {
                        method: 'POST',
                        headers: {
                            [getCsrfHeader()]: getCsrfToken()
                        }
                    });
                } else {
                    throw new Error('配置测试失败');
                }
            })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    updateApplyProgress('完成', '配置已成功应用');
                    setTimeout(() => {
                        Swal.fire({
                            icon: 'success',
                            title: '配置应用成功',
                            text: 'Nginx配置已更新并重载',
                            timer: 3000
                        });
                        updateConfigStatus('success');
                    }, 1000);
                } else {
                    throw new Error(data.message);
                }
            });
    }
    function updateApplyProgress(status, log) {
        const progressEl = document.getElementById('applyProgress');
        const logsEl = document.getElementById('applyLogs');
        if (progressEl) progressEl.textContent = status;
        if (logsEl) {
            logsEl.innerHTML += '[' + new Date().toLocaleTimeString() + '] ' + log + '\n';
            logsEl.scrollTop = logsEl.scrollHeight;
        }
    }
    function testNginxConfig() {
        fetch('/ssl/nginx/latest', {
            method: 'GET',
            headers: { [getCsrfHeader()]: getCsrfToken() }
        })
            .then(res => res.json())
            .then(data => {
                if (!data.success || !data.data) throw new Error('无法获取最新配置ID');
                return fetch(`/ssl/nginx/`+ data.data.id+`/test`, {
                    method: 'POST',
                    headers: { [getCsrfHeader()]: getCsrfToken() }
                });
            })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    Swal.fire('成功', '配置测试通过', 'success');
                } else {
                    Swal.fire('失败', '配置测试失败: ' + data.message, 'error');
                }
            })
            .catch(err => Swal.fire('错误', '测试失败: ' + err.message, 'error'));
    }

    function reloadNginxConfig() {
        Swal.fire({
            title: '确认重载 Nginx？',
            text: '此操作将重载当前已应用的配置',
            icon: 'question',
            showCancelButton: true,
            confirmButtonText: '确认重载',
            cancelButtonText: window.I18N.nginx_modal_cancel
        }).then((result) => {
            if (result.isConfirmed) {
                fetch('/ssl/nginx/reload', {
                    method: 'POST',
                    headers: { [getCsrfHeader()]: getCsrfToken() }
                })
                    .then(res => res.json())
                    .then(data => {
                        if (data.success) {
                            Swal.fire('成功', 'Nginx 已重载', 'success');
                        } else {
                            throw new Error(data.message);
                        }
                    })
                    .catch(err => Swal.fire('错误', '重载失败: ' + err.message, 'error'));
            }
        });
    }

    function refreshConfigDiff() {
        loadConfigDiff();
        Swal.fire({
            icon: 'success',
            title: '配置对比已刷新',
            timer: 1500,
            showConfirmButton: false
        });
    }
    function loadConfigDiff() {
        document.getElementById('currentConfigContent').textContent = '加载中...';
        document.getElementById('latestConfigContent').textContent = '加载中...';
        fetch('/ssl/nginx/diff', {
            method: 'GET',
            headers: { [getCsrfHeader()]: getCsrfToken() }
        })
            .then(res => res.json())
            .then(data => {
                if (data.success) {
                    updateConfigDiff(data.data);
                    updateConfigStatusFromApi(data.data);
                } else {
                    showError('加载配置失败: ' + data.message);
                }
            })
            .catch(err => showError('加载配置失败: ' + err.message));
    }

    function updateConfigStatusFromApi(diffData) {
        const hasChanges = diffData.latest && (
            !diffData.current ||
            diffData.current.id !== diffData.latest.id
        );

        if (hasChanges) {
            // 如果有变更，但尚未测试或测试失败，显示“待测试”
            // 可以从后端获取 testResult 字段来判断
            updateConfigStatus('pending');
        } else if (diffData.current) {
            updateConfigStatus('success');
        } else {
            updateConfigStatus('error');
        }
    }

    function showError(msg) {
        const cur = document.getElementById('currentConfigContent');
        const lat = document.getElementById('latestConfigContent');
        cur.innerHTML = `<div style="color:#ef4444">`+  msg+`</div>`;
        lat.innerHTML = `<div style="color:#ef4444">`+  msg+`</div>`;
    }
    function updateConfigDiff(diffData) {
        const cur = document.getElementById('currentConfigContent');
        const lat = document.getElementById('latestConfigContent');
        cur.textContent = diffData.current?.configContent || '暂无当前配置';
        lat.textContent = diffData.latest?.configContent || '暂无最新配置';
    }

    function showConfigLoadError(errorMessage) {
        document.getElementById('currentConfigContent').innerHTML =
            '<div style="color: #ef4444; font-style: italic;">' + errorMessage + '</div>';
        document.getElementById('latestConfigContent').innerHTML =
            '<div style="color: #ef4444; font-style: italic;">' + errorMessage + '</div>';
    }
    // 更新配置状态
    function updateConfigStatus(status) {
        const statusEl = document.getElementById('configStatus');
        const applyBtn = document.getElementById('applyBtn');
        statusEl.className = 'config-status-bar ' + status;
        if (status === 'pending') {
            statusEl.innerHTML = '<i class="fas fa-exclamation-triangle"></i><span>有未应用的配置更改，请检查并应用新配置</span>';
            if (applyBtn) applyBtn.disabled = false;
        } else if (status === 'success') {
            statusEl.innerHTML = '<i class="fas fa-check-circle"></i><span>配置已是最新状态，无需更改</span>';
            if (applyBtn) applyBtn.disabled = true;
        } else {
            statusEl.innerHTML = '<i class="fas fa-times-circle"></i><span>配置存在错误，请检查并修复</span>';
            if (applyBtn) applyBtn.disabled = true;
        }
    }
    function checkOpenRestyStatus() {
        fetch('/ssl/openresty/status', {
            method: 'GET',
            headers: {
                [getCsrfHeader()]: getCsrfToken()
            }
        })
            .then(response => response.json())
            .then(data => {
                if (!data.success || !data.data.installed) {
                    showOpenRestyNotInstalled();
                } else if (!data.data.running) {
                    showOpenRestyNotRunning();
                } else {
                    hideOpenRestyWarning();
                }
            })
            .catch(error => {
                console.error('检查OpenResty状态失败:', error);
                showOpenRestyNotInstalled();
            });
    }
    function showOpenRestyNotInstalled() {
        var I = window.I18N;
        var el = document.getElementById('openrestyStatus');
        el.style.display = 'flex';
        el.className = 'openresty-status-bar error';
        el.innerHTML =
            '<i class="fas fa-times-circle"></i>' +
            '<span>' + I.nginx_openresty_notInstalled + '</span>' +
            '<button class="btn btn-primary" style="margin-left:auto;" onclick="showInstallGuide()"><i class="fas fa-book"></i> ' + I.nginx_openresty_guide + '</button>' +
            '<button class="btn btn-secondary" onclick="checkOpenRestyStatus()"><i class="fas fa-sync"></i> ' + I.nginx_openresty_recheck + '</button>';
    }
    function showOpenRestyNotRunning() {
        var I = window.I18N;
        var el = document.getElementById('openrestyStatus');
        el.style.display = 'flex';
        el.className = 'openresty-status-bar warning';
        el.innerHTML =
            '<i class="fas fa-exclamation-triangle"></i>' +
            '<span>' + I.nginx_openresty_notRunning + '</span>' +
            '<button class="btn btn-warning" style="margin-left:auto;" onclick="startOpenResty()"><i class="fas fa-play"></i> ' + I.nginx_openresty_start + '</button>';
    }
    function hideOpenRestyWarning() {
        document.getElementById('openrestyStatus').style.display = 'none';
    }
    function showInstallGuide() {
        // 安装脚本路径(相对于本服务,Java 已经把脚本放在 classpath 下;
        // 真实场景下用户在服务器上手动执行,这里只展示命令)
        var SCRIPT = 'enhanced_openresty_v4.sh';
        var WGET   = 'wget -O ' + SCRIPT + ' ' + window.location.origin + '/script/nginx/' + SCRIPT;
        var CURL   = 'curl -fSL -o ' + SCRIPT + ' ' + window.location.origin + '/script/nginx/' + SCRIPT;
        var CHMOD  = 'chmod +x ' + SCRIPT;
        var RUN    = 'sudo ./' + SCRIPT;
        var I = window.I18N;

        var html =
            '<div class="install-guide">' +
              '<div class="ig-step">' +
                '<h4>' + I.nginx_guide_step1_title + '</h4>' +
                '<p>' + I.nginx_guide_step1_desc + '</p>' +
              '</div>' +
              '<div class="ig-step">' +
                '<h4>' + I.nginx_guide_step2_title + '</h4>' +
                '<code class="ig-cmd">' + WGET + '</code>' +
                '<p>' + I.nginx_guide_step2_altCurl + '</p>' +
                '<code class="ig-cmd">' + CURL + '</code>' +
              '</div>' +
              '<div class="ig-step">' +
                '<h4>' + I.nginx_guide_step3_title + '</h4>' +
                '<code class="ig-cmd">' + CHMOD + '</code>' +
              '</div>' +
              '<div class="ig-step">' +
                '<h4>' + I.nginx_guide_step4_title + '</h4>' +
                '<code class="ig-cmd">' + RUN + '</code>' +
              '</div>' +
              '<div class="ig-step">' +
                '<h4><i class="fab fa-docker"></i> ' + I.nginx_guide_docker_title + '</h4>' +
                '<p>' + I.nginx_guide_docker_desc + '</p>' +
                '<code class="ig-cmd">' +
                  'sudo OPENRESTY_API_TOKEN=&lt;your-token&gt; \\\n' +
                  '     API_LISTEN=0.0.0.0:8080 \\\n' +
                  '     API_ALLOWED_CLIENTS="127.0.0.1,172.17.0.0/16" \\\n' +
                  '     ./' + SCRIPT +
                '</code>' +
                '<p>' + I.nginx_guide_docker_appHint + '</p>' +
              '</div>' +
              '<div class="ig-notes">' +
                '<div class="ig-notes-title"><i class="fas fa-info-circle"></i>' + I.nginx_guide_notes + '</div>' +
                '<ul>' +
                  '<li>' + I.nginx_guide_note1 + '</li>' +
                  '<li>' + I.nginx_guide_note2 + '</li>' +
                  '<li>' + I.nginx_guide_note3 + '</li>' +
                '</ul>' +
              '</div>' +
            '</div>';

        Swal.fire({
            title: I.nginx_guide_title,
            html: html,
            width: 680,
            showCancelButton: true,
            confirmButtonText: I.nginx_guide_copy,
            cancelButtonText: I.nginx_guide_close
        }).then(function (result) {
            if (!result.isConfirmed) return;
            navigator.clipboard.writeText(WGET).then(function () {
                Swal.fire({ icon: 'success', title: I.nginx_guide_copied, timer: 1800, showConfirmButton: false });
            }).catch(function () {
                Swal.fire({
                    icon: 'info',
                    title: I.nginx_guide_copied,
                    html: '<code class="ig-cmd">' + WGET + '</code>',
                    confirmButtonText: I.common_confirm || 'OK'
                });
            });
        });
    }
    function startOpenResty() {
        Swal.fire({
            title: '正在启动OpenResty...',
            html: '请稍候，正在启动服务',
            allowOutsideClick: false,
            didOpen: () => {
                Swal.showLoading();
            }
        });
        fetch('/ssl/openresty/start', {
            method: 'POST',
            headers: {
                [getCsrfHeader()]: getCsrfToken()
            }
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    Swal.fire({
                        icon: 'success',
                        title: '服务启动成功',
                        timer: 2000
                    });
                    checkOpenRestyStatus();
                } else {
                    Swal.fire({
                        icon: 'error',
                        title: '启动失败',
                        text: data.message
                    });
                }
            })
            .catch(error => {
                Swal.fire({
                    icon: 'error',
                    title: '启动失败',
                    text: error.message
                });
            });
    }
    /**
     * 复制配置内容到剪贴板
     */
    function copyDiffContent(elementId, btn) {
        const text = document.getElementById(elementId).textContent;
        navigator.clipboard.writeText(text).then(() => {
            btn.innerHTML = '<i class="fas fa-check"></i> 已复制';
            btn.classList.add('copied');
            setTimeout(() => {
                btn.innerHTML = '<i class="fas fa-copy"></i> 复制';
                btn.classList.remove('copied');
            }, 2000);
        }).catch(() => {
            Swal.fire({ icon: 'error', title: '复制失败', text: '请手动选择文本复制', timer: 2000 });
        });
    }
    /**
     * 下载证书
     */
    function downloadCertificate(certificateId, domain) {
        const downloadUrl = '/ssl/certificates/' + certificateId + '/download';
        const link = document.createElement('a');
        link.href = downloadUrl;
        link.download = domain.replace('.', '_') + '_ssl_certificate.zip';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        Swal.fire({
            icon: 'success',
            title: '下载开始',
            text: '证书文件正在下载，请检查浏览器下载目录',
            timer: 2000,
            showConfirmButton: false
        });
    }
</script>
</body>
</html>