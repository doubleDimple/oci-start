
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

// 更新GitHub配置
async function updateGithubConfig(button) {
    const form = document.getElementById('githubForm');
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
    const formData = {
        enabled: enabled,
        username: document.querySelector('input[name="githubUsername"]').value,
        githubId: document.querySelector('input[name="githubId"]').value,
        clientId: document.querySelector('input[name="clientId"]').value,
        clientSecret: document.querySelector('input[name="clientSecret"]').value,
        redirectUri: document.querySelector('input[name="redirectUri"]').value
    };

    // 验证必填字段
    if (!formData.githubId) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.sys_plzGetGithubId,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    if (!formData.clientId || !formData.clientSecret || !formData.redirectUri) {
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
            icon: 'question',
            showCancelButton: true,
            ...swalConfig.confirmButton
        });

        if (result.isConfirmed) {
            button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> '+i18n.common_saving;
            button.disabled = true;

            const response = await fetch('/api/system/updateGithubConfig', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify(formData)
            });

            await assertResponseOk(response, i18n.common_confirmUpdateFail);

            /*const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: 'GitHub配置已更新'
            });*/
        }
    } catch (error) {
        await handleApiError(error, i18n.common_confirmUpdateFail);
    } finally {
        button.innerHTML = '<i class="fas fa-save"></i> '+i18n.sys_githubSave;
        button.disabled = false;
    }
}

