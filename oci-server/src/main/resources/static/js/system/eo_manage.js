let csrfToken, csrfHeaderName;
let currentRecordType = 'dns';
let currentZoneId = '';
let currentZoneName = '';

const i18n = window.I18N;

// 初始化全局变量
function initializeGlobalVariables() {
    csrfToken = document.querySelector('meta[name="_csrf"]').content;
    csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;
}

// 页面加载完成后初始化
document.addEventListener('DOMContentLoaded', function() {
    initializeGlobalVariables();
    const urlParams = new URLSearchParams(window.location.search);
    const typeFromUrl = urlParams.get('type');
    const recordTypeFromBackend = '${recordType!"dns"}';
    currentRecordType = typeFromUrl || recordTypeFromBackend || 'dns';

    console.log('初始化记录类型:', currentRecordType);

    initializePage();
    setupEventListeners();
    setupCustomSelect();
    initializeRecordTypeView(currentRecordType);
    loadAndSelectZone();
    initializeSearchInputs();
});

function loadAndSelectZone() {
    const selectedZoneId = (window.SERVER_CONFIG && window.SERVER_CONFIG.selectedZoneId) || '';
    console.log('准备加载域名列表，URL中的域名ID:', selectedZoneId);

    // 显示加载状态
    showLoading(true);

    loadZones().then((zones) => {
        // 如果URL中有指定的域名ID，尝试选中它
        if (selectedZoneId) {
            const zoneSelect = document.getElementById('zoneSelect');

            // 确保选项存在
            let optionExists = false;
            for (let i = 0; i < zoneSelect.options.length; i++) {
                if (zoneSelect.options[i].value === selectedZoneId) {
                    optionExists = true;
                    break;
                }
            }

            if (optionExists) {
                zoneSelect.value = selectedZoneId;
                console.log('成功选中指定域名:', selectedZoneId);
                currentZoneId = selectedZoneId;

                // 获取域名名称
                const selectedOption = zoneSelect.options[zoneSelect.selectedIndex];
                if (selectedOption) {
                    currentZoneName = selectedOption.dataset.zoneName;
                    console.log('当前域名名称:', currentZoneName);
                }
            } else {
                console.warn('未找到URL中指定的域名，保持默认选中第一个');
                if (zones && zones.length > 0 && currentZoneId) {
                }
            }
        } else {
            if (zones && zones.length > 0) {
                console.log('URL中无指定域名，已默认选中第一个:', currentZoneName);
            }
        }

        showLoading(false);
    }).catch(error => {
        console.error('加载域名列表失败:', error);
        showLoading(false);
    });
}

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

    // 添加加速域名表单提交
    document.getElementById('addDomainForm').addEventListener('submit', function(e) {
        e.preventDefault();
        addAccelerationDomain();
    });

    // 记录类型变化时的处理
    document.getElementById('recordType').addEventListener('change', function() {
        togglePriorityField('recordPriority', 'priorityGroup', this.value);
    });

    // 配置表单提交
    document.getElementById('configForm').addEventListener('submit', function(e) {
        e.preventDefault();
        saveConfig();
    });

    // 开关状态改变监听器
    document.getElementById('configEnabled').addEventListener('change', function() {
        toggleFormFields(this.checked);
        if (this.checked) {
            const secretId = document.getElementById('configSecretId').value.trim();
            const secretKey = document.getElementById('configSecretKey').value.trim();
            if (secretId && secretKey) {
                updateConfigStatus('connected');
            } else {
                updateConfigStatus('disconnected');
            }
        } else {
            updateConfigStatus('disconnected');
        }
    });
}

// 初始化视图状态
function initializeRecordTypeView(type) {
    console.log('初始化视图类型:', type);

    // 更新切换按钮状态
    document.getElementById('dnsToggle').classList.remove('active');
    document.getElementById('domainToggle').classList.remove('active');

    if (type === 'dns') {
        document.getElementById('dnsToggle').classList.add('active');
    } else {
        document.getElementById('domainToggle').classList.add('active');
    }

    // 显示/隐藏相应的操作按钮
    document.getElementById('dnsActions').style.display = type === 'dns' ? 'block' : 'none';
    document.getElementById('domainActions').style.display = type === 'domain' ? 'block' : 'none';

    // 显示/隐藏相应的搜索区域
    document.getElementById('dnsSearchSection').style.display = type === 'dns' ? 'flex' : 'none';
    document.getElementById('domainSearchSection').style.display = type === 'domain' ? 'flex' : 'none';

    // 显示/隐藏相应的表格
    document.getElementById('dnsTableView').style.display = type === 'dns' ? 'block' : 'none';
    document.getElementById('domainTableView').style.display = type === 'domain' ? 'block' : 'none';
}

