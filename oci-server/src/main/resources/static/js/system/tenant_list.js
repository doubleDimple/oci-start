let csrfToken, csrfHeaderName;

let currentUserPage = 1;
const userItemsPerPage = 5;
let allUsers = [];

let auditNextPageToken = null;
let auditTenantId = null;
let auditDays = 3; // 默认查询最近3天

let auditRowIndex = 0; // 当前序号计数

const i18n = window.I18N;

// 监听云厂商变更事件
document.addEventListener('cloudProviderChanged', function(event) {
    // 获取选择的云厂商类型
    const cloudType = event.detail.type;

    // 获取当前URL参数
    const urlParams = new URLSearchParams(window.location.search);

    // 设置cloudType参数
    urlParams.set('cloudType', cloudType);

    // 构建新的URL，保留其他参数
    const newUrl = '/tenants/list?' + urlParams.toString();

    // 跳转到新URL，实现页面刷新并传递cloudType参数
    window.location.href = newUrl;
});


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

    // 检查是否是账号类型字段
    if (element.classList.contains('account-type')) {
        if (isTruncated) {
            // 显示原始代码
            element.textContent = fullText;
            element.setAttribute('data-truncated', 'false');
            // 移除所有颜色类
            element.classList.remove('account-type-trial', 'account-type-upgrade', 'account-type-free');
        } else {
            // 显示中文名称并添加相应颜色
            const typeInfo = getAccountTypeInfo(fullText);
            element.textContent = typeInfo.text;
            if (typeInfo.color) element.classList.add(typeInfo.color);

            element.textContent = typeInfo.text;
            element.setAttribute('data-truncated', 'true');
            // 添加颜色类
            if (typeInfo.color) {
                element.classList.add(typeInfo.color);
            }
        }
    } else {
        // 原有的文本截断逻辑
        if (isTruncated) {
            element.textContent = fullText.length > 15 ? fullText.substring(0, 15) + '...' : fullText;
            element.setAttribute('data-truncated', 'false');
        } else {
            element.textContent = fullText;
            element.setAttribute('data-truncated', 'true');
        }
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
        statusText.textContent = '由于网络问题，请稍后去OCI控制台查看同步结果';

        setTimeout(() => {
            modal.style.display = 'none';
        }, 3000);
    }

    const xhr = new XMLHttpRequest();
    xhr.open('GET', '/tenants/syncOci?tenantId=' + tenantId, true);

    // 设置CSRF令牌
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        clearInterval(progressUpdater);
        clearTimeout(timeoutHandler);

        try {
            const data = JSON.parse(xhr.responseText);

            // 只有明确返回 error 状态时才显示错误
            if (data.status === 'error') {
                statusMessage.className = 'status-message error';
                statusText.textContent = (data.message || 'error') + '，please retry';

                setTimeout(() => {
                    modal.style.display = 'none';
                }, 3000);
            }
            // 明确返回 success 状态时显示成功
            else if (data.status === 'success') {
                progressBar.style.width = '100%';
                statusMessage.className = 'status-message success';
                statusText.textContent = 'successful';

                setTimeout(() => {
                    modal.style.display = 'none';
                    location.reload();
                }, 2000);
            }
            // 其他所有情况都按超时处理
            else {
                handleTimeout();
            }
        } catch (error) {
            // 解析错误时也按超时处理
            handleTimeout();
        }
    };

    xhr.onerror = function() {
        clearInterval(progressUpdater);
        clearTimeout(timeoutHandler);
        // 网络错误时也按超时处理
        handleTimeout();
    };

    xhr.send();
}

document.addEventListener('DOMContentLoaded', () => {
    const urlParams = new URLSearchParams(window.location.search);
    const cloudType = urlParams.get('cloudType');

    if (!cloudType) {
        const savedProvider = localStorage.getItem('selectedCloudProvider');
        let defaultType = '1';

        if (savedProvider) {
            try {
                const provider = JSON.parse(savedProvider);
                if (provider.type) {
                    defaultType = provider.type.toString();
                }
            } catch (error) {
            }
        }

        urlParams.set('cloudType', defaultType);
        window.location.href = '/tenants/list?' + urlParams.toString();
    }
    const searchForm = document.getElementById('searchForm');
    if (searchForm) {
        // 检查表单中是否已有cloudType的hidden输入
        let cloudTypeInput = searchForm.querySelector('input[name="cloudType"]');

        // 如果没有，创建一个
        if (!cloudTypeInput) {
            cloudTypeInput = document.createElement('input');
            cloudTypeInput.type = 'hidden';
            cloudTypeInput.name = 'cloudType';
            searchForm.appendChild(cloudTypeInput);
        }

        // 设置值
        cloudTypeInput.value = cloudType;
    }


    const enableTrafficStats = document.getElementById('enableTrafficStats');
    if (enableTrafficStats) {
        enableTrafficStats.addEventListener('change', function() {
            toggleAlertSettings(this.checked);
        });
    }

    const protocolSelect = document.getElementById('ruleProtocol');
    const portsInput = document.getElementById('rulePorts');
    const portsLabel = document.querySelector('label[for="rulePorts"]');

    var childRows = document.querySelectorAll('.child-row');
    childRows.forEach(function(row) {
        row.style.display = 'none';
    });

    // 重置所有展开图标
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
                portsLabel.innerHTML = ''+i18n.tenant_portRange+' <span style="color: #666;">'+i18n.tenant_icmpNoPort+'</span>';
            } else {
                portsInput.placeholder = '80,443 or 80-443';
                portsInput.disabled = false;
                portsLabel.innerHTML = ''+i18n.tenant_portRange+' <span style="color: red;">*</span>';
            }
        });

        // 初始检查
        if (protocolSelect.value === 'icmp') {
            portsInput.placeholder = i18n.tenant_icmpNoPort;
            portsInput.disabled = true;
            portsInput.value = ''; // 清空端口值
            portsLabel.innerHTML = ''+i18n.tenant_portRange+' <span style="color: #666;">'+i18n.tenant_icmpNoPort+'</span>';
        }
    }


    // 为所有同步表单添加提交事件监听
    const syncForms = document.querySelectorAll('form[action="/tenants/syncOci"]');
    syncForms.forEach(form => {
        form.addEventListener('submit', (e) => {
            e.preventDefault(); // 阻止表单默认提交
            const tenantId = form.querySelector('input[name="tenantId"]').value; // 获取实际的tenantId
            handleSync(tenantId); // 只传递tenantId值
        });
    });

    // 点击模态框外部关闭
    const modal = document.getElementById('syncModal');
    modal.addEventListener('click', (e) => {
        if (e.target === modal) {
            modal.style.display = 'none';
        }
    });

    // 点击账号详情模态框外部关闭
    const accountDetailModal = document.getElementById('accountDetailModal');
    if (accountDetailModal) {
        accountDetailModal.addEventListener('click', function(e) {
            if (e.target === accountDetailModal) {
                closeAccountDetailModal();
            }
        });
    }

    const tabs = document.querySelectorAll('.security-rules-tab');
    tabs.forEach(tab => {
        tab.addEventListener('click', function() {
            // 防止重复点击
            if (this.classList.contains('active')) {
                return;
            }

            tabs.forEach(t => t.classList.remove('active'));
            this.classList.add('active');

            //const modal = document.getElementById('securityRulesModal');
            //const tenantId = modal.dataset.tenantId;
            //loadSecurityRules(tenantId);
        });
    });

    // 初始化账号类型显示
    const accountTypeElements = document.querySelectorAll('.account-type');
    accountTypeElements.forEach(element => {
        const fullText = element.getAttribute('data-fulltext');
        const typeInfo = accountTypeMap[fullText] || { text: fullText, color: '' };
        element.textContent = typeInfo.text;
        element.setAttribute('data-truncated', 'true');
        if (typeInfo.color) {
            element.classList.add(typeInfo.color);
        }
    });

});

// 状态检查处理
function handleCheckStatus(tenantId) {
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
    statusText.textContent = "loading";

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
        statusText.textContent = i18n.tenant_checkFail;

        setTimeout(function() {
            modal.style.display = 'none';
            location.reload();
        }, 3000);
    }

    // 发送请求
    xhr.send();
}

// 删除处理
function handleDelete(tenantId) {
    Swal.fire({
        title: i18n.common_confirm,
        icon: 'warning',
        showCancelButton: true,              // 显示取消按钮
        confirmButtonColor: '#d33',         // 确认按钮颜色
        cancelButtonColor: '#3085d6',       // 取消按钮颜色
        confirmButtonText: i18n.common_confirm,           // 确认按钮文本
        cancelButtonText: i18n.common_cancel           // 取消按钮文本
    }).then((result) => {
        if (result.isConfirmed) {
            // 显示加载状态
            Swal.fire({
                title: 'loading',
                icon: 'info',
                allowOutsideClick: false,
                allowEscapeKey: false,
                showConfirmButton: false,
                didOpen: () => {
                    Swal.showLoading();
                }
            });

            // 如果用户点击了 "删除"，执行删除逻辑
            const xhr = new XMLHttpRequest();
            xhr.open('GET', '/tenants/deleteApi?tenantId=' + tenantId, true);

            // 设置CSRF令牌
            const token = document.querySelector('input[name="_csrf"]').value;
            xhr.setRequestHeader('X-CSRF-TOKEN', token);

            // 设置超时时间（30秒）
            xhr.timeout = 30000;

            xhr.onload = function () {
                // 适配ResponseEntity的JSON响应
                if (xhr.status >= 200 && xhr.status < 300) {
                    try {
                        const response = JSON.parse(xhr.responseText);
                        if (response.success) {
                            Swal.fire({
                                icon: 'success',
                                title: 'successful',
                                confirmButtonText: i18n.memo_btn_close
                            }).then(() => {
                                location.reload();
                            });
                        } else {
                            showError();
                        }
                    } catch (e) {
                        // 如果不是JSON格式，按原来的逻辑处理
                        Swal.fire({
                            icon: 'success',
                            title: 'successful',
                            confirmButtonText: i18n.memo_btn_close
                        }).then(() => {
                            location.reload();
                        });
                    }
                } else {
                    showError();
                }
            };

            xhr.onerror = function () {
                showError();
            };

            // 添加超时处理
            xhr.ontimeout = function () {
                showError();
            };

            xhr.send();
        }
    });
}


/*function handleUpdateAccountDetail(tenantId) {
    Swal.fire({
        title: i18n.common_confirm,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#d33',
        cancelButtonColor: '#3085d6',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            Swal.fire({
                title: 'loading',
                icon: 'info',
                allowOutsideClick: false,  // 不允许点击外部关闭
                allowEscapeKey: false,     // 不允许ESC键关闭
                showConfirmButton: false,  // 不显示确认按钮
                showCancelButton: false,   // 不显示取消按钮
                didOpen: () => {
                    Swal.showLoading();    // 显示加载动画
                }
            });

            const xhr = new XMLHttpRequest();
            xhr.open('GET', '/tenants/updateAccountDetail?tenantId=' + tenantId, true);

            // 设置CSRF令牌
            const token = document.querySelector('input[name="_csrf"]').value;
            xhr.setRequestHeader('X-CSRF-TOKEN', token);

            // 设置超时时间（可选，比如30秒）
            xhr.timeout = 60000;

            xhr.onload = function () {
                if (xhr.status === 200) {
                    // 更新成功
                    Swal.fire({
                        icon: 'success',
                        title: 'successful',
                        confirmButtonText: i18n.memo_btn_close,
                        confirmButtonColor: '#1abc9c'
                    }).then(() => {
                        location.reload();
                    });
                } else {
                    showError();
                }
            };

            xhr.onerror = function () {
                showError();
            };

            xhr.ontimeout = function () {
                showError();
            };

            xhr.send();
        }
    });
}*/

function handleUpdateAccountDetail(tenantId) {
    Swal.fire({
        title: i18n.common_confirm,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#d33',
        cancelButtonColor: '#3085d6',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            const token = document.querySelector('input[name="_csrf"]').value;
            Swal.fire({
                title: 'logs',
                html: '<div id="sse-messages" style="text-align: left; height: 300px; overflow-y: auto; font-size: 14px; font-family: monospace; color: #333; padding: 12px; background: #f4f5f7; border: 1px solid #e1e4e8; border-radius: 4px;">[System] connecting...<br></div>',
                width: '600px',
                allowOutsideClick: false,
                allowEscapeKey: false,
                showConfirmButton: false
            });
            const sseUrl = `/tenants/updateTenant?tenantId=${tenantId}&_csrf=${token}`;
            const eventSource = new EventSource(sseUrl);
            eventSource.addEventListener('progress', function (event) {
                const messagesDiv = document.getElementById('sse-messages');
                if (messagesDiv) {
                    messagesDiv.innerHTML += `<span>👉 ${event.data}</span><br>`;
                    messagesDiv.scrollTop = messagesDiv.scrollHeight; // 自动滚动到最底部
                }
            });

            eventSource.addEventListener('success', function (event) {
                eventSource.close();
                Swal.fire({
                    icon: 'success',
                    title: 'successful',
                    confirmButtonText: i18n.memo_btn_close,
                    confirmButtonColor: '#1abc9c'
                }).then(() => {
                    location.reload();
                });
            });

            eventSource.addEventListener('error', function (event) {
                eventSource.close();
                Swal.fire({
                    icon: 'error',
                    confirmButtonText: i18n.memo_btn_close
                });
            });
            eventSource.onerror = function(err) {
                if (eventSource.readyState === EventSource.CLOSED) {
                    return;
                }
                eventSource.close();
                Swal.fire({
                    icon: 'error',
                    confirmButtonText: i18n.memo_btn_close
                });
            };
        }
    });
}

// 初始化
document.addEventListener('DOMContentLoaded', function() {
    csrfToken = document.querySelector('meta[name="_csrf"]').content;
    csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;
    const enableTrafficStats = document.getElementById('enableTrafficStats');
    if (enableTrafficStats) {
        enableTrafficStats.addEventListener('change', function() {
            toggleAlertSettings(this.checked);
        });
    }

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
});
// 添加一个变量来存储当前正在操作的租户ID
let currentTenantId = null;


// 添加用户管理相关函数
function showUserManagement(tenantId) {
    const modal = document.getElementById('userManagementModal');
    modal.dataset.tenantId = tenantId;
    modal.style.display = 'flex';
    loadUserList(tenantId);
}

function loadUserList(tenantId) {
    const tbody = document.getElementById('userListTableBody');
    tbody.innerHTML = '<tr><td colspan="6" class="text-center"><span class="loading-spinner"></span> '+i18n.common_loading+'</td></tr>';

    // 重置分页
    currentUserPage = 1;

    const xhr = new XMLHttpRequest();
    xhr.open('GET', '/tenants/oracle-users?tenantId=' + tenantId, true);
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const users = JSON.parse(xhr.responseText);
                updateUserTable(users);
            } catch (error) {
                tbody.innerHTML = '<tr><td colspan="6" class="text-center" style="color: var(--accent-red);">加载用户列表失败</td></tr>';
            }
        } else {
            tbody.innerHTML = '<tr><td colspan="6" class="text-center" style="color: var(--accent-red);">加载用户列表失败</td></tr>';
        }
    };

    xhr.onerror = function() {
        tbody.innerHTML = '<tr><td colspan="6" class="text-center" style="color: var(--accent-red);">加载用户列表失败</td></tr>';
    };

    xhr.send();
}

