/**
 * VPS管理系统 - 登录页面
 * 包含登录、注册、验证码、忘记密码等功能
 */
if (window.top !== window.self) {
    window.top.location.href = window.location.href;
}
let currentResetStep = 1;
let resetSendTime = 0;
let resetToken = null;

let messageEnabled = false;
let mfaEnabled = false;
let currentVerificationMethod = 'message';

// Turnstile 验证状态
let turnstileVerified = false;

function onTurnstileSuccess(token) {
    turnstileVerified = true;
    const content = document.getElementById('loginFormContent');
    if (content) content.style.display = '';
    const hint = document.getElementById('turnstileHint');
    if (hint) hint.style.display = 'none';
}

function onTurnstileExpired() {
    turnstileVerified = false;
    const content = document.getElementById('loginFormContent');
    if (content) content.style.display = 'none';
    const hint = document.getElementById('turnstileHint');
    if (hint) hint.style.display = '';
}

const i18n = window.I18N;

document.addEventListener('DOMContentLoaded', function() {
    document.addEventListener('touchstart', function(event) {
        if (event.touches.length > 1) {
            event.preventDefault();
        }
    }, { passive: false });

    const inputs = document.querySelectorAll('input');
    inputs.forEach(input => {
        input.addEventListener('blur', function() {
            // iOS 键盘收起时页面回弹
            window.scrollTo(0, 0);
        });
    });

    const buttons = document.querySelectorAll('.btn');
    buttons.forEach(button => {
        button.addEventListener('touchstart', function() {
            this.style.transform = 'scale(0.98)';
        });
        button.addEventListener('touchend', function() {
            this.style.transform = 'scale(1)';
        });
    });

    updateResetStep();
});

document.addEventListener('DOMContentLoaded', async function() {
    const loginButton = document.getElementById('loginButton');

    try {
        const messageResponse = await fetch('/api/config/message-enabled');
        messageEnabled = await messageResponse.json();

        // 获取MFA配置
        const mfaResponse = await fetch('/api/config/mfa-enabled');
        mfaEnabled = await mfaResponse.json();

        setupVerificationMethods(messageEnabled, mfaEnabled, loginButton);
    } catch (error) {
        console.error('获取配置失败:', error);
        loginButton.disabled = false;
        loginButton.classList.remove('disabled');
    }
});

// 设置验证方式
function setupVerificationMethods(messageEnabled, mfaEnabled, loginButton) {
    const verificationGroup = document.getElementById('verificationGroup');
    const mfaGroup = document.getElementById('mfaGroup');
    const verificationChoice = document.getElementById('verificationChoice');

    if (messageEnabled && mfaEnabled) {
        verificationChoice.style.display = 'block';
        verificationGroup.style.display = 'block';
        mfaGroup.style.display = 'none';
        currentVerificationMethod = 'message';
    } else if (messageEnabled) {
        verificationGroup.style.display = 'block';
        currentVerificationMethod = 'message';
    } else if (mfaEnabled) {
        mfaGroup.style.display = 'block';
        currentVerificationMethod = 'mfa';
    }

    loginButton.disabled = false;
    loginButton.classList.remove('disabled');
}

function switchVerificationMethod(method) {
    const verificationGroup = document.getElementById('verificationGroup');
    const mfaGroup = document.getElementById('mfaGroup');
    const messageTab = document.getElementById('messageTab');
    const mfaTab = document.getElementById('mfaTab');

    currentVerificationMethod = method;

    if (method === 'message') {
        verificationGroup.style.display = 'block';
        mfaGroup.style.display = 'none';
        messageTab.classList.add('active');
        mfaTab.classList.remove('active');

        // 清除MFA验证码
        const mfaCodeInput = document.getElementById('mfaCode');
        if (mfaCodeInput) {
            mfaCodeInput.value = '';
        }
    } else {
        verificationGroup.style.display = 'none';
        mfaGroup.style.display = 'block';
        messageTab.classList.remove('active');
        mfaTab.classList.add('active');

        // 清除消息验证码
        const verificationCodeInput = document.getElementById('verificationCode');
        if (verificationCodeInput) {
            verificationCodeInput.value = '';
        }
    }
}

