let csrfToken, csrfHeaderName;
const i18n = window.I18N;

// 全局变量
let selectedTenantId = "";
let selectedRegionId = "";

document.addEventListener('DOMContentLoaded', function() {

    csrfToken = document.querySelector('meta[name="_csrf"]').content;
    csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;
    loadTenants();

    // 根据URL参数初始化选择
    const urlParams = new URLSearchParams(window.location.search);
    const tenantId = urlParams.get('tenantId');

    if (tenantId) {
        selectedTenantId = tenantId;
    }

    document.querySelectorAll('.nav-parent > .nav-link').forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            const parent = this.parentElement;
            parent.classList.toggle('expanded');
        });
    });

    const activeNavItem = document.querySelector('.nav-link.active');
    if (activeNavItem) {
        const parent = activeNavItem.closest('.nav-parent');
        if (parent) parent.classList.add('expanded');
    }

    document.querySelectorAll('.truncate').forEach(element => {
        const fullText = element.getAttribute('data-fulltext');
        if (fullText && fullText.length > 15) {
            element.textContent = fullText.substring(0, 15) + '...';

            element.addEventListener('click', function() {
                const isExpanded = this.getAttribute('data-expanded') === 'true';
                this.textContent = isExpanded ?
                    (fullText.length > 15 ? fullText.substring(0, 15) + '...' : fullText) :
                    fullText;
                this.setAttribute('data-expanded', !isExpanded);
            });
        }
    });

    // 眼睛按钮：绑定全局显示/隐藏租户名
    var spoilerBtn = document.getElementById('spoilerToggleBtn');
    if (spoilerBtn) {
        spoilerBtn.addEventListener('click', function(e) {
            e.stopPropagation();
            toggleAllSpoilers();
        });
    }
    // 各行名称点击单独切换
    document.querySelectorAll('.name-spoiler').forEach(function(el) {
        el.addEventListener('click', function(e) {
            e.stopPropagation();
            toggleSpoiler(this);
        });
    });
});

function showToast(message, duration = 3000) {
    const existingToast = document.querySelector('.toast');
    if (existingToast) existingToast.remove();

    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;
    document.body.appendChild(toast);

    setTimeout(() => {
        toast.style.opacity = '0';
        setTimeout(() => toast.remove(), 300);
    }, duration);
}

function handleStart(id) {
    // 在 Swal 调用前获取按钮元素
    const button = event.target.closest('button');
    const icon = button.querySelector('i');
    const originalClass = icon.className;

    Swal.fire({
        title: i18n.common_confirm,
        icon: 'question',
        showCancelButton: true,
        confirmButtonColor: '#3085d6',
        cancelButtonColor: '#d33',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (!result.isConfirmed) return;

        // 使用之前获取的引用
        button.disabled = true;
        icon.className = 'fas fa-spinner fa-spin';

        fetch(`/boot/startBoot?bootId=`+encodeURIComponent(id))
            .then(response => response.json())
            .then(data => {
                Swal.fire({
                    title: data.success ? 'success' : 'error',
                    text: data.success ? 'success' : 'error',
                    icon: data.success ? 'success' : 'error',
                    timer: 1500,
                    showConfirmButton: false
                });

                if (data.success) {
                    setTimeout(() => location.reload(), 1500);
                }
            })
            .catch(() => {
                Swal.fire({
                    title: 'error',
                    icon: 'error',
                    timer: 1500,
                    showConfirmButton: false
                });
            })
            .finally(() => {
                button.disabled = false;
                icon.className = originalClass;
            });
    });
}