function updateUserTable(users) {
    const tbody = document.getElementById('userListTableBody');

    // 保存所有用户数据
    allUsers = users;

    // 计算分页信息
    const totalPages = Math.ceil(users.length / userItemsPerPage);
    const startIndex = (currentUserPage - 1) * userItemsPerPage;
    const endIndex = startIndex + userItemsPerPage;
    const currentPageUsers = users.slice(startIndex, endIndex);

    // 清空表格
    tbody.innerHTML = '';

    if (users.length === 0) {
        tbody.innerHTML = '<tr><td colspan="6" class="text-center" style="color: var(--text-secondary);">暂无用户数据</td></tr>';
        updateUserPaginationControls(0, 0);
        return;
    }

    currentPageUsers.forEach(user => {
        const tr = document.createElement('tr');

        // 处理用户名:如果包含斜杠,只取斜杠后面的部分
        let displayUsername = user.username || '';
        if (displayUsername.includes('/')) {
            displayUsername = displayUsername.split('/').pop();
        }

        // 设置状态样式：Active 为绿色，其余为红色
        const userStatusClass = user.lifecycleState === 'Active' ? 'status-active' : 'status-locked';

        tr.innerHTML =
            '<td>' + user.domain + '</td>' +
            '<td>' + displayUsername + '</td>' +
            '<td>' + user.email + '</td>' +
            '<td><span class="user-status ' + userStatusClass + '">' + user.lifecycleState + '</span></td>' +
            '<td>' + user.timeCreated + '</td>' +
            '<td>' + (user.lastSuccessfulLoginTime ? user.lastSuccessfulLoginTime : '-') + '</td>' +
            '<td>' +
            '<div class="btn-group-sm">' +
            '<button class="btn btn-sm btn-warning" onclick="resetUserPassword(\'' + user.id + '\', \'' + user.username + '\')" title="'+i18n.login_reset_title+'">' +
            '<i class="fas fa-key"></i>' +
            '</button>' +
            '<button class="btn btn-sm btn-danger" onclick="deleteOciUser(\'' + user.id + '\')" title="'+i18n.tenant_deleteUser+'">' +
            '<i class="fas fa-trash"></i>' +
            '</button>' +
            '</div>' +
            '</td>';

        tbody.appendChild(tr);
    });

    // 更新分页控件
    updateUserPaginationControls(currentUserPage, totalPages);
}

function updateUserPaginationControls(current, total) {
    let paginationHtml = '';

    if (total > 1) {
        // 计算上一页和下一页
        var prevPage = current - 1;
        var nextPage = current + 1;

        // 判断按钮状态
        var prevDisabled = current <= 1;
        var nextDisabled = current >= total;

        paginationHtml =
            '<div class="user-pagination-controls" style="display: flex; justify-content: center; align-items: center; margin-top: 15px; gap: 10px; padding: 15px 0; border-top: 1px solid var(--card-border); background: var(--hover-bg);">' +
            '<button class="btn btn-primary' + (prevDisabled ? ' disabled' : '') + '" ' +
            'onclick="goToUserPage(' + prevPage + ')" ' +
            (prevDisabled ? 'disabled' : '') + '>' +
            '<i class="fas fa-chevron-left"></i> '+i18n.page_prev+'' +
            '</button>' +
            '<span style="color: var(--text-secondary); font-size: 14px;">' +
            '第 ' + current + ' 页 / 共 ' + total + ' 页 (共 ' + allUsers.length + ' 条)' +
            '</span>' +
            '<button class="btn btn-primary' + (nextDisabled ? ' disabled' : '') + '" ' +
            'onclick="goToUserPage(' + nextPage + ')" ' +
            (nextDisabled ? 'disabled' : '') + '>' +
            ''+i18n.page_next+' <i class="fas fa-chevron-right"></i>' +
            '</button>' +
            '</div>';
    }

    // 查找或创建分页容器
    let paginationContainer = document.querySelector('.user-pagination-controls');
    if (paginationContainer) {
        paginationContainer.remove();
    }

    // 在用户表格后添加分页控件
    const userTable = document.querySelector('#usersTab .table-view');
    if (userTable && paginationHtml) {
        userTable.insertAdjacentHTML('afterend', paginationHtml);
    }
}

function goToUserPage(page) {
    const totalPages = Math.ceil(allUsers.length / userItemsPerPage);

    if (page < 1 || page > totalPages) {
        return;
    }

    currentUserPage = page;
    updateUserTable(allUsers);
}


