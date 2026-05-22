<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - OCI实例管理</title>
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
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/app/oci_machine_list.css">
    <link rel="stylesheet" href="/css/common/dropdown-menu.css">
    <link rel="stylesheet" href="/css/common/custom-select.css">
    <style>
        body { opacity: 0; transition: opacity 0.12s ease; }
        /* 同租户行分组背景 */
        tr.tgrp-a { background-color: transparent; }
        tr.tgrp-b { background-color: rgba(99,179,237,0.07); }
        tr.tgrp-a:hover, tr.tgrp-b:hover { background-color: var(--hover-bg) !important; }
        [data-theme="dark"] tr.tgrp-b { background-color: rgba(99,179,237,0.05); }
        .name-spoiler { display: inline-block; max-width: 100%; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; cursor: pointer; user-select: none; filter: none !important; }
        .name-spoiler.is-hidden .name-masked { display: inline; color: var(--text-secondary); font-style: italic; letter-spacing: 1px; background: var(--hover-bg); border-radius: 4px; padding: 1px 6px; }
        .name-spoiler.is-hidden .name-full { display: none; }
        .name-spoiler.is-visible .name-masked { display: none; }
        .name-spoiler.is-visible .name-full { display: inline; color: var(--text-primary); }
    </style>
    <script>document.addEventListener('DOMContentLoaded', function(){ document.body.style.opacity = '1'; });</script>

    <!-- SweetAlert2 CSS -->
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <!-- SweetAlert2 JS -->
    <script src="/js/sweetalert2.min.js"></script>
    <script src="/js/common/dropdown-menu.js"></script>
    <script src="/js/common/jquery.min.js"></script>


    <#include "common/pagination.ftl" />

</head>
<body>
<#--<#include "common/version_info.ftl">-->

<#--<#include "common/header.ftl" />-->

<div class="layout">

    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
    <div class="page-card">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-cloud"></i>
                <span>${msg.get("machine.config")}</span>
            </h1>
            <div class="view-actions">
                <!-- 添加搜索框 -->
                <!-- 级联下拉搜索框 -->
                <div class="filter-controls">
                    <div class="filter-item">
                        <label class="filter-label">${msg.get("openBoot.select")}</label>
                        <div class="cascade-container">
                            <div class="cascade-selects">
                                <div class="cascade-select">
                                    <select id="tenantSelect"
                                            data-custom-select data-searchable data-page-size="5"
                                            data-placeholder="${msg.get("openBoot.selectTenant")}"
                                            onchange="syncTenantDropdown()">
                                        <option value="">${msg.get("openBoot.selectTenant")}</option>
                                    </select>
                                </div>
                                <div class="cascade-select">
                                    <select id="regionSelect"
                                            data-custom-select data-searchable data-page-size="5"
                                            data-placeholder="${msg.get("openBoot.selectRegion")}"
                                            onchange="syncRegionDropdown()" disabled>
                                        <option value="">${msg.get("openBoot.selectRegion")}</option>
                                    </select>
                                </div>
                            </div>
                            <button id="goToInstanceBtn" class="btn btn-primary" onclick="goToInstances()" disabled>
                                <i class="fas fa-search"></i> ${msg.get("machine.detail")}
                            </button>
                            <button id="resetFilterBtn" class="btn btn-secondary" onclick="resetFilter()" style="display:none;">
                                <i class="fas fa-times"></i> ${msg.get("common.reset")}
                            </button>
                            <div>
                                <button class="btn btn-secondary" onclick="history.back()">
                                    <i class="fas fa-arrow-left"></i> ${msg.get("common.rollback")}
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>

        <!-- Table View -->
        <div class="table-view">
            <table class="table">
                <thead>
                <tr>
                    <th style="min-width: 40px; width: 40px;">#</th>
                    <th>
                        <span style="display:inline-flex;align-items:center;gap:6px;">
                            ${msg.get("tenant.name")}
                            <button id="toggleAllSpoilersBtn" onclick="toggleAllSpoilers()" title="显示/隐藏所有租户名"
                                style="background:none;border:none;cursor:pointer;color:var(--text-secondary);padding:0;line-height:1;font-size:13px;display:inline-flex;align-items:center;">
                                <i class="fas fa-eye-slash" id="toggleAllSpoilersIcon"></i>
                            </button>
                        </span>
                    </th>
                    <th>${msg.get("machine.region")}</th>
                    <th>${msg.get("tenant.insName")}</th>
                    <th>CPU/MEM</th>
                    <th>${msg.get("machine.arch")}</th>
                    <th style="min-width: 70px; width: 70px;">${msg.get("openBoot.volume")}/VPU</th>
                    <th>${msg.get("machine.homeIpv4")}</th>
                    <th>IPV6</th>
                    <th>${msg.get("tenant.createTime")}</th>
                    <th>${msg.get("machine.action")}</th>
                </tr>
                </thead>
                <tbody id="instance-table-body">
                <#assign _prevTid = "">
                <#assign _tgrp = 0>
                <#list instanceDetailsRes as instance>
                    <#assign _tid = instance.tenantId?string>
                    <#if _tid != _prevTid>
                        <#if _prevTid != ""><#assign _tgrp = _tgrp + 1></#if>
                        <#assign _prevTid = _tid>
                    </#if>
                    <tr class="tgrp-${(_tgrp % 2 == 0)?then('a','b')}">
                        <!-- 序号列 -->
                        <td style="text-align: center; color: var(--text-secondary); font-size: 12px;">
                            ${currentPage * size + instance?index + 1}
                        </td>

                        <!-- 租户名列（带遮罩） -->
                        <td class="col-name">
                            <#assign tn = (instance.tenancyName)!''>
                            <#assign maskedTn = (tn?length > 2)?then(tn?substring(0,1) + '***' + tn?substring(tn?length - 1), (tn?length > 0)?then('***', ''))>
                            <span class="name-spoiler is-hidden" onclick="toggleSpoiler(this)" title="${tn}">
                                <span class="name-masked">${maskedTn}</span>
                                <span class="name-full">${tn}</span>
                            </span>
                        </td>

                        <!-- 所属区域列 -->
                        <td>
                            <span class="truncate" title="${instance.regionName!''}">${instance.regionName!''}</span>
                        </td>


                        <!-- 实例名称列 -->
                        <td>
                            <div class="instance-name-container">
                                <#if instance.state?lower_case == "running">
                                    <span class="status-indicator status-running" title="${msg.get("machine.running")}"></span>
                                <#elseif instance.state?lower_case == "stopped">
                                    <span class="status-indicator status-stopped" title="${msg.get("machine.stopped")}"></span>
                                <#elseif instance.state?lower_case == "starting">
                                    <span class="status-indicator status-starting" title="${msg.get("machine.starting")}"></span>
                                <#elseif instance.state?lower_case == "stopping">
                                    <span class="status-indicator status-stopping" title="${msg.get("machine.stopping")}"></span>
                                <#elseif instance.state?lower_case == "terminated" || instance.state?lower_case == "terminating">
                                    <span class="status-indicator status-terminated" title="${msg.get("machine.temed")}"></span>
                                <#else>
                                    <span class="status-indicator status-stopped" title="${msg.get("machine.unKnow")}"></span>
                                </#if>
                                <span class="truncate" title="${instance.displayName}">${instance.displayName}</span>
                            </div>
                        </td>

                        <!-- CPU/内存列 -->
                        <td style="min-width: 70px; width: 70px;">
                            <span class="truncate">${instance.cpuAndMem}</span>
                        </td>

                        <!-- 架构列 -->
                        <td>
                            <span class="truncate">${instance.architecture}</span>
                        </td>

                        <!-- 磁盘列 -->
                        <td style="min-width: 90px; width: 90px;">
                            <span>${instance.bootVolumeSizeInGBs}GB/${instance.vpusPerGB!0}</span>
                        </td>

                        <!-- IPV4列 -->
                        <td>
                            <span class="truncate" title="${instance.publicIps}">${instance.publicIps}</span>
                        </td>

                        <!-- IPV6列 -->
                        <td>
                            <#if instance.ipv6Addresses?? && instance.ipv6Addresses?trim != "">
                                <span class="truncate" title="${instance.ipv6Addresses}">${msg.get("token.status.enabled")}</span>
                            <#else>
                                <span class="ipv6-empty">${msg.get("tenant.no")}</span>
                            </#if>
                        </td>

                        <!-- 入库时间列 -->
                        <td style="white-space: nowrap; font-size: 12px; color: var(--text-secondary);">
                            <#if instance.createTime??>${instance.createTime?string("yyyy-MM-dd")}</#if>
                        </td>

                        <!-- 操作列 -->
                        <td class="actions-cell">
                            <div style="display: none;">
                                <input type="hidden" name="${_csrf.parameterName}" value="${_csrf.token}">
                            </div>

                            <div class="dropdown">
                                <button class="dropdown-toggle btn">
                                    <i class="fas fa-ellipsis-h"></i>
                                </button>

                                <div class="dropdown-panel">
                                    <#if instance.state?lower_case == "stopped">
                                        <button class="dropdown-item" onclick="handleStartInstance('${instance.id}')">
                                            <i class="fas fa-play"></i><span>${msg.get("machine.start")}</span>
                                        </button>
                                    <#elseif instance.state?lower_case == "running">
                                        <button class="dropdown-item" onclick="handleStopInstance('${instance.id}')">
                                            <i class="fas fa-stop"></i><span>${msg.get("machine.stop")}</span>
                                        </button>
                                    </#if>
                                    <button class="dropdown-item danger" onclick="handleTerminateInstance('${instance.id}')">
                                        <i class="fas fa-stop-circle"></i><span>${msg.get("machine.tem")}</span>
                                    </button>
                                    <button class="dropdown-item" onclick="handleUpdateRemark('${instance.id}', '${instance.remark!?js_string}')">
                                        <i class="fas fa-sticky-note"></i><span>${msg.get("machine.updateRemark")}</span>
                                    </button>
                                    <button class="dropdown-item" onclick="handleUpdateName('${instance.id}', '${instance.displayName?js_string}')">
                                        <i class="fas fa-tag"></i><span>${msg.get("machine.updateName")}</span>
                                    </button>
                                    <button class="dropdown-item" onclick="handleUpdateConfig('${instance.id}', ${instance.ocpus}, ${instance.memoryInGBs})">
                                        <i class="fas fa-microchip"></i><span>${msg.get("machine.update")}</span>
                                    </button>
                                    <button class="dropdown-item" onclick="handleUpdateBootVolume('${instance.id}', ${instance.bootVolumeSizeInGBs})">
                                        <i class="fas fa-hdd"></i><span>${msg.get("machine.updateDiskSize")}</span>
                                    </button>
                                    <button class="dropdown-item" onclick="handleUpdateVpu('${instance.bootVolumeId!''}', '${instance.tenantIdStr}', ${instance.vpusPerGB!0}, '${instance.id}')">
                                        <i class="fas fa-sliders-h"></i><span>${msg.get("machine.updateVpu")}</span>
                                    </button>
                                    <button class="dropdown-item" onclick="copyToClipboard('${instance.publicIps}', this)">
                                        <i class="fas fa-copy"></i><span>${msg.get("machine.copyIp")}</span>
                                    </button>
                                    <button class="dropdown-item" onclick="handleChangeIp('${instance.id}')">
                                        <i class="fas fa-sync-alt"></i><span>${msg.get("machine.changeIp")}</span>
                                    </button>
                                    <#if instance.ipv6Addresses?? && instance.ipv6Addresses?trim != "">
                                        <button class="dropdown-item" onclick="copyToClipboard('${instance.ipv6Addresses}', this)">
                                            <i class="fas fa-copy"></i><span>${msg.get("machine.copyIpv6")}</span>
                                        </button>
                                        <button class="dropdown-item" onclick="handleChangeIpv6('${instance.id}')">
                                            <i class="fas fa-globe"></i><span>${msg.get("machine.mgIpv6")}</span>
                                        </button>
                                    <#else>
                                        <button class="dropdown-item" onclick="handleChangeIpv6('${instance.id}')">
                                            <i class="fas fa-plus-circle"></i><span>${msg.get("machine.startIpv6")}</span>
                                        </button>
                                    </#if>
                                    <a href="/oci/terminal?instanceId=${instance.id}" class="dropdown-item">
                                        <i class="fas fa-terminal"></i><span>${msg.get("machine.sshConn")}</span>
                                    </a>
                                    <a href="/oci/console/terminal/${instance.id}" class="dropdown-item">
                                        <i class="fas fa-tv"></i><span>${msg.get("machine.console")}</span>
                                    </a>
                                    <a href="/oci/vnic/manage?instanceId=${instance.instanceId}" class="dropdown-item">
                                        <i class="fas fa-sitemap"></i><span>${msg.get("machine.net")}</span>
                                    </a>
                                    <button class="dropdown-item" onclick="handleQuickDD('${instance.id}', '${instance.displayName?js_string}')">
                                        <i class="fas fa-undo"></i><span>${msg.get("machine.osReset")}</span>
                                    </button>
                                    <button class="dropdown-item danger" onclick="handleDeleteRecord('${instance.id}', '${instance.displayName?js_string}')">
                                        <i class="fas fa-trash-alt"></i><span>${msg.get("machine.deleteRecord")}</span>
                                    </button>
                                </div>
                            </div>
                        </td>

                    </tr>
                </#list>
                </tbody>
            </table>

        </div>


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
    </div><!-- /.page-card -->
    </main>