// 切换记录类型 - 通过页面跳转
function switchRecordType(type) {
    console.log('切换记录类型到:', type, '当前类型:', currentRecordType);

    // 如果已经是当前类型，不做任何操作
    if (currentRecordType === type) {
        return;
    }

    currentRecordType = type;

    // 获取当前选择的域名ID
    const zoneSelect = document.getElementById('zoneSelect');
    const selectedZoneId = (zoneSelect && zoneSelect.value) || '';

    // 构建新的URL - 无论是DNS还是加速域名都通过页面跳转
    let newUrl = '/dns/edgeone?type=' + type + '&page=0&size=20';

    if (selectedZoneId) {
        newUrl += '&zoneId=' + selectedZoneId;
    }

    console.log('跳转到:', newUrl);
    window.location.href = newUrl;
}

// 加载域名列表
function loadZones() {
    console.log('开始加载域名列表...');

    return fetch('/dns/edgeone/api/zones', {
        method: 'GET',
        headers: {
            'Content-Type': 'application/json',
            [csrfHeaderName]: csrfToken
        }
    })
        .then(response => {
            if (!response.ok) {
                throw new Error('error');
            }
            return response.json();
        })
        .then(apiResponse => {
            if (apiResponse.success && apiResponse.data) {
                const zones = apiResponse.data;
                console.log('获取到域名列表:', zones);

                const zoneSelect = document.getElementById('zoneSelect');

                // 清空选项
                zoneSelect.innerHTML = '';

                // 如果有域名数据
                if (zones && zones.length > 0) {
                    // 添加所有域名选项
                    zones.forEach((zone, index) => {
                        const option = document.createElement('option');
                        option.value = zone.id;
                        option.textContent = zone.name + ' (' + zone.status + ')';
                        option.dataset.zoneName = zone.name;
                        option.dataset.zoneStatus = zone.status;

                        // 如果是第一个选项，设置为默认选中
                        if (index === 0) {
                            option.selected = true;
                            // 更新当前域名信息
                            currentZoneId = zone.id;
                            currentZoneName = zone.name;
                        }

                        zoneSelect.appendChild(option);
                    });

                    console.log('域名列表加载完成，共', zones.length, '个域名，默认选中第一个:', currentZoneName);
                } else {
                    // 如果没有域名，显示提示选项
                    const option = document.createElement('option');
                    option.value = '';
                    option.textContent = '暂无可用域名';
                    zoneSelect.appendChild(option);
                }

                return zones;
            } else {
                console.error('加载域名列表失败:', apiResponse.message);

                // 加载失败时，添加提示选项
                const zoneSelect = document.getElementById('zoneSelect');
                zoneSelect.innerHTML = '<option value="">加载失败，请刷新重试</option>';

                // 如果是配置问题，给出更友好的提示
                if (apiResponse.message && apiResponse.message.includes('配置')) {
                    Swal.fire({
                        title: i18n.tecent_plzConfig,
                        icon: 'info',
                        confirmButtonColor: '#006eff',
                        confirmButtonText: i18n.tecent_goConfig,
                        showCancelButton: true,
                        cancelButtonText: i18n.common_cancel
                    }).then((result) => {
                        if (result.isConfirmed) {
                            showConfigModal();
                        }
                    });
                } else {
                    Swal.fire({
                        title: 'error',
                        icon: 'error',
                        confirmButtonColor: '#ff6b6b'
                    });
                }
                throw new Error(apiResponse.message || 'error');
            }
        })
        .catch(error => {
            console.error('加载域名列表异常:', error);

            // 异常时添加提示选项
            const zoneSelect = document.getElementById('zoneSelect');
            if (!zoneSelect.innerHTML || zoneSelect.innerHTML === '') {
                zoneSelect.innerHTML = '<option value="">网络错误，请重试</option>';
            }

            // 网络错误的提示
            if (!error.message || error.message === 'error') {
                Swal.fire({
                    title: 'error',
                    text: i18n.common_network_error,
                    icon: 'error',
                    confirmButtonColor: '#ff6b6b'
                });
            }

            throw error;
        });
}

