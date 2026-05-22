<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - API管理详情</title>
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/app/oci_instance_detail.css">
    <script src="/js/common/jquery.min.js"></script>

</head>
<body>
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <main class="main-content">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-server"></i>
                <span>API管理详情</span>
            </h1>
        </div>

        <!-- Tab导航 -->
        <div class="tab-navigation">
            <button class="tab-button active" onclick="switchTab('instances')">
                <i class="fas fa-microchip"></i> 实例管理列表
            </button>
            <button class="tab-button" onclick="switchTab('volumes')">
                <i class="fas fa-hdd"></i> 引导卷管理列表
            </button>
        </div>

        <!-- 实例管理列表 -->
        <div id="instances-tab" class="tab-content active">
            <table class="detail-table">
                <thead>
                <tr>
                    <th>实例名称</th>
                    <th>状态</th>
                    <th>规格</th>
                    <th>IP地址</th>
                    <th>可用区</th>
                    <th>创建时间</th>
                    <th>操作</th>
                </tr>
                </thead>
                <tbody>
                <#list instanceDetailsRes as instance>
                    <tr>
                        <td>${instance.displayName!'-'}</td>
                        <td>
                                <span class="status-badge ${instance.lifecycleState!'UNKNOWN'}">
                                    ${instance.lifecycleState!'未知状态'}
                                </span>
                        </td>
                        <td>${instance.shape!'-'}</td>
                        <td>
                            <div>
                                <div>公网: ${instance.publicIps!'0.0.0.0'}</div>
                                <div>私网: ${instance.privateIps!'0.0.0.0'}</div>
                            </div>
                        </td>
                        <td>${instance.availabilityDomain!'空'}</td>
                        <td>${instance.timeCreated}</td>
                        <td>
                            <div class="btn-group">
                                <button class="btn btn-success btn-icon" title="修改配置"
                                        onclick="handleUpdateConfig('${instance.id}', ${instance.ocpus}, ${instance.memoryInGBs})">
                                    <i class="fas fa-cog"></i>
                                </button>
                                <button class="btn btn-danger btn-icon" title="切换IP"
                                        onclick="handleChangeIp('${instance.id}')">
                                    <i class="fas fa-sync"></i>
                                </button>
                                <button class="btn btn-primary btn-icon" title="开启IPv6"
                                        onclick="handleChangeIpv6('${instance.id}')">
                                    <i class="fas fa-network-wired"></i>
                                </button>
                                <button class="btn btn-info btn-icon" title="修改实例名称"
                                        onclick="handleUpdateName('${instance.id}', '${instance.displayName}')">
                                    <i class="fas fa-edit"></i>
                                </button>
                                <button class="btn btn-primary btn-icon" title="修改引导卷大小"
                                        onclick="handleUpdateBootVolume('${instance.id}', ${instance.bootVolumeSizeInGBs})">
                                    <i class="fas fa-hdd"></i>
                                </button>
                                <button class="btn btn-danger btn-icon" title="终止实例"
                                        onclick="handleTerminateInstance('${instance.id}')">
                                    <i class="fas fa-stop-circle"></i>
                                </button>
                            </div>
                        </td>
                    </tr>
                </#list>
                </tbody>
            </table>
        </div>
        <!-- 引导卷管理列表 -->
        <div id="volumes-tab" class="tab-content">
            <table class="detail-table">
                <thead>
                <tr>
                    <th>引导卷名称</th>
                    <th>大小(GB)</th>
                    <th>状态</th>
                    <th>所属实例</th>
                    <th>创建时间</th>
                    <th>操作</th>
                </tr>
                </thead>
                <tbody>
                <#list instanceDetailsRes as instance>
                    <tr>
                        <td>${instance.displayName!'-'} 的引导卷</td>
                        <td>${instance.bootVolumeSizeInGBs!'0'}</td>
                        <td>
                                <span class="status-badge ${instance.lifecycleState!'UNKNOWN'}">
                                    ${instance.lifecycleState!'未知状态'}
                                </span>
                        </td>
                        <td>${instance.displayName!'-'}</td>
                        <td>${instance.timeCreated}</td>
                        <td>
                            <div class="btn-group">
                                <button class="btn btn-primary btn-icon" title="修改配置"
                                        onclick="handleUpdateBootVolume('${instance.id}', ${instance.bootVolumeSizeInGBs})">
                                    <i class="fas fa-edit"></i>
                                </button>
                                <button class="btn btn-info btn-icon" title="详情">
                                    <i class="fas fa-info-circle"></i>
                                </button>
                            </div>
                        </td>
                    </tr>
                </#list>
                </tbody>
            </table>
        </div>

        <!-- 分页部分 -->
        <div class="pagination">
            <#if (currentPage > 0)>
                <a href="?page=${currentPage - 1}&tenantId=${tenantId}" class="btn btn-primary">
                    <i class="fas fa-chevron-left"></i> 上一页
                </a>
            </#if>
            <#if currentPage < (totalPages - 1)>
                <a href="?page=${currentPage + 1}&tenantId=${tenantId}" class="btn btn-primary">
                    下一页 <i class="fas fa-chevron-right"></i>
                </a>
            </#if>

            <div class="pagination-info">
                第 ${currentPage + 1} 页，共 ${totalPages} 页
            </div>
        </div>
    </main>