// 获取GitHub ID
async function fetchGithubId() {
    const usernameInput = document.querySelector('.github-username-input');
    const idInput = document.querySelector('.github-id-input');
    const fetchBtn = document.querySelector('.github-fetch-btn');

    if (!usernameInput || !idInput || !fetchBtn) {
        await Swal.fire({
            icon: 'error',
            title: i18n.common_error,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    const username = usernameInput.value.trim();
    if (!username) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.sys_plzGetGithubUser,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    const originalBtnContent = fetchBtn.innerHTML;
    fetchBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> '+i18n.sys_loading;
    fetchBtn.disabled = true;

    try {
        const response = await fetch(`https://api.github.com/users/`+username);
        const data = await response.json();

        if (!response.ok) {
            throw new Error(data.message || i18n.sys_githubIdFail);
        }

        idInput.value = data.id;
        usernameInput.value = data.login;

        const Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({
            icon: 'success',
            title: i18n.sys_githubUserSuccess+ `data.name`+` (ID: `+ data.login+`)`
        });
    } catch (error) {
        await handleApiError(error, i18n.sys_githubUserNotFund);
    } finally {
        fetchBtn.innerHTML = originalBtnContent;
        fetchBtn.disabled = false;
    }
}

// 初始化页面
document.addEventListener('DOMContentLoaded', function() {
    csrfToken = document.querySelector('meta[name="_csrf"]').content;
    csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;
    // 获取GitHub ID按钮事件监听
    const fetchBtn = document.querySelector('.github-fetch-btn');
    if (fetchBtn) {
        fetchBtn.addEventListener('click', fetchGithubId);
    }

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

    const codeInput = document.getElementById('mfaVerificationCode');
    if (codeInput) {
        // 回车键触发验证
        codeInput.addEventListener('keypress', function(e) {
            if (e.key === 'Enter') {
                e.preventDefault();
                const verifyBtn = document.querySelector('.mfa-verify-btn');
                if (verifyBtn && !verifyBtn.disabled) {
                    verifyMfaCode(verifyBtn);
                }
            }
        });

        // 限制只能输入数字
        codeInput.addEventListener('input', function(e) {
            this.value = this.value.replace(/\D/g, '');
            if (this.value.length > 6) {
                this.value = this.value.slice(0, 6);
            }
        });

        // 粘贴时也只保留数字
        codeInput.addEventListener('paste', function(e) {
            e.preventDefault();
            const paste = (e.clipboardData || window.clipboardData).getData('text');
            const numericPaste = paste.replace(/\D/g, '').slice(0, 6);
            this.value = numericPaste;
        });
    }
});

// 更新账号信息
async function updateAccount() {
    const form = document.getElementById('passwordForm');
    const formData = new FormData(form);

    // 获取表单数据
    const currentPassword = formData.get('currentPassword');
    const newUsername = formData.get('newUsername');
    const newPassword = formData.get('newPassword');
    const confirmPassword = formData.get('confirmPassword');

    // 验证当前密码
    if (!currentPassword) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.sys_plzCurrentPass,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    // 验证是否有修改
    if (!newUsername && !newPassword) {
        await Swal.fire({
            icon: 'info',
            title: i18n.sys_noEdit,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    // 如果要修改密码，验证两次输入是否一致
    if (newPassword && newPassword !== confirmPassword) {
        await Swal.fire({
            icon: 'error',
            title: i18n.sys_passNoMatch,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    // 确认修改
    const confirmText = [];
    if (newUsername) confirmText.push('用户名');
    if (newPassword) confirmText.push('密码');

    try {
        const result = await Swal.fire({
            title: i18n.common_confirmUpdate,
            icon: 'warning',
            showCancelButton: true,
            confirmButtonColor: '#2196f3',
            cancelButtonColor: '#ff6b6b',
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel
        });

        if (result.isConfirmed) {
            const response = await fetch('/api/system/updatePassword', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify({
                    currentPassword,
                    newUsername: newUsername || undefined,
                    newPassword: newPassword || undefined
                })
            });

            await assertResponseOk(response, i18n.sys_accountUpdateFail);

            if (newPassword) {
                /*await Swal.fire({
                    icon: 'success',
                    title: '修改成功',
                    text: '即将跳转到登录页面...',
                    timer: 2000,
                    showConfirmButton: false
                });*/
                window.location.href = '/login';
            } else {
                // 如果只修改了用户名，显示成功消息
                const Toast = Swal.mixin(swalConfig.toast);
                Toast.fire({
                    icon: 'success'
                });
                // 可能需要刷新页面以显示新用户名
                setTimeout(() => location.reload(), 1500);
            }
        }
    } catch (error) {
        await handleApiError(error, i18n.sys_accountUpdateFail);
    }
}

// 更新MFA配置
async function updateMfaConfig(button) {
    const form = document.getElementById('mfaForm');
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
    const formData = {
        enabled: enabled,
        issuer: document.querySelector('input[name="issuer"]').value || i18n.sys_ociStartVerify
    };

    try {
        const result = await Swal.fire({
            title: i18n.common_confirmUpdate,
            text: enabled ? ''+ i18n.sys_confirmMfa+'' : ''+ i18n.sys_disMfa+'',
            icon: 'question',
            showCancelButton: true,
            ...swalConfig.confirmButton
        });

        if (result.isConfirmed) {
            button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> '+i18n.common_saving;
            button.disabled = true;

            const response = await fetch('/api/system/updateMfaConfig', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify(formData)
            });

            await assertResponseOk(response, i18n.sys_mfaUpdateFail);

            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.sys_mfaEditSuccess
            });

            // 刷新页面以显示二维码
            setTimeout(() => location.reload(), 1500);
        }
    } catch (error) {
        await handleApiError(error, i18n.sys_mfaUpdateFail);
    } finally {
        button.innerHTML = '<i class="fas fa-save"></i> '+i18n.common_confirmUpdate;
        button.disabled = false;
    }
}

// 重新生成MFA密钥
async function regenerateMfaSecret(button) {
    try {
        const result = await Swal.fire({
            title: i18n.sys_mfaSecondGen,
            text: i18n.sys_mfaSecondGenAndRefreshDevice,
            icon: 'warning',
            showCancelButton: true,
            ...swalConfig.confirmButton
        });

        if (result.isConfirmed) {
            button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> '+i18n.common_saving;
            button.disabled = true;

            const response = await fetch('/api/system/regenerateMfaSecret', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
                }
            });

            await assertResponseOk(response, i18n.sys_mfaRegenerateFail);
            setTimeout(() => location.reload(), 1500);
        }
    } catch (error) {
        await handleApiError(error, i18n.sys_mfaRegenerateFail);
    } finally {
        button.innerHTML = '<i class="fas fa-refresh"></i> '+i18n.sys_mfaSecondSecret;
        button.disabled = false;
    }
}

async function verifyMfaCode(button) {
    const codeInput = document.getElementById('mfaVerificationCode');
    if (!codeInput) {
        await Swal.fire({
            icon: 'error',
            title: i18n.common_error,
            text: i18n.sys_mfaCodeInputMissing,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    const code = codeInput.value.trim();

    // 验证输入格式
    if (!code) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.verify_code_placeholder,
            confirmButtonColor: '#2196f3'
        });
        codeInput.focus();
        return;
    }

    if (!/^\d{6}$/.test(code)) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.common_confirmFormatFail,
            confirmButtonColor: '#2196f3'
        });
        codeInput.focus();
        codeInput.select();
        return;
    }

    const originalBtnContent = button.innerHTML;
    button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> '+i18n.sys_verifying;
    button.disabled = true;
    codeInput.disabled = true;

    try {
        const response = await fetch('/api/system/verifyMfaCode', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            },
            body: JSON.stringify({
                code: code
            })
        });

        const result = await assertResponseOk(response, i18n.sys_mfaVerifyRequestFail);

        // 使用ApiResponse格式处理返回结果
        if (result.success) {
            // 验证成功
            await Swal.fire({
                icon: 'success',
                title: i18n.sys_mfaVerifySuccess,
                confirmButtonColor: '#2196f3'
            });

            // 清空输入框
            codeInput.value = '';

            // 显示成功状态的Toast
            /*const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.sys_mfaVerifyPassed
            });*/
        } else {
            // 验证失败
            await Swal.fire({
                icon: 'error',
                title: i18n.sys_mfaVerifyFail,
                text: result.message || i18n.sys_checkDevCode,
                confirmButtonColor: '#2196f3'
            });

            // 清空输入框并聚焦
            codeInput.value = '';
            codeInput.focus();
        }
    } catch (error) {
        await handleApiError(error, i18n.sys_mfaVerifyRequestFail);
        // 验证失败时清空输入框
        codeInput.value = '';
        codeInput.focus();
    } finally {
        button.innerHTML = originalBtnContent;
        button.disabled = false;
        codeInput.disabled = false;
    }
}