// 域名选择改变 - 通过页面跳转
function onZoneSelectChange() {
    const zoneSelect = document.getElementById('zoneSelect');
    const selectedZoneId = zoneSelect.value;

    console.log('域名选择改变:', selectedZoneId, '当前记录类型:', currentRecordType);

    // 更新当前域名信息
    if (selectedZoneId) {
        currentZoneId = selectedZoneId;
        const selectedOption = zoneSelect.options[zoneSelect.selectedIndex];
        if (selectedOption) {
            currentZoneName = selectedOption.dataset.zoneName;
        }

        // 保持当前的记录类型，但清除搜索条件，重置到第一页
        let newUrl = '/dns/edgeone?zoneId=' + selectedZoneId + '&type=' + currentRecordType + '&page=0&size=20';

        console.log('域名切换URL:', newUrl);
        window.location.href = newUrl;
    } else {
        // 如果取消选择，清空当前域名信息
        currentZoneId = '';
        currentZoneName = '';
        window.location.href = '/dns/edgeone?type=' + currentRecordType;
    }
}

// 刷新记录 - 通过页面重新加载
function refreshRecords() {
    const currentZoneId = '${selectedZoneId!""}';
    if (!currentZoneId) {
        Swal.fire({
            title: i18n.tecent_plzSelectDomain,
            icon: 'warning',
            confirmButtonColor: '#006eff'
        });
        return;
    }

    // 重新加载当前页面
    window.location.reload();
}

// DNS记录搜索 - 通过页面跳转到后端查询
function performSearch() {
    const searchName = document.getElementById('searchName').value.trim();
    const searchContent = document.getElementById('searchContent').value.trim();
    const currentZoneId = '${selectedZoneId!""}';

    if (!currentZoneId) {
        Swal.fire({
            title: i18n.tecent_plzSelectDomain,
            icon: 'warning',
            confirmButtonColor: '#006eff'
        });
        return;
    }

    let searchUrl = '/dns/edgeone?zoneId=' + currentZoneId + '&type=' + currentRecordType + '&page=0&size=20';

    if (searchName) {
        searchUrl += '&searchName=' + encodeURIComponent(searchName);
    }

    if (searchContent) {
        searchUrl += '&searchContent=' + encodeURIComponent(searchContent);
    }

    console.log('DNS搜索URL:', searchUrl);
    window.location.href = searchUrl;
}

// 加速域名搜索 - 通过页面跳转到后端查询
function performDomainSearch() {
    const searchDomainName = document.getElementById('searchDomainName').value.trim();
    const searchDomainStatus = document.getElementById('searchDomainStatus').value;
    const currentZoneId = '${selectedZoneId!""}';

    if (!currentZoneId) {
        Swal.fire({
            title: i18n.tecent_plzSelectDomain,
            icon: 'warning',
            confirmButtonColor: '#006eff'
        });
        return;
    }

    let searchUrl = '/dns/edgeone?zoneId=' + currentZoneId + '&type=domain&page=0&size=20';

    if (searchDomainName) {
        searchUrl += '&searchName=' + encodeURIComponent(searchDomainName);
    }

    if (searchDomainStatus) {
        searchUrl += '&status=' + encodeURIComponent(searchDomainStatus);
    }

    console.log('域名搜索URL:', searchUrl);
    window.location.href = searchUrl;
}

function handleSearchKeyPress(event, type) {
    if (event.key === 'Enter') {
        if (type === 'domain') {
            performDomainSearch();
        } else {
            performSearch();
        }
    }
}

// 清除DNS搜索
function clearSearch() {
    const currentZoneId = '${selectedZoneId!""}';

    // 清空搜索框
    document.getElementById('searchName').value = '';
    document.getElementById('searchContent').value = '';

    if (currentZoneId) {
        window.location.href = '/dns/edgeone?zoneId=' + currentZoneId + '&type=' + currentRecordType + '&page=0&size=20';
    } else {
        window.location.href = '/dns/edgeone';
    }
}

