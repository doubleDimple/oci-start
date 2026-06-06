
let csrfToken = document.querySelector('meta[name="_csrf"]').content;
let csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;
let currentPage = 1;
let pageSize = 10;
let totalPages = 0;
const i18n = window.I18N;

document.addEventListener('DOMContentLoaded', function() {

    // 侧边栏菜单展开/收起
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

    loadProxyList(1);

    document.querySelectorAll('.view-toggle .btn').forEach(btn => {
        btn.addEventListener('click', function() {
            switchView(this.getAttribute('data-view'));
        });
    });
});

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

function loadProxyList(pageNum) {
    currentPage = pageNum;
    const requestData = {
        pageNumber: pageNum,
        pageSize: pageSize
    };

    fetch('/vpnProxy/pageList', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrfHeaderName]: csrfToken
        },
        body: JSON.stringify(requestData)
    })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                const pageData = data.data;
                totalPages = pageData.totalPages;
                renderTableView(pageData.content);
                //renderGridView(pageData.content);
                renderPagination(pageNum, totalPages);
            } else {
                Swal.fire({ title: '错误', text: data.message || '加载失败', icon: 'error' });
            }
        })
        .catch(error => {
            console.error('加载失败:', error);
            Swal.fire({ title: '错误', text: '加载失败', icon: 'error' });
        });
}



function renderGridView(data) {
    const gridView = document.getElementById('gridView');
    if (!data || data.length === 0) {
        gridView.innerHTML = '';
        return;
    }

    let html = '';
    for (let i = 0; i < data.length; i++) {
        const record = data[i];
        const statusHtml = record.availableStatus === 1
            ? '<span class="status-badge status-running"><i class="fas fa-check-circle"></i> '+i18n.common_available+'</span>'
            : '<span class="status-badge status-offline"><i class="fas fa-times-circle"></i> '+i18n.common_noAvailable+'</span>';

        const username = record.proxyUsername || '-';
        const password = record.proxyPassword || '';

        html += '<div class="instance-card">';
        html += '<div class="instance-card-header">';
        html += '<div class="instance-icon"><i class="fas fa-network-wired"></i></div>';
        html += '<div class="instance-title">';
        html += '<div class="instance-name">' + record.proxyType + '</div>';
        html += '<div class="instance-id">' + record.proxyHost + '</div>';
        html += '</div>';
        html += '</div>';
        html += '<div class="instance-content">';
        html += '<div class="instance-info-item"><span class="info-label">'+i18n.vpn_port+':</span><span class="info-value">' + record.proxyPort + '</span></div>';
        html += '<div class="instance-info-item"><span class="info-label">'+i18n.vpn_name+':</span><span class="info-value">' + username + '</span></div>';
        html += '<div class="instance-info-item"><span class="info-label">'+i18n.vpn_pass+':</span><span class="info-value"><span class="password-field" data-password="' + password + '" onclick="togglePassword(this)">********</span></span></div>';
        html += '<div class="instance-info-item"><span class="info-label">'+i18n.vpn_status+':</span><span class="info-value">' + statusHtml + '</span></div>';
        html += '</div>';
        html += '<div class="instance-actions">';
        html += '<button class="btn btn-primary btn-icon" onclick="openEditModal(' + record.id + ', \'' + record.proxyType + '\', \'' + record.proxyHost + '\', ' + record.proxyPort + ', \'' + (record.proxyUsername || '') + '\', \'' + (record.proxyPassword || '') + '\', ' + record.availableStatus + ')"><i class="fas fa-edit"></i></button>';
        html += '<button class="btn btn-danger btn-icon" onclick="handleDelete(' + record.id + ')"><i class="fas fa-trash"></i></button>';
        html += '</div>';
        html += '</div>';
    }

    gridView.innerHTML = html;
}

