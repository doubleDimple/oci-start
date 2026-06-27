// 全局变量
var allContacts = [];
var allTenants = [];
var currentPage = 1;
var pageSize = 10;
var totalPages = 0;
var totalElements = 0;
// 租户分页变量
var tenantCurrentPage = 1;
var tenantTotalPages = 0;
var tenantTotalElements = 0;

var allEmailRecords = [];
var recordCurrentPage = 1;
var recordPageSize = 10;
var recordTotalPages = 0;
var recordTotalElements = 0;

var detailCurrentPage = 1;
var detailPageSize = 10;
var detailTotalPages = 0;
var detailTotalElements = 0;
var currentEmailBodyId = '';
const i18n = window.I18N;

function refreshTenants() {
    showLoading('加载中...');
    loadTenantsList();
}

// 加载租户列表
function loadTenantsList() {
    var requestData = {
        pageNum: tenantCurrentPage,
        pageSize: 5,
        sort: 'createdTime',
        order: 'desc'
    };

    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/email/tenant/list', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.setRequestHeader('X-CSRF-TOKEN', document.querySelector('meta[name="_csrf"]').getAttribute('content'));

    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            hideLoading();
            if (xhr.status === 200) {
                var response = JSON.parse(xhr.responseText);
                if (response.success) {
                    var pageData = response.data;
                    allTenants = pageData.content;
                    tenantTotalPages = pageData.totalPages;
                    tenantTotalElements = pageData.totalElements;

                    displayTenantsList();
                    updateTenantsPagination();
                    updateTenantSelect();
                } else {
                    console.error('加载租户列表失败:', response.message);
                    document.getElementById('tenantsList').innerHTML =
                        '<div class="empty-state"><i class="fas fa-exclamation-triangle"></i><h4>加载失败</h4><p>' + response.message + '</p></div>';
                }
            } else {
                console.error('加载租户列表失败');
                document.getElementById('tenantsList').innerHTML =
                    '<div class="empty-state"><i class="fas fa-exclamation-triangle"></i><h4>加载失败</h4><p>网络错误</p></div>';
            }
        }
    };

    xhr.send(JSON.stringify(requestData));
}

function updateTenantSelect() {
    var select = document.getElementById('composeTenantSelect');
    var html = '<option value="">'+i18n.email_selectSenderEmail+'</option>';

    for (var i = 0; i < allTenants.length; i++) {
        var tenant = allTenants[i];
        html += '<option value="' + tenant.id + '">' + (tenant.senderEmail || i18n.aiModel_tenant + tenant.id) + '</option>';
    }

    select.innerHTML = html;
}

function refreshContacts() {
    showLoading('加载中...');
    loadContactsList();
}

function deleteContact(id) {
    Swal.fire({
        title: i18n.common_confirm,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#dc3545',
        cancelButtonColor: '#6c757d',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            showLoading('加载中...');

            var xhr = new XMLHttpRequest();
            var timeout = setTimeout(function() {
                xhr.abort();
                hideLoading();
                showError();
            }, 15000);

            xhr.open('POST', '/email/receive/delete?id=' + id, true);
            xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
            xhr.setRequestHeader('X-CSRF-TOKEN', document.querySelector('meta[name="_csrf"]').getAttribute('content'));

            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4) {
                    clearTimeout(timeout);
                    hideLoading();

                    if (xhr.status === 200) {
                        var response = JSON.parse(xhr.responseText);
                        if (response.success) {
                            Swal.fire({
                                icon: 'success',
                                title: '操作成功',
                                confirmButtonColor: '#28a745',
                                timer: 2000,
                                timerProgressBar: true
                            }).then(() => {
                                loadContactsList();
                            });
                        } else {
                            showError();
                        }
                    } else {
                        showError();
                    }
                }
            };
            xhr.send();
        }
    });
}

function refreshRecords() {
    showLoading('加载中...');
    loadEmailRecords();
}

// 显示邮件编写模态框
function showEmailComposeModal() {
    var modal = document.getElementById('emailComposeModal');
    loadRecipientsForCompose();
    modal.classList.add('show');
}

// 关闭邮件编写模态框
function closeEmailComposeModal() {
    var modal = document.getElementById('emailComposeModal');
    modal.classList.remove('show');
    document.getElementById('composeSubject').value = '';
    document.getElementById('composeContent').value = '';
    document.getElementById('composeTenantSelect').value = '';
    var checkboxes = document.querySelectorAll('.recipient-checkbox');
    for (var i = 0; i < checkboxes.length; i++) {
        checkboxes[i].checked = false;
    }
    updateSelectedCount();
}

// 加载联系人列表
function loadContactsList() {
    var requestData = {
        pageNum: currentPage,
        pageSize: pageSize,
        sort: 'createTime',
        order: 'desc'
    };

    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/email/receive/list', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.setRequestHeader('X-CSRF-TOKEN', document.querySelector('meta[name="_csrf"]').getAttribute('content'));

    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            hideLoading();
            if (xhr.status === 200) {
                var response = JSON.parse(xhr.responseText);
                if (response.success) {
                    var pageData = response.data;
                    allContacts = pageData.content;
                    totalPages = pageData.totalPages;
                    totalElements = pageData.totalElements;

                    displayContactsList();
                    updateContactsPagination();
                } else {
                    console.error('加载联系人列表失败:', response.message);
                    document.getElementById('contactsList').innerHTML =
                        '<div class="empty-state"><i class="fas fa-exclamation-triangle"></i><h4>error</h4><p>' + response.message + '</p></div>';
                }
            } else {
                console.error('加载联系人列表失败');
                document.getElementById('contactsList').innerHTML =
                    '<div class="empty-state"><i class="fas fa-exclamation-triangle"></i><h4>error</h4><p>network error</p></div>';
            }
        }
    };

    xhr.send(JSON.stringify(requestData));
}

