function _getCsrfToken() {
    const input = document.querySelector('input[name="_csrf"]');
    if (input) return input.value;
    const meta = document.querySelector('meta[name="_csrf"]');
    return meta ? (meta.getAttribute('content') || '') : '';
}

let currentPage = 1;
const itemsPerPage = 5;
let allRules = [];
const i18n = window.I18N;
var _spoilersVisible = false;

function toggleAllSpoilers() {
    _spoilersVisible = !_spoilersVisible;
    // 租户名 name-spoiler（双span方式）
    document.querySelectorAll('.name-spoiler').forEach(function(el) {
        if (_spoilersVisible) {
            el.classList.remove('is-hidden');
            el.classList.add('is-visible');
        } else {
            el.classList.remove('is-visible');
            el.classList.add('is-hidden');
        }
    });
    // 其他 blur 型 spoiler（密码等）
    document.querySelectorAll('.is-hidden:not(.name-spoiler), .is-visible:not(.name-spoiler)').forEach(function(el) {
        if (_spoilersVisible) {
            el.classList.remove('is-hidden');
            el.classList.add('is-visible');
        } else {
            el.classList.remove('is-visible');
            el.classList.add('is-hidden');
        }
    });
    var icon = document.getElementById('spoilerToggleIcon');
    var btn  = document.getElementById('spoilerToggleBtn');
    if (icon) icon.className = _spoilersVisible ? 'fas fa-eye-slash' : 'fas fa-eye';
    if (btn)  btn.classList.toggle('active', _spoilersVisible);
}

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

function handleSync(tenantId) {
    const modal = document.getElementById('syncModal');
    const progressBar = document.getElementById('progressBar');
    const statusMessage = document.getElementById('statusMessage');
    const statusText = document.getElementById('statusText');

    modal.style.display = 'flex';
    progressBar.style.width = '0%';

    let progress = 0;
    const totalTime = 180; // 3分钟 = 180秒
    const updateInterval = 1000; // 每秒更新一次
    const progressIncrement = 100 / totalTime; // 每秒增加的百分比

    // 进度条更新器
    const progressUpdater = setInterval(() => {
        progress += progressIncrement;
        if (progress > 98) { // 保持在98%，留出最后2%给成功响应
            clearInterval(progressUpdater);
            handleTimeout();
        } else {
            progressBar.style.width = progress + '%';
        }
    }, updateInterval);

    // 超时处理
    const timeoutHandler = setTimeout(() => {
        clearInterval(progressUpdater);
        handleTimeout();
    }, totalTime * 1000);

    function handleTimeout() {
        statusMessage.className = 'status-message warning';
        statusText.textContent = i18n.detail_netError;

        setTimeout(() => {
            modal.style.display = 'none';
        }, 3000);
    }

    const xhr = new XMLHttpRequest();
    xhr.open('GET', '/tenants/syncOci?tenantId=' + tenantId, true);

    // 设置CSRF令牌
    const token = _getCsrfToken();
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        clearInterval(progressUpdater);
        clearTimeout(timeoutHandler);

        try {
            const data = JSON.parse(xhr.responseText);
            if (data.status === 'error') {
                statusMessage.className = 'status-message error';
                statusText.textContent = (data.message || '同步失败') + '，请重试';

                setTimeout(() => {
                    modal.style.display = 'none';
                }, 3000);
            }
            else if (data.status === 'success') {
                progressBar.style.width = '100%';
                statusMessage.className = 'status-message success';
                statusText.textContent = i18n.detail_syncSuccess;
                setTimeout(() => {
                    modal.style.display = 'none';
                    location.reload();
                }, 2000);
            }
            else {
                handleTimeout();
            }
        } catch (error) {
            handleTimeout();
        }
    };

    xhr.onerror = function() {
        clearInterval(progressUpdater);
        clearTimeout(timeoutHandler);
        handleTimeout();
    };

    xhr.send();
}


document.addEventListener('DOMContentLoaded', () => {

    const protocolSelect = document.getElementById('ruleProtocol');
    const portsInput = document.getElementById('rulePorts');
    const portsLabel = document.querySelector('label[for="rulePorts"]');
    var childRows = document.querySelectorAll('.child-row');
    childRows.forEach(function(row) {
        row.style.display = 'none';
    });
    var expandIcons = document.querySelectorAll('.expand-icon');
    expandIcons.forEach(function(icon) {
        icon.classList.remove('expanded');
    });

    if (protocolSelect) {
        protocolSelect.addEventListener('change', function() {
            if (this.value === 'icmp') {
                portsInput.placeholder = i18n.tenant_icmpNoPort;
                portsInput.disabled = true;
                portsInput.value = '';
                portsLabel.innerHTML = i18n.tenant_portRange+' <span style="color: #666;">'+i18n.detail_icmpNoNeed+'</span>';
            }else if (this.value === 'all') {
                portsInput.placeholder = i18n.detail_openAll;
                portsInput.disabled = true;
                portsInput.value = '';
                portsLabel.innerHTML = i18n.tenant_portRange+' <span style="color: #666;">'+i18n.detail_openAllInCloud+'</span>';
            } else {
                portsInput.placeholder = '80,443 Or 80-443';
                portsInput.disabled = false;
                portsLabel.innerHTML = i18n.tenant_portRange+' <span style="color: red;">*</span>';
            }
        });

        // 初始检查
        if (protocolSelect.value === 'icmp') {
            portsInput.placeholder = i18n.tenant_icmpNoPort;
            portsInput.disabled = true;
            portsInput.value = ''; // 清空端口值
            portsLabel.innerHTML = i18n.tenant_portRange+' <span style="color: #666;">'+i18n.detail_icmpNoNeed+'</span>';
        }else if (protocolSelect.value === 'all') {
            portsInput.placeholder = i18n.detail_openAll;
            portsInput.disabled = true;
            portsInput.value = '';
            portsLabel.innerHTML = i18n.tenant_portRange+' <span style="color: #666;">'+i18n.detail_openAllInCloud+'</span>';
        }
    }
    const syncForms = document.querySelectorAll('form[action="/tenants/syncOci"]');
    syncForms.forEach(form => {
        form.addEventListener('submit', (e) => {
            e.preventDefault();
            const tenantId = form.querySelector('input[name="tenantId"]').value;
            handleSync(tenantId);
        });
    });

    const modal = document.getElementById('syncModal');
    modal.addEventListener('click', (e) => {
        if (e.target === modal) {
            modal.style.display = 'none';
        }
    });

    const tabs = document.querySelectorAll('.security-rules-tab');
    tabs.forEach(tab => {
        tab.addEventListener('click', function() {
            // 防止重复点击
            if (this.classList.contains('active')) {
                return;
            }

            tabs.forEach(t => t.classList.remove('active'));
            this.classList.add('active');

            const modal = document.getElementById('securityRulesModal');
            const tenantId = modal.dataset.tenantId;
            loadSecurityRules(tenantId);
        });
    });
});

// 状态检查处理
/*function handleCheckStatus(tenantId) {
    const modal = document.getElementById('checkStatusModal');
    const statusMessage = document.getElementById('checkStatusMessage');
    const statusText = document.getElementById('checkStatusText');
    const checkDetails = document.getElementById('checkDetails');
    const checkDetailsList = document.getElementById('checkDetailsList');
    const loadingSpinner = statusMessage.querySelector('.loading-spinner');

    // 显示模态框
    modal.style.display = 'flex';
    statusMessage.className = 'status-message syncing';
    checkDetails.style.display = 'none';
    statusText.textContent = "正在检测中...";

    // 创建XHR对象
    const xhr = new XMLHttpRequest();
    xhr.open('GET', '/tenants/checkStatus?tenantId=' + tenantId, true);

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const data = JSON.parse(xhr.responseText);

                // 隐藏加载图标
                loadingSpinner.style.display = 'none';

                // 更新状态消息
                statusMessage.className = 'status-message ' + data.status;
                statusText.textContent = data.message;

                // 显示详细检查结果
                if (data.checks) {
                    checkDetailsList.innerHTML = '';  // 清空现有内容

                    for (let key in data.checks) {
                        if (data.checks.hasOwnProperty(key)) {
                            const value = data.checks[key];
                            const checkItem = document.createElement('div');
                            checkItem.className = 'tenant-info-item';
                            checkItem.innerHTML = '<span class="info-label">' + key + ':</span>' +
                                '<span class="info-value" style="color: ' + (value === '正常' ? 'var(--accent-green)' : 'var(--accent-red)') + '">' +
                                value +
                                '</span>';
                            checkDetailsList.appendChild(checkItem);
                        }
                    }

                    checkDetails.style.display = 'block';
                }

                if (data.status === 'success') {
                    setTimeout(function() {
                        modal.style.display = 'none';
                    }, 3000);
                }
            } catch (error) {
                handleError();
            }
        } else {
            handleError();
        }
    };

    xhr.onerror = handleError;

    function handleError() {
        loadingSpinner.style.display = 'none';
        statusMessage.className = 'status-message error';
        statusText.textContent = '检测失败，请重试';

        setTimeout(function() {
            modal.style.display = 'none';
            location.reload();
        }, 3000);
    }

    // 发送请求
    xhr.send();
}*/