function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func.apply(this, args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

function switchTab(tab) {
    const loginForm = document.getElementById('loginForm');
    const registerForm = document.getElementById('registerForm');
    const tabs = document.querySelectorAll('.tab');

    if (tab === 'login') {
        loginForm.style.display = 'block';
        registerForm.style.display = 'none';
        tabs[0].classList.add('active');
        tabs[1].classList.remove('active');
    } else {
        loginForm.style.display = 'none';
        registerForm.style.display = 'block';
        tabs[0].classList.remove('active');
        tabs[1].classList.add('active');
    }
}

document.getElementById('registerForm')?.addEventListener('submit', async function(e) {
    e.preventDefault();
    const password = document.getElementById('registerPassword').value;
    const confirmPassword = document.getElementById('confirmPassword').value;

    if (password !== confirmPassword) {
        showMessage('error', i18n.login_passwd_match);
        return;
    }

    try {
        const response = await fetch('/api/register-first-user', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                username: document.getElementById('registerUsername').value,
                password: password
            })
        });

        if (response.ok) {
            showMessage('success', i18n.login_register_success);
            setTimeout(() => {
                window.location.href = '/login?registered=true';
            }, 1500);
        } else {
            const error = await response.json();
            throw new Error(error.message || i18n.login_register_fail);
        }
    } catch (error) {
        showMessage('error', i18n.login_register_fail + error.message);
    }
});


/** 抖动空输入框（无弹框提示） */
function shakeEmptyInputs(inputs) {
    const list = (inputs || []).filter(Boolean);
    if (!list.length) return;
    list.forEach((el) => {
        el.classList.remove('input-shake');
        // 强制重启动画
        void el.offsetWidth;
        el.classList.add('input-shake');
        const onEnd = () => {
            el.classList.remove('input-shake');
            el.removeEventListener('animationend', onEnd);
        };
        el.addEventListener('animationend', onEnd);
    });
    // 聚焦第一个空字段
    try {
        list[0].focus();
    } catch (e) { /* ignore */ }
}

function isBlank(value) {
    return !value || !String(value).trim();
}