// 显示联系人列表
function displayContactsList() {
    var container = document.getElementById('contactsList');
    var html = '';

    if (allContacts.length === 0) {
        html = '<div class="empty-state"><i class="fas fa-address-book"></i><h4>'+i18n.email_noContentPerson+'</h4><p>'+i18n.email_addFirstContentPerson+'</p></div>';
    } else {
        for (var i = 0; i < allContacts.length; i++) {
            var contact = allContacts[i];
            html +=
                '<div class="contact-item">' +
                '<div class="contact-info">' +
                '<div class="contact-name">' + contact.name + '</div>' +
                '<div class="contact-email">' + contact.email + '</div>' +
                '</div>' +
                '<div class="contact-actions">' +
                '<button class="btn btn-sm btn-danger" onclick="deleteContact(' + contact.id + ')">' +
                '<i class="fas fa-trash"></i>' +
                '</button>' +
                '</div>' +
                '</div>';
        }
    }

    container.innerHTML = html;
}

// 更新联系人分页
function updatePagination(config) {
    var pageInfo = document.getElementById(config.pageInfoId);
    var pageNumbers = document.getElementById(config.pageNumbersId);
    var prevBtn = document.getElementById(config.prevBtnId);
    var nextBtn = document.getElementById(config.nextBtnId);

    // 更新页面信息
    pageInfo.textContent = '共 ' + config.totalElements + ' ' + config.itemName;

    // 生成页码（含省略号）：1 ... cur-1 cur cur+1 ... last
    var html = '';
    if (config.totalPages > 0) {
        var cur = config.currentPage;
        var last = config.totalPages;
        var fn = config.goToPageFunction;

        function pageBtn(p) {
            var cls = p === cur ? ' active' : '';
            return '<button class="page-btn' + cls + '" onclick="' + fn + '(' + p + ')">' + p + '</button>';
        }
        function ellipsis() {
            return '<span class="page-ellipsis">...</span>';
        }

        if (last <= 7) {
            // 页数少，全部显示
            for (var i = 1; i <= last; i++) html += pageBtn(i);
        } else {
            // 始终显示第1页
            html += pageBtn(1);
            if (cur > 4) html += ellipsis();
            // 当前页周围 ±2
            var lo = Math.max(2, cur - 2);
            var hi = Math.min(last - 1, cur + 2);
            for (var i = lo; i <= hi; i++) html += pageBtn(i);
            if (cur < last - 3) html += ellipsis();
            // 始终显示最后一页
            html += pageBtn(last);
        }
    }
    pageNumbers.innerHTML = html;

    // 更新前后按钮状态
    if (config.currentPage <= 1) {
        prevBtn.classList.add('disabled');
    } else {
        prevBtn.classList.remove('disabled');
    }

    if (config.currentPage >= config.totalPages || config.totalPages === 0) {
        nextBtn.classList.add('disabled');
    } else {
        nextBtn.classList.remove('disabled');
    }
}

// 跳转到指定页面
function goToPage(page) {
    if (page < 1 || page > totalPages || page === currentPage) {
        return;
    }
    currentPage = page;
    loadContactsList();
}

function goToTenantPage(page) {
    if (page < 1 || page > tenantTotalPages || page === tenantCurrentPage) {
        return;
    }
    tenantCurrentPage = page;
    loadTenantsList();
}

// 为邮件编写加载收件人复选框列表
function loadRecipientsForCompose() {
    var requestData = {
        pageNum: 1,
        pageSize: 100,
        sort: 'name',
        order: 'asc'
    };

    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/email/receive/list', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.setRequestHeader('X-CSRF-TOKEN', document.querySelector('meta[name="_csrf"]').getAttribute('content'));

    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                var response = JSON.parse(xhr.responseText);
                if (response.success) {
                    var contacts = response.data.content;
                    displayRecipientsForCompose(contacts);
                } else {
                    console.error('加载收件人列表失败:', response.message);
                    document.getElementById('recipientsList').innerHTML =
                        '<div class="empty-state"><i class="fas fa-exclamation-triangle"></i><h4>error</h4><p>' + response.message + '</p></div>';
                }
            }
        }
    };

    xhr.send(JSON.stringify(requestData));
}

// 显示收件人复选框列表
function displayRecipientsForCompose(contacts) {
    var container = document.getElementById('recipientsList');
    var html = '';

    if (contacts.length === 0) {
        html = '<div class="empty-state"><i class="fas fa-address-book"></i><h4>'+i18n.email_noContentPerson+'</h4><p>'+i18n.email_addFirstContentPerson+'</p></div>';
    } else {
        for (var i = 0; i < contacts.length; i++) {
            var contact = contacts[i];
            html +=
                '<div class="recipient-item">' +
                '<input type="checkbox" class="recipient-checkbox" ' +
                'id="recipient_' + contact.id + '" ' +
                'value="' + contact.id + '" ' +
                'data-name="' + contact.name + '" ' +
                'data-email="' + contact.email + '" ' +
                'onchange="updateSelectedCount()">' +
                '<div class="recipient-info">' +
                '<div class="recipient-name">' + contact.name + '</div>' +
                '<div class="recipient-email">' + contact.email + '</div>' +
                '</div>' +
                '</div>';
        }
    }

    container.innerHTML = html;
    updateSelectedCount();
}

