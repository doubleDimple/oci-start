<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - OCI实例管理(待统计功能)</title>
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <script>function _getCsrfToken(){var i=document.querySelector('input[name="_csrf"]');if(i)return i.value;var m=document.querySelector('meta[name="_csrf"]');return m?(m.getAttribute('content')||''):''}</script>
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/common/fa-fix.css">
    <link rel="stylesheet" href="/css/styles.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/app/oci_machine_total_list.css">
    <!-- SweetAlert2 CSS -->
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <!-- SweetAlert2 JS -->
    <script src="/js/sweetalert2.min.js"></script>

    <#include "common/pagination.ftl" />

</head>
<body>
<#--<#include "common/version_info.ftl">-->

<#--<#include "common/header.ftl" />-->

<div class="layout">

    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-cloud"></i>
                <span>OCI实例管理</span>
            </h1>
            <div class="view-actions">
                <!-- 添加搜索框 -->
                <!-- 级联下拉搜索框 -->
                <div class="filter-controls" style="padding: 15px;">
                    <div class="filter-item">
                        <label class="filter-label">请选择：</label>
                        <div class="cascade-container">
                            <div class="cascade-selects">
                                <select id="tenantSelect" class="form-select cascade-select" onchange="loadRegions()">
                                    <option value="">请选择租户</option>
                                    <!-- 租户选项将通过JavaScript动态加载 -->
                                </select>
                                <select id="regionSelect" class="form-select cascade-select" onchange="regionChanged()" disabled>
                                    <option value="">请选择区域</option>
                                    <!-- 区域选项将通过JavaScript动态加载 -->
                                </select>
                            </div>
                            <button id="goToInstanceBtn" class="btn btn-primary" onclick="goToInstances()" disabled>
                                <i class="fas fa-search"></i> 查看实例
                            </button>
                        </div>
                    </div>
                </div>
                <div class="view-toggle">
                    <button class="btn active" onclick="switchView('table')">
                        <i class="fas fa-list"></i>
                    </button>
                    <button class="btn" onclick="switchView('grid')">
                        <i class="fas fa-th-large"></i>
                    </button>
                </div>
            </div>
        </div>

        <!-- Table View -->
        <div class="table-view">
            <table class="table">
                <thead>
                <tr>
                    <th>备注</th>
                    <#--<th>所属API</th>-->
                    <th>所属区域</th>
                    <th>实例名称</th>
                    <#--<th>实例镜像</th>-->
                    <#--<th>实例状态</th>-->
                    <th>CPU/内存</th>
                    <th>架构</th>
                    <th style="min-width: 70px; width: 70px;">磁盘</th>
                    <th>主IPV4</th>
                    <#--<th>私有IP</th>-->
                    <th>IPV6</th>
                    <th>操作</th>
                </tr>
                </thead>
                <tbody>
                <#list instanceDetailsRes as instance>
                    <tr>
                        <#--<td><span class="truncate" onclick="toggleText(this)" data-fulltext="${instance.id}">${instance.id}</span></td>-->
                        <!-- 备注列 -->
                        <td class="data-cell">
                            <div class="data-content">
                                <span class="data-text truncate" onclick="toggleText(this)" data-fulltext="${instance.remark!'无'}">${instance.remark!'无'}</span>
                                <a href="#" class="action-link edit" onclick="handleUpdateRemark('${instance.id}', '${instance.remark!}')" title="修改备注">
                                    <i class="fas fa-edit"></i>
                                </a>
                            </div>
                        </td>

                        <!-- 所属区域列 -->
                        <td>
                            <a href="/tenants/regionList?tenantId=${instance.tenantIdStr}">
                                <span class="truncate" onclick="toggleText(this)" data-fulltext="${instance.tenantId}">${instance.userName}</span>
                            </a>
                        </td>

                        <!-- 实例名称列 -->
                        <td class="data-cell">
                            <div class="data-content">
                                <div class="instance-name-container">
                                    <!-- 根据实例状态显示不同的状态指示器 -->
                                    <#if instance.state?lower_case == "running">
                                        <span class="status-indicator status-running" title="运行中"></span>
                                    <#elseif instance.state?lower_case == "stopped">
                                        <span class="status-indicator status-stopped" title="已停止"></span>
                                    <#elseif instance.state?lower_case == "starting">
                                        <span class="status-indicator status-starting" title="启动中"></span>
                                    <#elseif instance.state?lower_case == "stopping">
                                        <span class="status-indicator status-stopping" title="停止中"></span>
                                    <#elseif instance.state?lower_case == "terminated" || instance.state?lower_case == "terminating">
                                        <span class="status-indicator status-terminated" title="已终止"></span>
                                    <#else>
                                        <span class="status-indicator status-stopped" title="未知状态"></span>
                                    </#if>

                                    <span class="data-text truncate" onclick="toggleText(this)" data-fulltext="${instance.displayName}">${instance.displayName}</span>
                                </div>
                                <a href="#" class="action-link edit" onclick="handleUpdateName('${instance.id}', '${instance.displayName}')" title="修改实例名称">
                                    <i class="fas fa-edit"></i>
                                </a>
                            </div>
                        </td>

                        <!-- 实例状态列 -->
                        <#--<td>
                            <span class="truncate" onclick="toggleText(this)" data-fulltext="${instance.state}">${instance.state}</span>
                        </td>-->

                        <!-- CPU/内存列 -->
                        <td class="data-cell" style="min-width: 70px; width: 70px;">
                            <div class="data-content">
                                <span class="data-text truncate cpu-memory-text" onclick="toggleText(this)" data-fulltext="${instance.cpuAndMem}">${instance.cpuAndMem}</span>
                                <a href="#" class="action-link config" onclick="handleUpdateConfig('${instance.id}', ${instance.ocpus}, ${instance.memoryInGBs})" title="修改配置">
                                    <i class="fas fa-cog"></i>
                                </a>
                            </div>
                        </td>

                        <!-- 架构列 -->
                        <td>
                            <span class="truncate" onclick="toggleText(this)" data-fulltext="${instance.architecture}">${instance.architecture}</span>
                        </td>

                        <!-- 磁盘列 -->
                        <td class="data-cell" style="min-width: 90px; width: 90px;">
                            <div class="data-content">
                                <span class="data-text truncate storage-text" onclick="toggleText(this)" data-fulltext="${instance.bootVolumeSizeInGBs}GB">${instance.bootVolumeSizeInGBs}GB</span>
                                <a href="#" class="action-link storage" onclick="handleUpdateBootVolume('${instance.id}', ${instance.bootVolumeSizeInGBs})" title="修改引导卷大小">
                                    <i class="fas fa-hdd"></i>
                                </a>
                            </div>
                        </td>

                        <!-- IPV4列 -->
                        <td class="data-cell">
                            <div class="data-content">
                                <span class="data-text truncate ip-text" onclick="toggleText(this)" data-fulltext="${instance.publicIps}">${instance.publicIps}</span>
                                <a href="#" class="action-link copy" onclick="copyToClipboard('${instance.publicIps}', this)" title="复制IP地址">
                                    <i class="fas fa-copy"></i>
                                </a>
                                <a href="#" class="action-link danger" onclick="handleChangeIp('${instance.id}')" title="切换IP">
                                    <i class="fas fa-sync-alt"></i>
                                </a>
                            </div>
                        </td>

                        <!-- IPV6列 -->
                        <td class="data-cell">
                            <#if instance.ipv6Addresses?? && instance.ipv6Addresses?trim != "">
                                <div class="data-content">
                                    <span class="data-text truncate ip-text" onclick="toggleText(this)" data-fulltext="${instance.ipv6Addresses}">已启用</span>
                                    <a href="#" class="action-link copy" onclick="copyToClipboard('${instance.ipv6Addresses}', this)" title="复制IPv6地址">
                                        <i class="fas fa-copy"></i>
                                    </a>
                                    <a href="#" class="action-link network" onclick="handleChangeIpv6('${instance.id}')" title="管理IPv6">
                                        <i class="fas fa-network-wired"></i>
                                    </a>
                                </div>
                            <#else>
                                <div class="data-content">
                                    <span class="data-text ipv6-empty">未开启</span>
                                    <a href="#" class="action-link network" onclick="handleChangeIpv6('${instance.id}')" title="开启IPv6">
                                        <i class="fas fa-plus-circle"></i>
                                    </a>
                                </div>
                            </#if>
                        </td>


                        <td class="actions-cell">
                            <div style="display: none;">
                            </div>
                            <div class="btn-group">
                                <!-- 启动/停止按钮 -->
                                <#if instance.state?lower_case == "stopped">
                                    <button class="btn btn-success btn-icon" title="启动实例" onclick="handleStartInstance('${instance.id}')">
                                        <i class="fas fa-play"></i>
                                    </button>
                                <#elseif instance.state?lower_case == "running">
                                    <button class="btn btn-warning btn-icon" title="停止实例" onclick="handleStopInstance('${instance.id}')">
                                        <i class="fas fa-stop"></i>
                                    </button>
                                </#if>

                                <!-- 终止实例 -->
                                <button class="btn btn-danger btn-icon" title="终止实例" onclick="handleTerminateInstance('${instance.id}')">
                                    <i class="fas fa-stop-circle"></i>
                                </button>

                                <!-- SSH连接 -->
                                <a href="/oci/terminal?instanceId=${instance.id}">
                                    <button class="btn btn-primary btn-icon" title="SSH连接">
                                        <i class="fas fa-terminal"></i>
                                    </button>
                                </a>

                                <!-- 系统救援 -->
                                <#--<a href="/oci/sysHelp?instanceId=${instance.id}">
                                    <button class="btn btn-info btn-icon" title="系统救援">
                                        <i class="fas fa-life-ring"></i>
                                    </button>
                                </a>-->
                                <a href="/oci/console/terminal/${instance.id}">
                                    <button class="btn btn-success btn-icon" title="Cloud Shell控制台">
                                        <i class="fas fa-desktop"></i>
                                    </button>
                                </a>
                                <!-- 网络管理 -->
                                <a href="/oci/vnic/manage?instanceId=${instance.instanceId}">
                                    <button class="btn btn-primary btn-icon" title="网络管理">
                                        <i class="fas fa-network-wired"></i>
                                    </button>
                                </a>
                            </div>
                        </td>
                    </tr>
                </#list>
                </tbody>
            </table>
        </div>

        <!-- Grid View -->
        <div class="grid-view">
            <div style="display: none;">
            </div>
            <#list instanceDetailsRes as instance>
                <div class="instance-card">
                    <div class="instance-card-header">
                        <div class="instance-icon">
                            <i class="fas fa-server"></i>
                        </div>
                        <div class="instance-title">
                            <div class="instance-name">${instance.displayName}</div>
                            <div class="instance-id">${instance.id}</div>
                        </div>
                    </div>

                    <div class="instance-content">
                        <div class="instance-info-item">
                            <span class="info-label">所属API:</span>
                            <span class="info-value">${instance.userName}</span>
                        </div>
                        <div class="instance-info-item">
                            <span class="info-label">状态:</span>
                            <span class="info-value">${instance.state}</span>
                        </div>
                        <div class="instance-info-item">
                            <span class="info-label">配置:</span>
                            <span class="info-value">
                                CPU: ${instance.ocpus} /
                                内存: ${instance.memoryInGBs}GB /
                                磁盘: ${instance.bootVolumeSizeInGBs}GB
                            </span>
                        </div>

                        <#--<div class="instance-info-item">
                            <span class="info-label">IP:</span>
                            <span class="info-value">
                                公网IP: ${instance.publicIps} /
                                私网IP: ${instance.privateIps}
                            </span>
                        </div>-->
                        <div class="instance-info-item">
                            <span class="info-label">公网IP:</span>
                            <span class="info-value">${instance.publicIps}</span>
                        </div>
                        <div class="instance-info-item">
                            <span class="info-label">私网IP:</span>
                            <span class="info-value">${instance.privateIps}</span>
                        </div>
                        <#--<div class="instance-info-item">
                            <span class="info-label">备注:</span>
                            <div style="display: flex; align-items: center; gap: 4px; min-width: 0; flex: 1;">
                                <span class="info-value" style="flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;">${instance.remark!'无'}</span>
                                <button class="btn btn-icon" title="修改备注" onclick="handleUpdateRemark('${instance.id}', '${instance.remark!}')" style="background: none; padding: 2px; flex-shrink: 0;">
                                    <i class="fas fa-edit" style="color: #666; font-size: 12px;"></i>
                                </button>
                            </div>
                        </div>-->
                        <div class="instance-info-item">
                            <span class="info-label">可用域:</span>
                            <span class="info-value">${instance.availabilityDomain}</span>
                        </div>
                    </div>

                    <div class="instance-actions">
                        <button class="btn btn-success btn-icon" title="修改配置" onclick="handleUpdateConfig('${instance.id}', ${instance.ocpus}, ${instance.memoryInGBs})">
                            <i class="fas fa-cog"></i>
                        </button>
                        <button class="btn btn-danger btn-icon" title="切换IP" onclick="handleChangeIp('${instance.id}')">
                            <i class="fas fa-sync"></i>
                        </button>
                        <button class="btn btn-primary btn-icon" title="开启IPv6" onclick="handleChangeIpv6('${instance.id}')">
                            <i class="fas fa-network-wired"></i>
                        </button>
                        <button class="btn btn-info btn-icon" title="修改实例名称" onclick="handleUpdateName('${instance.id}', '${instance.displayName}')">
                            <i class="fas fa-edit"></i>
                        </button>
                        <button class="btn btn-primary btn-icon" title="修改引导卷大小" onclick="handleUpdateBootVolume('${instance.id}', ${instance.bootVolumeSizeInGBs})">
                            <i class="fas fa-hdd"></i>
                        </button>
                        <!-- 新增启动/停止按钮，根据实例状态显示 -->
                        <#if instance.state?lower_case == "stopped">
                            <button class="btn btn-success btn-icon" title="启动实例" onclick="handleStartInstance('${instance.id}')">
                                <i class="fas fa-play"></i>
                            </button>
                        <#elseif instance.state?lower_case == "running">
                            <button class="btn btn-warning btn-icon" title="停止实例" onclick="handleStopInstance('${instance.id}')">
                                <i class="fas fa-stop"></i>
                            </button>
                        </#if>
                        <!-- 新增终止按钮 -->
                        <button class="btn btn-danger btn-icon" title="终止实例" onclick="handleTerminateInstance('${instance.id}')">
                            <i class="fas fa-stop-circle"></i>
                        </button>
                    </div>
                </div>
            </#list>
        </div>

        <!-- Pagination -->
        <#--<div class="pagination">
            <#if (currentPage > 0)>
                <a href="/oci/list?page=${currentPage - 1}&size=20" class="btn btn-primary">
                    <i class="fas fa-arrow-left"></i> 上一页
                </a>
            </#if>
            <#if currentPage < (totalPages - 1)>
                <a href="/oci/list?page=${currentPage + 1}&size=20" class="btn btn-primary">
                    下一页 <i class="fas fa-arrow-right"></i>
                </a>
            </#if>
        </div>-->
        <@pagination
        url="/oci/list"
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
    </main>
