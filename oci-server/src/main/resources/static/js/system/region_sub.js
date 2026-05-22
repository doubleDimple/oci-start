let csrfToken, csrfHeaderName;
let availableRegions = [];
let selectedRegions = [];
const i18n = window.I18N;
document.addEventListener('DOMContentLoaded', function() {
    csrfToken = document.querySelector('meta[name="_csrf"]').content;
    csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;
    initializePage();
    loadSubscribedRegions();
    loadRegionSummary();

    // 初始化侧边栏
    var navParents = document.querySelectorAll('.nav-parent');
    navParents.forEach(function(parent) {
        var parentLink = parent.querySelector('.nav-link');
        parentLink.addEventListener('click', function(e) {
            e.preventDefault();
            parent.classList.toggle('expanded');
        });
    });

    // 展开当前活动菜单
    var activeLink = document.querySelector('.nav-link.active');
    if (activeLink) {
        var parent = activeLink.closest('.nav-parent');
        if (parent) {
            parent.classList.add('expanded');
        }
    }

    // 点击模态框外部关闭
    document.querySelectorAll('.modal-overlay').forEach(function(modal) {
        modal.addEventListener('click', function(e) {
            if (e.target === modal) {
                modal.style.display = 'none';
            }
        });
    });
});

function initializePage() {
    console.log('当前租户ID:', currentTenantId);
    console.log('已订阅区域数量:', subscribedRegions);
}

function loadRegionSummary() {
    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/tenants/region-summary?tenantId=' + currentTenantId, true);

    var token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                var data = JSON.parse(xhr.responseText);
                updateSummaryCards(data);
            } catch (error) {
                console.error('解析摘要数据失败:', error);
                // 使用默认值
                updateSummaryCards({
                    totalRegions: '--',
                    subscribedRegions: subscribedRegions,
                    unsubscribedRegions: '--'
                });
            }
        }
    };

    xhr.onerror = function() {
        console.error('加载摘要数据失败');
        updateSummaryCards({
            totalRegions: '--',
            subscribedRegions: subscribedRegions,
            unsubscribedRegions: '--'
        });
    };

    xhr.send();
}

// 更新摘要卡片
function updateSummaryCards(data) {
    if (data) {
        document.getElementById('totalRegions').textContent = data.totalRegions || '--';
        document.getElementById('subscribedRegions').textContent = data.subscribedRegions || subscribedRegions;
        document.getElementById('unsubscribedRegions').textContent = data.unsubscribedRegions || '--';
    }
}

// 切换标签页
function switchTab(tabName) {
    // 更新标签按钮状态
    document.querySelectorAll('.tab').forEach(tab => tab.classList.remove('active'));
    event.target.classList.add('active');
    document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));
    document.getElementById(tabName + 'Tab').classList.add('active');
    if (tabName === 'available') {
        loadAvailableRegions();
    }
}

// 加载可订阅区域
function loadAvailableRegions() {
    var tbody = document.getElementById('availableRegionsTable');
    tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; padding: 20px;"><span class="loading-spinner"></span>'+i18n.sub_regionLoading+'...</td></tr>';

    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/tenants/unsubscribed-regions?tenantId=' + currentTenantId, true);

    var token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                var regions = JSON.parse(xhr.responseText);
                availableRegions = regions;
                updateAvailableRegionsTable(regions);

                // 更新摘要信息
                document.getElementById('unsubscribedRegions').textContent = regions.length;
            } catch (error) {
                tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--accent-red);">加载可订阅区域失败</td></tr>';
            }
        } else {
            tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--accent-red);">加载可订阅区域失败</td></tr>';
        }
    };

    xhr.onerror = function() {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: var(--accent-red);">网络错误，加载失败</td></tr>';
    };

    xhr.send();
}

// 更新可订阅区域表格
function updateAvailableRegionsTable(regions) {
    var tbody = document.getElementById('availableRegionsTable');
    tbody.innerHTML = '';

    if (regions.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; padding: 20px;">所有区域都已订阅</td></tr>';
        return;
    }

    regions.forEach(function(region) {
        var tr = document.createElement('tr');
        tr.innerHTML =
            '<td>' +
            '<input type="checkbox" class="region-checkbox" value="' + region.key + '" onchange="updateSelection()">' +
            '</td>' +
            '<td>' + region.key + '</td>' +
            '<td>' + region.name + '</td>' +
            '<td>' + region.cnName + '</td>' +
            '<td>' +
            '<div class="btn-group">' +
            '<button class="btn btn-success" onclick="subscribeToRegion(\'' + region.key + '\')" title="订阅此区域">' +
            '<i class="fas fa-plus"></i>' +
            '</button>' +
            '</div>' +
            '</td>';
        tbody.appendChild(tr);
    });
}
function updateSelection() {
    var checkboxes = document.querySelectorAll('.region-checkbox:checked');
    selectedRegions = Array.from(checkboxes).map(function(cb) { return cb.value; });

    document.getElementById('selectedCount').textContent = selectedRegions.length;

    var batchActions = document.getElementById('batchActions');
    if (selectedRegions.length > 0) {
        batchActions.classList.add('visible');
    } else {
        batchActions.classList.remove('visible');
    }

    // 更新全选状态
    var selectAll = document.getElementById('selectAll');
    var allCheckboxes = document.querySelectorAll('.region-checkbox');
    selectAll.checked = allCheckboxes.length > 0 && selectedRegions.length === allCheckboxes.length;
}