function handleCloneStart(id) {
    // 在 Swal 调用前获取按钮元素
    const button = event.target.closest('button');
    const icon = button.querySelector('i');
    const originalClass = icon.className;

    Swal.fire({
        title: i18n.common_confirm,
        icon: 'question',
        showCancelButton: true,
        confirmButtonColor: '#3085d6',
        cancelButtonColor: '#d33',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (!result.isConfirmed) return;

        // 使用之前获取的引用
        button.disabled = true;
        icon.className = 'fas fa-spinner fa-spin';

        fetch(`/boot/startCloneBoot?bootId=`+encodeURIComponent(id))
            .then(response => response.json())
            .then(data => {
                Swal.fire({
                    title: data.success ? 'success' : 'error',
                    text: data.success ? 'successful' : 'error',
                    icon: data.success ? 'success' : 'error',
                    timer: 1500,
                    showConfirmButton: false
                });

                if (data.success) {
                    setTimeout(() => location.reload(), 1500);
                }
            })
            .catch(() => {
                Swal.fire({
                    title: 'error',
                    icon: 'error',
                    timer: 1500,
                    showConfirmButton: false
                });
            })
            .finally(() => {
                button.disabled = false;
                icon.className = originalClass;
            });
    });
}

function handleStop(id) {
    // 在 Swal 调用前就获取按钮元素
    const button = event.target.closest('button');
    const icon = button.querySelector('i');
    const originalClass = icon.className;

    Swal.fire({
        title: i18n.common_confirm,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#3085d6',
        cancelButtonColor: '#d33',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (!result.isConfirmed) return;

        // 直接使用之前获取的引用
        button.disabled = true;
        icon.className = 'fas fa-spinner fa-spin';

        fetch(`/boot/stopBoot?bootId=`+encodeURIComponent(id))
            .then(response => response.json())
            .then(data => {
                Swal.fire({
                    title: data.success ? 'success' : 'error',
                    text: data.success ? 'successful' : 'error',
                    icon: data.success ? 'success' : 'error',
                    timer: 1500,
                    showConfirmButton: false
                });

                if (data.success) {
                    setTimeout(() => location.reload(), 1500);
                }
            })
            .catch(() => {
                Swal.fire({
                    title: 'error',
                    icon: 'error',
                    timer: 1500,
                    showConfirmButton: false
                });
            })
            .finally(() => {
                button.disabled = false;
                icon.className = originalClass;
            });
    });
}

function handleDelete(id) {
    const button = event.target.closest('button');
    const icon = button.querySelector('i');
    const originalClass = icon.className;

    // 直接显示“正在删除”，跳过确认步骤
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });
    button.disabled = true;
    icon.className = 'fas fa-spinner fa-spin';

    fetch(`/boot/deleteBoot?bootId=` + encodeURIComponent(id))
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                // 成功提示并自动刷新
                showSuccess();
                setTimeout(() => location.reload(), 1000);
            } else {
                throw new Error(data.message || 'error');
            }
        })
        .catch((error) => {
            Swal.fire('error', 'error', 'error');
        })
        .finally(() => {
            button.disabled = false;
            icon.className = originalClass;
        });
}

// 新增：开机详情相关函数
function openDetailModal(id) {
    window.currentDetailBootId = id;

    const modal = document.getElementById('detailModal');
    const detailContent = document.getElementById('detailContent');

    // 显示加载状态
    detailContent.innerHTML = '<div style="text-align: center; padding: 20px;">' +
        '<i class="fas fa-spinner fa-spin" style="font-size: 24px; color: var(--accent-blue);"></i>' +
        '<p style="margin-top: 10px;">loading...</p>' +
        '</div>';

    modal.style.display = 'flex';
    modal.style.opacity = '0';
    setTimeout(() => {
        modal.style.opacity = '1';
    }, 50);

    // 获取开机详情数据
    loadBootDetail(id);
}

function closeDetailModal() {
    const modal = document.getElementById('detailModal');
    modal.style.opacity = '0';
    setTimeout(() => {
        modal.style.display = 'none';
        modal.style.opacity = '1';
    }, 300);
}

