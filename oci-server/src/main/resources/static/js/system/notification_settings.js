let csrfToken, csrfHeaderName;
const i18n = window.I18N;
const swalConfig = {
    confirmButton: {
        confirmButtonColor: '#2196f3',
        cancelButtonColor: '#ff6b6b',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    },
    toast: {
        toast: true,
        position: 'bottom-end',
        showConfirmButton: false,
        timer: 3000,
        timerProgressBar: true,
        didOpen: (toast) => {
            toast.addEventListener('mouseenter', Swal.stopTimer)
            toast.addEventListener('mouseleave', Swal.resumeTimer)
        }
    }
};

// 通用错误处理
async function handleApiError(error, title = i18n.request_operation_fail) {
    if (window.OciRequestUtils && typeof window.OciRequestUtils.showApiError === 'function') {
        await window.OciRequestUtils.showApiError(error, title);
        return;
    }

    await Swal.fire({
        icon: 'error',
        title: title,
        text: (error && error.message) || error || i18n.request_network_or_server_error,
        confirmButtonColor: '#2196f3'
    });
}

async function assertResponseOk(response, fallbackMessage = i18n.request_operation_fail) {
    if (window.OciRequestUtils && typeof window.OciRequestUtils.assertApiResponse === 'function') {
        return await window.OciRequestUtils.assertApiResponse(response, fallbackMessage);
    }
    if (!response.ok) {
        throw new Error(await response.text() || fallbackMessage);
    }
    const text = await response.text();
    return text ? JSON.parse(text) : null;
}

async function updateTelegramConfig() {
    const form = document.getElementById('telegramForm');
    const formData = new FormData(form);
    const enabled = document.querySelector('.settings-card:has(#telegramForm) .switch input[type="checkbox"]').checked;

    if (enabled && (!formData.get('botToken') || !formData.get('chatId'))) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.notification_plzInputGlobalInfo,
            text: i18n.notification_tg_required,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    try {
        const result = await Swal.fire({
            title: i18n.common_confirmUpdate,
            icon: 'question',
            showCancelButton: true,
            ...swalConfig.confirmButton
        });

        if (result.isConfirmed) {
            const response = await fetch('/api/system/updateTelegramConfig', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify({
                    botToken: formData.get('botToken'),
                    chatId: formData.get('chatId'),
                    chatName: formData.get('chatName') || null, // 可选字段
                    enabled: enabled
                })
            });

            await assertResponseOk(response, i18n.common_confirmUpdateFail);

            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.common_confirmUpdateSuccess
            });
        }
    } catch (error) {
        await handleApiError(error, i18n.common_confirmUpdateFail);
    }
}