// 清除加速域名搜索
function clearDomainSearch() {
    const currentZoneId = '${selectedZoneId!""}';

    // 清空搜索框
    document.getElementById('searchDomainName').value = '';

    if (currentZoneId) {
        window.location.href = '/dns/edgeone?zoneId=' + currentZoneId + '&type=domain&page=0&size=20';
    } else {
        window.location.href = '/dns/edgeone';
    }
}

// 显示添加DNS记录模态框
function showAddDnsModal() {
    currentZoneId = '${selectedZoneId!""}';
    if (!currentZoneId) {
        Swal.fire({
            title: i18n.tecent_plzSelectDomain,
            icon: 'warning',
            confirmButtonColor: '#006eff'
        });
        return;
    }

    document.getElementById('addDnsForm').reset();
    document.getElementById('recordType').value = 'A';
    togglePriorityField('recordPriority', 'priorityGroup', 'A');
    document.getElementById('addDnsModal').style.display = 'flex';
}

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
        priority: document.getElementById('recordPriority').value ? parseInt(document.getElementById('recordPriority').value) : null
    };

    if (!formData.name || !formData.content) {
        Swal.fire({
            title: '输入错误',
            text: '请填写所有必填字段',
            icon: 'error',
            confirmButtonColor: '#ff6b6b'
        });
        return;
    }

    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => Swal.showLoading()
    });

    fetch('/dns/edgeone/api/records', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrfHeaderName]: csrfToken
        },
        body: JSON.stringify(formData)
    })
        .then(response => response.json())
        .then(apiResponse => {
            if (apiResponse.success) {
                Swal.fire({
                    title: 'success',
                    text: 'successful',
                    icon: 'success',
                    confirmButtonColor: '#1abc9c'
                });
                closeAddDnsModal();
                // 添加成功后刷新当前页面
                window.location.reload();
            } else {
                Swal.fire({
                    title: 'error',
                    text: 'error',
                    icon: 'error',
                    confirmButtonColor: '#ff6b6b'
                });
            }
        })
        .catch(error => {
            console.error('添加DNS记录失败:', error);
            Swal.fire({
                title: 'error',
                text: i18n.common_network_error,
                icon: 'error',
                confirmButtonColor: '#ff6b6b'
            });
        });
}

// 显示编辑DNS记录模态框
function showEditDnsModal(recordId) {
    const row = document.querySelector(`button[onclick="showEditDnsModal('`+ recordId+`')"]`).closest('tr');
    const cells = row.querySelectorAll('td');

    const recordType = cells[0].querySelector('.record-type').textContent;
    const recordName = cells[1].querySelector('.truncate').getAttribute('title');
    const recordValue = cells[2].querySelector('.truncate').getAttribute('title');
    const ttlText = cells[3].textContent;
    const priorityText = cells[4].textContent;

    document.getElementById('editRecordId').value = recordId;
    document.getElementById('editRecordType').value = recordType;
    document.getElementById('editRecordName').value = recordName;
    document.getElementById('editRecordValue').value = recordValue;

    const ttlValue = parseTTLToValue(ttlText);
    document.getElementById('editRecordTtl').value = ttlValue;

    if (priorityText !== '-') {
        document.getElementById('editRecordPriority').value = priorityText;
    }

    togglePriorityField('editRecordPriority', 'editPriorityGroup', recordType);
    document.getElementById('editDnsModal').style.display = 'flex';
}

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
        priority: document.getElementById('editRecordPriority').value ? parseInt(document.getElementById('editRecordPriority').value) : null
    };

    if (!formData.content) {
        Swal.fire({
            title: 'error',
            text: i18n.common_plzInputGlobalRequired,
            icon: 'error',
            confirmButtonColor: '#ff6b6b'
        });
        return;
    }

    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => Swal.showLoading()
    });

    fetch(`/dns/edgeone/api/records/`+recordId, {
        method: 'PUT',
        headers: {
            'Content-Type': 'application/json',
            [csrfHeaderName]: csrfToken
        },
        body: JSON.stringify(formData)
    })
        .then(response => response.json())
        .then(apiResponse => {
            if (apiResponse.success) {
                closeEditDnsModal();
                // 更新成功后刷新当前页面
                window.location.reload();
            } else {
                Swal.fire({
                    title: 'error',
                    text: 'error',
                    icon: 'error',
                    confirmButtonColor: '#ff6b6b'
                });
            }
        })
        .catch(error => {
            console.error('更新DNS记录失败:', error);
            Swal.fire({
                title: 'error',
                text: i18n.common_network_error,
                icon: 'error',
                confirmButtonColor: '#ff6b6b'
            });
        });
}