// 保存联系人
function saveContact() {
    var name = document.getElementById('contactName').value.trim();
    var email = document.getElementById('contactEmail').value.trim();

    if (!name || !email) {
        Swal.fire({
            icon: 'warning',
            title: i18n.common_plzInputGlobalRequired,
            confirmButtonColor: '#007bff'
        });
        return;
    }

    var emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(email)) {
        Swal.fire({
            icon: 'warning',
            title: i18n.email_formatError,
            confirmButtonColor: '#007bff'
        });
        return;
    }

    var requestData = {
        name: name,
        email: email
    };

    // 显示保存中的加载提示
    showLoading('加载中...');

    var xhr = new XMLHttpRequest();
    var timeout = setTimeout(function() {
        xhr.abort();
        hideLoading();
        showError();
    }, 15000);

    xhr.open('POST', '/email/receive/add', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.setRequestHeader('X-CSRF-TOKEN', document.querySelector('meta[name="_csrf"]').getAttribute('content'));

    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            clearTimeout(timeout);
            hideLoading();

            if (xhr.status === 200) {
                var response = JSON.parse(xhr.responseText);
                if (response.success) {
                    Swal.fire({
                        icon: 'success',
                        title: '操作成功',
                        confirmButtonColor: '#28a745',
                        timer: 2000,
                        timerProgressBar: true
                    }).then(() => {
                        closeAddContactModal();
                        loadContactsList();
                    });
                } else {
                    showError();
                }
            } else {
                showError();
            }
        }
    };

    xhr.send(JSON.stringify(requestData));
}

function selectAllRecipients() {
    var checkboxes = document.querySelectorAll('.recipient-checkbox');
    for (var i = 0; i < checkboxes.length; i++) {
        checkboxes[i].checked = true;
    }
    updateSelectedCount();
}

function unselectAllRecipients() {
    var checkboxes = document.querySelectorAll('.recipient-checkbox');
    for (var i = 0; i < checkboxes.length; i++) {
        checkboxes[i].checked = false;
    }
    updateSelectedCount();
}

function updateSelectedCount() {
    var checkboxes = document.querySelectorAll('.recipient-checkbox:checked');
    var count = checkboxes.length;
    document.getElementById('selectedCount').textContent = count;
}

function sendEmail() {
    var subject = document.getElementById('composeSubject').value.trim();
    var content = document.getElementById('composeContent').value.trim();
    var tenantEmailConfigId = document.getElementById('composeTenantSelect').value;

    if (!subject || !content || !tenantEmailConfigId) {
        Swal.fire({
            icon: 'warning',
            title: i18n.common_plzInputGlobalRequired,
            confirmButtonColor: '#007bff'
        });
        return;
    }

    var checkboxes = document.querySelectorAll('.recipient-checkbox:checked');
    if (checkboxes.length === 0) {
        Swal.fire({
            icon: 'warning',
            title: i18n.email_noSelectReceive,
            confirmButtonColor: '#007bff'
        });
        return;
    }

    var emailReceiveIds = [];
    for (var i = 0; i < checkboxes.length; i++) {
        emailReceiveIds.push(parseInt(checkboxes[i].value));
    }

    var requestData = {
        title: subject,
        content: content,
        tenantEmailConfigId: parseInt(tenantEmailConfigId),
        emailReceiveIds: emailReceiveIds
    };

    // 显示发送中的加载提示
    showLoading('加载中...');

    var xhr = new XMLHttpRequest();
    var timeout = setTimeout(function() {
        xhr.abort();
        hideLoading();
        closeEmailComposeModal();
        refreshRecords();
    }, 30000); // 30秒超时

    xhr.open('POST', '/email/send', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.setRequestHeader('X-CSRF-TOKEN', document.querySelector('meta[name="_csrf"]').getAttribute('content'));

    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            clearTimeout(timeout);
            hideLoading();

            if (xhr.status === 200) {
                var response = JSON.parse(xhr.responseText);
                if (response.success) {
                    Swal.fire({
                        icon: 'success',
                        title: '操作成功',
                        confirmButtonColor: '#28a745'
                    }).then(() => {
                        closeEmailComposeModal();
                        refreshRecords();
                    });
                } else {
                    showError();
                }
            } else {
                showError();
            }
        }
    };

    xhr.send(JSON.stringify(requestData));
}

function showAddContactModal() {
    var modal = document.getElementById('addContactModal');
    modal.classList.add('show');
}

function closeAddContactModal() {
    var modal = document.getElementById('addContactModal');
    modal.classList.remove('show');
    document.getElementById('contactName').value = '';
    document.getElementById('contactEmail').value = '';
}