// 切换全选
function toggleSelectAll() {
    var selectAll = document.getElementById('selectAll');
    var checkboxes = document.querySelectorAll('.region-checkbox');

    checkboxes.forEach(function(cb) {
        cb.checked = selectAll.checked;
    });

    updateSelection();
}

// 清除选择
function clearSelection() {
    document.querySelectorAll('.region-checkbox').forEach(cb => {
        cb.checked = false;
    });
    document.getElementById('selectAll').checked = false;
    updateSelection();
}

// 订阅单个区域
function subscribeToRegion(regionKey) {
    Swal.fire({
        title: i18n.common_confirm,
        text: i18n.sub_subConfirm+' ' + regionKey + ' ？',
        icon: 'question',
        showCancelButton: true,
        confirmButtonColor: 'var(--accent-green)',
        cancelButtonColor: 'var(--accent-red)',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then(function(result) {
        if (result.isConfirmed) {
            performSubscription([regionKey]);
        }
    });
}

// 批量订阅区域
function batchSubscribeRegions() {
    if (selectedRegions.length === 0) {
        return;
    }

    Swal.fire({
        title: i18n.sub_subConfirmBatch,
        icon: 'question',
        showCancelButton: true,
        confirmButtonColor: 'var(--accent-green)',
        cancelButtonColor: 'var(--accent-red)',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then(function(result) {
        if (result.isConfirmed) {
            performSubscription(selectedRegions);
        }
    });
}

// 执行订阅操作
function performSubscription(regionKeys) {
    var modal = document.getElementById('subscriptionModal');
    var progressBar = document.getElementById('progressBar');
    var statusMessage = document.getElementById('statusMessage');
    var statusText = document.getElementById('statusText');

    modal.style.display = 'flex';
    progressBar.style.width = '0%';
    statusMessage.className = 'status-message syncing';
    statusText.innerHTML = '<span class="loading-spinner"></span>'+i18n.sub_subing+'... 0%';

    var progress = 0;
    var totalRegions = regionKeys.length;
    var progressIncrement = 100 / totalRegions;

    // 发送订阅请求
    var xhr = new XMLHttpRequest();
    xhr.open('POST', '/tenants/subscribe-regions', true);
    xhr.setRequestHeader('Content-Type', 'application/json');

    var token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);
    var progressInterval = setInterval(function() {
        progress += progressIncrement;
        if (progress >= 95) {
            clearInterval(progressInterval);
        } else {
            progressBar.style.width = progress + '%';
            statusText.innerHTML = '<span class="loading-spinner"></span>'+i18n.sub_subing+'... ' + Math.round(progress) + '%';
        }
    }, 1000);

    xhr.onload = function() {
        clearInterval(progressInterval);

        if (xhr.status === 200) {
            try {
                var result = JSON.parse(xhr.responseText);

                progressBar.style.width = '100%';
                statusMessage.className = 'status-message success';
                statusText.textContent = 'successful';

                // 显示详细结果
                if (result.details) {
                    var detailsDiv = document.getElementById('subscriptionDetails');
                    var detailsList = document.getElementById('subscriptionDetailsList');

                    detailsList.innerHTML = '';
                    result.details.forEach(function(detail) {
                        var item = document.createElement('div');
                        item.className = 'subscription-detail-item';

                        var color = detail.success ? 'var(--accent-green)' : 'var(--accent-red)';
                        var icon = detail.success ? '✓' : '✗';

                        item.innerHTML = '<span style="color: ' + color + ';">' +
                            icon + ' ' + detail.regionKey + ': ' + detail.message +
                            '</span>';

                        detailsList.appendChild(item);
                    });

                    detailsDiv.style.display = 'block';
                }

                setTimeout(function() {
                    modal.style.display = 'none';
                    location.reload();
                }, 3000);

            } catch (error) {
                showSubscriptionError('error');
            }
        } else {
            showSubscriptionError('error');
        }
    };

    xhr.onerror = function() {
        clearInterval(progressInterval);
        showSubscriptionError('error');
    };

    xhr.send(JSON.stringify({
        tenantId: currentTenantId,
        regionKeys: regionKeys
    }));
}



// 显示订阅错误
function showSubscriptionError(message) {
    var statusMessage = document.getElementById('statusMessage');
    var statusText = document.getElementById('statusText');

    statusMessage.className = 'status-message error';
    statusText.textContent = message;

    setTimeout(function() {
        document.getElementById('subscriptionModal').style.display = 'none';
    }, 3000);
}

// 刷新区域摘要
function refreshRegionSummary() {
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => {
            Swal.showLoading();
        }
    });

    loadRegionSummary();

    setTimeout(function() {
        Swal.close();
        location.reload();
    }, 2000);
}

// 显示可订阅区域
function showAvailableRegions() {
    // 切换到可订阅区域标签页
    document.querySelectorAll('.tab').forEach(tab => tab.classList.remove('active'));
    document.querySelectorAll('.tab')[1].classList.add('active');

    document.querySelectorAll('.tab-content').forEach(content => content.classList.remove('active'));
    document.getElementById('availableTab').classList.add('active');

    loadAvailableRegions();
}

// 显示区域详情
function showRegionDetails(regionKey) {
    Swal.fire({
        title: i18n.sub_regionDetail,
        text: i18n.sub_regionFlag+': ' + regionKey,
        icon: 'info',
        confirmButtonColor: 'var(--accent-blue)'
    });
}

// 检查订阅状态
function checkSubscriptionStatus(regionKey) {
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: function() {
            Swal.showLoading();
        }
    });

    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/tenants/check-subscription-status?tenantId=' + currentTenantId + '&regionKey=' + regionKey, true);

    var token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                var result = JSON.parse(xhr.responseText);

                Swal.fire({
                    title: 'success',
                    text:  regionKey + ' : ' + result.status,
                    icon: result.status === 'READY' ? 'success' : 'info',
                    confirmButtonColor: 'var(--accent-green)'
                }).then(function() {
                    if (result.status === 'READY') {
                        location.reload();
                    }
                });
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

    xhr.send();
}


