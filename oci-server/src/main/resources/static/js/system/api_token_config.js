let csrfToken, csrfHeaderName;
const i18n = window.I18N;
// 通用配置
const swalConfig = {
    confirmButton: {
        confirmButtonColor: '#2196f3',
        cancelButtonColor: '#ff6b6b',
        confirmButtonText: '确认',
        cancelButtonText: '取消'
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
async function handleApiError(error, title = '操作失败') {
    if (window.OciRequestUtils && typeof window.OciRequestUtils.showApiError === 'function') {
        await window.OciRequestUtils.showApiError(error, title);
        return;
    }

    await Swal.fire({
        icon: 'error',
        title: title,
        text: (error && error.message) || error || '网络异常或服务器无响应，请稍后重试',
        confirmButtonColor: '#2196f3'
    });
}

async function assertResponseOk(response, fallbackMessage = '操作失败') {
    if (window.OciRequestUtils && typeof window.OciRequestUtils.assertApiResponse === 'function') {
        return await window.OciRequestUtils.assertApiResponse(response, fallbackMessage);
    }
    if (!response.ok) {
        throw new Error(await response.text() || fallbackMessage);
    }
    const text = await response.text();
    return text ? JSON.parse(text) : null;
}

// 生成新Token
async function generateToken() {
    const form = document.getElementById('tokenConfigForm');
    const formData = new FormData(form);

    const config = {
        enabled: true,
        tokenName: formData.get('tokenName'),
        expirationDays: parseInt(formData.get('expirationDays')),
        description: formData.get('description'),
        allowSwaggerAccess: true
    };

    // 验证必填项
    if (!config.tokenName || !config.tokenName.trim()) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.token_require_name,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    try {
        const result = await Swal.fire({
            title: i18n.token_confirm,
            text: i18n.token_newAndOldTokenExpire,
            icon: 'question',
            showCancelButton: true,
            ...swalConfig.confirmButton
        });

        if (result.isConfirmed) {
            const response = await fetch('/api/system/generateApiToken', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify(config)
            });

            const tokenResponse = await assertResponseOk(response, i18n.token_genFail);

            // 显示生成的Token
            displayGeneratedToken(tokenResponse);

            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.token_genSuccess
            });
            setTimeout(() => {
                window.location.reload();
            }, 3000);
        }
    } catch (error) {
        await handleApiError(error, 'Token生成失败');
    }
}

function displayGeneratedToken(tokenResponse) {
    const tokenDisplayCard = document.getElementById('tokenDisplayCard');
    const generatedTokenInput = document.getElementById('generatedToken');
    const tokenExpirationInfo = document.getElementById('tokenExpirationInfo');

    generatedTokenInput.value = tokenResponse.tokenValue;
    tokenExpirationInfo.textContent = tokenResponse.daysUntilExpiration+`天 (`+tokenResponse.expiresAt +`)`;

    tokenDisplayCard.style.display = 'block';
    tokenDisplayCard.scrollIntoView({ behavior: 'smooth' });
}

// 复制Token
async function copyToken() {
    const tokenInput = document.getElementById('generatedToken');

    try {
        await navigator.clipboard.writeText(tokenInput.value);

        const Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({
            icon: 'success',
            title: i18n.token_alreadyCopy
        });
    } catch (error) {
        tokenInput.select();
        tokenInput.setSelectionRange(0, 99999);

        try {
            document.execCommand('copy');
            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.token_alreadyCopy
            });
        } catch (err) {
            await handleApiError('fail');
        }
    }
}

// 撤销Token
async function revokeToken() {
    try {
        const result = await Swal.fire({
            title: i18n.token_delete,
            text: i18n.token_ApiCancel,
            icon: 'warning',
            showCancelButton: true,
            ...swalConfig.confirmButton
        });

        if (result.isConfirmed) {
            const response = await fetch('/api/system/revokeApiToken', {
                method: 'POST',
                headers: {
                    [csrfHeaderName]: csrfToken
                }
            });

            await assertResponseOk(response, 'Token撤销失败');

            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.token_ApiAlreadyCancel
            });

            // 刷新页面
            setTimeout(() => {
                window.location.reload();
            }, 1500);
        }
    } catch (error) {
        await handleApiError(error, 'Token撤销失败');
    }
}

document.addEventListener('DOMContentLoaded', function() {
    csrfToken = document.querySelector('meta[name="_csrf"]').content;
    csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;
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
});

async function copyCurrentToken() {
    const tokenInput = document.getElementById('currentToken');

    try {
        await navigator.clipboard.writeText(tokenInput.value);

        const Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({
            icon: 'success',
            title: i18n.token_alreadyCopy
        });
    } catch (error) {
        tokenInput.select();
        tokenInput.setSelectionRange(0, 99999);

        try {
            document.execCommand('copy');
            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.token_alreadyCopy
            });
        } catch (err) {
            await handleApiError('复制失败，请手动选择复制');
        }
    }
}

// 复制代码片段
async function copyCode(text) {
    try {
        await navigator.clipboard.writeText(text);

        const Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({
            icon: 'success',
            title: i18n.token_codeCopy
        });
    } catch (error) {
        await handleApiError('复制失败，请手动选择复制');
    }
}

function getCurlExample() {
    const currentToken = document.getElementById('currentToken');
    const token = currentToken ? currentToken.value : '{your_token}';

    return `curl -X GET "http://localhost:9856/open-api/v1/system/info" \\
     -H "Authorization: Bearer `+  token+`"`;
}