async function loadBootDetail(bootId) {
    try {
        //var csrfToken = document.querySelector('input[name="_csrf"]').value;
        var response = await fetch('/boot/bootDetail?bootId=' + encodeURIComponent(bootId), {
            headers: {
                [csrfHeaderName]: csrfToken
            }
        });

        var result = await response.json();
        var detailContent = document.getElementById('detailContent');

        if (result.success && result.data && result.data.length > 0) {
            // 构建开机详情表格，包含配置信息列
            var tableHtml = '<div class="detail-list">' +
                '<table class="detail-table">' +
                '<thead>' +
                '<tr>' +
                /*'<th>序号</th>' +*/
                '<th>'+i18n.openBoot_yesterday+'</th>' +
                '<th>'+i18n.openBoot_today+'</th>' +
                '<th>'+i18n.openBoot_fail+'</th>' +
                /*'<th>架构</th>' +*/
                '<th>'+i18n.openBoot_os+'</th>' +
                '<th>'+i18n.openBoot_config+'</th>' +
               /* '<th>内存</th>' +
                '<th>磁盘</th>' +*/
                '<th>'+i18n.openBoot_range+'</th>' +
                '<th>'+i18n.openBoot_time+'</th>' +
                '<th>'+i18n.openBoot_rootPass+'</th>' +
                '<th>'+i18n.openBoot_status+'</th>' +
                /*'<th>公网IP</th>' +*/
                '<th>'+i18n.openBoot_startTime+'</th>' +
                '<th>'+i18n.openBoot_action+'</th>' +
                '</tr>' +
                '</thead>' +
                '<tbody>';

            result.data.forEach(function(item, index) {
                var statusText = item.status === 0 ? i18n.openBoot_noOpen :
                    item.status === 1 ? i18n.openBoot_opening : i18n.openBoot_alreadyOpen;
                var statusClass = item.status === 0 ? 'status-offline' :
                    item.status === 1 ? 'status-starting' : 'status-running';

                tableHtml += '<tr>' +
                    '<td>' + (item.yesterdayAttemptCount ?? '-') + '</td>' +
                    '<td>' + (item.currentAttemptCount ?? '-') + '</td>' +
                    '<td>' + (item.failCount ?? '-') + '</td>' +
                    '<td>' + (item.operatingSystem || '-')+ '/' + (item.operatingSystemVersion || '-') + '</td>' +
                    '<td>' + (item.ocpu || '-') + '/' + (item.memory || '-') + '/' + (item.disk || '-') +'/' + (item.architecture || '-')+ '</td>' +
                    '<td>' + (item.dayGap || '-') + '</td>' +
                    '<td>' + (item.loopTime || '-') + '</td>' +
                    '<td>' +
                    '<span class="password-field" onclick="togglePasswordInModal(this)" data-password="' + (item.rootPassword || '') + '">' +
                    '********' +
                    '</span>' +
                    '</td>' +
                    '<td>' +
                    '<span class="status-badge ' + statusClass + '">' +
                    statusText +
                    '</span>' +
                    '</td>' +
                    '<td>' + (item.createdAt || '-') + '</td>' +
                    '<td>' +
                    '<div class="dropdown">' +
                    '<button class="dropdown-toggle btn" onclick="handleDynamicToggle(this, event)">' +
                    '<i class="fas fa-ellipsis-h"></i>' +
                    '</button>' +
                    '<div class="dropdown-panel">' +
                    '<button class="dropdown-item" title="停止开机" onclick="toggleBootStatus(\'' + item.id + '\', 0)">' +
                    '<i class="fas fa-stop"></i><span>'+i18n.openBoot_stopOpen+'</span>' +
                    '</button>' +
                    '<button class="dropdown-item" title="启动开机" onclick="toggleBootStatus(\'' + item.id + '\', 1)">' +
                    '<i class="fas fa-play"></i><span>'+i18n.openBoot_startOpen+'</span>' +
                    '</button>' +
                    '<button class="dropdown-item" title="开机日志" onclick="openBootLogDrawer(\'' + item.id + '\')">' +
                    '<i class="fas fa-file-alt"></i><span>'+i18n.openBoot_log+'</span>' +
                    '</button>' +
                    '<button class="dropdown-item" title="修改" onclick="openEditDetailModal(\'' + item.id + '\', ' +
                    (item.ocpu || 0) + ', ' + (item.memory || 0) + ', ' + (item.disk || 0) + ', ' +
                    (item.loopTime || 0) + ', \'' + (item.rootPassword || '') + '\', \'' + (item.dayGap || '') + '\')">' +
                    '<i class="fas fa-edit"></i><span>'+i18n.openBoot_updateConfig+'</span>' +
                    '</button>' +
                    '<button class="dropdown-item" title="删除" onclick="handleDetailDelete(\'' + item.id + '\')">' +
                    '<i class="fas fa-trash"></i><span>'+i18n.openBoot_delete+'</span>' +
                    '</button>' +
                    '</div>' +
                    '</div>' +
                    '</td>' +
                    '</tr>';
            });

            tableHtml += '</tbody>' +
                '</table>' +
                '</div>';

            detailContent.innerHTML = tableHtml;
        } else {
            detailContent.innerHTML = '<div style="text-align: center; padding: 20px;">' +
                '<i class="fas fa-exclamation-triangle" style="font-size: 24px; color: var(--accent-red);"></i>' +
                '<p style="margin-top: 10px;">'+i18n.openBoot_nDetailData+'</p>' +
                '</div>';
        }
    } catch (error) {
        console.error('加载详情失败:', error);
        var detailContent = document.getElementById('detailContent');
        detailContent.innerHTML = '<div style="text-align: center; padding: 20px;">' +
            '<i class="fas fa-exclamation-triangle" style="font-size: 24px; color: var(--accent-red);"></i>' +
            '<p style="margin-top: 10px;">'+i18n.openBoot_loadingFail+'</p>' +
            '</div>';
    }
}