// 更新钉钉配置
async function updateDingTalkConfig(button) {
    const form = document.getElementById('dingTalkForm');
    if (!form) {
        await Swal.fire({
            icon: 'error',
            title: i18n.common_error,
            text: i18n.request_form_missing,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    const enabled = form.closest('.settings-card').querySelector('.switch input[type="checkbox"]').checked;
    const formData = new FormData(form);
    const config = {
        enabled: enabled,
        webhook: formData.get('webhook'),
        secret: formData.get('secret')
    };

    // 验证必填项
    if (!config.webhook || !config.webhook.trim()) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.notification_plzInputGlobalInfo,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    if (!config.secret || !config.secret.trim()) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.notification_plzInputGlobalInfo,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    if (!config.webhook.startsWith('https://oapi.dingtalk.com/robot/send')) {
        await Swal.fire({
            icon: 'error',
            title: i18n.common_confirmFormatFail,
            //text: i18n.common_confirmFormatFail,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    try {
        const result = await Swal.fire({
            title: i18n.common_confirmUpdate,
            //text: '是否保存钉钉配置？',
            icon: 'question',
            showCancelButton: true,
            ...swalConfig.confirmButton
        });

        if (result.isConfirmed) {
            button.innerHTML = '<i class="fas fa-spinner fa-spin"></i>'+i18n.common_saving;
            button.disabled = true;

            const response = await fetch('/api/system/updateDingTalkConfig', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify(config)
            });

            await assertResponseOk(response, i18n.notification_dingTalkUpdateFail);

            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.common_confirmUpdate
            });
        }
    } catch (error) {
        await handleApiError(error, i18n.common_confirmUpdateFail);
    } finally {
        button.innerHTML = '<i class="fas fa-save"></i> '+i18n.common_saving;
        button.disabled = false;
    }
}

// 测试钉钉消息
async function testDingTalk() {
    try {
        const response = await fetch('/api/system/testDingTalk', {
            method: 'POST',
            headers: {
                [csrfHeaderName]: csrfToken
            }
        });

        await assertResponseOk(response, i18n.common_sendFail);

        const Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({
            icon: 'success',
            title: i18n.common_sendSuccess
        });
    } catch (error) {
        await handleApiError(error, i18n.common_sendFail);
    }
}

async function testTgTalk() {
    try {
        const response = await fetch('/api/system/testTgTalk', {
            method: 'POST',
            headers: {
                /*'${_csrf.headerName}': '${_csrf.token}'*/
                [csrfHeaderName]: csrfToken
            }
        });

        await assertResponseOk(response, i18n.common_sendFail);

        const Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({
            icon: 'success',
            title: i18n.common_sendSuccess
        });
    } catch (error) {
        await handleApiError(error, i18n.common_sendFail);
    }
}

// 更新定时任务配置
async function updateTaskConfig(button) {
    const form = document.getElementById('taskForm');
    if (!form) {
        await Swal.fire({
            icon: 'error',
            title: i18n.common_error,
            text: i18n.request_form_missing,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    const enabled = form.closest('.settings-card').querySelector('.switch input[type="checkbox"]').checked;
    const executeHour = document.getElementById('executeHour').value;
    const notificationSecret = document.querySelector('input[name="notificationSecret"]').value;

    const enableAccountCheck = document.querySelector('input[name="enableAccountCheck"]').checked;
    const enableBootLog = document.querySelector('input[name="enableBootLog"]').checked;
    const enableCostCheck = document.querySelector('input[name="enableCostCheck"]').checked;

    const config = {
        enabled: enabled,
        executeHour: parseInt(executeHour),
        notificationSecret: notificationSecret || null,
        enableAccountCheck: enableAccountCheck,
        enableCostCheck: enableCostCheck,
        enableBootLog: enableBootLog
    };

    try {
        const result = await Swal.fire({
            title: i18n.common_confirmUpdate,
            //text: '是否保存定时任务配置？',
            icon: 'question',
            showCancelButton: true,
            ...swalConfig.confirmButton
        });

        if (result.isConfirmed) {
            button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> '+i18n.common_saving;
            button.disabled = true;

            const response = await fetch('/api/system/updateTaskConfig', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    /*'${_csrf.headerName}': '${_csrf.token}'*/
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify(config)
            });

            await assertResponseOk(response, i18n.notification_taskUpdateFail);

            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.common_confirmUpdateSuccess
            });
        }
    } catch (error) {
        await handleApiError(error, i18n.notification_taskUpdateFail);
    } finally {
        button.innerHTML = '<i class="fas fa-save"></i> ' + i18n.notification_save;
        button.disabled = false;
    }
}

// 更新Bark配置
async function updateBarkConfig(button) {
    const form = document.getElementById('barkForm');
    if (!form) {
        await Swal.fire({
            icon: 'error',
            title: i18n.common_error,
            text: i18n.request_form_missing,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    const enabled = form.closest('.settings-card').querySelector('.switch input[type="checkbox"]').checked;
    const formData = new FormData(form);
    const config = {
        enabled: enabled,
        url: formData.get('url'),
        deviceKey: formData.get('deviceKey')
    };

    // 验证必填项
    if (enabled && (!config.url || !config.deviceKey)) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.notification_plzInputGlobalInfo,
            //text: '启用Bark通知时，URL和设备Key为必填项',
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    try {
        const result = await Swal.fire({
            title: i18n.common_confirmUpdate,
            //text: '是否保存Bark配置？',
            icon: 'question',
            showCancelButton: true,
            ...swalConfig.confirmButton
        });

        if (result.isConfirmed) {
            button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> '+i18n.common_saving;
            button.disabled = true;

            const response = await fetch('/api/system/updateBarkConfig', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    /*'${_csrf.headerName}': '${_csrf.token}'*/
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify(config)
            });

            await assertResponseOk(response, i18n.common_confirmUpdateFail);

            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.common_confirmUpdateSuccess
            });
        }
    } catch (error) {
        await handleApiError(error, i18n.common_confirmUpdateFail);
    } finally {
        button.innerHTML = '<i class="fas fa-save"></i> '+ i18n.notification_save;
        button.disabled = false;
    }
}

// 测试Bark消息
async function testBark() {
    try {
        const response = await fetch('/api/system/testBark', {
            method: 'POST',
            headers: {
                /*'${_csrf.headerName}': '${_csrf.token}'*/
                [csrfHeaderName]: csrfToken
            }
        });

        await assertResponseOk(response, i18n.common_sendFail);

        const Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({
            icon: 'success',
            title: i18n.common_sendSuccess
        });
    } catch (error) {
        await handleApiError(error, i18n.common_sendFail);
    }
}

// 初始化页面
document.addEventListener('DOMContentLoaded', function() {
    csrfToken = document.querySelector('meta[name="_csrf"]').content;
    csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;
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

    const btn = document.getElementById("hourPickerBtn");
    const dropdown = document.getElementById("hourPickerDropdown");
    const gridItems = document.querySelectorAll(".hour-item");
    const label = document.getElementById("hourPickerLabel");
    const hiddenInput = document.getElementById("executeHour");

    // 点击按钮打开/关闭弹窗
    btn.addEventListener("click", function () {
        dropdown.style.display = dropdown.style.display === "block" ? "none" : "block";
    });

    // 点击小时选项
    gridItems.forEach(item => {
        item.addEventListener("click", function () {
            const hour = this.dataset.hour;

            // 设置 label 显示
            label.innerText = hour.toString().padStart(2, "0") + ":00";

            // 设置 hidden input 值
            hiddenInput.value = hour;

            // 切换选中样式
            gridItems.forEach(i => i.classList.remove("active"));
            this.classList.add("active");

            // 关闭下拉层
            dropdown.style.display = "none";
        });
    });

    // 点击外部关闭
    document.addEventListener("click", function (e) {
        if (!btn.contains(e.target) && !dropdown.contains(e.target)) {
            dropdown.style.display = "none";
        }
    });
});

async function updateFeishuConfig(button) {
    const form = document.getElementById('feishuForm');
    if (!form) {
        await Swal.fire({
            icon: 'error',
            title: i18n.common_error,
            text: i18n.request_form_missing,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    const enabled = form.closest('.settings-card').querySelector('.switch input[type="checkbox"]').checked;
    const formData = new FormData(form);
    const config = {
        enabled: enabled,
        webhook: formData.get('webhook'),
        secret: formData.get('secret')
    };

    // 验证必填项
    if (enabled && (!config.webhook || !config.webhook.trim())) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.notification_plzInputGlobalInfo,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    try {
        const result = await Swal.fire({
            title: i18n.common_confirmUpdate,
            //text: '是否保存飞书配置？',
            icon: 'question',
            showCancelButton: true,
            ...swalConfig.confirmButton
        });

        if (result.isConfirmed) {
            button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> '+i18n.common_saving;
            button.disabled = true;

            const response = await fetch('/api/system/updateFeishuConfig', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    /*'${_csrf.headerName}': '${_csrf.token}'*/
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify(config)
            });

            await assertResponseOk(response, i18n.common_confirmUpdateFail);

            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.common_confirmUpdateSuccess
            });
        }
    } catch (error) {
        await handleApiError(error, i18n.common_confirmUpdateFail);
    } finally {
        button.innerHTML = '<i class="fas fa-save"></i>'+i18n.notification_save;
        button.disabled = false;
    }
}

async function testFeishu() {
    try {
        const response = await fetch('/api/system/testFeishu', {
            method: 'POST',
            headers: {
                /*'${_csrf.headerName}': '${_csrf.token}'*/
                [csrfHeaderName]: csrfToken
            }
        });

        await assertResponseOk(response, i18n.common_sendFail);

        const Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({
            icon: 'success',
            title: i18n.common_sendSuccess
        });
    } catch (error) {
        await handleApiError(error, i18n.common_sendFail);
    }
}

// 1. 修改 updateProxyConfig 函数
async function updateProxyConfig() {
    const form = document.getElementById('proxyForm');
    const formData = new FormData(form);
    const enabled = document.querySelector('.settings-card:has(#proxyForm) .switch input[type="checkbox"]').checked;

    const config = {
        enabled: enabled,
        type: formData.get('proxyType'),
        host: formData.get('proxyHost'),
        port: parseInt(formData.get('proxyPort')) || 7890
    };

    if (enabled && (!config.host || !config.host.trim())) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.notification_plzInputGlobalInfo,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    try {
        const result = await Swal.fire({
            title: i18n.common_confirmUpdate,
            //text: '是否保存代理配置？',
            icon: 'question',
            showCancelButton: true,
            ...swalConfig.confirmButton
        });

        if (result.isConfirmed) {
            const response = await fetch('/api/system/updateProxyConfig', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    /*'${_csrf.headerName}': '${_csrf.token}'*/
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify(config)
            });

            await assertResponseOk(response, i18n.common_confirmUpdateFail);

            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.common_confirmUpdateSuccess
            });
        }
    } catch (error) {
        await handleApiError(error, i18n.common_confirmUpdateFail);
    }
}

