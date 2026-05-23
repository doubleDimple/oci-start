let csrfToken, csrfHeaderName;
const i18n = window.I18N;
// 通用配置
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

// 更新状态标识
function updateStatus(provider, status, message) {
    const statusBadge = document.querySelector(`[data-provider="`+ provider+`"] .status-badge`);

    statusBadge.className = `status-badge status-`+status;

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

    statusBadge.innerHTML = `
        <i class="fas fa-`+ icons[status]+`"></i>
        `+ statusTexts[status]+``;
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
        const Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({
            icon: 'warning',
            title: i18n.domain_noDataCopy
        });
        return;
    }

    try {
        await navigator.clipboard.writeText(value);
        const Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({
            icon: 'success',
            title: i18n.domain_copySuccess
        });
    } catch (err) {
        input.select();
        input.setSelectionRange(0, 99999);
        document.execCommand('copy');

        const Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({
            icon: 'success',
            title: i18n.domain_copySuccess
        });
    }
}

// 保存Cloudflare配置
async function saveCloudflareConfig() {
    const form = document.getElementById('cloudflareForm');

    const card = form.closest('.settings-card');
    const enabled = card.querySelector('.switch input[type="checkbox"]').checked;
    const formData = new FormData(form);

    // 构建配置对象
    const config = {
        enabled: enabled,
        apiToken: formData.get('apiToken')?.trim() || '',
        zoneId: formData.get('zoneId')?.trim() || '',
        email: formData.get('email')?.trim() || ''
    };

    // 验证必填项
    if (enabled && !config.apiToken) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.common_plzInputGlobalRequired,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    if (enabled && !config.email) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.common_plzInputGlobalRequired,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    try {
        const result = await Swal.fire({
            title: i18n.common_confirm,
            icon: 'question',
            showCancelButton: true,
            ...swalConfig.confirmButton
        });

        if (result.isConfirmed) {
            updateStatus('cloudflare','pending', i18n.common_saving);

            const response = await fetch('/api/system/updateCloudflareConfig', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify(config)
            });

            await assertResponseOk(response, i18n.domain_cloudflareSaveFail);

            updateStatus('cloudflare','connected');

            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.common_success
            });
        }
    } catch (error) {
        updateStatus('cloudflare','disconnected');
        await handleApiError(error, i18n.domain_cloudflareSaveFail);
    }
}

// 测试Cloudflare连接
async function testCloudflareConnection() {
    const form = document.getElementById('cloudflareForm');
    const formData = new FormData(form);
    const apiToken = formData.get('apiToken')?.trim();

    if (!apiToken) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.common_plzInputGlobalRequired,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    try {
        // 显示加载提示
        Swal.fire({
            title: i18n.domain_testing,
            allowOutsideClick: false,
            didOpen: () => Swal.showLoading()
        });

        updateStatus('cloudflare','pending', i18n.domain_testing);

        const response = await fetch('/api/system/testCloudflareConnection', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            },
            body: JSON.stringify({
                apiToken: apiToken,
                zoneId: formData.get('zoneId')?.trim() || '',
                email: formData.get('email')?.trim() || ''
            })
        });

        await assertResponseOk(response, i18n.domain_cloudflareTestFail);
        updateStatus('cloudflare','connected');
        Swal.fire({
            icon: 'success',
            title: i18n.common_success,
            confirmButtonColor: '#2196f3'
        });

    } catch (error) {
        updateStatus('cloudflare','disconnected');
        await handleApiError(error, i18n.domain_cloudflareTestFail);
    }
}

// 保存EdgeOne配置
async function saveEdgeOneConfig() {
    const form = document.getElementById('edgeOneForm');

    const card = form.closest('.settings-card');
    const enabled = card.querySelector('.switch input[type="checkbox"]').checked;
    const formData = new FormData(form);

    const config = {
        enabled: enabled,
        secretId: formData.get('secretId')?.trim() || '',
        secretKey: formData.get('secretKey')?.trim() || ''
    };

    if (enabled && !config.secretId) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.common_plzInputGlobalRequired,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    if (enabled && !config.secretKey) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.common_plzInputGlobalRequired,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    try {
        const result = await Swal.fire({
            title: i18n.common_confirm,
            icon: 'question',
            showCancelButton: true,
            ...swalConfig.confirmButton
        });

        if (result.isConfirmed) {
            updateStatus('edgeone', 'pending');

            const response = await fetch('/api/system/updateEdgeOneConfig', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify(config)
            });

            await assertResponseOk(response, i18n.domain_edgeOneSaveFail);

            updateStatus('edgeone', 'connected');

            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.common_success
            });
        }
    } catch (error) {
        updateStatus('edgeone', 'disconnected');
        await handleApiError(error, i18n.domain_edgeOneSaveFail);
    }
}

// 测试EdgeOne连接
async function testEdgeOneConnection() {
    const form = document.getElementById('edgeOneForm');
    const formData = new FormData(form);
    const secretId = formData.get('secretId')?.trim();
    const secretKey = formData.get('secretKey')?.trim();

    if (!secretId || !secretKey) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.common_plzInputGlobalRequired,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    try {
        Swal.fire({
            title: i18n.domain_testing,
            allowOutsideClick: false,
            didOpen: () => Swal.showLoading()
        });

        updateStatus('edgeone', 'pending');

        const response = await fetch('/api/system/testEdgeOneConnection', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            },
            body: JSON.stringify({
                secretId: secretId,
                secretKey: secretKey
            })
        });

        await assertResponseOk(response, i18n.domain_edgeOneTestFail);
        updateStatus('edgeone', 'connected');
        Swal.fire({
            icon: 'success',
            title: i18n.common_success,
            confirmButtonColor: '#2196f3'
        });

    } catch (error) {
        updateStatus('edgeone', 'disconnected');
        await handleApiError(error, i18n.domain_edgeOneTestFail);
    }
}

document.addEventListener('DOMContentLoaded', function() {
    csrfToken = document.querySelector('meta[name="_csrf"]').content;
    csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;
})