</div>

<!-- Change IP Modal -->
<!-- 修改 Change IP Modal 部分 -->
<div id="changeIpModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">IP切换设置</h3>
        </div>
        <div id="changeIpContent">
            <!-- 添加 CIDR 输入区域 -->
            <div class="cidr-input-container" style="margin-bottom: 20px;">
                <div class="cidr-list" id="cidrList">
                    <div class="cidr-item" style="display: flex; gap: 10px; margin-bottom: 10px;">
                        <input type="text"
                               class="cidr-input"
                               placeholder="请输入CIDR (例如: 10.0.0.0/24)"
                               style="flex: 1; padding: 8px; border: 1px solid #e0e0e0; border-radius: 3px;">
                    </div>
                </div>
                <button class="btn btn-primary"
                        onclick="addCidrInput()"
                        style="margin-bottom: 15px;">
                    <i class="fas fa-plus"></i> 添加CIDR
                </button>
            </div>

            <!-- 操作按钮 -->
            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmChangeIp()">
                    <i class="fas fa-check"></i> 确认切换
                </button>
                <button class="btn btn-danger" onclick="closeModal()">
                    <i class="fas fa-times"></i> 取消
                </button>
            </div>

            <!-- 状态消息区域 -->
            <div id="changeIpMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="changeIpText"></span>
            </div>
            <div id="changeIpDetails" style="display: none;">
                <div id="changeIpDetailsList"></div>
            </div>
        </div>
    </div>