// 删除处理
/*function handleDelete(tenantId) {
    Swal.fire({
        title: '确定要删除此API吗？',
        text: '此操作不可恢复！',
        icon: 'warning',
        showCancelButton: true,              // 显示取消按钮
        confirmButtonColor: '#d33',         // 确认按钮颜色
        cancelButtonColor: '#3085d6',       // 取消按钮颜色
        confirmButtonText: '删除',           // 确认按钮文本
        cancelButtonText: '取消'            // 取消按钮文本
    }).then((result) => {
        if (result.isConfirmed) {
            // 如果用户点击了 "删除"，执行删除逻辑
            const xhr = new XMLHttpRequest();
            xhr.open('GET', '/tenants/deleteApi?tenantId=' + tenantId, true);

            // 设置CSRF令牌
            const token = _getCsrfToken();
            xhr.setRequestHeader('X-CSRF-TOKEN', token);

            xhr.onload = function () {
                if (xhr.status === 200) {
                    Swal.fire({
                        icon: 'success',
                        title: '删除成功！',
                        text: '该API已成功删除。',
                        confirmButtonText: '关闭'
                    }).then(() => {
                        location.reload(); // 删除成功后刷新页面
                    });
                } else {
                    Swal.fire({
                        icon: 'error',
                        title: '删除失败！',
                        text: '请稍后重试。',
                        confirmButtonText: '关闭'
                    });
                }
            };

            xhr.onerror = function () {
                Swal.fire({
                    icon: 'error',
                    title: '网络错误！',
                    text: '无法连接到服务器，请检查网络。',
                    confirmButtonText: '关闭'
                });
            };

            xhr.send();
        }
    });
}*/

// 初始化
document.addEventListener('DOMContentLoaded', function() {
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
    document.querySelectorAll('.modal-overlay').forEach(modal => {
        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                modal.style.display = 'none';
            }
        });
    });
});

function showSecurityRules(tenantId) {
    const modal = document.getElementById('securityRulesModal');
    modal.style.display = 'flex';
    loadSecurityRules(tenantId);
}

function loadSecurityRules(tenantId) {
    const activeTab = document.querySelector('.security-rules-tab.active').dataset.tab;
    const loadingContainer = document.getElementById('rulesLoadingContainer');
    const rulesTable = document.querySelector('.rules-table');
    const tableBody = document.getElementById('rulesTableBody');
    const modal = document.getElementById('securityRulesModal');
    currentPage = 1;
    loadingContainer.style.display = 'block';
    rulesTable.classList.add('table-loading');
    tableBody.innerHTML = '';
    const xhr = new XMLHttpRequest();
    xhr.open('GET', `/tenants/security-rules?tenantId=`+tenantId +`&type=`+ activeTab+``, true);
    const token = _getCsrfToken();
    xhr.setRequestHeader('X-CSRF-TOKEN', token);
    xhr.onload = function() {
        loadingContainer.style.display = 'none';
        rulesTable.classList.remove('table-loading');
        if (xhr.status === 200) {
            try {
                const rules = JSON.parse(xhr.responseText);
                modal.dataset.rules = JSON.stringify(rules);
                updateRulesTable(rules);
            } catch (error) {
                console.error('Failed to load security rules:', error);
                tableBody.innerHTML = `
                <tr>
                    <td colspan="5" style="text-align: center; color: var(--accent-red);">
                        ${i18n.detail_loadRuleFail}
                    </td>
                </tr>`;
            }
        } else {
            tableBody.innerHTML = `
            <tr>
                <td colspan="5" style="text-align: center; color: var(--accent-red);">
                    ${i18n.detail_loadRuleFail}
                </td>
            </tr>`;
        }
    };

    xhr.onerror = function() {
        loadingContainer.style.display = 'none';
        rulesTable.classList.remove('table-loading');
        tableBody.innerHTML = `
        <tr>
            <td colspan="5" style="text-align: center; color: var(--accent-red);">
                ${i18n.detail_loadRuleFail}
            </td>
        </tr>`;
    };

    xhr.send();
}

function updateRulesTable(rules) {
    const tbody = document.getElementById('rulesTableBody');
    const modal = document.getElementById('securityRulesModal');
    const tenantId = modal.dataset.tenantId;
    const activeTab = document.querySelector('.security-rules-tab.active').dataset.tab;
    allRules = rules;
    const totalPages = Math.ceil(rules.length / itemsPerPage);
    const startIndex = (currentPage - 1) * itemsPerPage;
    const endIndex = startIndex + itemsPerPage;
    const currentPageRules = rules.slice(startIndex, endIndex);
    tbody.innerHTML = '';
    if (rules.length === 0) {
        const tr = document.createElement('tr');
        tr.innerHTML = '<td colspan="6" style="text-align: center;">'+i18n.common_noData+'</td>';
        tbody.appendChild(tr);
        updatePaginationControls(0, 0);
        return;
    }
    modal.dataset.rules = JSON.stringify(rules);
    currentPageRules.forEach((rule, pageIndex) => {
        const actualIndex = startIndex + pageIndex;
        const protocolDisplay = formatProtocol(rule.protocol);
        const portsDisplay = (rule.ports === 'null' ||
            rule.ports === 'N/A' ||
            rule.ports === null ||
            rule.protocol === '1' ||
            rule.protocol === 1)
            ? '-'
            : rule.ports;
        const compositeId = tenantId + "_" + actualIndex + "_" + activeTab;
        const tr = document.createElement('tr');
        tr.innerHTML =
            '<td>' + (actualIndex + 1) + '</td>' +
            '<td>' + rule.type + '</td>' +
            '<td>' + protocolDisplay + '</td>' +
            '<td>' + rule.source + '</td>' +
            '<td>' + portsDisplay + '</td>' +
            '<td class="rule-actions">' +
            '<button class="btn btn-primary btn-icon" onclick="editRule(\'' + compositeId + '\')">' +
            '<i class="fas fa-edit"></i>' +
            '</button>' +
            '<button class="btn btn-danger btn-icon" onclick="deleteRule(\'' + compositeId + '\')">' +
            '<i class="fas fa-trash"></i>' +
            '</button>' +
            '</td>';
        tbody.appendChild(tr);
    });
    updatePaginationControls(currentPage, totalPages);
}

function updatePaginationControls(current, total) {
    let paginationHtml = '';

    if (total > 1) {
        var prevPage = current - 1;
        var nextPage = current + 1;
        var prevDisabled = current <= 1;
        var nextDisabled = current >= total;
        paginationHtml =
            '<div class="pagination-controls" style="display: flex; justify-content: center; align-items: center; margin-top: 15px; gap: 10px;">' +
            '<button class="btn btn-primary' + (prevDisabled ? ' disabled' : '') + '" ' +
            'onclick="goToPage(' + prevPage + ')" ' +
            (prevDisabled ? 'disabled' : '') + '>' +
            '<i class="fas fa-chevron-left"></i> '+i18n.page_prev+'' +
            '</button>' +
            '<span style="color: var(--text-secondary); font-size: 14px;">' +
            ''+i18n.detail_to+' ' + current + ' '+i18n.detail_pageTotal+' ' + total + ''+i18n.detail_pageTotal2+'' + allRules.length + ' '+i18n.detail_pageTotal3+'' +
            '</span>' +
            '<button class="btn btn-primary' + (nextDisabled ? ' disabled' : '') + '" ' +
            'onclick="goToPage(' + nextPage + ')" ' +
            (nextDisabled ? 'disabled' : '') + '>' +
            ''+i18n.page_next+' <i class="fas fa-chevron-right"></i>' +
            '</button>' +
            '</div>';
    }
    let paginationContainer = document.querySelector('.pagination-controls');
    if (paginationContainer) {
        paginationContainer.remove();
    }
    const rulesTable = document.querySelector('.rules-table');
    if (rulesTable && paginationHtml) {
        rulesTable.insertAdjacentHTML('afterend', paginationHtml);
    }
}

function goToPage(page) {
    const totalPages = Math.ceil(allRules.length / itemsPerPage);
    if (page < 1 || page > totalPages) {
        return;
    }
    currentPage = page;
    updateRulesTable(allRules);
}

function editRule(compositeId) {
    const parts = compositeId.split('_');
    const tenantId = parts[0];
    const ruleIndex = parseInt(parts[1]);
    const ruleType = parts[2];

    const modal = document.getElementById('securityRulesModal');
    if (!modal) {
        return;
    }

    if (!modal.dataset.rules) {
        console.error('规则数据不存在');
        return;
    }

    try {
        const rules = JSON.parse(modal.dataset.rules);
        if (!Array.isArray(rules)) {
            console.error('规则数据不是有效的数组格式');
            return;
        }
        if (ruleIndex < 0 || ruleIndex >= rules.length) {
            console.error('规则索引无效');
            return;
        }

        const rule = rules[ruleIndex];
        if (!rule) {
            console.error('规则数据无效');
            return;
        }

        const protocolValue = rule.protocol === 'all' ? 'all' :
            (rule.protocol === '1' || rule.protocol === 1 ? 'icmp' :
                (rule.protocol === '6' || rule.protocol === 6 ? 'tcp' :
                    (rule.protocol === '17' || rule.protocol === 17 ? 'udp' : rule.protocol)));
        const protocolSelect = document.getElementById('ruleProtocol');
        const sourceInput = document.getElementById('ruleSource');
        const portsInput = document.getElementById('rulePorts');
        const editForm = document.getElementById('editRuleForm');
        const formGroups = editForm.querySelectorAll('.form-group');
        const portsLabel = formGroups.length >= 3 ? formGroups[2].querySelector('label') : null;
        if (!protocolSelect || !sourceInput || !portsInput || !editForm) {
            console.error('找不到必要的表单元素，请刷新后重试');
            return;
        }
        protocolSelect.value = protocolValue;
        sourceInput.value = rule.source || '';
        if (protocolValue === 'icmp') {
            portsInput.placeholder = i18n.tenant_icmpNoPort;
            portsInput.disabled = true;
            portsInput.value = '';
            if (portsLabel) {
                portsLabel.innerHTML = i18n.tenant_portRange+' <span style="color: #666;">'+i18n.detail_icmpNoNeed+'</span>';
            }
        } else if (protocolValue === 'all') {
            portsInput.placeholder = i18n.detail_openAll;
            portsInput.disabled = true;
            portsInput.value = '';
            if (portsLabel) {
                portsLabel.innerHTML = i18n.tenant_portRange+' <span style="color: #666;">'+i18n.detail_openAllInCloud+'</span>';
            }
        } else {
            portsInput.placeholder = '80,443 或 80-443';
            portsInput.disabled = false;
            portsInput.value = rule.ports || '';
            if (portsLabel) {
                portsLabel.innerHTML = i18n.tenant_portRange+' <span style="color: red;">*</span>';
            }
        }
        editForm.style.display = 'block';
        editForm.dataset.mode = 'edit';
        editForm.dataset.compositeId = compositeId;
    } catch (error) {
        console.error('规则解析错误:', error);
        console.log('规则数据内容:', modal.dataset.rules);
    }
}

