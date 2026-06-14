<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="_csrf" content=""/>
    <meta name="_csrf_header" content="X-CSRF-TOKEN"/>
    <title>VPS管理系统 - IP质量检测</title>
    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/app/ip_settings.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/common/custom-select.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <script src="/js/common/custom-select.js"></script>
</head>
<body>
<!-- 引入顶部导航栏 -->
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
        <div class="ip-check-container">
            <!-- 页面标题 -->
            <div class="page-header">
                <h1 class="page-title">
                    <i class="fas fa-network-wired"></i>
                    <span>${msg.get("ip.check")}</span>
                </h1>
            </div>

            <div class="settings-grid">
                <!-- IP质量检测配置 -->
                <div class="settings-card">
                    <div class="settings-card-header">
                        <div class="header-with-toggle">
                            <h3 class="settings-card-title">
                                <i class="fas fa-network-wired"></i>
                                ${msg.get("ip.checkConfig")}
                            </h3>
                            <label class="switch">
                                <input type="checkbox" id="ipCheckEnabled" name="enabled" ${ipCheckConfig.enabled?string('checked', '')}>
                                <span class="slider"></span>
                            </label>
                        </div>
                    </div>
                    <div class="settings-card-body">
                        <form id="ipCheckForm" class="compact-form">
                            <!-- 检测间隔 -->
                            <div class="form-row">
                                <label class="form-label">${msg.get("ip.checkRange")}</label>
                                <div class="form-control-with-tip">
                                    <select class="form-control" name="checkInterval" id="checkInterval"
                                            data-custom-select data-placeholder="${msg.get("ip.selectRange")}">
                                        <#list 1..24 as hour>
                                            <option value="${hour}" <#if hour == ipCheckConfig.checkInterval>selected</#if>>${hour}hour</option>
                                        </#list>
                                    </select>
                                    <div class="form-tip">${msg.get("ip.selectRange")}</div>
                                </div>
                            </div>
                        </form>
                    </div>
                    <div class="settings-card-footer">
                        <button type="button" class="btn btn-sm btn-success" onclick="saveIpCheckConfig()">
                            <i class="fas fa-save"></i>
                            ${msg.get("sys.githubSave")}
                        </button>
                    </div>
                </div>

                <!-- 电信VPS配置 -->
                <div class="settings-card">
                    <div class="settings-card-header">
                        <div class="header-with-toggle">
                            <h3 class="settings-card-title">
                                <i class="fas fa-server"></i>
                                ${msg.get("ip.chnDxConfig")}
                            </h3>
                            <label class="switch">
                                <input type="checkbox" id="telecomEnabled" name="enabled" ${telecomConfig.enabled?string('checked', '')}>
                                <span class="slider"></span>
                            </label>
                        </div>
                    </div>
                    <div class="settings-card-body">
                        <form id="telecomForm" class="compact-form">
                            <div class="form-row">
                                <label class="form-label">${msg.get("ip.address")}</label>
                                <input type="text" class="form-control" name="serverIp" value="${(telecomConfig.serverIp)!''}" placeholder="${msg.get("ip.plzInputAddress")}">
                            </div>

                            <div class="form-row-group">
                                <div>
                                    <label class="form-label">${msg.get("ip.user")}</label>
                                    <input type="text" class="form-control" name="username" value="${(telecomConfig.username)!'root'}" placeholder="${msg.get("ip.sshUser")}">
                                </div>
                                <div>
                                    <label class="form-label">${msg.get("ip.sshPort")}</label>
                                    <input type="number" class="form-control" name="sshPort" value="${(telecomConfig.sshPort)!22}" placeholder="SSH" min="1" max="65535">
                                </div>
                            </div>

                            <div class="form-row">
                                <label class="form-label">${msg.get("ip.sshPass")}</label>
                                <input type="password" class="form-control" name="password" value="${(telecomConfig.password)!''}" placeholder="${msg.get("ip.sshPass")}">
                            </div>
                        </form>
                    </div>
                    <div class="settings-card-footer">
                        <button type="button" class="btn btn-sm btn-info" onclick="testSSHConnection('telecom')">
                            <i class="fas fa-plug"></i> ${msg.get("ip.testConn")}
                        </button>
                        <button type="button" class="btn btn-sm btn-success" onclick="saveVPSConfig('telecom')">
                            <i class="fas fa-save"></i> ${msg.get("notification.save")}
                        </button>
                    </div>
                </div>

                <!-- 联通VPS配置 -->
                <div class="settings-card">
                    <div class="settings-card-header">
                        <div class="header-with-toggle">
                            <h3 class="settings-card-title">
                                <i class="fas fa-server"></i>
                                ${msg.get("ip.chnLtConfig")}
                            </h3>
                            <label class="switch">
                                <input type="checkbox" id="unicomEnabled" name="enabled" ${unicomConfig.enabled?string('checked', '')}>
                                <span class="slider"></span>
                            </label>
                        </div>
                    </div>
                    <div class="settings-card-body">
                        <form id="unicomForm" class="compact-form">
                            <div class="form-row">
                                <label class="form-label">${msg.get("ip.address")}</label>
                                <input type="text" class="form-control" name="serverIp" value="${(unicomConfig.serverIp)!''}" placeholder="${msg.get("ip.plzInputAddress")}">
                            </div>

                            <div class="form-row-group">
                                <div>
                                    <label class="form-label">${msg.get("ip.user")}</label>
                                    <input type="text" class="form-control" name="username" value="${(unicomConfig.username)!'root'}" placeholder="${msg.get("ip.sshUser")}">
                                </div>
                                <div>
                                    <label class="form-label">${msg.get("ip.sshPort")}</label>
                                    <input type="number" class="form-control" name="sshPort" value="${(unicomConfig.sshPort)!22}" placeholder="${msg.get("ip.sshPort")}" min="1" max="65535">
                                </div>
                            </div>

                            <div class="form-row">
                                <label class="form-label">${msg.get("ip.sshPass")}</label>
                                <input type="password" class="form-control" name="password" value="${(unicomConfig.password)!''}" placeholder="${msg.get("ip.sshPass")}">
                            </div>
                        </form>
                    </div>
                    <div class="settings-card-footer">
                        <button type="button" class="btn btn-sm btn-info" onclick="testSSHConnection('unicom')">
                            <i class="fas fa-plug"></i> ${msg.get("ip.testConn")}
                        </button>
                        <button type="button" class="btn btn-sm btn-success" onclick="saveVPSConfig('unicom')">
                            <i class="fas fa-save"></i> ${msg.get("notification.save")}
                        </button>
                    </div>
                </div>

                <!-- 移动VPS配置 -->
                <div class="settings-card">
                    <div class="settings-card-header">
                        <div class="header-with-toggle">
                            <h3 class="settings-card-title">
                                <i class="fas fa-server"></i>
                                ${msg.get("ip.chnYdConfig")}
                            </h3>
                            <label class="switch">
                                <input type="checkbox" id="mobileEnabled" name="enabled" ${mobileConfig.enabled?string('checked', '')}>
                                <span class="slider"></span>
                            </label>
                        </div>
                    </div>
                    <div class="settings-card-body">
                        <form id="mobileForm" class="compact-form">
                            <div class="form-row">
                                <label class="form-label">${msg.get("ip.address")}</label>
                                <input type="text" class="form-control" name="serverIp" value="${(mobileConfig.serverIp)!''}" placeholder="${msg.get("ip.address")}">
                            </div>

                            <div class="form-row-group">
                                <div>
                                    <label class="form-label">${msg.get("ip.user")}</label>
                                    <input type="text" class="form-control" name="username" value="${(mobileConfig.username)!'root'}" placeholder="${msg.get("ip.sshUser")}">
                                </div>
                                <div>
                                    <label class="form-label">${msg.get("ip.sshPort")}</label>
                                    <input type="number" class="form-control" name="sshPort" value="${(mobileConfig.sshPort)!22}" placeholder="${msg.get("ip.sshPort")}" min="1" max="65535">
                                </div>
                            </div>

                            <div class="form-row">
                                <label class="form-label">${msg.get("ip.sshPass")}</label>
                                <input type="password" class="form-control" name="password" value="${(mobileConfig.password)!''}" placeholder="${msg.get("ip.sshPass")}">
                            </div>
                        </form>
                    </div>
                    <div class="settings-card-footer">
                        <button type="button" class="btn btn-sm btn-info" onclick="testSSHConnection('mobile')">
                            <i class="fas fa-plug"></i> ${msg.get("ip.testConn")}
                        </button>
                        <button type="button" class="btn btn-sm btn-success" onclick="saveVPSConfig('mobile')">
                            <i class="fas fa-save"></i> ${msg.get("notification.save")}
                        </button>
                    </div>
                </div>
            </div>
        </div>
    </main>