</div>

<!-- 在changeIpModal后添加 -->
<div id="ipv6Modal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">IPv6设置</h3>
        </div>
        <div id="ipv6Content">
            <div style="margin-bottom: 20px;">
                <p>确认要为此实例开启IPv6吗？</p>
                <p style="font-size: 12px; color: var(--text-secondary);">开启后将自动分配IPv6地址(如未生效, 请重启实例即可)</p>
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
            <div id="ipv6Details" style="display: none;">
                <div id="ipv6DetailsList"></div>
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
            <!-- 第一步：确认提示 -->
            <div id="confirmStep" style="margin-bottom: 20px;">
                <div style="margin-bottom: 15px;">
                    <p style="color: #ff6b6b; font-weight: bold;">警告：此操作将永久删除实例及其数据，且不可恢复！</p>
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

            <!-- 第二步：验证码输入 -->
            <div id="verifyStep" style="display: none;">
                <div style="margin-bottom: 15px;">
                    <input type="text"
                           id="verificationCodeInput"
                           placeholder="请输入验证码"
                           style="width: 100%; padding: 8px; border: 1px solid #e0e0e0; border-radius: 3px; margin-bottom: 10px;">
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

            <!-- 状态消息区域 -->
            <div id="terminateMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="terminateText"></span>
            </div>
        </div>
    </div>
</div>

<!-- 添加修改配置的模态框 -->
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
                           style="width: 100%; padding: 8px; border: 1px solid #e0e0e0; border-radius: 3px;">
                </div>
                <div style="margin-bottom: 15px;">
                    <label style="display: block; margin-bottom: 5px;">内存大小 (GB)</label>
                    <input type="number"
                           id="memoryInput"
                           min="1"
                           max="256"
                           step="1"
                           style="width: 100%; padding: 8px; border: 1px solid #e0e0e0; border-radius: 3px;">
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