async function testProxyConnection() {
    const form = document.getElementById('proxyForm');
    const formData = new FormData(form);

    const config = {
        type: formData.get('proxyType'),
        host: formData.get('proxyHost'),
        port: parseInt(formData.get('proxyPort')) || 7890
    };

    if (!config.host || !config.host.trim()) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.notification_plzInputGlobalInfo,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    try {
        const response = await fetch('/api/system/testProxyConnection', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                /*'${_csrf.headerName}': '${_csrf.token}'*/
                [csrfHeaderName]: csrfToken
            },
            body: JSON.stringify(config)
        });

        const result = await assertResponseOk(response, i18n.common_testFail);
        const Toast = Swal.mixin(swalConfig.toast);

        if (result.success) {
            Toast.fire({
                icon: 'success',
                title: i18n.common_testSuccess
            });
        } else {
            Toast.fire({
                icon: 'error',
                title: i18n.common_sendFail
            });
        }
    } catch (error) {
        await handleApiError(error, i18n.common_testFail);
    }
}

async function startTgRobot() {
    try {
        const result = await Swal.fire({
            title: i18n.notification_tg_isReg,
            //text: '将使用当前配置启动Telegram机器人服务',
            icon: 'question',
            showCancelButton: true,
            confirmButtonColor: '#1abc9c',
            cancelButtonColor: '#6c757d',
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel
        });

        if (result.isConfirmed) {
            const response = await fetch('/system/startTgRobot', {
                method: 'POST',
                headers: {
                    /*'${_csrf.headerName}': '${_csrf.token}'*/
                    [csrfHeaderName]: csrfToken
                }
            });

            await assertResponseOk(response, i18n.common_confirmUpdateFail);

            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.common_confirmUpdateSuccess
            });
        }
    } catch (error) {
        await handleApiError(error, i18n.common_confirmUpdateFail);
    }
}

