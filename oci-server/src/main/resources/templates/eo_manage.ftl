<#setting url_escaping_charset='UTF-8'>
<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 腾讯云EdgeOne DNS管理</title>
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>(function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <link rel="stylesheet" href="/css/app/eo_manage.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/common/custom-select.css">

    <#include "common/pagination.ftl" />

    <script src="/js/common/jquery.min.js"></script>
    <style>
        .layout { padding-top: 0; }
        .main-content { margin-left: 0; padding: 20px 24px; background: var(--bg); }
    </style>

</head>
<body>
<!-- 引入顶部导航栏 -->
<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- 主要内容 -->
    <main class="main-content">
        <div class="page-card">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-cloud"></i>
                <span>${msg.get("tecent.config")}</span>
            </h1>
        </div>

        <!-- 记录类型切换 -->
        <div class="record-type-toggle">
            <button class="toggle-option active" id="dnsToggle" onclick="switchRecordType('dns')">
                <i class="fas fa-server"></i>
                ${msg.get("tecent.dnsRecord")}
            </button>
            <button class="toggle-option" id="domainToggle" onclick="switchRecordType('domain')">
                <i class="fas fa-tachometer-alt"></i>
                ${msg.get("tecent.domain")}
            </button>
        </div>

        <div class="toolbar-section">
            <!-- 第一行：域名选择 + 操作按钮 -->
            <div class="toolbar-row">
                <div class="zone-section">
                    <label for="zoneSelect">${msg.get("cf.domain")}:</label>
                    <select id="zoneSelect" data-custom-select
                            data-placeholder="${msg.get("cf.plzSelectDomain")}"
                            onchange="onZoneSelectChange()">
                    </select>
                    <button class="btn btn-secondary btn-sm" onclick="refreshZones()" title="${msg.get("cf.refreshList")}">
                        <i class="fas fa-redo"></i>
                    </button>
                </div>

                <div class="action-buttons">
                    <button class="btn btn-warning" onclick="showConfigModal()" title="${msg.get("tecent.secretConfig")}">
                        <i class="fas fa-key"></i>
                        <span>${msg.get("tecent.secretConfig")}</span>
                    </button>
                    <!-- DNS记录相关按钮 -->
                    <div id="dnsActions">
                        <#--<button class="btn btn-success" onclick="showAddDnsModal()" title="添加DNS记录">
                            <i class="fas fa-plus"></i>
                            <span>添加记录</span>
                        </button>-->
                        <button class="btn btn-primary" onclick="syncAllRecords()" title="${msg.get("cf.syncRecord")}">
                            <i class="fas fa-sync"></i>
                            <span>${msg.get("cf.syncRecord")}</span>
                        </button>
                    </div>
                    <!-- 加速域名相关按钮 -->
                    <div id="domainActions" style="display: none;">
                        <#--<button class="btn btn-success" onclick="showAddDomainModal()" title="添加加速域名">
                            <i class="fas fa-plus"></i>
                            <span>添加域名</span>
                        </button>-->
                        <button class="btn btn-primary" onclick="syncAllDomains()" title="${msg.get("tecent.syncDomain")}">
                            <i class="fas fa-sync"></i>
                            <span>${msg.get("tecent.syncDomain")}</span>
                        </button>
                    </div>
                    <button class="btn btn-info" onclick="refreshRecords()" title="${msg.get("cf.refreshList")}">
                        <i class="fas fa-redo"></i>
                        <span>${msg.get("cf.refreshList")}</span>
                    </button>
                </div>
            </div>

            <!-- 第二行：搜索区域 -->
            <div class="toolbar-row">
                <!-- DNS搜索区域 - 添加正确的ID -->
                <div class="search-section" id="dnsSearchSection" style="display: flex;">
                    <div class="search-group">
                        <label for="searchName">${msg.get("cf.searchName")}:</label>
                        <input type="text" id="searchName" placeholder="${msg.get("cf.searchName")}"
                               onkeypress="handleSearchKeyPress(event, 'dns')">
                    </div>
                    <div class="search-group">
                        <label for="searchContent">${msg.get("cf.searchValue")}:</label>
                        <input type="text" id="searchName" placeholder="${msg.get("cf.searchValue")}"
                               onkeypress="handleSearchKeyPress(event, 'dns')">
                    </div>
                    <div class="search-buttons">
                        <button class="btn btn-primary btn-sm" onclick="performSearch()">
                            <i class="fas fa-search"></i>
                            ${msg.get("cf.search")}
                        </button>
                        <button class="btn btn-secondary btn-sm" onclick="clearSearch()"
                                <#if (searchName?? && searchName != "") || (searchContent?? && searchContent != "")>
                            style="background-color: #ff6b6b; color: white;"
                            title="${msg.get("cf.clearSearch")}"
                        <#else>
                            title="${msg.get("cf.clearSearch")}"
                                </#if>>
                            <i class="fas fa-times"></i>
                            ${msg.get("cf.clearSearch")}
                        </button>
                    </div>
                </div>

                <!-- 加速域名搜索区域 - 修复重复的ID -->
                <div class="search-section" id="domainSearchSection" style="display: none;">
                    <div class="search-group">
                        <label for="searchDomainName">${msg.get("cf.domain")}:</label>
                        <input type="text" id="searchDomainName" placeholder=""
                               onkeypress="handleSearchKeyPress(event, 'domain')">
                    </div>
                    <div class="search-group">
                        <label for="searchDomainStatus">${msg.get("tecent.status")}:</label>
                        <select id="searchDomainStatus" data-custom-select
                                data-placeholder="${msg.get("arm.filter.status.all")}">
                            <option value="">${msg.get("arm.filter.status.all")}</option>
                            <option value="online">${msg.get("tecent.online")}</option>
                            <option value="offline">${msg.get("tecent.offline")}</option>
                            <option value="pending">${msg.get("tecent.execting")}</option>
                        </select>
                    </div>
                    <div class="search-buttons">
                        <button class="btn btn-primary btn-sm" onclick="performDomainSearch()">
                            <i class="fas fa-search"></i>
                            ${msg.get("cf.search")}
                        </button>
                        <button class="btn btn-secondary btn-sm" onclick="clearDomainSearch()" title="清除搜索">
                            <i class="fas fa-times"></i>
                            ${msg.get("cf.clearSearch")}
                        </button>
                    </div>
                </div>
            </div>
        </div>

        <!-- 加载指示器 -->
        <div id="loadingContainer" class="loading-container">
            <span class="loading-spinner"></span>
            <span id="loadingText">${msg.get("common.loading")}</span>
        </div>

        <div class="table-view" id="dnsTableView">
            <table class="table dns-table">
                <thead>
                <tr>
                    <th>${msg.get("cf.type")}</th>
                    <th>${msg.get("cf.searchName")}</th>
                    <th>${msg.get("cf.searchValue")}</th>
                    <th>TTL</th>
                    <th>${msg.get("tecent.first")}</th>
                    <th>${msg.get("mfa.table.col_action")}</th>
                </tr>
                </thead>
                <tbody id="dnsRecordsTable">
                <#if dnsRecords?? && (dnsRecords?size > 0)>
                    <#list dnsRecords as record>
                        <tr>
                            <td><span class="record-type ${record.type}">${record.type}</span></td>
                            <td><span class="truncate" title="${record.name}">${record.name}</span></td>
                            <td><span class="truncate" title="${record.content}">${record.content}</span></td>
                            <td>${record.ttl!300}</td>
                            <td>${record.priority!"-"}</td>
                            <td>
                                <div class="btn-group">
                                    <button class="btn btn-primary btn-icon" title="编辑" onclick="showEditDnsModal('${record.id}')">
                                        <i class="fas fa-edit"></i>
                                    </button>
                                    <button class="btn btn-danger btn-icon" title="删除" onclick="deleteDnsRecord('${record.id}', '${record.name}')">
                                        <i class="fas fa-trash"></i>
                                    </button>
                                </div>
                            </td>
                        </tr>
                    </#list>
                <#else>
                    <tr>
                        <td colspan="6" style="text-align:center;padding:40px;color:var(--muted)">
                            <i class="fas fa-info-circle" style="margin-right:6px"></i>
                            <#if selectedZoneId??>
                                ${msg.get("cf.noDnsRecord")}
                            <#else>
                                ${msg.get("cf.selectDomainDns")}
                            </#if>
                        </td>
                    </tr>
                </#if>
                </tbody>
            </table>
        </div>

        <div class="table-view" id="domainTableView" style="display: none;">
            <table class="table domain-table">
                <thead>
                <tr>
                    <th>${msg.get("cf.domain")}</th>
                    <th>${msg.get("arm.table.status")}</th>
                    <th>CNAME</th>
                    <th>${msg.get("tecent.protocol")}</th>
                    <th>${msg.get("mfa.table.col_action")}</th>
                </tr>
                </thead>
                <tbody id="domainsTable">
                <!-- 当type=domain时，使用dnsRecords数据，但展示不同的字段 -->
                <#if (recordType!"dns") == "domain">
                    <#if dnsRecords?? && (dnsRecords?size > 0)>
                        <#list dnsRecords as record>
                            <tr>
                                <td><span class="truncate" title="${record.name!''}">${record.name!''}</span></td>

                                <td>
                                    <#if record.status??>
                                        <span class="status-badge ${record.status}">
                                    <#if record.status == "online">${msg.get("tecent.online")}
                                    <#elseif record.status == "offline">${msg.get("tecent.online")}
                                    <#elseif record.status == "pending">${msg.get("tecent.execting")}
                                    <#else>${record.status}
                                    </#if>
                                </span>
                                    <#else>
                                        <span class="status-badge active">${msg.get("tecent.active")}</span>
                                    </#if>
                                </td>

                                <!-- CNAME字段：如果type是CNAME，content就是CNAME值 -->
                                <td>
                                    <span class="truncate" title="${record.content!'-'}">${record.content!'-'}</span>
                                </td>

                                <!-- 协议字段 -->
                                <td>${record.protocol!'HTTP/HTTPS'}</td>

                                <!-- 操作按钮 -->
                                <td>
                                    <div class="btn-group">
                                        <button class="btn btn-primary btn-icon" title="${msg.get("common.edit")}" onclick="showEditDomainModal('${record.id}')">
                                            <i class="fas fa-edit"></i>
                                        </button>
                                        <button class="btn btn-danger btn-icon" title="${msg.get("common.delete")}" onclick="deleteAccelerationDomain('${record.id}', '${record.name!''}')">
                                            <i class="fas fa-trash"></i>
                                        </button>
                                    </div>
                                </td>
                            </tr>
                        </#list>
                    <#else>
                        <tr>
                            <td colspan="5" style="text-align:center;padding:40px;color:var(--muted)">
                                <i class="fas fa-info-circle" style="margin-right:6px"></i>
                                <#if selectedZoneId??>
                                    ${msg.get("tecent.noSpeedDomain")}
                                <#else>
                                    ${msg.get("tecent.selectSpeedDomain")}
                                </#if>
                            </td>
                        </tr>
                    </#if>
                </#if>
                </tbody>
            </table>
        </div>

        <!-- 分页组件 -->
        <#if (totalElements!0) gt 0>
            <#assign paginationUrl = "/dns/edgeone?zoneId=" + (selectedZoneId!"")>
            <#if searchName?? && searchName != "">
                <#assign paginationUrl = paginationUrl + "&searchName=" + searchName?url>
            </#if>
            <#if searchContent?? && searchContent != "">
                <#assign paginationUrl = paginationUrl + "&searchContent=" + searchContent?url>
            </#if>

            <@pagination
            url=paginationUrl
            page=currentPage!0
            size=size!20
            totalPages=totalPages!1
            totalElements=totalElements!0
            textShow=msg.get("page.show")
            textItem=msg.get("page.item")
            textPrev=msg.get("page.prev")
            textNext=msg.get("page.next")
            textJump=msg.get("page.jump")
            textPage=msg.get("page.page")
            textTotal=msg.get("page.total")
            />
        </#if>

        </div><!-- /.page-card -->
    </main>
</div>


<!-- 添加DNS记录模态框 -->
<div id="addDnsModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("tecent.addDnsRecord")}</h3>
        </div>
        <form id="addDnsForm">
            <div class="form-group">
                <label for="recordType">${msg.get("cf.dnsType")} <span style="color:var(--accent-r)">*</span></label>
                <select id="recordType" class="form-control" data-custom-select required>
                    <option value="A">A</option>
                    <option value="AAAA">AAAA</option>
                    <option value="CNAME">CNAME</option>
                    <option value="MX">MX</option>
                    <option value="TXT">TXT</option>
                </select>
            </div>
            <div class="form-group">
                <label for="recordName">${msg.get("tecent.dnsName")} <span style="color:var(--accent-r)">*</span></label>
                <input type="text" id="recordName" class="form-control" placeholder="@, www, mail" required>
                <small style="color: var(--text-secondary); font-size: 12px;">${msg.get("cf.rootDomain")}</small>
            </div>
            <div class="form-group">
                <label for="recordValue">${msg.get("cf.searchValue")} <span style="color:var(--accent-r)">*</span></label>
                <input type="text" id="recordValue" class="form-control" placeholder="${msg.get("cf.ipOrDomain")}" required>
            </div>
            <div class="form-group">
                <label for="recordTtl">TTL</label>
                <select id="recordTtl" class="form-control" data-custom-select>
                    <option value="300">5min</option>
                    <option value="600">10min</option>
                    <option value="1800">30min</option>
                    <option value="3600">1min</option>
                    <option value="7200">2min</option>
                    <option value="18000">5hour</option>
                    <option value="43200">12hour</option>
                    <option value="86400">1day</option>
                </select>
            </div>
            <div class="form-group" id="priorityGroup" style="display: none;">
                <label for="recordPriority">${msg.get("tecent.first")}</label>
                <input type="number" id="recordPriority" class="form-control" placeholder="10" min="0" max="65535">
                <small style="color: var(--text-secondary); font-size: 12px;">${msg.get("tecent.mxDesc")}</small>
            </div>
            <div class="form-actions">
                <button type="submit" class="btn btn-success">
                    <i class="fas fa-save"></i>
                    ${msg.get("cf.addDnsRecord")}
                </button>
                <button type="button" class="btn btn-secondary" onclick="closeAddDnsModal()">
                    <i class="fas fa-times"></i>
                    ${msg.get("common.cancel")}
                </button>
            </div>
        </form>
    </div>
</div>


<div id="editDnsModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("common.edit")}</h3>
        </div>
        <form id="editDnsForm">
            <input type="hidden" id="editRecordId">
            <div class="form-group">
                <label for="editRecordType">${msg.get("cf.dnsType")}</label>
                <input type="text" id="editRecordType" class="form-control" readonly>
            </div>
            <div class="form-group">
                <label for="editRecordName">${msg.get("tecent.dnsName")}</label>
                <input type="text" id="editRecordName" class="form-control" readonly>
            </div>
            <div class="form-group">
                <label for="editRecordValue">${msg.get("cf.searchValue")} <span style="color:var(--accent-r)">*</span></label>
                <input type="text" id="editRecordValue" class="form-control" required>
            </div>
            <div class="form-group">
                <label for="editRecordTtl">TTL</label>
                <select id="editRecordTtl" class="form-control" data-custom-select>
                    <option value="300">5min</option>
                    <option value="600">10min</option>
                    <option value="1800">30min</option>
                    <option value="3600">1hour</option>
                    <option value="7200">2hour</option>
                    <option value="18000">5hour</option>
                    <option value="43200">12hour</option>
                    <option value="86400">1day</option>
                </select>
            </div>
            <div class="form-group" id="editPriorityGroup" style="display: none;">
                <label for="editRecordPriority">${msg.get("tecent.first")}</label>
                <input type="number" id="editRecordPriority" class="form-control" min="0" max="65535">
            </div>
            <div class="form-actions">
                <button type="submit" class="btn btn-success">
                    <i class="fas fa-save"></i>
                    ${msg.get("common.save")}
                </button>
                <button type="button" class="btn btn-secondary" onclick="closeEditDnsModal()">
                    <i class="fas fa-times"></i>
                    ${msg.get("common.cancel")}
                </button>
            </div>
        </form>
    </div>
</div>

<div id="addDomainModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("tecent.addSpeedDomain")}</h3>
        </div>
        <form id="addDomainForm">
            <div class="form-group">
                <label for="domainName">${msg.get("cf.domain")} <span style="color:var(--accent-r)">*</span></label>
                <input type="text" id="domainName" class="form-control" placeholder="www.example.com" required>
                <small style="color: var(--text-secondary); font-size: 12px;">${msg.get("tecent.inputSpeedDomain")}</small>
            </div>
            <div class="form-group">
                <label for="originType">${msg.get("tecent.sourceType")} <span style="color:var(--accent-r)">*</span></label>
                <select id="originType" class="form-control" data-custom-select required>
                    <option value="IP">IP</option>
                    <option value="DOMAIN">${msg.get("cf.domain")}</option>
                </select>
            </div>
            <div class="form-group">
                <label for="originValue">${msg.get("tecent.sourceAddress")} <span style="color:var(--accent-r)">*</span></label>
                <input type="text" id="originValue" class="form-control" placeholder="${msg.get("tecent.sourceIpOrDomain")}" required>
            </div>
            <div class="form-group">
                <label for="protocols">${msg.get("tecent.supportProtocol")} <span style="color:var(--accent-r)">*</span></label>
                <div class="protocol-group">
                    <label>
                        <input type="checkbox" id="protocolHttp" value="http" checked>
                        HTTP
                    </label>
                    <label>
                        <input type="checkbox" id="protocolHttps" value="https" checked>
                        HTTPS
                    </label>
                </div>
            </div>
            <div class="form-actions">
                <#--<button type="submit" class="btn btn-success">
                    <i class="fas fa-save"></i>
                    添加域名
                </button>-->
                <button type="button" class="btn btn-secondary" onclick="closeAddDomainModal()">
                    <i class="fas fa-times"></i>
                    ${msg.get("common.cancel")}
                </button>
            </div>
        </form>
    </div>
</div>

<div id="configModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <div style="display: flex; justify-content: space-between; align-items: center; width: 100%;">
                <h3 class="modal-title">
                    <i class="fas fa-cloud"></i>
                    ${msg.get("tecent.secretConfig")}
                    <span class="status-badge status-disconnected" id="configStatus">
                        <i class="fas fa-circle"></i>
                        ${msg.get("domain.disConn")}
                    </span>
                </h3>
                <label class="switch">
                    <input type="checkbox" id="configEnabled">
                    <span class="slider"></span>
                </label>
            </div>
        </div>
        <form id="configForm">
            <div class="form-group">
                <label for="configSecretId">Secret ID <span style="color:var(--accent-r)">*</span></label>
                <div class="password-input-wrapper">
                    <input type="password" id="configSecretId" class="form-control"
                           placeholder="输入腾讯云Secret ID" required>
                    <div class="password-actions">
                        <button type="button" class="password-btn" onclick="togglePasswordVisibility('configSecretId')" title="${msg.get("domain.showOrHidden")}">
                            <i class="fas fa-eye" id="configSecretId-eye"></i>
                        </button>
                        <button type="button" class="password-btn" onclick="copyToClipboard('configSecretId')" title="${msg.get("domain.copy")}">
                            <i class="fas fa-copy"></i>
                        </button>
                    </div>
                </div>
                <div class="form-tip">${msg.get("tecent.configPath")}</div>
            </div>
            <div class="form-group">
                <label for="configSecretKey">Secret Key <span style="color:var(--accent-r)">*</span></label>
                <div class="password-input-wrapper">
                    <input type="password" id="configSecretKey" class="form-control"
                           placeholder="输入腾讯云Secret Key" required>
                    <div class="password-actions">
                        <button type="button" class="password-btn" onclick="togglePasswordVisibility('configSecretKey')" title="${msg.get("domain.showOrHidden")}">
                            <i class="fas fa-eye" id="configSecretKey-eye"></i>
                        </button>
                        <button type="button" class="password-btn" onclick="copyToClipboard('configSecretKey')" title="${msg.get("domain.copy")}">
                            <i class="fas fa-copy"></i>
                        </button>
                    </div>
                </div>
            </div>
            <div class="form-group">
                <label for="configRegion">${msg.get("tecent.domains")}</label>
                <select id="configRegion" class="form-control" data-custom-select>
                    <option value="ap-beijing">北京 (ap-beijing)</option>
                    <option value="ap-shanghai">上海 (ap-shanghai)</option>
                    <option value="ap-guangzhou">广州 (ap-guangzhou)</option>
                    <option value="ap-singapore">新加坡 (ap-singapore)</option>
                    <option value="na-ashburn">弗吉尼亚 (na-ashburn)</option>
                    <option value="eu-frankfurt">法兰克福 (eu-frankfurt)</option>
                </select>
                <div class="form-tip">${msg.get("tecent.selectHighSpeed")}</div>
            </div>
            <div class="form-actions">
                <button type="button" class="btn btn-info" onclick="testConfigConnection()">
                    <i class="fas fa-plug"></i>
                    ${msg.get("ip.testConn")}
                </button>
                <button type="submit" class="btn btn-success">
                    <i class="fas fa-save"></i>
                    ${msg.get("common.save")}
                </button>
                <button type="button" class="btn btn-secondary" onclick="closeConfigModal()">
                    <i class="fas fa-times"></i>
                    ${msg.get("common.cancel")}
                </button>
            </div>
        </form>
    </div>
</div>
<#--<script>
    const zoneSelect = document.getElementById('zoneSelect');
    const selectedZoneId = zoneSelect.value || '${selectedZoneId!""}';
</script>-->
<script>
    window.I18N = {
        common_noData: "${msg.get('common.noData')?js_string}",
        common_available: "${msg.get('common.available')?js_string}",
        common_noAvailable: "${msg.get('common.noAvailable')?js_string}",
        tecent_plzConfig: "${msg.get('tecent.plzConfig')?js_string}",
        tecent_goConfig: "${msg.get('tecent.goConfig')?js_string}",
        common_cancel: "${msg.get('common.cancel')?js_string}",
        common_network_error: "${msg.get('common.network.error')?js_string}",
        tecent_plzSelectDomain: "${msg.get('tecent.plzSelectDomain')?js_string}",
        common_plzInputGlobalRequired: "${msg.get('common.plzInputGlobalRequired')?js_string}",
        tecent_delete: "${msg.get('mfa.confirm.delete_title')?js_string}",
        common_confirm: "${msg.get('common.confirm')?js_string}",
        tecent_devloping: "${msg.get('tecent.devloping')?js_string}",
        domain_conn: "${msg.get('domain.conn')?js_string}",
        domain_disConn: "${msg.get('domain.disConn')?js_string}",
        domain_connecting: "${msg.get('domain.connecting')?js_string}",
        domain_noDataCopy: "${msg.get('domain.noDataCopy')?js_string}",


    }
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/common/custom-select.js"></script>
<script src="/js/system/eo_manage.js"></script>
<!-- 在body结束前引入版本信息模块 -->
<#--
<#include "common/version_info.ftl">
-->
</body>
</html>