/*async function deleteMfaConfig(button) {
    try {
        // 1. 只保留一次确认弹窗
        const result = await Swal.fire({
            title: i18n.sys_confirmMfaDelete,
            text: '此操作将完全移除多因子认证，建议谨慎操作。', // 可选：添加描述文本
            icon: 'warning',
            showCancelButton: true,
            confirmButtonColor: '#ff6b6b',
            cancelButtonColor: '#6c757d',
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel,
            focusCancel: true
        });

        // 2. 如果用户点击取消，直接返回
        if (!result.isConfirmed) {
            return;
        }

        // 3. 开始执行删除逻辑
        button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> 删除中...';
        button.disabled = true;

        const response = await fetch('/api/system/deleteMfaConfig', {
            method: 'DELETE',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            }
        });

        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(errorText || 'MFA配置删除失败');
        }

        // 4. 成功提示
        await Swal.fire({
            icon: 'success',
            title: 'MFA配置已删除',
            text: '多因子认证已被完全移除',
            confirmButtonColor: '#2196f3',
            timer: 1500, // 增加自动关闭，提升体验
            showConfirmButton: false
        });

        // 刷新页面
        location.reload();

    } catch (error) {
        await handleApiError(error, 'MFA配置删除失败');
    } finally {
        // 5. 恢复按钮状态
        button.innerHTML = '<i class="fas fa-trash"></i> 删除MFA';
        button.disabled = false;
    }
}*/
async function deleteMfaConfig(button) {
    try {
        // 1. 只保留一次确认弹窗
        const result = await Swal.fire({
            title: i18n.sys_confirmMfaDelete,
            icon: 'warning',
            showCancelButton: true,
            confirmButtonColor: '#ff6b6b',
            cancelButtonColor: '#6c757d',
            confirmButtonText: i18n.common_confirm,
            cancelButtonText: i18n.common_cancel,
            focusCancel: true
        });

        if (!result.isConfirmed) {
            return;
        }

        button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> '+i18n.mfa_status_deleting;
        button.disabled = true;

        const response = await fetch('/api/system/deleteMfaConfig', {
            method: 'DELETE',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            }
        });

        await assertResponseOk(response, i18n.sys_mfaDeleteFail);
        location.reload();
    } catch (error) {
        await handleApiError(error, i18n.sys_mfaDeleteFail);
    } finally {
        button.innerHTML = '<i class="fas fa-trash"></i> '+i18n.sys_deleteMfa;
        button.disabled = false;
    }
}

async function updateGoogleConfig(button) {
    const form = document.getElementById('googleForm');
    if (!form) {
        return;
    }
    const enabled = form.closest('.settings-card').querySelector('.switch input[type="checkbox"]').checked;
    const emailInput = document.querySelector('#googleForm input[name="googleEmail"]');
    const clientIdInput = document.querySelector('#googleForm input[name="clientId"]');
    const clientSecretInput = document.querySelector('#googleForm input[name="clientSecret"]');
    const redirectUriInput = document.querySelector('#googleForm input[name="redirectUri"]');

    const formData = {
        enabled: enabled,
        email: emailInput ? emailInput.value.trim() : '',
        clientId: clientIdInput ? clientIdInput.value.trim() : '',
        clientSecret: clientSecretInput ? clientSecretInput.value.trim() : '',
        redirectUri: redirectUriInput ? redirectUriInput.value.trim() : ''
    };

    if (enabled) {
        if (!formData.clientId || !formData.clientSecret || !formData.redirectUri || !formData.email) {
            await Swal.fire({
                icon: 'warning',
                title: i18n.notification_plzInputGlobalInfo,
                confirmButtonColor: '#2196f3'
            });
            return;
        }
    }
    try {
        const result = await Swal.fire({
            title: i18n.common_confirmUpdate,
            icon: 'question',
            showCancelButton: true,
            ...swalConfig.confirmButton
        });

        if (result.isConfirmed) {
            const originalBtnHtml = button.innerHTML;
            button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> ' + i18n.common_saving;
            button.disabled = true;
            const response = await fetch('/api/system/updateGoogleConfig', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [csrfHeaderName]: csrfToken
                },
                body: JSON.stringify(formData)
            });

            await assertResponseOk(response, i18n.sys_googleUpdateFail);
            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.common_success
            });
        }
    } catch (error) {
        await handleApiError(error, i18n.sys_googleUpdateFail);
    } finally {
        button.innerHTML = '<i class="fas fa-save"></i> ' + (i18n.sys_githubSave);
        button.disabled = false;
    }
}