function saveRule() {
    const protocol = document.getElementById('ruleProtocol').value;
    const source = document.getElementById('ruleSource').value;
    const ports = document.getElementById('rulePorts').value;
    const editForm = document.getElementById('editRuleForm');
    const mode = editForm.dataset.mode || 'add';
    const modal = document.getElementById('securityRulesModal');
    const tenantId = modal.dataset.tenantId;
    const activeTab = document.querySelector('.security-rules-tab.active').dataset.tab;

    // 验证输入
    if (!source) {
        Swal.fire({
            title: 'error',
            text: i18n.common_plzInputGlobalRequired,
            icon: 'error',
            confirmButtonColor: 'var(--accent-blue)'
        });
        return;
    }

    if (protocol !== 'icmp' && protocol !== 'all' && !ports) {
        Swal.fire({
            title: 'error',
            text: i18n.common_plzInputGlobalRequired,
            icon: 'error',
            confirmButtonColor: 'var(--accent-blue)'
        });
        return;
    }

    const data = {
        tenantId: tenantId,
        type: activeTab,
        protocol: protocol,
        source: source,
        ports: protocol === 'icmp' ? '' : ports
    };

    let url, method;
    if (mode === 'edit') {
        const compositeId = editForm.dataset.compositeId;
        url = `/tenants/security-rules/`+ compositeId;
        method = 'PUT';
    } else {
        url = '/tenants/security-rules';
        method = 'POST';
        currentPage = 1;
    }

    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });

    const xhr = new XMLHttpRequest();
    xhr.open(method, url, true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    const token = _getCsrfToken();
    xhr.setRequestHeader('X-CSRF-TOKEN', token);
    xhr.onload = function() {
        if (xhr.status === 200) {
            loadSecurityRules(tenantId);
            editForm.style.display = 'none';
            editForm.dataset.mode = '';
            editForm.dataset.compositeId = '';
            Swal.fire({
                title: 'success',
                text: 'successful',
                icon: 'success',
                confirmButtonColor: 'var(--accent-green)'
            });
        } else {
            showError();
        }
    };

    xhr.onerror = function() {
       showError();
    };
    xhr.send(JSON.stringify(data));
}

function cancelEdit() {
    const editForm = document.getElementById('editRuleForm');

    Swal.fire({
        title: i18n.common_confirm,
        icon: 'question',
        showCancelButton: true,
        confirmButtonColor: 'var(--accent-blue)',
        cancelButtonColor: 'var(--accent-green)',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            editForm.style.display = 'none';
            editForm.dataset.mode = '';
            editForm.dataset.compositeId = '';
        }
    });
}

function deleteRule(compositeId) {
    Swal.fire({
        title: i18n.common_confirm,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: 'var(--accent-red)',
        cancelButtonColor: 'var(--accent-blue)',
        confirmButtonText: i18n.common_delete,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            const xhr = new XMLHttpRequest();
            xhr.open('DELETE', `/tenants/security-rules/`+compositeId, true);
            const token = _getCsrfToken();
            xhr.setRequestHeader('X-CSRF-TOKEN', token);
            Swal.fire({
                title: 'loading',
                allowOutsideClick: false,
                didOpen: () => {
                    Swal.showLoading();
                }
            });
            xhr.onload = function() {
                if (xhr.status === 200) {
                    const modal = document.getElementById('securityRulesModal');
                    const tenantId = modal.dataset.tenantId;
                    Swal.fire({
                        title: 'success',
                        text: 'successful',
                        icon: 'success',
                        confirmButtonColor: 'var(--accent-green)'
                    }).then(() => {
                        loadSecurityRules(tenantId);
                    });
                } else {
                    showError();
                }
            };

            xhr.onerror = function() {
                showError();
            };
            xhr.send();
        }
    });
}

function addNewRule() {
    const protocolSelect = document.getElementById('ruleProtocol');
    const sourceInput = document.getElementById('ruleSource');
    const portsInput = document.getElementById('rulePorts');
    const editForm = document.getElementById('editRuleForm');

    if (!protocolSelect || !sourceInput || !portsInput || !editForm) {
        return;
    }

    // 清空表单数据
    protocolSelect.value = 'tcp';
    sourceInput.value = '';
    portsInput.value = '';
    const formGroups = editForm.querySelectorAll('.form-group');
    const portsLabel = formGroups.length >= 3 ? formGroups[2].querySelector('label') : null;
    portsInput.placeholder = '80,443 或 80-443';
    portsInput.disabled = false;
    if (portsLabel) {
        portsLabel.innerHTML = i18n.tenant_portRange+' <span style="color: red;">*</span>';
    }
    editForm.dataset.mode = 'add';
    editForm.dataset.compositeId = '';
    editForm.style.display = 'block';
}

function saveRule() {
    const protocol = document.getElementById('ruleProtocol').value;
    const source = document.getElementById('ruleSource').value;
    const ports = document.getElementById('rulePorts').value;
    const editForm = document.getElementById('editRuleForm');
    const mode = editForm.dataset.mode || 'add';
    const modal = document.getElementById('securityRulesModal');
    const tenantId = modal.dataset.tenantId;
    const activeTab = document.querySelector('.security-rules-tab.active').dataset.tab;
    if (!source) {
        Swal.fire({
            title: 'error',
            text: i18n.common_plzInputGlobalRequired,
            icon: 'error',
            confirmButtonColor: 'var(--accent-blue)'
        });
        return;
    }
    if (protocol !== 'icmp' && protocol !== 'all' && !ports) {
        Swal.fire({
            title: 'error',
            text: i18n.common_plzInputGlobalRequired,
            icon: 'error',
            confirmButtonColor: 'var(--accent-blue)'
        });
        return;
    }

    const data = {
        tenantId: tenantId,
        type: activeTab,
        protocol: protocol,
        source: source,
        ports: protocol === 'icmp' ? '' : ports
    };

    let url, method;
    if (mode === 'edit') {
        const compositeId = editForm.dataset.compositeId;
        url = `/tenants/security-rules/`+ compositeId;
        method = 'PUT';
    } else {
        url = '/tenants/security-rules';
        method = 'POST';
    }
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });
    const xhr = new XMLHttpRequest();
    xhr.open(method, url, true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    const token = _getCsrfToken();
    xhr.setRequestHeader('X-CSRF-TOKEN', token);
    xhr.onload = function() {
        if (xhr.status === 200) {
            loadSecurityRules(tenantId);
            editForm.style.display = 'none';
            editForm.dataset.mode = '';
            editForm.dataset.compositeId = '';
            Swal.fire({
                title: 'success',
                text: 'successful',
                icon: 'success',
                confirmButtonColor: 'var(--accent-green)'
            });
        } else {
            showError();
        }
    };
    xhr.onerror = function() {
        showError();
    };

    xhr.send(JSON.stringify(data));
}

let currentTenantId = null;
function showSecurityRules(tenantId) {
    const modal = document.getElementById('securityRulesModal');
    modal.dataset.tenantId = tenantId;
    modal.style.display = 'flex';
    loadSecurityRules(tenantId);
}

/*function showUserManagement(tenantId) {
    const modal = document.getElementById('userManagementModal');
    modal.dataset.tenantId = tenantId;
    modal.style.display = 'flex';
    loadUserList(tenantId);
}*/

/*function loadUserList(tenantId) {
    const tbody = document.getElementById('userListTableBody');
    tbody.innerHTML = `<tr><td colspan="5" class="text-center"><span class="loading-spinner"></span> ${i18n.common_loading}</td></tr>`;

    const xhr = new XMLHttpRequest();
    xhr.open('GET', `/tenants/oracle-users?tenantId=` + tenantId, true);
    const token = _getCsrfToken();
    xhr.setRequestHeader('X-CSRF-TOKEN', token);
    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const users = JSON.parse(xhr.responseText);
                updateUserTable(users);
            } catch (error) {
                tbody.innerHTML = `<tr><td colspan="5" class="text-center" style="color: var(--accent-red);">加载用户列表失败</td></tr>`;
            }
        } else {
            tbody.innerHTML = `<tr><td colspan="5" class="text-center" style="color: var(--accent-red);">加载用户列表失败</td></tr>`;
        }
    };

    xhr.onerror = function() {
        tbody.innerHTML = `<tr><td colspan="5" class="text-center" style="color: var(--accent-red);">加载用户列表失败</td></tr>`;
    };

    xhr.send();
}*/

