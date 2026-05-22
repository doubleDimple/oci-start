<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 网络管理</title>
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
    <link rel="stylesheet" href="/css/app/oci_network_manage.css">
    <link rel="stylesheet" href="/css/common/loading.css">

    <!-- SweetAlert2 CSS -->
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <!-- SweetAlert2 JS -->
    <script src="/js/sweetalert2.min.js"></script>

</head>
<body>
<#--<#include "common/version_info.ftl">-->
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
    <div class="page-card">
        <!-- 页面标题 -->
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-network-wired"></i>
                <span>${msg.get("net.config")}</span>
            </h1>
            <div style="display: flex; gap: 10px;">
                <button class="btn btn-primary" onclick="refreshVnicInfo()">
                    <i class="fas fa-sync-alt"></i> ${msg.get("email.refresh")}
                </button>
                <a href="/oci/list" class="btn btn-secondary" id="backButton">
                    <i class="fas fa-arrow-left"></i> ${msg.get("common.rollback")}
                </a>
            </div>
        </div>

        <!-- 统计信息 -->
        <div class="stats-grid">
            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon primary">
                        <i class="fas fa-network-wired"></i>
                    </div>
                    <div class="stat-title">${msg.get("net.vncs")}</div>
                </div>
                <div class="stat-value" id="totalVnicCount">0</div>
                <div class="stat-description">${msg.get("net.vncAndOther")}</div>
            </div>

            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon success">
                        <i class="fas fa-check-circle"></i>
                    </div>
                    <div class="stat-title">${msg.get("net.activeVnic")}</div>
                </div>
                <div class="stat-value" id="activeVnicCount">0</div>
                <div class="stat-description">${msg.get("net.activeVnics")}</div>
            </div>

            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon warning">
                        <i class="fas fa-plus-circle"></i>
                    </div>
                    <div class="stat-title">${msg.get("net.otherVnic")}</div>
                </div>
                <div class="stat-value" id="secondaryVnicCount">0</div>
                <div class="stat-description">${msg.get("net.otherNetInterface")}</div>
            </div>

            <div class="stat-card">
                <div class="stat-header">
                    <div class="stat-icon info">
                        <i class="fas fa-globe"></i>
                    </div>
                    <div class="stat-title">${msg.get("machine.ipv6")}</div>
                </div>
                <div class="stat-value" id="totalIpv6Count">0</div>
                <div class="stat-description">${msg.get("net.ipv6s")}</div>
            </div>
        </div>

        <div class="load-balancer-section">
            <div class="load-balancer-content">
                <div class="load-balancer-title">
                    <i class="fas fa-balance-scale"></i>
                    ${msg.get("net.advancedNetConfig")}
                </div>
                <div class="load-balancer-description">
                    ${msg.get("net.advancedNetConfigSummary")}
                </div>
                <div class="load-balancer-actions">
                    <button class="btn btn-purple" onclick="showLoadBalancerModal()">
                        <i class="fas fa-rocket"></i> ${msg.get("net.activeLb")}
                    </button>
                    <button class="btn btn-warning" onclick="showRestoreNetworkModal()">
                        <i class="fas fa-undo"></i> ${msg.get("net.restoreLb")}
                    </button>
                </div>
            </div>
        </div>

        <!-- 负载均衡配置模态框 -->
        <div id="loadBalancerModal" class="modal-overlay">
            <div class="modal-container">
                <div class="modal-header">
                    <h3 class="modal-title">${msg.get("net.startLb")}</h3>
                </div>
                <div class="modal-body">
                    <div id="loadBalancerProgress" style="display: none;">
                        <div class="progress-container">
                            <div class="progress-bar">
                                <div class="progress-fill" id="progressFill"></div>
                            </div>
                            <div class="progress-text" id="progressText">${msg.get("net.starting")}</div>
                        </div>

                        <div class="progress-steps">
                            <div class="progress-step" id="step1">
                                <div class="progress-step-icon">
                                    <i class="fas fa-circle"></i>
                                </div>
                                <span>${msg.get("net.createNetGateway")}</span>
                            </div>
                            <div class="progress-step" id="step2">
                                <div class="progress-step-icon">
                                    <i class="fas fa-circle"></i>
                                </div>
                                <span>${msg.get("net.createRouteTable")}</span>
                            </div>
                            <div class="progress-step" id="step3">
                                <div class="progress-step-icon">
                                    <i class="fas fa-circle"></i>
                                </div>
                                <span>${msg.get("net.refreshNet")}</span>
                            </div>
                            <div class="progress-step" id="step4">
                                <div class="progress-step-icon">
                                    <i class="fas fa-circle"></i>
                                </div>
                                <span>${msg.get("net.createLb")}</span>
                            </div>
                            <div class="progress-step" id="step5">
                                <div class="progress-step-icon">
                                    <i class="fas fa-circle"></i>
                                </div>
                                <span>${msg.get("net.finish")}</span>
                            </div>
                        </div>
                    </div>

                    <div id="loadBalancerInitial">
                        <div class="status-message info">
                            <i class="fas fa-info-circle"></i>
                            <div>
                                <strong>${msg.get("net.toast")}：</strong>
                                <ul style="margin: 5px 0; padding-left: 20px;">
                                    <li>${msg.get("net.toast1")}</li>
                                    <li>${msg.get("net.toast2")}</li>
                                    <li>${msg.get("net.toast3")}</li>
                                </ul>
                            </div>
                        </div>
                    </div>

                    <div id="loadBalancerResult" style="display: none;">
                        <div id="resultMessage"></div>
                        <div id="resultDetails"></div>
                    </div>
                </div>
                <div class="modal-footer">
                    <button class="btn btn-purple" onclick="startLoadBalancerConfig()" id="confirmLoadBalancerBtn">
                        <i class="fas fa-check"></i> ${msg.get("common.confirm")}
                    </button>
                    <button class="btn btn-secondary" onclick="closeLoadBalancerModal()" id="cancelLoadBalancerBtn">
                        <i class="fas fa-times"></i> ${msg.get("common.cancel")}
                    </button>
                </div>
            </div>
        </div>

        <!-- 还原网络配置模态框 -->
        <div id="restoreNetworkModal" class="modal-overlay">
            <div class="modal-container">
                <div class="modal-header">
                    <h3 class="modal-title">${msg.get("net.restoreLb")}</h3>
                </div>
                <div class="modal-body">
                    <div id="restoreNetworkProgress" style="display: none;">
                        <div class="progress-container">
                            <div class="progress-bar">
                                <div class="progress-fill" id="restoreProgressFill"></div>
                            </div>
                            <div class="progress-text" id="restoreProgressText">${msg.get("net.starting")}</div>
                        </div>

                        <div class="progress-steps">
                            <div class="progress-step" id="restoreStep1">
                                <div class="progress-step-icon">
                                    <i class="fas fa-circle"></i>
                                </div>
                                <span>${msg.get("net.checkConfig")}</span>
                            </div>
                            <div class="progress-step" id="restoreStep2">
                                <div class="progress-step-icon">
                                    <i class="fas fa-circle"></i>
                                </div>
                                <span>${msg.get("net.deleteLb")}</span>
                            </div>
                            <div class="progress-step" id="restoreStep3">
                                <div class="progress-step-icon">
                                    <i class="fas fa-circle"></i>
                                </div>
                                <span>${msg.get("net.deleteNetGateway")}</span>
                            </div>
                            <div class="progress-step" id="restoreStep4">
                                <div class="progress-step-icon">
                                    <i class="fas fa-circle"></i>
                                </div>
                                <span>${msg.get("net.restoreRoute")}</span>
                            </div>
                            <div class="progress-step" id="restoreStep5">
                                <div class="progress-step-icon">
                                    <i class="fas fa-circle"></i>
                                </div>
                                <span>${msg.get("common.finish")}</span>
                            </div>
                        </div>
                    </div>

                    <div id="restoreNetworkInitial">
                        <div class="status-message warning">
                            <i class="fas fa-exclamation-triangle"></i>
                            <div>
                                <strong>${msg.get("net.toast4")}</strong>
                                <p>${msg.get("net.toast5")}</p>
                            </div>
                        </div>
                        <p>${msg.get("net.toast6")}：</p>
                        <ul style="margin: 10px 0; padding-left: 20px; font-size: 12px;">
                            <li>${msg.get("net.toast7")}</li>
                            <li>${msg.get("net.toast8")}</li>
                            <li>${msg.get("net.toast9")}</li>
                        </ul>
                    </div>

                    <div id="restoreNetworkResult" style="display: none;">
                        <div id="restoreResultMessage"></div>
                        <div id="restoreResultDetails"></div>
                    </div>
                </div>
                <div class="modal-footer">
                    <button class="btn btn-warning" onclick="startRestoreNetwork()" id="confirmRestoreBtn">
                        <i class="fas fa-undo"></i> ${msg.get("common.confirm")}
                    </button>
                    <button class="btn btn-secondary" onclick="closeRestoreNetworkModal()" id="cancelRestoreBtn">
                        <i class="fas fa-times"></i> ${msg.get("common.cancel")}
                    </button>
                </div>
            </div>
        </div>

        <!-- 快速操作 -->
        <div class="action-section">
            <h3 class="section-title">
                <i class="fas fa-tools"></i>
                ${msg.get("net.quickAction")}
            </h3>
            <div class="action-buttons">
                <button class="btn btn-success" onclick="showCreateVnicModal()">
                    <i class="fas fa-plus"></i> ${msg.get("net.createVnic")}
                </button>
                <#--<button class="btn btn-warning" onclick="showCreateIpv6Modal()">
                    <i class="fas fa-globe"></i> 添加IPv6
                </button>
                <button class="btn btn-danger" onclick="showDeleteAllSecondaryModal()">
                    <i class="fas fa-trash-alt"></i> 删除所有辅助VNIC
                </button>-->
            </div>
        </div>

        <!-- 主VNIC信息 -->
        <div id="primaryVnicSection" class="vnic-section" style="display: none;">
            <div class="vnic-section-header">
                <h3 class="section-title">
                    <i class="fas fa-star"></i>
                    ${msg.get("net.homeVnic")}
                </h3>
                <span class="btn btn-sm btn-primary">${msg.get("net.homeNetInterface")}</span>
            </div>
            <div id="primaryVnicContent" class="vnic-grid">

            </div>
        </div>

        <!-- 辅助VNIC列表 -->
        <div class="vnic-section">
            <div class="vnic-section-header">
                <h3 class="section-title">
                    <i class="fas fa-network-wired"></i>
                    ${msg.get(("net.otherVnic"))}
                </h3>
                <span class="btn btn-sm btn-info"><span id="secondaryVnicCountDisplay">0</span> ${msg.get("net.otherInterfaces")}</span>
            </div>

            <div id="secondaryVnicContent" class="vnic-grid">
                <!-- 辅助VNIC内容将在这里动态生成 -->
            </div>

            <div id="emptySecondaryState" class="empty-state" style="display: none;">
                <i class="fas fa-network-wired"></i>
                <div class="empty-state-title">${msg.get("net.noOtherVnic")}</div>
                <div class="empty-state-text">${msg.get("net.createOtherVnicSummary")}</div>
            </div>
        </div>
    </div><!-- /.page-card -->
    </main>