document.getElementById('loginForm')?.addEventListener('submit', async function(e) {
    e.preventDefault();

    const usernameInput = document.getElementById('username');
    const passwordInput = document.getElementById('password');
    const username = usernameInput ? usernameInput.value : '';
    const rawPassword = passwordInput ? passwordInput.value : '';

    // 未填写的必填项：抖动提示，不弹错误框
    const emptyFields = [];
    if (isBlank(username)) emptyFields.push(usernameInput);
    if (isBlank(rawPassword)) emptyFields.push(passwordInput);

    if (messageEnabled || mfaEnabled) {
        const verificationCodeInput = document.getElementById('verificationCode');
        const mfaCodeInput = document.getElementById('mfaCode');
        const verificationCode = verificationCodeInput?.value;
        const mfaCode = mfaCodeInput?.value;
        const verificationVisible = verificationCodeInput &&
            verificationCodeInput.offsetParent !== null;
        const mfaVisible = mfaCodeInput && mfaCodeInput.offsetParent !== null;

        if (messageEnabled && mfaEnabled) {
            // 双开时：当前激活方式对应的输入框不能为空
            if (currentVerificationMethod === 'message' && verificationVisible && isBlank(verificationCode)) {
                emptyFields.push(verificationCodeInput);
            } else if (currentVerificationMethod === 'mfa' && mfaVisible && isBlank(mfaCode)) {
                emptyFields.push(mfaCodeInput);
            } else if (!verificationCode && !mfaCode) {
                if (verificationVisible) emptyFields.push(verificationCodeInput);
                else if (mfaVisible) emptyFields.push(mfaCodeInput);
            }
        } else if (messageEnabled && verificationVisible && isBlank(verificationCode)) {
            emptyFields.push(verificationCodeInput);
        } else if (mfaEnabled && mfaVisible && isBlank(mfaCode)) {
            emptyFields.push(mfaCodeInput);
        }
    }

    if (emptyFields.length) {
        shakeEmptyInputs(emptyFields);
        return;
    }

    let finalPassword = rawPassword;
    if (window.RSA_PUBLIC_KEY && window.RSA_PUBLIC_KEY.length > 0) {
        const encrypt = new JSEncrypt();
        encrypt.setPublicKey(window.RSA_PUBLIC_KEY);
        const encrypted = encrypt.encrypt(rawPassword);
        if (encrypted) {
            finalPassword = encrypted;
            console.log("RSA 加密成功");
        } else {
            console.error("RSA 加密失败，请检查公钥格式");
        }
    }
    const verificationCodeInput = document.getElementById('verificationCode');
    const mfaCodeInput = document.getElementById('mfaCode');
    if (messageEnabled && mfaEnabled) {
        const vCode = verificationCodeInput?.value;
        const mCode = mfaCodeInput?.value;
        if (vCode && !mCode) {
            if (verificationCodeInput) verificationCodeInput.setAttribute('name', 'verificationCode');
            if (mfaCodeInput) mfaCodeInput.removeAttribute('name');
        } else if (mCode && !vCode) {
            if (mfaCodeInput) mfaCodeInput.setAttribute('name', 'mfaCode');
            if (verificationCodeInput) verificationCodeInput.removeAttribute('name');
        } else if (vCode && mCode) {
            if (currentVerificationMethod === 'message') {
                if (verificationCodeInput) verificationCodeInput.setAttribute('name', 'verificationCode');
                if (mfaCodeInput) mfaCodeInput.removeAttribute('name');
            } else {
                if (mfaCodeInput) mfaCodeInput.setAttribute('name', 'mfaCode');
                if (verificationCodeInput) verificationCodeInput.removeAttribute('name');
            }
        }
    } else if (messageEnabled) {
        if (verificationCodeInput) verificationCodeInput.setAttribute('name', 'verificationCode');
        if (mfaCodeInput) mfaCodeInput.removeAttribute('name');
    } else if (mfaEnabled) {
        if (mfaCodeInput) mfaCodeInput.setAttribute('name', 'mfaCode');
        if (verificationCodeInput) verificationCodeInput.removeAttribute('name');
    }
    const loginButton = document.getElementById('loginButton');
    loginButton.disabled = true;
    loginButton.innerHTML = '<i class="fas fa-spinner fa-spin"></i><span>'+i18n.login_input_login_loading+'</span>';

    try {
        const formData = new FormData(this);
        formData.set('password', finalPassword);
        const response = await fetch('/perform_login', {
            method: 'POST',
            body: formData,
            credentials: 'include',
            headers: {
                'Accept': 'application/json',
                'X-Requested-With': 'XMLHttpRequest'
            },
            redirect: 'manual'
        });
        if (response.type === 'opaqueredirect' || response.status === 0 || response.status === 302) {
            window.location.href = '/index';
        } else if (response.ok) {
            const text = await response.text();
            // 1. 判断是否密码错误退回了登录页
            if (text.includes('error=true') || (text.includes('login') && text.includes('form'))) {
                showMessage('error', i18n.login_input_login_userOrNameError);
                heroCryOnLoginFail();
            } else {
                // 2. 核心修改：尝试解析后端传来的 JSON
                try {
                    const resJson = JSON.parse(text);
                    // 如果后端传了 redirectUrl，就听后端的
                    if (resJson.redirectUrl) {
                        window.location.href = resJson.redirectUrl;
                        return; // 跳转后直接结束
                    }
                } catch (parseError) {
                    console.log('响应不是JSON，使用兜底跳转');
                }
                window.location.href = '/index';
            }
        } else {
            showMessage('error', i18n.login_input_login_failAndRetry);
            heroCryOnLoginFail();
        }

    } catch (error) {
        showMessage('error', i18n.common_network_error);
        heroCryOnLoginFail();
    }
    loginButton.disabled = false;
    loginButton.innerHTML = '<i class="fas fa-sign-in-alt"></i><span>'+i18n.login_title+'</span>';
});

let lastSendTime = 0;
const SEND_INTERVAL = 60000;