async function handleDetailDelete(bootId) {
    try {
        const result = await Swal.fire({
            title: i18n.common_confirm,
            icon: 'warning',
            showCancelButton: true,
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel,
            confirmButtonColor: '#ff6b6b',
            cancelButtonColor: '#6c757d',
            reverseButtons: true
        });

        if (!result.isConfirmed) return;

        // 显示加载状态
        Swal.fire({
            title: 'loading',
            allowOutsideClick: false,
            didOpen: () => Swal.showLoading()
        });

        const response = await fetch('/boot/deleteBootDetail?bootId=' + bootId, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            }
        });

        const data = await response.json();

        if (!data.success) {
            throw new Error(data.message || 'error');
        }

       showSuccess();

        await loadDetailByGroup(data.tenantId, data.architecture);

    } catch (error) {
        showError();
    }
}


function togglePasswordInModal(element) {
    const password = element.getAttribute('data-password');
    if (element.textContent === '********') {
        element.textContent = password;
        element.style.userSelect = 'text';
    } else {
        element.textContent = '********';
        element.style.userSelect = 'none';
    }
}

async function loadDetailByGroup(tenantId, architecture) {
    try {
        const response = await fetch('/boot/bootDetailList', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            },
            body: JSON.stringify({
                tenantId: tenantId,
                architecture: architecture
            })
        });

        const res = await response.json();

        if (res.success) {

            const bootId = res.bootId;

            if (bootId) {
                window.currentDetailBootId = bootId;
                loadBootDetail(bootId);
            } else {
                const detailContent = document.getElementById('detailContent');

                detailContent.innerHTML = `
                    <div style="text-align:center;padding:20px;">
                        <i class="fas fa-info-circle" style="font-size:24px;color:var(--accent-blue);"></i>
                        <p style="margin-top:10px;">'+${i18n.openBoot_noDetail}+'</p>
                    </div>
                `;

                setTimeout(() => {
                    location.reload();
                }, 1000);
            }

        } else {
            document.getElementById('detailContent').innerHTML =
                `<div style="padding:20px;text-align:center;">error：${res.message || ''}</div>`;
        }

    } catch (error) {
        console.error('loadDetailByGroup 失败:', error);
    }
}



function openEditDetailModal(detailId, ocpu, memory, disk, loopTime, rootPassword, dayGap) {
    try {
        document.getElementById('editDetailId').value = detailId;
        document.getElementById('editDetailOcpu').value = ocpu || '';
        document.getElementById('editDetailMemory').value = memory || '';
        document.getElementById('editDetailDisk').value = disk || '';
        document.getElementById('editDetailLoopTime').value = loopTime || '';
        document.getElementById('editDetailPassword').value = rootPassword || '';
        document.getElementById('editDetailDayGap').value = dayGap || '';

        const modal = document.getElementById('editDetailModal');
        modal.style.display = 'flex';
        modal.style.opacity = '0';
        setTimeout(() => {
            modal.style.opacity = '1';
        }, 50);
    } catch (error) {
        console.error('打开编辑模态框失败:', error);
       showError();
    }
}

