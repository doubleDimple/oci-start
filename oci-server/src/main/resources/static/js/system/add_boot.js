let csrfToken, csrfHeaderName;
const i18n = window.I18N;
let currentMode = 'quick'; // 默认模式

document.addEventListener('DOMContentLoaded', function() {
    csrfToken = document.querySelector('meta[name="_csrf"]').content;
    csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;

    initRegionSelection();
    initModeSwitch();
    initTemplateSelection();
    initIntervalSelection();
    initFormValidation();
    generateAndSetPassword();
});

// 模式切换
function initModeSwitch() {
    const tabs = document.querySelectorAll('.mode-tab');
    const areas = document.querySelectorAll('.mode-area');

    tabs.forEach(tab => {
        tab.addEventListener('click', function() {
            // UI 切换
            tabs.forEach(t => t.classList.remove('active'));
            this.classList.add('active');

            areas.forEach(a => a.style.display = 'none');
            document.getElementById(`${this.dataset.mode}-mode-area`).style.display = 'block';

            currentMode = this.dataset.mode;

            // 重置/应用隐藏表单域
            if (currentMode === 'quick') {
                const selectedQuick = document.querySelector('.quick-card.selected');
                if(selectedQuick) applyTemplateData(selectedQuick.dataset.template);
                // 快速模式下实例强制为 1，清空 OS 以便后端走默认
                document.getElementById('instanceCountHidden').value = 1;
                clearOSSelection();
            } else {
                const selectedCustom = document.querySelector('.custom-card.selected');
                if(selectedCustom) applyTemplateData(selectedCustom.dataset.template);
                document.getElementById('instanceCountHidden').value = document.getElementById('customInstanceCount').value;
            }
        });
    });
}

// 模板选择
function initTemplateSelection() {
    // 快速模式卡片
    const quickCards = document.querySelectorAll('.quick-card');
    quickCards.forEach(card => {
        card.addEventListener('click', function() {
            quickCards.forEach(c => c.classList.remove('selected'));
            this.classList.add('selected');
            if(currentMode === 'quick') applyTemplateData(this.dataset.template);
        });
    });

    // 自定义模式卡片
    const customCards = document.querySelectorAll('.custom-card');
    let currentMaxCount = 2;
    const customInstanceCount = document.getElementById('customInstanceCount');

    customCards.forEach(card => {
        card.addEventListener('click', function() {
            customCards.forEach(c => c.classList.remove('selected'));
            this.classList.add('selected');

            const template = JSON.parse(this.dataset.template);
            if(currentMode === 'custom') applyTemplateData(this.dataset.template);

            currentMaxCount = template.maxCount;
            customInstanceCount.max = currentMaxCount;
            if (parseInt(customInstanceCount.value) > currentMaxCount) {
                customInstanceCount.value = currentMaxCount;
                document.getElementById('instanceCountHidden').value = currentMaxCount;
            }
            document.getElementById('maxInstanceText').textContent = `最大可创建数量: ${currentMaxCount}`;

            const tenantId = document.querySelector('input[name="tenantId"]').value;
            fetchSystemImages(tenantId, template.architecture);
        });
    });

    // 同步实例数
    customInstanceCount.addEventListener('input', function() {
        let value = parseInt(this.value);
        if (value > currentMaxCount) this.value = currentMaxCount;
        document.getElementById('instanceCountHidden').value = this.value;
    });
}

function applyTemplateData(templateJsonStr) {
    const template = JSON.parse(templateJsonStr);
    document.getElementById('ocpu').value = template.ocpu;
    document.getElementById('memory').value = template.memory;
    document.getElementById('disk').value = template.disk;
    document.getElementById('architecture').value = template.architecture;
}

function clearOSSelection() {
    document.getElementById('operatingSystemHidden').value = '';
    document.getElementById('operatingSystemVersionHidden').value = '';
    document.getElementById('imageIdHidden').value = '';
}

// 循环时间选择功能 (针对自定义模式)
function initIntervalSelection() {
    const intervalBtns = document.querySelectorAll('.interval-btn');
    const customIntervalInput = document.getElementById('customInterval');
    const loopTimeInput = document.getElementById('loopTime');

    intervalBtns.forEach(btn => {
        btn.addEventListener('click', function() {
            intervalBtns.forEach(b => b.classList.remove('selected'));
            this.classList.add('selected');
            loopTimeInput.value = this.dataset.value;
            customIntervalInput.value = '';
        });
    });

    customIntervalInput.addEventListener('input', function() {
        if (this.value) {
            intervalBtns.forEach(btn => btn.classList.remove('selected'));
            loopTimeInput.value = this.value;
        }
    });
}

// 随机密码生成
function generateAndSetPassword() {
    const charset = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    let password = '';
    password += 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'[Math.floor(Math.random() * 26)];
    password += 'abcdefghijklmnopqrstuvwxyz'[Math.floor(Math.random() * 26)];
    password += '0123456789'[Math.floor(Math.random() * 10)];
    for (let i = 4; i < 16; i++) {
        password += charset[Math.floor(Math.random() * charset.length)];
    }
    password = password.split('').sort(() => Math.random() - 0.5).join('');
    document.getElementById('rootPassword').value = password;
}