document.getElementById('sendCodeBtn')?.addEventListener('click', async function() {
    const now = Date.now();

    if (now - lastSendTime < SEND_INTERVAL) {
        const remainingTime = Math.ceil((SEND_INTERVAL - (now - lastSendTime)) / 1000);
        showMessage('error', `请等待 ${remainingTime} 秒后再次发送`);
        return;
    }

    const username = document.getElementById('username').value;
    if (!username) {
        showMessage('error', i18n.login_username_placeholder);
        return;
    }

    try {
        this.disabled = true;
        this.innerHTML = '<i class="fas fa-spinner fa-spin"></i><span>'+i18n.login_input_sending+'</span>';

        const response = await fetch('/api/send-verification-code', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ username })
        });

        if (response.ok) {
            showMessage('success', i18n.login_input_code_success);
            lastSendTime = now;
            startCountdown(this);
        } else {
            const error = await response.json();
            throw new Error(error.message || i18n.login_input_code_fail);
        }
    } catch (error) {
        showMessage('error', error.message);
        this.disabled = false;
        this.innerHTML = '<i class="fas fa-paper-plane"></i><span>'+i18n.login_btn_send_code+'</span>';
    }
});

// 倒计时功能
function startCountdown(button) {
    let countdown = 60;
    button.disabled = true;
    // 立即更新按钮文字，不等待第一个 tick
    button.innerHTML = `<i class="fas fa-clock"></i><span>${countdown}${i18n.login_input_seconds_retry}</span>`;

    const timer = setInterval(() => {
        countdown--;
        if (countdown > 0) {
            button.innerHTML = `<i class="fas fa-clock"></i><span>${countdown}${i18n.login_input_seconds_retry}</span>`;
        } else {
            clearInterval(timer);
            button.disabled = false;
            button.innerHTML = '<i class="fas fa-paper-plane"></i><span>'+i18n.login_btn_send_code+'</span>';
        }
    }, 1000);
}

// 显示消息提示
function showMessage(type, content) {
    const container = document.querySelector('.login-card');
    const existingMessage = container.querySelector('.message');
    if (existingMessage) {
        existingMessage.remove();
    }

    const messageDiv = document.createElement('div');
    messageDiv.className = `message ${type}-message`;

    const icon = document.createElement('i');
    icon.className = 'fas fa-' + (type === 'error' ? 'exclamation' : 'check') + '-circle';

    messageDiv.appendChild(icon);
    messageDiv.appendChild(document.createTextNode(content));

    container.insertBefore(messageDiv, container.firstChild);

    // 成功消息时恢复正常表情
    if (type === 'success' && typeof window.setHeroMood === 'function') {
        window.setHeroMood('normal');
    }

    // 自动消失
    setTimeout(() => {
        messageDiv.remove();
    }, 3000);
}

/** 登录失败时左侧角色变哭脸 */
function heroCryOnLoginFail() {
    if (typeof window.setHeroMood === 'function') {
        window.setHeroMood('cry');
    }
}

// GitHub 登录
document.getElementById('githubLoginBtn')?.addEventListener('click', async function() {
    handleOAuthLogin(this, '/api/github/login/url', '<i class="fab fa-github"></i>', 'GitHub');
});

// Google 登录 (新增)
document.getElementById('googleLoginBtn')?.addEventListener('click', async function() {
    handleOAuthLogin(this, '/api/google/login/url', '<i class="fab fa-google"></i>', 'Google');
});

function openForgotPasswordModal() {
    document.getElementById('forgotPasswordModal').classList.add('show');
    document.body.style.overflow = 'hidden';
    resetModal();
}

function closeForgotPasswordModal() {
    document.getElementById('forgotPasswordModal').classList.remove('show');
    document.body.style.overflow = '';
    resetModal();
}

function resetModal() {
    currentResetStep = 1;
    resetToken = null;
    updateResetStep();
    document.getElementById('resetUsername').value = '';
    document.getElementById('resetVerificationCode').value = '';

    const messageContainer = document.getElementById('resetMessage');
    messageContainer.innerHTML = '';

    const sendBtn = document.getElementById('resetSendCodeBtn');
    sendBtn.disabled = false;
    sendBtn.innerHTML = '<i class="fas fa-paper-plane"></i><span>'+i18n.login_btn_send_code+'</span>';
}