/*function updateUserTable(users) {
    const tbody = document.getElementById('userListTableBody');
    tbody.innerHTML = '';

    users.forEach(user => {
        const tr = document.createElement('tr');

        // 设置状态样式：Active 为绿色，其余为红色
        const userStatusClass = user.lifecycleState === 'Active' ? 'status-active' : 'status-locked';

        tr.innerHTML =
            '<td>' + user.username + '</td>' +
            '<td>' + user.email + '</td>' +
            '<td><span class="user-status ' + userStatusClass + '">' + user.lifecycleState + '</span></td>' +
            '<td>' + user.timeCreated + '</td>' +
            '<td>' + (user.lastSuccessfulLoginTime ? user.lastSuccessfulLoginTime : '-') + '</td>';

        tbody.appendChild(tr);
    });
}*/


/*function showAddUserForm() {
    // Create form content
    const addUserForm = document.getElementById('addUserForm');

    // Show loading state
    addUserForm.innerHTML = `
        <div class="loading-container" style="display: flex; justify-content: center; padding: 20px;">
            <span class="loading-spinner"></span>
            <span class="loading-text">正在加载用户组...</span>
        </div>
    `;
    addUserForm.style.display = 'block';

    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;

    // Fetch groups from backend
    fetchGroups(tenantId)
        .then(groups => {
            // Prepare options for the dropdown
            let groupOptions = '';
            for (var i = 0; i < groups.length; i++) {
                groupOptions += '<option value="' + groups[i].groupId + '">' + groups[i].groupName + '</option>';
            }

            // Build the form with groups dropdown
            addUserForm.innerHTML =
                '<div style="margin-bottom: 15px; padding: 8px 12px; background-color: rgba(33, 150, 243, 0.1); border-radius: 4px; color: var(--accent-blue);">' +
                '<i class="fas fa-info-circle" style="margin-right: 8px;"></i>' +
                '<span style="font-size: 12px;">当前创建的用户默认在 <strong>DEFAULT</strong> 域</span>' +
                '</div>' +
                '<div class="form-group">' +
                '<label>用户名 <span style="color: red;">*</span></label>' +
                '<input type="text" id="newUsername" placeholder="请输入用户名" required>' +
                '</div>' +
                '<div class="form-group">' +
                '<label>邮箱 <span style="color: red;">*</span></label>' +
                '<input type="email" id="email" placeholder="请输入邮箱" required>' +
                '</div>' +
                '<div class="form-group">' +
                '<label>用户组 <span style="color: red;">*</span></label>' +
                '<select id="userGroup" class="form-control">' +
                '<option value="">请选择用户组</option>' +
                groupOptions +
                '</select>' +
                '</div>' +
                '<div class="form-group" style="display: flex; align-items: center; margin-top: -5px;">' +
                '<input type="checkbox" id="useEmailAsUsername" style="width: auto; margin-right: 8px;">' +
                '<label for="useEmailAsUsername" style="cursor: pointer; font-size: 12px; color: var(--text-secondary);">' +
                '使用邮箱作为用户名' +
                '</label>' +
                '</div>' +
                '<div class="form-actions">' +
                '<button class="btn btn-primary" onclick="createUser()">创建</button>' +
                '<button class="btn btn-danger" onclick="hideAddUserForm()">取消</button>' +
                '</div>';

            // Add event listeners
            document.getElementById('useEmailAsUsername').addEventListener('change', function() {
                const emailInput = document.getElementById('email');
                const usernameInput = document.getElementById('newUsername');

                if (this.checked) {
                    // If checkbox is checked, use email value to fill username
                    usernameInput.value = emailInput.value;
                    usernameInput.disabled = true;
                } else {
                    // If unchecked, enable username input
                    usernameInput.disabled = false;
                }
            });

            // When email changes, if checkbox is checked, sync username
            document.getElementById('email').addEventListener('input', function() {
                const useEmailCheckbox = document.getElementById('useEmailAsUsername');
                const usernameInput = document.getElementById('newUsername');

                if (useEmailCheckbox.checked) {
                    usernameInput.value = this.value;
                }
            });
        })
        .catch(error => {
            addUserForm.innerHTML = `
                <div class="status-message error" style="margin-bottom: 15px;">
                    <i class="fas fa-exclamation-circle" style="margin-right: 8px;"></i>
                    <span>加载用户组失败：` + error.message +`</span>
                </div>
                <div class="form-group">
                    <label>用户名 <span style="color: red;">*</span></label>
                    <input type="text" id="newUsername" placeholder="请输入用户名" required>
                </div>
                <div class="form-group">
                    <label>邮箱 <span style="color: red;">*</span></label>
                    <input type="email" id="email" placeholder="请输入邮箱" required>
                </div>
                <div class="form-group" style="display: flex; align-items: center; margin-top: -5px;">
                    <input type="checkbox" id="useEmailAsUsername" style="width: auto; margin-right: 8px;">
                    <label for="useEmailAsUsername" style="cursor: pointer; font-size: 12px; color: var(--text-secondary);">
                        使用邮箱作为用户名
                    </label>
                </div>
                <div class="form-actions">
                    <button class="btn btn-primary" onclick="createUser()">创建</button>
                    <button class="btn btn-danger" onclick="hideAddUserForm()">取消</button>
                </div>
            `;

            // Add event listeners
            document.getElementById('useEmailAsUsername').addEventListener('change', function() {
                const emailInput = document.getElementById('email');
                const usernameInput = document.getElementById('newUsername');

                if (this.checked) {
                    usernameInput.value = emailInput.value;
                    usernameInput.disabled = true;
                } else {
                    usernameInput.disabled = false;
                }
            });

            document.getElementById('email').addEventListener('input', function() {
                const useEmailCheckbox = document.getElementById('useEmailAsUsername');
                const usernameInput = document.getElementById('newUsername');

                if (useEmailCheckbox.checked) {
                    usernameInput.value = this.value;
                }
            });
        });
}*/


function hideAddUserForm() {
    document.getElementById('addUserForm').style.display = 'none';
}

/*function createUser() {
    const usernameInput = document.getElementById('newUsername');
    const emailInput = document.getElementById('email');
    const useEmailAsUsername = document.getElementById('useEmailAsUsername');
    const groupSelect = document.getElementById('userGroup');

    // Get current values
    let username = usernameInput.value.trim();
    const email = emailInput.value.trim();
    const groupId = groupSelect ? groupSelect.value : '';

    // If using email as username, ensure username matches email
    if (useEmailAsUsername.checked) {
        username = email;
    }

    // Validate inputs
    if (!username || !email) {
        Swal.fire({
            title: '输入错误',
            text: '请填写所有必填字段',
            icon: 'error',
            confirmButtonColor: 'var(--accent-red)'
        });
        return;
    }

    // Validate group selection if group dropdown exists
    if (groupSelect && !groupId) {
        Swal.fire({
            title: '输入错误',
            text: '请选择用户组',
            icon: 'error',
            confirmButtonColor: 'var(--accent-red)'
        });
        return;
    }

    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;

    // Show loading state
    Swal.fire({
        title: '创建中',
        text: '正在创建用户...',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/oracle-users', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    const token = _getCsrfToken();
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function () {
        if (xhr.status === 200) {
            const response = JSON.parse(xhr.responseText);
            hideAddUserForm();
            //loadUserList(tenantId);

            // Display success message with user info and password
            Swal.fire({
                title: '用户创建成功',
                html:
                    '<div style="text-align: left; margin: 20px 0;">' +
                    '<div style="margin-bottom: 15px;">' +
                    '<span style="font-weight: bold;">用户名：</span>' +
                    '<span>' + response.username + '</span>' +
                    '</div>' +
                    '<div style="margin-bottom: 15px;">' +
                    '<span style="font-weight: bold;">邮  箱：</span>' +
                    '<span>' + response.email + '</span>' +
                    '</div>' +
                    '<div style="margin-bottom: 15px;">' +
                    '<span style="font-weight: bold;">用户组：</span>' +
                    '<span>' + (groupSelect ? groupSelect.options[groupSelect.selectedIndex].text : '默认组') + '</span>' +
                    '</div>' +
                    '<div style="margin-bottom: 15px;">' +
                    '<span style="font-weight: bold;">密  码：</span>' +
                    '<span style="color: var(--accent-red); font-family: monospace; background: var(--hover-bg); padding: 2px 6px; border-radius: 3px;">' + response.password + '</span>' +
                    '</div>' +
                    '<div style="margin-top: 20px; padding: 10px; background-color: #fff3cd; color: #856404; border-radius: 4px; font-size: 14px;">' +
                    '<i class="fas fa-exclamation-triangle" style="margin-right: 8px;"></i>' +
                    '<strong>注意：</strong>密码仅展示一次，请妥善保存！' +
                    '</div>' +
                    '</div>',
                confirmButtonText: '已复制并保存',
                confirmButtonColor: 'var(--accent-green)',
                showCancelButton: true,
                cancelButtonText: '复制密码',
                cancelButtonColor: 'var(--accent-blue)',
            }).then((result) => {
                if (!result.isConfirmed) {
                    // If user clicked "Copy Password", copy to clipboard
                    navigator.clipboard.writeText(response.password)
                        .then(() => {
                            Swal.fire({
                                title: '复制成功',
                                text: '密码已复制到剪贴板',
                                icon: 'success',
                                confirmButtonColor: 'var(--accent-green)',
                                timer: 2000,
                                timerProgressBar: true
                            });
                        })
                        .catch(() => {
                            Swal.fire({
                                title: '复制失败',
                                text: '请手动复制密码',
                                icon: 'warning',
                                confirmButtonColor: 'var(--accent-green)'
                            });
                        });
                }
            });
        } else {
            Swal.fire({
                title: '创建失败',
                text: '创建用户失败，请重试',
                icon: 'error',
                confirmButtonColor: 'var(--accent-red)'
            });
        }
    };

    xhr.onerror = function() {
        Swal.fire({
            title: '网络错误',
            text: '无法连接到服务器，请检查网络',
            icon: 'error',
            confirmButtonColor: 'var(--accent-red)'
        });
    };

    // Send request with group ID if available
    xhr.send(JSON.stringify({
        tenantId: tenantId,
        username: username,
        email: email,
        groupId: groupId || undefined
    }));
}*/