</div>

<!-- 实例配置修改模态框 -->
<div id="updateConfigModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">修改实例配置</h3>
        </div>
        <div id="updateConfigContent">
            <div style="margin-bottom: 20px;">
                <div style="margin-bottom: 15px;">
                    <label style="display: block; margin-bottom: 5px;">CPU核心数</label>
                    <input type="number"
                           id="cpuInput"
                           min="1"
                           max="24"
                           step="1"
                           style="width: 100%; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px;">
                </div>
                <div style="margin-bottom: 15px;">
                    <label style="display: block; margin-bottom: 5px;">内存大小 (GB)</label>
                    <input type="number"
                           id="memoryInput"
                           min="1"
                           max="256"
                           step="1"
                           style="width: 100%; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px;">
                </div>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmUpdateConfig()">
                    <i class="fas fa-check"></i> 确认修改
                </button>
                <button class="btn btn-danger" onclick="closeUpdateConfigModal()">
                    <i class="fas fa-times"></i> 取消
                </button>
            </div>

            <div id="updateConfigMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="updateConfigText"></span>
            </div>
        </div>
    </div>
</div>
<!-- IP切换模态框 -->
<div id="changeIpModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">IP切换设置</h3>
        </div>
        <div id="changeIpContent">
            <div class="cidr-input-container" style="margin-bottom: 20px;">
                <div class="cidr-list" id="cidrList">
                    <div class="cidr-item" style="display: flex; gap: 10px; margin-bottom: 10px;">
                        <input type="text"
                               class="cidr-input"
                               placeholder="请输入CIDR (例如: 10.0.0.0/24)"
                               style="flex: 1; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px;">
                    </div>
                </div>
                <button class="btn btn-primary"
                        onclick="addCidrInput()"
                        style="margin-bottom: 15px;">
                    <i class="fas fa-plus"></i> 添加CIDR
                </button>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmChangeIp()">
                    <i class="fas fa-check"></i> 确认切换
                </button>
                <button class="btn btn-danger" onclick="closeModal()">
                    <i class="fas fa-times"></i> 取消
                </button>
            </div>

            <div id="changeIpMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="changeIpText"></span>
            </div>

            <!-- 添加在这里 -->
            <div id="changeIpDetails" style="display: none;">
                <div id="changeIpDetailsList"></div>
            </div>
        </div>
    </div>
</div>