// ── AI 配置模态框（左右双面板布局） ──
var currentModels = []; // 当前选中租户的模型列表
var _configs = [];      // 已配置列表（右侧面板）

// 打开AI配置模态框
async function openAiConfigModal() {
    var modal = document.getElementById('aiConfigModal');
    modal.classList.add('show');

    // 并行加载租户列表 + 已配置列表
    await Promise.all([loadTenants(), loadCurrentAiConfigs()]);
}

// 关闭AI配置模态框
function closeAiConfigModal() {
    var modal = document.getElementById('aiConfigModal');
    modal.classList.remove('show');
}

// 加载租户列表，填充下拉框
async function loadTenants() {
    var tenantSelect = document.getElementById('tenantSelect');
    try {
        var response = await fetch('/system/ai/tenants', {
            headers: { [csrfHeaderName]: csrfToken }
        });
        if (!response.ok) throw new Error(i18n.notification_tg_getAiModelFail);
        var tenants = await response.json();

        // 清空并填充
        tenantSelect.innerHTML = '<option value="">' + i18n.notification_plzSelectAiTenantName + '</option>';
        tenants.forEach(function(t) {
            var opt = document.createElement('option');
            opt.value = t.id;
            opt.textContent = t.name;
            tenantSelect.appendChild(opt);
        });

        // 初始化自定义下拉（如果尚未初始化）
        if (!tenantSelect._csInited) {
            CustomSelect.init(tenantSelect);
        }
    } catch (e) {
        console.error('加载租户失败:', e);
    }
}