function showError(){
    Swal.fire({
        title: 'error',
        text: i18n.common_network_error,
        icon: 'error',
        confirmButtonColor: '#ff6b6b'
    });
}

function loadSubscribedRegions() {
    const tbody = document.getElementById('subscribedRegionsTable');

    var xhr = new XMLHttpRequest();
    xhr.open('GET', '/tenants/subscribed-regions-data?tenantId=' + currentTenantId, true);

    var token = document.querySelector('input[name="_csrf"]').value;
    xhr.setRequestHeader('X-CSRF-TOKEN', token);

    xhr.onload = function() {
        if (xhr.status === 200) {
            try {
                const regions = JSON.parse(xhr.responseText);

                // 1. 渲染表格
                renderSubscribedTable(regions);

                // 2. 更新摘要卡片的数字 (对应 id="subscribedRegions")
                const summaryVal = document.getElementById('subscribedRegions');
                if(summaryVal) summaryVal.textContent = regions.length;

                // 3. 更新 Tab 上的文字 (对应你 FTL 里的第一个 .tab)
                // 建议给 FTL 里的 Tab 内部文字加个 id，如果没有加，就这样写：
                const subTab = document.querySelector('.tab.active');
                if(subTab) {
                    // 使用之前 I18N 映射里的 key，保持图标
                    subTab.innerHTML = `<i class="fas fa-check-circle"></i> ${i18n.sub_subAlreadyRegion || '已订阅'} (${regions.length})`;
                }

            } catch (e) {
                console.error(e);
                tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: red;">Data Parse Error</td></tr>';
            }
        } else {
            tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; color: red;">Failed to load data</td></tr>';
        }
    };
    xhr.send();
}

function renderSubscribedTable(regions) {
    const tbody = document.getElementById('subscribedRegionsTable');
    tbody.innerHTML = '';

    if (regions.length === 0) {
        tbody.innerHTML = '<tr><td colspan="5" style="text-align: center; padding: 20px;">' + i18n.sub_noSub + '</td></tr>';
        return;
    }

    regions.forEach(sub => {
        const tr = document.createElement('tr');
        const statusClass = sub.status.value.toLowerCase().replace('_', '-');
        const homeClass = sub.isHomeRegion ? 'is-home' : 'not-home';
        const homeText = sub.isHomeRegion ? 'YES' : 'NO';

        let actionHtml = `
            <div class="btn-group">
                <button class="btn btn-info" onclick="showRegionDetails('${sub.regionKey}')"><i class="fas fa-info"></i></button>
        `;
        if (sub.status.value !== "READY") {
            actionHtml += `<button class="btn btn-primary" onclick="checkSubscriptionStatus('${sub.regionKey}')"><i class="fas fa-sync"></i></button>`;
        }
        actionHtml += `</div>`;

        tr.innerHTML = `
            <td>${sub.regionKey}</td>
            <td>${sub.regionName}</td>
            <td><span class="status-badge status-${statusClass}">${sub.status.value}</span></td>
            <td><span class="home-region-badge ${homeClass}">${homeText}</span></td>
            <td>${actionHtml}</td>
        `;
        tbody.appendChild(tr);
    });
}