function closeEditDetailModal() {
    const modal = document.getElementById('editDetailModal');
    modal.style.opacity = '0';
    setTimeout(() => {
        modal.style.display = 'none';
        modal.style.opacity = '1';
    }, 300);
}

async function handleEditDetail(event) {
    event.preventDefault();
    const form = event.target;
    const formData = new FormData(form);
    const data = Object.fromEntries(formData.entries());

    const dayGap = (data.dayGap || '').trim();

    if (dayGap) {

        const reg = /^(\d{1,2})-(\d{1,2})$/;
        const match = dayGap.match(reg);

        if (!match) {
            Swal.fire({
                icon: 'warning',
                title: i18n.openBoot_timeForError,
                text: i18n.openBoot_timeForExample
            });
            throw new Error("dayGap 格式错误");
        }

        const start = parseInt(match[1]);
        const end = parseInt(match[2]);

        if (start < 0 || start > 23 || end < 1 || end > 24) {
            Swal.fire({
                icon: 'warning',
                title: i18n.openBoot_timeForError,
                text: i18n.openBoot_timeRangeForExample
            });
            throw new Error("dayGap 范围错误");
        }

        if (start >= end) {
            Swal.fire({
                icon: 'warning',
                title: i18n.openBoot_timeForError,
                text: i18n.openBoot_timeRangeNoSupport
            });
            throw new Error("dayGap 起始时间错误");
        }
    }

    try {
        const submitButton = form.querySelector('button[type="submit"]');
        const originalText = submitButton.textContent;
        submitButton.disabled = true;
        submitButton.innerHTML = '<i class="fas fa-spinner fa-spin"></i> 保存中...';

        //const csrfToken = document.querySelector('input[name="_csrf"]').value;

        const response = await fetch('/boot/updateBoot', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            },
            body: JSON.stringify(data)
        });

        const result = await response.json();

        if (result.success) {
            showSuccess();

            closeEditDetailModal();
            // 重新加载详情数据
            const currentBootId = new URLSearchParams().get('bootId');
            setTimeout(() => location.reload(), 500);
        } else {
            throw new Error(result.message || '修改失败');
        }
    } catch (error) {
        showError();
        const submitButton = form.querySelector('button[type="submit"]');
        submitButton.disabled = false;
        submitButton.textContent = i18n.common_save;
    }
}

// Close modal when clicking outside
document.getElementById('detailModal').addEventListener('click', function(e) {
    if (e.target === this) {
        closeDetailModal();
    }
});

document.getElementById('editDetailModal').addEventListener('click', function(e) {
    if (e.target === this) {
        closeEditDetailModal();
    }
});

async function handleBatchStart() {
    try {
        // 先获取未开机实例的数量
        const countResponse = await fetch('/boot/getOfflineCount');
        const countData = await countResponse.json();

        if (!countData.count || countData.count === 0) {
            return;
        }

        const result = await Swal.fire({
            title: i18n.common_confirm,
            icon: 'question',
            showCancelButton: true,
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel,
            confirmButtonColor: '#1abc9c',
            cancelButtonColor: '#6c757d',
            reverseButtons: true
        });

        if (!result.isConfirmed) return;

        // 显示加载状态
        Swal.fire({
            title: 'loading',
            allowOutsideClick: false,
            didOpen: () => {
                Swal.showLoading();
            }
        });

        const response = await fetch('/boot/batchStart', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            }
        });

        const data = await response.json();

        if (data.success) {
            showSuccess();
            location.reload();
        } else {
            throw new Error(data.message || 'error');
        }
    } catch (error) {
        showError();
    }
}

async function handleBatchStop() {
    try {
        // 先获取开机中实例的数量
        const countResponse = await fetch('/boot/getStartingCount');
        const countData = await countResponse.json();

        if (!countData.count || countData.count === 0) {
            return;
        }

        const result = await Swal.fire({
            title: i18n.common_confirm,
            icon: 'warning',
            showCancelButton: true,
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel,
            confirmButtonColor: '#ff6b6b',
            cancelButtonColor: '#6c757d',
            reverseButtons: true
        });

        if (!result.isConfirmed) return;

        // 显示加载状态
        Swal.fire({
            title: 'loading',
            allowOutsideClick: false,
            didOpen: () => {
                Swal.showLoading();
            }
        });

        const response = await fetch('/boot/batchStop', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            }
        });

        const data = await response.json();

        if (data.success) {
            showSuccess();
            location.reload();
        } else {
            throw new Error(data.message || 'error');
        }
    } catch (error) {
        showError();
    }
}