</div>

<!-- Toast提示 -->
<div id="toast" class="toast" style="display: none;">
    <div class="toast-content">
        <i class="fas fa-check-circle toast-icon"></i>
        <span id="toastMessage"></span>
    </div>
</div>

<#include "common/version_info.ftl">
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script>
    // Toast提示函数
    function showToast(message, type = 'success') {
        const toast = document.getElementById('toast');
        const toastMessage = document.getElementById('toastMessage');

        toastMessage.textContent = message;
        toast.className = `toast ` + type;
        toast.style.display = 'block';

        setTimeout(() => {
            toast.style.display = 'none';
        }, 3000);
    }

    // 保存IP质量检测配置
    async function saveIpCheckConfig() {
        const enabled = document.getElementById('ipCheckEnabled').checked;
        const checkInterval = document.getElementById('checkInterval').value;

        try {

            const csrfHeader = document.querySelector('meta[name="_csrf_header"]').getAttribute('content');
            const csrfToken = document.querySelector('meta[name="_csrf"]').getAttribute('content');

            const headers = {
                'Content-Type': 'application/json'
            };
            headers[csrfHeader] = csrfToken;

            const response = await fetch('/api/system/updateIpCheckConfig', {
                method: 'POST',
                headers: headers,
                body: JSON.stringify({
                    enabled: enabled,
                    checkInterval: parseInt(checkInterval)
                })
            });

            if (!response.ok) {
                throw new Error(await response.text() || 'error');
            }

            showSuccess();
        } catch (error) {
            showError();
        }
    }

    // 保存VPS配置
    async function saveVPSConfig(type) {
        const form = document.getElementById(type + `Form`);
        const enabled = document.getElementById(type + `Enabled`).checked;

        const config = {
            type: type,
            enabled: enabled,
            serverIp: form.querySelector('input[name="serverIp"]').value,
            username: form.querySelector('input[name="username"]').value,
            sshPort: parseInt(form.querySelector('input[name="sshPort"]').value),
            password: form.querySelector('input[name="password"]').value
        };

        if (enabled && (!config.serverIp || !config.username || !config.password)) {
            Swal.fire({
                icon: 'warning',
                title: 'warning',
                text: '${msg.get("notification.plzInputGlobalInfo")}',
                confirmButtonText: '${msg.get("mfa.action.confirm")}'
            });
            return;
        }

        try {

            const csrfHeader = document.querySelector('meta[name="_csrf_header"]').getAttribute('content');
            const csrfToken = document.querySelector('meta[name="_csrf"]').getAttribute('content');

            const headers = {
                'Content-Type': 'application/json'
            };
            headers[csrfHeader] = csrfToken;

            const response = await fetch('/system/vps/saveConfig', {
                method: 'POST',
                headers: headers,
                body: JSON.stringify(config)
            });

            if (!response.ok) {
                throw new Error(await response.text() || 'error');
            }
            showSuccess();
        } catch (error) {
            showError();
        }
    }

    // 测试SSH连接
    async function testSSHConnection(type) {
        const form = document.getElementById(type + `Form`);

        const config = {
            type: type,
            serverIp: form.querySelector('input[name="serverIp"]').value,
            username: form.querySelector('input[name="username"]').value,
            sshPort: parseInt(form.querySelector('input[name="sshPort"]').value),
            password: form.querySelector('input[name="password"]').value
        };

        if (!config.serverIp || !config.username || !config.password) {
            Swal.fire({
                icon: 'warning',
                title: 'warn',
                text: '${msg.get("notification.plzInputGlobalInfo")}',
                confirmButtonText: '${msg.get("mfa.action.confirm")}'
            });
            return;
        }

        try {

            const csrfHeader = document.querySelector('meta[name="_csrf_header"]').getAttribute('content');
            const csrfToken = document.querySelector('meta[name="_csrf"]').getAttribute('content');

            const headers = {
                'Content-Type': 'application/json'
            };
            headers[csrfHeader] = csrfToken;

            const response = await fetch('/system/vps/testConnection', {
                method: 'POST',
                headers: headers,
                body: JSON.stringify(config)
            });

            if (!response.ok) {
                throw new Error(await response.text() || 'error');
            }

            showSuccess();
        } catch (error) {
            showError();
        }
    }

    // 侧边栏展开/收起
    document.addEventListener('DOMContentLoaded', function() {
        const navParents = document.querySelectorAll('.nav-parent');
        navParents.forEach(parent => {
            const parentLink = parent.querySelector('.nav-link');
            parentLink.addEventListener('click', (e) => {
                e.preventDefault();
                parent.classList.toggle('expanded');
            });
        });

        // 展开当前活动菜单
        const activeLink = document.querySelector('.nav-link.active');
        if (activeLink) {
            const parent = activeLink.closest('.nav-parent');
            if (parent) {
                parent.classList.add('expanded');
            }
        }
    });

    function showError(){
        Swal.fire({
            icon: 'error',
            title: '${msg.get("common.network.error")}',
            text: 'error',
            confirmButtonText: '${msg.get("mfa.action.confirm")}'
        });
    }

    function showSuccess(){
        Swal.fire({
            icon: 'success',
            title: 'success',
            text: '${msg.get("common.confirmUpdateSuccess")}',
            timer: 1500,
            showConfirmButton: false
        });
    }
</script>
</body>
</html>