</div>


<!-- 创建VNIC模态框 -->
<div id="createVnicModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("net.createVnic")}</h3>
        </div>
        <div class="modal-body">
            <form id="createVnicForm">
                <div class="form-group">
                    <label class="form-label">${msg.get("net.subnetId")}</label>
                    <input type="text" id="subnetId" class="form-control"
                           value="${primaryVnic.subnetId!''}" placeholder="${msg.get("net.subnetId")}">
                    <div class="form-text">${msg.get("net.sameSubnetId")}</div>
                </div>
                <div class="form-group">
                    <label class="form-label">${msg.get("net.vncs")}</label>
                    <input type="number" id="vnicCount" class="form-control"
                           value="1" min="1" max="31" placeholder="请输入要创建的VNIC数量">
                    <div class="form-text">${msg.get("net.vnicLimit")}</div>
                </div>
                <div class="form-group">
                    <label class="form-label">${msg.get("net.vnicIpv6s")}</label>
                    <input type="number" id="ipv6CountPerVnic" class="form-control"
                           value="0" min="0" max="32" placeholder="${msg.get("net.vnicIpv6Count")}">
                    <div class="form-text">${msg.get("net.vnicIpv6CountSummary")}</div>
                </div>
            </form>

            <div id="createVnicMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="createVnicText"></span>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-success" onclick="confirmCreateVnic()">
                <i class="fas fa-check"></i> ${msg.get("common.confirm")}
            </button>
            <button class="btn btn-secondary" onclick="closeCreateVnicModal()">
                <i class="fas fa-times"></i> ${msg.get("common.cancel")}
            </button>
        </div>
    </div>
</div>

<div id="ipv6Modal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("net.ipv6List")} - <span id="ipv6ModalVnicName"></span></h3>
        </div>
        <div class="modal-body">
            <div id="ipv6List" class="ipv6-addresses-container">
                <!-- IPv6地址列表将在这里动态加载 -->
            </div>

            <div id="ipv6LoadingMessage" class="status-message info" style="display: none;">
                <span class="loading-spinner"></span>
                <span>${msg.get("net.loadingIpv6List")}...</span>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-success" onclick="exportIpv6Addresses()" id="exportIpv6Button">
                <i class="fas fa-download"></i> ${msg.get("net.exportIpv6")}
            </button>
            <button class="btn btn-secondary" onclick="closeIpv6Modal()">
                <i class="fas fa-times"></i> ${msg.get("common.cancel")}
            </button>
        </div>
    </div>
</div>

<div id="deleteVnicModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("net.deleteVnic")}</h3>
        </div>
        <div class="modal-body">
            <div class="status-message warning">
                <i class="fas fa-exclamation-triangle"></i>
                <div>
                    <div style="font-weight: 500;">${msg.get("net.toast4")}</div>
                    <div>${msg.get("net.deleteVnicDes")}</div>
                </div>
            </div>
            <p>${msg.get("net.deleteVnicConfirm")} "<span id="deleteVnicName"></span>" ？</p>

            <div id="deleteVnicMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="deleteVnicText"></span>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-danger" onclick="confirmDeleteVnic()">
                <i class="fas fa-trash"></i> ${msg.get("common.confirm")}
            </button>
            <button class="btn btn-secondary" onclick="closeDeleteVnicModal()">
                <i class="fas fa-times"></i> ${msg.get("common.cancel")}
            </button>
        </div>
    </div>
</div>

<!-- 创建IPv6模态框 -->
<div id="createIpv6Modal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("net.vnicAddIpv6")}</h3>
        </div>
        <div class="modal-body">
            <form id="createIpv6Form">
                <div class="form-group">
                    <label class="form-label">VNIC ID</label>
                    <input type="text" id="targetVnicId" class="form-control" readonly>
                </div>
                <div class="form-group">
                    <label class="form-label">${msg.get("net.ipv6Counts")}</label>
                    <input type="number" id="ipv6Count" class="form-control"
                           value="1" min="1" max="32" placeholder="${msg.get("net.ipv6Counts")}">
                    <div class="form-text">${msg.get("net.ipv6CountsLimit")}</div>
                </div>
            </form>

            <div id="createIpv6Message" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="createIpv6Text"></span>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-success" onclick="confirmCreateIpv6()">
                <i class="fas fa-check"></i> ${msg.get("common.confirm")}
            </button>
            <button class="btn btn-secondary" onclick="closeCreateIpv6Modal()">
                <i class="fas fa-times"></i> ${msg.get("common.cancel")}
            </button>
        </div>
    </div>
</div>