<!-- IPv6设置模态框 -->
<div id="ipv6Modal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">IPv6设置</h3>
        </div>
        <div id="ipv6Content">
            <div style="margin-bottom: 20px;">
                <p>确认要为此实例开启IPv6吗？</p>
                <p style="font-size: 12px; color: var(--text-secondary);">开启后将自动分配IPv6地址</p>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmEnableIpv6()">
                    <i class="fas fa-check"></i> 确认开启
                </button>
                <button class="btn btn-danger" onclick="closeIpv6Modal()">
                    <i class="fas fa-times"></i> 取消
                </button>
            </div>

            <div id="ipv6Message" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="ipv6Text"></span>
            </div>
        </div>
    </div>
</div>

<!-- 实例名称修改模态框 -->
<div id="updateNameModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">修改实例名称</h3>
        </div>
        <div id="updateNameContent">
            <div style="margin-bottom: 20px;">
                <div style="margin-bottom: 15px;">
                    <label style="display: block; margin-bottom: 5px;">实例名称</label>
                    <input type="text"
                           id="instanceNameInput"
                           placeholder="请输入新的实例名称"
                           style="width: 100%; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px;">
                </div>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmUpdateName()">
                    <i class="fas fa-check"></i> 确认修改
                </button>
                <button class="btn btn-danger" onclick="closeUpdateNameModal()">
                    <i class="fas fa-times"></i> 取消
                </button>
            </div>

            <div id="updateNameMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="updateNameText"></span>
            </div>
        </div>
    </div>
</div>
<!-- 引导卷大小修改模态框 -->
<div id="updateBootVolumeModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">修改引导卷大小</h3>
        </div>
        <div id="updateBootVolumeContent">
            <div style="margin-bottom: 20px;">
                <div id="volumeChangeWarning" class="status-message" style="display: none; margin-bottom: 15px;">
                </div>
                <div style="margin-bottom: 15px;">
                    <label style="display: block; margin-bottom: 5px;">当前大小: <span id="currentSizeDisplay"></span> GB</label>
                    <label style="display: block; margin-bottom: 5px;">引导卷大小 (GB)</label>
                    <input type="number"
                           id="bootVolumeSizeInput"
                           min="47"
                           step="1"
                           style="width: 100%; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px;"
                           oninput="validateVolumeSize(this.value)">
                    <small style="color: var(--text-secondary);">最小值: 47GB</small>
                </div>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmUpdateBootVolume()" id="confirmButton">
                    <i class="fas fa-check"></i> 确认修改
                </button>
                <button class="btn btn-danger" onclick="closeUpdateBootVolumeModal()">
                    <i class="fas fa-times"></i> 取消
                </button>
            </div>

            <div id="updateBootVolumeMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="updateBootVolumeText"></span>
            </div>
        </div>
    </div>
</div>

<!-- 终止实例模态框 -->
<div id="terminateInstanceModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">终止实例</h3>
        </div>
        <div id="terminateInstanceContent">
            <div id="confirmStep" style="margin-bottom: 20px;">
                <div style="margin-bottom: 15px;">
                    <p style="color: var(--accent-red); font-weight: bold;">警告：此操作将永久删除实例及其数据，且不可恢复！</p>
                </div>
                <div style="display: flex; gap: 10px;">
                    <button class="btn btn-danger" onclick="requestVerificationCode()">
                        <i class="fas fa-check"></i> 确认继续
                    </button>
                    <button class="btn btn-primary" onclick="closeTerminateModal()">
                        <i class="fas fa-times"></i> 取消
                    </button>
                </div>
            </div>

            <div id="verifyStep" style="display: none;">
                <div style="margin-bottom: 15px;">
                    <input type="text"
                           id="verificationCodeInput"
                           placeholder="请输入验证码"
                           style="width: 100%; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px; margin-bottom: 10px;">
                </div>
                <div style="display: flex; gap: 10px;">
                    <button class="btn btn-danger" onclick="confirmTermination()">
                        <i class="fas fa-check"></i> 验证并终止
                    </button>
                    <button class="btn btn-primary" onclick="closeTerminateModal()">
                        <i class="fas fa-times"></i> 取消
                    </button>
                </div>
            </div>

            <div id="terminateMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="terminateText"></span>
            </div>
        </div>
    </div>