// 邮件详情相关函数保持不变...
function showEmailDetails(emailBodyId) {
    // 首先找到对应的邮件记录
    var emailRecord = null;
    for (var i = 0; i < allEmailRecords.length; i++) {
        if (allEmailRecords[i].emailBodyId === emailBodyId) {
            emailRecord = allEmailRecords[i];
            break;
        }
    }

    if (!emailRecord) {
        return;
    }

    // 设置邮件基本信息
    document.getElementById('emailSubjectTitle').textContent = emailRecord.title || '未知';

    var createTime = formatDateTime(emailRecord.createTime);
    var emailDetailInfo =
        '<strong>'+i18n.email_sendTime+'：</strong>' + createTime + '<br>' +
        '<strong>'+i18n.email_sender+'：</strong>' + (emailRecord.senderEmail || '未知') + '<br>' +
        '<strong>'+i18n.aiModel_tenant+'：</strong>' + (emailRecord.tenantName || '未知') + '<br>' +
        '<strong>'+i18n.email_content+'：</strong><br>' +
        '<div style="background: white; padding: 10px; border: 1px solid #dee2e6; border-radius: 4px; margin-top: 5px;">' +
        (emailRecord.content || '无内容') +
        '</div>';

    document.getElementById('emailDetailInfo').innerHTML = emailDetailInfo;

    // 加载收件人详细列表
    loadEmailSendRecords(emailBodyId);

    // 显示模态框
    var modal = document.getElementById('emailDetailsModal');
    modal.classList.add('show');
}

function closeEmailDetailsModal() {
    var modal = document.getElementById('emailDetailsModal');
    modal.classList.remove('show');
}

window.onclick = function(event) {
    var emailModal = document.getElementById('emailDetailsModal');
    var composeModal = document.getElementById('emailComposeModal');
    var contactModal = document.getElementById('addContactModal');

    if (event.target === emailModal) {
        closeEmailDetailsModal();
    }
    if (event.target === composeModal) {
        closeEmailComposeModal();
    }
    if (event.target === contactModal) {
        closeAddContactModal();
    }
}

// 页面初始化
document.addEventListener('DOMContentLoaded', function() {
    console.log('邮件管理页面已加载');
    loadTenantsList();
    loadContactsList();
    loadEmailRecords();
});

// 显示租户列表
function displayTenantsList() {
    var badge = document.getElementById('enabledCount');
    if (badge) badge.textContent = tenantTotalElements;
    var container = document.getElementById('tenantsList');
    var html = '';

    if (allTenants.length === 0) {
        html = '<div class="empty-state"><i class="fas fa-server"></i><h4>'+i18n.email_noTenant+'</h4><p>'+i18n.email_noEmailServerTenant+'</p></div>';
    } else {
        for (var i = 0; i < allTenants.length; i++) {
            var tenant = allTenants[i];
            var todaySentCount = tenant.todaySentCount || 0;
            var dailyEmailLimit = tenant.dailyEmailLimit || 200;
            var percentage = (todaySentCount / dailyEmailLimit * 100);
            var progressClass = percentage >= 90 ? 'danger' : (percentage >= 75 ? 'warning' : '');

            var displayName = tenant.tenantName || '';
            html +=
                '<div class="tenant-item" style="display: flex; align-items: flex-start; padding: 10px 12px;">' +
                '<div class="tenant-info" style="flex: 1; min-width: 0; margin-right: 10px;">' +
                (displayName ? '<div style="font-size:12px;color:var(--text-secondary);margin-bottom:2px;">' + _escHtml(displayName) + '</div>' : '') +
                '<div class="tenant-name" style="margin-bottom: 6px;">' + (tenant.senderEmail || i18n.aiModel_tenant + tenant.tenantId) + '</div>' +
                '<div class="tenant-progress" style="display: flex; align-items: center; gap: 6px;">' +
                '<span style="white-space: nowrap; font-size: 11px;">' + todaySentCount + '/' + dailyEmailLimit + '</span>' +
                '<div class="progress-bar" style="flex: 1; height: 4px; background: #e9ecef; border-radius: 2px; overflow: hidden;">' +
                '<div class="progress-fill ' + progressClass + '" style="height: 100%; width: ' + percentage + '%; transition: width 0.3s ease;"></div>' +
                '</div>' +
                '</div>' +
                '</div>' +
                '<div style="flex-shrink: 0; margin-left: 8px;">' +
                '<button class="btn btn-sm btn-danger" onclick="disableEmailService(' + tenant.id + ', \'' + (tenant.senderEmail || i18n.aiModel_tenant + tenant.tenantId) + '\')" title="${i18n.email_disEmailServer}" style="padding: 4px 8px; font-size: 12px;">' +
                '<i class="fas fa-trash"></i>' +
                '</button>' +
                '</div>' +
                '</div>';
        }
    }

    container.innerHTML = html;
}

function disableEmailService(tenantId, tenantName) {
    Swal.fire({
        title: i18n.common_confirm,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#dc3545',
        cancelButtonColor: '#6c757d',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel,
        width: '500px'
    }).then((result) => {
        if (result.isConfirmed) {
            // 显示禁用中的加载提示
            showLoading('加载中...');

            var xhr = new XMLHttpRequest();
            var timeout = setTimeout(function() {
                xhr.abort();
                hideLoading();
                showError();
            }, 30000); // 30秒超时

            xhr.open('POST', '/email/disable', true);
            xhr.setRequestHeader('Content-Type', 'application/json');
            xhr.setRequestHeader('X-CSRF-TOKEN', document.querySelector('meta[name="_csrf"]').getAttribute('content'));

            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4) {
                    clearTimeout(timeout);
                    hideLoading();

                    if (xhr.status === 200) {
                        var response = JSON.parse(xhr.responseText);
                        if (response.success) {
                            Swal.fire({
                                icon: 'success',
                                title: '操作成功',
                                confirmButtonColor: '#28a745',
                                timer: 3000,
                                timerProgressBar: true
                            }).then(() => {
                                loadTenantsList();
                                updateTenantSelect();
                            });
                        } else {
                            showError();
                        }
                    } else {
                        showError();
                    }
                }
            };

            var requestData = {
                id: tenantId
            };
            xhr.send(JSON.stringify(requestData));
        }
    });
}