// 已配置列表（右侧面板）
async function loadCurrentAiConfigs() {
    var configList = document.getElementById('configList');
    try {
        var response = await fetch('/system/telegramAiConfigs', {
            headers: { [csrfHeaderName]: csrfToken }
        });
        if (!response.ok) throw new Error('获取配置列表失败');
        _configs = await response.json();
        renderConfigList();
    } catch (e) {
        console.error('加载AI配置列表失败:', e);
        configList.innerHTML = '<div class="empty-state"><i class="fas fa-exclamation-triangle fa-2x"></i><p>' + i18n.common_loadFail + '</p></div>';
    }
}

// 租户选择变化 → 加载该租户的可用模型（左侧面板）
async function onTenantChange() {
    var tenantSelect = document.getElementById('tenantSelect');
    var modelList = document.getElementById('modelList');
    var leftLoading = document.getElementById('leftLoading');
    var tenantId = tenantSelect.value;

    if (!tenantId) {
        currentModels = [];
        modelList.innerHTML = '<div class="empty-state"><i class="fas fa-hand-point-up fa-2x"></i><p>' + i18n.notification_plzSelectAiTenantName + '</p></div>';
        return;
    }

    // 显示加载
    leftLoading.style.display = '';
    modelList.innerHTML = '<div class="empty-state"><i class="fas fa-spinner fa-spin fa-2x"></i></div>';

    try {
        var response = await fetch('/system/ai/modelsByTenant?tenantId=' + encodeURIComponent(tenantId), {
            headers: { [csrfHeaderName]: csrfToken }
        });
        if (!response.ok) throw new Error(i18n.notification_tg_getAiModelFail);
        currentModels = await response.json();
        renderModelList(tenantId);
    } catch (e) {
        console.error('加载模型失败:', e);
        modelList.innerHTML = '<div class="empty-state"><i class="fas fa-exclamation-triangle fa-2x"></i><p>' + i18n.common_loadFail + '</p></div>';
        currentModels = [];
    } finally {
        leftLoading.style.display = 'none';
    }
}

// 渲染左侧可用模型列表
function renderModelList(tenantId) {
    var modelList = document.getElementById('modelList');
    if (!currentModels || currentModels.length === 0) {
        modelList.innerHTML = '<div class="empty-state"><i class="fas fa-robot fa-2x"></i><p>' + i18n.notification_noAiConfig + '</p></div>';
        return;
    }
    var html = '';
    currentModels.forEach(function(model) {
        // 检查是否已添加
        var alreadyAdded = _configs.some(function(c) { return c.modelId === model.id; });
        html += '<div class="model-card">';
        html += '  <div class="model-card-body">';
        html += '    <div class="model-card-name" title="' + model.name + '">' + model.name + '</div>';
        html += '    <div class="model-details"><span class="badge badge-provider">' + (model.provider || 'OCI') + '</span></div>';
        html += '  </div>';
        html += '  <div class="model-card-footer">';
        if (alreadyAdded) {
            html += '    <button class="btn btn-sm btn-secondary" disabled><i class="fas fa-check"></i> ' + i18n.notification_alreadyAiModel + '</button>';
        } else {
            html += '    <button class="btn btn-sm btn-success" onclick="addModelToConfig(\'' + tenantId + '\',\'' + model.id + '\')"><i class="fas fa-plus"></i> ' + i18n.notification_addYourAiModel + '</button>';
        }
        html += '  </div>';
        html += '</div>';
    });
    modelList.innerHTML = html;
}