</div>

<!-- Change IP Modal -->
<!-- 修改 Change IP Modal 部分 -->
<div id="changeIpModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("machine.ipChangeConfig")}</h3>
        </div>
        <div id="changeIpContent">
            <!-- 添加 CIDR 输入区域 -->
            <div class="cidr-input-container" style="margin-bottom: 20px;">
                <div class="cidr-list" id="cidrList">
                    <div class="cidr-item" style="display: flex; gap: 10px; margin-bottom: 10px;">
                        <input type="text"
                               class="cidr-input"
                               placeholder="CIDR ( 10.0.0.0/24)"
                               style="flex: 1; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px;">
                    </div>
                </div>
                <button class="btn btn-primary"
                        onclick="addCidrInput()"
                        style="margin-bottom: 15px;">
                    <i class="fas fa-plus"></i> ${msg.get("machine.addCidr")}
                </button>
            </div>

            <!-- 操作按钮 -->
            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmChangeIp()">
                    <i class="fas fa-check"></i> ${msg.get("common.confirm")}
                </button>
                <button class="btn btn-danger" onclick="closeModal()">
                    <i class="fas fa-times"></i> ${msg.get("common.cancel")}
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
            <h3 class="modal-title">${msg.get("machine.ipv6Config")}</h3>
        </div>
        <div id="ipv6Content">
            <div style="margin-bottom: 20px;">
                <p>${msg.get("machine.ipv6ConfigSum1")}？</p>
                <p style="font-size: 12px; color: var(--text-secondary);">${msg.get("machine.ipv6ConfigSum2")}</p>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmEnableIpv6()">
                    <i class="fas fa-check"></i> ${msg.get("common.confirm")}
                </button>
                <button class="btn btn-danger" onclick="closeIpv6Modal()">
                    <i class="fas fa-times"></i> ${msg.get("common.cancel")}
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
            <h3 class="modal-title">${msg.get("machine.temIns")}</h3>
        </div>
        <div id="terminateInstanceContent">
            <!-- 第一步：确认提示 -->
            <div id="confirmStep" style="margin-bottom: 20px;">
                <div style="margin-bottom: 15px;">
                    <p style="color: var(--accent-red); font-weight: bold;">${msg.get("machine.temInsSum1")}</p>
                </div>
                <div style="display: flex; gap: 10px;">
                    <button class="btn btn-danger" onclick="requestVerificationCode()">
                        <i class="fas fa-check"></i> ${msg.get("common.confirm")}
                    </button>
                    <button class="btn btn-primary" onclick="closeTerminateModal()">
                        <i class="fas fa-times"></i> ${msg.get("common.cancel")}
                    </button>
                </div>
            </div>

            <!-- 第二步：验证码输入 -->
            <div id="verifyStep" style="display: none;">
                <div style="margin-bottom: 15px;">
                    <input type="text"
                           id="verificationCodeInput"
                           placeholder="${msg.get("login.verify.code.placeholder")}"
                           style="width: 100%; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px; margin-bottom: 10px;">
                </div>
                <div style="display: flex; gap: 10px;">
                    <button class="btn btn-danger" onclick="confirmTermination()">
                        <i class="fas fa-check"></i> ${msg.get("machine.temInsSum2")}
                    </button>
                    <button class="btn btn-primary" onclick="closeTerminateModal()">
                        <i class="fas fa-times"></i> ${msg.get("common.cancel")}
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
            <h3 class="modal-title">${msg.get("machine.updateIns")}</h3>
        </div>
        <div id="updateConfigContent">
            <div style="margin-bottom: 20px;">
                <div style="margin-bottom: 15px;">
                    <label style="display: block; margin-bottom: 5px;">CPU</label>
                    <input type="number"
                           id="cpuInput"
                           min="1"
                           max="24"
                           step="1"
                           style="width: 100%; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px;">
                </div>
                <div style="margin-bottom: 15px;">
                    <label style="display: block; margin-bottom: 5px;">MEM (GB)</label>
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
                    <i class="fas fa-check"></i> ${msg.get("common.confirm")}
                </button>
                <button class="btn btn-danger" onclick="closeUpdateConfigModal()">
                    <i class="fas fa-times"></i> ${msg.get("common.cancel")}
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
            <h3 class="modal-title">${msg.get("machine.updateName")}</h3>
        </div>
        <div id="updateNameContent">
            <div style="margin-bottom: 20px;">
                <div style="margin-bottom: 15px;">
                    <label style="display: block; margin-bottom: 5px;">${msg.get("tenant.insName")}</label>
                    <input type="text"
                           id="instanceNameInput"
                           placeholder="${msg.get("machine.newName")}"
                           style="width: 100%; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px;">
                </div>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmUpdateName()">
                    <i class="fas fa-check"></i> ${msg.get("common.confirm")}
                </button>
                <button class="btn btn-danger" onclick="closeUpdateNameModal()">
                    <i class="fas fa-times"></i> ${msg.get("common.cancel")}
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
            <h3 class="modal-title">${msg.get("machine.updateDiskSize")}</h3>
        </div>
        <div id="updateBootVolumeContent">
            <div style="margin-bottom: 20px;">
                <div id="volumeChangeWarning" class="status-message" style="display: none; margin-bottom: 15px;">
                </div>
                <div style="margin-bottom: 15px;">
                    <label style="display: block; margin-bottom: 5px;">${msg.get("machine.size")}: <span id="currentSizeDisplay"></span> GB</label>
                    <label style="display: block; margin-bottom: 5px;">${msg.get("machine.vsize")} (GB)</label>
                    <input type="number"
                           id="bootVolumeSizeInput"
                           min="47"
                           step="1"
                           style="width: 100%; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px;"
                           oninput="validateVolumeSize(this.value)">
                    <small style="color: var(--text-secondary);">${msg.get("machine.msize")}: 47GB</small>
                </div>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmUpdateBootVolume()" id="confirmButton">
                    <i class="fas fa-check"></i> ${msg.get("common.confirm")}
                </button>
                <button class="btn btn-danger" onclick="closeUpdateBootVolumeModal()">
                    <i class="fas fa-times"></i> ${msg.get("common.cancel")}
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
            <h3 class="modal-title">${msg.get("machine.updateRemark")}</h3>
        </div>
        <div id="updateRemarkContent">
            <div style="margin-bottom: 20px;">
                <div style="margin-bottom: 15px;">
                    <label style="display: block; margin-bottom: 5px;">${msg.get("machine.content")}</label>
                    <textarea id="remarkInput"
                              placeholder="${msg.get("machine.content")}"
                              style="width: 100%; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px; min-height: 100px; background: var(--input-bg); color: var(--text-primary);"></textarea>
                </div>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmUpdateRemark()">
                    <i class="fas fa-check"></i> ${msg.get("common.confirm")}
                </button>
                <button class="btn btn-danger" onclick="closeUpdateRemarkModal()">
                    <i class="fas fa-times"></i> ${msg.get("common.cancel")}
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
            <h3 class="modal-title">${msg.get("machine.start")}</h3>
        </div>
        <div id="startInstanceContent">
            <div style="margin-bottom: 20px;">
                <p>${msg.get("machine.startSum1")}</p>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmStartInstance()">
                    <i class="fas fa-check"></i> ${msg.get("common.confirm")}
                </button>
                <button class="btn btn-danger" onclick="closeStartInstanceModal()">
                    <i class="fas fa-times"></i> ${msg.get("common.cancel")}
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
            <h3 class="modal-title">${msg.get("machine.stop")}</h3>
        </div>
        <div id="stopInstanceContent">
            <div style="margin-bottom: 20px;">
                <p>${msg.get("machine.stopSum1")}？</p>
                <p style="font-size: 12px; color: var(--text-secondary);">${msg.get("machine.stopSum2")}</p>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmStopInstance()">
                    <i class="fas fa-check"></i> ${msg.get("common.confirm")}
                </button>
                <button class="btn btn-danger" onclick="closeStopInstanceModal()">
                    <i class="fas fa-times"></i> ${msg.get("common.cancel")}
                </button>
            </div>

            <div id="stopInstanceMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="stopInstanceText"></span>
            </div>
        </div>
    </div>