/* ═══════════════════════════════════════════
   Tab 切换 & 未开启租户管理
═══════════════════════════════════════════ */
var currentEmailTab = 'enabled';
var notEnabledCurrentPage = 1;
var notEnabledTotalPages = 0;
var notEnabledTotalElements = 0;
var tenantSearchKeyword = '';
var _searchTimer = null;

function switchEmailTab(tab) {
    currentEmailTab = tab;
    document.getElementById('tab-btn-enabled').classList.toggle('active', tab === 'enabled');
    document.getElementById('tab-btn-disabled').classList.toggle('active', tab === 'disabled');
    document.getElementById('tab-content-enabled').style.display = tab === 'enabled' ? 'flex' : 'none';
    document.getElementById('tab-content-disabled').style.display = tab === 'disabled' ? 'flex' : 'none';
    document.getElementById('tenantSearchInput').value = '';
    tenantSearchKeyword = '';
    if (tab === 'disabled') {
        notEnabledCurrentPage = 1;
        loadNotEnabledTenants();
    } else {
        tenantCurrentPage = 1;
        loadTenantsList();
    }
}

function refreshCurrentTab() {
    tenantSearchKeyword = '';
    document.getElementById('tenantSearchInput').value = '';
    if (currentEmailTab === 'enabled') {
        tenantCurrentPage = 1;
        loadTenantsList();
    } else {
        notEnabledCurrentPage = 1;
        loadNotEnabledTenants();
    }
}

function onTenantSearch(val) {
    clearTimeout(_searchTimer);
    tenantSearchKeyword = val.trim();
    _searchTimer = setTimeout(function() {
        if (currentEmailTab === 'enabled') {
            tenantCurrentPage = 1;
            loadTenantsList();
        } else {
            notEnabledCurrentPage = 1;
            loadNotEnabledTenants();
        }
    }, 300);
}

function loadNotEnabledTenants() {
    var params = new URLSearchParams();
    params.set('page', notEnabledCurrentPage - 1);
    params.set('size', 5);
    params.set('cloudType', 1);
    params.set('emailEnable', 0);
    if (tenantSearchKeyword) params.set('keyword', tenantSearchKeyword);

    var container = document.getElementById('notEnabledTenantsList');
    container.innerHTML = '<div class="empty-state" style="padding:20px 0;"><span class="loading-spinner"></span></div>';

    fetch('/tenants/list/json?' + params.toString(), {
        headers: { 'X-CSRF-TOKEN': document.querySelector('meta[name="_csrf"]').getAttribute('content') }
    })
    .then(function(r) { return r.json(); })
    .then(function(data) {
        notEnabledTotalPages = data.totalPages;
        notEnabledTotalElements = data.totalElements;
        document.getElementById('disabledCount').textContent = data.totalElements;
        displayNotEnabledTenants(data.content || []);
        updateNotEnabledPagination();
    })
    .catch(function(e) {
        console.error('加载未开启租户失败', e);
        container.innerHTML = '<div class="empty-state"><p>加载失败</p></div>';
    });
}