async function handleBatchFail() {
    try {
        const result = await Swal.fire({
            title: i18n.openBoot_batchClearFailCount,
            icon: 'warning',
            showCancelButton: true,
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel,
            confirmButtonColor: '#ff6b6b',
            cancelButtonColor: '#6c757d',
            reverseButtons: true
        });

        if (!result.isConfirmed) return;

        // 显示加载状态
        Swal.fire({
            title: 'loading',
            allowOutsideClick: false,
            didOpen: () => {
                Swal.showLoading();
            }
        });

        const response = await fetch('/boot/batchInitFailCount', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            }
        });

        const data = await response.json();

        if (data.success) {
            showSuccess();
            location.reload();
        } else {
            throw new Error(data.message || 'error');
        }
    } catch (error) {
        showError();
    }
}
async function handleManualBoot(id) {
    try {
        const result = await Swal.fire({
            title: i18n.openBoot_manalConfirm,
            icon: 'question',
            showCancelButton: true,
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel,
            confirmButtonColor: '#1abc9c',
            cancelButtonColor: '#6c757d',
            reverseButtons: true
        });

        if (!result.isConfirmed) return;

        // 显示加载状态
        Swal.fire({
            title: 'loading',
            allowOutsideClick: false,
            didOpen: () => {
                Swal.showLoading();
            }
        });

        const response = await fetch(`/boot/manualBoot?bootId=`+encodeURIComponent(id), {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            }
        });

        const data = await response.json();

        if (data.success) {
            showSuccess();
            location.reload();
        } else {
            throw new Error(data.message || 'error');
        }
    } catch (error) {
        showError();
    }
}