function updateResetStep() {
    const steps = ['step1', 'step2', 'step3'];
    const stepContents = ['resetStep1', 'resetStep2', 'resetStep3'];
    steps.forEach((stepId, index) => {
        const stepElement = document.getElementById(stepId);
        if (stepElement) {
            const stepNum = index + 1;
            stepElement.classList.remove('active', 'completed');
            if (stepNum < currentResetStep) {
                stepElement.classList.add('completed');
            } else if (stepNum === currentResetStep) {
                stepElement.classList.add('active');
            }
        }
    });

    stepContents.forEach((contentId, index) => {
        const contentElement = document.getElementById(contentId);
        if (contentElement) {
            contentElement.classList.toggle('active', index + 1 === currentResetStep);
        }
    });

    const progressLine = document.getElementById('progressLine');
    if (progressLine) {
        const progressWidth = ((currentResetStep - 1) / (steps.length - 1)) * 100;
        progressLine.style.width = `calc(${progressWidth}% - 16px)`;
    }

    // 2. 关键：防御性修改按钮文本
    const nextBtn = document.getElementById('resetNextBtn');
    const cancelBtn = document.getElementById('resetCancelBtn');

    if (nextBtn) {
        if (currentResetStep === 1) {
            nextBtn.textContent = i18n.login_reset_step1;
            nextBtn.style.display = 'block';
        } else if (currentResetStep === 2) {
            nextBtn.textContent = i18n.login_reset_step2;
            nextBtn.style.display = 'block';
        } else if (currentResetStep === 3) {
            nextBtn.style.display = 'none';
        }
    }

    if (cancelBtn) {
        if (currentResetStep === 1) {
            cancelBtn.textContent = i18n.common_cancel;
        } else if (currentResetStep === 2) {
            cancelBtn.textContent = i18n.common_rollback;
        } else if (currentResetStep === 3) {
            cancelBtn.textContent = i18n.common_finish;
        }
    }
}

async function nextResetStep() {
    if (currentResetStep === 1) {
        await verifyResetIdentity();
    } else if (currentResetStep === 2) {
        await executePasswordReset();
    }
}

async function verifyResetIdentity() {
    const username = document.getElementById('resetUsername').value;
    const verificationCode = document.getElementById('resetVerificationCode').value;

    if (!username) {
        showResetMessage('error', i18n.login_username_placeholder);
        return;
    }

    if (!verificationCode) {
        showResetMessage('error', i18n.login_verify_code_placeholder);
        return;
    }

    try {
        const response = await fetch('/api/verify-reset-code', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                username,
                verificationCode
            })
        });

        const result = await response.json();

        if (result.success) {
            resetToken = result.data.resetToken;
            currentResetStep = 2;
            updateResetStep();
            showResetMessage('success', i18n.login_input_verify_success);
        } else {
            showResetMessage('error', result.message || i18n.login_input_verify_fail);
        }
    } catch (error) {
        showResetMessage('error', i18n.login_input_verify_fail + error.message);
    }
}

async function executePasswordReset() {
    const username = document.getElementById('resetUsername').value;

    if (!resetToken) {
        showResetMessage('error', i18n.login_input_verify_fail_retry);
        currentResetStep = 1;
        updateResetStep();
        return;
    }

    try {
        const nextBtn = document.getElementById('resetNextBtn');
        nextBtn.disabled = true;
        nextBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> '+i18n.login_input_resetting;

        const response = await fetch('/api/reset-password', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                username,
                resetToken
            })
        });

        const result = await response.json();

        if (result.success) {
            currentResetStep = 3;
            updateResetStep();
            showResetMessage('success', result.message);
            resetToken = null;
            setTimeout(() => {
                window.location.href = '/login?reset=success';
            }, 2000);
        } else {
            showResetMessage('error', result.message || i18n.login_input_resetting_error);
            nextBtn.disabled = false;
            nextBtn.innerHTML = i18n.login_reset_title;
        }
    } catch (error) {
        showResetMessage('error', i18n.login_input_resetting_error + error.message);
        const nextBtn = document.getElementById('resetNextBtn');
        nextBtn.disabled = false;
        nextBtn.innerHTML = i18n.login_reset_title;
    }
}