function renderPagination(currentPageNum, total) {
    const paginationDiv = document.getElementById('pagination');
    if (total <= 1) {
        paginationDiv.innerHTML = '';
        return;
    }

    let html = '';

    if (currentPageNum > 1) {
        html += '<button class="btn btn-secondary" onclick="loadProxyList(1)"><i class="fas fa-step-backward"></i></button>';
        html += '<button class="btn btn-secondary" onclick="loadProxyList(' + (currentPageNum - 1) + ')"><i class="fas fa-chevron-left"></i></button>';
    }

    for (let i = 1; i <= total; i++) {
        if (i === currentPageNum) {
            html += '<button class="btn active">' + i + '</button>';
        } else if (i <= 3 || i >= total - 2 || (i >= currentPageNum - 2 && i <= currentPageNum + 2)) {
            html += '<button class="btn" onclick="loadProxyList(' + i + ')">' + i + '</button>';
        } else if (i === 4 || i === total - 3) {
            html += '<span style="padding: 0 5px;">...</span>';
        }
    }

    if (currentPageNum < total) {
        html += '<button class="btn btn-secondary" onclick="loadProxyList(' + (currentPageNum + 1) + ')"><i class="fas fa-chevron-right"></i></button>';
        html += '<button class="btn btn-secondary" onclick="loadProxyList(' + total + ')"><i class="fas fa-step-forward"></i></button>';
    }

    paginationDiv.innerHTML = html;
}

function refreshProxyModalSelects() {
    if (typeof CustomSelect === 'undefined') return;
    CustomSelect.refresh(document.getElementById('proxyType'));
    CustomSelect.refresh(document.getElementById('availableStatus'));
}

function openAddModal() {
    const modal = document.getElementById('proxyModal');
    document.getElementById('proxyForm').reset();
    document.getElementById('proxyId').value = '';
    document.getElementById('modalTitle').textContent = '新增代理';
    refreshProxyModalSelects();
    modal.style.display = 'flex';
    setTimeout(() => { modal.style.opacity = '1'; }, 50);
}

function openEditModal(id, proxyType, proxyHost, proxyPort, proxyUsername, proxyPassword, availableStatus) {
    const modal = document.getElementById('proxyModal');
    document.getElementById('proxyId').value = id;
    document.getElementById('proxyType').value = proxyType;
    document.getElementById('proxyHost').value = proxyHost;
    document.getElementById('proxyPort').value = proxyPort;
    document.getElementById('proxyUsername').value = proxyUsername || '';
    document.getElementById('proxyPassword').value = proxyPassword || '';
    document.getElementById('availableStatus').value = availableStatus;
    document.getElementById('modalTitle').textContent = i18n.vpn_edit;
    refreshProxyModalSelects();
    modal.style.display = 'flex';
    setTimeout(() => { modal.style.opacity = '1'; }, 50);
}

function closeProxyModal() {
    const modal = document.getElementById('proxyModal');
    modal.style.opacity = '0';
    setTimeout(() => { modal.style.display = 'none'; }, 300);
}

function handleSaveProxy(event) {
    event.preventDefault();

    const proxyId = document.getElementById('proxyId').value;
    const proxyType = document.getElementById('proxyType').value;
    const proxyHost = document.getElementById('proxyHost').value;
    const proxyPort = document.getElementById('proxyPort').value;
    const proxyUsername = document.getElementById('proxyUsername').value;
    const proxyPassword = document.getElementById('proxyPassword').value;
    const availableStatus = document.getElementById('availableStatus').value;

    if (!proxyType || !proxyHost || !proxyPort) {
        Swal.fire({ title: 'error', text: i18n.common_plzInputGlobalRequired, icon: 'warning', confirmButtonColor: '#ff9800' });
        return;
    }

    if (proxyPort < 1 || proxyPort > 65535) {
        Swal.fire({ title: 'error', text: i18n.common_portRange, icon: 'warning', confirmButtonColor: '#ff9800' });
        return;
    }

    const requestData = {
        id: proxyId ? parseInt(proxyId) : null,
        proxyType: proxyType,
        proxyHost: proxyHost,
        proxyPort: parseInt(proxyPort),
        proxyUsername: proxyUsername || null,
        proxyPassword: proxyPassword || null,
        availableStatus: parseInt(availableStatus)
    };
    fetch('/vpnProxy/saveOrUpdate', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrfHeaderName]: csrfToken
        },
        body: JSON.stringify(requestData)
    })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                closeProxyModal();
                loadProxyList(1);
            } else {
                throw new Error(data.message || 'error');
            }
        })
        .catch(error => {
            Swal.fire({ title: 'error', text: error.message, icon: 'error', confirmButtonColor: '#ff6b6b' });
        });
}