// 删除DNS记录
function deleteDnsRecord(recordId, recordName) {
    Swal.fire({
        title: i18n.tecent_delete,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#ff6b6b',
        cancelButtonColor: '#006eff',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            Swal.fire({
                title: 'loading',
                allowOutsideClick: false,
                didOpen: () => Swal.showLoading()
            });

            fetch(`/dns/edgeone/api/records/`+recordId, {
                method: 'DELETE',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
                }
            })
                .then(response => response.json())
                .then(apiResponse => {
                    if (apiResponse.success) {
                        // 删除成功后刷新当前页面
                        window.location.reload();
                    } else {
                        Swal.fire({
                            title: 'error',
                            text: i18n.common_network_error,
                            icon: 'error',
                            confirmButtonColor: '#ff6b6b'
                        });
                    }
                })
                .catch(error => {
                    console.error('删除DNS记录失败:', error);
                    Swal.fire({
                        title: 'error',
                        text: i18n.common_network_error,
                        icon: 'error',
                        confirmButtonColor: '#ff6b6b'
                    });
                });
        }
    });
}

function closeAddDomainModal() {
    document.getElementById('addDomainModal').style.display = 'none';
}

function addAccelerationDomain() {
    const formData = {
        zoneId: currentZoneId,
        domainName: document.getElementById('domainName').value.trim(),
        originType: document.getElementById('originType').value,
        originValue: document.getElementById('originValue').value.trim(),
        protocols: []
    };

    if (document.getElementById('protocolHttp').checked) {
        formData.protocols.push('http');
    }
    if (document.getElementById('protocolHttps').checked) {
        formData.protocols.push('https');
    }

    if (!formData.domainName || !formData.originValue || formData.protocols.length === 0) {
        Swal.fire({
            title: 'warn',
            text: i18n.common_plzInputGlobalRequired,
            icon: 'error',
            confirmButtonColor: '#ff6b6b'
        });
        return;
    }

    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => Swal.showLoading()
    });

    fetch('/dns/edgeone/api/domains', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrfHeaderName]: csrfToken
        },
        body: JSON.stringify(formData)
    })
        .then(response => response.json())
        .then(apiResponse => {
            if (apiResponse.success) {
                Swal.fire({
                    title: 'success',
                    icon: 'success',
                    confirmButtonColor: '#1abc9c'
                });
                closeAddDomainModal();
                // 添加成功后刷新当前页面
                window.location.reload();
            } else {
                Swal.fire({
                    title: 'error',
                    text: i18n.common_network_error,
                    icon: 'error',
                    confirmButtonColor: '#ff6b6b'
                });
            }
        })
        .catch(error => {
            console.error('添加加速域名失败:', error);
            Swal.fire({
                title: 'error',
                text: i18n.common_network_error,
                icon: 'error',
                confirmButtonColor: '#ff6b6b'
            });
        });
}

// 显示编辑加速域名模态框
function showEditDomainModal(domainId) {
    // 这里需要根据你的需求实现编辑功能
    console.log('编辑加速域名:', domainId);
    Swal.fire({
        title: i18n.tecent_devloping,
        icon: 'info',
        confirmButtonColor: '#006eff'
    });
}

function deleteAccelerationDomain(domainId, domainName) {
    Swal.fire({
        title: i18n.tecent_delete,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#ff6b6b',
        cancelButtonColor: '#006eff',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            Swal.fire({
                title: 'loading',
                allowOutsideClick: false,
                didOpen: () => Swal.showLoading()
            });

            fetch(`/dns/edgeone/api/domains/`+domainId, {
                method: 'DELETE',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
                }
            })
                .then(response => response.json())
                .then(apiResponse => {
                    if (apiResponse.success) {
                        // 删除成功后刷新当前页面
                        window.location.reload();
                    } else {
                        showError();
                    }
                })
                .catch(error => {
                    showError();
                });
        }
    });
}