<!-- 删除所有辅助VNIC模态框 -->
<div id="deleteAllSecondaryModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("net.deleteOtherVnic")}</h3>
        </div>
        <div class="modal-body">
            <div class="status-message error">
                <i class="fas fa-exclamation-triangle"></i>
                <div>
                    <div style="font-weight: 500;">${msg.get("net.toast4")}</div>
                    <div>${msg.get("net.deleteOtherVnicDes")}</div>
                </div>
            </div>
            <p>${msg.get("net.deleteOtherVnicDes1")} <strong>${secondaryVnics?size!0}</strong> ${msg.get("net.deleteOtherVnicDes2")}？</p>

            <div id="deleteAllSecondaryMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="deleteAllSecondaryText"></span>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-danger" onclick="confirmDeleteAllSecondary()">
                <i class="fas fa-trash-alt"></i> ${msg.get("common.confirm")}
            </button>
            <button class="btn btn-secondary" onclick="closeDeleteAllSecondaryModal()">
                <i class="fas fa-times"></i> ${msg.get("common.cancel")}
            </button>
        </div>
    </div>
</div>

<!-- 切换IP模态框 -->
<div id="switchIpModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("net.changeIp")} - <span id="switchIpVnicName"></span></h3>
        </div>
        <div class="modal-body">
            <!-- CIDR输入区域 -->
            <div class="cidr-input-container">
                <label class="form-label">${msg.get("net.cidrRange")}</label>
                <div class="cidr-list" id="switchIpCidrList">
                    <div class="cidr-item">
                        <input type="text"
                               class="cidr-input"
                               placeholder="CIDR (forExample: 10.0.0.0/24)"
                               id="cidrInput1">
                    </div>
                </div>
                <button class="btn btn-primary btn-sm" onclick="addSwitchIpCidrInput()">
                    <i class="fas fa-plus"></i> ${msg.get("machine.addCidr")}
                </button>
            </div>

            <div class="form-text" style="margin-bottom: 15px; color: var(--text-secondary); font-size: 11px;">
                ${msg.get("net.cidrRangeDes")}
            </div>

            <div id="switchIpMessage" class="status-message" style="display: none;">
                <span class="loading-spinner"></span>
                <span id="switchIpText"></span>
            </div>

            <div id="switchIpDetails" style="display: none;">
                <div id="switchIpDetailsList"></div>
            </div>
        </div>
        <div class="modal-footer">
            <button class="btn btn-warning" onclick="confirmSwitchVnicIp()">
                <i class="fas fa-sync-alt"></i> ${msg.get("common.confirm")}
            </button>
            <button class="btn btn-secondary" onclick="closeSwitchIpModal()">
                <i class="fas fa-times"></i> ${msg.get("common.cancel")}
            </button>
        </div>
    </div>