</div>

<#--<#include "common/version_info.ftl">-->
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script>
    // Tab切换功能
    function switchTab(tabName) {
        document.querySelectorAll('.tab-content').forEach(tab => {
            tab.classList.remove('active');
        });
        document.querySelectorAll('.tab-button').forEach(button => {
            button.classList.remove('active');
        });
        document.getElementById(tabName + '-tab').classList.add('active');
        event.currentTarget.classList.add('active');
    }

    // 修改配置相关函数
    function handleUpdateConfig(instanceId, currentCpu, currentMemory) {
        const modal = document.getElementById('updateConfigModal');
        const cpuInput = document.getElementById('cpuInput');
        const memoryInput = document.getElementById('memoryInput');
        const statusMessage = document.getElementById('updateConfigMessage');

        // 设置当前值
        cpuInput.value = currentCpu;
        memoryInput.value = currentMemory;
        modal.setAttribute('data-instance-id', instanceId);
        statusMessage.style.display = 'none';
        modal.style.display = 'flex';
    }

    function confirmUpdateConfig() {
        const modal = document.getElementById('updateConfigModal');
        const instanceId = modal.getAttribute('data-instance-id');
        const newCpu = document.getElementById('cpuInput').value;
        const newMemory = document.getElementById('memoryInput').value;
        const statusMessage = document.getElementById('updateConfigMessage');
        const statusText = document.getElementById('updateConfigText');

        if (!newCpu || !newMemory) {
            statusMessage.className = 'status-message error';
            statusMessage.style.display = 'block';
            statusText.textContent = '请填写完整的配置信息';
            return;
        }

        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = "正在更新配置...";

        const xhr = new XMLHttpRequest();
        const csrfToken = document.querySelector('input[name="_csrf"]').value;

        xhr.open('POST', '/oci/updateConfig', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = '配置更新成功';
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 2000);
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent = data.message || '配置更新失败';
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = '请求失败，请重试';
                }
            }
        };

        xhr.send(JSON.stringify({
            instanceId: instanceId,
            cpu: newCpu,
            memory: newMemory
        }));
    }

    function closeUpdateConfigModal() {
        document.getElementById('updateConfigModal').style.display = 'none';
    }

    // IP切换相关函数
    function handleChangeIp(instanceId) {
        const modal = document.getElementById('changeIpModal');
        const cidrList = document.getElementById('cidrList');
        cidrList.innerHTML = `
            <div class="cidr-item" style="display: flex; gap: 10px; margin-bottom: 10px;">
                <input type="text"
                       class="cidr-input"
                       placeholder="请输入CIDR (例如: 10.0.0.0/24)"
                       style="flex: 1; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px;">
            </div>
        `;

        const statusMessage = document.getElementById('changeIpMessage');
        const changeIpDetails = document.getElementById('changeIpDetails');
        statusMessage.style.display = 'none';
        if (changeIpDetails) {
            changeIpDetails.style.display = 'none';
        }

        modal.setAttribute('data-instance-id', instanceId);
        modal.style.display = 'flex';
    }
    function addCidrInput() {
        const cidrList = document.getElementById('cidrList');
        const newInput = document.createElement('div');
        newInput.className = 'cidr-item';
        newInput.style = 'display: flex; gap: 10px; margin-bottom: 10px;';
        newInput.innerHTML = `
            <input type="text"
                   class="cidr-input"
                   placeholder="请输入CIDR (例如: 10.0.0.0/24)"
                   style="flex: 1; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px;">
            <button class="btn btn-danger btn-icon"
                    onclick="this.parentElement.remove()"
                    style="padding: 8px;">
                <i class="fas fa-trash"></i>
            </button>
        `;
        cidrList.appendChild(newInput);
    }

    function confirmChangeIp() {
        const modal = document.getElementById('changeIpModal');
        const instanceId = modal.getAttribute('data-instance-id');
        const statusMessage = document.getElementById('changeIpMessage');
        const statusText = document.getElementById('changeIpText');
        const changeIpDetails = document.getElementById('changeIpDetails');

        // 收集所有CIDR输入
        const cidrInputs = document.querySelectorAll('.cidr-input');
        const cidrRanges = Array.from(cidrInputs)
            .map(input => input.value.trim())
            .filter(value => value !== '');

        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = "正在切换IP...";

        const xhr = new XMLHttpRequest();
        const csrfToken = document.querySelector('input[name="_csrf"]').value;

        xhr.open('POST', '/oci/changeSpecIp', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);

                    if (data.status === 'success') {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = data.message || 'Operation successful';

                        if (data.details) {
                            changeIpDetails.style.display = 'block';
                            const detailsList = document.getElementById('changeIpDetailsList');
                            detailsList.innerHTML = '<div class="instance-info-item">' +
                                '<div><span class="info-label">原IP: </span>' + data.details.oldIp + '</div>' +
                                '<div><span class="info-label">新IP: </span>' + data.details.newIp + '</div>' +
                                '</div>';
                        }

                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        throw new Error(data.message || 'IP切换失败');
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = '请求失败，请重试';
                }
            }
        };

        xhr.onerror = function() {
            statusMessage.className = 'status-message error';
            statusText.textContent = 'IP切换失败，请重试';
        };

        xhr.send(JSON.stringify({
            instanceId: instanceId,
            cidrRanges: cidrRanges
        }));
    }

    function closeModal() {
        document.getElementById('changeIpModal').style.display = 'none';
    }

    // IPv6相关函数
    function handleChangeIpv6(instanceId) {
        const modal = document.getElementById('ipv6Modal');
        const statusMessage = document.getElementById('ipv6Message');
        const ipv6Details = document.getElementById('ipv6Details');

        statusMessage.style.display = 'none';
        ipv6Details.style.display = 'none';

        modal.setAttribute('data-instance-id', instanceId);
        modal.style.display = 'flex';
    }

    function confirmEnableIpv6() {
        const modal = document.getElementById('ipv6Modal');
        const instanceId = modal.getAttribute('data-instance-id');
        const statusMessage = document.getElementById('ipv6Message');
        const statusText = document.getElementById('ipv6Text');
        const ipv6Details = document.getElementById('ipv6Details');

        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = "正在开启IPv6...";

        const xhr = new XMLHttpRequest();
        const csrfToken = document.querySelector('input[name="_csrf"]').value;

        xhr.open('POST', '//oci/enableIpv6', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);

                    if (data.status === 'success') {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = data.message || 'IPv6开启成功';

                        if (data.details) {
                            ipv6Details.style.display = 'block';
                            const detailsList = document.getElementById('ipv6DetailsList');
                            detailsList.innerHTML = '<div class="instance-info-item">' +
                                '<div><span class="info-label">IPv6地址: </span>' + data.details.ipv6Address + '</div>' +
                                '</div>';
                        }

                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        throw new Error(data.message || 'IPv6开启失败');
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = '请求失败，请重试';
                }
            }
        };

        xhr.send(JSON.stringify({
            instanceId: instanceId
        }));
    }

    function closeIpv6Modal() {
        document.getElementById('ipv6Modal').style.display = 'none';
    }
    // 实例名称修改相关函数
    function handleUpdateName(instanceId, currentName) {
        const modal = document.getElementById('updateNameModal');
        const nameInput = document.getElementById('instanceNameInput');
        const statusMessage = document.getElementById('updateNameMessage');

        nameInput.value = currentName;
        modal.setAttribute('data-instance-id', instanceId);
        statusMessage.style.display = 'none';
        modal.style.display = 'flex';
    }

    function confirmUpdateName() {
        const modal = document.getElementById('updateNameModal');
        const instanceId = modal.getAttribute('data-instance-id');
        const newName = document.getElementById('instanceNameInput').value.trim();
        const statusMessage = document.getElementById('updateNameMessage');
        const statusText = document.getElementById('updateNameText');

        if (!newName) {
            statusMessage.className = 'status-message error';
            statusMessage.style.display = 'block';
            statusText.textContent = '请输入实例名称';
            return;
        }

        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = "正在更新实例名称...";

        const xhr = new XMLHttpRequest();
        const csrfToken = document.querySelector('input[name="_csrf"]').value;

        xhr.open('POST', '/oci/updateName', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = '名称更新成功';
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 2000);
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent = data.message || '名称更新失败';
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = '请求失败，请重试';
                }
            }
        };

        xhr.send(JSON.stringify({
            instanceId: instanceId,
            newName: newName
        }));
    }

    function closeUpdateNameModal() {
        document.getElementById('updateNameModal').style.display = 'none';
    }

    // 引导卷相关函数
    let currentVolumeSize = 0;

    function handleUpdateBootVolume(instanceId, currentSize) {
        const modal = document.getElementById('updateBootVolumeModal');
        const sizeInput = document.getElementById('bootVolumeSizeInput');
        const currentSizeDisplay = document.getElementById('currentSizeDisplay');
        const volumeChangeWarning = document.getElementById('volumeChangeWarning');
        const statusMessage = document.getElementById('updateBootVolumeMessage');

        currentVolumeSize = currentSize;
        currentSizeDisplay.textContent = currentSize;
        sizeInput.value = currentSize;
        modal.setAttribute('data-instance-id', instanceId);

        volumeChangeWarning.style.display = 'none';
        statusMessage.style.display = 'none';

        validateVolumeSize(currentSize);
        modal.style.display = 'flex';
    }

    function validateVolumeSize(newSize) {
        const warning = document.getElementById('volumeChangeWarning');
        const confirmButton = document.getElementById('confirmButton');
        newSize = parseInt(newSize);

        if (newSize < 47) {
            warning.className = 'status-message error';
            warning.style.display = 'block';
            warning.textContent = '引导卷大小不能小于47GB';
            confirmButton.disabled = true;
            return false;
        }

        if (newSize < currentVolumeSize) {
            warning.className = 'status-message error';
            warning.style.display = 'block';
            warning.innerHTML = '<i class="fas fa-exclamation-triangle"></i> 警告：您正在进行缩小操作，这可能会导致数据丢失！请确保已备份重要数据。';
            confirmButton.disabled = false;
        } else if (newSize > currentVolumeSize) {
            warning.className = 'status-message success';
            warning.style.display = 'block';
            warning.innerHTML = '<i class="fas fa-info-circle"></i> 您正在进行扩容操作。';
            confirmButton.disabled = false;
        } else {
            warning.style.display = 'none';
            confirmButton.disabled = true;
        }

        return true;
    }

    function confirmUpdateBootVolume() {
        const modal = document.getElementById('updateBootVolumeModal');
        const instanceId = modal.getAttribute('data-instance-id');
        const newSize = parseInt(document.getElementById('bootVolumeSizeInput').value);
        const statusMessage = document.getElementById('updateBootVolumeMessage');
        const statusText = document.getElementById('updateBootVolumeText');

        if (!validateVolumeSize(newSize)) {
            return;
        }

        const isExpand = newSize >= currentVolumeSize;

        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = isExpand ? "正在扩容引导卷..." : "正在缩小引导卷...";

        const xhr = new XMLHttpRequest();
        const csrfToken = document.querySelector('input[name="_csrf"]').value;

        xhr.open('POST', '/oci/updateBootVolume', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = isExpand ? '引导卷扩容成功' : '引导卷缩小成功';
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 2000);
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent = data.message || (isExpand ? '引导卷扩容失败' : '引导卷缩小失败');
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = '请求失败，请重试';
                }
            }
        };

        xhr.send(JSON.stringify({
            instanceId: instanceId,
            bootVolumeSize: newSize,
            expand: isExpand
        }));
    }

    function closeUpdateBootVolumeModal() {
        document.getElementById('updateBootVolumeModal').style.display = 'none';
    }
    // 终止实例相关函数
    function handleTerminateInstance(instanceId) {
        const modal = document.getElementById('terminateInstanceModal');
        const confirmStep = document.getElementById('confirmStep');
        const verifyStep = document.getElementById('verifyStep');
        const statusMessage = document.getElementById('terminateMessage');

        // 重置模态框状态
        confirmStep.style.display = 'block';
        verifyStep.style.display = 'none';
        statusMessage.style.display = 'none';

        // 存储实例ID
        modal.setAttribute('data-instance-id', instanceId);
        modal.style.display = 'flex';
    }

    function requestVerificationCode() {
        const modal = document.getElementById('terminateInstanceModal');
        const instanceId = modal.getAttribute('data-instance-id');
        const confirmStep = document.getElementById('confirmStep');
        const statusMessage = document.getElementById('terminateMessage');
        const statusText = document.getElementById('terminateText');

        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = "正在发送验证码...";

        const xhr = new XMLHttpRequest();
        const csrfToken = document.querySelector('input[name="_csrf"]').value;

        xhr.open('POST', '/oci/sendVerificationCode', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        confirmStep.style.display = 'none';
                        document.getElementById('verifyStep').style.display = 'block';
                        statusMessage.style.display = 'none';
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent = data.message || '发送验证码失败';
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = '请求失败，请重试';
                }
            }
        };

        xhr.send(JSON.stringify({
            instanceId: instanceId
        }));
    }

    function confirmTermination() {
        const modal = document.getElementById('terminateInstanceModal');
        const instanceId = modal.getAttribute('data-instance-id');
        const verificationCode = document.getElementById('verificationCodeInput').value.trim();
        const statusMessage = document.getElementById('terminateMessage');
        const statusText = document.getElementById('terminateText');

        if (!verificationCode) {
            statusMessage.className = 'status-message error';
            statusMessage.style.display = 'block';
            statusText.textContent = '请输入验证码';
            return;
        }

        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = "正在终止实例...";

        const xhr = new XMLHttpRequest();
        const csrfToken = document.querySelector('input[name="_csrf"]').value;

        xhr.open('POST', '/oci/terminateInstance', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = data.message || '实例终止成功';

                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent = data.message || '终止实例失败';
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = '请求失败，请重试';
                }
            }
        };

        xhr.send(JSON.stringify({
            instanceId: instanceId,
            verificationCode: verificationCode
        }));
    }

    function closeTerminateModal() {
        document.getElementById('terminateInstanceModal').style.display = 'none';
    }

    // 页面初始化
    document.addEventListener('DOMContentLoaded', function() {
        // Tab切换初始化
        const tabButtons = document.querySelectorAll('.tab-button');
        tabButtons.forEach(button => {
            button.addEventListener('click', (e) => {
                const tabName = e.target.getAttribute('data-tab');
                switchTab(tabName);
            });
        });

        // 模态框外部点击关闭
        const modals = document.querySelectorAll('.modal-overlay');
        modals.forEach(modal => {
            modal.addEventListener('click', (e) => {
                if (e.target === modal) {
                    modal.style.display = 'none';
                }
            });
        });

        // 引导卷大小输入验证
        const bootVolumeSizeInput = document.getElementById('bootVolumeSizeInput');
        if (bootVolumeSizeInput) {
            bootVolumeSizeInput.addEventListener('input', (e) => {
                validateVolumeSize(e.target.value);
            });
        }
    });
</script>

</body>
</html>