/*function refreshUserList() {
    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;
    //loadUserList(tenantId);
}*/

/*function resetUserPassword(username) {
    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;

    const newPassword = prompt('请输入新密码');
    if (!newPassword) return;

    const xhr = new XMLHttpRequest();
    xhr.open('PUT', `/tenants/oracle-users/` +username + `/reset-password`, true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    const token = _getCsrfToken();
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            alert('密码重置成功');
            loadUserList(tenantId);
        } else {
            alert('密码重置失败，请重试');
        }
    };

    xhr.send(JSON.stringify({
        tenantId: tenantId,
        password: newPassword
    }));
}*/


/*function exportData() {
    fetch('/tenants/export', {
        method: 'GET',
        headers: {
            'X-CSRF-TOKEN': _getCsrfToken()
        }
    })
        .then(response => response.json())
        .then(data => {
            const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = 'exported_data.json';
            a.click();
            URL.revokeObjectURL(url);
        })
        .catch(err => {
            alert('导出失败：' + err.message);
        });
}*/

/*function importData() {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'application/json';

    input.onchange = () => {
        const file = input.files[0];
        const reader = new FileReader();

        reader.onload = () => {
            const jsonData = JSON.parse(reader.result);

            // 创建 XMLHttpRequest 实例
            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/tenants/import', true);

            // 设置请求头，包括 CSRF Token
            const csrfToken = _getCsrfToken();
            xhr.setRequestHeader('Content-Type', 'application/json');
            xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

            // 定义响应处理
            xhr.onload = function () {
                if (xhr.status === 200) {
                    Swal.fire({
                        icon: 'success',
                        title: '导入成功！',
                        text: '数据已成功导入。',
                        confirmButtonText: '刷新页面'
                    }).then(() => {
                        location.reload(); // 刷新当前页面
                    });
                } else {
                    Swal.fire({
                        icon: 'error',
                        title: '导入失败！',
                        text: xhr.responseText || '请检查数据格式或网络连接。',
                        confirmButtonText: '关闭'
                    });
                }
            };

            xhr.onerror = function () {
                Swal.fire({
                    icon: 'error',
                    title: '导入请求失败！',
                    text: '无法连接到服务器，请检查网络连接。',
                    confirmButtonText: '关闭'
                });
            };

            // 发送 JSON 数据
            xhr.send(JSON.stringify(jsonData));
        };

        reader.readAsText(file);
    };

    input.click();
}*/

/*function startAccountCheck() {
    // 显示 SweetAlert2 的加载中模态框
    Swal.fire({
        title: '账号检测中',
        text: '正在检测账号状态，请稍候...',
        icon: 'info',
        allowOutsideClick: false,
        showCancelButton: false,
        showConfirmButton: false,
        didOpen: function () {
            Swal.showLoading(); // 显示加载动画
        }
    });

    // 发起检测请求
    const xhr = new XMLHttpRequest();
    xhr.open('GET', '/tenants/checkAccounts', true);

    xhr.onload = function () {
        if (xhr.status === 200) {
            const result = JSON.parse(xhr.responseText);

            // 创建一个画布元素，用于绘制图表
            const canvasContainer = document.createElement('div');
            canvasContainer.style.width = '100%';
            canvasContainer.style.height = '300px'; // 限制图表高度
            canvasContainer.style.margin = '0 auto';
            const canvas = document.createElement('canvas');
            canvas.style.maxHeight = '300px'; // 图表的最大高度
            canvasContainer.appendChild(canvas);

            // 等待图表加载后显示 SweetAlert2
            Swal.fire({
                title: '检测完成！',
                html: '<div style="width: 100%; text-align: center;">账号数据分析</div>',
                confirmButtonText: '关闭',
                didOpen: () => {
                    Swal.getHtmlContainer().appendChild(canvasContainer);

                    // 初始化 Chart.js 图表
                    new Chart(canvas, {
                        type: 'bar',
                        data: {
                            labels: ['总账号数量', '正常账号数量', '异常账号数量'],
                            datasets: [{
                                label: '账号数据统计',
                                data: [result.totalAccounts, result.activeAccounts, result.inactiveAccounts],
                                backgroundColor: [
                                    '#4CAF50', // 绿色：总账号数量
                                    '#2196F3', // 蓝色：正常账号数量
                                    '#F44336'  // 红色：异常账号数量
                                ],
                                borderColor: [
                                    '#4CAF50',
                                    '#2196F3',
                                    '#F44336'
                                ],
                                borderWidth: 1
                            }]
                        },
                        options: {
                            responsive: true,
                            maintainAspectRatio: false, // 禁止自动保持宽高比例
                            scales: {
                                y: {
                                    beginAtZero: true,
                                    ticks: {
                                        stepSize: 1, // 每次增加 1
                                        callback: function (value) {
                                            return Number.isInteger(value) ? value : ''; // 仅显示整数
                                        }
                                    }
                                }
                            },
                            plugins: {
                                legend: {
                                    display: true
                                },
                                tooltip: {
                                    callbacks: {
                                        label: function (context) {
                                            return context.raw + ' 个账号';
                                        }
                                    }
                                }
                            },
                            elements: {
                                bar: {
                                    barThickness: 10, // 控制柱子宽度
                                    maxBarThickness: 35 // 设置柱子的最大宽度
                                }
                            }
                        }
                    });
                }
            });
        } else {
            Swal.fire({
                title: '检测失败！',
                text: '检测过程中发生错误，请稍后重试。',
                icon: 'error',
                confirmButtonText: '关闭'
            });
        }
    };

    xhr.onerror = function () {
        Swal.fire({
            title: '网络错误！',
            text: '无法连接到服务器，请检查网络。',
            icon: 'error',
            confirmButtonText: '关闭'
        });
    };

    xhr.send();
}*/


/*function closeAccountCheckModal() {
    const modal = document.getElementById('accountCheckModal');
    modal.style.display = 'none';
}*/