<!-- 添加修改实例名称的模态框 -->
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
                           style="width: 100%; padding: 8px; border: 1px solid #e0e0e0; border-radius: 3px;">
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

<!-- 修改引导卷大小的模态框 -->
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
                           style="width: 100%; padding: 8px; border: 1px solid #e0e0e0; border-radius: 3px;"
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

<!-- 修改备注的模态框 -->
<div id="updateRemarkModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">修改备注</h3>
        </div>
        <div id="updateRemarkContent">
            <div style="margin-bottom: 20px;">
                <div style="margin-bottom: 15px;">
                    <label style="display: block; margin-bottom: 5px;">备注内容</label>
                    <textarea id="remarkInput"
                              placeholder="请输入备注内容"
                              style="width: 100%; padding: 8px; border: 1px solid #e0e0e0; border-radius: 3px; min-height: 100px;"></textarea>
                </div>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmUpdateRemark()">
                    <i class="fas fa-check"></i> 确认修改
                </button>
                <button class="btn btn-danger" onclick="closeUpdateRemarkModal()">
                    <i class="fas fa-times"></i> 取消
                </button>
            </div>

            <div id="updateRemarkMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="updateRemarkText"></span>
            </div>
        </div>
    </div>
</div>

<!-- 3. 添加启动实例的模态框 -->
<div id="startInstanceModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">启动实例</h3>
        </div>
        <div id="startInstanceContent">
            <div style="margin-bottom: 20px;">
                <p>确认要启动此实例吗？</p>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmStartInstance()">
                    <i class="fas fa-check"></i> 确认启动
                </button>
                <button class="btn btn-danger" onclick="closeStartInstanceModal()">
                    <i class="fas fa-times"></i> 取消
                </button>
            </div>

            <div id="startInstanceMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="startInstanceText"></span>
            </div>
        </div>
    </div>
</div>

<!-- 4. 添加停止实例的模态框 -->
<div id="stopInstanceModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">停止实例</h3>
        </div>
        <div id="stopInstanceContent">
            <div style="margin-bottom: 20px;">
                <p>确认要停止此实例吗？</p>
                <p style="font-size: 12px; color: var(--text-secondary);">停止实例后，您可以随时重新启动它。</p>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmStopInstance()">
                    <i class="fas fa-check"></i> 确认停止
                </button>
                <button class="btn btn-danger" onclick="closeStopInstanceModal()">
                    <i class="fas fa-times"></i> 取消
                </button>
            </div>

            <div id="stopInstanceMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="stopInstanceText"></span>
            </div>
        </div>
    </div>