</div>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script>

    window.I18N = {
        common_noData: "${msg.get('common.noData')?js_string}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        common_delete: "${msg.get('common.delete')?js_string}",
        machine_oldIp: "${msg.get('machine.oldIp')?js_string}",
        machine_newIp: "${msg.get('machine.newIp')?js_string}",
        machine_copyIp: "${msg.get('machine.copyIp')?js_string}",
        machine_changeIp: "${msg.get('machine.changeIp')?js_string}",
        net_homeVnic: "${msg.get('net.homeVnic')?js_string}",
        net_subnetId: "${msg.get('net.subnetId')?js_string}",
        net_status: "${msg.get('index.version.status')?js_string}",
        machine_ipv6: "${msg.get('machine.ipv6')?js_string}",
        net_findIpv6: "${msg.get('net.findIpv6')?js_string}",
        net_deleteVnic: "${msg.get('net.deleteVnic')?js_string}",
        delete_title: "${msg.get('mfa.confirm.delete_title')?js_string}",
        net_toast: "${msg.get('net.toast')?js_string}",
        net_toast1: "${msg.get('net.toast1')?js_string}",
        net_toast2: "${msg.get('net.toast2')?js_string}",
        net_toast3: "${msg.get('net.toast3')?js_string}",
        net_restoreLb: "${msg.get('net.restoreLb')?js_string}",
        net_toast4: "${msg.get('net.toast4')?js_string}",
        net_toast5: "${msg.get('net.toast5')?js_string}",
        net_starting: "${msg.get('net.starting')?js_string}",
        net_netError: "${msg.get('net.netError')?js_string}",
        net_vnicLimitDes: "${msg.get('net.vnicLimitDes')?js_string}",
        net_ipv6LimitDes: "${msg.get('net.ipv6LimitDes')?js_string}",
        net_creatingVnic: "${msg.get('net.creatingVnic')?js_string}",
        net_noActiveVnic: "${msg.get('net.noActiveVnic')?js_string}",
        net_plzSelectVnic: "${msg.get('net.plzSelectVnic')?js_string}",
        net_creatingIpv6: "${msg.get('net.creatingIpv6')?js_string}",
        net_noOtherVnicDel: "${msg.get('net.noOtherVnicDel')?js_string}",
        net_deletingVnics: "${msg.get('net.deletingVnics')?js_string}",
        net_homeVnic2: "${msg.get('net.homeVnic2')?js_string}",
        net_noDel: "${msg.get('net.noDel')?js_string}",
        net_toastDes: "${msg.get('net.toastDes')?js_string}",
        net_public: "${msg.get('net.public')?js_string}",
        net_addIpv6: "${msg.get('net.addIpv6')?js_string}",
        net_privateIpv: "${msg.get('net.privateIpv')?js_string}",
        net_otherInterface: "${msg.get('net.otherInterface')?js_string}",
        net_copyAddress: "${msg.get('net.copyAddress')?js_string}",
        net_deleteAddress: "${msg.get('net.deleteAddress')?js_string}",
        net_noIpv6: "${msg.get('net.noIpv6')?js_string}",
        net_noVnicIpv6: "${msg.get('net.noVnicIpv6')?js_string}",
        net_startLoadBalance: "${msg.get('net.startLoadBalance')?js_string}",
        net_confirmContinue: "${msg.get('net.confirmContinue')?js_string}",
        net_stp1: "${msg.get('net.stp1')?js_string}",
        net_stp2: "${msg.get('net.stp2')?js_string}",
        net_stp3: "${msg.get('net.stp3')?js_string}",
        net_stp4: "${msg.get('net.stp4')?js_string}",
        net_stp5: "${msg.get('net.stp5')?js_string}",
        net_stpFinish: "${msg.get('net.stpFinish')?js_string}",
        net_stpDetail: "${msg.get('net.stpDetail')?js_string}",
        net_gateway: "${msg.get('net.gateway')?js_string}",
        net_route: "${msg.get('net.route')?js_string}",
        net_lb: "${msg.get('net.lb')?js_string}",
        net_lbPublicIp: "${msg.get('net.lbPublicIp')?js_string}",
        net_lpError: "${msg.get('net.lpError')?js_string}",
        net_background: "${msg.get('net.background')?js_string}",
        net_restore1: "${msg.get('net.restore1')?js_string}",
        net_restore2: "${msg.get('net.restore2')?js_string}",
        net_restore3: "${msg.get('net.restore3')?js_string}",
        net_restore4: "${msg.get('net.restore4')?js_string}",
        net_restore5: "${msg.get('net.restore5')?js_string}",
        net_restoreError: "${msg.get('net.restoreError')?js_string}",
        machine_changeIngIp: "${msg.get('machine.changeIngIp')?js_string}"

    }
    const i18n = window.I18N;
    // 全局变量
    const instanceId = '${instanceId}';
    let selectedVnicId = '';
    let currentVnicName = '';
    let currentIpv6List = [];
    let selectedVnicIdForIpSwitch = '';
    let selectedVnicNameForIpSwitch = '';

    function handleSwitchVnicIp(vnicId, vnicName) {
        selectedVnicIdForIpSwitch = vnicId;
        selectedVnicNameForIpSwitch = vnicName;

        const modal = document.getElementById('switchIpModal');
        const vnicNameSpan = document.getElementById('switchIpVnicName');
        const messageDiv = document.getElementById('switchIpMessage');
        const detailsDiv = document.getElementById('switchIpDetails');

        // 设置VNIC名称
        vnicNameSpan.textContent = vnicName;

        // 重置CIDR输入
        const cidrList = document.getElementById('switchIpCidrList');
        cidrList.innerHTML = `
                <div class="cidr-item">
                    <input type="text"
                           class="cidr-input"
                           placeholder="CIDR (for: 10.0.0.0/24)"
                           id="cidrInput1">
                 </div>
            `;
        messageDiv.style.display = 'none';
        detailsDiv.style.display = 'none';
        modal.style.display = 'flex';
    }
    function addSwitchIpCidrInput() {
        const cidrList = document.getElementById('switchIpCidrList');
        const cidrCount = cidrList.children.length + 1;

        const newInput = document.createElement('div');
        newInput.className = 'cidr-item';
        newInput.innerHTML = `
                <input type="text"
                       class="cidr-input"
                       placeholder="CIDR (For: 10.0.0.0/24)"
                       id="cidrInput`+ cidrCount+`">
                <button class="btn btn-danger btn-icon btn-sm"
                        onclick="this.parentElement.remove()"
                        title="`+i18n.common_delete+`">
                    <i class="fas fa-trash"></i>
                </button>
            `;
        cidrList.appendChild(newInput);
    }
    function confirmSwitchVnicIp() {
        if (!selectedVnicIdForIpSwitch) {
            return;
        }
        const messageDiv = document.getElementById('switchIpMessage');
        const messageText = document.getElementById('switchIpText');
        const detailsDiv = document.getElementById('switchIpDetails');
        const cidrInputs = document.querySelectorAll('#switchIpCidrList .cidr-input');
        const cidrRanges = Array.from(cidrInputs)
            .map(input => input.value.trim())
            .filter(value => value !== '');
        messageDiv.className = 'status-message info';
        messageDiv.style.display = 'flex';
        messageText.innerHTML = '<span class="loading-spinner"></span>'+i18n.machine_changeIngIp;
        detailsDiv.style.display = 'none';
        fetch('/oci/vnic/changeSpecIp', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': getCsrfToken()
            },
            body: JSON.stringify({
                instanceId: instanceId,
                vnicId: selectedVnicIdForIpSwitch,
                cidrRanges: cidrRanges,
                preferredIp: null
            })
        })
            .then(response => response.json())
            .then(data => {
                if (data.status === 'success') {
                    messageDiv.className = 'status-message success';
                    messageText.innerHTML = '<i class="fas fa-check"></i>' + (data.message || 'IP切换成功');

                    if (data.details) {
                        detailsDiv.style.display = 'block';
                        const detailsList = document.getElementById('switchIpDetailsList');
                        detailsList.innerHTML = `
                            <div class="vnic-info-item">
                                <span class="info-label">`+i18n.machine_oldIp+`:</span>
                                <span class="info-value">`+ data.details.oldIp+`</span>
                            </div>
                            <div class="vnic-info-item">
                                <span class="info-label">`+i18n.machine_newIp+`:</span>
                                <span class="info-value">`+ data.details.newIp+`</span>
                            </div>
                        `;
                    }
                    setTimeout(() => {
                        closeSwitchIpModal();
                        loadPageData();
                    }, 3000);
                } else {
                    messageDiv.className = 'status-message error';
                    messageText.innerHTML = '<i class="fas fa-times"></i>' + (data.message || 'error');
                }
            })
            .catch(error => {
                console.error('切换IP失败:', error);
                messageDiv.className = 'status-message error';
                messageText.innerHTML = '<i class="fas fa-times"></i>'+i18n.net_netError;
            });
    }
    function closeSwitchIpModal() {
        document.getElementById('switchIpModal').style.display = 'none';
        selectedVnicIdForIpSwitch = '';
        selectedVnicNameForIpSwitch = '';
    }
    document.addEventListener('DOMContentLoaded', () => {
        initializeSidebar();
        document.querySelectorAll('.modal-overlay').forEach(modal => {
            modal.addEventListener('click', (e) => {
                if (e.target === modal) {
                    modal.style.display = 'none';
                }
            });
        });

        loadPageData();
    });
    function showCreateVnicModal() {
        const modal = document.getElementById('createVnicModal');
        const messageDiv = document.getElementById('createVnicMessage');
        document.getElementById('createVnicForm').reset();
        const subnetIdInput = document.getElementById('subnetId');
        if (window.vnicData && window.vnicData.primaryVnic && window.vnicData.primaryVnic.subnetId) {
            subnetIdInput.value = window.vnicData.primaryVnic.subnetId;
        } else {
            subnetIdInput.value = '';
        }
        document.getElementById('vnicCount').value = '1';
        document.getElementById('ipv6CountPerVnic').value = '0';
        messageDiv.style.display = 'none';
        modal.style.display = 'flex';
    }
    function closeCreateVnicModal() {
        document.getElementById('createVnicModal').style.display = 'none';
    }
    function confirmCreateVnic() {
        const subnetId = document.getElementById('subnetId').value.trim();
        const vnicCount = parseInt(document.getElementById('vnicCount').value);
        const ipv6CountPerVnic = parseInt(document.getElementById('ipv6CountPerVnic').value);
        const messageDiv = document.getElementById('createVnicMessage');
        const messageText = document.getElementById('createVnicText');
        if (!subnetId) {
            return;
        }
        if (!vnicCount || vnicCount < 1 || vnicCount > 31) {
            showMessage(messageDiv, messageText, 'error', i18n.net_vnicLimitDes);
            return;
        }
        if (ipv6CountPerVnic < 0 || ipv6CountPerVnic > 32) {
            showMessage(messageDiv, messageText, 'error', i18n.net_ipv6LimitDes);
            return;
        }
        showMessage(messageDiv, messageText, 'info', i18n.net_creatingVnic, true);
        fetch('/oci/vnic/create', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': getCsrfToken()
            },
            body: JSON.stringify({
                instanceId: instanceId,
                subnetId: subnetId,
                vnicCount: vnicCount,
                ipv6CountPerVnic: ipv6CountPerVnic
            })
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    showMessage(messageDiv, messageText, 'success', 'successful');
                    setTimeout(() => {
                        closeCreateVnicModal();
                        loadPageData();
                    }, 2000);
                } else {
                    showMessage(messageDiv, messageText, 'error', 'error');
                }
            })
            .catch(error => {
                console.error('创建VNIC失败:', error);
                showMessage(messageDiv, messageText, 'error', i18n.net_netError);
            });
    }
    function showDeleteVnicModal(vnicId, vnicName) {
        selectedVnicId = vnicId;
        const modal = document.getElementById('deleteVnicModal');
        const messageDiv = document.getElementById('deleteVnicMessage');
        document.getElementById('deleteVnicName').textContent = vnicName;
        messageDiv.style.display = 'none';
        modal.style.display = 'flex';
    }
    function closeDeleteVnicModal() {
        document.getElementById('deleteVnicModal').style.display = 'none';
        selectedVnicId = '';
    }
    function confirmDeleteVnic() {
        if (!selectedVnicId) {
            return;
        }
        const messageDiv = document.getElementById('deleteVnicMessage');
        const messageText = document.getElementById('deleteVnicText');
        showMessage(messageDiv, messageText, 'info', i18n.net_creatingVnic, true);
        fetch('/oci/vnic/delete', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': getCsrfToken()
            },
            body: JSON.stringify({
                instanceId: instanceId,
                vnicId: selectedVnicId
            })
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    showMessage(messageDiv, messageText, 'success', data.message || 'successful');
                    setTimeout(() => {
                        closeDeleteVnicModal();
                        loadPageData();
                    }, 2000);
                } else {
                    showMessage(messageDiv, messageText, 'error', data.message || 'error');
                }
            })
            .catch(error => {
                console.error('删除VNIC失败:', error);
                showMessage(messageDiv, messageText, 'error', i18n.net_netError);
            });
    }
    function showCreateIpv6ForVnicModal(vnicId) {
        selectedVnicId = vnicId;
        const modal = document.getElementById('createIpv6Modal');
        const messageDiv = document.getElementById('createIpv6Message');

        document.getElementById('targetVnicId').value = vnicId;
        document.getElementById('ipv6Count').value = '1';
        messageDiv.style.display = 'none';

        modal.style.display = 'flex';
    }
    function showCreateIpv6Modal() {
        var defaultVnicId = '';
        if (window.vnicData) {
            if (window.vnicData.secondaryVnics && window.vnicData.secondaryVnics.length > 0) {
                defaultVnicId = window.vnicData.secondaryVnics[0].vnicId;
            } else if (window.vnicData.primaryVnic && window.vnicData.primaryVnic.vnicId) {
                defaultVnicId = window.vnicData.primaryVnic.vnicId;
            }
        }

        if (defaultVnicId) {
            showCreateIpv6ForVnicModal(defaultVnicId);
        } else {
            Swal.fire({
                icon: 'warning',
                title: i18n.net_toastDes,
                text: i18n.net_noActiveVnic
            });
        }
    }
    function closeCreateIpv6Modal() {
        document.getElementById('createIpv6Modal').style.display = 'none';
        selectedVnicId = '';
    }
    function confirmCreateIpv6() {
        const vnicId = selectedVnicId || document.getElementById('targetVnicId').value;
        const ipv6Count = parseInt(document.getElementById('ipv6Count').value);
        const messageDiv = document.getElementById('createIpv6Message');
        const messageText = document.getElementById('createIpv6Text');
        if (!vnicId) {
            showMessage(messageDiv, messageText, 'error', i18n.net_plzSelectVnic);
            return;
        }
        if (!ipv6Count || ipv6Count < 1 || ipv6Count > 32) {
            showMessage(messageDiv, messageText, 'error', i18n.net_ipv6LimitDes);
            return;
        }
        showMessage(messageDiv, messageText, 'info', i18n.net_creatingIpv6, true);
        fetch('/oci/vnic/createIpv6', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': getCsrfToken()
            },
            body: JSON.stringify({
                instanceId: instanceId,
                vnicId: vnicId,
                ipv6Count: ipv6Count
            })
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    showMessage(messageDiv, messageText, 'success', data.message || 'successful');
                    setTimeout(() => {
                        closeCreateIpv6Modal();
                        loadPageData();
                    }, 2000);
                } else {
                    showMessage(messageDiv, messageText, 'error', data.message || 'error');
                }
            })
            .catch(error => {
                console.error('创建IPv6地址失败:', error);
                showMessage(messageDiv, messageText, 'error', i18n.net_netError);
            });
    }
    function showDeleteAllSecondaryModal() {
        const secondaryCount = ${secondaryVnics?size!0};
        if (secondaryCount === 0) {
            Swal.fire({
                icon: 'info',
                title: i18n.net_toastDes,
                text: i18n.net_noOtherVnicDel
            });
            return;
        }

        const modal = document.getElementById('deleteAllSecondaryModal');
        const messageDiv = document.getElementById('deleteAllSecondaryMessage');

        messageDiv.style.display = 'none';
        modal.style.display = 'flex';
    }
    function closeDeleteAllSecondaryModal() {
        document.getElementById('deleteAllSecondaryModal').style.display = 'none';
    }
    function confirmDeleteAllSecondary() {
        const messageDiv = document.getElementById('deleteAllSecondaryMessage');
        const messageText = document.getElementById('deleteAllSecondaryText');
        showMessage(messageDiv, messageText, 'info', i18n.net_deletingVnics, true);
        fetch('/oci/vnic/deleteAllSecondary', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': getCsrfToken()
            },
            body: JSON.stringify({
                instanceId: instanceId
            })
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    showMessage(messageDiv, messageText, 'success', data.message || 'successful');
                    setTimeout(() => {
                        closeDeleteAllSecondaryModal();
                        loadPageData();
                    }, 2000);
                } else {
                    showMessage(messageDiv, messageText, 'error', data.message || 'error');
                }
            })
            .catch(error => {
                console.error('删除所有辅助VNIC失败:', error);
                showMessage(messageDiv, messageText, 'error', i18n.net_netError);
            });
    }
    function refreshVnicInfo() {
        Swal.fire({
            title: 'loading',
            allowOutsideClick: false,
            didOpen: () => {
                Swal.showLoading();
            }
        });
        fetch(`/oci/vnic/refresh?instanceId=`+instanceId, {
            method: 'GET',
            headers: {
                'X-CSRF-TOKEN': getCsrfToken()
            }
        })
            .then(response => response.json())
            .then(data => {
                Swal.close();
                if (data.success) {
                    window.location.reload();
                } else {
                    Swal.fire({
                        icon: 'error',
                        title: 'error',
                        text: data.message || 'error'
                    });
                }
            })
            .catch(error => {
                Swal.close();
                console.error('刷新VNIC信息失败:', error);
                Swal.fire({
                    icon: 'error',
                    title: 'error',
                    text: i18n.net_netError
                });
            });
    }

    function copyToClipboard(text, element) {
        navigator.clipboard.writeText(text).then(() => {
            showCopySuccess(element);
            Swal.fire({
                icon: 'success',
                title: 'successful',
                text: text,
                timer: 1500,
                showConfirmButton: false,
                toast: true,
                position: 'top-end'
            });
        }).catch(() => {
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
                    text: text,
                    timer: 1500,
                    showConfirmButton: false,
                    toast: true,
                    position: 'top-end'
                });
            } catch (err) {
                Swal.fire({
                    icon: 'error',
                    title: 'error',
                    timer: 2000,
                    showConfirmButton: false,
                    toast: true,
                    position: 'top-end'
                });
            } finally {
                document.body.removeChild(textArea);
            }
        });
    }
    function showCopySuccess(element) {
        const icon = element.querySelector('i');
        const originalClass = icon.className;
        icon.className = 'fas fa-check';
        element.style.color = '#4caf50';
        setTimeout(() => {
            icon.className = originalClass;
            element.style.color = '';
        }, 800);
    }
    function showMessage(messageDiv, messageText, type, text, showSpinner = false) {
        messageDiv.className = `status-message `+type;
        messageDiv.style.display = 'flex';
        if (showSpinner) {
            messageText.innerHTML = '<span class="loading-spinner"></span>' + text;
        } else {
            messageText.textContent = text;
        }
    }
    function getCsrfToken() {
        const csrfInput = document.querySelector('input[name="_csrf"]');
        return csrfInput ? csrfInput.value : '';
    }
    function initializeSidebar() {
        const navParents = document.querySelectorAll('.nav-parent');
        navParents.forEach(parent => {
            const parentLink = parent.querySelector('.nav-link');
            parentLink.addEventListener('click', (e) => {
                e.preventDefault();
                parent.classList.toggle('expanded');
            });
        });
        const activeLink = document.querySelector('.nav-link.active');
        if (activeLink) {
            const parent = activeLink.closest('.nav-parent');
            if (parent) {
                parent.classList.add('expanded');
            }
        }
    }

    function loadPageData() {
        Swal.fire({
            title: 'loading',
            allowOutsideClick: false,
            didOpen: () => {
                Swal.showLoading();
            }
        });
        fetch(`/oci/vnic/loadData?instanceId=`+instanceId, {
            method: 'GET',
            headers: {
                'X-CSRF-TOKEN': getCsrfToken()
            }
        })
            .then(response => response.json())
            .then(data => {
                Swal.close();
                if (data.success) {
                    updatePageWithData(data.data);
                } else {
                    console.error('获取VNIC信息失败:', data.message);
                }
            })
            .catch(error => {
                Swal.close();
                console.error('加载数据失败:', error);
            });
    }

    function updatePageWithData(data) {
        const { vnicList, primaryVnic, secondaryVnics, tenantId } = data;

        if (tenantId) {
            const backButton = document.getElementById('backButton');
            backButton.href = '/oci/list?tenantId=' + tenantId;
        }
        document.getElementById('totalVnicCount').textContent = vnicList ? vnicList.length : 0;
        document.getElementById('activeVnicCount').textContent =
            vnicList ? vnicList.filter(v => v.lifecycleState === 'ATTACHED').length : 0;
        document.getElementById('secondaryVnicCount').textContent = secondaryVnics ? secondaryVnics.length : 0;
        document.getElementById('secondaryVnicCountDisplay').textContent = secondaryVnics ? secondaryVnics.length : 0;
        let totalIpv6 = 0;
        if (vnicList) {
            vnicList.forEach(function(vnic) {
                if (vnic.ipv6Addresses) {
                    totalIpv6 += vnic.ipv6Addresses.length;
                }
            });
        }
        document.getElementById('totalIpv6Count').textContent = totalIpv6;
        updatePrimaryVnicDisplay(primaryVnic);
        updateSecondaryVnicsDisplay(secondaryVnics);
        window.vnicData = data;
    }

    function updatePrimaryVnicDisplay(primaryVnic) {
        const primaryVnicSection = document.getElementById('primaryVnicSection');
        const primaryVnicContent = document.getElementById('primaryVnicContent');
        if (primaryVnic) {
            primaryVnicSection.style.display = 'block';
            const ipv6Count = primaryVnic.ipv6Addresses ? primaryVnic.ipv6Addresses.length : 0;
            primaryVnicContent.innerHTML =
                '<div class="vnic-card primary">' +
                '<div class="vnic-card-header">' +
                '<div class="vnic-icon">' +
                '<i class="fas fa-star"></i>' +
                '</div>' +
                '<div class="vnic-title">' +
                '<div class="vnic-name">' + (primaryVnic.vnicDisplayName || ''+i18n.net_homeVnic2+'') + '</div>' +
                '<div class="vnic-type">'+i18n.net_noDel+'</div>' +
                '</div>' +
                '</div>' +
                '<div class="vnic-content">' +
                '<div class="vnic-info-item">' +
                '<span class="info-label">VNIC ID:</span>' +
                '<span class="info-value">' + (primaryVnic.vnicId || '') + '</span>' +
                '</div>' +
                '<div class="vnic-info-item">' +
                '<span class="info-label">'+i18n.net_privateIpv+':</span>' +
                '<span class="info-value">' + (primaryVnic.privateIp || 'unknow') + '</span>' +
                '</div>' +
                '<div class="vnic-info-item">' +
                '<span class="info-label">'+i18n.net_public+':</span>' +
                '<div class="info-value" style="display: flex; align-items: center; gap: 8px;">' +
                '<span class="ip-text" style="flex: 1;">' + (primaryVnic.publicIp || 'unknow') + '</span>' +
                '<a href="#" class="action-link copy" onclick="copyToClipboard(\'' + (primaryVnic.publicIp || '') + '\', this)" title="'+i18n.machine_copyIp+'">' +
                '<i class="fas fa-copy"></i>' +
                '</a>' +
                '<a href="#" class="action-link switch" onclick="handleSwitchVnicIp(\'' + (primaryVnic.vnicId || '') + '\', \'' + (primaryVnic.vnicDisplayName || ''+i18n.net_homeVnic+'') + '\')" title="'+i18n.machine_changeIp+'">' +
                '<i class="fas fa-sync-alt"></i>' +
                '</a>' +
                '</div>' +
                '</div>' +
                '<div class="vnic-info-item">' +
                '<span class="info-label">'+i18n.net_subnetId+':</span>' +
                '<span class="info-value">' + (primaryVnic.subnetId || 'unKnow') + '</span>' +
                '</div>' +
                '<div class="vnic-info-item">' +
                '<span class="info-label">'+i18n.net_status+':</span>' +
                '<span class="info-value">' + (primaryVnic.lifecycleState || 'unKnow') + '</span>' +
                '</div>' +
                '<div class="vnic-info-item">' +
                '<span class="info-label">'+i18n.machine_ipv6+':</span>' +
                '<div class="info-value">' +
                '<button class="btn btn-sm btn-info" onclick="showIpv6Modal(\'' + (primaryVnic.vnicId || '') + '\', \'' + (primaryVnic.vnicDisplayName || ''+i18n.net_homeVnic+'') + '\')">' +
                '<i class="fas fa-eye"></i> '+i18n.net_findIpv6+' (<span id="primary-ipv6-count">' + ipv6Count + '</span>)' +
                '</button>' +
                '</div>' +
                '</div>' +
                '</div>' +
                '<div class="vnic-actions">' +
                '<button class="btn btn-sm btn-warning" onclick="showCreateIpv6ForVnicModal(\'' + (primaryVnic.vnicId || '') + '\')">' +
                '<i class="fas fa-plus"></i> '+i18n.net_addIpv6+'' +
                '</button>' +
                '</div>' +
                '</div>';
        } else {
            primaryVnicSection.style.display = 'none';
        }
    }

    function updateSecondaryVnicsDisplay(secondaryVnics) {
        const secondaryVnicContent = document.getElementById('secondaryVnicContent');
        const emptySecondaryState = document.getElementById('emptySecondaryState');

        if (secondaryVnics && secondaryVnics.length > 0) {
            emptySecondaryState.style.display = 'none';

            var secondaryHtmlArray = [];
            for (var i = 0; i < secondaryVnics.length; i++) {
                var vnic = secondaryVnics[i];
                var ipv6Count = vnic.ipv6Addresses ? vnic.ipv6Addresses.length : 0;

                secondaryHtmlArray.push(
                    '<div class="vnic-card secondary">' +
                    '<div class="vnic-card-header">' +
                    '<div class="vnic-icon">' +
                    '<i class="fas fa-ethernet"></i>' +
                    '</div>' +
                    '<div class="vnic-title">' +
                    '<div class="vnic-name">' + (vnic.vnicDisplayName || 'VNIC') + '</div>' +
                    '<div class="vnic-type">'+i18n.net_otherInterface+'</div>' +
                    '</div>' +
                    '</div>' +
                    '<div class="vnic-content">' +
                    '<div class="vnic-info-item">' +
                    '<span class="info-label">VNIC ID:</span>' +
                    '<span class="info-value">' + (vnic.vnicId || '') + '</span>' +
                    '</div>' +
                    '<div class="vnic-info-item">' +
                    '<span class="info-label">'+i18n.net_privateIpv+':</span>' +
                    '<span class="info-value">' + (vnic.privateIp || 'unKnow') + '</span>' +
                    '</div>' +
                    '<div class="vnic-info-item">' +
                    '<span class="info-label">'+i18n.net_public+':</span>' +
                    '<div class="info-value" style="display: flex; align-items: center; gap: 8px;">' +
                    '<span class="ip-text" style="flex: 1;">' + (vnic.publicIp || 'unKnow') + '</span>' +
                    '<a href="#" class="action-link copy" onclick="copyToClipboard(\'' + (vnic.publicIp || '') + '\', this)" title="'+i18n.machine_copyIp+'">' +
                    '<i class="fas fa-copy"></i>' +
                    '</a>' +
                    '<a href="#" class="action-link switch" onclick="handleSwitchVnicIp(\'' + vnic.vnicId + '\', \'' + (vnic.vnicDisplayName || '辅助VNIC') + '\')" title="切换IP">' +
                    '<i class="fas fa-sync-alt"></i>' +
                    '</a>' +
                    '</div>' +
                    '</div>' +
                    '<div class="vnic-info-item">' +
                    '<span class="info-label">'+i18n.net_subnetId+':</span>' +
                    '<span class="info-value">' + (vnic.subnetId || 'unKnow') + '</span>' +
                    '</div>' +
                    '<div class="vnic-info-item">' +
                    '<span class="info-label">'+i18n.net_status+':</span>' +
                    '<span class="info-value">' + (vnic.lifecycleState || 'unKnow') + '</span>' +
                    '</div>' +
                    '<div class="vnic-info-item">' +
                    '<span class="info-label">IPv6:</span>' +
                    '<div class="info-value">' +
                    '<button class="btn btn-sm btn-info" onclick="showIpv6Modal(\'' + vnic.vnicId + '\', \'' + (vnic.vnicDisplayName || 'VNIC') + '\')">' +
                    '<i class="fas fa-eye"></i> '+i18n.net_findIpv6+' (<span class="ipv6-count" data-vnic-id="' + vnic.vnicId + '">' + ipv6Count + '</span>)' +
                    '</button>' +
                    '</div>' +
                    '</div>' +
                    '</div>' +
                    '<div class="vnic-actions">' +
                    '<button class="btn btn-sm btn-warning" onclick="showCreateIpv6ForVnicModal(\'' + vnic.vnicId + '\')">' +
                    '<i class="fas fa-plus"></i> '+i18n.net_addIpv6+'' +
                    '</button>' +
                    '<button class="btn btn-sm btn-danger" onclick="showDeleteVnicModal(\'' + vnic.vnicId + '\', \'' + (vnic.vnicDisplayName || '此VNIC') + '\')">' +
                    '<i class="fas fa-trash"></i> '+i18n.net_deleteVnic+'' +
                    '</button>' +
                    '</div>' +
                    '</div>'
                );
            }
            secondaryVnicContent.innerHTML = secondaryHtmlArray.join('');
        } else {
            secondaryVnicContent.innerHTML = '';
            emptySecondaryState.style.display = 'block';
        }
    }
    function showIpv6Modal(vnicId, vnicName) {
        const modal = document.getElementById('ipv6Modal');
        const vnicNameSpan = document.getElementById('ipv6ModalVnicName');
        const ipv6List = document.getElementById('ipv6List');
        const loadingMessage = document.getElementById('ipv6LoadingMessage');
        vnicNameSpan.textContent = vnicName;
        currentVnicName = vnicName;
        loadingMessage.style.display = 'flex';
        ipv6List.innerHTML = '';
        modal.style.display = 'flex';
        let targetVnic = null;
        if (window.vnicData) {
            if (window.vnicData.primaryVnic && window.vnicData.primaryVnic.vnicId === vnicId) {
                targetVnic = window.vnicData.primaryVnic;
            } else {
                targetVnic = window.vnicData.secondaryVnics.find(vnic => vnic.vnicId === vnicId);
            }
        }
        setTimeout(() => {
            loadingMessage.style.display = 'none';
            if (targetVnic && targetVnic.ipv6Addresses && targetVnic.ipv6Addresses.length > 0) {
                currentIpv6List = targetVnic.ipv6Addresses.slice();
                const ipv6HtmlArray = [];
                for (let i = 0; i < targetVnic.ipv6Addresses.length; i++) {
                    const ipv6 = targetVnic.ipv6Addresses[i];
                    ipv6HtmlArray.push(
                        '<div class="ipv6-address-item">' +
                        '<span class="ipv6-address-text">' + ipv6 + '</span>' +
                        '<div class="ipv6-address-actions">' +
                        '<button class="btn btn-sm btn-info" onclick="copyToClipboard(\'' + ipv6 + '\', this)" title="'+i18n.net_copyAddress+'">' +
                        '<i class="fas fa-copy"></i>' +
                        '</button>' +
                        '<button class="btn btn-sm btn-danger" onclick="confirmDeleteIpv6(\'' + ipv6 + '\', \'' + vnicId + '\')" title="'+i18n.net_deleteAddress+'">' +
                        '<i class="fas fa-trash"></i>' +
                        '</button>' +
                        '</div>' +
                        '</div>'
                    );
                }
                const ipv6Html = ipv6HtmlArray.join('');
                ipv6List.innerHTML = ipv6Html;
                document.getElementById('exportIpv6Button').style.display = 'inline-flex';

            } else {
                currentIpv6List = [];
                ipv6List.innerHTML = `
                <div class="empty-ipv6-state">
                    <i class="fas fa-globe"></i>
                    <div style="font-weight: 500; margin-bottom: 8px;">`+i18n.net_noIpv6+`</div>
                    <div style="font-size: 12px;">`+i18n.net_noVnicIpv6+`</div>
                </div>
            `;
                document.getElementById('exportIpv6Button').style.display = 'none';
            }
        }, 500);
    }

    function closeIpv6Modal() {
        document.getElementById('ipv6Modal').style.display = 'none';
    }

    function confirmDeleteIpv6(ipv6Address, vnicId) {
        Swal.fire({
            title: i18n.delete_title,
            icon: 'warning',
            showCancelButton: true,
            confirmButtonColor: '#d33',
            cancelButtonColor: '#3085d6',
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel,
        }).then(function(result) {
            if (result.isConfirmed) {
                deleteIpv6Address(ipv6Address, vnicId);
            }
        });
    }

    function deleteIpv6Address(ipv6Address, vnicId) {
        Swal.fire({
            title: 'loading',
            allowOutsideClick: false,
            didOpen: function() {
                Swal.showLoading();
            }
        });

        fetch('/oci/vnic/deleteIpv6', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': getCsrfToken()
            },
            body: JSON.stringify({
                ipv6Address: ipv6Address,
                vnicId: vnicId,
                instanceId: instanceId
            })
        })
            .then(function(response) {
                return response.json();
            })
            .then(function(data) {
                Swal.close();
                if (data.success) {
                    Swal.fire({
                        icon: 'success',
                        text: data.message,
                        timer: 1500,
                        showConfirmButton: false
                    });
                    closeIpv6Modal();
                    loadPageData();
                } else {
                    Swal.fire({
                        icon: 'error',
                        title: 'error',
                        text: data.message
                    });
                }
            })
            .catch(function(error) {
                Swal.close();
                console.error('删除IPv6地址失败:', error);
            });
    }

    // 导出IPv6地址
    function exportIpv6Addresses() {
        if (!currentIpv6List || currentIpv6List.length === 0) {
            console.warn('没有数据可导出');
            return;
        }

        try {
            const content = currentIpv6List.join('\n');
            const blob = new Blob([content], { type: 'text/plain;charset=utf-8' });
            const url = window.URL.createObjectURL(blob);
            const link = document.createElement('a');
            link.href = url;
            const timestamp = new Date().toISOString().slice(0, 19).replace(/:/g, '-');
            const fileName = currentVnicName+`_IPv6地址_`+timestamp +`.txt`;
            link.download = fileName;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            window.URL.revokeObjectURL(url);
            Swal.fire({
                icon: 'success',
                title: 'success',
                text: `copied:`+fileName,
                timer: 2000,
                showConfirmButton: false,
                toast: true,
                position: 'top-end'
            });

        } catch (error) {
            console.error('导出失败:', error);
        }
    }


    function showLoadBalancerModal() {
        Swal.fire({
            title: i18n.net_startLoadBalance,
            html: `
            <div style="text-align: left; font-size: 14px;">
                <p><strong>`+i18n.net_toast+ `：</strong></p>
                <ul style="margin: 10px 0; padding-left: 20px;">
                    <li>`+i18n.net_toast1+ `</li>
                    <li>`+i18n.net_toast2+ `</li>
                    <li>`+i18n.net_toast3+ `</li>
                </ul>
                <p>`+i18n.net_confirmContinue+`</p>
            </div>
        `,
            icon: 'question',
            showCancelButton: true,
            confirmButtonColor: '#667eea',
            cancelButtonColor: '#6c757d',
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel,
            reverseButtons: true
        }).then((result) => {
            if (result.isConfirmed) {
                const modal = document.getElementById('loadBalancerModal');
                modal.style.display = 'flex';
            }
        });
    }
    function closeLoadBalancerModal() {
        document.getElementById('loadBalancerModal').style.display = 'none';
        resetLoadBalancerModal();
    }
    function resetLoadBalancerModal() {
        document.getElementById('loadBalancerInitial').style.display = 'block';
        document.getElementById('loadBalancerProgress').style.display = 'none';
        document.getElementById('loadBalancerResult').style.display = 'none';
        document.getElementById('confirmLoadBalancerBtn').style.display = 'inline-flex';
        document.getElementById('cancelLoadBalancerBtn').textContent = '取消';
        document.getElementById('progressFill').style.width = '0%';
        document.getElementById('progressText').textContent = '准备开始...';
        for (let i = 1; i <= 5; i++) {
            const step = document.getElementById('step' + i);
            step.className = 'progress-step';
            step.querySelector('i').className = 'fas fa-circle';
        }
    }
    function startLoadBalancerConfig() {
        document.getElementById('loadBalancerInitial').style.display = 'none';
        document.getElementById('loadBalancerProgress').style.display = 'block';
        document.getElementById('confirmLoadBalancerBtn').style.display = 'none';
        document.getElementById('cancelLoadBalancerBtn').textContent = '后台运行';
        simulateLoadBalancerProgress();
        fetch('/oci/vnic/network/configureLoadBalancer', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': getCsrfToken()
            },
            body: JSON.stringify({
                instanceId: instanceId
            })
        })
            .then(response => response.json())
            .then(data => {
                handleLoadBalancerResult(data);
            })
            .catch(error => {
                console.error('配置负载均衡失败:', error);
                handleLoadBalancerResult({
                    success: false,
                    message: 'error: ' + error.message
                });
            });
    }

    // 模拟负载均衡进度
    function simulateLoadBalancerProgress() {
        const steps = [
            { id: 'step1', text: i18n.net_stp1, progress: 20 },
            { id: 'step2', text: i18n.net_stp2, progress: 40 },
            { id: 'step3', text: i18n.net_stp3, progress: 60 },
            { id: 'step4', text: i18n.net_stp4, progress: 80 },
            { id: 'step5', text: i18n.net_stp5, progress: 100 }
        ];

        let currentStep = 0;
        function updateProgress() {
            if (currentStep < steps.length) {
                const step = steps[currentStep];
                document.getElementById('progressFill').style.width = step.progress + '%';
                document.getElementById('progressText').textContent = step.text;
                const stepElement = document.getElementById(step.id);
                stepElement.className = 'progress-step active';
                stepElement.querySelector('i').className = 'fas fa-spinner fa-spin';
                for (let i = 0; i < currentStep; i++) {
                    const prevStep = document.getElementById(steps[i].id);
                    prevStep.className = 'progress-step completed';
                    prevStep.querySelector('i').className = 'fas fa-check';
                }
                currentStep++;
                setTimeout(updateProgress, 12000);
            }
        }
        updateProgress();
    }
    function handleLoadBalancerResult(data) {
        document.getElementById('loadBalancerProgress').style.display = 'none';
        document.getElementById('loadBalancerResult').style.display = 'block';
        document.getElementById('cancelLoadBalancerBtn').textContent = '关闭';

        const resultMessage = document.getElementById('resultMessage');
        const resultDetails = document.getElementById('resultDetails');

        if (data.success) {
            resultMessage.innerHTML = '<div class="status-message success">' +
                '<i class="fas fa-check-circle"></i>' +
                '<div>' +
                '<strong>success！</strong>' +
                '<p>' + (data.message || i18n.net_stpFinish) + '</p>' +
                '</div>' +
                '</div>';

            if (data.details) {
                let detailsHtml = '<div style="margin-top: 15px; font-size: 12px;"><h4>'+i18n.net_stpDetail+'：</h4><ul style="margin: 8px 0; padding-left: 20px;">';

                if (data.details.natGatewayId) {
                    detailsHtml += '<li>'+i18n.net_gateway+': ' + data.details.natGatewayName + '</li>';
                }
                if (data.details.routeTableId) {
                    detailsHtml += '<li>'+i18n.net_route+': ' + data.details.routeTableName + '</li>';
                }
                if (data.details.networkLoadBalancerId) {
                    detailsHtml += '<li>'+i18n.net_lb+': ' + data.details.networkLoadBalancerName + '</li>';
                }

                if (data.details.nlpIpAddress) {
                    detailsHtml += '<li>'+i18n.net_lbPublicIp+': ' + data.details.nlpIpAddress + '</li>';
                }

                detailsHtml += '</ul></div>';
                resultDetails.innerHTML = detailsHtml;
            }
            setTimeout(() => {
                closeLoadBalancerModal();
                loadPageData();
            }, 3000);

        } else {
            resultMessage.innerHTML = '<div class="status-message error">' +
                '<i class="fas fa-times-circle"></i>' +
                '<div>' +
                '<strong>error</strong>' +
                '<p>' + (data.message || ''+i18n.net_lpError+'') + '</p>' +
                '</div>' +
                '</div>';
        }
    }
    function showRestoreNetworkModal() {
        Swal.fire({
            title: i18n.net_restoreLb,
            html: `
            <div style="text-align: left; font-size: 14px;">
                <p><strong>`+i18n.net_toast4+`</strong></p>
                <p>`+i18n.net_toast5+`</p>
            </div>
        `,
            icon: 'warning',
            showCancelButton: true,
            confirmButtonColor: '#ff9800',
            cancelButtonColor: '#6c757d',
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel,
            reverseButtons: true
        }).then((result) => {
            if (result.isConfirmed) {
                const modal = document.getElementById('restoreNetworkModal');
                modal.style.display = 'flex';
            }
        });
    }
    function closeRestoreNetworkModal() {
        document.getElementById('restoreNetworkModal').style.display = 'none';
        resetRestoreNetworkModal();
    }
    function resetRestoreNetworkModal() {
        document.getElementById('restoreNetworkInitial').style.display = 'block';
        document.getElementById('restoreNetworkProgress').style.display = 'none';
        document.getElementById('restoreNetworkResult').style.display = 'none';
        document.getElementById('confirmRestoreBtn').style.display = 'inline-flex';
        document.getElementById('cancelRestoreBtn').textContent = i18n.common_cancel;
        document.getElementById('restoreProgressFill').style.width = '0%';
        document.getElementById('restoreProgressText').textContent = i18n.net_starting;
        for (let i = 1; i <= 5; i++) {
            const step = document.getElementById('restoreStep' + i);
            step.className = 'progress-step';
            step.querySelector('i').className = 'fas fa-circle';
        }
    }
    function startRestoreNetwork() {
        document.getElementById('restoreNetworkInitial').style.display = 'none';
        document.getElementById('restoreNetworkProgress').style.display = 'block';
        document.getElementById('confirmRestoreBtn').style.display = 'none';
        document.getElementById('cancelRestoreBtn').textContent = i18n.net_background;
        simulateRestoreProgress();
        fetch('/oci/vnic/network/restoreNetwork', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': getCsrfToken()
            },
            body: JSON.stringify({
                instanceId: instanceId
            })
        })
            .then(response => response.json())
            .then(data => {
                handleRestoreResult(data);
            })
            .catch(error => {
                console.error('还原网络配置失败:', error);
                handleRestoreResult({
                    success: false,
                    message: 'error: ' + error.message
                });
            });
    }

    // 模拟还原进度
    function simulateRestoreProgress() {
        const steps = [
            { id: 'restoreStep1', text: i18n.net_restore1, progress: 20 },
            { id: 'restoreStep2', text: i18n.net_restore2, progress: 40 },
            { id: 'restoreStep3', text: i18n.net_restore3, progress: 60 },
            { id: 'restoreStep4', text: i18n.net_restore4, progress: 80 },
            { id: 'restoreStep5', text: i18n.net_restore5, progress: 100 }
        ];

        let currentStep = 0;

        function updateProgress() {
            if (currentStep < steps.length) {
                const step = steps[currentStep];
                document.getElementById('restoreProgressFill').style.width = step.progress + '%';
                document.getElementById('restoreProgressText').textContent = step.text;
                const stepElement = document.getElementById(step.id);
                stepElement.className = 'progress-step active';
                stepElement.querySelector('i').className = 'fas fa-spinner fa-spin';
                for (let i = 0; i < currentStep; i++) {
                    const prevStep = document.getElementById(steps[i].id);
                    prevStep.className = 'progress-step completed';
                    prevStep.querySelector('i').className = 'fas fa-check';
                }

                currentStep++;
                setTimeout(updateProgress, 12000);
            }
        }

        updateProgress();
    }
    function handleRestoreResult(data) {
        document.getElementById('restoreNetworkProgress').style.display = 'none';
        document.getElementById('restoreNetworkResult').style.display = 'block';
        document.getElementById('cancelRestoreBtn').textContent = '关闭';
        const resultMessage = document.getElementById('restoreResultMessage');
        const resultDetails = document.getElementById('restoreResultDetails');
        if (data.success) {
            resultMessage.innerHTML = `
            <div class="status-message success">
                <i class="fas fa-check-circle"></i>
                <div>
                    <strong>successful！</strong>
                </div>
            </div>
        `;
            setTimeout(() => {
                closeRestoreNetworkModal();
                loadPageData();
            }, 3000);

        } else {
            resultMessage.innerHTML = `
            <div class="status-message error">
                <i class="fas fa-times-circle"></i>
                <div>
                    <strong>error</strong>
                    <p>`+i18n.net_restoreError+`</p>
                </div>
            </div>
        `;
        }
    }
</script>
<div style="display: none;">
    <input type="hidden" name="${_csrf.parameterName}" value="${_csrf.token}">
</div>

</body>
</html>