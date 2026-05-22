<!DOCTYPE html>
<html lang="${currentLocale!'zh-CN'}">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <meta name="mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <title>登录 - OCI-START</title>
    <!-- 防止主题切换闪烁 -->
    <script>(function(){var t=localStorage.getItem('mob-theme')||'dark';var d=document.documentElement;d.setAttribute('data-theme',t==='auto'?(window.matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light'):t);})();</script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/mobile-app.css">
    <script src="/js/common/jsencrypt.min.js"></script>
    <#if turnstileEnabled?? && turnstileEnabled>
    <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
    </#if>
    <style>
        * { box-sizing: border-box; }
        body {
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            background: var(--mob-bg);
            padding: 24px 16px;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        }
        .mob-login-wrap {
            width: 100%;
            max-width: 420px;
        }
        .mob-login-brand {
            display: flex;
            align-items: center;
            gap: 14px;
            margin-bottom: 32px;
            justify-content: center;
        }
        .mob-login-logo {
            width: 48px;
            height: 48px;
            border-radius: 14px;
            background: var(--mob-primary);
            color: #fff;
            display: flex;
            align-items: center;
            justify-content: center;
            font-weight: 900;
            font-size: 18px;
            letter-spacing: .4px;
            flex-shrink: 0;
        }
        .mob-login-brand-text { line-height: 1.1; }
        .mob-login-title {
            font-size: 22px;
            font-weight: 800;
            color: var(--mob-text);
        }
        .mob-login-sub {
            font-size: 13px;
            color: var(--mob-text-muted);
            margin-top: 4px;
        }
        .mob-login-card {
            background: var(--mob-surface);
            border: 1px solid var(--mob-border);
            border-radius: var(--mob-radius);
            padding: 28px 24px;
            box-shadow: var(--mob-shadow);
        }
        .mob-login-section-title {
            font-size: 16px;
            font-weight: 700;
            color: var(--mob-text);
            margin-bottom: 20px;
        }
        /* Tab group for login/register */
        .mob-login-tabs {
            display: flex;
            gap: 4px;
            background: var(--mob-bg);
            border-radius: 10px;
            padding: 4px;
            margin-bottom: 22px;
        }
        .mob-login-tab {
            flex: 1;
            text-align: center;
            padding: 8px 0;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 600;
            color: var(--mob-text-muted);
            cursor: pointer;
            transition: all 0.2s;
            user-select: none;
        }
        .mob-login-tab.active {
            background: var(--mob-surface);
            color: var(--mob-text);
            box-shadow: 0 1px 4px rgba(0,0,0,0.2);
        }
        /* Form fields */
        .mob-field {
            margin-bottom: 18px;
        }
        .mob-field label {
            display: block;
            font-size: 13px;
            font-weight: 600;
            color: var(--mob-text-muted);
            margin-bottom: 8px;
            letter-spacing: .3px;
        }
        .mob-field input {
            width: 100%;
            background: var(--mob-bg);
            border: 1px solid var(--mob-border);
            border-radius: 10px;
            padding: 13px 14px;
            font-size: 16px;
            color: var(--mob-text);
            outline: none;
            transition: border-color 0.2s;
            -webkit-appearance: none;
        }
        .mob-field input:focus {
            border-color: var(--mob-primary);
        }
        .mob-field input::placeholder {
            color: var(--mob-text-muted);
            opacity: 0.6;
        }
        /* Code row */
        .mob-code-row {
            display: flex;
            gap: 10px;
            align-items: stretch;
        }
        .mob-code-row input {
            flex: 1;
        }
        .mob-send-code-btn {
            flex-shrink: 0;
            padding: 0 16px;
            border-radius: 10px;
            border: 1px solid var(--mob-primary);
            background: transparent;
            color: var(--mob-primary);
            font-size: 13px;
            font-weight: 600;
            cursor: pointer;
            white-space: nowrap;
            transition: background 0.15s;
        }
        .mob-send-code-btn:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        /* Meta row */
        .mob-login-meta {
            display: flex;
            align-items: center;
            justify-content: space-between;
            margin: 4px 0 22px;
        }
        .mob-remember {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 14px;
            color: var(--mob-text);
            cursor: pointer;
        }
        .mob-remember input[type="checkbox"] {
            width: 16px;
            height: 16px;
            accent-color: var(--mob-primary);
            cursor: pointer;
        }
        .mob-forgot-link {
            font-size: 13px;
            color: var(--mob-text-muted);
            text-decoration: none;
        }
        .mob-forgot-link:hover { color: var(--mob-primary); }
        /* Submit button */
        .mob-login-submit {
            width: 100%;
            padding: 14px;
            border-radius: 12px;
            border: none;
            background: var(--mob-primary);
            color: #fff;
            font-size: 16px;
            font-weight: 700;
            cursor: pointer;
            transition: opacity 0.2s;
        }
        .mob-login-submit:disabled {
            opacity: 0.5;
            cursor: not-allowed;
        }
        .mob-login-submit:active { opacity: 0.85; }
        /* OAuth buttons */
        .mob-oauth-divider {
            display: flex;
            align-items: center;
            gap: 12px;
            margin: 18px 0;
            color: var(--mob-text-muted);
            font-size: 12px;
        }
        .mob-oauth-divider::before, .mob-oauth-divider::after {
            content: '';
            flex: 1;
            height: 1px;
            background: var(--mob-border);
        }
        .mob-oauth-row {
            display: flex;
            gap: 10px;
        }
        .mob-oauth-btn {
            flex: 1;
            display: flex;
            align-items: center;
            justify-content: center;
            gap: 8px;
            padding: 12px;
            border-radius: 10px;
            border: 1px solid var(--mob-border);
            background: var(--mob-bg);
            color: var(--mob-text);
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
            transition: border-color 0.15s;
        }
        .mob-oauth-btn:active { border-color: var(--mob-primary); }
        /* Error message */
        .mob-login-error {
            color: #f04747;
            font-size: 13px;
            margin-bottom: 14px;
            text-align: center;
            display: none;
        }
        /* Reset modal */
        .mob-modal-overlay {
            display: none;
            position: fixed;
            inset: 0;
            background: rgba(0,0,0,0.6);
            backdrop-filter: blur(4px);
            z-index: 1000;
            align-items: flex-end;
            justify-content: center;
        }
        .mob-modal-overlay.show { display: flex; }
        .mob-modal-sheet {
            width: 100%;
            max-width: 500px;
            background: var(--mob-surface);
            border-radius: 20px 20px 0 0;
            padding: 24px 20px 32px;
            border: 1px solid var(--mob-border);
        }
        .mob-modal-title {
            font-size: 17px;
            font-weight: 700;
            color: var(--mob-text);
            margin-bottom: 16px;
        }
        .mob-modal-actions {
            display: flex;
            gap: 10px;
            margin-top: 16px;
        }
        .mob-modal-btn {
            flex: 1;
            padding: 12px;
            border-radius: 10px;
            border: 1px solid var(--mob-border);
            background: transparent;
            color: var(--mob-text);
            font-size: 14px;
            font-weight: 600;
            cursor: pointer;
        }
        .mob-modal-btn-primary {
            background: var(--mob-primary);
            color: #fff;
            border-color: var(--mob-primary);
        }
        /* Toast */
        .mob-login-toast {
            position: fixed;
            top: 20px;
            left: 50%;
            transform: translateX(-50%) translateY(-80px);
            background: #333;
            color: #fff;
            padding: 10px 20px;
            border-radius: 20px;
            font-size: 14px;
            transition: transform 0.3s;
            z-index: 2000;
            white-space: nowrap;
        }
        .mob-login-toast.show { transform: translateX(-50%) translateY(0); }
        .mob-login-toast.success { background: #43b581; }
        .mob-login-toast.error { background: #f04747; }
    </style>
</head>
<body>
<div class="mob-login-wrap">
    <!-- 品牌 -->
    <div class="mob-login-brand">
        <div class="mob-login-logo">OS</div>
        <div class="mob-login-brand-text">
            <div class="mob-login-title">OCI-START</div>
            <div class="mob-login-sub">欢迎回来，请登录</div>
        </div>
    </div>

    <div class="mob-login-card">
        <#if allowRegister?? && allowRegister>
        <div class="mob-login-tabs">
            <div class="mob-login-tab active" id="tabLogin" onclick="switchTab('login')">登录</div>
            <div class="mob-login-tab" id="tabRegister" onclick="switchTab('register')">注册</div>
        </div>
        </#if>

        <!-- 错误提示 -->
        <div class="mob-login-error" id="loginError">用户名或密码错误，请重试</div>

        <!-- 登录表单 -->
        <form id="loginForm" method="post" action="/perform_login">
            <#if turnstileEnabled?? && turnstileEnabled>
            <div id="turnstileContainer" style="margin-bottom:16px;text-align:center;">
                <div class="cf-turnstile"
                     data-sitekey="${turnstileSiteKey!''}"
                     data-callback="onTurnstileSuccess"
                     data-expired-callback="onTurnstileExpired"
                     data-theme="auto">
                </div>
                <div id="turnstileHint" style="font-size:12px;color:var(--mob-text-muted);margin-top:8px;">完成验证后，登录表单将自动显示</div>
            </div>
            </#if>

            <div id="loginFormContent"<#if turnstileEnabled?? && turnstileEnabled> style="display:none"</#if>>
            <div class="mob-field">
                <label for="username">用户名</label>
                <input type="text" id="username" name="username" autocomplete="username"
                       placeholder="请输入用户名" required>
            </div>
            <div class="mob-field">
                <label for="password">密码</label>
                <input type="password" id="password" name="password" autocomplete="current-password"
                       placeholder="请输入密码" required>
            </div>

            <!-- 验证码（MFA消息验证码，默认隐藏） -->
            <div id="verificationGroup" style="display:none">
                <div class="mob-field">
                    <label for="verificationCode">验证码</label>
                    <div class="mob-code-row">
                        <input type="text" id="verificationCode" name="verificationCode"
                               placeholder="请输入验证码" maxlength="8">
                        <button type="button" class="mob-send-code-btn" id="sendCodeBtn">
                            <i class="fas fa-paper-plane"></i> 发送
                        </button>
                    </div>
                </div>
            </div>

            <!-- MFA 动态口令（默认隐藏） -->
            <div id="mfaGroup" style="display:none">
                <div class="mob-field">
                    <label for="mfaCode">动态口令</label>
                    <input type="text" id="mfaCode" name="mfaCode"
                           placeholder="请输入6位动态口令" maxlength="6" inputmode="numeric">
                </div>
            </div>

            <!-- 验证方式选择（默认隐藏） -->
            <div id="verificationChoice" style="display:none">
                <div class="mob-login-tabs" style="margin-bottom:16px">
                    <div class="mob-login-tab active" id="messageTab" onclick="switchVerificationMethod('message')">
                        <i class="fas fa-envelope"></i> 消息验证
                    </div>
                    <div class="mob-login-tab" id="mfaTab" onclick="switchVerificationMethod('mfa')">
                        <i class="fas fa-shield-alt"></i> 动态口令
                    </div>
                </div>
            </div>

            <div class="mob-login-meta">
                <label class="mob-remember">
                    <input type="checkbox" name="remember-me" value="true">
                    记住我
                </label>
                <a href="#" class="mob-forgot-link" onclick="openForgotPasswordModal(); return false;">
                    忘记密码?
                </a>
            </div>

            <button type="submit" class="mob-login-submit" id="loginButton" disabled>
                <i class="fas fa-sign-in-alt"></i> 登录
            </button>

            <#if (githubEnabled?? && githubEnabled) || (googleEnabled?? && googleEnabled)>
            <div class="mob-oauth-divider">或通过第三方登录</div>
            <div class="mob-oauth-row">
                <#if githubEnabled?? && githubEnabled>
                <button type="button" id="githubLoginBtn" class="mob-oauth-btn">
                    <i class="fab fa-github"></i> GitHub
                </button>
                </#if>
                <#if googleEnabled?? && googleEnabled>
                <button type="button" id="googleLoginBtn" class="mob-oauth-btn">
                    <i class="fab fa-google"></i> Google
                </button>
                </#if>
            </div>
            </#if>
            </div><!-- /#loginFormContent -->
        </form>

        <#if allowRegister?? && allowRegister>
        <!-- 注册表单 -->
        <form id="registerForm" method="post" action="/api/register-first-user" style="display:none">
            <div class="mob-field">
                <label for="registerUsername">用户名</label>
                <input type="text" id="registerUsername" name="username" placeholder="请输入用户名" required>
            </div>
            <div class="mob-field">
                <label for="registerPassword">密码</label>
                <input type="password" id="registerPassword" name="password" placeholder="请输入密码" required>
            </div>
            <div class="mob-field">
                <label for="confirmPassword">确认密码</label>
                <input type="password" id="confirmPassword" name="confirmPassword" placeholder="再次输入密码" required>
            </div>
            <button type="submit" class="mob-login-submit">
                <i class="fas fa-user-plus"></i> 注册
            </button>
        </form>
        </#if>
    </div>

    <!-- 版权信息 -->
    <p style="text-align:center;margin-top:24px;margin-bottom:0;font-size:12px;color:var(--mob-text-muted);opacity:.7">
        &copy; 2025
        <a href="https://github.com/doubleDimple" target="_blank" rel="noopener"
           style="color:inherit;text-decoration:none;font-weight:600">doubleDimple</a>
        &nbsp;&middot;&nbsp; OCI-START
    </p>
</div>

<!-- 忘记密码 Sheet -->
<div class="mob-modal-overlay" id="forgotPasswordModal">
    <div class="mob-modal-sheet">
        <div class="mob-modal-title"><i class="fas fa-key"></i> 重置密码</div>
        <!-- Step 1: 输入用户名 + 发送验证码 -->
        <div id="resetStep1">
            <div class="mob-field">
                <label>用户名</label>
                <input type="text" id="resetUsername" placeholder="请输入用户名">
            </div>
            <div class="mob-field">
                <label>验证码</label>
                <div class="mob-code-row">
                    <input type="text" id="resetVerificationCode" placeholder="请输入验证码">
                    <button type="button" class="mob-send-code-btn" id="resetSendCodeBtn">
                        <i class="fas fa-paper-plane"></i> 发送
                    </button>
                </div>
            </div>
        </div>
        <!-- Step 2: 提示 -->
        <div id="resetStep2" style="display:none">
            <p style="color:var(--mob-text-muted);font-size:14px;line-height:1.6">
                <i class="fas fa-robot" style="color:var(--mob-primary)"></i>
                密码重置已通过AI机器人处理，请检查您的消息通知，按提示操作完成密码重置。
            </p>
        </div>
        <!-- Step 3: 成功 -->
        <div id="resetStep3" style="display:none;text-align:center;padding:12px 0">
            <i class="fas fa-check-circle" style="font-size:36px;color:#43b581;margin-bottom:10px"></i>
            <div style="font-weight:700;color:var(--mob-text)">重置请求已发送</div>
            <div style="font-size:13px;color:var(--mob-text-muted);margin-top:6px">请查收消息通知</div>
        </div>
        <div id="resetMessage" style="font-size:13px;margin-top:8px"></div>
        <div class="mob-modal-actions">
            <button type="button" class="mob-modal-btn" onclick="closeForgotPasswordModal()">取消</button>
            <button type="button" class="mob-modal-btn mob-modal-btn-primary" id="resetNextBtn" onclick="nextResetStep()">下一步</button>
        </div>
    </div>
</div>

<!-- Toast -->
<div class="mob-login-toast" id="mobLoginToast"></div>

<script>
    window.RSA_PUBLIC_KEY = "${publicKey!''}";
    window.TURNSTILE_ENABLED = ${(turnstileEnabled?? && turnstileEnabled)?string('true','false')};
    window.I18N = {
        login_passwd_match: "${msg.get('login.notMatch.password')}",
        login_register_success: "${msg.get('login.register.success')}",
        login_register_fail: "${msg.get('login.register.fail')}",
        login_input_userAndName: "${msg.get('login.input.userAndName')}",
        login_input_codeAndMfaCode: "${msg.get('login.input.codeAndMfaCode')}",
        login_input_msgCode: "${msg.get('login.input.msgCode')}",
        login_input_mfaCode: "${msg.get('login.input.mfaCode')}",
        login_input_login_loading: "${msg.get('login.input.login.loading')}",
        login_input_login_userOrNameError: "${msg.get('login.input.userOrNameError')}",
        login_input_login_failAndRetry: "${msg.get('login.input.failAndRetry')}",
        common_network_error: "${msg.get('common.network.error')}",
        login_title: "${msg.get('login.title')}",
        login_username_placeholder: "${msg.get('login.username.placeholder')}",
        login_input_code_success: "${msg.get('login.input.code.success')}",
        login_input_code_fail: "${msg.get('login.input.code.fail')}",
        login_btn_send_code: "${msg.get('login.btn.send.code')}",
        login_input_seconds_retry: "${msg.get('login.input.seconds.retry')}",
        login_input_step_next: "${msg.get('login.input.step.next')}",
        login_input_githubUrl_fail: "${msg.get('login.input.githubUrl.fail')}",
        login_input_githubUrl_login_fail: "${msg.get('login.input.githubUrl.login.fail')}",
        login_input_github_login: "${msg.get('login.input.github.login')}",
        login_reset_step1: "${msg.get('login.reset.step1')}",
        common_cancel: "${msg.get('common.cancel')}",
        login_reset_step2: "${msg.get('login.reset.step2')}",
        common_rollback: "${msg.get('common.rollback')}",
        common_finish: "${msg.get('common.finish')}",
        login_verify_code_placeholder: "${msg.get('login.verify.code.placeholder')}",
        login_input_verify_success: "${msg.get('login.input.verify.success')}",
        login_input_verify_fail: "${msg.get('login.input.verify.fail')}",
        login_input_verify_fail_retry: "${msg.get('login.input.verify.fail.retry')}",
        login_input_resetting: "${msg.get('login.input.resetting')}",
        login_input_resetting_error: "${msg.get('login.input.resetting.error')}",
        login_reset_title: "${msg.get('login.reset.title')}",
        login_input_send_retry: "${msg.get('login.input.send.retry')}",
        login_input_sending: "${msg.get('login.input.sending')}",
        login_send_yourDevice: "${msg.get('login.send.yourDevice')}"
    };
</script>
<script>
    /* ── Tab 切换 ── */
    function switchTab(tab) {
        var isLogin = tab === 'login';
        document.getElementById('loginForm').style.display = isLogin ? '' : 'none';
        var regForm = document.getElementById('registerForm');
        if (regForm) regForm.style.display = isLogin ? 'none' : '';
        document.getElementById('tabLogin').classList.toggle('active', isLogin);
        document.getElementById('tabRegister').classList.toggle('active', !isLogin);
    }

    /* ── 验证方式 tab（由 login_user_v1.js 调用） ── */
    function switchVerificationMethod(method) {
        var isMfa = method === 'mfa';
        document.getElementById('verificationGroup').style.display = isMfa ? 'none' : 'block';
        document.getElementById('mfaGroup').style.display = isMfa ? 'block' : 'none';
        document.getElementById('messageTab').classList.toggle('active', !isMfa);
        document.getElementById('mfaTab').classList.toggle('active', isMfa);
    }

    /* ── 忘记密码 ── */
    var _resetCurrentStep = 1;
    function openForgotPasswordModal() {
        _resetCurrentStep = 1;
        document.getElementById('resetStep1').style.display = '';
        document.getElementById('resetStep2').style.display = 'none';
        document.getElementById('resetStep3').style.display = 'none';
        document.getElementById('resetMessage').textContent = '';
        document.getElementById('resetNextBtn').textContent = '下一步';
        document.getElementById('forgotPasswordModal').classList.add('show');
    }
    function closeForgotPasswordModal() {
        document.getElementById('forgotPasswordModal').classList.remove('show');
    }
    function nextResetStep() {
        if (_resetCurrentStep === 1) {
            /* 第一步：走 login_user_v1.js 的 nextResetStep，若无则简化处理 */
            if (typeof window._loginNextResetStep === 'function') {
                window._loginNextResetStep();
            } else {
                document.getElementById('resetStep1').style.display = 'none';
                document.getElementById('resetStep2').style.display = '';
                document.getElementById('resetNextBtn').textContent = '完成';
                _resetCurrentStep = 2;
            }
        } else {
            closeForgotPasswordModal();
        }
    }

    /* ── Toast ── */
    function mobLoginToast(msg, type) {
        var t = document.getElementById('mobLoginToast');
        t.textContent = msg;
        t.className = 'mob-login-toast show' + (type ? ' ' + type : '');
        clearTimeout(t._tid);
        t._tid = setTimeout(function() { t.className = 'mob-login-toast'; }, 3000);
    }

    /* URL 错误参数提示 */
    (function() {
        var params = new URLSearchParams(window.location.search);
        if (params.get('error')) {
            var el = document.getElementById('loginError');
            if (el) el.style.display = 'block';
        }
    })();
</script>
<script src="/js/login/login_user_v1.js"></script>
</body>
</html>