function handleDelete(id) {
    Swal.fire({
        title: i18n.vpn_isDelete,
        //text: '此操作不可恢复。',
        icon: 'warning',
        showCancelButton: true,
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel,
        reverseButtons: true,
        confirmButtonColor: '#ff6b6b',
        cancelButtonColor: '#6c757d'
    }).then(result => {
        if (result.isConfirmed) {

            const requestData = { id: id };

            fetch('/vpnProxy/delete', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify(requestData)
            })
                .then(response => response.json())
                .then(data => {
                    if (data.success) {
                        loadProxyList(1)
                    } else {
                        throw new Error(data.message || 'error');
                    }
                })
                .catch(error => {
                    Swal.fire({ title: 'error', text: error.message, icon: 'error', confirmButtonColor: '#ff6b6b' });
                });
        }
    });
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

function renderTableView(data) {
    const tbody = document.getElementById('tableBody');
    if (!data || data.length === 0) {
        tbody.innerHTML = '<tr><td colspan="7" style="text-align: center; padding: 30px;">'
            + '<i class="fas fa-inbox" style="font-size: 24px; color: var(--text-secondary); margin-right: 10px;"></i>'
            + '<span style="color: var(--text-secondary);">'+i18n.common_noData+'</span></td></tr>';
        return;
    }

    let html = '';
    for (let i = 0; i < data.length; i++) {
        const record = data[i];
        const statusHtml = record.availableStatus === 1
            ? '<span class="status-badge status-running"><i class="fas fa-check-circle"></i> '+i18n.common_available+'</span>'
            : '<span class="status-badge status-offline"><i class="fas fa-times-circle"></i> '+i18n.common_noAvailable+'</span>';

        const username = record.proxyUsername || '-';
        const password = record.proxyPassword || '';

        html += '<tr>';
        html += '<td>' + record.proxyType + '</td>';
        html += '<td><span class="truncate" title="' + record.proxyHost + '">' + record.proxyHost + '</span></td>';
        html += '<td>' + record.proxyPort + '</td>';
        html += '<td><span class="truncate" title="' + username + '">' + username + '</span></td>';
        html += '<td><span class="password-field" data-password="' + password + '" onclick="togglePassword(this)">********</span></td>';
        html += '<td>' + statusHtml + '</td>';
        const editArgs = record.id + ", '"
            + record.proxyType + "', '"
            + record.proxyHost + "', "
            + record.proxyPort + ", '"
            + (record.proxyUsername || '') + "', '"
            + (record.proxyPassword || '') + "', "
            + record.availableStatus;
        html += '<td>';
        html += '  <div class="dropdown">';
        html += '    <button class="btn btn-primary btn-icon dropdown-toggle" onclick="handleDynamicToggle(this, event)">';
        html += '      <i class="fas fa-ellipsis-h"></i>';
        html += '    </button>';
        html += '    <div class="dropdown-panel">';
        html += '      <button class="dropdown-item" onclick="openEditModal(' + editArgs + ')">';
        html += '        <i class="fas fa-edit"></i><span>' + i18n.vpn_edit + '</span>';
        html += '      </button>';
        html += '      <button class="dropdown-item" onclick="handleDelete(' + record.id + ')">';
        html += '        <i class="fas fa-trash"></i><span>' + i18n.common_delete + '</span>';
        html += '      </button>';
        html += '    </div>';
        html += '  </div>';
        html += '</td>';
        html += '</tr>';
    }
    tbody.innerHTML = html;
}