function showBootVolumeManagement(tenantId) {
    var modal = document.getElementById("bootVolumesModal");
    var modalContainer = modal.querySelector(".modal-container");

    // 添加重置大小按钮
    if (!document.querySelector(".reset-size-btn")) {
        var resetSizeBtn = document.createElement("button");
        resetSizeBtn.className = "reset-size-btn";
        resetSizeBtn.title = i18n.detail_resetSize;
        resetSizeBtn.innerHTML = '<i class="fas fa-expand-arrows-alt"></i>';
        resetSizeBtn.onclick = function() {
            modalContainer.style.width = "90%";
            modalContainer.style.maxWidth = "900px";
            modalContainer.style.height = "80vh";
        };
        modalContainer.appendChild(resetSizeBtn);
    }
    modal.style.display = "flex";

    var modalTitle = document.querySelector('#bootVolumesModal .modal-header #modalTitle');
    modalTitle.innerHTML = '<i class="fas fa-hdd" style="color: var(--accent-green); margin-right: 10px;"></i> ID: ' + tenantId;

    var loadingIndicator = document.getElementById('bootVolumesLoading');
    var tableView = document.querySelector('#bootVolumesModal .table-responsive');

    // 重置状态
    loadingIndicator.style.display = 'flex';
    tableView.style.display = 'none';

    const token = _getCsrfToken();
    var requestUrl = '/tenants/boot-volumes?tenantId=' + encodeURIComponent(tenantId);
    showLoading(i18n.tenant_volumeMgrLoad || '正在加载硬盘信息...');
    fetch(requestUrl, {
        headers: {
            'X-CSRF-TOKEN': token
        }
    })
        .then(function(response) {
            if (!response.ok) {
                throw new Error('无法获取引导卷数据，请稍后重试。');
            }
            return response.json();
        })
        .then(function(data) {
            hideLoading();
            loadingIndicator.style.display = 'none';
            tableView.style.display = 'block';

            var tableBody = document.getElementById('bootVolumesTable');
            tableBody.innerHTML = '';

            if (data.length === 0) {
                tableBody.innerHTML = '<tr><td colspan="5" style="text-align: center; padding: 20px; color: var(--text-secondary);">'+i18n.detail_noVolume+'</td></tr>';
                return;
            }

            data.forEach(function(volume) {
                var row = document.createElement('tr');
                var instanceName = volume.instanceName || i18n.detail_noConnIns;
                var isOrphanVolume = !volume.instanceName;
                var actionButtons = '<div class="volume-actions">' +
                    '<button class="btn btn-primary edit-btn" data-id="' + volume.id + '">' +
                    '<i class="fas fa-edit"></i> <span>'+i18n.detail_update+'</span>' +
                    '</button>';
                if (isOrphanVolume) {
                    actionButtons +=
                        '<button class="btn btn-danger delete-btn" data-id="' + volume.id + '">' +
                        '<i class="fas fa-trash"></i> <span>'+i18n.common_delete+'</span>' +
                        '</button>';
                }
                actionButtons += '</div>';
                row.innerHTML =
                    '<td class="instance-name" title="' + instanceName + '">' +
                    (isOrphanVolume ? '<span style="color: var(--accent-red);">' + instanceName + '</span>' : instanceName) +
                    '</td>' +
                    '<td class="volume-name" title="' + volume.displayName + '">' + volume.displayName + '</td>' +
                    '<td style="text-align: center;"><span class="size-badge">' + volume.sizeInGBs + '</span></td>' +
                    '<td style="text-align: center;"><span class="vpus-badge">' + volume.vpusPerGB + '</span></td>' +
                    '<td style="text-align: center;">' + actionButtons + '</td>';

                tableBody.appendChild(row);
            });
            var editButtons = document.querySelectorAll('.edit-btn');
            editButtons.forEach(function(button) {
                button.addEventListener('click', function() {
                    var volumeId = this.getAttribute('data-id');
                    var row = this.closest('tr');
                    var nameCell = row.querySelector('.volume-name');
                    var vpusCell = row.querySelector('.vpus-badge');

                    var currentName = nameCell.textContent;
                    var currentVpus = parseInt(vpusCell.textContent, 10);

                    Swal.fire({
                        title: i18n.tenant_uv,
                        html:
                            '<div class="form-group" style="margin-bottom: 15px;">' +
                            '<div class="tenant-info-item" style="border: none; display: flex; align-items: center;">' +
                            '<span class="info-label" style="width: 120px; font-size: 14px; color: var(--text-primary);">'+i18n.tenant_un+':</span>' +
                            '<div class="info-value" style="width: 220px;">' +
                            '<input id="swal-input1" class="form-control" value="' + currentName + '" ' +
                            'style="width: 100%; padding: 8px 12px; background: var(--main-bg); ' +
                            'border: 1px solid var(--card-border); border-radius: 4px; ' +
                            'color: var(--text-primary); font-size: 14px;">' +
                            '</div>' +
                            '</div>' +
                            '</div>' +
                            '<div class="form-group" style="margin-bottom: 15px;">' +
                            '<div class="tenant-info-item" style="border: none; display: flex; align-items: center;">' +
                            '<span class="info-label" style="width: 120px; font-size: 14px; color: var(--text-primary);">VPUs:</span>' +
                            '<div class="info-value" style="flex: 1;">' +
                            '<div style="display: flex; align-items: center; gap: 10px;">' +
                            '<input id="swal-input2" type="range" min="10" max="120" step="10" ' +
                            'value="' + currentVpus + '" class="form-control" ' +
                            'style="flex: 1; height: 8px; background: var(--accent-green); ' +
                            'border: none; border-radius: 4px; cursor: pointer; ' +
                            'appearance: none; -webkit-appearance: none;">' +
                            '<output for="swal-input2" id="vpus-output" ' +
                            'style="min-width: 50px; padding: 6px 12px; text-align: center; ' +
                            'background: var(--hover-bg); border-radius: 4px; ' +
                            'color: var(--text-primary); font-size: 14px; font-weight: 500;">' +
                            currentVpus +
                            '</output>' +
                            '</div>' +
                            '</div>' +
                            '</div>' +
                            '</div>' +
                            '<style>' +
                            'input[type="range"]::-webkit-slider-thumb {' +
                            'appearance: none;' +
                            '-webkit-appearance: none;' +
                            'width: 20px;' +
                            'height: 20px;' +
                            'background: var(--accent-green);' +
                            'border: 2px solid white;' +
                            'border-radius: 50%;' +
                            'cursor: pointer;' +
                            'transition: all 0.2s;' +
                            'margin-top: -6px;' +
                            '}' +
                            'input[type="range"]::-webkit-slider-thumb:hover {' +
                            'transform: scale(1.1);' +
                            'background: var(--accent-blue);' +
                            '}' +
                            'input[type="range"]:focus {' +
                            'outline: none;' +
                            '}' +
                            '.form-group input:focus {' +
                            'border-color: var(--accent-green);' +
                            'outline: none;' +
                            'box-shadow: 0 0 0 2px rgba(26, 188, 156, 0.2);' +
                            '}' +
                            '</style>',
                        showClass: {
                            popup: 'animate__animated animate__fadeIn'
                        },
                        hideClass: {
                            popup: 'animate__animated animate__fadeOut'
                        },
                        width: '500px',
                        background: 'var(--main-bg)',
                        confirmButtonColor: 'var(--accent-green)',
                        confirmButtonText: i18n.common_confirm,
                        cancelButtonText: i18n.common_cancel,
                        showCancelButton: true,
                        focusConfirm: false,
                        customClass: {
                            title: 'text-lg font-medium text-gray-900',
                            htmlContainer: 'mt-4',
                            actions: 'mt-5 flex justify-end gap-2'
                        },
                        didOpen: () => {
                            const slider = document.getElementById('swal-input2');
                            const output = document.getElementById('vpus-output');
                            slider.oninput = function() {
                                output.textContent = this.value;
                            }
                        },
                        preConfirm: () => {
                            return [
                                document.getElementById('swal-input1').value,
                                document.getElementById('swal-input2').value
                            ]
                        }
                    }).then((result) => {
                        if (result.isConfirmed) {
                            var newName = result.value[0].trim();
                            var newVpus = parseInt(result.value[1], 10);

                            var updateName = newName !== currentName ? newName : '';
                            var updateVpus = newVpus !== currentVpus ? newVpus : -1;

                            if (updateName === '' && updateVpus === -1) {
                                return;
                            }

                            if (updateName !== '' && updateName === '') {
                                Swal.fire({
                                    title: 'error',
                                    text: i18n.common_plzInputGlobalRequired,
                                    icon: 'error',
                                    confirmButtonColor: 'var(--accent-green)'
                                });
                                return;
                            }
                            fetch('/tenants/update-volumes/' + volumeId, {
                                method: 'PUT',
                                headers: {
                                    'Content-Type': 'application/json',
                                    'X-CSRF-TOKEN': token
                                },
                                body: JSON.stringify({
                                    tenantId: tenantId,
                                    displayName: updateName,
                                    vpusPerGB: updateVpus
                                })
                            })
                                .then(response => response.json())
                                .then(data => {
                                    if (data.success) {
                                        if (updateName !== '') {
                                            nameCell.textContent = updateName;
                                            nameCell.title = updateName;
                                        }
                                        if (updateVpus !== -1) {
                                            vpusCell.textContent = updateVpus;
                                        }
                                        Swal.fire({
                                            title: 'success',
                                            text: 'successful',
                                            icon: 'success',
                                            confirmButtonColor: 'var(--accent-green)'
                                        });
                                    } else {
                                        showError();
                                    }
                                })
                                .catch(error => {
                                    showError();
                                });
                        }
                    });
                });
            });
            var deleteButtons = document.querySelectorAll('.delete-btn');
            deleteButtons.forEach(function(button) {
                button.addEventListener('click', function() {
                    var volumeId = this.getAttribute('data-id');
                    var row = this.closest('tr');

                    Swal.fire({
                        title: i18n.tenant_delete_title,
                        icon: 'warning',
                        showCancelButton: true,
                        confirmButtonColor: 'var(--accent-red)',
                        cancelButtonColor: 'var(--accent-blue)',
                        confirmButtonText: i18n.common_confirm,
                        cancelButtonText: i18n.common_cancel
                    }).then((result) => {
                        if (result.isConfirmed) {
                            Swal.fire({
                                title: 'loading',
                                allowOutsideClick: false,
                                didOpen: () => {
                                    Swal.showLoading();
                                }
                            });
                            fetch('/tenants/delete-volume/' + volumeId, {
                                method: 'DELETE',
                                headers: {
                                    'Content-Type': 'application/json',
                                    'X-CSRF-TOKEN': token
                                },
                                body: JSON.stringify({
                                    tenantId: tenantId
                                })
                            })
                                .then(response => response.json())
                                .then(data => {
                                    if (data.success) {
                                        row.style.opacity = '0';
                                        row.style.transition = 'opacity 0.5s';
                                        setTimeout(() => {
                                            row.remove();
                                            if (document.querySelectorAll('#bootVolumesTable tr').length === 0) {
                                                document.getElementById('bootVolumesTable').innerHTML =
                                                    '<tr><td colspan="5" style="text-align: center; padding: 20px; color: var(--text-secondary);">没有找到引导卷数据</td></tr>';
                                            }
                                        }, 500);

                                        Swal.fire({
                                            title: 'success',
                                            icon: 'success',
                                            confirmButtonColor: 'var(--accent-green)'
                                        });
                                    } else {
                                        showError();
                                    }
                                })
                                .catch(error => {
                                    showError();
                                });
                        }
                    });
                });
            });
            initResizableModal();
        })
        .catch(function(error) {
            hideLoading();
            loadingIndicator.style.display = 'none';
            console.error('加载引导卷数据时出错:', error);
            showError();
        });
}

/**
 * 关闭模态框
 * @param {string} modalId
 */
function closeModal(modalId) {
    var modal = document.getElementById(modalId);
    modal.style.display = 'none';
}

function formatProtocol(protocol) {
    switch(protocol) {
        case "6":
        case 6:
            return "TCP";
        case "1":
        case 1:
            return "ICMP";
        case "17":
        case 17:
            return "UDP";
        case "all":
            return i18n.detail_allProtocol;
        default:
            return protocol;
    }
}