function _escHtml(s) {
    return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function displayNotEnabledTenants(tenants) {
    var container = document.getElementById('notEnabledTenantsList');
    if (!tenants || tenants.length === 0) {
        container.innerHTML = '<div class="empty-state"><i class="fas fa-check-circle" style="font-size:28px;color:var(--accent-green,#28a745);"></i><p style="margin-top:8px;">所有租户均已开启邮件服务</p></div>';
        return;
    }
    var html = '';
    tenants.forEach(function(t) {
        var id = t.idStr || String(t.id);
        var name = _escHtml(t.tenancyName || t.defName || id);
        var region = _escHtml(t.region || '');
        html +=
            '<div style="border-bottom:1px solid var(--card-border);">' +
              '<div class="tenant-item" style="display:flex;align-items:center;padding:10px 12px;gap:10px;">' +
                '<div style="flex:1;min-width:0;">' +
                  '<div class="tenant-name" style="font-weight:500;">' + name + '</div>' +
                  '<div style="font-size:11px;color:var(--text-secondary);">' + region + '</div>' +
                '</div>' +
                '<button class="btn btn-sm btn-success" style="flex-shrink:0;" onclick="toggleEnableForm(\'' + id + '\')">' +
                  '<i class="fas fa-plus"></i> 开启' +
                '</button>' +
              '</div>' +
              '<div class="enable-inline-form" id="enable-form-' + id + '" style="display:none;">' +
                '<div class="form-row">' +
                  '<input type="text" id="domain-' + id + '" class="form-control" placeholder="example.com"' +
                  ' onkeydown="if(event.key===\'Enter\')submitEnableEmail(\'' + id + '\')">' +
                  '<button class="btn btn-sm btn-success" onclick="submitEnableEmail(\'' + id + '\')">' +
                    '<i class="fas fa-check"></i>' +
                  '</button>' +
                  '<button class="btn btn-sm btn-secondary" onclick="toggleEnableForm(\'' + id + '\')">' +
                    '<i class="fas fa-times"></i>' +
                  '</button>' +
                '</div>' +
              '</div>' +
            '</div>';
    });
    container.innerHTML = html;
}

function toggleEnableForm(id) {
    var form = document.getElementById('enable-form-' + id);
    if (!form) return;
    var opening = form.style.display === 'none';
    // 关闭所有其他展开的表单
    document.querySelectorAll('.enable-inline-form').forEach(function(f) { f.style.display = 'none'; });
    if (opening) {
        form.style.display = 'block';
        var input = document.getElementById('domain-' + id);
        if (input) { input.value = ''; setTimeout(function() { input.focus(); }, 50); }
    }
}

function submitEnableEmail(tenantId) {
    var input = document.getElementById('domain-' + tenantId);
    var domain = input ? input.value.trim() : '';
    if (!domain) { if (input) input.focus(); return; }

    var domainPattern = /^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*(\.[a-zA-Z]{2,})$/;
    if (!domainPattern.test(domain)) {
        Swal.fire({ title: '域名格式错误', text: '请输入正确的域名，如 example.com', icon: 'error', confirmButtonColor: '#dc3545' });
        return;
    }

    showLoading('开启中...');

    fetch('/tenants/email/enable', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            'X-CSRF-TOKEN': document.querySelector('meta[name="_csrf"]').getAttribute('content')
        },
        body: JSON.stringify({ tenantId: tenantId, emailDomain: domain })
    })
    .then(function(r) { return r.json(); })
    .then(function(data) {
        hideLoading();
        if (data.success) {
            Swal.fire({ icon: 'success', title: '开启成功', confirmButtonColor: '#28a745', timer: 2000, timerProgressBar: true })
            .then(function() {
                notEnabledCurrentPage = 1;
                loadNotEnabledTenants();
                loadTenantsList();
            });
        } else {
            Swal.fire({ icon: 'error', title: data.message || '开启失败', confirmButtonColor: '#dc3545' });
        }
    })
    .catch(function() { hideLoading(); showError(); });
}

function goToNotEnabledPage(page) {
    if (page < 1 || page > notEnabledTotalPages || page === notEnabledCurrentPage) return;
    notEnabledCurrentPage = page;
    loadNotEnabledTenants();
}

function updateNotEnabledPagination() {
    updatePagination({
        currentPage: notEnabledCurrentPage,
        totalPages: notEnabledTotalPages,
        totalElements: notEnabledTotalElements,
        pageInfoId: 'notEnabledPageInfo',
        pageNumbersId: 'notEnabledPageNumbers',
        prevBtnId: 'notEnabledPrevBtn',
        nextBtnId: 'notEnabledNextBtn',
        goToPageFunction: 'goToNotEnabledPage',
        itemName: '个租户'
    });
}

// 初始化侧边栏（DOMContentLoaded 已在上方注册，此处仅保留导航初始化）
document.addEventListener('DOMContentLoaded', function() {
    const navParents = document.querySelectorAll('.nav-parent');
    navParents.forEach(function(parent) {
        const parentLink = parent.querySelector('.nav-link');
        if (parentLink) {
            parentLink.addEventListener('click', function(e) {
                e.preventDefault();
                parent.classList.toggle('expanded');
            });
        }
    });
    const activeLink = document.querySelector('.nav-link.active');
    if (activeLink) {
        const parent = activeLink.closest('.nav-parent');
        if (parent) parent.classList.add('expanded');
    }
});

// 更新联系人分页
function updateContactsPagination() {
    updatePagination({
        pageInfoId: 'contactsPageInfo',
        pageNumbersId: 'pageNumbers',
        prevBtnId: 'prevPageBtn',
        nextBtnId: 'nextPageBtn',
        totalElements: totalElements,
        totalPages: totalPages,
        currentPage: currentPage,
        itemName: i18n.email_personCount,
        goToPageFunction: 'goToPage'
    });
}

// 更新租户分页
function updateTenantsPagination() {
    updatePagination({
        pageInfoId: 'tenantPageInfo',
        pageNumbersId: 'tenantPageNumbers',
        prevBtnId: 'tenantPrevBtn',
        nextBtnId: 'tenantNextBtn',
        totalElements: tenantTotalElements,
        totalPages: tenantTotalPages,
        currentPage: tenantCurrentPage,
        itemName: '个' + i18n.aiModel_tenant,
        goToPageFunction: 'goToTenantPage'
    });
}