</div>

<!-- VPU修改模态框 -->
<div id="updateVpuModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("machine.updateVpu")}</h3>
        </div>
        <div id="updateVpuContent">
            <div style="margin-bottom: 20px;">
                <div style="margin-bottom: 15px;">
                    <label style="display: block; margin-bottom: 8px;">VPUs / GB
                        <span style="color: var(--text-secondary); font-size: 12px;">(0 ~ 120, step 10)</span>
                    </label>
                    <div style="display: flex; align-items: center; gap: 12px;">
                        <input type="range" id="vpuSlider" min="0" max="120" step="10" value="0"
                               style="flex: 1; accent-color: var(--accent-blue);"
                               oninput="document.getElementById('vpuValue').textContent = this.value">
                        <span id="vpuValue" style="min-width: 36px; text-align: center; font-weight: bold; color: var(--accent-blue); font-size: 16px;">0</span>
                    </div>
                    <div style="display: flex; justify-content: space-between; font-size: 10px; color: var(--text-secondary); margin-top: 4px; padding: 0 2px;">
                        <span>0</span><span>10</span><span>20</span><span>30</span><span>40</span><span>50</span><span>60</span><span>70</span><span>80</span><span>90</span><span>100</span><span>110</span><span>120</span>
                    </div>
                </div>
            </div>

            <div style="display: flex; gap: 10px; margin-bottom: 20px;">
                <button class="btn btn-success" onclick="confirmUpdateVpu()">
                    <i class="fas fa-check"></i> ${msg.get("common.confirm")}
                </button>
                <button class="btn btn-danger" onclick="closeUpdateVpuModal()">
                    <i class="fas fa-times"></i> ${msg.get("common.cancel")}
                </button>
            </div>

            <div id="updateVpuMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="updateVpuText"></span>
            </div>
        </div>
    </div>
</div>

<!-- 一键DD日志模态框 -->
<div id="ddLogModal" class="modal-overlay" style="display:none;">
    <div class="modal-container dd-log-modal">
        <#--<div class="modal-header">
            <h3 class="modal-title">一键DD系统执行日志</h3>
            <button class="btn btn-danger btn-sm" onclick="closeDdLogModal()">
                <i class="fas fa-times"></i> 关闭
            </button>
        </div>-->

        <div class="dd-log-body">
            <pre id="dd-log-window"></pre>
        </div>
    </div>
</div>