function fetchGroups(tenantId) {
    return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.open('POST', '/tenants/groups', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        const token = _getCsrfToken();
        xhr.setRequestHeader('X-CSRF-TOKEN', token);
        xhr.onload = function() {
            if (xhr.status === 200) {
                try {
                    const groups = JSON.parse(xhr.responseText);
                    resolve(groups);
                } catch (error) {
                    reject(new Error('Failed to parse groups response'));
                }
            } else {
                reject(new Error('Failed to fetch groups'));
            }
        };

        xhr.onerror = function() {
            reject(new Error('Network error when fetching groups'));
        };
        xhr.send(JSON.stringify({ tenantId }));
    });
}

/*function batchEnableIcmp() {
    Swal.fire({
        title: '确认启用ICMP协议',
        text: '确定要为所有租户开启ICMP协议吗？',
        icon: 'question',
        showCancelButton: true,
        confirmButtonColor: '#1abc9c',
        cancelButtonColor: '#ef4444',
        confirmButtonText: '确认开启',
        cancelButtonText: '取消'
    }).then((result) => {
        if (result.isConfirmed) {
            // 显示处理中的状态
            Swal.fire({
                title: '处理中',
                text: '正在为所有租户开启ICMP协议...',
                allowOutsideClick: false,
                didOpen: () => {
                    Swal.showLoading();
                }
            });

            // 发送请求到后端
            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/tenants/enableIcmp', true);

            // 设置CSRF令牌
            const token = _getCsrfToken();
            xhr.setRequestHeader('X-CSRF-TOKEN', token);
            xhr.setRequestHeader('Content-Type', 'application/json');

            xhr.onload = function() {
                if (xhr.status === 200) {
                    try {
                        const response = JSON.parse(xhr.responseText);

                        if (response.success) {
                            Swal.fire({
                                title: '操作成功',
                                text: response.message || 'ICMP协议已成功开启',
                                icon: 'success',
                                confirmButtonColor: '#1abc9c'
                            });
                        } else {
                            Swal.fire({
                                title: '操作部分完成',
                                text: response.message || '部分租户ICMP协议开启失败',
                                icon: 'warning',
                                confirmButtonColor: '#f59e0b'
                            });
                        }
                    } catch (error) {
                        // JSON解析错误
                        Swal.fire({
                            title: '操作失败',
                            text: '处理响应时出现错误',
                            icon: 'error',
                            confirmButtonColor: '#ef4444'
                        });
                    }
                } else {
                    // 请求失败
                    Swal.fire({
                        title: '操作失败',
                        text: '启用ICMP协议请求失败，请稍后重试',
                        icon: 'error',
                        confirmButtonColor: '#ef4444'
                    });
                }
            };

            xhr.onerror = function() {
                Swal.fire({
                    title: '网络错误',
                    text: '无法连接到服务器，请检查网络连接',
                    icon: 'error',
                    confirmButtonColor: '#ef4444'
                });
            };

            // 发送请求
            xhr.send(JSON.stringify({}));
        }
    });
}*/

/*function toggleChildren(icon, parentId) {
    // 首先确保我们有正确的parentId
    // 从DOM中获取实际的parentId,而不是使用传入的参数
    const parentRow = icon.closest('tr');
    const correctParentId = parentRow.getAttribute('data-id');
    console.log('Using parent ID from DOM:', correctParentId);

    // 使用确切的parentId查找子行
    const childRows = document.querySelectorAll('tr.child-row[data-parent-id="' + correctParentId + '"]');
    console.log('Matching child rows found:', childRows.length);

    // 切换图标状态
    icon.classList.toggle('expanded');
    const isExpanded = icon.classList.contains('expanded');

    // 切换子行显示状态
    childRows.forEach(function(row) {
        if (isExpanded) {
            row.style.display = 'table-row';
            row.style.backgroundColor = 'rgba(0, 0, 0, 0.02)';
        } else {
            row.style.display = 'none';
        }
    });
}*/

/**
 * 初始化可调整大小的模态框
 */
function initResizableModal() {
    const modalContainer = document.querySelector('#bootVolumesModal .modal-container');
    const handles = document.querySelectorAll('.resize-handle');
    const defaultSize = {
        width: modalContainer.offsetWidth,
        height: modalContainer.offsetHeight
    };
    handles.forEach(handle => {
        handle.addEventListener('mousedown', initResize);
    });
    let currentHandle = null;
    let startX, startY, startWidth, startHeight;
    function initResize(e) {
        e.preventDefault();
        e.stopPropagation();
        currentHandle = e.target;
        const direction = currentHandle.getAttribute('data-direction');

        startX = e.clientX;
        startY = e.clientY;
        startWidth = modalContainer.offsetWidth;
        startHeight = modalContainer.offsetHeight;
        document.addEventListener('mousemove', resizeModal);
        document.addEventListener('mouseup', stopResize);
        modalContainer.classList.add('resizing');
    }
    function resizeModal(e) {
        if (!currentHandle) return;

        const direction = currentHandle.getAttribute('data-direction');
        let newWidth = startWidth;
        let newHeight = startHeight;
        if (direction.includes('e')) {
            newWidth = startWidth + (e.clientX - startX);
        }

        if (direction.includes('s')) {
            newHeight = startHeight + (e.clientY - startY);
        }
        newWidth = Math.max(newWidth, 300); // 最小宽度为 300px
        newHeight = Math.max(newHeight, 300); // 最小高度为 300px
        newWidth = Math.min(newWidth, window.innerWidth * 0.95); // 最大宽度为窗口宽度的 95%
        newHeight = Math.min(newHeight, window.innerHeight * 0.95); // 最大高度为窗口高度的 95%
        modalContainer.style.width = newWidth + 'px';
        modalContainer.style.height = newHeight + 'px';
        modalContainer.style.maxWidth = 'none'; // 覆盖默认的最大宽度
    }
    function stopResize() {
        currentHandle = null;
        document.removeEventListener('mousemove', resizeModal);
        document.removeEventListener('mouseup', stopResize);
        modalContainer.classList.remove('resizing');
    }
    modalContainer.querySelectorAll('.resize-handle').forEach(handle => {
        handle.addEventListener('dblclick', resetSize);
    });
    function resetSize() {
        modalContainer.style.width = '90%';
        modalContainer.style.maxWidth = '900px';
        modalContainer.style.height = '80vh';
    }
    const resetSizeBtn = document.querySelector('.reset-size-btn');
    if (resetSizeBtn) {
        resetSizeBtn.addEventListener('click', resetSize);
    }
}

/**
 * 关闭模态框
 * @param {string} modalId
 */
function closeModal(modalId) {
    var modal = document.getElementById(modalId);
    modal.style.display = 'none';
}

function toggleSpoiler(element) {
    if (element.classList.contains('is-hidden')) {
        element.classList.remove('is-hidden');
        element.classList.add('is-visible');
    }
    else {
        element.classList.remove('is-visible');
        element.classList.add('is-hidden');
    }
}

/**
 * 显示MySQL管理模态框
 */
function showMysqlManagement(tenantId) {
    const modal = document.getElementById('mysqlManagementModal');
    modal.dataset.tenantId = tenantId;
    modal.style.display = 'flex';

    loadMysqlInfo(tenantId);
}