// 表单验证与提交
function initFormValidation() {
    const form = document.getElementById('bootForm');
    form.addEventListener('submit', function(e) {
        e.preventDefault();

        // 自定义模式下需校验配置是否选全
        if (currentMode === 'custom') {
            const selectedCustomTemplate = document.querySelector('.custom-card.selected');
            if (!selectedCustomTemplate) {
                Swal.fire({ icon: 'warning', title: i18n.ins_plzConfigTemplate });
                return;
            }
            // 时间校验
            const dayGap = document.getElementById('dayGap').value.trim();
            if (dayGap) {
                const match = dayGap.match(/^(\d{1,2})-(\d{1,2})$/);
                if (!match) return Swal.fire({ icon: 'warning', title: i18n.ins_timeBetweenError, text: i18n.ins_timeBetweenRule1 });
                const start = parseInt(match[1]), end = parseInt(match[2]);
                if (start < 0 || start > 23 || end < 1 || end > 24) return Swal.fire({ icon: 'warning', title: i18n.ins_timeBetweenError, text: i18n.ins_timeBetweenErrorAnd24Hours });
                if (start >= end) return Swal.fire({ icon: 'warning', title: i18n.ins_timeBetweenError, text: i18n.ins_timeBetweenErrorDays });
            }
        }

        generateAndSetPassword();
        const submitBtn = document.getElementById('submit-btn');
        submitBtn.disabled = true;
        submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> '+i18n.common_saving;

        showLoading("loading...");

        fetch(form.action, {
            method: form.method,
            headers: { [csrfHeaderName]: csrfToken },
            body: new FormData(form)
        })
            .then(response => response.json())
            .then(data => {
                hideLoading();
                if (data.success) {
                    window.location.href = `/tenants/bootList?tenantId=${document.querySelector('input[name="tenantId"]').value}`;
                } else {
                    Swal.fire({ title: 'error', text: data.message, icon: 'error', confirmButtonColor: '#ff6b6b' });
                }
            })
            .catch(err => {
                console.error(err);
                hideLoading();
                showError();
                submitBtn.disabled = false;
                submitBtn.innerHTML = '<i class="fas fa-plus"></i> '+i18n.common_saving;
            });
    });
}

function fetchSystemImages(tenantId, shapeType) {
    showLoading("loading...");
    fetch('/tenants/querySystemImages', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', [csrfHeaderName]: csrfToken },
        body: JSON.stringify({ tenantId, shapeType })
    })
        .then(response => response.json())
        .then(data => {
            hideLoading();
            if (!data || !data.success || !Array.isArray(data.data)) return showError();

            const systemSelect = document.getElementById('operatingSystem');
            const versionSelect = document.getElementById('operatingSystemVersion');

            systemSelect.innerHTML = '<option value="">'+i18n.ins_plzOs+'</option>';
            versionSelect.innerHTML = '<option value="">'+i18n.ins_plzVersion+'</option>';
            clearOSSelection();

            const systemMap = {};
            data.data.forEach(item => {
                if (!systemMap[item.operatingSystem]) systemMap[item.operatingSystem] = [];
                systemMap[item.operatingSystem].push(item);
            });

            Object.keys(systemMap).forEach(os => {
                const opt = document.createElement('option');
                opt.value = os; opt.textContent = os;
                systemSelect.appendChild(opt);
            });

            systemSelect.onchange = function() {
                const selected = this.value;
                versionSelect.innerHTML = '<option value="">'+i18n.ins_plzVersion+'</option>';
                document.getElementById('operatingSystemHidden').value = selected || '';
                document.getElementById('operatingSystemVersionHidden').value = '';
                document.getElementById('imageIdHidden').value = '';

                if (selected && systemMap[selected]) {
                    systemMap[selected].forEach(v => {
                        const opt = document.createElement('option');
                        opt.value = v.operatingSystemVersion;
                        opt.textContent = v.operatingSystemVersion;
                        opt.dataset.imageId = v.imageId;
                        versionSelect.appendChild(opt);
                    });
                }
            };

            versionSelect.onchange = function() {
                const selectedOption = this.options[this.selectedIndex];
                document.getElementById('operatingSystemVersionHidden').value = selectedOption.value || '';
                document.getElementById('imageIdHidden').value = selectedOption.dataset.imageId || '';
            };

            document.getElementById('system-section').style.display = 'block';
        })
        .catch(err => {
            hideLoading();
            console.error("fetchSystemImages 出错：", err);
            showError();
        });
}

// 初始化区域选择
function initRegionSelection() {
    const tenantIdHidden = document.getElementById('tenantIdHidden');
    const regionSelect = document.getElementById('regionSelect');
    const initialParentId = tenantIdHidden.value;

    fetch(`/tenants/listRegions?parentId=${initialParentId}`, {
        method: 'GET',
        headers: {
            'Accept': 'application/json'
        }
    })
        .then(response => response.json())
        .then(data => {
            regionSelect.innerHTML = '';
            if (!data || data.length === 0) {
                regionSelect.innerHTML = '<option value="">no Region</option>';
                return;
            }

            let homeRegionId = null;
            data.forEach(item => {
                const opt = document.createElement('option');
                opt.value = item.id;
                opt.textContent = `${item.region}`;
                if (item.isHomeRegion) {
                    opt.selected = true;
                    homeRegionId = item.id;
                }
                regionSelect.appendChild(opt);
            });
            if (!homeRegionId && data.length > 0) {
                regionSelect.selectedIndex = 0;
                homeRegionId = data[0].id;
            }
            tenantIdHidden.value = homeRegionId;
            regionSelect.addEventListener('change', function() {
                tenantIdHidden.value = this.value;
                if (currentMode === 'custom') {
                    const selectedCustom = document.querySelector('.custom-card.selected');
                    if (selectedCustom) {
                        const template = JSON.parse(selectedCustom.dataset.template);
                        fetchSystemImages(this.value, template.architecture);
                    }
                }
            });
        })
        .catch(err => {
            console.error("获取区域列表失败：", err);
            regionSelect.innerHTML = '<option value="">error</option>';
        });
}

function showError(){
    Swal.fire({ title: 'error', text: i18n.common_network_error, icon: 'error', confirmButtonColor: '#ff6b6b' });
}