// 加载租户列表
function loadTenants() {
    const tenantSelect = document.getElementById('tenantSelect');

    // 显示加载状态
    tenantSelect.innerHTML = '<option value="">'+i18n.common_loading+'</option>';
    tenantSelect.disabled = true;

    // 获取CSRF令牌
    //const csrfToken = document.querySelector('input[name="_csrf"]').value;

    fetch('/tenants/listParentTenants', {
        headers: {
            [csrfHeaderName]: csrfToken
        }
    })
        .then(response => response.json())
        .then(data => {
            tenantSelect.innerHTML = '<option value="">'+i18n.notification_plzSelectAiTenantName+'</option>';
            tenantSelect.disabled = false;

            data.sort((a, b) => {
                if (a.userName && b.userName) {
                    return a.userName.localeCompare(b.userName);
                }
                return 0;
            });

            data.forEach(tenant => {
                const option = document.createElement('option');
                option.value = tenant.id;
                option.textContent = tenant.userName || tenant.tenancyName || `租户 `+tenant.id;
                tenantSelect.appendChild(option);
            });

            if (selectedTenantId) {
                tenantSelect.value = selectedTenantId;
                if (window.CustomSelect) CustomSelect.refresh(tenantSelect);
                loadRegions();
            }
        })
        .catch(error => {
            console.error('加载租户列表失败:', error);
            tenantSelect.innerHTML = '<option value="">error</option>';
            tenantSelect.disabled = false;
        });
}

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

    //const csrfToken = document.querySelector('input[name="_csrf"]').value;

    fetch('/tenants/listRegions?parentId=' + encodeURIComponent(selectedTenantId), {
        headers: {
            [csrfHeaderName]: csrfToken
        }
    })
        .then(response => response.json())
        .then(data => {
            regionSelect.innerHTML = '<option value="">'+i18n.openBoot_selectRegion+'</option>';
            regionSelect.disabled = false;

            if (data && data.length > 0) {
                if (data.length === 1) {
                    const region = data[0];
                    const option = document.createElement('option');
                    option.value = region.id;
                    option.textContent = region.region || `region `+region.id;
                    regionSelect.appendChild(option);

                    regionSelect.value = region.id;
                    if (window.CustomSelect) CustomSelect.refresh(regionSelect);
                    selectedRegionId = region.id;
                    goToInstanceBtn.disabled = false;
                } else {
                    data.sort((a, b) => {
                        if (a.region && b.region) {
                            return a.region.localeCompare(b.region);
                        }
                        return 0;
                    });

                    data.forEach(region => {
                        const option = document.createElement('option');
                        option.value = region.id;
                        option.textContent = region.region || `区域 `+region.id;
                        regionSelect.appendChild(option);
                    });
                }
            } else {
                regionSelect.innerHTML = '<option value="">'+i18n.openBoot_noRegion+'</option>';
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
    goToInstanceBtn.disabled = !selectedRegionId;
}

// 查看实例
function goToInstances() {
    if (!selectedRegionId) {
        return;
    }

    const form = document.createElement('form');
    form.method = 'GET';
    form.action = '/boot/fullBootList';

    const input = document.createElement('input');
    input.type = 'hidden';
    input.name = 'tenantId';
    input.value = selectedRegionId;

    form.appendChild(input);
    document.body.appendChild(form);
    form.submit();
}

function togglePassword(element) {
    const password = element.getAttribute('data-password');
    if (element.textContent === '********') {
        element.textContent = password;
        element.style.userSelect = 'text';
    } else {
        element.textContent = '********';
        element.style.userSelect = 'none';
    }
}

/**
 * 切换启动/停止状态 (SweetAlert2 版)
 */
async function toggleBootStatus(id, targetStatus) {
    const currentBootId = id;
    const isStart = (targetStatus === 1);
    const actionName = isStart ? i18n.openBoot_startOpen : i18n.openBoot_stopOpen;
    const actionColor = isStart ? '#22c55e' : '#ef4444';

    const result = await Swal.fire({
        title: `${actionName}？`,
        text: isStart ? i18n.openBoot_startBootTask : i18n.openBoot_stopBootTask,
        icon: 'question',
        showCancelButton: true,
        confirmButtonColor: actionColor,
        cancelButtonColor: '#64748b',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel,
        background: '#fff',
        backdrop: `rgba(15, 23, 42, 0.5)`
    });

    if (result.isConfirmed) {
        Swal.fire({
            title: 'loading',
            didOpen: () => { Swal.showLoading(); },
            allowOutsideClick: false
        });

        try {
            const params = new URLSearchParams();
            params.append('id', id);
            params.append('status', targetStatus);

            const response = await fetch('/boot/toggleStatus', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                    'X-Requested-With': 'XMLHttpRequest',
                    [csrfHeaderName]: csrfToken
                },
                body: params
            });

            const apiRes = await response.json();

            if (apiRes.success) {
                // 操作成功提示
                await Swal.fire({
                    icon: 'success',
                    title: `${actionName} success`,
                    timer: 1500,
                    showConfirmButton: false
                });
                await loadBootDetail(currentBootId);
            } else {
                Swal.fire({
                    icon: 'error',
                    title: `error`,
                    text: apiRes.message,
                    confirmButtonColor: '#3b82f6'
                });
            }
        } catch (error) {
            console.error('Operation Error:', error);
            showError();
        }
    }
}

var _allSpoilersVisible = false;