// 同步所有DNS记录
function syncAllRecords() {
    const currentZoneId = '${selectedZoneId!""}';
    if (!currentZoneId) {
        Swal.fire({
            title: 'warning',
            text: i18n.common_plzInputGlobalRequired,
            icon: 'warning',
            confirmButtonColor: '#006eff'
        });
        return;
    }

    const zoneSelect = document.getElementById('zoneSelect');
    const selectedOption = zoneSelect.options[zoneSelect.selectedIndex];
    const currentZoneName = selectedOption ? selectedOption.dataset.zoneName : '';

    Swal.fire({
        title: i18n.common_confirm,
        icon: 'question',
        showCancelButton: true,
        confirmButtonColor: '#1abc9c',
        cancelButtonColor: '#006eff',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            Swal.fire({
                title: 'loading',
                allowOutsideClick: false,
                didOpen: () => Swal.showLoading()
            });

            fetch(`/dns/edgeone/api/zones/`+ currentZoneId+`/sync`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
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
                        showSuccess();
                        // 同步成功后刷新当前页面
                        window.location.reload();
                    } else {
                        showError();
                    }
                })
                .catch(error => {
                    console.error('同步DNS记录失败:', error);
                    showError();
                });
        }
    });
}

// 同步所有加速域名
function syncAllDomains() {
    const currentZoneId = '${selectedZoneId!""}';
    if (!currentZoneId) {
        Swal.fire({
            title: i18n.tecent_plzSelectDomain,
            icon: 'warning',
            confirmButtonColor: '#006eff'
        });
        return;
    }

    const zoneSelect = document.getElementById('zoneSelect');
    const selectedOption = zoneSelect.options[zoneSelect.selectedIndex];
    const currentZoneName = selectedOption ? selectedOption.dataset.zoneName : '';

    Swal.fire({
        title: i18n.common_confirm,
        icon: 'question',
        showCancelButton: true,
        confirmButtonColor: '#1abc9c',
        cancelButtonColor: '#006eff',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    }).then((result) => {
        if (result.isConfirmed) {
            Swal.fire({
                title: 'loading',
                allowOutsideClick: false,
                didOpen: () => Swal.showLoading()
            });

            fetch(`/dns/edgeone/api/zones/`+ currentZoneId+`/sync-domains`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
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
                        showSuccess();
                        // 同步成功后刷新当前页面
                        window.location.reload();
                    } else {
                        showError();
                    }
                })
                .catch(error => {
                    console.error('同步加速域名失败:', error);
                    showError();
                });
        }
    });
}

// 显示配置模态框
function showConfigModal() {
    loadCurrentConfig();
    document.getElementById('configModal').style.display = 'flex';
}

function closeConfigModal() {
    document.getElementById('configModal').style.display = 'none';
}

function loadCurrentConfig() {
    const configSecretId = '${edgeOneConfig.secretId!""}';
    const configSecretKey = '${edgeOneConfig.secretKey!""}';
    const configRegion = '${edgeOneConfig.region!"ap-beijing"}';
    const configEnabled = '${edgeOneConfig.enabled?string("true", "false")}';

    document.getElementById('configSecretId').value = configSecretId;
    document.getElementById('configSecretKey').value = configSecretKey;
    document.getElementById('configRegion').value = configRegion;
    document.getElementById('configEnabled').checked = configEnabled;

    if (configEnabled && configSecretId && configSecretKey) {
        updateConfigStatus('connected');
    } else {
        updateConfigStatus('disconnected');
    }

    toggleFormFields(configEnabled);
}