function loadEmailRecords() {
    var requestData = {
        pageNum: recordCurrentPage,
        pageSize: recordPageSize,
        sort: 'createTime',
        order: 'desc'
    };

    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/email/body/list', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.setRequestHeader('X-CSRF-TOKEN', document.querySelector('meta[name="_csrf"]').getAttribute('content'));

    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            hideLoading();
            if (xhr.status === 200) {
                var response = JSON.parse(xhr.responseText);
                if (response.success) {
                    var pageData = response.data;
                    allEmailRecords = pageData.content;
                    recordTotalPages = pageData.totalPages;
                    recordTotalElements = pageData.totalElements;

                    displayEmailRecords();
                    updateEmailRecordsPagination();
                } else {
                    console.error('加载邮件记录失败:', response.message);
                    document.getElementById('emailRecords').innerHTML =
                        '<div class="empty-state"><i class="fas fa-exclamation-triangle"></i><h4>error</h4><p>' + response.message + '</p></div>';
                }
            } else {
                console.error('加载邮件记录失败');
                document.getElementById('emailRecords').innerHTML =
                    '<div class="empty-state"><i class="fas fa-exclamation-triangle"></i><h4>error</h4><p>network error</p></div>';
            }
        }
    };

    xhr.send(JSON.stringify(requestData));
}

function displayEmailRecords() {
    var container = document.getElementById('emailRecords');
    var html = '';

    if (allEmailRecords.length === 0) {
        html = '<div class="empty-state"><i class="fas fa-envelope"></i><h4>'+i18n.email_noEmailRecords+'</h4><p>'+i18n.email_noSendEmail+'</p></div>';
    } else {
        for (var i = 0; i < allEmailRecords.length; i++) {
            var record = allEmailRecords[i];
            var createTime = formatDateTime(record.createTime);
            var receiveTotal = record.receiveTotal || 0;
            var receiveSuccessTotal = record.receiveSuccessTotal || 0;
            var receiveFailTotal = record.receiveFailTotal || 0;

            html +=
                '<div class="record-item">' +
                '<div class="record-info" onclick="showEmailDetails(\'' + record.emailBodyId + '\')" style="cursor: pointer; flex: 1;">' +
                '<div class="record-subject">' + (record.title || '未知') + '</div>' +
                '<div class="record-details">' +
                '<span>'+i18n.email_sendTime+': ' + createTime + '</span>' +
                '<span>'+i18n.aiModel_tenant+': ' + (record.tenantName || record.senderEmail || '未知') + '</span>' +
                '<span>'+i18n.email_receiveNo+': ' + receiveTotal + '</span>' +
                '<span>'+i18n.email_success+': ' + receiveSuccessTotal + '</span>' +
                '<span>'+i18n.email_fail+': ' + receiveFailTotal + '</span>' +
                '</div>' +
                '</div>' +
                '<div class="record-actions" style="display: flex; align-items: center; gap: 8px; margin-left: 10px;">' +
                '<button class="btn btn-sm btn-danger" onclick="deleteEmailRecord(' + record.id + ')" title="${i18n.email_deleteRecords}">' +
                '<i class="fas fa-trash"></i>' +
                '</button>' +
                '<div class="record-action" onclick="showEmailDetails(\'' + record.emailBodyId + '\')" style="cursor: pointer;">' +
                '<i class="fas fa-chevron-right"></i>' +
                '</div>' +
                '</div>' +
                '</div>';
        }
    }

    container.innerHTML = html;
}

function loadEmailSendRecords(emailBodyId, page) {
    currentEmailBodyId = emailBodyId;
    if (page) {
        detailCurrentPage = page;
    } else {
        detailCurrentPage = 1;
    }

    var requestData = {
        emailBodyId: emailBodyId,
        pageNum: detailCurrentPage,
        pageSize: detailPageSize,
        sort: 'createTime',
        order: 'desc'
    };

    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/email/send/list', true);
    xhr.setRequestHeader('Content-Type', 'application/json');
    xhr.setRequestHeader('X-CSRF-TOKEN', document.querySelector('meta[name="_csrf"]').getAttribute('content'));

    xhr.onreadystatechange = function() {
        if (xhr.readyState === 4) {
            if (xhr.status === 200) {
                var response = JSON.parse(xhr.responseText);
                if (response.success) {
                    var pageData = response.data;
                    var sendRecords = pageData.content;
                    detailTotalPages = pageData.totalPages;
                    detailTotalElements = pageData.totalElements;

                    displayEmailSendRecords(sendRecords);
                    updateEmailDetailPagination(); // 使用统一方法
                } else {
                    console.error('加载发送记录详情失败:', response.message);
                    document.getElementById('recipientsDetailList').innerHTML =
                        '<div class="empty-state"><i class="fas fa-exclamation-triangle"></i><h4>error</h4><p>' + response.message + '</p></div>';
                }
            } else {
                console.error('加载发送记录详情失败');
                document.getElementById('recipientsDetailList').innerHTML =
                    '<div class="empty-state"><i class="fas fa-exclamation-triangle"></i><h4>error</h4><p>network error</p></div>';
            }
        }
    };

    xhr.send(JSON.stringify(requestData));
}

function updateEmailDetailPagination() {
    updatePagination({
        pageInfoId: 'emailDetailPageInfo',
        pageNumbersId: 'emailDetailPageNumbers',
        prevBtnId: 'emailDetailPrevBtn',
        nextBtnId: 'emailDetailNextBtn',
        totalElements: detailTotalElements,
        totalPages: detailTotalPages,
        currentPage: detailCurrentPage,
        itemName: i18n.email_records,
        goToPageFunction: 'goToDetailPage'
    });
}

function goToDetailPage(page) {
    if (page < 1 || page > detailTotalPages || page === detailCurrentPage) {
        return;
    }
    loadEmailSendRecords(currentEmailBodyId, page);
}