</div>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script>

    function showLoading(title) {
        Swal.fire({
            title: title,
            allowOutsideClick: false,
            didOpen: () => {
                Swal.showLoading();
            }
        });
    }

    function showSuccess(title, text) {
        Swal.fire({
            icon: 'success',
            title: title,
            text: text,
            timer: 2000,
            showConfirmButton: false
        });
    }

    function showError(title, text) {
        Swal.fire({
            icon: 'error',
            title: title,
            text: text
        });
    }

    // 视图切换功能
    function switchView(view) {
        const tableView = document.querySelector('.table-view');
        const gridView = document.querySelector('.grid-view');
        const buttons = document.querySelectorAll('.view-toggle .btn');

        buttons.forEach(btn => btn.classList.remove('active'));
        if (view === 'table') {
            buttons[0].classList.add('active');
            tableView.style.display = 'block';
            gridView.style.display = 'none';
        } else {
            buttons[1].classList.add('active');
            tableView.style.display = 'none';
            gridView.style.display = 'grid';
        }

        localStorage.setItem('preferredView', view);
    }

    // 文本截断切换
    function toggleText(element) {
        const fullText = element.getAttribute('data-fulltext');
        const isTruncated = element.getAttribute('data-truncated') === 'true';

        if (isTruncated) {
            element.textContent = fullText.length > 15 ? fullText.substring(0, 15) + '...' : fullText;
            element.setAttribute('data-truncated', 'false');
        } else {
            element.textContent = fullText;
            element.setAttribute('data-truncated', 'true');
        }
    }

    // IP切换处理
    function handleChangeIp(instanceId) {
        const modal = document.getElementById('changeIpModal');
        // 清空之前的 CIDR 输入
        const cidrList = document.getElementById('cidrList');
        cidrList.innerHTML = `
            <div class="cidr-item" style="display: flex; gap: 10px; margin-bottom: 10px;">
                <input type="text"
                       class="cidr-input"
                       placeholder="请输入CIDR (例如: 10.0.0.0/24)"
                       style="flex: 1; padding: 8px; border: 1px solid #e0e0e0; border-radius: 3px;">
            </div>
        `;

        // 重置状态消息
        const statusMessage = document.getElementById('changeIpMessage');
        const changeIpDetails = document.getElementById('changeIpDetails');
        statusMessage.style.display = 'none';
        changeIpDetails.style.display = 'none';

        // 存储实例ID供后续使用
        modal.setAttribute('data-instance-id', instanceId);

        // 显示模态框
        modal.style.display = 'flex';
    }

    // 添加 CIDR 输入框
    function addCidrInput() {
        const cidrList = document.getElementById('cidrList');
        const newInput = document.createElement('div');
        newInput.className = 'cidr-item';
        newInput.style = 'display: flex; gap: 10px; margin-bottom: 10px;';
        newInput.innerHTML = `
            <input type="text"
                   class="cidr-input"
                   placeholder="请输入CIDR (例如: 10.0.0.0/24)"
                   style="flex: 1; padding: 8px; border: 1px solid #e0e0e0; border-radius: 3px;">
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

        // 验证输入,可以为空
        /*if (cidrRanges.length === 0) {
            alert('请至少输入一个CIDR范围');
            return;
        }*/

        // 显示加载状态
        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = "正在切换IP...";

        // 发送请求
        const xhr = new XMLHttpRequest();
        const csrfToken = _getCsrfToken();

        xhr.open('POST', '/oci/changeSpecIp', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);

                    if (data.status === 'success') {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = data.message || 'IP切换成功';

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

        // 发送数据
        xhr.send(JSON.stringify({
            tenantId: instanceId,
            cidrRanges: cidrRanges
        }));
    }

    // 关闭模态框
    function closeModal() {
        const modal = document.getElementById('changeIpModal');
        modal.style.display = 'none';
    }

    // 页面加载初始化
    document.addEventListener('DOMContentLoaded', () => {
        // 恢复上次视图选择
        const preferredView = localStorage.getItem('preferredView') || 'table';
        switchView(preferredView);

        // 初始化文本截断
        const truncateElements = document.querySelectorAll('.truncate');
        truncateElements.forEach(element => {
            const fullText = element.textContent.trim();
            element.setAttribute('data-fulltext', fullText);
            if (fullText.length > 15) {
                element.textContent = fullText.substring(0, 15) + '...';
                element.setAttribute('data-truncated', 'false');
            } else {
                element.setAttribute('data-truncated', 'true');
            }
        });

        // 初始化侧边栏
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

        // 点击模态框外部关闭
        document.querySelectorAll('.modal-overlay').forEach(modal => {
            modal.addEventListener('click', (e) => {
                if (e.target === modal) {
                    modal.style.display = 'none';
                }
            });
        });

        const startRescueBtn = document.getElementById('startRescueBtn');
        if (startRescueBtn) {
            console.log('找到救援按钮，添加事件监听器');
            startRescueBtn.addEventListener('click', function() {
                console.log('按钮被点击');
                startSystemRescue();
            });
        } else {
            console.error('未找到救援按钮');
        }

        initializeStatusIndicators();

    });

    // 在现有script标签内添加
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
        const csrfToken = _getCsrfToken();

        xhr.open('POST', '/oci/enableIpv6', true);
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

        xhr.onerror = function() {
            statusMessage.className = 'status-message error';
            statusText.textContent = 'IPv6开启失败，请重试';
        };

        xhr.send(JSON.stringify({
            tenantId: instanceId
        }));
    }

    function closeIpv6Modal() {
        const modal = document.getElementById('ipv6Modal');
        modal.style.display = 'none';
    }


    // 终止实例处理
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

        // 显示模态框
        modal.style.display = 'flex';
    }

    // 请求验证码
    function requestVerificationCode() {
        const modal = document.getElementById('terminateInstanceModal');
        const instanceId = modal.getAttribute('data-instance-id');
        const confirmStep = document.getElementById('confirmStep');
        const statusMessage = document.getElementById('terminateMessage');
        const statusText = document.getElementById('terminateText');

        // 显示加载状态
        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = "正在发送验证码...";

        // 发送请求获取验证码
        const xhr = new XMLHttpRequest();
        const csrfToken = _getCsrfToken();

        xhr.open('POST', '/oci/sendVerificationCode', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        // 显示验证码输入步骤
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

    // 确认终止实例
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

        // 显示加载状态
        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = "正在终止实例...";

        // 发送终止请求
        const xhr = new XMLHttpRequest();
        const csrfToken = _getCsrfToken();

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

                        // 3秒后刷新页面
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

    // 关闭终止实例模态框
    function closeTerminateModal() {
        const modal = document.getElementById('terminateInstanceModal');
        modal.style.display = 'none';
    }

    function handleUpdateConfig(instanceId, currentCpu, currentMemory) {
        const modal = document.getElementById('updateConfigModal');
        const cpuInput = document.getElementById('cpuInput');
        const memoryInput = document.getElementById('memoryInput');

        // 设置当前值
        cpuInput.value = currentCpu;
        memoryInput.value = currentMemory;

        // 存储实例ID
        modal.setAttribute('data-instance-id', instanceId);

        // 显示模态框
        modal.style.display = 'flex';
    }

    function confirmUpdateConfig() {
        const modal = document.getElementById('updateConfigModal');
        const instanceId = modal.getAttribute('data-instance-id');
        const newCpu = document.getElementById('cpuInput').value;
        const newMemory = document.getElementById('memoryInput').value;
        const statusMessage = document.getElementById('updateConfigMessage');
        const statusText = document.getElementById('updateConfigText');

        // 验证输入
        if (!newCpu || !newMemory) {
            statusMessage.className = 'status-message error';
            statusMessage.style.display = 'block';
            statusText.textContent = '请填写完整的配置信息';
            return;
        }

        // 显示加载状态
        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = "正在更新配置...";

        // 发送更新请求
        const xhr = new XMLHttpRequest();
        const csrfToken = _getCsrfToken();

        xhr.open('POST', '/oci/updateConfig', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = data.message || '配置更新成功';

                        // 3秒后刷新页面
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
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
        const modal = document.getElementById('updateConfigModal');
        modal.style.display = 'none';
    }

    function handleUpdateName(instanceId, currentName) {
        const modal = document.getElementById('updateNameModal');
        const nameInput = document.getElementById('instanceNameInput');

        // 设置当前名称
        nameInput.value = currentName;

        // 存储实例ID
        modal.setAttribute('data-instance-id', instanceId);

        // 显示模态框
        modal.style.display = 'flex';
    }

    function confirmUpdateName() {
        const modal = document.getElementById('updateNameModal');
        const instanceId = modal.getAttribute('data-instance-id');
        const newName = document.getElementById('instanceNameInput').value.trim();
        const statusMessage = document.getElementById('updateNameMessage');
        const statusText = document.getElementById('updateNameText');

        // 验证输入
        if (!newName) {
            statusMessage.className = 'status-message error';
            statusMessage.style.display = 'block';
            statusText.textContent = '请输入实例名称';
            return;
        }

        // 显示加载状态
        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = "正在更新实例名称...";

        // 发送更新请求
        const xhr = new XMLHttpRequest();
        const csrfToken = _getCsrfToken();

        xhr.open('POST', '/oci/updateName', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = data.message || '名称更新成功';

                        // 3秒后刷新页面
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
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
        const modal = document.getElementById('updateNameModal');
        modal.style.display = 'none';
    }

    let currentVolumeSize = 0;

    function handleUpdateBootVolume(instanceId, currentSize) {
        const modal = document.getElementById('updateBootVolumeModal');
        const sizeInput = document.getElementById('bootVolumeSizeInput');
        const currentSizeDisplay = document.getElementById('currentSizeDisplay');

        // 存储当前大小供后续比较
        currentVolumeSize = currentSize;

        // 显示当前大小
        currentSizeDisplay.textContent = currentSize;

        // 设置当前大小
        sizeInput.value = currentSize;

        // 存储实例ID
        modal.setAttribute('data-instance-id', instanceId);

        // 初始化警告信息
        validateVolumeSize(currentSize);

        // 显示模态框
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

        // 再次验证输入
        if (!validateVolumeSize(newSize)) {
            return;
        }

        // 计算是扩容还是缩小 - 修改这里的判断
        const isExpand = newSize >= currentVolumeSize;  // 大于等于当前大小就是扩容

        // 显示加载状态
        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        if (isExpand) {
            statusText.textContent = "正在扩容引导卷...";
        } else {
            statusText.textContent = "正在缩小引导卷...";
        }

        // 发送更新请求
        const xhr = new XMLHttpRequest();
        const csrfToken = _getCsrfToken();

        xhr.open('POST', '/oci/updateBootVolume', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        statusMessage.className = 'status-message success';
                        if (!data.message) {
                            if (isExpand) {
                                statusText.textContent = "引导卷扩容成功";
                            } else {
                                statusText.textContent = "引导卷缩小成功";
                            }
                        } else {
                            statusText.textContent = data.message;
                        }

                        // 3秒后刷新页面
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        statusMessage.className = 'status-message error';
                        if (!data.message) {
                            if (isExpand) {
                                statusText.textContent = "引导卷扩容失败";
                            } else {
                                statusText.textContent = "引导卷缩小失败";
                            }
                        } else {
                            statusText.textContent = data.message;
                        }
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
        const modal = document.getElementById('updateBootVolumeModal');
        modal.style.display = 'none';
    }



    function handleUpdateRemark(instanceId, currentRemark) {
        const modal = document.getElementById('updateRemarkModal');
        const remarkInput = document.getElementById('remarkInput');

        // 设置当前备注
        remarkInput.value = currentRemark || '';

        // 存储实例ID
        modal.setAttribute('data-instance-id', instanceId);

        // 显示模态框
        modal.style.display = 'flex';
    }

    function confirmUpdateRemark() {
        const modal = document.getElementById('updateRemarkModal');
        const instanceId = modal.getAttribute('data-instance-id');
        const newRemark = document.getElementById('remarkInput').value.trim();
        const statusMessage = document.getElementById('updateRemarkMessage');
        const statusText = document.getElementById('updateRemarkText');

        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = "正在更新备注...";

        // 发送更新请求
        const xhr = new XMLHttpRequest();
        const csrfToken = _getCsrfToken();

        xhr.open('POST', '/oci/updateRemark', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = data.message || '备注更新成功';

                        // 3秒后刷新页面
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent = data.message || '备注更新失败';
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = '请求失败，请重试';
                }
            }
        };

        xhr.send(JSON.stringify({
            instanceId: instanceId,
            remark: newRemark
        }));
    }

    function closeUpdateRemarkModal() {
        const modal = document.getElementById('updateRemarkModal');
        modal.style.display = 'none';
    }
    // 全局变量用于保存当前选中的实例ID
    let selectedInstanceId = "";

    function loadInstanceList() {
        const instanceSelect = document.getElementById('instanceSelect');

        // 显示加载状态
        instanceSelect.innerHTML = '<option value="">加载中...</option>';
        instanceSelect.disabled = true;

        // 获取CSRF令牌
        const csrfToken = _getCsrfToken();

        // 构造请求配置
        const options = {
            headers: {
                'X-CSRF-TOKEN': csrfToken
            }
        };

        // 请求实例列表数据
        fetch('/tenants/listAll', options)
            .then(response => {
                if (!response.ok) {
                    throw new Error('网络请求失败');
                }
                return response.json();
            })
            .then(data => {
                // 清空下拉框并添加默认选项
                instanceSelect.innerHTML = '<option value="">请选择实例</option>';
                instanceSelect.disabled = false;

                // 按用户名称排序
                data.sort((a, b) => {
                    if (a.userName && b.userName) {
                        return a.userName.localeCompare(b.userName);
                    }
                    return 0;
                });

                // 添加实例选项
                data.forEach(instance => {
                    const option = document.createElement('option');
                    option.value = instance.tenantId;
                    option.textContent = instance.userName + " (" + instance.tenantId.substring(0, 8) + "...)";
                    instanceSelect.appendChild(option);
                });

                // 从URL参数获取已选择的实例ID
                const urlParams = new URLSearchParams(window.location.search);
                const instanceId = urlParams.get('instanceId');

                if (instanceId) {
                    selectedInstanceId = instanceId;
                    instanceSelect.value = instanceId;
                }
            })
            .catch(error => {
                console.error('加载实例列表失败:', error);
                instanceSelect.innerHTML = '<option value="">加载失败，请刷新页面</option>';
                instanceSelect.disabled = false;
            });
    }

    // 实例选择变更事件处理
    function instanceChanged() {
        selectedInstanceId = document.getElementById('instanceSelect').value;

        // 构建URL参数
        const urlParams = new URLSearchParams(window.location.search);

        // 如果选择了默认选项，则移除instanceId参数
        if (!selectedInstanceId) {
            urlParams.delete('instanceId');
        } else {
            // 否则设置instanceId参数
            urlParams.set('instanceId', selectedInstanceId);
        }

        // 保留其他现有参数（如分页参数）
        const page = urlParams.get('page');
        const size = urlParams.get('size');

        if (page !== null) {
            urlParams.set('page', page);
        }

        if (size !== null) {
            urlParams.set('size', size);
        }

        // 构建新URL并导航
        const newUrl = `/oci/list?` + urlParams.toString();
        window.location.href = newUrl;
    }


    // 全局变量
    let selectedTenantId = "";  // 始终使用字符串
    let selectedRegionId = "";  // 始终使用字符串

    // 页面加载时初始化
    document.addEventListener('DOMContentLoaded', () => {
        // 加载租户列表
        loadTenants();

        // 根据URL参数初始化选择
        const urlParams = new URLSearchParams(window.location.search);
        const tenantId = urlParams.get('tenantId');

        if (tenantId) {
            selectedTenantId = tenantId;  // 直接使用字符串，不尝试转换为数值
        }

        const modal = document.getElementById('sshModal');
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                modal.style.display = 'none';
                disconnectSsh();
            }
        });
    });

    // 加载租户列表
    function loadTenants() {
        const tenantSelect = document.getElementById('tenantSelect');

        // 显示加载状态
        tenantSelect.innerHTML = '<option value="">加载中...</option>';
        tenantSelect.disabled = true;

        // 获取CSRF令牌
        const csrfToken = _getCsrfToken();

        // 构造请求配置
        const options = {
            headers: {
                'X-CSRF-TOKEN': csrfToken
            }
        };

        // 请求顶级租户数据（只获取父级租户）
        fetch('/tenants/listParentTenants', options)
            .then(response => {
                if (!response.ok) {
                    throw new Error('网络请求失败');
                }
                return response.json();
            })
            .then(data => {
                // 清空下拉框并添加默认选项
                tenantSelect.innerHTML = '<option value="">请选择租户</option>';
                tenantSelect.disabled = false;

                // 按用户名称排序
                data.sort((a, b) => {
                    if (a.userName && b.userName) {
                        return a.userName.localeCompare(b.userName);
                    }
                    return 0;
                });

                // 添加租户选项
                data.forEach(tenant => {
                    const option = document.createElement('option');
                    // 直接使用DTO中的字符串id，不需要再转换
                    option.value = tenant.id;
                    option.textContent = tenant.userName || tenant.tenancyName || `租户 `+tenant.id;
                    tenantSelect.appendChild(option);
                });

                // 如果URL中有租户ID，自动选择并加载区域
                if (selectedTenantId) {
                    tenantSelect.value = selectedTenantId;
                    loadRegions();
                }
            })
            .catch(error => {
                console.error('加载租户列表失败:', error);
                tenantSelect.innerHTML = '<option value="">加载失败，请刷新页面</option>';
                tenantSelect.disabled = false;
            });
    }

    // 加载区域列表
    function loadRegions() {
        const tenantSelect = document.getElementById('tenantSelect');
        const regionSelect = document.getElementById('regionSelect');
        const goToInstanceBtn = document.getElementById('goToInstanceBtn');

        // 直接获取select的value，这已经是字符串
        selectedTenantId = tenantSelect.value;

        // 如果没有选择租户，禁用区域选择和按钮
        if (!selectedTenantId) {
            regionSelect.innerHTML = '<option value="">请选择区域</option>';
            regionSelect.disabled = true;
            goToInstanceBtn.disabled = true;
            return;
        }

        // 显示加载状态
        regionSelect.innerHTML = '<option value="">加载中...</option>';
        regionSelect.disabled = true;
        goToInstanceBtn.disabled = true;

        // 获取CSRF令牌
        const csrfToken = _getCsrfToken();

        // 构造请求配置
        const options = {
            headers: {
                'X-CSRF-TOKEN': csrfToken
            }
        };

        // 使用GET请求，将parentId作为URL参数
        fetch('/tenants/listRegions?parentId=' + encodeURIComponent(selectedTenantId), options)
            .then(response => {
                if (!response.ok) {
                    throw new Error('网络请求失败');
                }
                return response.json();
            })
            .then(data => {
                // 清空下拉框并添加默认选项
                regionSelect.innerHTML = '<option value="">请选择区域</option>';
                regionSelect.disabled = false;

                // 调试输出
                console.log('接收到的区域数据:', data);

                // 添加区域选项
                if (data && data.length > 0) {
                    // 如果只有一个区域，直接选中
                    if (data.length === 1) {
                        const region = data[0];
                        const option = document.createElement('option');
                        // 直接使用DTO中的字符串id
                        option.value = region.id;
                        option.textContent = region.region || `区域 `+region.id;
                        regionSelect.appendChild(option);

                        // 自动选择该区域
                        regionSelect.value = region.id;
                        selectedRegionId = region.id;

                        // 启用查看实例按钮
                        goToInstanceBtn.disabled = false;
                    } else {
                        // 多个区域，按区域名称排序
                        data.sort((a, b) => {
                            if (a.region && b.region) {
                                return a.region.localeCompare(b.region);
                            }
                            return 0;
                        });

                        // 添加区域选项
                        data.forEach(region => {
                            const option = document.createElement('option');
                            // 直接使用DTO中的字符串id
                            option.value = region.id;
                            option.textContent = region.region || `区域 `+region.id;
                            regionSelect.appendChild(option);
                        });

                        // 如果URL中有区域ID，自动选择
                        if (selectedRegionId) {
                            const regionIds = data.map(region => region.id);
                            if (regionIds.includes(selectedRegionId)) {
                                regionSelect.value = selectedRegionId;
                                goToInstanceBtn.disabled = false;
                            } else {
                                selectedRegionId = "";
                            }
                        }
                    }
                } else {
                    // 没有区域数据
                    regionSelect.innerHTML = '<option value="">无可用区域</option>';
                    regionSelect.disabled = true;
                    goToInstanceBtn.disabled = true;
                }
            })
            .catch(error => {
                console.error('加载区域列表失败:', error);
                regionSelect.innerHTML = '<option value="">加载失败，请重试</option>';
                regionSelect.disabled = true;
                goToInstanceBtn.disabled = true;
            });
    }

    // 区域选择变更事件
    function regionChanged() {
        const regionSelect = document.getElementById('regionSelect');
        const goToInstanceBtn = document.getElementById('goToInstanceBtn');

        selectedRegionId = regionSelect.value;

        // 如果选择了区域，启用查看实例按钮
        goToInstanceBtn.disabled = !selectedRegionId;
    }

    // 查看实例
    function goToInstances() {
        if (!selectedRegionId) {
            return;
        }

        // 使用表单提交替代URL拼接
        const form = document.createElement('form');
        form.method = 'GET';
        form.action = '/oci/list';

        const input = document.createElement('input');
        input.type = 'hidden';
        input.name = 'tenantId';
        input.value = selectedRegionId;

        form.appendChild(input);
        document.body.appendChild(form);
        form.submit();
    }

    // 添加启动实例处理函数
    function handleStartInstance(instanceId) {
        const modal = document.getElementById('startInstanceModal');
        const statusMessage = document.getElementById('startInstanceMessage');

        // 重置状态消息
        statusMessage.style.display = 'none';

        // 存储实例ID
        modal.setAttribute('data-instance-id', instanceId);

        // 显示模态框
        modal.style.display = 'flex';
    }

    function confirmStartInstance() {
        const modal = document.getElementById('startInstanceModal');
        const instanceId = modal.getAttribute('data-instance-id');
        const statusMessage = document.getElementById('startInstanceMessage');
        const statusText = document.getElementById('startInstanceText');

        // 显示加载状态
        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = "正在启动实例...";

        // 发送请求
        const xhr = new XMLHttpRequest();
        const csrfToken = _getCsrfToken();

        xhr.open('POST', '/oci/startInstance', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = data.message || '实例启动成功';

                        // 3秒后刷新页面
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent = data.message || '实例启动失败';
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = '请求失败，请重试';
                }
            }
        };

        xhr.onerror = function() {
            statusMessage.className = 'status-message error';
            statusText.textContent = '启动请求失败，请重试';
        };

        xhr.send(JSON.stringify({
            instanceId: instanceId
        }));
    }

    function closeStartInstanceModal() {
        const modal = document.getElementById('startInstanceModal');
        modal.style.display = 'none';
    }

    // 添加停止实例处理函数
    function handleStopInstance(instanceId) {
        const modal = document.getElementById('stopInstanceModal');
        const statusMessage = document.getElementById('stopInstanceMessage');

        // 重置状态消息
        statusMessage.style.display = 'none';

        // 存储实例ID
        modal.setAttribute('data-instance-id', instanceId);

        // 显示模态框
        modal.style.display = 'flex';
    }

    function confirmStopInstance() {
        const modal = document.getElementById('stopInstanceModal');
        const instanceId = modal.getAttribute('data-instance-id');
        const statusMessage = document.getElementById('stopInstanceMessage');
        const statusText = document.getElementById('stopInstanceText');

        // 显示加载状态
        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = "正在停止实例...";

        // 发送请求
        const xhr = new XMLHttpRequest();
        const csrfToken = _getCsrfToken();

        xhr.open('POST', '/oci/stopInstance', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = data.message || '实例停止成功';

                        // 3秒后刷新页面
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent = data.message || '实例停止失败';
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = '请求失败，请重试';
                }
            }
        };

        xhr.onerror = function() {
            statusMessage.className = 'status-message error';
            statusText.textContent = '停止请求失败，请重试';
        };

        xhr.send(JSON.stringify({
            instanceId: instanceId
        }));
    }

    function closeStopInstanceModal() {
        const modal = document.getElementById('stopInstanceModal');
        modal.style.display = 'none';
    }


    // 复制到剪贴板功能
    function copyToClipboard(text, element) {
        // 创建临时文本区域
        const textArea = document.createElement('textarea');
        textArea.value = text;
        textArea.style.position = 'fixed';
        textArea.style.left = '-999999px';
        textArea.style.top = '-999999px';
        document.body.appendChild(textArea);

        try {
            // 选择并复制文本
            textArea.focus();
            textArea.select();
            document.execCommand('copy');

            // 显示复制成功的视觉反馈
            showCopySuccess(element);

            // 使用SweetAlert2显示成功提示
            Swal.fire({
                icon: 'success',
                title: '复制成功',
                text: `已复制: ` +text ,
                timer: 1500,
                showConfirmButton: false,
                toast: true,
                position: 'top-end'
            });

        } catch (err) {
            // 降级到使用现代浏览器的Clipboard API
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).then(() => {
                    showCopySuccess(element);
                    Swal.fire({
                        icon: 'success',
                        title: '复制成功',
                        text: `已复制: `+text ,
                        timer: 1500,
                        showConfirmButton: false,
                        toast: true,
                        position: 'top-end'
                    });
                }).catch(() => {
                    showCopyError();
                });
            } else {
                showCopyError();
            }
        } finally {
            // 清理临时元素
            document.body.removeChild(textArea);
        }
    }

    // 显示复制成功的视觉反馈
    function showCopySuccess(element) {
        const icon = element.querySelector('i');
        const originalClass = icon.className;

        // 暂时改变图标
        icon.className = 'fas fa-check';
        element.classList.add('copy-success');
        element.style.color = '#4caf50';

        // 0.8秒后恢复原来的图标
        setTimeout(() => {
            icon.className = originalClass;
            element.classList.remove('copy-success');
            element.style.color = '';
        }, 800);
    }

    // 显示复制失败提示
    function showCopyError() {
        Swal.fire({
            icon: 'error',
            title: '复制失败',
            text: '您的浏览器不支持自动复制，请手动复制',
            timer: 2000,
            showConfirmButton: false,
            toast: true,
            position: 'top-end'
        });
    }

    // 阻止复制按钮的默认行为
    document.addEventListener('DOMContentLoaded', function() {
        document.addEventListener('click', function(e) {
            if (e.target.closest('.action-link.copy')) {
                e.preventDefault();
            }
        });
    });

    function getStatusClass(state) {
        if (!state) return 'status-stopped';

        const lowerState = state.toLowerCase();

        switch (lowerState) {
            case 'running':
                return 'status-running';
            case 'stopped':
                return 'status-stopped';
            case 'starting':
                return 'status-starting';
            case 'stopping':
                return 'status-stopping';
            case 'terminated':
            case 'terminating':
                return 'status-terminated';
            default:
                return 'status-stopped';
        }
    }

    /**
     * 初始化状态指示器
     */
    function initializeStatusIndicators() {
        // 为所有状态指示器添加工具提示
        document.querySelectorAll('.status-indicator').forEach(indicator => {
            const statusClass = indicator.className.split(' ').find(cls => cls.startsWith('status-'));
            let statusText = '';

            switch (statusClass) {
                case 'status-running':
                    statusText = '运行中';
                    break;
                case 'status-stopped':
                    statusText = '已停止';
                    break;
                case 'status-starting':
                    statusText = '启动中';
                    break;
                case 'status-stopping':
                    statusText = '停止中';
                    break;
                case 'status-terminated':
                    statusText = '已终止';
                    break;
                default:
                    statusText = '未知状态';
            }

            indicator.title = statusText;
        });
    }


</script>
</body>
</html>