// 点击左侧模型卡片的「添加」按钮 → 保存配置
async function addModelToConfig(tenantId, modelId) {
    var model = currentModels.find(function(m) { return m.id === modelId; });
    if (!model) return;

    try {
        var response = await fetch('/system/updateTelegramAiConfig', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            },
            body: JSON.stringify({
                tenantId: tenantId,
                modelId: model.id,
                modelName: model.name,
                provider: model.provider || 'OCI',
                enabled: true,
                cloudType: 1
            })
        });

        if (!response.ok) throw new Error(i18n.common_confirmUpdateFail);

        var Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({ icon: 'success', title: i18n.common_confirmUpdateSuccess });

        // 刷新两侧面板
        await loadCurrentAiConfigs();
        renderModelList(tenantId);
    } catch (e) {
        console.error('保存失败:', e);
        await handleApiError(e, i18n.common_confirmUpdateFail);
    }
}

// 渲染右侧已配置列表
function renderConfigList() {
    var configList = document.getElementById('configList');
    if (!_configs || _configs.length === 0) {
        configList.innerHTML =
            '<div class="empty-state">' +
            '  <i class="fas fa-robot fa-2x"></i>' +
            '  <h4>' + i18n.notification_noAiConfig + '</h4>' +
            '  <p>' + i18n.notification_addYourAiModel + '</p>' +
            '</div>';
        return;
    }

    var html = '';
    _configs.forEach(function(config) {
        var statusClass = config.enabled ? 'enabled' : 'disabled';
        var statusText = config.enabled ? i18n.common_start : i18n.common_stop;
        var statusIcon = config.enabled ? 'fa-check-circle' : 'fa-times-circle';
        var modelName = config.modelName || config.modelId;
        var toggleText = config.enabled ? i18n.common_stop : i18n.common_start;

        html += '<div class="config-card ' + statusClass + '">';
        html += '  <div class="config-card-title" title="' + modelName + '">';
        html += '    <i class="fas fa-robot"></i> ' + modelName;
        html += '  </div>';
        html += '  <span class="badge-status ' + statusClass + '"><i class="fas ' + statusIcon + '"></i> ' + statusText + '</span>';
        html += '  <div class="config-card-actions">';
        html += '    <button class="btn btn-sm btn-outline-secondary" onclick="toggleConfigStatus(' + config.id + ',' + (!config.enabled) + ')">';
        html += '      <i class="fas fa-power-off"></i> ' + toggleText;
        html += '    </button>';
        html += '    <button class="btn btn-sm btn-outline-danger" onclick="deleteAiConfig(' + config.id + ')">';
        html += '      <i class="fas fa-trash"></i>';
        html += '    </button>';
        html += '  </div>';
        html += '</div>';
    });
    configList.innerHTML = html;
}

// 切换配置状态
async function toggleConfigStatus(configId, enabled) {
    try {
        var response = await fetch('/system/updateTelegramAiConfig', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            },
            body: JSON.stringify({ id: configId, enabled: enabled })
        });
        if (!response.ok) throw new Error(i18n.common_confirmUpdateFail);

        await loadCurrentAiConfigs();
        // 同步刷新左侧按钮状态
        var tenantSelect = document.getElementById('tenantSelect');
        if (tenantSelect && tenantSelect.value) renderModelList(tenantSelect.value);

        var Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({ icon: 'success', title: i18n.common_confirmUpdateSuccess });
    } catch (e) {
        await handleApiError(e, i18n.common_confirmUpdateFail);
    }
}

async function deleteAiConfig(configId) {
    try {
        var response = await fetch('/system/deleteTelegramAiConfig/' + configId, {
            method: 'DELETE',
            headers: { [csrfHeaderName]: csrfToken }
        });
        if (!response.ok) throw new Error(i18n.common_confirmUpdateFail);

        await loadCurrentAiConfigs();
        // 同步刷新左侧按钮状态
        var tenantSelect = document.getElementById('tenantSelect');
        if (tenantSelect && tenantSelect.value) renderModelList(tenantSelect.value);
    } catch (e) {
        await handleApiError(e, i18n.common_confirmUpdateFail);
    }
}

document.addEventListener('DOMContentLoaded', function() {
    csrfToken = document.querySelector('meta[name="_csrf"]').content;
    csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;
});

// 点击模态框外部关闭
document.addEventListener('click', function(event) {
    var modal = document.getElementById('aiConfigModal');
    if (event.target === modal) closeAiConfigModal();
});

// ESC键关闭模态框
document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape') {
        var modal = document.getElementById('aiConfigModal');
        if (modal && modal.classList.contains('show')) closeAiConfigModal();
    }
});