function saveConfig() {
    const formData = {
        enabled: document.getElementById('configEnabled').checked,
        secretId: document.getElementById('configSecretId').value.trim(),
        secretKey: document.getElementById('configSecretKey').value.trim(),
        region: document.getElementById('configRegion').value
    };

    if (formData.enabled) {
        if (!formData.secretId) {
            Swal.fire({
                title: 'warning',
                text: i18n.common_plzInputGlobalRequired,
                icon: 'warning',
                confirmButtonColor: '#006eff'
            });
            return;
        }

        if (!formData.secretKey) {
            Swal.fire({
                title: 'warning',
                text: i18n.common_plzInputGlobalRequired,
                icon: 'warning',
                confirmButtonColor: '#006eff'
            });
            return;
        }
    }

    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => Swal.showLoading()
    });

    updateConfigStatus('pending');

    fetch('/api/system/updateEdgeOneConfig', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrfHeaderName]: csrfToken
        },
        body: JSON.stringify(formData)
    })
        .then(response => {
            if (!response.ok) {
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

            return response.text().then(text => {
                if (text.trim() === '') {
                    return { success: true, message: '配置保存成功' };
                } else {
                    try {
                        return JSON.parse(text);
                    } catch (e) {
                        return { success: true, message: text };
                    }
                }
            });
        })
        .then(data => {
            Swal.fire({
                title: 'success',
                icon: 'success',
                confirmButtonColor: '#1abc9c',
                timer: 1500,
                showConfirmButton: false
            }).then(() => {
                window.location.reload();
            });
        })
        .catch(error => {
            console.error('保存配置失败:', error);
            updateConfigStatus('disconnected');
            showError();
        });
}

function testConfigConnection() {
    const secretId = document.getElementById('configSecretId').value.trim();
    const secretKey = document.getElementById('configSecretKey').value.trim();
    const region = document.getElementById('configRegion').value;

    if (!secretId || !secretKey) {
        Swal.fire({
            title: 'warning',
            text: i18n.common_plzInputGlobalRequired,
            icon: 'warning',
            confirmButtonColor: '#006eff'
        });
        return;
    }

    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => Swal.showLoading()
    });

    updateConfigStatus('pending');

    fetch('/api/system/testEdgeOneConnection', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrfHeaderName]: csrfToken
        },
        body: JSON.stringify({
            secretId: secretId,
            secretKey: secretKey,
            region: region
        })
    })
        .then(response => response.json())
        .then(data => {
            if (data.success) {
                updateConfigStatus('connected');
                showSuccess();
            } else {
                throw new Error(data.message || 'error');
            }
        })
        .catch(error => {
            updateConfigStatus('disconnected');
            showError();
        });
}

function toggleFormFields(enabled) {
    const secretIdInput = document.getElementById('configSecretId');
    const secretKeyInput = document.getElementById('configSecretKey');
    const regionSelect = document.getElementById('configRegion');
    const testBtn = document.querySelector('#configModal .btn-info');

    if (enabled) {
        secretIdInput.disabled = false;
        secretKeyInput.disabled = false;
        regionSelect.disabled = false;
        testBtn.disabled = false;
        secretIdInput.style.opacity = '1';
        secretKeyInput.style.opacity = '1';
        regionSelect.style.opacity = '1';
        testBtn.style.opacity = '1';
    } else {
        secretIdInput.disabled = true;
        secretKeyInput.disabled = true;
        regionSelect.disabled = true;
        testBtn.disabled = true;
        secretIdInput.style.opacity = '0.5';
        secretKeyInput.style.opacity = '0.5';
        regionSelect.style.opacity = '0.5';
        testBtn.style.opacity = '0.5';
    }
}

function updateConfigStatus(status) {
    const statusBadge = document.getElementById('configStatus');

    const statusTexts = {
        connected: i18n.domain_conn,
        disconnected: i18n.domain_disConn,
        pending: i18n.domain_connecting
    };

    const icons = {
        connected: 'check-circle',
        disconnected: 'circle',
        pending: 'clock'
    };

    statusBadge.className = `status-badge status-`+ status+``;
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
        Swal.fire({
            title: i18n.domain_noDataCopy,
            icon: 'warning',
            timer: 2000,
            showConfirmButton: false
        });
        return;
    }

    try {
        await navigator.clipboard.writeText(value);
        Swal.fire({
            title: 'success',
            icon: 'success',
            timer: 2000,
            showConfirmButton: false
        });
    } catch (err) {
        input.select();
        document.execCommand('copy');
        Swal.fire({
            title: 'success',
            icon: 'success',
            timer: 2000,
            showConfirmButton: false
        });
    }
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
    if (ttl < 60) return ttl + 's';
    if (ttl < 3600) return Math.floor(ttl / 60) + 'min';
    if (ttl < 86400) return Math.floor(ttl / 3600) + 'hour';
    return Math.floor(ttl / 86400) + 'day';
}