<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/common/custom-select.js"></script>
<script>
    window.I18N = {
        common_noData: "${msg.get('common.noData')?js_string}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        machine_changeIngIp: "${msg.get('machine.changeIngIp')?js_string}",
        machine_oldIp: "${msg.get('machine.oldIp')?js_string}",
        machine_newIp: "${msg.get('machine.newIp')?js_string}",
        machine_startingIpv6: "${msg.get("machine.startingIpv6")?js_string}",
        machine_ipv6: "${msg.get("machine.ipv6")?js_string}",
        machine_placeholder: "${msg.get("login.verify.code.placeholder")?js_string}",
        machine_deletingIns: "${msg.get("machine.deletingIns")?js_string}",
        notification_plzInputGlobalInfo: "${msg.get("notification.plzInputGlobalInfo"?js_string)}",
        machine_updatingMachine: "${msg.get("machine.updatingMachine"?js_string)}",
        machine_sendCode: "${msg.get("machine.sendCode")?js_string}",
        machine_plzInsName: "${msg.get("machine.plzInsName")?js_string}",
        machine_updatingMachName: "${msg.get("machine.updatingMachName")?js_string}",
        machine_diskSizeLimit: "${msg.get("machine.diskSizeLimit")?js_string}",
        machine_diskSizeLimitSum1: "${msg.get("machine.diskSizeLimitSum1")?js_string}",
        machine_diskSizeLimitSum2: "${msg.get("machine.diskSizeLimitSum2")?js_string}",
        common_loading: "${msg.get("common.loading")?js_string}",
        machine_plzIns: "${msg.get("machine.plzIns")?js_string}",
        openBoot_selectTenant: "${msg.get("openBoot.selectTenant")?js_string}",
        aiModel_tenant: "${msg.get("aiModel.tenant")?js_string}",
        openBoot_selectRegion: "${msg.get("openBoot.selectRegion")?js_string}",
        machine_startingIns: "${msg.get("machine.startingIns")?js_string}",
        machine_stopingIns: "${msg.get("machine.stopingIns")?js_string}",
        machine_running: "${msg.get("machine.running")?js_string}",
        machine_stopped: "${msg.get("machine.stopped")?js_string}",
        machine_starting: "${msg.get("machine.starting")?js_string}",
        machine_stopping: "${msg.get("machine.stopping")?js_string}",
        machine_temed: "${msg.get("machine.temed")?js_string}",
        machine_unKnow: "${msg.get("machine.unKnow")?js_string}",
        machine_osReset: "${msg.get("machine.osReset")?js_string}",
        machine_osSelect: "${msg.get("machine.osSelect")?js_string}",
        cost_other: "${msg.get("cost.other")?js_string}",
        machine_updatingRemark: "${msg.get("machine.updatingRemark")?js_string}",
        machine_notice: "${msg.get("machine.notice")?js_string}",
        machine_noticeSum1: "${msg.get("machine.noticeSum1")?js_string}",
        machine_noticeSum2: "${msg.get("machine.noticeSum2")?js_string}",
        machine_noticeSum3: "${msg.get("machine.noticeSum3")?js_string}",
        ins_plzOs: "${msg.get("ins.plzOs")?js_string}",
        machine_ddNewPass: "${msg.get("machine.ddNewPass")?js_string}",
        machine_ddplzPass: "${msg.get("machine.ddplzPass")?js_string}",
        machine_ddConfirm: "${msg.get("machine.ddConfirm")?js_string}",
        machine_startDdConfirm: "${msg.get("machine.startDdConfirm")?js_string}",
        vpn_edit: "${msg.get('vpn.edit')?js_string}",
        machine_start: "${msg.get('machine.start')?js_string}",
        machine_stop: "${msg.get('machine.stop')?js_string}",
        machine_tem: "${msg.get('machine.tem')?js_string}",
        machine_updateRemark: "${msg.get('machine.updateRemark')?js_string}",
        machine_updateName: "${msg.get('machine.updateName')?js_string}",
        machine_update: "${msg.get('machine.update')?js_string}",
        machine_updateDiskSize: "${msg.get('machine.updateDiskSize')?js_string}",
        machine_updateVpu: "${msg.get('machine.updateVpu')?js_string}",
        machine_copyIp: "${msg.get('machine.copyIp')?js_string}",
        machine_changeIp: "${msg.get('machine.changeIp')?js_string}",
        machine_copyIpv6: "${msg.get('machine.copyIpv6')?js_string}",
        machine_mgIpv6: "${msg.get('machine.mgIpv6')?js_string}",
        machine_startIpv6: "${msg.get('machine.startIpv6')?js_string}",
        machine_sshConn: "${msg.get('machine.sshConn')?js_string}",
        machine_console: "${msg.get('machine.console')?js_string}",
        machine_net: "${msg.get('machine.net')?js_string}",
        machine_deleteRecord: "${msg.get('machine.deleteRecord')?js_string}",
        token_enabled: "${msg.get('token.status.enabled')?js_string}",
        tenant_no: "${msg.get('tenant.no')?js_string}"
    }

    const i18n = window.I18N;

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

    // 租户名遮罩切换
    function toggleSpoiler(el) {
        if (el.classList.contains('is-hidden')) {
            el.classList.remove('is-hidden');
            el.classList.add('is-visible');
        } else {
            el.classList.remove('is-visible');
            el.classList.add('is-hidden');
        }
    }

    // 一键显示/隐藏所有租户名
    var _allSpoilersVisible = false;
    function toggleAllSpoilers() {
        _allSpoilersVisible = !_allSpoilersVisible;
        var spoilers = document.querySelectorAll('.name-spoiler');
        var icon = document.getElementById('toggleAllSpoilersIcon');
        spoilers.forEach(function(el) {
            if (_allSpoilersVisible) {
                el.classList.remove('is-hidden');
                el.classList.add('is-visible');
            } else {
                el.classList.remove('is-visible');
                el.classList.add('is-hidden');
            }
        });
        if (icon) {
            icon.className = _allSpoilersVisible ? 'fas fa-eye' : 'fas fa-eye-slash';
        }
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
                       placeholder="CIDR ( 10.0.0.0/24)"
                       style="flex: 1; padding: 8px; border: 1px solid var(--input-border); border-radius: 3px;">
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

        // 验证输入,可以为空
        /*if (cidrRanges.length === 0) {
            alert('请至少输入一个CIDR范围');
            return;
        }*/

        // 显示加载状态
        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = i18n.machine_changeIngIp;

        // 发送请求
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
                        statusText.textContent = data.message || 'IP切换成功';

                        if (data.details) {
                            changeIpDetails.style.display = 'block';
                            const detailsList = document.getElementById('changeIpDetailsList');
                            detailsList.innerHTML = '<div class="instance-info-item">' +
                                '<div><span class="info-label">'+i18n.machine_oldIp+': </span>' + data.details.oldIp + '</div>' +
                                '<div><span class="info-label">'+i18n.machine_newIp+': </span>' + data.details.newIp + '</div>' +
                                '</div>';
                        }

                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        throw new Error(data.message || 'error');
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = 'error';
                }
            }
        };

        xhr.onerror = function() {
            statusMessage.className = 'status-message error';
            statusText.textContent = 'error';
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

       /* const startRescueBtn = document.getElementById('startRescueBtn');
        if (startRescueBtn) {
            console.log('找到救援按钮，添加事件监听器');
            startRescueBtn.addEventListener('click', function() {
                console.log('按钮被点击');
                startSystemRescue();
            });
        } else {
            console.error('未找到救援按钮');
        }*/

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
        statusText.textContent = i18n.machine_startingIpv6;

        const xhr = new XMLHttpRequest();
        const csrfToken = document.querySelector('input[name="_csrf"]').value;

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
                                '<div><span class="info-label">'+i18n.machine_ipv6+': </span>' + data.details.ipv6Address + '</div>' +
                                '</div>';
                        }

                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        throw new Error(data.message || 'error');
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = 'error';
                }
            }
        };

        xhr.onerror = function() {
            statusMessage.className = 'status-message error';
            statusText.textContent = 'IPv6 error';
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
        statusText.textContent = i18n.machine_sendCode;

        // 发送请求获取验证码
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
                        // 显示验证码输入步骤
                        confirmStep.style.display = 'none';
                        document.getElementById('verifyStep').style.display = 'block';
                        statusMessage.style.display = 'none';
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent = data.message || 'error';
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = 'error';
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
            statusText.textContent = i18n.machine_placeholder;
            return;
        }

        // 显示加载状态
        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = i18n.machine_deletingIns;

        // 发送终止请求
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
                        statusText.textContent = 'success';

                        // 3秒后刷新页面
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent =  'error';
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = 'error';
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
            statusText.textContent = i18n.notification_plzInputGlobalInfo;
            return;
        }

        // 显示加载状态
        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = i18n.machine_updatingMachine;

        // 发送更新请求
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
                        statusText.textContent =  'success';

                        // 3秒后刷新页面
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent =  'error';
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = 'error';
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
            statusText.textContent = i18n.machine_plzInsName;
            return;
        }

        // 显示加载状态
        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = i18n.machine_updatingMachName;

        // 发送更新请求
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
                        statusText.textContent =  'success';

                        // 3秒后刷新页面
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent =  'error';
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = 'error';
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
            warning.textContent = i18n.machine_diskSizeLimit;
            confirmButton.disabled = true;
            return false;
        }

        if (newSize < currentVolumeSize) {
            warning.className = 'status-message error';
            warning.style.display = 'block';
            warning.innerHTML = '<i class="fas fa-exclamation-triangle"></i> '+i18n.machine_diskSizeLimitSum1;
            confirmButton.disabled = false;
        } else if (newSize > currentVolumeSize) {
            warning.className = 'status-message success';
            warning.style.display = 'block';
            warning.innerHTML = '<i class="fas fa-info-circle"></i> '+i18n.machine_diskSizeLimitSum2;
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
        const isExpand = newSize >= currentVolumeSize;

        // 显示加载状态
        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        if (isExpand) {
            statusText.textContent = "loading";
        } else {
            statusText.textContent = "loading";
        }

        // 发送更新请求
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
                        if (!data.message) {
                            if (isExpand) {
                                statusText.textContent = "successful";
                            } else {
                                statusText.textContent = "successful";
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
                                statusText.textContent = "error";
                            } else {
                                statusText.textContent = "error";
                            }
                        } else {
                            statusText.textContent = data.message;
                        }
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = 'error';
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
        statusText.textContent = i18n.machine_updatingRemark;

        // 发送更新请求
        const xhr = new XMLHttpRequest();
        const csrfToken = document.querySelector('input[name="_csrf"]').value;

        xhr.open('POST', '/oci/updateRemark', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = 'successful';

                        // 3秒后刷新页面
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent = 'error';
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = 'error';
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
        instanceSelect.innerHTML = '<option value="">'+i18n.common_loading+'</option>';
        instanceSelect.disabled = true;
        const csrfToken = document.querySelector('input[name="_csrf"]').value;
        const options = {
            headers: {
                'X-CSRF-TOKEN': csrfToken
            }
        };
        fetch('/tenants/listAll', options)
            .then(response => {
                if (!response.ok) {
                    throw new Error('network error');
                }
                return response.json();
            })
            .then(data => {
                instanceSelect.innerHTML = '<option value="">'+i18n.machine_plzIns+'</option>';
                instanceSelect.disabled = false;
                data.sort((a, b) => {
                    if (a.userName && b.userName) {
                        return a.userName.localeCompare(b.userName);
                    }
                    return 0;
                });
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
                instanceSelect.innerHTML = '<option value="">error</option>';
                instanceSelect.disabled = false;
            });
    }

    // 实例选择变更事件处理
    function instanceChanged() {
        selectedInstanceId = document.getElementById('instanceSelect').value;

        // 构建URL参数
        const urlParams = new URLSearchParams(window.location.search);
        if (!selectedInstanceId) {
            urlParams.delete('instanceId');
        } else {
            urlParams.set('instanceId', selectedInstanceId);
        }
        const page = urlParams.get('page');
        const size = urlParams.get('size');

        if (page !== null) {
            urlParams.set('page', page);
        }

        if (size !== null) {
            urlParams.set('size', size);
        }
        const newUrl = `/oci/list?` + urlParams.toString();
        window.location.href = newUrl;
    }
    let selectedTenantId = "";
    let selectedRegionId = "";

    document.addEventListener('DOMContentLoaded', () => {
        // 加载租户列表
        loadTenants();

        // 根据URL参数初始化选择
        const urlParams = new URLSearchParams(window.location.search);
        const tenantId = urlParams.get('tenantId');

        if (tenantId) {
            selectedTenantId = tenantId;
            var resetBtn = document.getElementById('resetFilterBtn');
            if (resetBtn) resetBtn.style.display = '';
        }

        const modal = document.getElementById('sshModal');
        if (modal) {
            modal.addEventListener('click', (e) => {
                if (e.target === modal) {
                    modal.style.display = 'none';
                    disconnectSsh();
                }
            });
        }

        // Close cascade dropdowns on outside click
    });

    function syncTenantDropdown() { loadRegions(); }

    function syncRegionDropdown() {
        selectedRegionId = document.getElementById('regionSelect').value;
        var goBtn = document.getElementById('goToInstanceBtn');
        if (goBtn) goBtn.disabled = !selectedRegionId;
    }

    // 加载租户列表
    function loadTenants() {
        const tenantSelect = document.getElementById('tenantSelect');
        tenantSelect.innerHTML = '<option value="">'+i18n.common_loading+'</option>';
        tenantSelect.disabled = true;
        const csrfToken = document.querySelector('input[name="_csrf"]').value;
        const options = { headers: { 'X-CSRF-TOKEN': csrfToken } };
        fetch('/tenants/listParentTenants', options)
            .then(response => {
                if (!response.ok) throw new Error('网络请求失败');
                return response.json();
            })
            .then(data => {
                tenantSelect.innerHTML = '<option value="">'+i18n.openBoot_selectTenant+'</option>';
                tenantSelect.disabled = false;
                data.sort((a, b) => (a.userName && b.userName) ? a.userName.localeCompare(b.userName) : 0);
                data.forEach(tenant => {
                    const option = document.createElement('option');
                    option.value = tenant.id;
                    option.textContent = tenant.userName || tenant.tenancyName || i18n.aiModel_tenant+tenant.id;
                    tenantSelect.appendChild(option);
                });
                // 如果URL中有租户ID，自动选择并加载区域
                if (selectedTenantId) {
                    tenantSelect.value = selectedTenantId;
                    CustomSelect.refresh(tenantSelect);
                    loadRegions();
                }
            })
            .catch(error => {
                console.error('加载租户列表失败:', error);
                tenantSelect.innerHTML = '<option value="">加载失败</option>';
                tenantSelect.disabled = false;
            });
    }

    // 加载区域列表
    function loadRegions() {
        const tenantSelect = document.getElementById('tenantSelect');
        const regionSelect = document.getElementById('regionSelect');
        const goToInstanceBtn = document.getElementById('goToInstanceBtn');
        selectedTenantId = tenantSelect.value;
        if (!selectedTenantId) {
            regionSelect.innerHTML = '<option value="">'+i18n.openBoot_selectRegion+'</option>';
            regionSelect.disabled = true;
            goToInstanceBtn.disabled = true;
            return;
        }
        regionSelect.innerHTML = '<option value="">'+i18n.common_loading+'</option>';
        regionSelect.disabled = true;
        goToInstanceBtn.disabled = true;
        const csrfToken = document.querySelector('input[name="_csrf"]').value;
        fetch('/tenants/listRegions?parentId=' + encodeURIComponent(selectedTenantId), {
            headers: { 'X-CSRF-TOKEN': csrfToken }
        })
            .then(response => {
                if (!response.ok) throw new Error('网络请求失败');
                return response.json();
            })
            .then(data => {
                regionSelect.innerHTML = '<option value="">'+i18n.openBoot_selectRegion+'</option>';
                if (data && data.length > 0) {
                    regionSelect.disabled = false;
                    data.sort((a, b) => (a.region && b.region) ? a.region.localeCompare(b.region) : 0);
                    data.forEach(region => {
                        const option = document.createElement('option');
                        option.value = region.id;
                        option.textContent = region.region || 'region ' + region.id;
                        regionSelect.appendChild(option);
                    });
                    // 自动选中：只有一个区域 或 URL中有匹配的区域ID
                    if (data.length === 1) {
                        regionSelect.value = data[0].id;
                        selectedRegionId = data[0].id;
                        goToInstanceBtn.disabled = false;
                        CustomSelect.refresh(regionSelect);
                    } else if (selectedRegionId) {
                        const regionIds = data.map(r => r.id);
                        if (regionIds.includes(selectedRegionId)) {
                            regionSelect.value = selectedRegionId;
                            goToInstanceBtn.disabled = false;
                            CustomSelect.refresh(regionSelect);
                        } else {
                            selectedRegionId = '';
                        }
                    }
                } else {
                    regionSelect.innerHTML = '<option value="">'+i18n.common_noData+'</option>';
                    regionSelect.disabled = true;
                    goToInstanceBtn.disabled = true;
                }
            })
            .catch(error => {
                console.error('加载区域列表失败:', error);
                regionSelect.innerHTML = '<option value="">加载失败</option>';
                regionSelect.disabled = true;
                goToInstanceBtn.disabled = true;
            });
    }
    function regionChanged() {
        const regionSelect = document.getElementById('regionSelect');
        const goToInstanceBtn = document.getElementById('goToInstanceBtn');
        selectedRegionId = regionSelect.value;
        goToInstanceBtn.disabled = !selectedRegionId;
    }

    /* ── AJAX pagination ── */

    var _currentTenantId = new URLSearchParams(window.location.search).get('tenantId') || '';

    function esc(str) {
        if (str == null) return '';
        return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;').replace(/'/g,'&#39;');
    }

    function maskName(name) {
        if (!name) return '';
        if (name.length > 2) return name.charAt(0) + '***' + name.charAt(name.length - 1);
        if (name.length > 0) return '***';
        return '';
    }

    function renderRows(instances, currentPage, pageSize) {
        if (!instances || instances.length === 0) {
            return '<tr><td colspan="11" style="text-align:center;padding:40px;color:var(--text-secondary);">' + esc(i18n.common_noData) + '</td></tr>';
        }
        var html = '';
        var prevTid = '';
        var grpIdx = 0;
        instances.forEach(function(ins, idx) {
            var tid = String(ins.tenantId);
            if (tid !== prevTid) {
                if (prevTid !== '') grpIdx++;
                prevTid = tid;
            }
            var grpClass = grpIdx % 2 === 0 ? 'tgrp-a' : 'tgrp-b';
            var seqNo = currentPage * pageSize + idx + 1;

            // state indicator
            var state = (ins.state || '').toLowerCase();
            var stateClass = 'status-stopped', stateTitle = i18n.machine_unKnow;
            if (state === 'running')   { stateClass = 'status-running';    stateTitle = i18n.machine_running; }
            else if (state === 'stopped') { stateClass = 'status-stopped'; stateTitle = i18n.machine_stopped; }
            else if (state === 'starting'){ stateClass = 'status-starting';stateTitle = i18n.machine_starting; }
            else if (state === 'stopping'){ stateClass = 'status-stopping';stateTitle = i18n.machine_stopping; }
            else if (state === 'terminated' || state === 'terminating') { stateClass = 'status-terminated'; stateTitle = i18n.machine_temed; }

            // tenant name masking
            var tn = ins.tenancyName || '';
            var maskedTn = maskName(tn);

            // ipv6
            var hasIpv6 = ins.ipv6Addresses && ins.ipv6Addresses.trim() !== '';

            // createTime
            var createTimeStr = '';
            if (ins.createTime) {
                var d = new Date(ins.createTime);
                createTimeStr = d.getFullYear() + '-' + String(d.getMonth()+1).padStart(2,'0') + '-' + String(d.getDate()).padStart(2,'0');
            }

            // start/stop button
            var startStopBtn = '';
            if (state === 'stopped') {
                startStopBtn = '<button class="dropdown-item" onclick="handleStartInstance(\'' + esc(ins.id) + '\')">' +
                    '<i class="fas fa-play"></i><span>' + esc(i18n.machine_start) + '</span></button>';
            } else if (state === 'running') {
                startStopBtn = '<button class="dropdown-item" onclick="handleStopInstance(\'' + esc(ins.id) + '\')">' +
                    '<i class="fas fa-stop"></i><span>' + esc(i18n.machine_stop) + '</span></button>';
            }

            // ipv6 buttons
            var ipv6Btns = '';
            if (hasIpv6) {
                ipv6Btns = '<button class="dropdown-item" onclick="copyToClipboard(\'' + esc(ins.ipv6Addresses) + '\', this)">' +
                    '<i class="fas fa-copy"></i><span>' + esc(i18n.machine_copyIpv6) + '</span></button>' +
                    '<button class="dropdown-item" onclick="handleChangeIpv6(\'' + esc(ins.id) + '\')">' +
                    '<i class="fas fa-globe"></i><span>' + esc(i18n.machine_mgIpv6) + '</span></button>';
            } else {
                ipv6Btns = '<button class="dropdown-item" onclick="handleChangeIpv6(\'' + esc(ins.id) + '\')">' +
                    '<i class="fas fa-plus-circle"></i><span>' + esc(i18n.machine_startIpv6) + '</span></button>';
            }

            var remark = ins.remark || '';
            var bootVolumeId = ins.bootVolumeId || '';

            html += '<tr class="' + grpClass + '">' +
                '<td style="text-align:center;color:var(--text-secondary);font-size:12px;">' + seqNo + '</td>' +
                '<td class="col-name"><span class="name-spoiler is-hidden" onclick="toggleSpoiler(this)" title="' + esc(tn) + '">' +
                    '<span class="name-masked">' + esc(maskedTn) + '</span>' +
                    '<span class="name-full">' + esc(tn) + '</span>' +
                '</span></td>' +
                '<td><span class="truncate" title="' + esc(ins.regionName) + '">' + esc(ins.regionName) + '</span></td>' +
                '<td><div class="instance-name-container">' +
                    '<span class="status-indicator ' + stateClass + '" title="' + esc(stateTitle) + '"></span>' +
                    '<span class="truncate" title="' + esc(ins.displayName) + '">' + esc(ins.displayName) + '</span>' +
                '</div></td>' +
                '<td style="min-width:70px;width:70px;"><span class="truncate">' + esc(ins.cpuAndMem) + '</span></td>' +
                '<td><span class="truncate">' + esc(ins.architecture) + '</span></td>' +
                '<td style="min-width:90px;width:90px;"><span>' + (ins.bootVolumeSizeInGBs || '') + 'GB/' + (ins.vpusPerGB || 0) + '</span></td>' +
                '<td><span class="truncate" title="' + esc(ins.publicIps) + '">' + esc(ins.publicIps) + '</span></td>' +
                '<td>' + (hasIpv6
                    ? '<span class="truncate" title="' + esc(ins.ipv6Addresses) + '">' + esc(i18n.token_enabled) + '</span>'
                    : '<span class="ipv6-empty">' + esc(i18n.tenant_no) + '</span>') + '</td>' +
                '<td style="white-space:nowrap;font-size:12px;color:var(--text-secondary);">' + createTimeStr + '</td>' +
                '<td class="actions-cell">' +
                    '<div class="dropdown">' +
                        '<button class="dropdown-toggle btn" onclick="handleDynamicToggle(this, event)"><i class="fas fa-ellipsis-h"></i></button>' +
                        '<div class="dropdown-panel">' +
                            startStopBtn +
                            '<button class="dropdown-item danger" onclick="handleTerminateInstance(\'' + esc(ins.id) + '\')">' +
                                '<i class="fas fa-stop-circle"></i><span>' + esc(i18n.machine_tem) + '</span></button>' +
                            '<button class="dropdown-item" onclick="handleUpdateRemark(\'' + esc(ins.id) + '\',\'' + esc(remark).replace(/'/g,"\\'") + '\')">' +
                                '<i class="fas fa-sticky-note"></i><span>' + esc(i18n.machine_updateRemark) + '</span></button>' +
                            '<button class="dropdown-item" onclick="handleUpdateName(\'' + esc(ins.id) + '\',\'' + esc(ins.displayName).replace(/'/g,"\\'") + '\')">' +
                                '<i class="fas fa-tag"></i><span>' + esc(i18n.machine_updateName) + '</span></button>' +
                            '<button class="dropdown-item" onclick="handleUpdateConfig(\'' + esc(ins.id) + '\',' + (ins.ocpus||0) + ',' + (ins.memoryInGBs||0) + ')">' +
                                '<i class="fas fa-microchip"></i><span>' + esc(i18n.machine_update) + '</span></button>' +
                            '<button class="dropdown-item" onclick="handleUpdateBootVolume(\'' + esc(ins.id) + '\',' + (ins.bootVolumeSizeInGBs||0) + ')">' +
                                '<i class="fas fa-hdd"></i><span>' + esc(i18n.machine_updateDiskSize) + '</span></button>' +
                            '<button class="dropdown-item" onclick="handleUpdateVpu(\'' + esc(bootVolumeId) + '\',\'' + (ins.tenantIdStr || String(ins.tenantId)) + '\',' + (ins.vpusPerGB || 0) + ',\'' + esc(ins.id) + '\')">' +
                                '<i class="fas fa-sliders-h"></i><span>' + esc(i18n.machine_updateVpu) + '</span></button>' +
                            '<button class="dropdown-item" onclick="copyToClipboard(\'' + esc(ins.publicIps) + '\',this)">' +
                                '<i class="fas fa-copy"></i><span>' + esc(i18n.machine_copyIp) + '</span></button>' +
                            '<button class="dropdown-item" onclick="handleChangeIp(\'' + esc(ins.id) + '\')">' +
                                '<i class="fas fa-sync-alt"></i><span>' + esc(i18n.machine_changeIp) + '</span></button>' +
                            ipv6Btns +
                            '<a href="/oci/terminal?instanceId=' + esc(ins.id) + '" class="dropdown-item">' +
                                '<i class="fas fa-terminal"></i><span>' + esc(i18n.machine_sshConn) + '</span></a>' +
                            '<a href="/oci/console/terminal/' + esc(ins.id) + '" class="dropdown-item">' +
                                '<i class="fas fa-tv"></i><span>' + esc(i18n.machine_console) + '</span></a>' +
                            '<a href="/oci/vnic/manage?instanceId=' + esc(ins.instanceId) + '" class="dropdown-item">' +
                                '<i class="fas fa-sitemap"></i><span>' + esc(i18n.machine_net) + '</span></a>' +
                            '<button class="dropdown-item" onclick="handleQuickDD(\'' + esc(ins.id) + '\',\'' + esc(ins.displayName).replace(/'/g,"\\'") + '\')">' +
                                '<i class="fas fa-undo"></i><span>' + esc(i18n.machine_osReset) + '</span></button>' +
                            '<button class="dropdown-item danger" onclick="handleDeleteRecord(\'' + esc(ins.id) + '\',\'' + esc(ins.displayName).replace(/'/g,"\\'") + '\')">' +
                                '<i class="fas fa-trash-alt"></i><span>' + esc(i18n.machine_deleteRecord) + '</span></button>' +
                        '</div>' +
                    '</div>' +
                '</td>' +
            '</tr>';
        });
        return html;
    }

    function updatePaginationUI(currentPage, totalPages) {
        // Update page number buttons
        document.querySelectorAll('.page-btn').forEach(function(btn) {
            var onclick = btn.getAttribute('onclick') || '';
            var m = onclick.match(/gotoPage\((\d+)/);
            if (m) {
                var p = parseInt(m[1]);
                btn.classList.toggle('active', p === currentPage);
            }
        });
        // Update prev/next buttons (also update onclick so stale FTL-rendered handlers don't break AJAX navigation)
        document.querySelectorAll('.prev-btn').forEach(function(b) {
            b.disabled = currentPage <= 0;
            b.classList.toggle('disabled', currentPage <= 0);
            b.setAttribute('onclick', 'gotoPage(' + (currentPage - 1) + ', \'/oci/list\')');
        });
        document.querySelectorAll('.next-btn').forEach(function(b) {
            b.disabled = currentPage >= totalPages - 1;
            b.classList.toggle('disabled', currentPage >= totalPages - 1);
            b.setAttribute('onclick', 'gotoPage(' + (currentPage + 1) + ', \'/oci/list\')');
        });
        // Update jump input placeholder
        var jumpInput = document.getElementById('jumpPageInput');
        if (jumpInput) jumpInput.value = currentPage + 1;
        // Update page info text
        var pageInfoEl = document.querySelector('.page-info');
        if (pageInfoEl) {
            var strong = pageInfoEl.querySelectorAll('strong');
            if (strong[0]) strong[0].textContent = currentPage + 1;
            if (strong[1]) strong[1].textContent = totalPages;
        }
    }

    var _ajaxLoading = false;

    function loadPage(page, size, tenantId) {
        if (_ajaxLoading) return;
        _ajaxLoading = true;
        var tbody = document.querySelector('#instance-table-body');
        if (tbody) tbody.style.opacity = '0.4';

        var params = new URLSearchParams();
        params.set('page', page);
        params.set('size', size);
        if (tenantId) params.set('tenantId', tenantId);

        var csrfToken = document.querySelector('meta[name="_csrf"]').getAttribute('content');
        fetch('/oci/list/json?' + params.toString(), {
            headers: { 'X-CSRF-TOKEN': csrfToken }
        })
        .then(function(r) { return r.json(); })
        .then(function(data) {
            if (tbody) {
                tbody.innerHTML = renderRows(data.content, data.currentPage, data.size);
                tbody.style.opacity = '1';
            }
            updatePaginationUI(data.currentPage, data.totalPages);

            // Sync URL without reload
            var newParams = new URLSearchParams(window.location.search);
            newParams.set('page', data.currentPage);
            newParams.set('size', data.size);
            if (tenantId) newParams.set('tenantId', tenantId);
            else newParams.delete('tenantId');
            history.pushState({ page: data.currentPage, size: data.size, tenantId: tenantId }, '', '/oci/list?' + newParams.toString());

            // Sync _allSpoilersVisible state: reset all spoilers to hidden after page change
            _allSpoilersVisible = false;
            var icon = document.getElementById('toggleAllSpoilersIcon');
            if (icon) icon.className = 'fas fa-eye-slash';
        })
        .catch(function(e) {
            console.error('加载失败', e);
            if (tbody) tbody.style.opacity = '1';
        })
        .finally(function() {
            _ajaxLoading = false;
        });
    }

    function resetFilter() {
        _currentTenantId = '';
        var resetBtn = document.getElementById('resetFilterBtn');
        if (resetBtn) resetBtn.style.display = 'none';
        var curSize = parseInt(document.getElementById('pageSizeSelect').value) || 10;
        loadPage(0, curSize, '');
    }

    function goToInstances() {
        if (!selectedRegionId) return;
        _currentTenantId = selectedRegionId;
        var resetBtn = document.getElementById('resetFilterBtn');
        if (resetBtn) resetBtn.style.display = '';
        var curSize = parseInt(document.getElementById('pageSizeSelect').value) || 10;
        loadPage(0, curSize, _currentTenantId);
    }

    // 添加启动实例处理函数
    function handleStartInstance(instanceId) {
        const modal = document.getElementById('startInstanceModal');
        const statusMessage = document.getElementById('startInstanceMessage');
        statusMessage.style.display = 'none';
        modal.setAttribute('data-instance-id', instanceId);
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
        statusText.textContent = i18n.machine_startingIns;

        // 发送请求
        const xhr = new XMLHttpRequest();
        const csrfToken = document.querySelector('input[name="_csrf"]').value;

        xhr.open('POST', '/oci/startInstance', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = 'success';
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent = 'error';
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = 'error';
                }
            }
        };

        xhr.onerror = function() {
            statusMessage.className = 'status-message error';
            statusText.textContent = 'error and try';
        };

        xhr.send(JSON.stringify({
            instanceId: instanceId
        }));
    }

    function closeStartInstanceModal() {
        const modal = document.getElementById('startInstanceModal');
        modal.style.display = 'none';
    }
    function handleStopInstance(instanceId) {
        const modal = document.getElementById('stopInstanceModal');
        const statusMessage = document.getElementById('stopInstanceMessage');
        statusMessage.style.display = 'none';
        modal.setAttribute('data-instance-id', instanceId);
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
        statusText.textContent = i18n.machine_stopingIns;

        // 发送请求
        const xhr = new XMLHttpRequest();
        const csrfToken = document.querySelector('input[name="_csrf"]').value;

        xhr.open('POST', '/oci/stopInstance', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    const data = JSON.parse(xhr.responseText);
                    if (data.success) {
                        statusMessage.className = 'status-message success';
                        statusText.textContent = 'success';

                        // 3秒后刷新页面
                        setTimeout(() => {
                            modal.style.display = 'none';
                            location.reload();
                        }, 3000);
                    } else {
                        statusMessage.className = 'status-message error';
                        statusText.textContent = 'error';
                    }
                } else {
                    statusMessage.className = 'status-message error';
                    statusText.textContent = 'error';
                }
            }
        };

        xhr.onerror = function() {
            statusMessage.className = 'status-message error';
            statusText.textContent = 'error';
        };

        xhr.send(JSON.stringify({
            instanceId: instanceId
        }));
    }

    function closeStopInstanceModal() {
        const modal = document.getElementById('stopInstanceModal');
        modal.style.display = 'none';
    }


    function copyToClipboard(text, element) {
        const textArea = document.createElement('textarea');
        textArea.value = text;
        textArea.style.position = 'fixed';
        textArea.style.left = '-999999px';
        textArea.style.top = '-999999px';
        document.body.appendChild(textArea);

        try {
            textArea.focus();
            textArea.select();
            document.execCommand('copy');
            showCopySuccess(element);
            Swal.fire({
                icon: 'success',
                title: 'successful',
                text: text ,
                timer: 1500,
                showConfirmButton: false,
                toast: true,
                position: 'top-end'
            });

        } catch (err) {
            if (navigator.clipboard && navigator.clipboard.writeText) {
                navigator.clipboard.writeText(text).then(() => {
                    showCopySuccess(element);
                    Swal.fire({
                        icon: 'success',
                        title: 'successful',
                        text: text ,
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

    function showCopySuccess(element) {
        const icon = element.querySelector('i');
        const originalClass = icon.className;

        icon.className = 'fas fa-check';
        element.classList.add('copy-success');
        element.style.color = '#4caf50';

        setTimeout(() => {
            icon.className = originalClass;
            element.classList.remove('copy-success');
            element.style.color = '';
        }, 800);
    }

    function showCopyError() {
        Swal.fire({
            icon: 'error',
            title: 'error',
            timer: 2000,
            showConfirmButton: false,
            toast: true,
            position: 'top-end'
        });
    }
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

    function initializeStatusIndicators() {
        document.querySelectorAll('.status-indicator').forEach(indicator => {
            const statusClass = indicator.className.split(' ').find(cls => cls.startsWith('status-'));
            let statusText = '';

            switch (statusClass) {
                case 'status-running':
                    statusText = i18n.machine_running;
                    break;
                case 'status-stopped':
                    statusText = i18n.machine_stopped;
                    break;
                case 'status-starting':
                    statusText = i18n.machine_starting;
                    break;
                case 'status-stopping':
                    statusText = i18n.machine_stopping;
                    break;
                case 'status-terminated':
                    statusText = i18n.machine_temed;
                    break;
                default:
                    statusText = i18n.machine_unKnow;
            }

            indicator.title = statusText;
        });
    }

    function handleDeleteRecord(instanceId, instanceName) {
        event.preventDefault();
        Swal.fire({
            title: '${msg.get("machine.deleteRecord")}',
            html: '<p style="color:var(--text-primary)">确认删除实例 <strong>' + instanceName + '</strong> 的本地记录？<br/><span style="color:var(--accent-red);font-size:13px;">此操作仅删除本地数据，不会操作OCI云端实例。</span></p>',
            icon: 'warning',
            showCancelButton: true,
            confirmButtonText: '${msg.get("common.confirm")}',
            cancelButtonText: '${msg.get("common.cancel")}',
            confirmButtonColor: '#e74c3c',
            cancelButtonColor: '#95a5a6'
        }).then(function(result) {
            if (result.isConfirmed) {
                var csrfToken = document.querySelector('meta[name="_csrf"]').getAttribute('content');
                var csrfHeader = document.querySelector('meta[name="_csrf_header"]').getAttribute('content');
                var headers = { 'Content-Type': 'application/json' };
                headers[csrfHeader] = csrfToken;
                fetch('/oci/deleteInstanceRecord', {
                    method: 'POST',
                    headers: headers,
                    body: JSON.stringify({ id: instanceId })
                }).then(function(r) { return r.json(); }).then(function(data) {
                    if (data.code === 200 || data.success) {
                        Swal.fire({ icon: 'success', title: '删除成功', timer: 1200, showConfirmButton: false })
                            .then(function() { location.reload(); });
                    } else {
                        Swal.fire({ icon: 'error', title: '删除失败', text: data.message || data.msg || '' });
                    }
                }).catch(function(e) {
                    Swal.fire({ icon: 'error', title: '请求失败', text: e.message });
                });
            }
        });
    }

    function handleQuickDD(instanceId, instanceName) {
        event.preventDefault();

        Swal.fire({
            title: i18n.machine_osReset,
            html: `
                <div style="text-align: left; max-width: 500px;">
                    <div style="margin-bottom: 20px;">
                        <label style="display: block; margin-bottom: 8px; font-weight: 600; font-size: 14px; color: var(--text-primary);">`+i18n.machine_osSelect+`</label>
                        <select id="ddOsSelect" style="width: 100%; padding: 12px 14px; border: 1px solid var(--input-border); border-radius: 6px; font-size: 14px; background: var(--input-bg); color: var(--text-primary); cursor: pointer; transition: all 0.3s ease;">
                            <option value="">`+i18n.ins_plzOs+`</option>
                            <optgroup label="Alpine">
                                <option value="alpine|3.19">Alpine 3.19</option>
                                <option value="alpine|3.20">Alpine 3.20</option>
                                <option value="alpine|3.21">Alpine 3.21</option>
                                <option value="alpine|3.22">Alpine 3.22</option>
                            </optgroup>
                            <optgroup label="Debian">
                                <option value="debian|9">Debian 9</option>
                                <option value="debian|10">Debian 10</option>
                                <option value="debian|11">Debian 11</option>
                                <option value="debian|12">Debian 12</option>
                                <option value="debian|13">Debian 13</option>
                            </optgroup>
                            <optgroup label="Ubuntu">
                                <option value="ubuntu|16.04">Ubuntu 16.04</option>
                                <option value="ubuntu|18.04">Ubuntu 18.04</option>
                                <option value="ubuntu|20.04">Ubuntu 20.04</option>
                                <option value="ubuntu|22.04">Ubuntu 22.04</option>
                                <option value="ubuntu|24.04">Ubuntu 24.04</option>
                                <option value="ubuntu|25.10">Ubuntu 25.10</option>
                            </optgroup>
                            <optgroup label="RHEL">
                                <option value="centos|9">CentOS 9</option>
                                <option value="centos|10">CentOS 10</option>
                                <option value="rocky|8">Rocky 8</option>
                                <option value="rocky|9">Rocky 9</option>
                                <option value="rocky|10">Rocky 10</option>
                                <option value="almalinux|8">AlmaLinux 8</option>
                                <option value="almalinux|9">AlmaLinux 9</option>
                                <option value="almalinux|10">AlmaLinux 10</option>
                                <option value="oracle|8">Oracle 8</option>
                                <option value="oracle|9">Oracle 9</option>
                                <option value="oracle|10">Oracle 10</option>
                                <option value="fedora|41">Fedora 41</option>
                                <option value="fedora|42">Fedora 42</option>
                            </optgroup>
                            <optgroup label="Other">
                                <option value="anolis|7">Anolis 7</option>
                                <option value="anolis|8">Anolis 8</option>
                                <option value="anolis|23">Anolis 23</option>
                                <option value="opencloudos|8">OpenCloudOS 8</option>
                                <option value="opencloudos|9">OpenCloudOS 9</option>
                                <option value="openeuler|20.03">OpenEuler 20.03</option>
                                <option value="openeuler|22.03">OpenEuler 22.03</option>
                                <option value="openeuler|24.03">OpenEuler 24.03</option>
                                <option value="openeuler|25.09">OpenEuler 25.09</option>
                                <option value="opensuse|15.6">OpenSUSE 15.6</option>
                                <option value="opensuse|16.0">OpenSUSE 16.0</option>
                                <option value="opensuse|tumbleweed">OpenSUSE Tumbleweed</option>
                                <option value="nixos|25.05">NixOS 25.05</option>
                                <option value="kali|">Kali Linux</option>
                                <option value="arch|">Arch Linux</option>
                                <option value="gentoo|">Gentoo</option>
                                <option value="aosc|">AOSC</option>
                                <option value="fnos|">FNOS</option>
                                <option value="netboot.xyz|">Netboot.xyz</option>
                            </optgroup>
                        </select>
                    </div>
                    <div style="margin-bottom: 20px;">
                        <label style="display: block; margin-bottom: 8px; font-weight: 600; font-size: 14px; color: var(--text-primary);"> ` +i18n.machine_ddNewPass+`</label>
                        <div style="position: relative;">
                            <input type="password" id="ddPassword" placeholder="` +i18n.machine_ddNewPass+`" style="width: 100%; padding: 12px 14px; border: 1px solid var(--input-border); border-radius: 6px; font-size: 14px; background: var(--input-bg); color: var(--text-primary); box-sizing: border-box; transition: all 0.3s ease;" onfocus="this.style.borderColor='#6c5ce7'; this.style.boxShadow='0 0 0 3px rgba(108, 92, 231, 0.1)'" onblur="this.style.borderColor=''; this.style.boxShadow='none'">
                            <button type="button" onclick="togglePasswordVisibility()" style="position: absolute; right: 12px; top: 50%; transform: translateY(-50%); background: none; border: none; color: var(--text-secondary); cursor: pointer; font-size: 16px; padding: 0;">
                                <i class="fas fa-eye" id="ddPasswordIcon"></i>
                            </button>
                        </div>
                    </div>
                    <div style="margin-top: 20px; padding: 12px 14px; background: var(--surface-2); border: 1px solid var(--accent-red); border-radius: 6px;">
                        <p style="margin: 0; font-size: 13px; color: var(--text-primary); line-height: 1.8;">
                            <strong style="color: var(--accent-red);">`+i18n.machine_notice+`：</strong><br/>
                            `+i18n.machine_noticeSum1+` <a href="https://github.com/bin456789/reinstall" target="_blank" style="color: var(--accent-blue); text-decoration: none; font-weight: 600;">reinstall</a> `+i18n.machine_noticeSum2+`<br/>
                            <span style="color: var(--accent-red);">`+i18n.machine_noticeSum3+`</span>
                        </p>
                    </div>
                </div>
            `,
            showCancelButton: true,
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel,
            confirmButtonColor: '#6c5ce7',
            cancelButtonColor: '#95a5a6',
            preConfirm: function() {
                var osSelect = document.getElementById('ddOsSelect').value;
                var password = document.getElementById('ddPassword').value;

                if (!osSelect) {
                    Swal.showValidationMessage(i18n.ins_plzOs);
                    return false;
                }
                if (!password) {
                    Swal.showValidationMessage(i18n.machine_ddplzPass);
                    return false;
                }

                var osArr = osSelect.split('|');
                return {
                    os: osArr[0],
                    version: osArr[1],
                    password: password
                };
            }
        }).then(function(result) {
            if (result.isConfirmed) {
                showDDConfirmation(instanceId, instanceName, result.value);
            }
        });
    }

    function togglePasswordVisibility() {
        var passwordInput = document.getElementById('ddPassword');
        var passwordIcon = document.getElementById('ddPasswordIcon');

        if (passwordInput.type === 'password') {
            passwordInput.type = 'text';
            passwordIcon.classList.remove('fa-eye');
            passwordIcon.classList.add('fa-eye-slash');
        } else {
            passwordInput.type = 'password';
            passwordIcon.classList.remove('fa-eye-slash');
            passwordIcon.classList.add('fa-eye');
        }
    }

    function showDDConfirmation(instanceId, instanceName, params) {
        Swal.fire({
            title: i18n.machine_ddConfirm,
            icon: 'warning',
            showCancelButton: true,
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel,
            confirmButtonColor: '#d33'
        }).then(function(result) {
            if (result.isConfirmed) {
                executeDDToBackend(instanceId, params);
            }
        });
    }

    // 打开日志模态框
    function openDdLogModal() {
        document.getElementById("ddLogModal").style.display = "flex";
    }
    function closeDdLogModal() {
        document.getElementById("ddLogModal").style.display = "none";
    }

    function executeDDToBackend(instanceId, params) {

        openDdLogModal();
        $("#dd-log-window").text("");

        const requestData = {
            instanceId: instanceId,
            osType: params.os,
            osVersion: params.version,
            ddPassword: params.password
        };

        const es = new EventSource("/oci/instance/quickDD?" + new URLSearchParams(requestData));

        appendLog(i18n.machine_startDdConfirm+"\n");

        es.addEventListener("log", function (e) {
            appendLog(e.data);
        });

        es.addEventListener("success", function (e) {
            appendLog("\n" + e.data + "\n");
        });

        es.addEventListener("complete", function (e) {
            appendLog("\n" + e.data + "\n");
            es.close();
        });

        es.addEventListener("error", function (e) {
            es.close();
        });

    }


    function appendLog(msg) {
        const pre = $("#dd-log-window");
        pre.append(msg + "\n");

        const scrollBox = $(".dd-log-body");
        scrollBox.scrollTop(scrollBox[0].scrollHeight);
    }

    function handleUpdateVpu(bootVolumeId, tenantId, currentVpus, instanceDetailId) {
        if (!bootVolumeId || bootVolumeId === '-1' || bootVolumeId === '') {
            showError('Error', 'Boot volume ID not found for this instance.');
            return;
        }
        const modal = document.getElementById('updateVpuModal');
        const slider = document.getElementById('vpuSlider');
        const valueDisplay = document.getElementById('vpuValue');
        const initVpus = currentVpus != null ? currentVpus : 0;
        slider.value = initVpus;
        valueDisplay.textContent = initVpus;
        document.getElementById('updateVpuMessage').style.display = 'none';
        modal.setAttribute('data-boot-volume-id', bootVolumeId);
        modal.setAttribute('data-tenant-id', tenantId);
        modal.setAttribute('data-instance-detail-id', instanceDetailId || '');
        modal.style.display = 'flex';
    }

    function confirmUpdateVpu() {
        const modal = document.getElementById('updateVpuModal');
        const bootVolumeId = modal.getAttribute('data-boot-volume-id');
        const tenantId = modal.getAttribute('data-tenant-id');
        const instanceDetailIdStr = modal.getAttribute('data-instance-detail-id');
        const instanceDetailId = instanceDetailIdStr ? parseInt(instanceDetailIdStr, 10) : null;
        const vpus = parseInt(document.getElementById('vpuSlider').value);
        const statusMessage = document.getElementById('updateVpuMessage');
        const statusText = document.getElementById('updateVpuText');

        statusMessage.className = 'status-message syncing';
        statusMessage.style.display = 'block';
        statusText.textContent = i18n.common_loading;

        const csrfToken = document.querySelector('input[name="_csrf"]').value;

        fetch('/tenants/update-volumes/' + encodeURIComponent(bootVolumeId), {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrfToken },
            body: JSON.stringify({ vpusPerGB: vpus, tenantId: tenantId, instanceDetailId: instanceDetailId })
        })
        .then(r => r.json())
        .then(data => {
            if (data.success) {
                statusMessage.className = 'status-message success';
                statusText.textContent = data.message || 'success';
                setTimeout(() => { modal.style.display = 'none'; location.reload(); }, 3000);
            } else {
                statusMessage.className = 'status-message error';
                statusText.textContent = data.message || 'error';
            }
        })
        .catch(() => {
            statusMessage.className = 'status-message error';
            statusText.textContent = 'error';
        });
    }

    function closeUpdateVpuModal() {
        document.getElementById('updateVpuModal').style.display = 'none';
    }

    // Override pagination.ftl functions to use AJAX
    function gotoPage(targetPage, url) {
        var size = parseInt(document.getElementById('pageSizeSelect').value) || 10;
        if (targetPage < 0) return;
        loadPage(targetPage, size, _currentTenantId);
    }

    function jumpToPage(url) {
        var input = document.getElementById('jumpPageInput');
        var targetPage = parseInt(input.value) - 1;
        var size = parseInt(document.getElementById('pageSizeSelect').value) || 10;
        if (isNaN(targetPage) || targetPage < 0) return;
        loadPage(targetPage, size, _currentTenantId);
    }

    function changePageSize(newSize, url, currentPage) {
        document.getElementById('pageSizeSelect').value = newSize;
        var label = document.getElementById('pageSizeBtnLabel');
        if (label) label.textContent = newSize;
        loadPage(0, newSize, _currentTenantId);
    }

</script>
</body>
</html>