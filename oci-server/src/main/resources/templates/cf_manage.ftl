<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <title>VPS管理系统 - Cloudflare DNS管理</title>
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>(function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <link rel="stylesheet" href="/css/app/cf_manage.css">
    <link rel="stylesheet" href="/css/common/custom-select.css">
    <link rel="stylesheet" href="/css/common/loading.css">
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
                <i class="fab fa-cloudflare"></i>
                <span>${msg.get("cf.config")}</span>
            </h1>
        </div>

        <div class="toolbar-section">
            <!-- 第一行：域名选择 + 操作按钮 -->
            <div class="toolbar-row">
                <div class="zone-section">
                    <label for="zoneSelect">${msg.get("cf.domain")}:</label>
                    <div class="custom-select-wrapper" id="zoneSelectWrapper">
                        <div class="select-trigger" onclick="toggleZoneDropdown()">
                            <span id="selectedZoneText">${msg.get("cf.plzSelectDomain")}</span>
                            <i class="fas fa-chevron-down"></i>
                        </div>
                        <div class="select-dropdown" id="zoneDropdown" style="display: none;">
                            <div class="dropdown-search">
                                <input type="text" id="zoneFilter" placeholder="搜索域名..." oninput="filterZones()">
                            </div>
                            <ul id="zoneList" onscroll="handleDropdownScroll(this)">
                            </ul>
                        </div>
                    </div>
                    <input type="hidden" id="zoneSelect" value="${selectedZoneId!""}">
                    <button class="btn btn-secondary btn-sm" onclick="loadZones()" title="${msg.get("cf.refreshList")}">
                        <i class="fas fa-redo"></i>
                    </button>
                </div>

                <div class="action-buttons">
                    <button class="btn btn-warning" onclick="showConfigModal()" title="${msg.get("cf.secretConfig")}">
                        <i class="fas fa-key"></i>
                        <span>${msg.get("cf.secretConfig")}</span>
                    </button>
                    <button class="btn btn-success" onclick="showAddDnsModal()" title="${msg.get("cf.addDnsRecord")}">
                        <i class="fas fa-plus"></i>
                        <span>${msg.get("cf.addDnsRecord")}</span>
                    </button>
                    <button class="btn btn-primary" onclick="syncAllRecords()" title="${msg.get("cf.syncRecord")}">
                        <i class="fas fa-sync"></i>
                        <span>${msg.get("cf.syncRecord")}</span>
                    </button>
                    <button class="btn btn-info" onclick="refreshRecords()" title="${msg.get("cf.syncList")}">
                        <i class="fas fa-redo"></i>
                        <span>${msg.get("cf.syncList")}</span>
                    </button>
                </div>
            </div>

            <div class="toolbar-row">
                <div class="search-section">
                    <div class="search-group">
                        <label for="searchName">${msg.get("cf.searchName")}:</label>
                        <input type="text" id="searchName" placeholder="${msg.get("cf.searchName")}"
                               value="${searchName!""}" onkeypress="handleSearchKeyPress(event, 'name')">
                    </div>

                    <div class="search-group">
                        <label for="searchContent">${msg.get("cf.searchValue")}:</label>
                        <input type="text" id="searchContent" placeholder="${msg.get("cf.searchValue")}"
                               value="${searchContent!""}" onkeypress="handleSearchKeyPress(event, 'content')">
                    </div>

                    <div class="search-buttons">
                        <button class="btn btn-primary btn-sm" onclick="performSearch()">
                            <i class="fas fa-search"></i>
                            ${msg.get("cf.search")}
                        </button>
                        <!-- 始终显示清除按钮，如果有搜索条件则高亮 -->
                        <button class="btn btn-secondary btn-sm" onclick="clearSearch()"
                                <#if (searchName?? && searchName != "") || (searchContent?? && searchContent != "")>
                            style="background-color: var(--accent-red); color: white;"
                            title="${msg.get("cf.clearSearch")}"
                        <#else>
                            title="${msg.get("cf.clearSearch")}"
                                </#if>>
                            <i class="fas fa-times"></i>
                            ${msg.get("cf.clearSearch")}
                        </button>
                    </div>
                </div>
            </div>
        </div>

        <!-- 加载指示器 -->
        <#--<div id="loadingContainer" class="loading-container">
            <span class="loading-spinner"></span>
            <span>正在加载DNS记录...</span>
        </div>-->

        <!-- DNS记录表格 -->
        <div class="table-view">
            <table class="table">
                <thead>
                <tr>
                    <th>${msg.get("cf.type")}</th>
                    <th>${msg.get("cf.searchName")}</th>
                    <th>${msg.get("cf.searchValue")}</th>
                    <th>TTL</th>
                    <th>${msg.get("cf.proxyStatus")}</th>
                    <th>${msg.get("vpn.action")}</th>
                </tr>
                </thead>
                <tbody id="dnsRecordsTable">
                <#if dnsRecords?? && (dnsRecords?size > 0)>
                    <#list dnsRecords as record>
                        <tr>
                            <td><span class="record-type ${record.type}">${record.type}</span></td>
                            <td><span class="truncate" title="${record.name}">${record.name}</span></td>
                            <td><span class="truncate" title="${record.content}">${record.content}</span></td>
                            <td>${record.ttl}</td>
                            <td>
                                <#if record.proxied?? && record.proxied>
                                    <span class="status-badge proxied">${msg.get("cf.alreadyProxy")}</span>
                                <#else>
                                    <span class="status-badge active">DNS</span>
                                </#if>
                            </td>
                            <td>
                                <div class="btn-group">
                                    <button class="btn btn-primary btn-icon" title="${msg.get("common.edit")}" onclick="showEditDnsModal('${record.id}')">
                                        <i class="fas fa-edit"></i>
                                    </button>
                                    <button class="btn btn-danger btn-icon" title="${msg.get("common.delete")}" onclick="deleteDnsRecord('${record.id}', '${record.name}')">
                                        <i class="fas fa-trash"></i>
                                    </button>
                                </div>
                            </td>
                        </tr>
                    </#list>
                <#else>
                    <tr>
                        <td colspan="6" style="text-align: center; padding: 40px;">
                            <i class="fas fa-info-circle" style="color: var(--text-secondary); margin-right: 8px;"></i>
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

        <!-- 添加分页组件 -->
        <#if (totalElements!0) gt 0>
        <#-- 构建基础URL，包含所有搜索参数 -->
            <#assign paginationUrl = "/dns/cloudflare?zoneId=" + (selectedZoneId!"")>
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

<!-- 隐藏的CSRF令牌输入，与其他页面保持一致 -->

<!-- 添加DNS记录模态框 -->
<div id="addDnsModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("cf.addDnsRecord")}</h3>
        </div>
        <form id="addDnsForm">
            <div class="form-group">
                <label for="recordType">${msg.get("cf.dnsType")} <span style="color: red;">*</span></label>
                <select id="recordType" class="form-control" data-custom-select data-placeholder="选择类型..." required>
                    <option value="A">A-IPv4</option>
                    <option value="AAAA">AAAA-IPv6</option>
                    <option value="CNAME">CNAME</option>
                    <option value="MX">MX</option>
                    <option value="TXT">TXT</option>
                </select>
            </div>
            <div class="form-group">
                <label for="recordName">${msg.get("cf.searchName")} <span style="color: red;">*</span></label>
                <input type="text" id="recordName" class="form-control" placeholder="@, www, mail" required>
                <small style="color: var(--text-secondary); font-size: 12px;">${msg.get("cf.rootDomain")}</small>
            </div>
            <div class="form-group">
                <label for="recordValue">${msg.get("cf.searchValue")} <span style="color: red;">*</span></label>
                <input type="text" id="recordValue" class="form-control" placeholder="${msg.get("cf.ipOrDomain")}" required>
            </div>
            <div class="form-group">
                <label for="recordTtl">TTL</label>
                <select id="recordTtl" class="form-control" data-custom-select data-placeholder="选择TTL...">
                    <option value="1">${msg.get("cf.auto")}</option>
                    <option value="300">5min</option>
                    <option value="600">10min</option>
                    <option value="1800">30min</option>
                    <option value="3600">1h</option>
                    <option value="7200">2h</option>
                    <option value="18000">5h</option>
                    <option value="43200">12h</option>
                    <option value="86400">1day</option>
                </select>
            </div>
            <div class="form-group" id="proxiedGroup">
                <label>
                    <input type="checkbox" id="recordProxied" style="width: auto; margin-right: 8px;">
                    ${msg.get("cf.availableProxy")}
                </label>
                <small style="color: var(--text-secondary); font-size: 12px; display: block; margin-top: 5px;">
                    ${msg.get("cf.protect")}
                </small>
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

<!-- 编辑DNS记录模态框 -->
<div id="editDnsModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <h3 class="modal-title">${msg.get("common.edit")}</h3>
        </div>
        <form id="editDnsForm">
            <input type="hidden" id="editRecordId">
            <div class="form-group">
                <label for="editRecordType">${msg.get("cf.type")}</label>
                <input type="text" id="editRecordType" class="form-control" readonly>
            </div>
            <div class="form-group">
                <label for="editRecordName">${msg.get("cf.searchName")}</label>
                <input type="text" id="editRecordName" class="form-control" readonly>
            </div>
            <div class="form-group">
                <label for="editRecordValue">${msg.get("cf.searchValue")} <span style="color: red;">*</span></label>
                <input type="text" id="editRecordValue" class="form-control" required>
            </div>
            <div class="form-group">
                <label for="editRecordTtl">TTL</label>
                <select id="editRecordTtl" class="form-control" data-custom-select data-placeholder="选择TTL...">
                    <option value="1">${msg.get("cf.auto")}</option>
                    <option value="300">5min</option>
                    <option value="600">10min</option>
                    <option value="1800">30min</option>
                    <option value="3600">1h</option>
                    <option value="7200">2h</option>
                    <option value="18000">5h</option>
                    <option value="43200">12h</option>
                    <option value="86400">1day</option>
                </select>
            </div>
            <div class="form-group" id="editProxiedGroup">
                <label>
                    <input type="checkbox" id="editRecordProxied" style="width: auto; margin-right: 8px;">
                    ${msg.get("cf.availableProxy")}
                </label>
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

<!-- 修改配置模态框部分，添加开关 -->
<div id="configModal" class="modal-overlay">
    <div class="modal-container">
        <div class="modal-header">
            <div style="display: flex; justify-content: space-between; align-items: center; width: 100%;">
                <h3 class="modal-title">
                    <i class="fab fa-cloudflare" style="color: #f38020;"></i>
                    ${msg.get("cf.secretConfig")}
                    <span class="status-badge status-disconnected" id="configStatus">
                        <i class="fas fa-circle"></i>
                        ${msg.get("syslog.noConn")}
                    </span>
                </h3>
                <!-- 添加开关 -->
                <label class="switch">
                    <input type="checkbox" id="configEnabled">
                    <span class="slider"></span>
                </label>
            </div>
        </div>
        <form id="configForm">
            <div class="form-group">
                <label for="configApiToken">API Key <span style="color: red;">*</span></label>
                <div class="password-input-wrapper">
                    <input type="password" id="configApiToken" class="form-control"
                           placeholder="输入Cloudflare API Key" required>
                    <div class="password-actions">
                        <button type="button" class="password-btn" onclick="togglePasswordVisibility('configApiToken')" title="${msg.get("domain.showOrHidden")}">
                            <i class="fas fa-eye" id="configApiToken-eye"></i>
                        </button>
                        <button type="button" class="password-btn" onclick="copyToClipboard('configApiToken')" title="${msg.get("domain.copy")}">
                            <i class="fas fa-copy"></i>
                        </button>
                    </div>
                </div>
                <div class="form-tip">${msg.get("cf.configPath")}</div>
            </div>
            <div class="form-group">
                <label for="configEmail">${msg.get("domain.cfEmail")} <span style="color: red;">*</span></label>
                <input type="email" id="configEmail" class="form-control"
                       placeholder="${msg.get("cf.email")}" required>
                <div class="form-tip">${msg.get("domain.cfVerify")}</div>
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
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/common/custom-select.js"></script>
<script>
    let allDnsRecords = [];
    let filteredRecords = [];
    let searchTimeout = null;
    let currentZoneId = '';
    let currentZoneName = '';
    let allZonesData = [];
    let displayedCount = 15;
    let filteredZonesData = [];

    // 页面加载完成后初始化
    document.addEventListener('DOMContentLoaded', function() {
        initializePage();
        setupEventListeners();
        //setupCustomSelect();
        initializeSearchInputs();
        const selectedZoneId = '${selectedZoneId!""}';
        if (selectedZoneId) {
            loadZones().then(() => {
                document.getElementById('zoneSelect').value = selectedZoneId;
            });
        } else {
            loadZones();
        }
    });

    function initializePage() {
        // 初始化侧边栏
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

        // 加载域名列表
        loadZones();

        // 点击模态框外部关闭
        document.querySelectorAll('.modal-overlay').forEach(modal => {
            modal.addEventListener('click', (e) => {
                if (e.target === modal) {
                    modal.style.display = 'none';
                }
            });
        });
    }

    function setupEventListeners() {
        // 添加DNS记录表单提交
        document.getElementById('addDnsForm').addEventListener('submit', function(e) {
            e.preventDefault();
            addDnsRecord();
        });

        // 编辑DNS记录表单提交
        document.getElementById('editDnsForm').addEventListener('submit', function(e) {
            e.preventDefault();
            updateDnsRecord();
        });

        // 记录类型变化时的处理
        document.getElementById('recordType').addEventListener('change', function() {
            toggleProxiedOption('recordProxied', 'proxiedGroup', this.value);
        });

        // 配置表单提交
        document.getElementById('configForm').addEventListener('submit', function(e) {
            e.preventDefault();
            saveConfig();
        });

        // 开关状态改变监听器
        document.getElementById('configEnabled').addEventListener('change', function() {
            toggleFormFields(this.checked);

            // 根据开关状态更新状态显示
            if (this.checked) {
                const apiToken = document.getElementById('configApiToken').value.trim();
                const email = document.getElementById('configEmail').value.trim();
                if (apiToken && email) {
                    updateConfigStatus('connected');
                } else {
                    updateConfigStatus('disconnected');
                }
            } else {
                updateConfigStatus('disconnected');
            }
        });
    }

    // 加载域名列表
    function loadZones() {
        return fetch('/dns/cloudflare/api/zones', {
            method: 'GET',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': getCSRFToken() }
        })
            .then(response => response.json())
            .then(apiResponse => {
                if (apiResponse.success) {
                    allZonesData = apiResponse.data;
                    filteredZonesData = [...allZonesData];
                    const selectedZoneId = '${selectedZoneId!""}';
                    if (selectedZoneId) {
                        const currentZone = allZonesData.find(z => z.id === selectedZoneId);
                        if (currentZone) {
                            document.getElementById('zoneSelect').value = currentZone.id;
                            document.getElementById('selectedZoneText').textContent =
                                currentZone.name + ' (' + currentZone.status + ')';
                        }
                    }
                    renderZoneItems(true);
                }
            });
    }

    function renderZoneItems(reset = false) {
        if (reset) {
            displayedCount = 15;
            document.getElementById('zoneList').scrollTop = 0;
        }

        const zoneListUl = document.getElementById('zoneList');
        const fragment = document.createDocumentFragment();
        const itemsToShow = filteredZonesData.slice(reset ? 0 : zoneListUl.children.length, displayedCount);

        if (reset) zoneListUl.innerHTML = '';

        itemsToShow.forEach(zone => {
            const li = document.createElement('li');
            li.textContent = zone.name + ' (' + zone.status + ')';
            li.onclick = () => selectZone(zone.id, zone.name);
            fragment.appendChild(li);
        });

        zoneListUl.appendChild(fragment);
    }

    function handleDropdownScroll(target) {
        if (target.scrollTop + target.clientHeight >= target.scrollHeight - 20) {
            if (displayedCount < filteredZonesData.length) {
                displayedCount += 15;
                renderZoneItems(false);
            }
        }
    }

    function selectZone(id, name) {
        document.getElementById('zoneSelect').value = id;
        document.getElementById('selectedZoneText').textContent = name;
        document.getElementById('zoneDropdown').style.display = 'none';
        onZoneSelectChange();
    }

    function filterZones() {
        const keyword = document.getElementById('zoneFilter').value.toLowerCase();
        filteredZonesData = allZonesData.filter(z => z.name.toLowerCase().includes(keyword));
        renderZoneItems(true);
    }

    function toggleZoneDropdown() {
        const dp = document.getElementById('zoneDropdown');
        dp.style.display = dp.style.display === 'none' ? 'block' : 'none';
    }

    document.addEventListener('click', function(e) {
        if (!document.getElementById('zoneSelectWrapper').contains(e.target)) {
            document.getElementById('zoneDropdown').style.display = 'none';
        }
    });



    // 加载DNS记录
    function loadDnsRecords() {
        const currentPage = ${currentPage!0};
        const currentSize = ${size!20};
        const currentZoneId = '${selectedZoneId!""}';
        window.location.href = `/dns/cloudflare?zoneId=`+ currentZoneId+`&page=`+ currentPage+`&size=`+ currentSize+``;
    }

    // 更新DNS记录表格
    function updateDnsRecordsTable(records, isSearchResult = false) {
        const tbody = document.getElementById('dnsRecordsTable');

        // 如果不是搜索结果，更新allDnsRecords
        if (!isSearchResult) {
            allDnsRecords = records;
        }

        if (records.length === 0) {
            return;
        }

        tbody.innerHTML = '';

        records.forEach(record => {
            const row = document.createElement('tr');

            // 记录类型
            const typeCell = document.createElement('td');
            typeCell.innerHTML = `<span class="record-type `+ record.type+`">`+ record.type+`</span>`;

            // 记录名称
            const nameCell = document.createElement('td');
            nameCell.innerHTML = `<span class="truncate" title="`+ record.name+`">`+ record.name+`</span>`;

            // 记录值
            const valueCell = document.createElement('td');
            valueCell.innerHTML = `<span class="truncate" title="`+ record.content+`">`+ record.content+`</span>`;

            // TTL
            const ttlCell = document.createElement('td');
            ttlCell.textContent = formatTTL(record.ttl);

            // 代理状态
            const proxiedCell = document.createElement('td');
            if (record.proxied !== undefined) {
                proxiedCell.innerHTML = record.proxied
                    ? '<span class="status-badge proxied">'+${msg.get("cf.alreadyProxy")}+'</span>'
                    : '<span class="status-badge active">DNS</span>';
            } else {
                proxiedCell.textContent = '-';
            }

            // 操作
            const actionsCell = document.createElement('td');

            actionsCell.innerHTML = `
            <div class="btn-group">
                <button class="btn btn-primary btn-icon" title="${msg.get("common.edit")}" onclick="showEditDnsModal('`+ record.id+`')">
                    <i class="fas fa-edit"></i>
                </button>
                <button class="btn btn-danger btn-icon" title="${msg.get("common.delete")}" onclick="deleteDnsRecord('`+ record.id+`', '`+ record.name+`')">
                    <i class="fas fa-trash"></i>
                </button>
            </div>
        `;

            row.appendChild(typeCell);
            row.appendChild(nameCell);
            row.appendChild(valueCell);
            row.appendChild(ttlCell);
            row.appendChild(proxiedCell);
            row.appendChild(actionsCell);

            tbody.appendChild(row);
        });
    }
    // 显示添加DNS记录模态框
    function showAddDnsModal() {
        currentZoneId = '${selectedZoneId!""}';
        if (!currentZoneId) {
            Swal.fire({
                title: '${msg.get("cf.selectDomainDns")}',
                icon: 'warning',
                confirmButtonColor: 'var(--accent-blue)'
            });
            return;
        }

        // 重置表单
        document.getElementById('addDnsForm').reset();
        document.getElementById('recordType').value = 'A';
        toggleProxiedOption('recordProxied', 'proxiedGroup', 'A');

        document.getElementById('addDnsModal').style.display = 'flex';
    }

    // 关闭添加DNS记录模态框
    function closeAddDnsModal() {
        document.getElementById('addDnsModal').style.display = 'none';
    }

    // 添加DNS记录
    function addDnsRecord() {
        const formData = {
            zoneId: currentZoneId,
            type: document.getElementById('recordType').value,
            name: document.getElementById('recordName').value.trim(),
            content: document.getElementById('recordValue').value.trim(),
            ttl: parseInt(document.getElementById('recordTtl').value),
            proxied: document.getElementById('recordProxied').checked
        };

        // 验证表单
        if (!formData.name || !formData.content) {
            Swal.fire({
                title: '${msg.get("common.error")?js_string}',
                text: '${msg.get("common.plzInputGlobalRequired")}',
                icon: 'error',
                confirmButtonColor: 'var(--accent-red)'
            });
            return;
        }

        // 显示加载状态
        Swal.fire({
            title: '${msg.get("common.loading")?js_string}',
            text: '${msg.get("common.loading")}',
            allowOutsideClick: false,
            didOpen: () => {
                Swal.showLoading();
            }
        });

        fetch('/dns/cloudflare/api/records', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': getCSRFToken()
            },
            body: JSON.stringify(formData)
        })
            .then(response => response.json())
            .then(apiResponse => {
                if (apiResponse.success) {
                    Swal.fire({
                        title: '${msg.get("common.success")?js_string}',
                        text: apiResponse.message || '${msg.get("cf.addDnsSuccess")?js_string}',
                        icon: 'success',
                        confirmButtonColor: 'var(--accent-green)'
                    });
                    closeAddDnsModal();
                    const currentPage = ${currentPage!0};
                    const currentSize = ${size!20};
                    const currentZoneId = '${selectedZoneId!""}';
                    window.location.href = `/dns/cloudflare?zoneId=`+ currentZoneId+`&page=`+ currentPage+`&size=`+ currentSize+``;
                } else {
                    Swal.fire({
                        title: '${msg.get("cf.addDnsFail")?js_string}',
                        text: apiResponse.message || '${msg.get("common.network.error")}',
                        icon: 'error',
                        confirmButtonColor: 'var(--accent-red)'
                    });
                }
            })
            .catch(error => {
                console.error('添加DNS记录失败:', error);
                Swal.fire({
                    title: '${msg.get("common.error")?js_string}',
                    text: '${msg.get("common.network.error")}',
                    icon: 'error',
                    confirmButtonColor: 'var(--accent-red)'
                });
            });
    }

    // 显示编辑DNS记录模态框
    function showEditDnsModal(recordId) {
        // 从当前表格中找到记录信息
        const row = document.querySelector(`button[onclick="showEditDnsModal('`+ recordId+`')"]`).closest('tr');
        const cells = row.querySelectorAll('td');

        const recordType = cells[0].querySelector('.record-type').textContent;
        const recordName = cells[1].querySelector('.truncate').getAttribute('title');
        const recordValue = cells[2].querySelector('.truncate').getAttribute('title');
        const ttlText = cells[3].textContent;
        const proxiedText = cells[4].textContent;

        // 填充编辑表单
        document.getElementById('editRecordId').value = recordId;
        document.getElementById('editRecordType').value = recordType;
        document.getElementById('editRecordName').value = recordName;
        document.getElementById('editRecordValue').value = recordValue;

        // 设置TTL
        const ttlValue = parseTTLToValue(ttlText);
        document.getElementById('editRecordTtl').value = ttlValue;

        // 设置代理状态
        const isProxied = proxiedText.includes('已代理');
        document.getElementById('editRecordProxied').checked = isProxied;

        // 根据记录类型显示/隐藏代理选项
        toggleProxiedOption('editRecordProxied', 'editProxiedGroup', recordType);

        document.getElementById('editDnsModal').style.display = 'flex';
    }

    // 关闭编辑DNS记录模态框
    function closeEditDnsModal() {
        document.getElementById('editDnsModal').style.display = 'none';
    }

    // 更新DNS记录
    function updateDnsRecord() {
        const recordId = document.getElementById('editRecordId').value;
        const formData = {
            content: document.getElementById('editRecordValue').value.trim(),
            recordType: document.getElementById('editRecordType').value,
            recordName: document.getElementById('editRecordName').value,
            ttl: parseInt(document.getElementById('editRecordTtl').value),
            zoneId: '${selectedZoneId!""}',
            proxied: document.getElementById('editRecordProxied').checked
        };

        // 验证表单
        if (!formData.content) {
            Swal.fire({
                title: '${msg.get("common.error")?js_string}',
                text: '${msg.get("common.plzInputGlobalRequired")}',
                icon: 'error',
                confirmButtonColor: 'var(--accent-red)'
            });
            return;
        }

        // 显示加载状态
        Swal.fire({
            title: '${msg.get("common.loading")?js_string}',
            allowOutsideClick: false,
            didOpen: () => {
                Swal.showLoading();
            }
        });

        fetch(`/dns/cloudflare/api/records/`+recordId, {
            method: 'PUT',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': getCSRFToken()
            },
            body: JSON.stringify(formData)
        })
            .then(response => response.json())
            .then(apiResponse => {
                if (apiResponse.success) {
                    closeEditDnsModal();
                    const currentPage = ${currentPage!0};
                    const currentSize = ${size!20};
                    const currentZoneId = '${selectedZoneId!""}';
                    window.location.href = `/dns/cloudflare?zoneId=`+ currentZoneId+`&page=`+ currentPage+`&size=`+ currentSize+``;+``;
                } else {
                    Swal.fire({
                        title: '${msg.get("cf.updateDnsFail")?js_string}',
                        text: apiResponse.message || '${msg.get("common.network.error")}',
                        icon: 'error',
                        confirmButtonColor: 'var(--accent-red)'
                    });
                }
            })
            .catch(error => {
                console.error('更新DNS记录失败:', error);
                Swal.fire({
                    title: '${msg.get("common.error")?js_string}',
                    text: '${msg.get("common.network.error")}',
                    icon: 'error',
                    confirmButtonColor: 'var(--accent-red)'
                });
            });
    }

    // 删除DNS记录
    function deleteDnsRecord(recordId, recordName) {
        Swal.fire({
            title: '${msg.get("mfa.confirm.delete_title")}',
            html: '${msg.get("cf.deleteDnsConfirmPrefix")?js_string} <strong style="color:var(--text);word-break:break-all;">' + recordName + '</strong> ${msg.get("cf.deleteDnsConfirmSuffix")?js_string}<br><span style="color:var(--muted);">${msg.get("cf.deleteDnsConfirmWarning")?js_string}</span>',
            icon: 'warning',
            showCancelButton: true,
            customClass: {
                popup: 'compact-confirm'
            },
            confirmButtonColor: 'var(--accent-r)',
            cancelButtonColor: 'var(--surface-2)',
            confirmButtonText: '${msg.get("common.confirm")}',
            cancelButtonText: '${msg.get("common.cancel")}'
        }).then((result) => {
            if (result.isConfirmed) {
                // 显示加载状态
                Swal.fire({
                    title: '${msg.get("common.loading")?js_string}',
                    allowOutsideClick: false,
                    didOpen: () => {
                        Swal.showLoading();
                    }
                });

                const currentZoneId = '${selectedZoneId!""}';
                const deleteUrl = `/dns/cloudflare/api/records/` + recordId
                    + (currentZoneId ? `?zoneId=` + encodeURIComponent(currentZoneId) : '');
                fetch(deleteUrl, {
                    method: 'DELETE',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-TOKEN': getCSRFToken()
                    }
                })
                    .then(response => response.json())
                    .then(apiResponse => {
                        if (apiResponse.success) {
                            const currentPage = ${currentPage!0};
                            const currentSize = ${size!20};
                            window.location.href = `/dns/cloudflare?zoneId=`+ currentZoneId+`&page=`+ currentPage+`&size=`+ currentSize+``;+``;
                        } else {
                            Swal.fire({
                                title: '${msg.get("cf.deleteDnsFail")?js_string}',
                                text: apiResponse.message || '${msg.get("common.network.error")}',
                                icon: 'error',
                                confirmButtonColor: 'var(--accent-red)'
                            });
                        }
                    })
                    .catch(error => {
                        console.error('删除DNS记录失败:', error);
                        Swal.fire({
                            title: '${msg.get("common.error")?js_string}',
                            text: '${msg.get("common.network.error")}',
                            icon: 'error',
                            confirmButtonColor: 'var(--accent-red)'
                        });
                    });
            }
        });
    }

    // 同步所有记录
    function syncAllRecords() {
        const currentZoneId = '${selectedZoneId!""}';
        if (!currentZoneId) {
            Swal.fire({
                title: '${msg.get("cf.selectDomainDns")}',
                text: '${msg.get("cf.selectSyncDomain")}',
                icon: 'warning',
                confirmButtonColor: 'var(--accent-blue)'
            });
            return;
        }

        // 从当前选择的下拉框获取域名名称
        const currentZone = allZonesData.find(zone => zone.id === currentZoneId);
        const currentZoneName = currentZone ? currentZone.name : getSelectedZoneNameFromText();

        Swal.fire({
            title: '${msg.get("cf.confirmSync")}',
            icon: 'question',
            showCancelButton: true,
            confirmButtonColor: 'var(--accent-green)',
            cancelButtonColor: 'var(--accent-blue)',
            confirmButtonText: '${msg.get("common.confirm")}',
            cancelButtonText: '${msg.get("common.cancel")}'
        }).then((result) => {
            if (result.isConfirmed) {
                // 显示加载状态
                Swal.fire({
                    title: '${msg.get("common.loading")?js_string}',
                    allowOutsideClick: false,
                    didOpen: () => {
                        Swal.showLoading();
                    }
                });

                fetch(`/dns/cloudflare/api/zones/`+ currentZoneId+`/sync`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-TOKEN': getCSRFToken()
                    },
                    body: JSON.stringify({
                        zoneId: currentZoneId,
                        domainName: currentZoneName
                    })
                })
                    .then(response => response.json())
                    .then(apiResponse => {
                        if (apiResponse.success) {
                            const syncCount = apiResponse.data ? apiResponse.data.syncCount : 0;
                            Swal.fire({
                                title: '${msg.get("common.success")?js_string}',
                                text: apiResponse.message || '${msg.get("cf.syncSuccess")?js_string}',
                                icon: 'success',
                                confirmButtonColor: 'var(--accent-green)'
                            });
                            loadDnsRecords();
                        } else {
                            Swal.fire({
                                title: '${msg.get("cf.syncFail")?js_string}',
                                text: apiResponse.message || '${msg.get("common.network.error")}',
                                icon: 'error',
                                confirmButtonColor: 'var(--accent-red)'
                            });
                        }
                    })
                    .catch(error => {
                        console.error('同步DNS记录失败:', error);
                        Swal.fire({
                            title: '${msg.get("common.error")?js_string}',
                            text: '${msg.get("common.network.error")}',
                            icon: 'error',
                            confirmButtonColor: 'var(--accent-red)'
                        });
                    });
            }
        });
    }

    // 刷新记录
    function refreshRecords() {
        currentZoneId = '${selectedZoneId!""}';
        if (!currentZoneId) {
            Swal.fire({
                title: '${msg.get("cf.selectDomainDns")}',
                icon: 'warning',
                confirmButtonColor: 'var(--accent-blue)'
            });
            return;
        }

        loadDnsRecords();
    }

    function getSelectedZoneNameFromText() {
        const text = document.getElementById('selectedZoneText').textContent || '';
        return text.replace(/\s*\([^)]*\)\s*$/, '').trim();
    }

    // 获取CSRF令牌
    function getCSRFToken() {
        const token = document.querySelector('input[name="_csrf"]');
        return token ? token.value : '';
    }

    // 显示/隐藏加载指示器
    function showLoading(show) {
        const loadingContainer = document.getElementById('loadingContainer');
        loadingContainer.style.display = show ? 'block' : 'none';
    }

    // 格式化TTL显示
    function formatTTL(ttl) {
        if (ttl === 1) return '${msg.get("cf.auto")}';
        if (ttl < 60) return ttl + 's';
        if (ttl < 3600) return Math.floor(ttl / 60) + 'min';
        if (ttl < 86400) return Math.floor(ttl / 3600) + 'hour';
        return Math.floor(ttl / 86400) + 'day';
    }

    // 将TTL文本转换为数值
    function parseTTLToValue(ttlText) {
        if (ttlText === '${msg.get("cf.auto")}') return 1;
        if (ttlText.includes('min')) {
            const minutes = parseInt(ttlText);
            return minutes * 60;
        }
        if (ttlText.includes('hour')) {
            const hours = parseInt(ttlText);
            return hours * 3600;
        }
        if (ttlText.includes('day')) {
            const days = parseInt(ttlText);
            return days * 86400;
        }
        return 300; // 默认5分钟
    }

    // 根据记录类型显示/隐藏代理选项
    function toggleProxiedOption(checkboxId, groupId, recordType) {
        const checkbox = document.getElementById(checkboxId);
        const group = document.getElementById(groupId);

        // 只有A和AAAA记录支持代理
        if (recordType === 'A' || recordType === 'AAAA') {
            group.style.display = 'block';
        } else {
            group.style.display = 'none';
            checkbox.checked = false;
        }
    }

    function updatePagination(totalPages, totalElements, currentPage, size) {
        const paginationContainer = document.getElementById('paginationContainer');
        if (totalElements > 0) {
            paginationContainer.style.display = 'block';
            // 这里分页宏会自动处理显示，你只需要确保数据正确传递给后端
        } else {
            paginationContainer.style.display = 'none';
        }
    }

    function onZoneSelectChange() {
        const zoneSelect = document.getElementById('zoneSelect');
        const selectedZoneId = zoneSelect.value;

        if (selectedZoneId) {
            // 跳转到选择域名的第一页
            window.location.href = `/dns/cloudflare?zoneId=`+ selectedZoneId+`&page=0&size=20`;
        } else {
            // 清空选择，回到初始状态
            window.location.href = '/dns/cloudflare';
        }
    }

    // 显示配置模态框
    function showConfigModal() {
        // 加载当前配置
        loadCurrentConfig();
        document.getElementById('configModal').style.display = 'flex';
    }

    // 关闭配置模态框
    function closeConfigModal() {
        document.getElementById('configModal').style.display = 'none';
    }

    function loadCurrentConfig() {
        // 直接从页面模板获取配置数据，不需要发送AJAX请求
        const configApiToken = '${cloudflareConfig.apiToken!""}';
        const configEmail = '${cloudflareConfig.email!""}';
        const configEnabled = ${cloudflareConfig.enabled?string('true', 'false')};

        // 填充表单
        document.getElementById('configApiToken').value = configApiToken;
        document.getElementById('configEmail').value = configEmail;
        document.getElementById('configEnabled').checked = configEnabled;

        // 更新状态
        if (configEnabled && configApiToken && configEmail) {
            updateConfigStatus('connected');
        } else {
            updateConfigStatus('disconnected');
        }

        // 根据开关状态启用/禁用表单项
        toggleFormFields(configEnabled);
    }

    // 保存配置
    function saveConfig() {
        const formData = {
            enabled: document.getElementById('configEnabled').checked,
            apiToken: document.getElementById('configApiToken').value.trim(),
            email: document.getElementById('configEmail').value.trim()
        };

        // 如果启用了Cloudflare，验证必填项
        if (formData.enabled) {
            if (!formData.apiToken) {
                Swal.fire({
                    title: '${msg.get("common.confirmFormatFail")?js_string}',
                    text: '${msg.get("common.plzInputGlobalRequired")}',
                    icon: 'warning',
                    confirmButtonColor: 'var(--accent-blue)'
                });
                return;
            }

            if (!formData.email) {
                Swal.fire({
                    title: '${msg.get("common.confirmFormatFail")?js_string}',
                    text: '${msg.get("common.plzInputGlobalRequired")}',
                    icon: 'warning',
                    confirmButtonColor: 'var(--accent-blue)'
                });
                return;
            }
        }

        // 显示加载状态
        Swal.fire({
            title: '${msg.get("common.loading")?js_string}',
            text: '${msg.get("common.saving")}',
            allowOutsideClick: false,
            didOpen: () => Swal.showLoading()
        });

        updateConfigStatus('pending');

        fetch('/api/system/updateCloudflareConfig', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': getCSRFToken()
            },
            body: JSON.stringify(formData)
        })
            .then(response => {
                if (!response.ok) {
                    // 处理错误响应
                    return response.text().then(text => {
                        let errorMessage = text;
                        try {
                            const errorData = JSON.parse(text);
                            errorMessage = errorData.message || text;
                        } catch (e) {
                            // 如果不是JSON，直接使用文本
                        }
                        throw new Error(errorMessage);
                    });
                }

                // 检查响应是否有内容
                return response.text().then(text => {
                    if (text.trim() === '') {
                        // 空响应表示成功
                        return { success: true, message: '${msg.get("common.success")?js_string}' };
                    } else {
                        try {
                            return JSON.parse(text);
                        } catch (e) {
                            // 如果不是JSON但有内容，可能是成功消息
                            return { success: true, message: text };
                        }
                    }
                });
            })
            .then(data => {
                // 保存成功后直接刷新页面
                Swal.fire({
                    title: '${msg.get("common.success")?js_string}',
                    icon: 'success',
                    confirmButtonColor: 'var(--accent-green)',
                    timer: 1500,  // 1.5秒后自动关闭
                    showConfirmButton: false
                }).then(() => {
                    // 刷新当前页面
                    window.location.reload();
                });
            })
            .catch(error => {
                console.error('保存配置失败:', error);
                updateConfigStatus('disconnected');
                Swal.fire({
                    title: '${msg.get("common.error")?js_string}',
                    text: '${msg.get("common.network.error")}',
                    icon: 'error',
                    confirmButtonColor: 'var(--accent-red)'
                });
            });
    }

    function toggleFormFields(enabled) {
        const apiTokenInput = document.getElementById('configApiToken');
        const emailInput = document.getElementById('configEmail');
        const testBtn = document.querySelector('#configModal .btn-info');

        if (enabled) {
            apiTokenInput.disabled = false;
            emailInput.disabled = false;
            testBtn.disabled = false;
            apiTokenInput.style.opacity = '1';
            emailInput.style.opacity = '1';
            testBtn.style.opacity = '1';
        } else {
            apiTokenInput.disabled = true;
            emailInput.disabled = true;
            testBtn.disabled = true;
            apiTokenInput.style.opacity = '0.5';
            emailInput.style.opacity = '0.5';
            testBtn.style.opacity = '0.5';
        }
    }

    // 测试连接
    function testConfigConnection() {
        const apiToken = document.getElementById('configApiToken').value.trim();
        const email = document.getElementById('configEmail').value.trim();

        if (!apiToken || !email) {
            Swal.fire({
                title: '${msg.get("common.confirmFormatFail")?js_string}',
                text: '${msg.get("common.plzInputGlobalRequired")}',
                icon: 'warning',
                confirmButtonColor: 'var(--accent-blue)'
            });
            return;
        }

        // 显示加载状态
        Swal.fire({
            title: '${msg.get("common.loading")?js_string}',
            allowOutsideClick: false,
            didOpen: () => Swal.showLoading()
        });

        updateConfigStatus('pending');

        fetch('/api/system/testCloudflareConnection', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-CSRF-TOKEN': getCSRFToken()
            },
            body: JSON.stringify({
                apiToken: apiToken,
                email: email
            })
        })
            .then(response => response.json())
            .then(data => {
                if (data.success) {
                    updateConfigStatus('connected');
                    Swal.fire({
                        title: '${msg.get("common.success")?js_string}',
                        text: data.message || '${msg.get("common.success")?js_string}',
                        icon: 'success',
                        confirmButtonColor: 'var(--accent-green)'
                    });
                } else {
                    throw new Error(data.message || '${msg.get("cf.connectionFail")?js_string}');
                }
            })
            .catch(error => {
                updateConfigStatus('disconnected');
                Swal.fire({
                    title: '${msg.get("common.error")?js_string}',
                    text: error.message,
                    icon: 'error',
                    confirmButtonColor: 'var(--accent-red)'
                });
            });
    }

    // 更新配置状态
    function updateConfigStatus(status) {
        const statusBadge = document.getElementById('configStatus');

        const statusTexts = {
            connected: '${msg.get("domain.conn")}',
            disconnected: '${msg.get("domain.disConn")}',
            pending: '${msg.get("domain.connecting")}'
        };

        const icons = {
            connected: 'check-circle',
            disconnected: 'circle',
            pending: 'clock'
        };

        statusBadge.className = `status-badge status-`+  status+ ``;
        statusBadge.innerHTML = `
        <i class="fas fa-`+ icons[status]+`"></i>
            `+ statusTexts[status]+`
        `;
    }

    // 密码显示/隐藏切换
    function togglePasswordVisibility(inputId) {
        const input = document.getElementById(inputId);
        const eyeIcon = document.getElementById(inputId + '-eye');

        if (input.type === 'password') {
            input.type = 'text';
            eyeIcon.className = 'fas fa-eye-slash';
        } else {
            input.type = 'password';
            eyeIcon.className = 'fas fa-eye';
        }
    }

    // 复制到剪贴板
    async function copyToClipboard(inputId) {
        const input = document.getElementById(inputId);
        const value = input.value;

        if (!value) {
            /*Swal.fire({
                title: '没有内容可复制',
                icon: 'warning',
                timer: 2000,
                showConfirmButton: false
            });*/
            return;
        }

        try {
            await navigator.clipboard.writeText(value);
            Swal.fire({
                title: '${msg.get("domain.copySuccess")?js_string}',
                icon: 'success',
                timer: 2000,
                showConfirmButton: false
            });
        } catch (err) {
            // 降级方案
            input.select();
            document.execCommand('copy');
            Swal.fire({
                title: '${msg.get("domain.copySuccess")?js_string}',
                icon: 'success',
                timer: 2000,
                showConfirmButton: false
            });
        }
    }

    // 搜索功能

    function performSearch() {
        const searchName = document.getElementById('searchName').value.trim();
        const searchContent = document.getElementById('searchContent').value.trim();
        const currentZoneId = '${selectedZoneId!""}';
        const currentSize = ${size!20};

        if (!currentZoneId) {
            Swal.fire({
                title: '${msg.get("cf.selectDomainDns")}',
                icon: 'warning',
                confirmButtonColor: 'var(--accent-blue)'
            });
            return;
        }

        // 如果两个搜索框都为空，给出提示
        if (!searchName && !searchContent) {
            Swal.fire({
                title: '${msg.get("cf.inputCondition")}',
                icon: 'info',
                confirmButtonColor: 'var(--accent-blue)'
            });
            return;
        }

        // 构建搜索URL
        let searchUrl = `/dns/cloudflare?zoneId=`+ currentZoneId+`&page=0&size=`+currentSize +``;

        if (searchName) {
            searchUrl += `&searchName=`+ encodeURIComponent(searchName)+``;
        }

        if (searchContent) {
            searchUrl += `&searchContent=`+ encodeURIComponent(searchContent)+``;
        }

        // 跳转到搜索结果页面
        window.location.href = searchUrl;
    }

    function handleSearchKeyPress(event, type) {
        if (event.key === 'Enter') {
            performSearch();
        }
    }

    // 清除搜索
    function clearSearch() {
        const currentZoneId = '${selectedZoneId!""}';
        const currentSize = ${size!20};

        // 清空搜索框
        document.getElementById('searchName').value = '';
        document.getElementById('searchContent').value = '';

        if (currentZoneId) {
            window.location.href = `/dns/cloudflare?zoneId=`+ currentZoneId+`&page=0&size=`+ currentSize+``;
        } else {
            // 如果没有选择域名，只是清空搜索框
            window.location.href = '/dns/cloudflare';
        }
    }
    /*function setupCustomSelect() {
        const customSelect = document.querySelector('.custom-select');
        const select = customSelect.querySelector('select');

        select.addEventListener('focus', () => {
            customSelect.classList.add('open');
        });

        select.addEventListener('blur', () => {
            customSelect.classList.remove('open');
        });
    }*/

    function initializeSearchInputs() {
        // 从模板变量设置搜索框值
        const searchName = '${searchName!""}';
        const searchContent = '${searchContent!""}';

        if (searchName) {
            document.getElementById('searchName').value = searchName;
        }

        if (searchContent) {
            document.getElementById('searchContent').value = searchContent;
        }

        // 或者从URL参数获取（作为备选方案）
        const urlParams = new URLSearchParams(window.location.search);
        const urlSearchName = urlParams.get('searchName');
        const urlSearchContent = urlParams.get('searchContent');

        if (urlSearchName && !searchName) {
            document.getElementById('searchName').value = urlSearchName;
        }

        if (urlSearchContent && !searchContent) {
            document.getElementById('searchContent').value = urlSearchContent;
        }
    }
</script>
</body>
</html>