document.getElementById('resetSendCodeBtn')?.addEventListener('click', async function() {
    const now = Date.now();

    if (now - resetSendTime < SEND_INTERVAL) {
        const remainingTime = Math.ceil((SEND_INTERVAL - (now - resetSendTime)) / 1000);
        showResetMessage('error', `${remainingTime} `+i18n.login_input_send_retry);
        return;
    }

    const username = document.getElementById('resetUsername').value;
    if (!username) {
        showResetMessage('error', i18n.login_username_placeholder);
        return;
    }

    try {
        this.disabled = true;
        this.innerHTML = '<i class="fas fa-spinner fa-spin"></i><span>'+i18n.login_input_sending+'</span>';

        const response = await fetch('/api/send-reset-code', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({ username })
        });

        if (response.ok) {
            showResetMessage('success', i18n.login_send_yourDevice);
            resetSendTime = now;
            startResetCountdown(this);
        } else {
            const error = await response.json();
            throw new Error(error.message || i18n.login_input_code_fail);
        }
    } catch (error) {
        showResetMessage('error', error.message);
        this.disabled = false;
        this.innerHTML = '<i class="fas fa-paper-plane"></i><span>'+i18n.login_btn_send_code+'</span>';
    }
});

function startResetCountdown(button) {
    let countdown = 60;
    button.disabled = true;
    // 立即更新按钮文字，不等待第一个 tick
    button.innerHTML = `<i class="fas fa-clock"></i><span>${countdown}</span>`;

    const timer = setInterval(() => {
        countdown--;
        if (countdown > 0) {
            button.innerHTML = `<i class="fas fa-clock"></i><span>${countdown}</span>`;
        } else {
            clearInterval(timer);
            button.disabled = false;
            button.innerHTML = '<i class="fas fa-paper-plane"></i><span>'+i18n.login_btn_send_code+'</span>';
        }
    }, 1000);
}

function showResetMessage(type, content) {
    const container = document.getElementById('resetMessage');
    container.innerHTML = '';

    const messageDiv = document.createElement('div');
    messageDiv.className = `message ${type}-message`;
    messageDiv.style.marginTop = '16px';

    const icon = document.createElement('i');
    icon.className = 'fas fa-' + (type === 'error' ? 'exclamation' : type === 'warning' ? 'exclamation-triangle' : 'check') + '-circle';

    messageDiv.appendChild(icon);
    messageDiv.appendChild(document.createTextNode(content));

    container.appendChild(messageDiv);

    setTimeout(() => {
        messageDiv.remove();
    }, 3000);
}

document.getElementById('forgotPasswordModal')?.addEventListener('click', function(e) {
    if (e.target === this) {
        closeForgotPasswordModal();
    }
});

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' && document.getElementById('forgotPasswordModal').classList.contains('show')) {
        closeForgotPasswordModal();
    }
});

async function handleOAuthLogin(btn, urlEndpoint, iconHtml, name) {
    const originalHtml = btn.innerHTML;
    try {
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i><span> ' + (i18n.login_input_step_next || 'Loading...') + '</span>';
        const rememberMeChecked = document.querySelector('input[name="remember-me"]')?.checked;
        const targetUrl = new URL(urlEndpoint, window.location.origin);
        if (rememberMeChecked) {
            targetUrl.searchParams.append('remember-me', 'on');
        }
        const response = await fetch(targetUrl.toString());
        if (!response.ok) {
            throw new Error('Get Login URL Failed');
        }
        const loginUrl = await response.text();
        window.location.href = loginUrl;
    } catch (error) {
        console.error(name + ' Login Error:', error);
        btn.disabled = false;
        if(typeof originalHtml !== 'undefined') btn.innerHTML = originalHtml;
        showMessage('error', i18n.common_network_error || 'Login failed');
    }
}