function toggleAllSpoilers() {
    _allSpoilersVisible = !_allSpoilersVisible;
    document.querySelectorAll('.name-spoiler').forEach(function(el) {
        if (_allSpoilersVisible) {
            el.classList.remove('is-hidden');
            el.classList.add('is-visible');
        } else {
            el.classList.remove('is-visible');
            el.classList.add('is-hidden');
        }
    });
    var icon = document.getElementById('spoilerToggleIcon');
    var btn  = document.getElementById('spoilerToggleBtn');
    if (icon) icon.className = _allSpoilersVisible ? 'fas fa-eye-slash' : 'fas fa-eye';
    if (btn)  btn.classList.toggle('active', _allSpoilersVisible);
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

function showSuccess(){
    Swal.fire({
        icon: 'success',
        title: 'successful',
        timer: 1500,
        showConfirmButton: false
    });
}

function showError(){
    Swal.fire({
        icon: 'error',
        title: 'error',
        text: message,
        timer: 1500,
        showConfirmButton: false
    });
}

// =================== 开机日志抽屉 ===================
let bootLogEventSource = null;
let bootLogTaskIdRegex = null;
let bootLogCount = 0;
const BOOT_LOG_MAX_LINES = 1000;

function openBootLogDrawer(bootId) {
    if (!bootId) return;
    const drawer = document.getElementById('bootLogDrawer');
    const bodyEl = document.getElementById('bootLogDrawerBody');
    const emptyEl = document.getElementById('bootLogDrawerEmpty');
    const idLabel = document.getElementById('bootLogDrawerBootId');

    bodyEl.querySelectorAll('.boot-log-line').forEach(function (el) { el.remove(); });
    bootLogCount = 0;
    if (emptyEl) emptyEl.style.display = '';

    idLabel.textContent = '#' + bootId;
    const escaped = String(bootId).replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    bootLogTaskIdRegex = new RegExp('[Tt]ask[Ii]d\\s*[=:：]\\s*' + escaped + '(?![0-9])');

    drawer.classList.add('open');
    drawer.setAttribute('aria-hidden', 'false');

    connectBootLogSSE();
}

function closeBootLogDrawer() {
    const drawer = document.getElementById('bootLogDrawer');
    drawer.classList.remove('open');
    drawer.setAttribute('aria-hidden', 'true');

    disconnectBootLogSSE();
    bootLogTaskIdRegex = null;
}

function connectBootLogSSE() {
    disconnectBootLogSSE();
    setBootLogStatus('connecting');

    try {
        const es = new EventSource('/system/streamLogs?isBootLog=true');
        bootLogEventSource = es;

        es.onopen = function () { setBootLogStatus('connected'); };
        es.onmessage = function (event) {
            const text = event.data;
            if (!text) return;
            if (bootLogTaskIdRegex && bootLogTaskIdRegex.test(text)) {
                appendBootLogLine(text);
            }
        };
        es.onerror = function () { setBootLogStatus('disconnected'); };
    } catch (e) {
        setBootLogStatus('disconnected');
    }
}

function disconnectBootLogSSE() {
    if (bootLogEventSource) {
        try { bootLogEventSource.close(); } catch (e) {}
        bootLogEventSource = null;
    }
}

function setBootLogStatus(state) {
    const statusEl = document.getElementById('bootLogDrawerStatus');
    if (!statusEl) return;
    statusEl.setAttribute('data-state', state);
    const textEl = statusEl.querySelector('.boot-log-drawer__status-text');
    if (textEl) {
        if (state === 'connected') textEl.textContent = '已连接';
        else if (state === 'connecting') textEl.textContent = '连接中';
        else textEl.textContent = '已断开';
    }
}

function appendBootLogLine(rawText) {
    const bodyEl = document.getElementById('bootLogDrawerBody');
    const emptyEl = document.getElementById('bootLogDrawerEmpty');
    if (emptyEl && emptyEl.style.display !== 'none') emptyEl.style.display = 'none';

    let cls = 'boot-log-line';
    let text = rawText;
    if (/\[success]/i.test(text)) { cls += ' boot-log-line--success'; text = text.replace(/\[success]/ig, ''); }
    else if (/\[warn]/i.test(text)) { cls += ' boot-log-line--warn'; text = text.replace(/\[warn]/ig, ''); }
    else if (/\[error]/i.test(text)) { cls += ' boot-log-line--error'; text = text.replace(/\[error]/ig, ''); }

    const div = document.createElement('div');
    div.className = cls;
    div.textContent = text;
    bodyEl.appendChild(div);
    bootLogCount++;

    if (bootLogCount > BOOT_LOG_MAX_LINES) {
        const first = bodyEl.querySelector('.boot-log-line');
        if (first) first.remove();
        bootLogCount--;
    }

    const autoEl = document.getElementById('bootLogAutoScroll');
    if (autoEl && autoEl.checked) {
        bodyEl.scrollTop = bodyEl.scrollHeight;
    }
}