// 更新 Logo 名称
async function saveLogoNameOnly(button) {
    const logoInput = document.getElementById('siteLogoInput');
    if (!logoInput) {
        return;
    }

    const newName = logoInput.value.trim();

    if (!newName) {
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
            const originalBtnHtml = button.innerHTML;
            button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> ' + i18n.common_saving;
            button.disabled = true;
            const response = await fetch('/api/system/settings/logo', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/x-www-form-urlencoded',
                    [csrfHeaderName]: csrfToken
                },
                body: new URLSearchParams({ 'logoName': newName })
            });

            const resData = await assertResponseOk(response, i18n.sys_logoUpdateFail);

            // 5. 成功反馈
            const Toast = Swal.mixin(swalConfig.toast);
            Toast.fire({
                icon: 'success',
                title: i18n.common_success
            });
            const brandLogo = document.querySelector('.brand h1');
            if (brandLogo) {
                brandLogo.innerText = newName;
            }
        }
    } catch (error) {
        await handleApiError(error, i18n.sys_logoUpdateFail);
    } finally {
        button.innerHTML = '<i class="fas fa-check"></i> '+ (i18n.sys_githubSave);
        button.disabled = false;
    }
}

// 更新开机频道通知配置
async function updateChannelNotifyConfig(button) {
    const enabled = document.getElementById('channelNotifyEnabled').checked;

    const result = await Swal.fire({
        title: enabled ? i18n.channel_notify_confirm_enable : i18n.channel_notify_confirm_disable,
        icon: 'question',
        showCancelButton: true,
        ...swalConfig.confirmButton
    });

    if (!result.isConfirmed) return;

    try {
        button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> ' + i18n.common_saving;
        button.disabled = true;

        const response = await fetch('/api/system/updateChannelNotifyConfig', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            },
            body: JSON.stringify({ enabled })
        });

        await assertResponseOk(response, i18n.channel_notify_update_fail);

        const Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({ icon: 'success', title: i18n.common_success });
    } catch (error) {
        await handleApiError(error, i18n.channel_notify_update_fail);
    } finally {
        button.innerHTML = '<i class="fas fa-save"></i> ' + i18n.channel_notify_save;
        button.disabled = false;
    }
}

// 更新 Turnstile 配置
async function updateTurnstileConfig(button) {
    const form = document.getElementById('turnstileForm');
    if (!form) return;

    const enabled = document.getElementById('turnstileEnabled').checked;
    const siteKey = form.querySelector('input[name="siteKey"]').value.trim();
    const secretKey = form.querySelector('input[name="secretKey"]').value.trim();

    if (enabled && (!siteKey || !secretKey)) {
        await Swal.fire({
            icon: 'warning',
            title: i18n.sys_turnstilePlzFillKeys,
            confirmButtonColor: '#2196f3'
        });
        return;
    }

    const result = await Swal.fire({
        title: enabled ? i18n.sys_turnstileConfirmEnable : i18n.sys_turnstileDisable,
        icon: 'question',
        showCancelButton: true,
        ...swalConfig.confirmButton
    });

    if (!result.isConfirmed) return;

    try {
        button.innerHTML = '<i class="fas fa-spinner fa-spin"></i> ' + i18n.common_saving;
        button.disabled = true;

        const response = await fetch('/api/system/updateTurnstileConfig', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [csrfHeaderName]: csrfToken
            },
            body: JSON.stringify({ enabled, siteKey, secretKey })
        });

        await assertResponseOk(response, i18n.sys_turnstileUpdateFail);

        const Toast = Swal.mixin(swalConfig.toast);
        Toast.fire({ icon: 'success', title: i18n.common_confirmUpdateSuccess });
    } catch (error) {
        await handleApiError(error, i18n.sys_turnstileUpdateFail);
    } finally {
        button.innerHTML = '<i class="fas fa-save"></i> ' + i18n.sys_turnstileSave;
        button.disabled = false;
    }
}