function loadMysqlInfo(tenantId) {
    const loading = document.getElementById('mysqlLoading');
    const content = document.getElementById('mysqlContent');
    const instanceList = document.getElementById('mysqlInstanceList');

    if (loading) loading.style.display = 'flex';
    if (content) content.style.display = 'none';

    const xhr = new XMLHttpRequest();
    xhr.open('GET', '/tenants/mysql-info?tenantId=' + tenantId, true);
    const token = _getCsrfToken();
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (loading) loading.style.display = 'none';
        if (content) content.style.display = 'block';

        try {
            const response = JSON.parse(xhr.responseText);
            if (response.success && Array.isArray(response.data) && response.data.length > 0) {

                var tableHtml = '<table class="table db-list-table">' +
                    '<thead>' +
                    '<tr>' +
                    '<th>'+i18n.detail_dbName+'</th>' +
                    '<th>'+i18n.detail_dbv+'</th>' +
                    '<th>'+i18n.detail_dbs+'</th>' +
                    '<th>'+i18n.detail_dbpn+'</th>' +
                    /*'<th>内网</th>' +*/
                    '<th>'+i18n.detail_dbup+'</th>' +
                    '<th>'+i18n.detail_dbsku+'</th>' +
                    '<th>'+i18n.detail_dbsave+'(GB)</th>' +
                    /*'<th>高可用</th>' +*/
                    '<th>'+i18n.tenant_action+'</th>' +
                    '</tr>' +
                    '</thead>' +
                    '<tbody>';

                response.data.forEach(function(item, index) {
                    var haText = item.highlyAvailable === 1 ? '是' : '否';
                    var haClass = item.highlyAvailable === 1 ? 'is-home' : 'not-home';

                    tableHtml += '<tr>' +
                        '<td>' +
                        '<strong title="点击复制OCID" onclick="copyToClipboard(\'' + item.dbId + '\')" style="cursor:pointer; color:var(--accent-blue);">' +
                        (item.displayName || '未命名') +
                        '</strong>' +
                        '</td>' +
                        '<td>' + (item.dbVersion || '-') + '</td>' +
                        '<td>' + (item.dbStatus || '-') + '</td>' +
                        '<td>' +
                        '<span class="text-blue">' +
                        (item.dbPublicUrl || ''+i18n.detail_dbNo+'') + ' / ' + (item.dbPort || '3306') +
                        '</span>' +
                        '</td>' +
                        /*'<td><span class="text-secondary">' + (item.dbPrivateUrl || '-') + '</span></td>' +*/
                        '<td>' +
                        (item.dbName || ''+i18n.detail.dbNoU+'') + ' / ' +
                        '<code class="is-hidden" onclick="toggleSpoiler(this)">' + (item.dbPassword || ''+i18n.detail_dbNoP+'') + '</code>' +
                        '</td>' +
                        '<td>' + (item.shapeName || '-') + '</td>' +
                        '<td>' + (item.dataStorageSizeInGBs || '-') + '</td>' +
                        /*'<td>' +
                        '<span class="home-region-badge ' + haClass + '">' + haText + '</span>' +
                        '</td>' +*/
                        '<td>' +
                        '<div class="dropdown">' +
                        '<button class="btn btn-primary btn-icon dropdown-toggle" onclick="handleDynamicToggle(this, event)">' +
                        '<i class="fas fa-ellipsis-h"></i>' +
                        '</button>' +
                        '<div class="dropdown-panel">' +
                        '<button class="dropdown-item" title="'+i18n.detail_dbSync+'" onclick="syncSingleMysql(\'' + item.id + '\', \'' + tenantId + '\')">' +
                        '<i class="fas fa-sync"></i><span>'+i18n.detail_dbUpdate+'</span>' +
                        '</button>' +
                        '<button class="dropdown-item" title="'+i18n.detail_dbResetPass+'" onclick="resetMysqlAuth(\'' + item.id + '\', \'' + tenantId + '\')">' +
                        '<i class="fas fa-key"></i><span>'+i18n.detail_dbResetPass+'</span>' +
                        '</button>' +
                        '<button class="dropdown-item" title="'+i18n.detail_bindPublicIp+'" onclick="bindPublicIp(\'' + item.id + '\', \'' + tenantId + '\')">' +
                        '<i class="fas fa-globe"></i><span>'+i18n.detail_bindPublicIp+'</span>' +
                        '</button>' +
                        /*'<button class="dropdown-item" title="重启实例" onclick="handleMysqlAction(\'restart\', \'' + item.dbId + '\')">' +
                        '<i class="fas fa-sync-alt"></i><span>重启实例</span>' +
                        '</button>' +*/
                        '<button class="dropdown-item text-danger" title="'+i18n.detail_termDb+'" onclick="handleMysqlAction(\'delete\', \'' + item.id + '\')">' +
                        '<i class="fas fa-trash-alt"></i><span>'+i18n.detail_termDb+'</span>' +
                        '</button>' +
                        '</div>' +
                        '</div>' +
                        '</td>' +
                        '</tr>';
                });

                tableHtml += '</tbody></table>';
                instanceList.innerHTML = tableHtml;

            } else {
                instanceList.innerHTML = '<div class="text-center" style="padding:40px; color:var(--text-secondary);">'+i18n.common_noData+'</div>';
            }
        } catch (e) {
            console.error("解析实例列表异常", e);
        }
    };
    xhr.send();
}


function copyToClipboard(text) {
    navigator.clipboard.writeText(text).then(() => {
        Swal.fire({ title: i18n.detail_copy_success+' OCID', timer: 1000, showConfirmButton: false, icon: 'success' });
    });
}

function syncMysqlFromCloud() {
    const tenantId = document.getElementById('mysqlManagementModal').dataset.tenantId;

    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/sync-mysql?tenantId=' + tenantId, true);
    const token = _getCsrfToken();
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        try {
            const response = JSON.parse(xhr.responseText);
            if (response.success) {
                Swal.fire({
                    icon: 'success',
                    title: 'successful',
                    timer: 2000
                }).then(() => {
                    loadMysqlInfo(tenantId);
                });
            } else {
                console.error("同步实例列表异常", response.message);
                showError();
            }
        } catch (e) {
            showError();
        }
    };
    xhr.send();
}

function syncSingleMysql(configId, tenantId) {
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => { Swal.showLoading(); }
    });

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/sync-single-mysql?id=' + configId, true);
    const token = _getCsrfToken();
    xhr.setRequestHeader('X-CSRF-TOKEN', token);
    xhr.onload = function() {
        try {
            const response = JSON.parse(xhr.responseText);
            if (response.success) {
                Swal.fire('success', 'successful', 'success').then(() => {
                    loadMysqlInfo(tenantId);
                });
            } else {
                showError();
            }
        } catch (e) { showError();}
    };
    xhr.send();
}


function handleMysqlAction(action, id) {
    const tenantId = document.getElementById('mysqlManagementModal').dataset.tenantId;

    const actionMap = {
        'restart': { name: i18n.detail_DbReset, icon: 'info', color: 'var(--accent-blue)' },
        'stop': { name: i18n.detail_temRun, icon: 'warning', color: 'var(--accent-orange)' },
        'delete': { name: i18n.detail_tem, icon: 'error', color: 'var(--accent-red)' }
    };

    const config = actionMap[action];

    Swal.fire({
        title: i18n.common_confirm + config.name + '?',
        text: action === 'delete' ? i18n.detail_deleteAlert : i18n.detail_deleteConfirm,
        icon: config.icon,
        showCancelButton: true,
        confirmButtonColor: config.color,
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            Swal.showLoading();

            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/tenants/mysql-action', true);
            xhr.setRequestHeader('Content-Type', 'application/json');
            const token = _getCsrfToken();
            xhr.setRequestHeader('X-CSRF-TOKEN', token);

            xhr.onload = function() {
                try {
                    const response = JSON.parse(xhr.responseText);
                    if (response.success) {
                        loadMysqlInfo(tenantId);
                    } else {
                        showError();
                    }
                } catch (e) {
                    showError();
                }
            };
            xhr.send(JSON.stringify({
                tenantId: tenantId,
                id: id,
                action: action
            }));
        }
    });
}

function bindPublicIp(configId, tenantId) {
    Swal.fire({
        title: i18n.common_confirm,
        icon: 'question',
        showCancelButton: true,
        confirmButtonColor: 'var(--accent-blue)',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            Swal.fire({
                title: 'loading',
                text: i18n.detail_requestDbResource,
                allowOutsideClick: false,
                didOpen: () => { Swal.showLoading(); }
            });

            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/tenants/bind-public-ip?id=' + configId, true);
            const token = _getCsrfToken();
            xhr.setRequestHeader('X-CSRF-TOKEN', token);

            xhr.onload = function() {
                try {
                    const response = JSON.parse(xhr.responseText);
                    if (response.success) {
                        Swal.fire('success', i18n.detail_requestDbResourceSuccess, 'success').then(() => {
                            loadMysqlInfo(tenantId);
                        });
                    } else {
                        showError();
                    }
                } catch (e) {
                    showError();
                }
            };
            xhr.send();
        }
    });
}

function createMysql() {
    const tenantId = document.getElementById('mysqlManagementModal').dataset.tenantId;

    Swal.fire({
        title: i18n.detail_createDb,
        text: i18n.detail_createDbFree,
        icon: 'info',
        showCancelButton: true,
        confirmButtonColor: 'var(--accent-green, #28a745)',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            Swal.fire({
                title: 'loading',
                text: i18n.detail_mysqlLoading,
                allowOutsideClick: false,
                didOpen: () => {
                    Swal.showLoading();
                }
            });
            const params = new URLSearchParams();
            params.append('tenantId', tenantId);

            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/tenants/mysql-create', true);

            const csrfElement = document.querySelector('input[name="_csrf"]');
            if (csrfElement) {
                xhr.setRequestHeader('X-CSRF-TOKEN', csrfElement.value);
            }
            xhr.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');
            xhr.onload = function() {
                try {
                    const response = JSON.parse(xhr.responseText);
                    if (response.success || response.code === 200) {
                        Swal.fire({
                            title: i18n.detail_mysqlSend,
                            text: i18n.detail_mysqlCreating,
                            icon: 'success'
                        }).then(() => {
                            if (typeof loadMysqlInfo === 'function') {
                                loadMysqlInfo(tenantId);
                            }
                        });
                    } else {
                        Swal.fire('error', response.message || i18n.detail_mysqlCreatLimit, 'error');
                    }
                } catch (e) {
                    console.error("解析错误:", e);
                    showError();
                }
            };

            xhr.onerror = function() {
                showError();
            };

            xhr.send(params.toString());
        }
    });
}

function resetMysqlAuth(id, tenantId) {
    Swal.fire({
        title: i18n.detail_mysqlResetPass,
        text: i18n.detail_mysqlResetPassSum,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#f39c12',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            Swal.fire({
                title: 'loading',
                allowOutsideClick: false,
                didOpen: () => { Swal.showLoading(); }
            });
            const params = new URLSearchParams();
            params.append('id', id);
            params.append('tenantId', tenantId);
            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/tenants/mysql-reset-auth', true);
            const token = _getCsrfToken();
            xhr.setRequestHeader('X-CSRF-TOKEN', token);
            xhr.setRequestHeader('Content-type', 'application/x-www-form-urlencoded');
            xhr.onload = function() {
                try {
                    const response = JSON.parse(xhr.responseText);
                    if (response.success) {
                        Swal.fire('success', 'successful', 'success').then(() => {
                            loadMysqlInfo(tenantId);
                        });
                    } else {
                        showError();
                    }
                } catch (e) {
                    showError();
                }
            };
            xhr.send(params.toString());
        }
    });
}

function showError(){
    Swal.fire({
        title: 'error',
        text: i18n.common_network_error,
        icon: 'error',
        confirmButtonColor: '#ff6b6b'
    });
}