// 将TTL文本转换为数值
function parseTTLToValue(ttlText) {
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

// 根据记录类型显示/隐藏优先级字段
function togglePriorityField(inputId, groupId, recordType) {
    const priorityInput = document.getElementById(inputId);
    const priorityGroup = document.getElementById(groupId);

    // 只有MX记录需要优先级
    if (recordType === 'MX') {
        priorityGroup.style.display = 'block';
        priorityInput.required = true;
    } else {
        priorityGroup.style.display = 'none';
        priorityInput.required = false;
        priorityInput.value = '';
    }
}

// 自定义选择器
function setupCustomSelect() {
    const customSelect = document.querySelector('.custom-select');
    if (customSelect) {
        const select = customSelect.querySelector('select');

        select.addEventListener('focus', () => {
            customSelect.classList.add('open');
        });

        select.addEventListener('blur', () => {
            customSelect.classList.remove('open');
        });
    }
}

// 初始化搜索框的值
function initializeSearchInputs() {
    const searchName = (window.SERVER_CONFIG && window.SERVER_CONFIG.searchName) || '';
    const searchContent = (window.SERVER_CONFIG && window.SERVER_CONFIG.searchContent) || '';

    // DNS搜索框初始化
    if (currentRecordType === 'dns') {
        const searchNameInput = document.getElementById('searchName');
        const searchContentInput = document.getElementById('searchContent');

        if (searchNameInput && searchName) {
            searchNameInput.value = searchName;
        }

        if (searchContentInput && searchContent) {
            searchContentInput.value = searchContent;
        }
    }

    // 加速域名搜索框初始化
    if (currentRecordType === 'domain' && searchName) {
        const domainSearchInput = document.getElementById('searchDomainName');
        if (domainSearchInput) {
            domainSearchInput.value = searchName;
        }
    }
}

// 刷新域名列表 - 手动刷新时调用
function refreshZones() {
    console.log('手动刷新域名列表...');

    // 记住当前选中的域名
    const previousZoneId = currentZoneId || '${selectedZoneId!""}';

    // 显示加载提示
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => Swal.showLoading()
    });

    loadZones().then((zones) => {
        console.log('域名列表刷新完成');

        const zoneSelect = document.getElementById('zoneSelect');

        // 尝试恢复之前的选中状态
        if (previousZoneId) {
            // 检查之前选中的域名是否还存在
            let found = false;
            for (let i = 0; i < zoneSelect.options.length; i++) {
                if (zoneSelect.options[i].value === previousZoneId) {
                    zoneSelect.value = previousZoneId;
                    currentZoneId = previousZoneId;
                    const selectedOption = zoneSelect.options[i];
                    if (selectedOption) {
                        currentZoneName = selectedOption.dataset.zoneName;
                    }
                    found = true;
                    break;
                }
            }

            if (!found && zones && zones.length > 0) {
                // 如果之前的域名不存在了，已经默认选中了第一个
                console.log('之前的域名不存在，已默认选中第一个');
            }
        }

        Swal.fire({
            title: 'success',
            icon: 'success',
            timer: 1500,
            showConfirmButton: false
        });
    }).catch(error => {
        console.error('刷新域名列表失败:', error);
        Swal.close();
    });
}

function initializeCurrentZoneInfo() {
    const zoneSelect = document.getElementById('zoneSelect');
    if (zoneSelect.value) {
        currentZoneId = zoneSelect.value;
        const selectedOption = zoneSelect.options[zoneSelect.selectedIndex];
        if (selectedOption) {
            currentZoneName = selectedOption.dataset.zoneName;
            console.log('初始化域名信息 - ID:', currentZoneId, 'Name:', currentZoneName);
        }
    }
}


function showError(){
    Swal.fire({
        title: 'error',
        text: i18n.common_network_error,
        icon: 'error',
        confirmButtonColor: '#ff6b6b'
        });
}

function  showSuccess(){
    Swal.fire({
        title: 'success',
        icon: 'success',
        confirmButtonColor: '#1abc9c'
    });
}