function displayEmailSendRecords(sendRecords) {
    var container = document.getElementById('recipientsDetailList');
    var html = '';

    if (sendRecords.length === 0) {
        html = '<div class="empty-state"><i class="fas fa-users"></i><h4>'+i18n.email_noSendEmail+'</h4><p>'+i18n.email_noFindRecords+'</p></div>';
    } else {
        for (var i = 0; i < sendRecords.length; i++) {
            var record = sendRecords[i];
            var statusClass = record.sendState === 1 ? 'success' : 'failed';
            var statusText = record.sendState === 1 ? '成功' : '失败';
            var statusIcon = record.sendState === 1 ? 'fas fa-check-circle' : 'fas fa-times-circle';

            html +=
                '<div class="recipient-detail-item">' +
                '<div class="recipient-detail-info">' +
                '<div class="recipient-name">'+i18n.email_receivers+': ' + record.receiveEmailAddress + '</div>' +
                '</div>' +
                '<div class="recipient-status ' + statusClass + '">' +
                '<i class="' + statusIcon + '"></i>' +
                statusText +
                '</div>' +
                '</div>';
        }
    }

    container.innerHTML = html;
}

function updateEmailRecordsPagination() {
    updatePagination({
        pageInfoId: 'emailRecordsPageInfo',
        pageNumbersId: 'emailRecordsPageNumbers',
        prevBtnId: 'emailRecordsPrevBtn',
        nextBtnId: 'emailRecordsNextBtn',
        totalElements: recordTotalElements,
        totalPages: recordTotalPages,
        currentPage: recordCurrentPage,
        itemName: i18n.email_records,
        goToPageFunction: 'goToEmailRecordsPage'
    });
}

function goToEmailRecordsPage(page) {
    if (page < 1 || page > recordTotalPages || page === recordCurrentPage) {
        return;
    }
    recordCurrentPage = page;
    loadEmailRecords();
}

function formatDateTime(dateTimeStr) {
    if (!dateTimeStr) return '未知时间';

    var date = new Date(dateTimeStr);
    if (isNaN(date.getTime())) {
        if (typeof dateTimeStr === 'string') {
            var parts = dateTimeStr.replace('T', ' ').split(':');
            if (parts.length >= 2) {
                return parts[0] + ':' + parts[1];
            }
        }
        return dateTimeStr;
    }

    var year = date.getFullYear();
    var month = String(date.getMonth() + 1).padStart(2, '0');
    var day = String(date.getDate()).padStart(2, '0');
    var hours = String(date.getHours()).padStart(2, '0');
    var minutes = String(date.getMinutes()).padStart(2, '0');

    return year + '-' + month + '-' + day + ' ' + hours + ':' + minutes;
}

// 批量删除所有记录 - 使用SweetAlert2
function batchDeleteAllRecords() {
    Swal.fire({
        title: i18n.common_confirm,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#dc3545',
        cancelButtonColor: '#6c757d',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            // 显示删除中提示
            showLoading('加载中...');

            var xhr = new XMLHttpRequest();
            xhr.open('POST', '/email/body/batchDelete', true);
            xhr.setRequestHeader('Content-Type', 'application/x-www-form-urlencoded');
            xhr.setRequestHeader('X-CSRF-TOKEN', document.querySelector('meta[name="_csrf"]').getAttribute('content'));

            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4) {
                    hideLoading();
                    if (xhr.status === 200) {
                        var response = JSON.parse(xhr.responseText);
                        if (response.success) {
                            Swal.fire({
                                icon: 'success',
                                title: '操作成功',
                                confirmButtonColor: '#28a745'
                            }).then(() => {
                                loadEmailRecords();
                            });
                        } else {
                            showError();
                        }
                    } else {
                        showError();
                    }
                }
            };
            xhr.send();
        }
    });
}

function deleteEmailRecord(recordId) {
    Swal.fire({
        title: i18n.common_confirm,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#dc3545',
        cancelButtonColor: '#6c757d',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            // 显示删除中的加载提示
            showLoading('加载中...');

            var xhr = new XMLHttpRequest();
            var timeout = setTimeout(function() {
                xhr.abort();
                hideLoading();
                showError();
            }, 15000);

            xhr.open('POST', '/email/body/delete', true);
            xhr.setRequestHeader('Content-Type', 'application/json');
            xhr.setRequestHeader('X-CSRF-TOKEN', document.querySelector('meta[name="_csrf"]').getAttribute('content'));

            xhr.onreadystatechange = function() {
                if (xhr.readyState === 4) {
                    clearTimeout(timeout);
                    hideLoading();

                    if (xhr.status === 200) {
                        var response = JSON.parse(xhr.responseText);
                        if (response.success) {
                            Swal.fire({
                                icon: 'success',
                                title: '操作成功',
                                confirmButtonColor: '#28a745',
                                timer: 2000,
                                timerProgressBar: true
                            }).then(() => {
                                loadEmailRecords();
                            });
                        } else {
                            showError();
                        }
                    } else {
                       showError();
                    }
                }
            };

            var requestData = {
                id: recordId
            };
            xhr.send(JSON.stringify(requestData));
        }
    });
}

function showError(){
    Swal.fire({
        title: '操作失败',
        text: i18n.common_network_error || '网络错误，请重试',
        icon: 'error',
        confirmButtonColor: '#ff6b6b'
    });
}