function showAddUserForm() {
    // Create form content
    const addUserForm = document.getElementById('addUserForm');

    // Show loading state
    addUserForm.innerHTML = `
        <div class="loading-container" style="display: flex; justify-content: center; padding: 20px;">
            <span class="loading-spinner"></span>
            <span class="loading-text">loading</span>
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
                '<span style="font-size: 12px;">'+i18n.tenant_addUserDefaultRegion+' <strong>DEFAULT</strong></span>' +
                '</div>' +
                '<div class="form-group">' +
                '<label>'+i18n.login_username+' <span style="color: red;">*</span></label>' +
                '<input type="text" id="newUsername" placeholder="'+i18n.login_username_placeholder+'" required>' +
                '</div>' +
                '<div class="form-group">' +
                '<label>'+i18n.email_address+' <span style="color: red;">*</span></label>' +
                '<input type="email" id="email" placeholder="'+i18n.email_address+'" required>' +
                '</div>' +
                '<div class="form-group">' +
                '<label>'+i18n.tenant_userGroup+' <span style="color: red;">*</span></label>' +
                '<select id="userGroup" class="form-control">' +
                '<option value="">'+i18n.tenant_selectUserGroup+'</option>' +
                groupOptions +
                '</select>' +
                '</div>' +
                '<div class="form-group" style="display: flex; align-items: center; margin-top: -5px;">' +
                '<input type="checkbox" id="useEmailAsUsername" style="width: auto; margin-right: 8px;">' +
                '<label for="useEmailAsUsername" style="cursor: pointer; font-size: 12px; color: var(--text-secondary);">' +
                ''+i18n.tenant_emailName+'' +
                '</label>' +
                '</div>' +
                '<div class="form-actions">' +
                '<button class="btn btn-primary" onclick="createUser()">'+i18n.common_save+'</button>' +
                '<button class="btn btn-danger" onclick="hideAddUserForm()">'+i18n.common_cancel+'</button>' +
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
                    <label>${i18n.login_username} <span style="color: red;">*</span></label>
                    <input type="text" id="newUsername" placeholder="${i18n.login_username_placeholder}" required>
                </div>
                <div class="form-group">
                    <label>${i18n.email_address} <span style="color: red;">*</span></label>
                    <input type="email" id="email" placeholder="${i18n.email_plzAddress}" required>
                </div>
                <div class="form-group" style="display: flex; align-items: center; margin-top: -5px;">
                    <input type="checkbox" id="useEmailAsUsername" style="width: auto; margin-right: 8px;">
                    <label for="useEmailAsUsername" style="cursor: pointer; font-size: 12px; color: var(--text-secondary);">
                        ${i18n.tenant_emailName}
                    </label>
                </div>
                <div class="form-actions">
                    <button class="btn btn-primary" onclick="createUser()">${i18n.common_save}</button>
                    <button class="btn btn-danger" onclick="hideAddUserForm()">${i18n.common_cancel}</button>
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
}


function hideAddUserForm() {
    document.getElementById('addUserForm').style.display = 'none';
}

function createUser() {
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
            title: 'waning',
            text: i18n.common_plzInputGlobalRequired,
            icon: 'error',
            confirmButtonColor: 'var(--accent-red)'
        });
        return;
    }

    // Validate group selection if group dropdown exists
    if (groupSelect && !groupId) {
        Swal.fire({
            title: 'waning',
            text: i18n.common_plzInputGlobalRequired,
            icon: 'error',
            confirmButtonColor: 'var(--accent-red)'
        });
        return;
    }

    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;

    // Show loading state
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/oracle-users', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function () {
        if (xhr.status === 200) {
            const response = JSON.parse(xhr.responseText);
            hideAddUserForm();

            // 新增用户时跳转到第一页
            currentUserPage = 1;
            loadUserList(tenantId);

            // Display success message with user info and password
            Swal.fire({
                title: i18n.tenant_addUserSuccess,
                html:
                    '<div style="text-align: left; margin: 20px 0;">' +
                    '<div style="margin-bottom: 15px;">' +
                    '<span style="font-weight: bold;">'+i18n.login_username+'：</span>' +
                    '<span>' + response.username + '</span>' +
                    '</div>' +
                    '<div style="margin-bottom: 15px;">' +
                    '<span style="font-weight: bold;">'+i18n.email_address+'：</span>' +
                    '<span>' + response.email + '</span>' +
                    '</div>' +
                    '<div style="margin-bottom: 15px;">' +
                    '<span style="font-weight: bold;">'+i18n.tenant_userGroup+'：</span>' +
                    '<span>' + (groupSelect ? groupSelect.options[groupSelect.selectedIndex].text : 'default') + '</span>' +
                    '</div>' +
                    '<div style="margin-bottom: 15px;">' +
                    '<span style="font-weight: bold;">'+i18n.login_password+'：</span>' +
                    '<span style="color: var(--accent-red); font-family: monospace; background: var(--hover-bg); padding: 2px 6px; border-radius: 3px;">' + response.password + '</span>' +
                    '</div>' +
                    '<div style="margin-top: 20px; padding: 10px; background-color: #fff3cd; color: #856404; border-radius: 4px; font-size: 14px;">' +
                    '<i class="fas fa-exclamation-triangle" style="margin-right: 8px;"></i>' +
                    '<strong>'+i18n.tenant_motice+'：</strong>'+i18n.tenant_passOnceDes+'' +
                    '</div>' +
                    '</div>',
                confirmButtonText: i18n.tenant_copyAndSave,
                confirmButtonColor: 'var(--accent-green)',
                showCancelButton: true,
                cancelButtonText: i18n.tenant_copyPass,
                cancelButtonColor: 'var(--accent-blue)',
            }).then((result) => {
                if (!result.isConfirmed) {
                    // If user clicked "Copy Password", copy to clipboard
                    navigator.clipboard.writeText(response.password)
                        .then(() => {
                            Swal.fire({
                                title: i18n.tenant_copyPass,
                                icon: 'success',
                                confirmButtonColor: 'var(--accent-green)',
                                timer: 2000,
                                timerProgressBar: true
                            });
                        })
                        .catch(() => {
                            console.error('copyerror')
                        });
                }
            });
        } else {
            showError();
        }
    };

    xhr.onerror = function() {
        showError();
    };

    // Send request with group ID if available
    xhr.send(JSON.stringify({
        tenantId: tenantId,
        username: username,
        email: email,
        groupId: groupId || undefined
    }));
}

function refreshUserList() {
    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;
    loadUserList(tenantId);
}

function resetUserPassword(userId, userName) {
    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;

    if (!tenantId || !userId || !userName) {
        showError();
        return;
    }

    // 处理用户名显示：如果包含斜杠，只显示后面部分
    let displayUsername = userName;
    if (displayUsername.includes('/')) {
        displayUsername = displayUsername.split('/').pop();
    }

    Swal.fire({
        title: i18n.tenant_rpc,
        icon: 'question',
        showCancelButton: true,
        confirmButtonColor: '#ff9800',
        cancelButtonColor: '#6c757d',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            Swal.fire({
                title: 'loading',
                icon: 'info',
                allowOutsideClick: false,
                allowEscapeKey: false,
                showConfirmButton: false,
                didOpen: () => {
                    Swal.showLoading();
                }
            });

            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/tenants/oracle-users/resetPassword', true);
            xhr.setRequestHeader('Content-Type', 'application/json');

            const token = document.querySelector('input[name="_csrf"]').value;
            xhr.setRequestHeader('X-CSRF-TOKEN', token);

            xhr.timeout = 30000;

            xhr.onload = function() {
                try {
                    const response = JSON.parse(xhr.responseText);

                    if (response.success === true) {
                        // 获取返回的数据
                        const data = response.data;
                        const loginUser = data.loginUser || displayUsername;
                        const tempPassword = data.temporaryPassword || '';  // 注意是 temporaryPassword，不是 temporarypassword
                        const resetTime = data.resetTime || '';

                        // 构建成功消息的HTML
                        let successHtml = '<div style="text-align: left; padding: 20px;">';

                        // 用户名行
                        successHtml += '<div style="margin-bottom: 20px;">';
                        successHtml += '<div style="font-weight: 600; color: #495057; margin-bottom: 8px; font-size: 14px;">';
                        successHtml += '<i class="fas fa-user" style="margin-right: 8px; color: #17a2b8;"></i>'+i18n.tenant_loginUser+'';
                        successHtml += '</div>';
                        successHtml += '<div style="display: flex; align-items: center; gap: 10px;">';
                        successHtml += '<input type="text" value="' + loginUser + '" id="loginUserInput" readonly ';
                        successHtml += 'style="flex: 1; padding: 10px; border: 1px solid #ced4da; border-radius: 4px; ';
                        successHtml += 'background-color: #f8f9fa; font-family: monospace; font-size: 14px;">';
                        successHtml += '<button onclick="copyToClipboard(\'loginUserInput\', this)" ';
                        successHtml += 'style="padding: 10px 16px; background-color: #17a2b8; color: white; border: none; ';
                        successHtml += 'border-radius: 4px; cursor: pointer; font-size: 13px; white-space: nowrap;">';
                        successHtml += '<i class="fas fa-copy"></i> '+i18n.tenant_cy+'';
                        successHtml += '</button>';
                        successHtml += '</div>';
                        successHtml += '</div>';

                        // 临时密码行
                        successHtml += '<div style="margin-bottom: 20px;">';
                        successHtml += '<div style="font-weight: 600; color: #495057; margin-bottom: 8px; font-size: 14px;">';
                        successHtml += '<i class="fas fa-key" style="margin-right: 8px; color: #ffc107;"></i>'+i18n.tenant_tp+'';
                        successHtml += '</div>';
                        successHtml += '<div style="display: flex; align-items: center; gap: 10px;">';
                        successHtml += '<input type="text" value="' + tempPassword + '" id="tempPasswordInput" readonly ';
                        successHtml += 'style="flex: 1; padding: 10px; border: 1px solid #ced4da; border-radius: 4px; ';
                        successHtml += 'background-color: #f8f9fa; font-family: monospace; font-size: 14px; color: #e83e8c; font-weight: bold;">';
                        successHtml += '<button onclick="copyToClipboard(\'tempPasswordInput\', this)" ';
                        successHtml += 'style="padding: 10px 16px; background-color: #28a745; color: white; border: none; ';
                        successHtml += 'border-radius: 4px; cursor: pointer; font-size: 13px; white-space: nowrap;">';
                        successHtml += '<i class="fas fa-copy"></i> '+i18n.tenant_cy+'';
                        successHtml += '</button>';
                        successHtml += '</div>';
                        successHtml += '</div>';

                        // 重置时间
                        if (resetTime) {
                            successHtml += '<div style="margin-top: 15px; padding: 10px; background-color: #e7f3ff; ';
                            successHtml += 'border-left: 3px solid #2196F3; border-radius: 4px; font-size: 13px; color: #495057;">';
                            successHtml += '<i class="fas fa-clock" style="margin-right: 8px; color: #2196F3;"></i>';
                            successHtml += ''+i18n.tenant_rt+': ' + resetTime;
                            successHtml += '</div>';
                        }

                        // 提示信息
                        successHtml += '<div style="margin-top: 20px; padding: 12px; background-color: #fff3cd; ';
                        successHtml += 'border-left: 3px solid #ffc107; border-radius: 4px; font-size: 12px; color: #856404;">';
                        successHtml += '<i class="fas fa-exclamation-triangle" style="margin-right: 8px;"></i>';
                        successHtml += '<strong>'+i18n.tenant_motice+'：</strong>'+i18n.tenant_fls+'';
                        successHtml += '</div>';

                        successHtml += '</div>';

                        Swal.fire({
                            title: '<i class="fas fa-check-circle" style="color: #28a745;"></i> '+i18n.tenant_rs+'',
                            html: successHtml,
                            icon: 'success',
                            confirmButtonColor: '#28a745',
                            confirmButtonText: i18n.tenant_kw,
                            width: '600px',
                            customClass: {
                                popup: 'password-reset-success-modal'
                            }
                        });
                    } else {
                        console.error('密码重置失败:', response)
                        showError();
                    }
                } catch (error) {
                    console.error('解析响应失败:', error);
                    showError();
                }
            };

            xhr.onerror = function() {
                showError();
            };

            xhr.ontimeout = function() {
                showError();
            };

            xhr.send(JSON.stringify({
                tenantId: tenantId,
                userId: userId,
                userName: userName
            }));
        }
    });
}

/**
 * 复制到剪贴板
 */
function copyToClipboard(inputId, button) {
    const input = document.getElementById(inputId);

    // 选择输入框的文本
    input.select();
    input.setSelectionRange(0, 99999); // 兼容移动设备

    try {
        document.execCommand('copy');

        const originalHtml = button.innerHTML;
        button.innerHTML = '<i class="fas fa-check"></i> '+i18n.tenant_copyAndSave;
        button.style.backgroundColor = '#28a745';

        setTimeout(function() {
            button.innerHTML = originalHtml;
            if (inputId === 'loginUserInput') {
                button.style.backgroundColor = '#17a2b8';
            } else {
                button.style.backgroundColor = '#28a745';
            }
        }, 2000);
        window.getSelection().removeAllRanges();

    } catch (err) {
        console.error('复制失败:', err);
    }
}

/**
 * 删除OCI用户
 */
function deleteOciUser(userId) {
    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;

    if (!tenantId || !userId) {
        console.error('无效的租户ID或用户ID');
        showError();
        return;
    }

    Swal.fire({
        title: i18n.tenant_clu,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#dc3545',
        cancelButtonColor: '#6c757d',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            // 显示处理中状态
            Swal.fire({
                title: 'loading',
                icon: 'info',
                allowOutsideClick: false,
                allowEscapeKey: false,
                showConfirmButton: false,
                didOpen: () => {
                    Swal.showLoading();
                }
            });

            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/tenants/oracle-users/deleteUser', true);
            xhr.setRequestHeader('Content-Type', 'application/json');

            const token = document.querySelector('input[name="_csrf"]').value;
            xhr.setRequestHeader('X-CSRF-TOKEN', token);

            // 设置30秒超时
            xhr.timeout = 30000;

            xhr.onload = function() {
                if (xhr.status === 200) {
                    try {
                        const response = JSON.parse(xhr.responseText);
                        if (response.success) {
                            Swal.fire({
                                title: 'success',
                                icon: 'success',
                                confirmButtonColor: '#28a745',
                                confirmButtonText: i18n.common_confirm
                            }).then(() => {
                                // 刷新用户列表
                                loadUserList(tenantId);
                            });
                        } else {
                            console.error('用户删除失败:', response)
                            showError();
                        }
                    } catch (error) {
                        console.error('解析响应失败:', error)
                        showError();
                    }
                } else {
                    console.error('用户删除失败:', xhr.status)
                    showError();
                }
            };

            xhr.onerror = function() {
                showError();
            };

            xhr.ontimeout = function() {
                showError();
            };

            xhr.send(JSON.stringify({
                tenantId: tenantId,
                userId: userId
            }));
        }
    });
}


/*function exportData() {
    fetch('/tenants/export', {
        method: 'GET',
        headers: {
            'X-CSRF-TOKEN': document.querySelector('input[name="_csrf"]').value
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

/*function exportDataByTenant(id) {
    fetch('/tenants/exportByTenant?id='+id, {
        method: 'GET',
        headers: {
            'X-CSRF-TOKEN': document.querySelector('input[name="_csrf"]').value
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

function exportData() {
    handleSecureExport('/tenants/export', 'all_tenants_data.json');
}

function exportDataByTenant(id) {
    handleSecureExport('/tenants/exportByTenant?id=' + id, `tenant_${id}_data.json`);
}


async function handleSecureExport(apiUrl, defaultFileName) {
    const csrfToken = document.querySelector('input[name="_csrf"]').value;

    try {
        const sendRes = await fetch('/tenants/verify/sendExportCode', {
            method: 'POST',
            headers: { 'X-CSRF-TOKEN': csrfToken }
        });

        if (!sendRes.ok) {
            const errorText = await sendRes.text();
            throw new Error(errorText || '验证码发送失败');
        }

        const { value: code, isConfirmed } = await Swal.fire({
            title: i18n.tenant_ec,
            text: i18n.tenant_ecs,
            input: 'text',
            inputPlaceholder: i18n.tenant_ecs2,
            inputAttributes: { maxlength: 6, autocapitalize: 'off' },
            showCancelButton: true,
            confirmButtonText: i18n.tenant_cad,
            cancelButtonText: i18n.common_cancel,
            showLoaderOnConfirm: true,
            preConfirm: async (inputCode) => {
                try {
                    const response = await fetch(apiUrl, {
                        method: 'GET',
                        headers: {
                            'X-CSRF-TOKEN': csrfToken,
                            'X-Verify-Code': inputCode
                        }
                    });

                    if (!response.ok) {
                        const errorMsg = await response.text();
                        throw new Error(errorMsg || 'error');
                    }
                    return await response.json();
                } catch (error) {
                    Swal.showValidationMessage(`error: ${error.message}`);
                }
            },
            allowOutsideClick: () => !Swal.isLoading()
        });

        if (isConfirmed && code) {
            const blob = new Blob([JSON.stringify(code, null, 2)], { type: 'application/json' });
            const url = URL.createObjectURL(blob);
            const a = document.createElement('a');
            a.href = url;
            a.download = defaultFileName;
            document.body.appendChild(a);
            a.click();
            document.body.removeChild(a);
            URL.revokeObjectURL(url);

            Swal.fire({ icon: 'success', title: 'successful', timer: 1500, showConfirmButton: false });
        }

    } catch (err) {
        console.error('导出失败：', err);
        showError();
    }
}

function importData() {
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
            const csrfToken = document.querySelector('input[name="_csrf"]').value;
            xhr.setRequestHeader('Content-Type', 'application/json');
            xhr.setRequestHeader('X-CSRF-TOKEN', csrfToken);

            // 定义响应处理
            xhr.onload = function () {
                if (xhr.status === 200) {
                    Swal.fire({
                        icon: 'success',
                        title: 'successful',
                        confirmButtonText: i18n.tenant_rp
                    }).then(() => {
                        location.reload();
                    });
                } else {
                    console.error('导入失败:', xhr.status, xhr.statusText)
                    showError();
                }
            };

            xhr.onerror = function () {
                console.error('导入请求失败')
                showError();
            };

            // 发送 JSON 数据
            xhr.send(JSON.stringify(jsonData));
        };

        reader.readAsText(file);
    };

    input.click();
}

function startAccountCheck() {
    Swal.fire({
        title: i18n.tenant_cg,
        width: '760px',
        html: `
            <div id="progressLog" style="
                height: 320px;
                overflow-y: auto;
                text-align: left;
                padding: 12px;
                border: 1px solid var(--card-border, #ccc);
                background: var(--surface-2, #f9f9f9);
                color: var(--text-primary, #333);
                font-size: 13px;
                font-family: monospace;
                border-radius: 6px;">
            </div>
            <div style="margin-top: 15px; width: 100%; background: var(--surface-2, #eee); border-radius: 10px; overflow: hidden; height: 18px;">
                <div id="animatedBar" style="
                    width: 0%;
                    height: 100%;
                    background: linear-gradient(90deg, #2196F3, #4CAF50);
                    background-size: 200% 100%;
                    animation: slide 1.5s linear infinite;
                    transition: width 0.4s ease;">
                </div>
            </div>
            <div id="progressText" style="text-align:center;margin-top:8px;font-size:14px;">${i18n.tenant_rcg}</div>
            <style>
                @keyframes slide {
                    0% { background-position: 0 0; }
                    100% { background-position: -200% 0; }
                }
            </style>
        `,
        allowOutsideClick: false,
        showConfirmButton: false,
        didOpen: () => {
            const logDiv = document.getElementById('progressLog');
            const bar = document.getElementById('animatedBar');
            const progressText = document.getElementById('progressText');

            const eventSource = new EventSource('/tenants/checkAccountsStream');
            let total = 0;
            let processed = 0;

            eventSource.addEventListener('start', e => {
                try {
                    const data = JSON.parse(e.data);
                    total = data.total || 0;
                    logDiv.innerHTML += `<div>${data.message}</div>`;
                    progressText.innerText = data.message;
                } catch {
                    logDiv.innerHTML += `<div>${e.data}</div>`;
                }
                logDiv.scrollTop = logDiv.scrollHeight;
            });

            eventSource.addEventListener('progress', e => {
                processed++;
                logDiv.innerHTML += `<div>${e.data}</div>`;
                logDiv.scrollTop = logDiv.scrollHeight;

                if (total > 0) {
                    const percent = Math.min(100, Math.floor((processed / total) * 100));
                    bar.style.width = percent + "%";
                    progressText.innerText = i18n.tenant_rcgh+`：${percent}% (${processed}/${total})`;
                }
            });

            eventSource.addEventListener('complete', e => {
                eventSource.close();
                const result = JSON.parse(e.data);
                bar.style.width = "100%";
                progressText.innerText = i18n.tenant_rcghs+` ${result.totalAccounts} `+i18n.tenant_nac;
                showAccountCheckResult(result);
            });

            eventSource.addEventListener('error', e => {
                eventSource.close();
                showError();
            });
        }
    });
}

function showAccountCheckResult(result) {
    const canvasContainer = document.createElement('div');
    canvasContainer.style.width = '100%';
    canvasContainer.style.height = '300px';
    const canvas = document.createElement('canvas');
    canvasContainer.appendChild(canvas);

    Swal.fire({
        title: i18n.tenant_cs,
        width: '600px',
        html: '<div style="width: 100%; text-align: center;">'+i18n.tenant_ada+'</div>',
        confirmButtonText: i18n.memo_btn_close,
        didOpen: () => {
            Swal.getHtmlContainer().appendChild(canvasContainer);

            new Chart(canvas, {
                type: 'doughnut',
                data: {
                    labels: [i18n.tenant_accountTotal, i18n.tenant_activeAccountTotal, i18n.tenant_failAccountTotal],
                    datasets: [{
                        data: [result.totalAccounts, result.activeAccounts, result.inactiveAccounts],
                        backgroundColor: ['#4CAF50', '#2196F3', '#F44336'],
                        borderWidth: 2,
                        borderColor: 'transparent',
                        hoverOffset: 6
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    cutout: '60%',
                    plugins: {
                        legend: { display: true, position: 'bottom' },
                        tooltip: { callbacks: { label: ctx => `${ctx.label}: ${ctx.raw} `+i18n.tenant_nac } }
                    }
                }
            });
        }
    });
}










function closeAccountCheckModal() {
    const modal = document.getElementById('accountCheckModal');
    modal.style.display = 'none';
}


/**
 * 显示引导卷管理的模态框
 * @param {string} tenantId
 */
function showBootVolumeManagement(tenantId) {
    var modal = document.getElementById("bootVolumesModal");
    modal.style.display = "flex";

    var modalTitle = document.querySelector('#bootVolumesModal .modal-header #modalTitle');
    modalTitle.textContent = 'volume -  ID: ' + tenantId;

    var loadingIndicator = document.getElementById('bootVolumesLoading');
    loadingIndicator.style.display = 'block';

    var tableView = document.querySelector('#bootVolumesModal .table-responsive');
    tableView.style.display = 'none';

    // 获取CSRF token
    const token = document.querySelector('input[name="_csrf"]').value;

    var requestUrl = '/tenants/boot-volumes?tenantId=' + encodeURIComponent(tenantId);
    fetch(requestUrl, {
        headers: {
            'X-CSRF-TOKEN': token  // 添加CSRF token到请求头
        }
    })
        .then(function(response) {
            if (!response.ok) {
                throw new Error('error');
            }
            return response.json();
        })
        .then(function(data) {
            loadingIndicator.style.display = 'none';
            tableView.style.display = 'block';

            var tableBody = document.getElementById('bootVolumesTable');
            tableBody.innerHTML = '';

            data.forEach(function(volume) {
                var row = document.createElement('tr');
                row.innerHTML =
                    '<td class="instace-name">' + volume.instanceName + '</td>' +
                    '<td class="volume-name">' + volume.displayName + '</td>' +
                    '<td>' + volume.sizeInGBs + '</td>' +
                    '<td class="volume-vpus">' + volume.vpusPerGB + '</td>' +
                    '<td>' +
                    '<button class="btn btn-primary edit-btn" data-id="' + volume.id + '">' +
                    '<i class="fas fa-edit"></i> '+i18n.sys_saveUpdate+'' +
                    '</button>' +
                    '</td>';
                tableBody.appendChild(row);
            });

            var editButtons = document.querySelectorAll('.edit-btn');
            editButtons.forEach(function(button) {
                button.addEventListener('click', function() {
                    var volumeId = this.getAttribute('data-id');
                    var row = this.closest('tr');
                    var nameCell = row.querySelector('.volume-name');
                    var vpusCell = row.querySelector('.volume-vpus');

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
                                    title: 'warning',
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
                                    } else {console.error('更新失败: ' + data.message);
                                       showError();
                                    }
                                })
                                .catch(error => {
                                    console.error('更新请求失败: ' + error);
                                    showError();
                                });
                        }
                    });
                });
            });
        })
        .catch(function(error) {
            loadingIndicator.style.display = 'none';
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

function fetchGroups(tenantId) {
    return new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        xhr.open('POST', '/tenants/groups', true);
        xhr.setRequestHeader('Content-Type', 'application/json');

        // Get CSRF token
        const token = document.querySelector('input[name="_csrf"]').value;
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


document.addEventListener('DOMContentLoaded', function() {
    // 搜索框输入监听，显示/隐藏清除按钮
    const searchInput = document.getElementById('searchKeyword');
    const clearSearchBtn = document.getElementById('clearSearch');
    if (searchInput && clearSearchBtn) {
        searchInput.addEventListener('input', function() {
            if (this.value.trim() !== '') {
                clearSearchBtn.style.display = 'inline-flex';
            } else {
                clearSearchBtn.style.display = 'none';
            }
        });
    }

    // Intercept search form to use AJAX
    var searchForm = document.getElementById('searchForm');
    if (searchForm) {
        searchForm.addEventListener('submit', function(e) {
            e.preventDefault();
            var kw = document.getElementById('searchKeyword').value.trim();
            if (typeof _tlCurrentKeyword !== 'undefined') _tlCurrentKeyword = kw;
            var clearBtn = document.getElementById('clearSearch');
            if (clearBtn) clearBtn.style.display = kw ? 'inline-flex' : 'none';
            if (typeof tlLoadPage === 'function') {
                tlLoadPage(0, (typeof _tlCurrentSize !== 'undefined' ? _tlCurrentSize : 10), kw, (typeof _tlCurrentCloudType !== 'undefined' ? _tlCurrentCloudType : 1));
            }
        });
    }
    if (clearSearchBtn) {
        clearSearchBtn.addEventListener('click', function() {
            document.getElementById('searchKeyword').value = '';
            if (typeof _tlCurrentKeyword !== 'undefined') _tlCurrentKeyword = '';
            this.style.display = 'none';
            if (typeof tlLoadPage === 'function') {
                tlLoadPage(0, (typeof _tlCurrentSize !== 'undefined' ? _tlCurrentSize : 10), '', (typeof _tlCurrentCloudType !== 'undefined' ? _tlCurrentCloudType : 1));
            }
        });
    }

    // 高亮搜索匹配内容
    const highlightMatches = function() {
        const keyword = searchInput ? searchInput.value.trim() : '';
        if (!keyword) return;
        const textElements = document.querySelectorAll('.truncate');
        textElements.forEach(element => {
            const originalText = element.getAttribute('data-fulltext');
            if (!originalText) return;
            const regex = new RegExp(keyword, 'gi');
            if (originalText.match(regex)) {
                const parent = element.closest('tr');
                if (parent) {
                    parent.classList.add('highlighted-row');
                }
                if (element.getAttribute('data-truncated') === 'true') {
                    const highlightedText = originalText.replace(
                        regex,
                        match => `<span class="highlight-match">`+ match +`</span>`
                    );
                    element.innerHTML = highlightedText;
                }
            }
        });
    };

    setTimeout(highlightMatches, 500);

    document.addEventListener('click', function(e) {
        if (e.target.classList.contains('truncate')) {
            setTimeout(highlightMatches, 50);
        }
    });

    const enableTenantPasswordExpiry = document.getElementById('enableTenantPasswordExpiry');
    if (enableTenantPasswordExpiry) {
        enableTenantPasswordExpiry.addEventListener('change', function() {
            const expiryDaysSection = document.getElementById('tenantExpiryDaysSection');
            if (this.checked) {
                expiryDaysSection.style.display = 'block';
            } else {
                expiryDaysSection.style.display = 'none';
            }
        });
    }

    const tenantPasswordPolicyModal = document.getElementById('tenantPasswordPolicyModal');
    if (tenantPasswordPolicyModal) {
        tenantPasswordPolicyModal.addEventListener('click', function(e) {
            if (e.target === tenantPasswordPolicyModal) {
                closeTenantPasswordPolicyModal();
            }
        });
    }
});

const accountTypeMap = {
    'TRIAL_PAID_ACCOUNT': {
        text: i18n.tenant_triala,
        color: 'account-type-trial-paid-account'
    },
    'UPGRADE_ACCOUNT': {
        text: i18n.tenant_pa,
        color: 'account-type-upgrade-account'
    },
    'FREE_ACCOUNT': {
        text: i18n.tenant_fat,
        color: 'account-type-free-account'
    }
};

function resetMfa() {
    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;
    Swal.fire({
        title: i18n.tenant_crm,
        text: i18n.tenant_crrms,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#f59e0b',
        cancelButtonColor: '#6b7280',
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
            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/tenants/resetAccountFactor', true);
            xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
            const token = document.querySelector('input[name="_csrf"]').value;
            xhr.setRequestHeader('X-CSRF-TOKEN', token);
            xhr.onload = function() {
                if (xhr.status === 200) {
                    try {
                        const response = JSON.parse(xhr.responseText);
                        if (response.success) {
                            Swal.fire({
                                title: 'success',
                                text: 'successful',
                                icon: 'success',
                                confirmButtonColor: '#1abc9c'
                            });
                        } else {
                            console.error('重置MFA失败：', response.message);
                            showError();
                        }
                    } catch (error) {
                        showError();
                    }
                } else {
                    showError();
                }
            };

            xhr.onerror = function() {
                showError();
            };
            xhr.send('tenantId=' + tenantId);
        }
    });
}

function showTrafficAlert(tenantId) {
    const modal = document.getElementById('trafficAlertModal');
    modal.dataset.tenantId = tenantId;

    const enableTrafficStats = document.getElementById('enableTrafficStats');
    const alertThreshold = document.getElementById('alertThreshold');
    const autoShutdownEl = document.getElementById('autoShutdown');
    enableTrafficStats.checked = false;
    alertThreshold.value = '';
    autoShutdownEl.checked = false;
    toggleAlertSettings(false);

    // 加载期间禁用保存按钮，避免用户在 XHR 完成前点击保存导致空值覆盖已有配置
    const saveBtn = modal.querySelector('button.btn-success');
    let savedLabel = '';
    if (saveBtn) {
        savedLabel = saveBtn.textContent;
        saveBtn.disabled = true;
        saveBtn.dataset.loading = '1';
    }
    modal.style.display = 'flex';

    const restoreSaveBtn = function() {
        if (saveBtn) {
            saveBtn.disabled = false;
            saveBtn.textContent = savedLabel;
            delete saveBtn.dataset.loading;
        }
    };

    const xhr = new XMLHttpRequest();
    xhr.open('GET', `/tenants/traffic-alert/`+tenantId, true);

    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        try {
            const body = xhr.responseText ? xhr.responseText.trim() : '';
            if (xhr.status === 200 && body && body !== 'null') {
                const config = JSON.parse(body);
                if (config && typeof config === 'object') {
                    enableTrafficStats.checked = config.statisticsEnabled === true;
                    // 显式区分 null/undefined 与 0，避免 `0 || ''` 把已有阈值显示成空
                    alertThreshold.value = (config.threshold !== null && config.threshold !== undefined)
                        ? config.threshold
                        : '';
                    autoShutdownEl.checked = config.autoShutdown === true;
                    toggleAlertSettings(enableTrafficStats.checked);
                }
            }
        } catch (error) {
            console.error('Failed to parse traffic alert config:', error);
        } finally {
            restoreSaveBtn();
        }
    };

    xhr.onerror = function() {
        restoreSaveBtn();
    };

    xhr.send();
}

function toggleAlertSettings(show) {
    const alertSettingsSection = document.getElementById('alertSettingsSection');
    if (alertSettingsSection) {
        alertSettingsSection.style.display = show ? 'block' : 'none';
    }
}

function closeTrafficAlertModal() {
    const modal = document.getElementById('trafficAlertModal');
    modal.style.display = 'none';
}

function saveTrafficAlert() {
    const modal = document.getElementById('trafficAlertModal');
    const tenantId = modal.dataset.tenantId;
    const statisticsEnabled = document.getElementById('enableTrafficStats').checked;
    const threshold = document.getElementById('alertThreshold').value;
    const autoShutdown = document.getElementById('autoShutdown').checked;
    const thresholdNum = parseFloat(threshold);
    // 配置必须包含有效阈值，避免把 0/空值持久化后下次打开显示为空
    if (!threshold || isNaN(thresholdNum) || thresholdNum <= 0) {
        Swal.fire({
            title: 'warning',
            text: i18n.tenant_pev,
            icon: 'error',
            confirmButtonColor: 'var(--accent-red)'
        });
        return;
    }
    const saveBtn = modal.querySelector('button.btn-success');
    if (saveBtn && saveBtn.dataset.loading === '1') {
        return;
    }
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/traffic-alert', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);
    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const response = JSON.parse(xhr.responseText);
                if (response.success) {
                    Swal.fire({
                        title: 'success',
                        text: 'successful',
                        icon: 'success',
                        confirmButtonColor: 'var(--accent-green)'
                    }).then(() => {
                        closeTrafficAlertModal();
                    });
                } else {
                    console.error('保存配置时出错：', response.message);
                   showError();
                }
            } catch (error) {
                showError();
            }
        } else {
            showError();
        }
    };

    xhr.onerror = function() {
        showError();
    };

    xhr.send(JSON.stringify({
        tenantId: tenantId,
        statisticsEnabled: statisticsEnabled,
        threshold: thresholdNum,
        autoShutdown: statisticsEnabled ? autoShutdown : false
    }));
}

function showAccountDetail(tenantId) {
    const modal = document.getElementById('accountDetailModal');
    const contentContainer = document.getElementById('accountDetailContent');

    tenantId = String(tenantId);
    // 获取租户数据
    const tenantData = tenantsData[tenantId];


    if (!tenantData) {
        console.error('未找到租户数据：', tenantId);
        showError();
        return;
    }

    if (!tenantData.registerDetail) {
        return;
    }
    populateAccountDetail(tenantData);
    modal.style.display = 'flex';
}

function populateAccountDetail(tenantData) {
    const data = tenantData.registerDetail;
    const accountType = getAccountTypeName(data.accountType) || '-';
    const planType = getPlanTypeName(data.planType) || '-';
    const accountTypeAndPlan = (accountType !== '-' && planType !== '-') ?
        accountType + ` - ` + planType :
        (accountType !== '-' ? accountType : planType);

    const addressParts = [
        data.country || '',
        data.city || '',
        data.line1 || ''
    ].filter(part => part.trim() !== '');
    const fullAddress = addressParts.length > 0 ? addressParts.join(' - ') : '-';
    document.getElementById('accountTypeAndPlan').textContent = accountTypeAndPlan;
    document.getElementById('registerTime').textContent = data.registerTime || '-';
    document.getElementById('subscriptionPlanNumber').textContent = data.subscriptionPlanNumber || '-';
    document.getElementById('emailAddress').textContent = data.emailAddress || '-';
    document.getElementById('fullAddress').textContent = fullAddress;
}

function getAccountTypeName(accountType) {
    const typeMap = {
        'PERSONAL': i18n.tenant_apn,
        'Personal': i18n.tenant_apn,
        'CORPORATE': i18n.tenant_acy,
        'Corporate': i18n.tenant_acy,
        'CORPORATE_SUBMITTED': i18n.tenant_acbs,
        'CorporateSubmitted': i18n.tenant_acbs
    };
    return typeMap[accountType?.toUpperCase()] || accountType;
}

// 获取计划类型中文名称
function getPlanTypeName(planType) {
    const typeMap = {
        'FREE_TIER': i18n.tenant_fat,
        'FREETIER': i18n.tenant_fat,
        'FREE': i18n.tenant_fat,
        'PAID': i18n.tenant_pag,
        'PAYG': i18n.tenant_pag,
        'PAY_AS_YOU_GO': i18n.tenant_pag
    };
    return typeMap[planType?.toUpperCase()] || planType;
}

function normalizeType(type) {
    if (!type) return type;
    return type.toUpperCase().replace(/[-_\s]/g, '');
}

const ACCOUNT_TYPE_MAP = {
    PERSONAL: { text: i18n.tenant_apn, color: 'account-type-free' },
    CORPORATE: { text: i18n.tenant_acy, color: 'account-type-upgrade' },
    CORPORATESUBMITTED: { text: i18n.tenant_acbs, color: 'account-type-trial' }
};

function getAccountTypeName(type) {
    const key = normalizeType(type);
    return ACCOUNT_TYPE_MAP[key]?.text || type;
}

function getAccountTypeInfo(type) {
    const key = normalizeType(type);
    return ACCOUNT_TYPE_MAP[key] || { text: type, color: '' };
}

const PLAN_TYPE_MAP = {
    FREETIER: i18n.tenant_fat,
    FREE: i18n.tenant_fat,
    PAID: i18n.tenant_pag,
    PAYG: i18n.tenant_pag,
    PAYASYOUGO: i18n.tenant_pag
};

function getPlanTypeName(type) {
    const key = normalizeType(type);
    return PLAN_TYPE_MAP[key] || type;
}

// 关闭账号详情模态框
function closeAccountDetailModal() {
    const modal = document.getElementById('accountDetailModal');
    modal.style.display = 'none';
}

let currentEditingTenantId = null;

function editCustomName(tenantId, currentName) {
    currentEditingTenantId = String(tenantId);

    console.log('编辑租户ID:', currentEditingTenantId);

    const nameInput = document.getElementById('customNameInput');
    nameInput.value = currentName || '';

    const modal = document.getElementById('editCustomNameModal');
    modal.style.display = 'flex';

    setTimeout(() => {
        nameInput.focus();
        nameInput.select();
    }, 100);
}

function saveCustomName() {
    if (!currentEditingTenantId) {
        console.error('无效的租户ID');
        return;
    }

    const nameInput = document.getElementById('customNameInput');
    const newName = nameInput.value.trim();

    console.log('保存租户ID:', currentEditingTenantId, '新名称:', newName);
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/updateCustomName', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const response = JSON.parse(xhr.responseText);
                if (response.success) {
                    updateCustomNameDisplay(currentEditingTenantId, newName);
                    closeEditCustomNameModal();
                    Swal.fire({
                        title: 'success',
                        text: 'successful',
                        icon: 'success',
                        confirmButtonColor: 'var(--accent-green)',
                        timer: 2000,
                        timerProgressBar: true
                    });
                } else {
                    console.error('保存自定义名称失败:', response.message);
                    showError();
                }
            } catch (error) {
                console.error('解析响应失败:', error);
                showError();
            }
        } else {
            console.error('请求失败，状态码:', xhr.status);
            showError();
        }
    };

    xhr.onerror = function() {
        console.error('网络请求失败');
        showError();
    };
    const requestData = {
        tenantId: currentEditingTenantId,
        defName: newName
    };

    console.log('发送的请求数据:', requestData);
    xhr.send(JSON.stringify(requestData));
}

function updateCustomNameDisplay(tenantId, newName) {
    const nameElement = document.getElementById('defName-' + tenantId);
    if (nameElement) {
        nameElement.textContent = newName || '';
        nameElement.setAttribute('data-fulltext', newName || '');

        if (!newName) {
            nameElement.style.color = 'var(--text-secondary)';
            nameElement.style.fontStyle = 'italic';
            nameElement.textContent = i18n.tenant_unset;
        } else {
            nameElement.style.color = '';
            nameElement.style.fontStyle = '';
        }
    } else {
        console.warn('未找到要更新的元素，tenantId:', tenantId);
    }
}

function closeEditCustomNameModal() {
    const modal = document.getElementById('editCustomNameModal');
    modal.style.display = 'none';
    currentEditingTenantId = null;
    document.getElementById('customNameInput').value = '';
}

function showPasswordPolicyModal() {
    const modal = document.getElementById('tenantPasswordPolicyModal');
    const userManagementModal = document.getElementById('userManagementModal');
    const tenantId = userManagementModal.dataset.tenantId;
    document.getElementById('enableTenantPasswordExpiry').checked = false;
    document.getElementById('tenantPasswordExpiryDays').value = 90;
    document.getElementById('tenantExpiryDaysSection').style.display = 'none';
    modal.style.display = 'flex';
    const loadingHtml = `
                    <div style="text-align: center; padding: 20px;">
                        <span class="loading-spinner"></span>
                        <span style="margin-left: 10px;">${i18n.tenant_lppy}</span>
                    </div>
                `;
    let policyInfoSection = document.getElementById('policyInfoSection');
    if (!policyInfoSection) {
        const infoSection = document.createElement('div');
        infoSection.id = 'policyInfoSection';
        infoSection.style.marginBottom = '20px';
        const modalContent = modal.querySelector('.modal-content');
        const formGroup = modal.querySelector('.form-group');
        modalContent.insertBefore(infoSection, formGroup);
        policyInfoSection = infoSection;
    }
    policyInfoSection.innerHTML = loadingHtml;
    loadCurrentPasswordPolicy(tenantId);
}

function loadCurrentPasswordPolicy(tenantId) {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/oracle-users/getPasspolicy', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);
    xhr.onload = function() {
        const policyInfoSection = document.getElementById('policyInfoSection');
        if (xhr.status === 200) {
            try {
                const apiResponse = JSON.parse(xhr.responseText);
                if (apiResponse.success) {
                    if (apiResponse.data && Array.isArray(apiResponse.data)) {
                        displayPasswordPolicyInfo(apiResponse.data);
                    } else {
                        policyInfoSection.innerHTML =
                            '<div style="padding: 10px; background-color: rgba(107, 114, 128, 0.1); border-radius: 4px; color: var(--text-secondary);">' +
                            '<i class="fas fa-info-circle"></i>' +
                            '<span style="margin-left: 8px;">'+i18n.tenant_nppy+'</span>' +
                            '</div>';
                    }
                } else {
                    // success = false 的情况
                    policyInfoSection.innerHTML =
                        '<div style="padding: 10px; background-color: rgba(239, 68, 68, 0.1); border-radius: 4px; color: var(--accent-red);">' +
                        '<i class="fas fa-exclamation-triangle"></i>' +
                        '<span style="margin-left: 8px;">error: ' + (apiResponse.message || 'error') + '</span>' +
                        '</div>';
                }
            } catch (error) {
                console.error('解析响应数据失败:', error);
                policyInfoSection.innerHTML =
                    '<div style="padding: 10px; background-color: rgba(239, 68, 68, 0.1); border-radius: 4px; color: var(--accent-red);">' +
                    '<i class="fas fa-exclamation-triangle"></i>' +
                    '<span style="margin-left: 8px;">error</span>' +
                    '</div>';
            }
        } else {
            policyInfoSection.innerHTML =
                '<div style="padding: 10px; background-color: rgba(239, 68, 68, 0.1); border-radius: 4px; color: var(--accent-red);">' +
                '<i class="fas fa-exclamation-triangle"></i>' +
                '<span style="margin-left: 8px;">network error (code: ' + xhr.status + ')</span>' +
                '</div>';
        }
    };

    xhr.onerror = function() {
        const policyInfoSection = document.getElementById('policyInfoSection');
        policyInfoSection.innerHTML =
            '<div style="padding: 10px; background-color: rgba(239, 68, 68, 0.1); border-radius: 4px; color: var(--accent-red);">' +
            '<i class="fas fa-exclamation-triangle"></i>' +
            '<span style="margin-left: 8px;">network error</span>' +
            '</div>';
    };

    xhr.send(JSON.stringify({
        tenantId: tenantId
    }));
}

function closeTenantPasswordPolicyModal() {
    document.getElementById('tenantPasswordPolicyModal').style.display = 'none';
}
function saveTenantPasswordPolicy() {
    const enablePasswordExpiry = document.getElementById('enableTenantPasswordExpiry').checked;
    const expiryDays = parseInt(document.getElementById('tenantPasswordExpiryDays').value) || 120;
    if (enablePasswordExpiry && (expiryDays < 1 || expiryDays > 365)) {
        Swal.fire({
            title: 'error',
            text: i18n.tenant_cds,
            icon: 'error',
            confirmButtonColor: 'var(--accent-red)'
        });
        return;
    }
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });

    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/oracle-users/password-policy', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);
    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const response = JSON.parse(xhr.responseText);
                if (response.success) {
                    Swal.fire({
                        title: 'success',
                        text: response.message,
                        icon: 'success',
                        confirmButtonColor: 'var(--accent-green)'
                    }).then(() => {
                        closeTenantPasswordPolicyModal();
                    });
                } else {
                    console.error('密码策略设置失败:', response.message);
                    showError();
                }
            } catch (error) {
                showError();
            }
        } else {
            showError();
        }
    };

    xhr.onerror = function() {
        showError();
    };

    // 发送数据
    xhr.send(JSON.stringify({
        tenantId: tenantId,
        enablePasswordExpiry: enablePasswordExpiry,
        expiryDays: enablePasswordExpiry ? expiryDays : null
    }));
}

function displayPasswordPolicyInfo(policyList) {
    const policyInfoSection = document.getElementById('policyInfoSection');

    if (!policyList || policyList.length === 0) {
        policyInfoSection.innerHTML =
            '<div style="padding: 10px; background-color: rgba(107, 114, 128, 0.1); border-radius: 4px; color: var(--text-secondary);">' +
            '<i class="fas fa-info-circle"></i>' +
            '<span style="margin-left: 8px;">'+i18n.tenant_nfppy+'</span>' +
            '</div>';
        return;
    }
    const enabledPolicies = policyList.filter(function(policy) {
        return policy.enablePasswordExpiry;
    });
    const hasEnabledPolicy = enabledPolicies.length > 0;
    let minExpiryDays = 120;
    if (hasEnabledPolicy) {
        const expiryDaysList = enabledPolicies.map(function(p) {
            return p.expiryDays || 120;
        });
        minExpiryDays = Math.min.apply(Math, expiryDaysList);
    }
    document.getElementById('enableTenantPasswordExpiry').checked = hasEnabledPolicy;
    document.getElementById('tenantPasswordExpiryDays').value = minExpiryDays;
    document.getElementById('tenantExpiryDaysSection').style.display = hasEnabledPolicy ? 'block' : 'none';
    let policyHtml =
        '<div style="margin-bottom: 20px; padding: 15px; background-color: rgba(26, 188, 156, 0.05); border-radius: 4px; border-left: 4px solid var(--accent-green);">' +
        '<div style="display: flex; align-items: center; gap: 8px; margin-bottom: 12px;">' +
        '<i class="fas fa-shield-alt" style="color: var(--accent-green);"></i>' +
        '<span style="font-weight: 500; color: var(--text-primary);">'+i18n.tenant_cppy+'</span>' +
        '</div>' +
        '<div style="display: grid; gap: 8px;">';

    policyList.forEach(function(policy, index) {
        const statusColor = policy.enablePasswordExpiry ? 'var(--accent-green)' : 'var(--text-secondary)';
        const statusIcon = policy.enablePasswordExpiry ? 'fas fa-check-circle' : 'fas fa-times-circle';
        const statusText = policy.enablePasswordExpiry ? i18n.tenant_enabled : i18n.tenant_stop;
        const expiryDays = policy.expiryDays || 0;
        const expiryText = policy.enablePasswordExpiry ? (expiryDays + i18n.tenant_expireDay) : i18n.tenant_expireDayForever;
        const policyName = policy.name || (i18n.tenant_policy + (index + 1));

        policyHtml +=
            '<div style="display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; background: var(--surface-2, #f8fafc); border-radius: 3px; border: 1px solid var(--card-border); font-size: 13px;">' +
            '<div style="display: flex; align-items: center; gap: 8px;">' +
            '<i class="' + statusIcon + '" style="color: ' + statusColor + '; width: 16px;"></i>' +
            '<span style="font-weight: 500;">' + policyName + '</span>' +
            '</div>' +
            '<div style="display: flex; align-items: center; gap: 12px; color: var(--text-secondary);">' +
            '<span style="color: ' + statusColor + ';">' + statusText + '</span>' +
            '<span>' + expiryText + '</span>' +
            '</div>' +
            '</div>';
    });

    policyHtml +=
        '</div>' +
        '</div>';

    policyInfoSection.innerHTML = policyHtml;
}

// 标签页切换
function switchUserTab(tabName) {
    // 更新标签按钮状态
    document.querySelectorAll('.user-tab').forEach(tab => {
        tab.classList.remove('active');
    });
    document.querySelector(`[data-tab="`+ tabName+`"]`).classList.add('active');

    // 更新内容区域
    document.querySelectorAll('.tab-content').forEach(content => {
        content.classList.remove('active');
        content.style.display = 'none';
    });

    const activeTab = document.getElementById(tabName + 'Tab');
    activeTab.classList.add('active');
    activeTab.style.display = 'block';

    // 根据标签页加载相应数据
    if (tabName === 'notifications') {
        loadNotificationRecipients();
    } else if (tabName === 'mfa') {
        refreshMfaStatus();
    }
}

// 加载通知收件人列表
function loadNotificationRecipients() {
    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;
    const tbody = document.getElementById('notificationRecipientsTableBody');

    tbody.innerHTML = '<tr><td colspan="4" class="text-center"><span class="loading-spinner"></span> '+i18n.common_loading+'</td></tr>';

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/notification/recipients', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const response = JSON.parse(xhr.responseText);
                if (response.success) {
                    updateNotificationRecipientsTable(response.recipients || []);
                    updateNotificationStats(response.recipients || []);
                } else {
                    tbody.innerHTML = `<tr><td colspan="4" class="text-center" style="color: var(--accent-red);">`+ response.message+`</td></tr>`;
                }
            } catch (error) {
                tbody.innerHTML = `<tr><td colspan="4" class="text-center" style="color: var(--accent-red);">加载通知收件人失败</td></tr>`;
            }
        } else {
            tbody.innerHTML = `<tr><td colspan="4" class="text-center" style="color: var(--accent-red);">加载通知收件人失败</td></tr>`;
        }
    };

    xhr.onerror = function() {
        tbody.innerHTML = `<tr><td colspan="4" class="text-center" style="color: var(--accent-red);">网络连接失败</td></tr>`;
    };

    xhr.send(JSON.stringify({ tenantId: tenantId }));
}

function updateNotificationRecipientsTable(recipients) {
    const tbody = document.getElementById('notificationRecipientsTableBody');
    tbody.innerHTML = '';

    if (recipients.length === 0) {
        tbody.innerHTML = '<tr><td colspan="4" class="text-center" style="color: var(--text-secondary);">暂无通知邮箱</td></tr>';
        return;
    }

    recipients.forEach((email, index) => {
        const tr = document.createElement('tr');
        const num = index + 1;
        tr.innerHTML = `
            <td>`+ num+`</td>
            <td>`+  email+`</td>
            <td><span class="notification-status active">${i18n.tenant_normal}</span></td>
            <td>
                <button class="btn btn-danger btn-sm" onclick="removeNotificationRecipient('`+  email+`')" title="${i18n.common_delete}">
                    <i class="fas fa-trash"></i>
                </button>
            </td>
        `;
        tbody.appendChild(tr);
    });
}

// 更新统计信息
function updateNotificationStats(recipients) {
    const totalElement = document.getElementById('totalRecipients');
    const domainStatsElement = document.getElementById('domainStats');

    totalElement.textContent = recipients.length;

    if (recipients.length > 0) {
        const domains = {};
        recipients.forEach(email => {
            if (email.includes('@')) {
                const domain = email.split('@')[1];
                domains[domain] = (domains[domain] || 0) + 1;
            }
        });
    } else {
        domainStatsElement.textContent = '';
    }
}

function showAddNotificationEmailForm() {
    document.getElementById('addNotificationEmailForm').style.display = 'block';
    document.getElementById('notificationEmail').focus();
}

function hideAddNotificationEmailForm() {
    document.getElementById('addNotificationEmailForm').style.display = 'none';
    document.getElementById('notificationEmail').value = '';
}
function addNotificationEmail() {
    const emailInput = document.getElementById('notificationEmail');
    const email = emailInput.value.trim();

    if (!email) {
        Swal.fire({
            title: 'error',
            text: i18n.common_plzInputGlobalRequired,
            icon: 'error',
            confirmButtonColor: 'var(--accent-red)'
        });
        return;
    }
    const emailPattern = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
    if (!emailPattern.test(email)) {
        Swal.fire({
            title: i18n.email_formatError,
            icon: 'error',
            confirmButtonColor: 'var(--accent-red)'
        });
        return;
    }

    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;

    // 获取当前邮箱列表
    getCurrentNotificationRecipients(tenantId, (currentEmails) => {
        if (currentEmails.includes(email.toLowerCase())) {
            console.log('邮箱已存在');
            return;
        }

        // 添加到现有列表
        const updatedEmails = [...currentEmails, email.toLowerCase()];
        updateNotificationRecipientsList(tenantId, updatedEmails, () => {
            hideAddNotificationEmailForm();
            loadNotificationRecipients();
            Swal.fire({
                title: 'success',
                text: 'successful',
                icon: 'success',
                confirmButtonColor: 'var(--accent-green)',
                timer: 2000,
                timerProgressBar: true
            });
        });
    });
}

// 删除通知收件人
function removeNotificationRecipient(emailToRemove) {
    Swal.fire({
        title: i18n.delete_title,
        icon: 'question',
        showCancelButton: true,
        confirmButtonColor: 'var(--accent-red)',
        cancelButtonColor: 'var(--accent-blue)',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            const modal = document.getElementById('userManagementModal');
            const tenantId = modal.dataset.tenantId;

            getCurrentNotificationRecipients(tenantId, (currentEmails) => {
                const updatedEmails = currentEmails.filter(email => email !== emailToRemove);

                if (updatedEmails.length === 0) {
                    Swal.fire({
                        title: 'warning',
                        text: i18n.tenant_deleteSum,
                        icon: 'warning',
                        confirmButtonColor: 'var(--accent-blue)'
                    });
                    return;
                }

                updateNotificationRecipientsList(tenantId, updatedEmails, () => {
                    loadNotificationRecipients();
                    Swal.fire({
                        title: 'success',
                        text: 'successful',
                        icon: 'success',
                        confirmButtonColor: 'var(--accent-green)',
                        timer: 2000,
                        timerProgressBar: true
                    });
                });
            });
        }
    });
}

function refreshNotificationRecipients() {
    loadNotificationRecipients();
}

function getCurrentNotificationRecipients(tenantId, callback) {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/notification/recipients', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const response = JSON.parse(xhr.responseText);
                if (response.success) {
                    callback(response.recipients || []);
                } else {
                    callback([]);
                }
            } catch (error) {
                callback([]);
            }
        } else {
            callback([]);
        }
    };

    xhr.onerror = function() {
        callback([]);
    };

    xhr.send(JSON.stringify({ tenantId: tenantId }));
}

function updateNotificationRecipientsList(tenantId, emails, callback) {
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/notification/update', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const response = JSON.parse(xhr.responseText);
                if (response.success) {
                    Swal.close();
                    callback();
                } else {
                    console.log('更新失败:', response.message);
                    showError();
                }
            } catch (error) {
                showError();
            }
        } else {
            showError();
        }
    };

    xhr.onerror = function() {
        showError();
    };

    xhr.send(JSON.stringify({ tenantId: tenantId, emails: emails }));
}

// MFA管理相关函数
function enableEmailMFA() {
    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;

    Swal.fire({
        title: i18n.tenant_confirmStartEmailMfa,
        icon: 'question',
        showCancelButton: true,
        confirmButtonColor: 'var(--accent-green)',
        cancelButtonColor: 'var(--text-secondary)',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            performMfaOperation(tenantId, true);
        }
    });
}

function disableEmailMFA() {
    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;

    Swal.fire({
        title: i18n.tenant_confirmStopEmailMfa,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: 'var(--accent-red)',
        cancelButtonColor: 'var(--text-secondary)',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            performMfaOperation(tenantId, false);
        }
    });
}

function performMfaOperation(tenantId, enableEmail) {
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/mfa/email', true);
    xhr.setRequestHeader('Content-Type', 'application/json');

    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const response = JSON.parse(xhr.responseText);
                if (response.success) {
                    Swal.fire({
                        title: 'success',
                        text: 'successful',
                        icon: 'success',
                        confirmButtonColor: 'var(--accent-green)'
                    }).then(() => {
                        refreshMfaStatus();
                    });
                } else {
                    console.log('MFA设置失败:', response.message);
                    showError();
                }
            } catch (error) {
                showError();
            }
        } else {
            showError();
        }
    };

    xhr.onerror = function() {
        showError();
    };

    xhr.send(JSON.stringify({
        tenantId: tenantId,
        enableEmail: enableEmail
    }));
}

function refreshMfaStatus() {
    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;
    const statusContent = document.getElementById('mfaStatusContent');

    statusContent.innerHTML = `
        <div style="text-align: center; padding: 20px;">
            <span class="loading-spinner"></span>
            <span style="margin-left: 10px;">${i18n.tenant_mfaLoading}</span>
        </div>
    `;

    const xhr = new XMLHttpRequest();
    xhr.open('GET', `/tenants/mfa/status?tenantId=`+tenantId, true);

    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const response = JSON.parse(xhr.responseText);
                if (response.success) {
                    updateMfaStatusDisplay(response.data);
                } else {
                    statusContent.innerHTML = `
                        <div style="text-align: center; padding: 20px; color: var(--accent-red);">
                            <i class="fas fa-exclamation-circle"></i>
                            <span style="margin-left: 8px;">'error'</span>
                        </div>
                    `;
                }
            } catch (error) {
                statusContent.innerHTML = `
                    <div style="text-align: center; padding: 20px; color: var(--accent-red);">
                        <i class="fas fa-exclamation-circle"></i>
                        <span style="margin-left: 8px;">error</span>
                    </div>
                `;
            }
        } else {
            statusContent.innerHTML = `
                <div style="text-align: center; padding: 20px; color: var(--accent-red);">
                    <i class="fas fa-exclamation-circle"></i>
                    <span style="margin-left: 8px;">error</span>
                </div>
            `;
        }
    };

    xhr.onerror = function() {
        statusContent.innerHTML = `
            <div style="text-align: center; padding: 20px; color: var(--accent-red);">
                <i class="fas fa-exclamation-circle"></i>
                <span style="margin-left: 8px;">error</span>
            </div>
        `;
    };

    xhr.send();
}

function updateMfaStatusDisplay(mfaData) {
    const statusContent = document.getElementById('mfaStatusContent');

    const emailStatus = mfaData.emailEnabled ? i18n.tenant_enabled : i18n.tenant_stop;
    const emailStatusColor = mfaData.emailEnabled ? 'var(--accent-green)' : 'var(--accent-red)';
    const emailIcon = mfaData.emailEnabled ? 'fas fa-check-circle' : 'fas fa-times-circle';

    const pushStatus = mfaData.pushEnabled ? i18n.tenant_enabled : i18n.tenant_stop;
    const pushStatusColor = mfaData.pushEnabled ? 'var(--accent-green)' : 'var(--accent-red)';
    const pushIcon = mfaData.pushEnabled ? 'fas fa-check-circle' : 'fas fa-times-circle';

    const mfaStatus = mfaData.totpEnabled ? i18n.tenant_enabled : i18n.tenant_stop;
    const mfaStatusColor = mfaData.totpEnabled ? 'var(--accent-green)' : 'var(--accent-red)';
    const mfaIcon = mfaData.totpEnabled ? 'fas fa-check-circle' : 'fas fa-times-circle';

    statusContent.innerHTML = `
        <div style="display: grid; gap: 10px;">
            <div style="display: flex; align-items: center; justify-content: space-between; padding: 12px; background: var(--surface-2, #f8fafc); border-radius: 3px; border: 1px solid var(--card-border);">
                <div style="display: flex; align-items: center; gap: 10px;">
                    <i class="`+ emailIcon+`" style="color: `+  emailStatusColor+`; width: 18px;"></i>
                    <span style="font-weight: 500;">${i18n.tenant_emailVerify}</span>
                </div>
                <span style="color: `+ emailStatusColor+`; font-weight: 500;">`+ emailStatus+`</span>
            </div>
            <div style="display: flex; align-items: center; justify-content: space-between; padding: 12px; background: var(--surface-2, #f8fafc); border-radius: 3px; border: 1px solid var(--card-border);">
                <div style="display: flex; align-items: center; gap: 10px;">
                    <i class="`+ pushIcon+`" style="color: `+  pushStatusColor+`; width: 18px;"></i>
                    <span style="font-weight: 500;">${i18n.tenant_smsVerify}</span>
                </div>
                <span style="color: `+ pushStatusColor+`; font-weight: 500;">`+ pushStatus+`</span>
            </div>
           <div style="display: flex; align-items: center; justify-content: space-between; padding: 12px; background: var(--surface-2, #f8fafc); border-radius: 3px; border: 1px solid var(--card-border);">
                <div style="display: flex; align-items: center; gap: 10px;">
                    <i class="`+ mfaIcon+`" style="color: `+  mfaStatusColor+`; width: 18px;"></i>
                    <span style="font-weight: 500;">${i18n.tenant_mfaVerify}</span>
                </div>
                <span style="color: `+ mfaStatusColor+`; font-weight: 500;">`+ mfaStatus+`</span>
            </div>
        </div>
    `;
}

/*function showResetPasswordModal() {
    const modal = document.getElementById('userManagementModal');
    const tenantId = modal.dataset.tenantId;

    Swal.fire({
        title: '确认重置密码',
        text: '确定要重置此租户的控制台密码吗？重置后将生成新的临时密码。',
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#f39c12',
        cancelButtonColor: '#6b7280',
        confirmButtonText: '确认重置',
        cancelButtonText: '取消'
    }).then((result) => {
        if (result.isConfirmed) {
            executePasswordReset(tenantId);
        }
    });
}*/

// 执行密码重置
/*function executePasswordReset(tenantId) {
    // 显示加载状态
    Swal.fire({
        title: '重置中',
        text: '正在重置密码，请稍候...',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });

    // 发送请求到后端
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/oracle-users/resetPassword', true);
    xhr.setRequestHeader('Content-Type', 'application/json');

    // 设置CSRF令牌
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const response = JSON.parse(xhr.responseText);
                if (response.success) {
                    Swal.fire({
                        title: '重置成功',
                        text: response.message || '密码已成功重置，临时密码已通过通知发送',
                        icon: 'success',
                        confirmButtonColor: '#1abc9c'
                    });
                } else {
                    Swal.fire({
                        title: '重置失败',
                        text: response.message || '密码重置失败',
                        icon: 'error',
                        confirmButtonColor: '#ef4444'
                    });
                }
            } catch (error) {
                Swal.fire({
                    title: '操作失败',
                    text: '处理响应时出现错误',
                    icon: 'error',
                    confirmButtonColor: '#ef4444'
                });
            }
        } else {
            Swal.fire({
                title: '操作失败',
                text: '密码重置请求失败，请稍后重试',
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

    // 发送数据
    xhr.send(JSON.stringify({
        tenantId: tenantId
    }));
}*/

let currentEmailServiceTenantId = null;

function handleEmailServiceAction(tenantId, emailEnable) {
    enableEmailService(String(tenantId), (parseInt(emailEnable) === 1));
}
function enableEmailService(tenantId, isViewOnly = false) {
    currentEmailServiceTenantId = tenantId;

    const modal = document.getElementById('emailServiceModal');
    const domainInput = document.getElementById('emailDomainInput');
    const saveBtn = modal.querySelector('.btn-success');
    const resetBtn = document.getElementById('emailResetBtn'); // 获取重置按钮

    // 1. 基础重置 [cite: 168, 179]
    modal.dataset.tenantId = tenantId;
    domainInput.value = '';
    domainInput.disabled = false;
    saveBtn.disabled = false;
    saveBtn.style.display = 'inline-flex';
    resetBtn.style.display = 'none'; // 默认隐藏重置按钮

    // 2. 显示模态框 [cite: 165]
    modal.style.display = 'flex';

    if (isViewOnly) {
        domainInput.disabled = true;
        saveBtn.style.display = 'none';
        resetBtn.style.display = 'inline-flex';
        domainInput.placeholder = i18n.common_loading || 'Loading...';

        const xhr = new XMLHttpRequest();
        xhr.open('POST', '/email/tenant/get', true);
        xhr.setRequestHeader('Content-Type', 'application/json');
        xhr.setRequestHeader('X-CSRF-TOKEN', document.querySelector('input[name="_csrf"]').value);

        xhr.onload = function() {
            if (xhr.status === 200) {
                const res = JSON.parse(xhr.responseText);
                if (res.success && res.data && res.data.length > 0) {
                    domainInput.value = res.data[0].domainName || '';
                } else {
                    domainInput.value = '';
                    domainInput.placeholder = 'No configuration found';
                }
            }
        };
        xhr.send(JSON.stringify({ tenantId: tenantId }));
    } else {
        domainInput.placeholder = ' example.com';
        setTimeout(() => domainInput.focus(), 100);
    }
}

function resetEmailEditMode() {
    const domainInput = document.getElementById('emailDomainInput');
    const saveBtn = document.querySelector('#emailServiceModal .btn-success');
    const resetBtn = document.getElementById('emailResetBtn');
    domainInput.disabled = false;
    saveBtn.style.display = 'inline-flex';
    saveBtn.disabled = false;
    resetBtn.style.display = 'none';
    domainInput.focus();
}

function closeEmailServiceModal() {
    const modal = document.getElementById('emailServiceModal');
    modal.style.display = 'none';
    modal.dataset.tenantId = '';
    document.getElementById('emailDomainInput').value = '';
}

/**
 * 确认启用邮件服务
 */
function confirmEnableEmailService() {
    const modal = document.getElementById('emailServiceModal');
    const tenantId = modal.dataset.tenantId;

    if (!tenantId) {
        return;
    }

    const domainInput = document.getElementById('emailDomainInput');
    const emailDomain = domainInput.value.trim();

    // 验证域名输入
    if (!emailDomain) {
        Swal.fire({
            title: 'error',
            text: i18n.tenant_plzEmailDomain,
            icon: 'error',
            confirmButtonColor: 'var(--accent-red)'
        });
        domainInput.focus();
        return;
    }
    const domainPattern = /^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/;
    if (!domainPattern.test(emailDomain)) {
        Swal.fire({
            title: i18n.tenant_domainFormatError,
            icon: 'error',
            confirmButtonColor: 'var(--accent-red)'
        });
        domainInput.focus();
        return;
    }
    closeEmailServiceModal();
    executeEnableEmailService(tenantId, emailDomain);
}


function executeEnableEmailService(tenantId, emailDomain) {
    Swal.fire({
        title: 'loading',
        icon: 'info',
        allowOutsideClick: false,
        allowEscapeKey: false,
        showConfirmButton: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/email/enable', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    // 获取 CSRF Token
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);
    xhr.timeout = 60000;

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const response = JSON.parse(xhr.responseText);
                if (response.success) {
                    var successHtml = '<div style="text-align: left; margin: 20px 0;">' +
                        '<p style="color: var(--accent-green); font-weight: 500; margin-bottom: 15px;">' +
                        '<i class="fas fa-check-circle"></i> ' + i18n.tenant_emailSuccess + '' +
                        '</p></div>';

                    Swal.fire({
                        title: 'success',
                        html: successHtml,
                        icon: 'success',
                        confirmButtonColor: 'var(--accent-green)',
                        confirmButtonText: i18n.tenant_kw
                    }).then(() => {
                        location.reload();
                    });
                } else {
                    showError(response.message || 'Operation failed');
                }
            } catch (error) {
                showError('Data parsing error');
            }
        } else {
            showError('Server error: ' + xhr.status);
        }
    };

    xhr.onerror = function() {
        showError('Network connection error');
    };

    xhr.ontimeout = function() {
        showError('Request timed out');
    };
    xhr.send(JSON.stringify({
        tenantId: tenantId,
        emailDomain: emailDomain
    }));
}

function toggleEmailInfo() {
    const infoPanel = document.getElementById('emailInfoPanel');
    const icon = document.querySelector('.info-icon');

    if (infoPanel.style.display === 'none') {
        infoPanel.style.display = 'block';
        icon.className = 'fas fa-info-circle info-icon';
        icon.style.color = '#28a745';
        icon.title = i18n.tenant_clickHide;
    } else {
        infoPanel.style.display = 'none';
        icon.className = 'fas fa-info-circle info-icon';
        icon.style.color = '#3085d6';
        icon.title = i18n.tenant_clickShow;
    }
}

function showAuditLogs(tenantId) {
    auditTenantId = tenantId;
    auditNextPageToken = null;
    auditRowIndex = 0;

    const today = new Date().toISOString().split('T')[0];
    const startInput = document.getElementById('startDate');
    const endInput = document.getElementById('endDate');
    if (startInput && endInput) {
        startInput.value = today;
        endInput.value = today;
    }

    document.getElementById('auditLogModal').style.display = 'flex';
    loadAuditLogs(today, today);
}

function closeAuditLogModal() {
    document.getElementById('auditLogModal').style.display = 'none';
}

function searchAuditLogsByDate() {
    const startInput = document.getElementById('startDate');
    const endInput = document.getElementById('endDate');

    const startDateStr = startInput.value;
    const endDateStr = endInput.value || startDateStr; // 若未选endDate, 用startDate代替

    if (!startDateStr) {
        Swal.fire('warning', i18n.tenant_plzStartTime, 'info');
        return;
    }

    const startDate = new Date(startDateStr);
    const endDate = new Date(endDateStr);
    const now = new Date();

    // 检查日期范围有效性
    if (startDate > endDate) {
        Swal.fire('warning', i18n.tenant_plzStartTime1, 'warning');
        return;
    }

    const diffDays = (now - startDate) / (1000 * 60 * 60 * 24);
    if (diffDays > 90) {
        Swal.fire('warning', i18n.tenant_plzStartTime2, 'warning');
        return;
    }

    auditNextPageToken = null;
    auditRowIndex = 0;
    loadAuditLogs(startDateStr, endDateStr);
}

function loadAuditLogs(startDateStr, endDateStr) {
    const tbody = document.getElementById('auditLogTableBody');
    tbody.innerHTML = '<tr><td colspan="7" class="text-center"><span class="loading-spinner"></span> '+i18n.common_loading+'</td></tr>';

    const token = document.querySelector('meta[name="_csrf"]').content;
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/audit/log', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            const response = JSON.parse(xhr.responseText);
            if (response.success && response.data) {
                const data = response.data.data || [];
                const nextToken = response.data.nextPageToken;

                if (!data.length) {
                    tbody.innerHTML = '<tr><td colspan="7" class="text-center" style="color: var(--text-secondary);">暂无数据</td></tr>';
                    document.getElementById('loadMoreLogsBtn').style.display = 'none';
                    return;
                }

                const rows = data.map(item => `
                      <tr class="${item.responseStatus && String(item.responseStatus) !== '200' ? 'audit-error-row' : ''}">
                        <td>${++auditRowIndex}</td>
                        <td>${item.userName || '-'}</td>
                        <td>${item.ipAddress || '-'}</td>
                        <td>${item.eventType || '-'}</td>
                        <td>${item.clientEnv || '-'}</td>
                        <td>${item.eventTime || '-'}</td>
                        <td>${item.responseStatus || '-'}</td>
                    </tr>
                `).join('');

                tbody.innerHTML = rows;
                auditNextPageToken = nextToken;
                document.getElementById('loadMoreLogsBtn').style.display = nextToken ? 'inline-block' : 'none';
            } else {
                tbody.innerHTML = `<tr><td colspan="7" class="text-center" style="color: var(--accent-red);">${response.message || '加载失败'}</td></tr>`;
            }
        } else {
            tbody.innerHTML = '<tr><td colspan="7" class="text-center" style="color: var(--accent-red);">服务器错误</td></tr>';
        }
    };

    xhr.onerror = function() {
        tbody.innerHTML = '<tr><td colspan="7" class="text-center" style="color: var(--accent-red);">网络错误</td></tr>';
    };

    xhr.send(JSON.stringify({
        tenantId: auditTenantId,
        startDate: startDateStr,
        endDate: endDateStr,
        pageToken: auditNextPageToken
    }));
}

function loadMoreAuditLogs() {
    if (!auditNextPageToken) return;

    const tbody = document.getElementById('auditLogTableBody');
    const loadMoreBtn = document.getElementById('loadMoreLogsBtn');
    const token = document.querySelector('meta[name="_csrf"]').content;

    let startDateStr = '';
    let endDateStr = '';

    const startInput = document.getElementById('startDate');
    const endInput = document.getElementById('endDate');
    const singleDateInput = document.getElementById('auditDate');

    if (startInput && startInput.value) {
        startDateStr = startInput.value;
        endDateStr = (endInput && endInput.value) ? endInput.value : startDateStr;
    } else if (singleDateInput && singleDateInput.value) {
        startDateStr = singleDateInput.value;
        endDateStr = singleDateInput.value; // 单天查询
    } else {
        const today = new Date().toISOString().split('T')[0];
        startDateStr = today;
        endDateStr = today;
    }

    loadMoreBtn.disabled = true;
    const originalText = loadMoreBtn.innerHTML;
    loadMoreBtn.innerHTML = '<span class="loading-spinner"></span> '+i18n.common_loading;

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/audit/log', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function () {
        loadMoreBtn.disabled = false;
        loadMoreBtn.innerHTML = originalText;

        if (xhr.status === 200) {
            const response = JSON.parse(xhr.responseText);
            if (response.success && response.data) {
                const data = response.data.data || [];
                const nextToken = response.data.nextPageToken;

                if (data.length > 0) {
                    const rows = data.map(item => `
                         <tr class="${item.responseStatus && String(item.responseStatus) !== '200' ? 'audit-error-row' : ''}">
                            <td>${++auditRowIndex}</td>
                            <td>${item.userName || '-'}</td>
                            <td>${item.ipAddress || '-'}</td>
                            <td>${item.eventType || '-'}</td>
                            <td>${item.clientEnv || '-'}</td>
                            <td>${item.eventTime || '-'}</td>
                            <td>${item.responseStatus || '-'}</td>
                        </tr>
                    `).join('');
                    tbody.insertAdjacentHTML('beforeend', rows);
                }

                auditNextPageToken = nextToken;
                if (!nextToken) loadMoreBtn.style.display = 'none';
            } else {
                console.error('Failed to load audit logs:', response.message);
                showError();
            }
        } else {
           showError();
        }
    };

    xhr.onerror = function () {
        loadMoreBtn.disabled = false;
        loadMoreBtn.innerHTML = originalText;
        showError();
    };

    xhr.send(JSON.stringify({
        tenantId: auditTenantId,
        startDate: startDateStr,
        endDate: endDateStr,
        pageToken: auditNextPageToken
    }));
}

function toggleSpoiler(element) {
    if (element.classList.contains('is-hidden')) {
        element.classList.remove('is-hidden');
        element.classList.add('is-visible');
    } else {
        element.classList.remove('is-visible');
        element.classList.add('is-hidden');
    }
}

var _spoilersVisible = false;
function toggleAllSpoilers() {
    _spoilersVisible = !_spoilersVisible;
    var spoilers = document.querySelectorAll('.name-spoiler');
    spoilers.forEach(function(el) {
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

function showError(){
    Swal.fire({
        title: 'error',
        text: i18n.common_network_error,
        icon: 'error',
        confirmButtonColor: '#ff6b6b'
    });
}

// ================= 自定义名称列显示宽度截断 =================
// 中文/全角字符计 2，英文/数字计 1
function _defNameCharWidth(code) {
    return (code >= 0x1100 && (
        code <= 0x115F ||
        (code >= 0x2E80 && code <= 0x303E) ||
        (code >= 0x3040 && code <= 0x33FF) ||
        (code >= 0x3400 && code <= 0x4DBF) ||
        (code >= 0x4E00 && code <= 0x9FFF) ||
        (code >= 0xAC00 && code <= 0xD7AF) ||
        (code >= 0xF900 && code <= 0xFAFF) ||
        (code >= 0xFF00 && code <= 0xFF60) ||
        (code >= 0xFFE0 && code <= 0xFFE6)
    )) ? 2 : 1;
}

function _truncateByDisplayWidth(str, maxWidth) {
    var w = 0;
    for (var i = 0; i < str.length; i++) {
        w += _defNameCharWidth(str.charCodeAt(i));
        if (w > maxWidth) {
            return str.substring(0, i) + '...';
        }
    }
    return str;
}

document.addEventListener('DOMContentLoaded', function () {
    document.querySelectorAll('.defname-cell').forEach(function (el) {
        var full = el.getAttribute('data-fullname') || '';
        var display = _truncateByDisplayWidth(full, 14);
        if (display !== full) {
            el.textContent = display;
            el.title = full;
        }
    });
});

// ================= 社媒登录配置相关逻辑 =================

let currentSocialTenantId = null;
let currentSocialCloudType = null;
let availableSocialTypes = [];

// 打开模态框
function showSocialLoginModal(tenantId, cloudType) {
    currentSocialTenantId = tenantId;
    currentSocialCloudType = parseInt(cloudType);

    const modal = document.getElementById('socialLoginModal');
    modal.style.display = 'flex';

    // 初始化：先隐藏表单，显示列表
    hideSocialEditForm();

    // 1. 获取支持的登录类型
    loadAvailableLoginTypes();
    // 2. 获取当前已配置的列表
    loadSocialList();
}

// 关闭模态框
function closeSocialLoginModal() {
    document.getElementById('socialLoginModal').style.display = 'none';
    currentSocialTenantId = null;
}

// 获取支持的类型 (调用 /social/availableLoginTypes)
function loadAvailableLoginTypes() {
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/social/availableLoginTypes', true); // 注意你的Controller是POST还是GET，如果没参数建议GET，但你是REST风格
    // 设置 CSRF
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);
    xhr.setRequestHeader('Content-Type', 'application/json');

    xhr.onload = function() {
        if (xhr.status === 200) {
            const res = JSON.parse(xhr.responseText);
            if (res.success) {
                availableSocialTypes = res.data; // 假设返回的是字符串数组 ["Google", "Microsoft"...]
                renderSocialTypeOptions();
            }
        }
    };
    xhr.send();
}

// 渲染下拉框选项
function renderSocialTypeOptions() {
    const select = document.getElementById('socialTypeSelect');
    select.innerHTML = '';
    availableSocialTypes.forEach(type => {
        const opt = document.createElement('option');
        opt.value = type;
        opt.textContent = type;
        select.appendChild(opt);
    });
}

// 获取列表 (调用 /social/list)
function loadSocialList() {
    const tbody = document.getElementById('socialListBody');
    tbody.innerHTML = '<tr><td colspan="4" class="text-center"><span class="loading-spinner"></span> 加载中...</td></tr>';

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/social/list', true);
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);
    xhr.setRequestHeader('Content-Type', 'application/json');

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const res = JSON.parse(xhr.responseText);
                if (res.success) {
                    renderSocialTable(res.data);
                } else {
                    tbody.innerHTML = `<tr><td colspan="4" class="text-center" style="color: red;">${res.message}</td></tr>`;
                }
            } catch (e) {
                tbody.innerHTML = '<tr><td colspan="4" class="text-center" style="color: red;">解析错误</td></tr>';
            }
        } else {
            tbody.innerHTML = '<tr><td colspan="4" class="text-center" style="color: red;">网络错误</td></tr>';
        }
    };

    // 构造 TenantSocial 对象传给后端
    const data = {
        tenantId: currentSocialTenantId,
        cloudType: currentSocialCloudType
    };
    xhr.send(JSON.stringify(data));
}

// 刷新列表
function refreshSocialList() {
    loadSocialList();
}

// 渲染表格
function renderSocialTable(list) {
    const tbody = document.getElementById('socialListBody');
    tbody.innerHTML = '';

    if (!list || list.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" class="text-center" style="color: #999;">' + i18n.openBoot_nDetailData + '</td></tr>';
        return;
    }

    list.forEach(item => {
        const tr = document.createElement('tr');

        // 状态样式定义
        let statusHtml = '';
        if (item.socialStatus === 'active' || item.socialStatus === 'null') {
            statusHtml = `<span class="badge" style="background:#e8f5e9; color:#2e7d32;">Active</span>`;
        } else if (item.socialStatus === 'inactive') {
            statusHtml = `<span class="badge" style="background:#fff3e0; color:#ef6c00;">Inactive</span>`;
        } else if (item.socialStatus === 'disabled') {
            statusHtml = `<span class="badge" style="background:#ffebee; color:#c62828;">Disabled</span>`;
        } else {
            statusHtml = `<span class="badge">${item.socialStatus}</span>`;
        }

        const itemJson = JSON.stringify(item).replace(/"/g, '&quot;');

        // 按钮逻辑：如果已经是禁用状态，则禁用按钮本身
        const isBtnDisabled = item.socialStatus === 'disabled' ? 'disabled' : '';
        const isStatusDisabled = item.socialStatus === 'disabled';

        tr.innerHTML = `
            <td>
                <span class="status-badge" style="background:#e3f2fd; color:#1976d2; font-weight:bold;">
                    ${item.socialTypeStr || item.serviceProviderName || 'Unknown'}
                </span>
            </td>
            <td title="${item.clientId}">${item.clientId.substring(0,15)}...</td>
            <td title="${item.redirectUrl}">${item.redirectUrl.substring(0,15)}...</td>
            <td>${statusHtml}</td>
            <td>
                <button class="btn btn-sm btn-primary" onclick="showEditSocialForm(${itemJson})">
                    <i class="fas fa-edit"></i> ${i18n.common_edit}
                </button>
               ${isStatusDisabled ?
                    `<button class="btn btn-sm btn-success" onclick="enableSocialConfig(${itemJson})">
                        <i class="fas fa-check-circle"></i> ${i18n.common_start}
                    </button>` :
                    `<button class="btn btn-sm btn-danger" onclick="disableSocialConfig(${itemJson})">
                        <i class="fas fa-ban"></i> ${i18n.common_stop}
                    </button>`
                }
            </td>
        `;
        tbody.appendChild(tr);
    });
}

function showAddSocialForm() {
    document.getElementById('socialListView').style.display = 'none';
    document.getElementById('socialEditView').style.display = 'block';
    document.getElementById('socialId').value = '';
    document.getElementById('socialClientId').value = '';
    document.getElementById('socialClientSecret').value = '';
    const _st = document.getElementById('socialTypeSelect');
    const _stWrap = _st.closest ? _st.closest('.cs-wrapper') : null;
    if (_stWrap) _stWrap.style.display = 'block'; else _st.style.display = 'block';
    document.getElementById('socialTypeReadOnly').style.display = 'none';
    document.getElementById('redirectUrlGroup').style.display = 'none';
}

function showEditSocialForm(item) {
    document.getElementById('socialListView').style.display = 'none';
    document.getElementById('socialEditView').style.display = 'block';
    document.getElementById('socialId').value = item.id;
    document.getElementById('socialClientId').value = item.clientId || '';
    document.getElementById('socialClientSecret').value = item.clientSecret || ''; // 注意安全，后端可能要脱敏，这里假设后端返回了
    const typeStr = item.socialTypeStr || item.serviceProviderName;
    const typeInput = document.getElementById('socialTypeReadOnly');
    typeInput.value = typeStr;
    typeInput.style.display = 'block';
    const _st2 = document.getElementById('socialTypeSelect');
    const _stWrap2 = _st2.closest ? _st2.closest('.cs-wrapper') : null;
    if (_stWrap2) _stWrap2.style.display = 'none'; else _st2.style.display = 'none';
    if (item.redirectUrl) {
        document.getElementById('redirectUrlGroup').style.display = 'block';
        document.getElementById('socialRedirectUrl').value = item.redirectUrl;
    } else {
        document.getElementById('redirectUrlGroup').style.display = 'none';
    }
}

function hideSocialEditForm() {
    document.getElementById('socialEditView').style.display = 'none';
    document.getElementById('socialListView').style.display = 'block';
}

function saveSocialConfig() {
    const id = document.getElementById('socialId').value;
    const clientId = document.getElementById('socialClientId').value.trim();
    const clientSecret = document.getElementById('socialClientSecret').value.trim();
    let socialType = '';

    if (!clientId || !clientSecret) {
        Swal.fire('warning', i18n.common_plzInputGlobalRequired, 'warning');
        return;
    }
    const isUpdate = !!id;
    let url = isUpdate ? '/social/update' : '/social/add';

    if (isUpdate) {
        socialType = document.getElementById('socialTypeReadOnly').value;
    } else {
        socialType = document.getElementById('socialTypeSelect').value;
    }
    const data = {
        id: id || null,
        tenantId: currentSocialTenantId,
        cloudType: currentSocialCloudType,
        socialTypeStr: socialType,
        clientId: clientId,
        clientSecret: clientSecret
    };
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => Swal.showLoading()
    });

    const xhr = new XMLHttpRequest();
    xhr.open('POST', url, true);
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);
    xhr.setRequestHeader('Content-Type', 'application/json');

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const res = JSON.parse(xhr.responseText);
                if (res.success) {
                    Swal.fire({
                        icon: 'success',
                        title: 'successful',
                        text: res.message,
                        timer: 1500,
                        showConfirmButton: false
                    }).then(() => {
                        hideSocialEditForm();
                        loadSocialList();
                    });
                } else {
                    Swal.fire('error', res.message, 'error');
                }
            } catch (e) {
                showError();
            }
        } else {
            showError();
        }
    };

    xhr.onerror = function() {
        showError();
    };

    xhr.send(JSON.stringify(data));
}

function disableSocialConfig(item) {
    Swal.fire({
        title: i18n.common_confirm,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#d33',
        cancelButtonColor: '#3085d6',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            Swal.fire({
                title: 'loading',
                allowOutsideClick: false,
                didOpen: () => Swal.showLoading()
            });
            const requestData = {
                id: item.id,
                tenantId: currentSocialTenantId,
                cloudType: currentSocialCloudType,
                socialTypeStr: item.socialTypeStr || item.serviceProviderName,
                socialStatus: 'disabled'
            };
            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/social/disable', true);
            const tokenElement = document.querySelector('input[name="_csrf"]');
            const token = tokenElement ? tokenElement.value : '';
            xhr.setRequestHeader('X-CSRF-TOKEN', token);
            xhr.setRequestHeader('Content-Type', 'application/json');
            xhr.onload = function() {
                if (xhr.status === 200) {
                    try {
                        const res = JSON.parse(xhr.responseText);
                        if (res.success) {
                            Swal.fire({
                                icon: 'success',
                                title: 'successful',
                                timer: 1500,
                                showConfirmButton: false
                            }).then(() => {
                                loadSocialList();
                            });
                        } else {
                            showError();
                        }
                    } catch (e) {
                        showError();
                    }
                } else {
                    showError();
                }
            };
            xhr.onerror = function() {
                Swal.fire('Error', '无法连接到服务器，请检查网络。', 'error');
            };
            xhr.send(JSON.stringify(requestData));
        }
    });
}

function enableSocialConfig(item) {
    Swal.fire({
        title: i18n.common_confirm,
        icon: 'question',
        showCancelButton: true,
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            Swal.fire({ title: 'loading', allowOutsideClick: false, didOpen: () => Swal.showLoading() });

            const xhr = new XMLHttpRequest();
            xhr.open('POST', '/social/enable', true);

            const token = document.querySelector('input[name="_csrf"]').value;
            xhr.setRequestHeader('X-CSRF-TOKEN', token);
            xhr.setRequestHeader('Content-Type', 'application/json');

            xhr.onload = function() {
                if (xhr.status === 200) {
                    const res = JSON.parse(xhr.responseText);
                    if (res.success) {
                        Swal.fire({ icon: 'success', title: 'successful', timer: 1500, showConfirmButton: false })
                            .then(() => loadSocialList());
                    } else {
                        console.error(res.message)
                        showError();
                    }
                }
            };
            xhr.send(JSON.stringify({
                id: item.id,
                tenantId: currentSocialTenantId,
                cloudType: currentSocialCloudType,
                socialTypeStr: item.socialTypeStr
            }));
        }
    });
}

// 1. 弹出编辑账号成本的对话框
function editAccountCost(tenantId, currentCost) {
    currentEditingTenantId = String(tenantId);

    Swal.fire({
        title: i18n.tenant_editCost,
        input: 'text',
        inputValue: currentCost || '',
        showCancelButton: true,
        confirmButtonColor: 'var(--accent-green)',
        cancelButtonColor: '#6c757d',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel,
        inputValidator: (value) => {
            return null;
        }
    }).then((result) => {
        if (result.isConfirmed) {
            saveAccountCost(currentEditingTenantId, result.value);
        }
    });
}

function saveAccountCost(tenantId, newCost) {
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });

    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/updateAccountCost', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const response = JSON.parse(xhr.responseText);
                if (response.success) {
                    const costElement = document.getElementById('cost-' + tenantId);
                    if (costElement) {
                        costElement.textContent = newCost || '';
                        costElement.setAttribute('data-fulltext', newCost || '');
                    }
                    Swal.fire({
                        icon: 'success',
                        title: 'successful',
                        timer: 1500,
                        showConfirmButton: false
                    });
                } else {
                    showError();
                }
            } catch (error) {
                showError();
            }
        } else {
            showError();
        }
    };

    xhr.onerror = showError;
    xhr.send(JSON.stringify({
        tenantId: tenantId,
        accountCost: newCost
    }));
}

let currentTransferTenantId = null;

function showTransferModal(tenantId) {
    currentTransferTenantId = tenantId;
    document.getElementById('transferAmount').value = '';
    document.getElementById('transferModal').style.display = 'flex';
}

function closeTransferModal() {
    document.getElementById('transferModal').style.display = 'none';
    currentTransferTenantId = null;
}

function confirmTransfer() {
    let amount = document.getElementById('transferAmount').value;
    if (!amount || amount.trim() === '' || parseFloat(amount) < 0) {
        amount = "0";
    }
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/transfer', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    const token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);
    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const res = JSON.parse(xhr.responseText);
                if (res.success) {
                    location.reload();
                } else {
                    Swal.fire('Error', res.message, 'error');
                }
            } catch (e) {
                Swal.fire('Error', 'Data error', 'error');
            }
        } else {
            Swal.fire('Error', 'Server error: ' + xhr.status, 'error');
        }
    };
    xhr.onerror = function() {
        Swal.fire('Error', 'Network error', 'error');
    };
    xhr.send(JSON.stringify({
        tenantId: currentTransferTenantId,
        transferAmount: amount
    }));
}

function showTransferDetail(id, amount) {
    const displayAmount = (amount && amount !== 'null') ? amount : '0';
    document.getElementById('detailTransferAmount').innerText = displayAmount;
    const modal = document.getElementById('transferDetailModal');
    if (modal) {
        modal.style.display = 'flex';
    }
}

function closeModal(modalId) {
    const modal = document.getElementById(modalId);
    if (modal) {
        modal.style.display = 'none';
    }
}

function showQuotaModal(tenantId) {
    var modal = document.getElementById('quotaModal');
    var content = document.getElementById('quotaContent');
    modal.style.display = 'flex';
    // Reset content
    content.innerHTML = '<div style="text-align:center;padding:60px 0;color:var(--text-secondary);">'
        + '<i class="fas fa-chart-bar" style="font-size:36px;display:block;margin-bottom:12px;opacity:0.25;"></i>'
        + '<div style="font-size:13px;">选择租户和服务类型，点击查询</div></div>';
    document.getElementById('quotaModalSubtitle').textContent = '选择租户和服务后点击查询';

    // Fetch tenant list (clicked tenant + children if parent)
    var tenantSel = document.getElementById('quotaTenantSelect');
    tenantSel.innerHTML = '<option value="">加载中...</option>';
    if (window.CustomSelect) CustomSelect.refresh(tenantSel);

    var csrfToken = document.querySelector('meta[name="_csrf"]').getAttribute('content');
    fetch('/tenants/listRegions?parentId=' + tenantId, { headers: { 'X-CSRF-TOKEN': csrfToken } })
    .then(function(r) { return r.json(); })
    .then(function(list) {
        tenantSel.innerHTML = '';
        if (!list || list.length === 0) {
            // No children — this IS the leaf tenant, add it directly
            tenantSel.innerHTML = '<option value="' + tenantId + '">当前租户</option>';
        } else {
            list.forEach(function(t) {
                var label = t.tenancyName || t.userName || t.tenantId || t.id;
                if (t.region) label += ' (' + t.region + ')';
                var opt = document.createElement('option');
                opt.value = t.id;
                opt.textContent = label;
                tenantSel.appendChild(opt);
            });
        }
        if (window.CustomSelect) CustomSelect.refresh(tenantSel);
    })
    .catch(function() {
        tenantSel.innerHTML = '<option value="' + tenantId + '">当前租户</option>';
        if (window.CustomSelect) CustomSelect.refresh(tenantSel);
    });

    // Reset service select to compute
    var svcSel = document.getElementById('quotaServiceSelect');
    svcSel.value = 'compute';
    if (window.CustomSelect) CustomSelect.refresh(svcSel);
}

function doQuotaQuery() {
    var tenantSel  = document.getElementById('quotaTenantSelect');
    var svcSel     = document.getElementById('quotaServiceSelect');
    var tenantId   = tenantSel.value;
    var svc        = svcSel.value || 'compute';
    var svcLabels  = {'compute':'计算 (Compute)','block-storage':'块存储 (Block Storage)','object-storage':'对象存储 (Object Storage)'};

    if (!tenantId) {
        alert('请先选择租户');
        return;
    }

    var content = document.getElementById('quotaContent');
    var btn     = document.getElementById('quotaQueryBtn');
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> 查询中...';

    content.innerHTML = '<div style="text-align:center;padding:60px 0;color:var(--text-secondary);">'
        + '<i class="fas fa-spinner fa-spin" style="font-size:28px;display:block;margin-bottom:12px;"></i>'
        + '<div style="font-size:13px;">正在查询 ' + (svcLabels[svc]||svc) + ' 配额...</div></div>';

    var csrfToken = document.querySelector('meta[name="_csrf"]').getAttribute('content');
    fetch('/tenants/quota?tenantId=' + tenantId + '&serviceName=' + encodeURIComponent(svc), {
        headers: { 'X-CSRF-TOKEN': csrfToken }
    })
    .then(function(r) { return r.json(); })
    .then(function(data) {
        btn.disabled = false;
        btn.innerHTML = '<i class="fas fa-search"></i> 查询';
        if (data.error) {
            content.innerHTML = '<div style="color:var(--accent-red);padding:40px;text-align:center;">'
                + '<i class="fas fa-exclamation-circle" style="font-size:28px;display:block;margin-bottom:10px;"></i>'
                + data.error + '</div>';
            return;
        }
        var itemCount = (data.items || []).length;
        document.getElementById('quotaModalSubtitle').textContent
            = (data.region || '') + ' · ' + (svcLabels[svc]||svc) + ' · 共 ' + itemCount + ' 项';
        content.innerHTML = renderQuotaContent(data);
    })
    .catch(function() {
        btn.disabled = false;
        btn.innerHTML = '<i class="fas fa-search"></i> 查询';
        content.innerHTML = '<div style="color:var(--accent-red);padding:40px;text-align:center;">获取配额失败，请稍后重试</div>';
    });
}

function renderQuotaContent(data) {
    var items = data.items || [];
    if (items.length === 0) {
        return '<div style="padding:40px;text-align:center;color:var(--text-secondary);">'
            + '<i class="fas fa-inbox" style="font-size:32px;display:block;margin-bottom:10px;opacity:0.35;"></i>'
            + '<div style="font-size:13px;">该服务暂无配额数据</div></div>';
    }

    function bar(pct) {
        var c = pct >= 90 ? '#dc2626' : pct >= 60 ? '#d97706' : '#16a34a';
        return '<div style="height:6px;border-radius:3px;background:var(--hover-bg);border:1px solid var(--card-border);overflow:hidden;">'
            + '<div style="height:100%;width:' + pct + '%;background:' + c + ';border-radius:3px;transition:width 0.4s;"></div></div>';
    }

    function dot(pct) {
        var c = pct >= 90 ? '#dc2626' : pct >= 60 ? '#d97706' : '#16a34a';
        return '<span style="display:inline-block;width:7px;height:7px;border-radius:50%;background:' + c + ';margin-right:6px;flex-shrink:0;vertical-align:middle;"></span>';
    }

    var rows = items.map(function(it) {
        var total = it.total || 0, used = it.used || 0, avail = it.available || 0;
        var pct   = total > 0 ? Math.min(100, Math.round(used / total * 100)) : 0;
        var ac    = avail <= 0 ? '#dc2626' : avail < total * 0.2 ? '#d97706' : '#16a34a';
        var pc    = pct >= 90 ? '#dc2626' : pct >= 60 ? '#d97706' : 'var(--text-secondary)';
        return '<tr style="border-bottom:1px solid var(--card-border);transition:background 0.1s;"'
            + ' onmouseover="this.style.background=\'var(--hover-bg)\'" onmouseout="this.style.background=\'transparent\'">'
            + '<td style="padding:9px 16px;font-size:11px;color:var(--text-primary);word-break:break-all;">'
            + dot(pct) + it.name + '</td>'
            + '<td style="padding:9px 12px;font-size:12px;text-align:center;color:var(--text-secondary);">' + total + '</td>'
            + '<td style="padding:9px 12px;font-size:12px;text-align:center;color:var(--text-secondary);">' + used + '</td>'
            + '<td style="padding:9px 12px;font-size:12px;text-align:center;font-weight:700;color:' + ac + ';">' + avail + '</td>'
            + '<td style="padding:9px 16px;min-width:120px;">' + bar(pct) + '</td>'
            + '<td style="padding:9px 12px;font-size:12px;text-align:center;font-weight:600;color:' + pc + ';white-space:nowrap;">' + pct + '%</td>'
            + '</tr>';
    }).join('');

    return '<div style="border:1px solid var(--card-border);border-radius:10px;overflow:hidden;">'
        + '<table style="width:100%;border-collapse:collapse;">'
        + '<thead><tr style="background:var(--surface-2,var(--hover-bg));border-bottom:1px solid var(--card-border);">'
        + '<th style="padding:9px 16px;font-size:10px;font-weight:700;color:var(--text-secondary);text-align:left;letter-spacing:.6px;text-transform:uppercase;">限额名称</th>'
        + '<th style="padding:9px 12px;font-size:10px;font-weight:700;color:var(--text-secondary);text-align:center;width:64px;letter-spacing:.6px;text-transform:uppercase;">总量</th>'
        + '<th style="padding:9px 12px;font-size:10px;font-weight:700;color:var(--text-secondary);text-align:center;width:64px;letter-spacing:.6px;text-transform:uppercase;">已用</th>'
        + '<th style="padding:9px 12px;font-size:10px;font-weight:700;color:var(--text-secondary);text-align:center;width:64px;letter-spacing:.6px;text-transform:uppercase;">可用</th>'
        + '<th style="padding:9px 16px;font-size:10px;font-weight:700;color:var(--text-secondary);width:130px;letter-spacing:.6px;text-transform:uppercase;">进度条</th>'
        + '<th style="padding:9px 12px;font-size:10px;font-weight:700;color:var(--text-secondary);text-align:center;width:60px;letter-spacing:.6px;text-transform:uppercase;">占比</th>'
        + '</tr></thead>'
        + '<tbody>' + rows + '</tbody>'
        + '</table></div>';
}