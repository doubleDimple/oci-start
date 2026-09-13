<!DOCTYPE html>
<html lang="${currentLocale}" data-theme="dark">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <script>
        (function () {
            var t = 'dark';
            try { t = localStorage.getItem('oci_theme') || t; } catch (e) {}
            if (t === 'system') t = window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
            document.documentElement.dataset.theme = t === 'light' ? 'light' : 'dark';
        })();
    </script>
    <title>${msg.get('login.page.title')}</title>
    <link rel="icon" href="/favicon.svg" type="image/svg+xml">
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/common/fa-fix.css">
    <link rel="stylesheet" href="/css/app/login_user.css?v=20260913g">
    <script src="/js/common/jsencrypt.min.js"></script>
    <#if turnstileEnabled?? && turnstileEnabled>
    <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
    </#if>
</head>
<body>
<section class="stage" aria-labelledby="heroBrandName">
    <div class="brand">
        <svg viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <path d="M12 2.5c0 0 6.8 7.4 6.8 12.1A6.8 6.8 0 0 1 12 21.4a6.8 6.8 0 0 1-6.8-6.8C5.2 9.9 12 2.5 12 2.5z" stroke="var(--brand-hi)" stroke-width="1.6" stroke-linejoin="round"/>
            <path d="M12 17.6a3 3 0 0 1-3-3c0-1.6 3-5 3-5s3 3.4 3 5a3 3 0 0 1-3 3z" fill="var(--brand-hi)"/>
        </svg>
        <span class="nm" id="heroBrandName">${siteLogoName!'OCI-START'} <em>/ <#if currentLocale?starts_with('zh')>多云工作台<#else>Cloud workspace</#if></em></span>
    </div>
    <div class="pitch">
        <h2><#if currentLocale?starts_with('zh')>所有云端，一处掌控。<#else>Every cloud. One place.</#if></h2>
        <p><#if currentLocale?starts_with('zh')>把分散在各个租户里的实例、网络与自动化任务，收进同一个控制台。<#else>Bring instances, networks and automated tasks across your tenants into one console.</#if></p>
    </div>
    <div class="mapbox login-mapbox" aria-hidden="true">
        <canvas id="loginRegionMap"></canvas>
        <div id="loginMapTooltip" role="presentation"><strong></strong><span></span></div>
    </div>
    <div class="stats">
        <div class="stat"><b id="loginMapRegionCount">17</b><span><#if currentLocale?starts_with('zh')>地图区域节点<#else>Map locations</#if></span></div>
        <div class="stat"><b>OCI · GCP</b><span><#if currentLocale?starts_with('zh')>支持云平台<#else>Cloud platforms</#if></span></div>
        <div class="stat"><b class="live"><#if currentLocale?starts_with('zh')>自动化<#else>Automation</#if></b><span><#if currentLocale?starts_with('zh')>任务与资源管理<#else>Tasks and resources</#if></span></div>
    </div>
    <div class="foot">&copy; 2026 doubleDimple · <a href="https://github.com/doubleDimple/oci-start" target="_blank" rel="noopener">GitHub</a> · <a href="https://github.com/doubleDimple/oci-start#readme" target="_blank" rel="noopener"><#if currentLocale?starts_with('zh')>文档<#else>Docs</#if></a></div>
</section>

<section class="auth">
        <div class="topbar">
            <div class="lang" data-current-locale="${currentLocale}">
                <button type="button" class="${(currentLocale == 'zh_CN')?string('active', '')}" aria-current="${currentLocale?starts_with('zh')?string('true','false')}" onclick="setLocale('zh_CN')">中文</button>
                <i aria-hidden="true">/</i>
                <button type="button" class="${(currentLocale == 'en_US')?string('active', '')}" aria-current="${currentLocale?starts_with('en')?string('true','false')}" onclick="setLocale('en_US')">EN</button>
            </div>
            <button class="icon-btn" type="button" id="themeToggle" title="<#if currentLocale?starts_with('zh')>切换外观<#else>Switch appearance</#if>" aria-label="<#if currentLocale?starts_with('zh')>切换外观<#else>Switch appearance</#if>" onclick="toggleLoginTheme()">
                <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8z"/></svg>
            </button>
        </div>

        <div class="login-card">
                <h1><#if currentLocale?starts_with('zh')>欢迎回来<#else>Welcome back</#if></h1>
                <p class="lede"><#if currentLocale?starts_with('zh')>登录后继续管理你的云端资源。<#else>Sign in to continue managing your cloud resources.</#if></p>

                <#if allowRegister?? && allowRegister>
                    <div class="tab-group">
                        <button type="button" class="tab active" onclick="switchTab('login')">${msg.get('login.title')}</button>
                        <button type="button" class="tab" onclick="switchTab('register')">${msg.get('login.register')}</button>
                    </div>
                </#if>

                <form id="loginForm" method="post" action="/perform_login" novalidate class="auth-form ${(allowRegister?? && allowRegister)?string('active','auth-form-single')}">
                    <#if turnstileEnabled?? && turnstileEnabled>
                    <div id="turnstileContainer" style="margin-bottom:18px;text-align:center;">
                        <div class="cf-turnstile"
                             data-sitekey="${turnstileSiteKey!''}"
                             data-callback="onTurnstileSuccess"
                             data-expired-callback="onTurnstileExpired"
                             data-theme="auto">
                        </div>
                        <div id="turnstileHint" style="font-size:12px;color:var(--text-muted);margin-top:8px;"><#if currentLocale?starts_with('zh')>完成验证后，登录表单将自动显示<#else>The sign-in form will appear after verification.</#if></div>
                    </div>
                    </#if>

                    <div id="loginFormContent"<#if turnstileEnabled?? && turnstileEnabled> style="display:none"</#if>>
                    <div class="field form-group">
                        <label for="username">${msg.get('login.username')}</label>
                        <div class="ctrl input-container">
                            <input type="text" id="username" name="username" class="form-control" autocomplete="username" autocapitalize="none" spellcheck="false" required placeholder="${msg.get('login.username.placeholder')}">
                            <i class="fas fa-user input-icon"></i>
                        </div>
                    </div>

                    <div class="field form-group">
                        <label for="password">${msg.get('login.password')}</label>
                        <div class="ctrl input-container password-container">
                            <input type="password" id="password" name="password" class="form-control" autocomplete="current-password" required placeholder="${msg.get('login.password.placeholder')}">
                            <button type="button" class="peek password-toggle" id="loginPasswordToggle" aria-controls="password" aria-pressed="false" aria-label="<#if currentLocale?starts_with('zh')>显示密码<#else>Show password</#if>" data-show-label="<#if currentLocale?starts_with('zh')>显示密码<#else>Show password</#if>" data-hide-label="<#if currentLocale?starts_with('zh')>隐藏密码<#else>Hide password</#if>"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 12s3.8-6.5 10-6.5S22 12 22 12s-3.8 6.5-10 6.5S2 12 2 12z"/><circle cx="12" cy="12" r="2.8"/></svg></button>
                        </div>
                    </div>

                    <div id="verificationGroup" style="display: none;">
                        <div class="field form-group">
                            <label for="verificationCode">${msg.get('login.verify.code')}</label>
                            <div class="verification-group">
                                <div class="verification-input">
                                    <input type="text" id="verificationCode" name="verificationCode" class="form-control" placeholder="${msg.get('login.verify.code.placeholder')}">
                                </div>
                                <button type="button" class="btn btn-send-code" id="sendCodeBtn">
                                    <i class="fas fa-paper-plane"></i>
                                    <span>${msg.get('login.btn.send.code')}</span>
                                </button>
                            </div>
                        </div>
                    </div>

                    <div id="mfaGroup" style="display: none;">
                        <div class="field form-group">
                            <label for="mfaCode">${msg.get('login.mfa.code')}</label>
                            <div class="ctrl input-container">
                                <input type="text" id="mfaCode" name="mfaCode" class="form-control" placeholder="${msg.get('login.mfa.code.placeholder')}" maxlength="6">
                                <i class="fas fa-shield-alt input-icon"></i>
                            </div>
                        </div>
                    </div>

                    <div id="verificationChoice" style="display: none;">
                        <div class="field form-group">
                            <label>${msg.get('login.verify.method')}</label>
                            <div class="tab-group" style="margin-bottom: 12px;">
                                <button type="button" class="tab active" onclick="switchVerificationMethod('message')" id="messageTab">
                                    <i class="fas fa-envelope"></i> <span>${msg.get('login.verify.method.msg')}</span>
                                </button>
                                <button type="button" class="tab" onclick="switchVerificationMethod('mfa')" id="mfaTab">
                                    <i class="fas fa-shield-alt"></i> <span>${msg.get('login.verify.method.mfa')}</span>
                                </button>
                            </div>
                        </div>
                    </div>

                    <div class="aux form-meta">
                        <label class="check remember-me">
                            <input type="checkbox" name="remember-me" value="true">
                            <span>${msg.get('login.remember.me')}</span>
                        </label>
                        <a href="#" class="link forgot-password-link" onclick="openForgotPasswordModal(); return false;">${msg.get('login.forgot.password')}</a>
                    </div>

                    <button type="submit" class="submit btn btn-primary" id="loginButton" disabled>
                        <span class="spin" aria-hidden="true"></span><span class="txt">${msg.get('login.btn.login')}</span>
                    </button>
                    <p class="msg" aria-hidden="true"></p>
                    <#if (githubEnabled?? && githubEnabled) || (googleEnabled?? && googleEnabled)>
                        <div class="oauth-row">
                            <#if githubEnabled?? && githubEnabled>
                                <button type="button" id="githubLoginBtn" class="btn btn-github btn-oauth">
                                    <i class="fab fa-github"></i>
                                    <span>${msg.get('login.btn.github')}</span>
                                </button>
                            </#if>
                            <#if googleEnabled?? && googleEnabled>
                                <button type="button" id="googleLoginBtn" class="btn btn-google btn-oauth">
                                    <i class="fab fa-google"></i>
                                    <span>${msg.get('login.btn.google')}</span>
                                </button>
                            </#if>
                        </div>
                    </#if>
                    </div>
                </form>

                <#if allowRegister?? && allowRegister>
                    <form id="registerForm" method="post" action="/api/register-first-user" class="auth-form" style="display: none;">
                        <div class="field form-group">
                            <label for="registerUsername">${msg.get('login.username')}</label>
                            <div class="ctrl input-container">
                                <input type="text" id="registerUsername" name="username" class="form-control" required placeholder="${msg.get('login.username.placeholder')}">
                                <i class="fas fa-user input-icon"></i>
                            </div>
                        </div>
                        <div class="field form-group">
                            <label for="registerPassword">${msg.get('login.password')}</label>
                            <div class="ctrl input-container">
                                <input type="password" id="registerPassword" name="password" class="form-control" required placeholder="${msg.get('login.password.placeholder')}">
                                <i class="fas fa-lock input-icon"></i>
                            </div>
                        </div>
                        <div class="field form-group">
                            <label for="confirmPassword">${msg.get('login.confirm.password')}</label>
                            <div class="ctrl input-container">
                                <input type="password" id="confirmPassword" name="confirmPassword" class="form-control" required placeholder="${msg.get('login.confirm.password.placeholder')}">
                                <i class="fas fa-lock input-icon"></i>
                            </div>
                        </div>
                        <button type="submit" class="submit btn btn-primary">
                            <i class="fas fa-user-plus"></i> <span>${msg.get('login.register')}</span>
                        </button>
                    </form>
                </#if>
        </div>
        <div class="authfoot"><#if allowRegister?? && allowRegister><#if currentLocale?starts_with('zh')>首次使用？切换到注册以创建账号。<#else>New here? Switch to Register to create an account.</#if><#else><#if currentLocale?starts_with('zh')>还没有账号？请联系管理员开通。<#else>Need an account? Contact your administrator.</#if></#if></div>
</section>

<div id="forgotPasswordModal" class="modal-overlay">
    <div class="modal">
        <div class="modal-header">
            <div class="modal-title"><i class="fas fa-key"></i> ${msg.get('login.reset.title')}</div>
            <button type="button" class="modal-close" aria-label="<#if currentLocale?starts_with('zh')>关闭<#else>Close</#if>" onclick="closeForgotPasswordModal()"><i class="fas fa-times" aria-hidden="true"></i></button>
        </div>

        <div class="modal-steps">
            <div class="progress-line" id="progressLine"></div>
            <div class="step active" id="step1">
                <div class="step-circle">1</div>
                <div class="step-label">${msg.get('login.reset.step1')}</div>
            </div>
            <div class="step" id="step2">
                <div class="step-circle">2</div>
                <div class="step-label">${msg.get('login.reset.step2')}</div>
            </div>
            <div class="step" id="step3">
                <div class="step-circle"><i class="fas fa-check"></i></div>
                <div class="step-label">${msg.get('login.reset.step3')}</div>
            </div>
        </div>

        <div class="modal-body">
            <div class="reset-step active" id="resetStep1">
                <div class="step-description"><i class="fas fa-info-circle"></i> ${msg.get('login.reset.info1')}</div>
                <div class="field form-group">
                    <label>${msg.get('login.username')}</label>
                    <div class="ctrl input-container">
                        <input type="text" id="resetUsername" class="form-control" placeholder="${msg.get('login.username.placeholder')}">
                        <i class="fas fa-user input-icon"></i>
                    </div>
                </div>
                <div class="field form-group">
                    <label>${msg.get('login.verify.code')}</label>
                    <div class="verification-group">
                        <div class="verification-input">
                            <input type="text" id="resetVerificationCode" class="form-control" placeholder="${msg.get('login.verify.code.placeholder')}">
                        </div>
                        <button type="button" class="btn btn-send-code" id="resetSendCodeBtn">
                            <i class="fas fa-paper-plane"></i> <span>${msg.get('login.btn.send.code')}</span>
                        </button>
                    </div>
                </div>
            </div>

            <div class="reset-step" id="resetStep2">
                <div class="step-description"><i class="fas fa-shield-alt"></i> ${msg.get('login.reset.info2')}</div>
                <div class="field form-group">
                    <label>${msg.get('login.reset.method.title')}</label>
                    <div class="modal-box">
                        <i class="fas fa-robot"></i>
                        ${msg.get('login.reset.method.desc')}
                        <ul class="modal-box-list">
                            <li>${msg.get('login.reset.method.list1')}</li>
                            <li>${msg.get('login.reset.method.list2')}</li>
                        </ul>
                    </div>
                </div>
            </div>

            <div class="reset-step" id="resetStep3">
                <div class="step-description"><i class="fas fa-check-circle"></i> ${msg.get('login.reset.success')}</div>
                <div class="modal-success">
                    <i class="fas fa-paper-plane" style="font-size: 32px; color: var(--status-ok); margin-bottom: 8px;"></i>
                    <div class="modal-success-title">${msg.get('login.reset.success')}</div>
                    <div class="modal-success-sub">${msg.get('login.reset.check.msg')}</div>
                </div>
            </div>
            <div id="resetMessage"></div>
        </div>

        <div class="modal-actions">
            <button type="button" class="btn btn-secondary btn-modal" id="resetCancelBtn" onclick="closeForgotPasswordModal()">${msg.get('login.btn.cancel')}</button>
            <button type="button" class="btn btn-primary btn-modal" id="resetNextBtn" onclick="nextResetStep()">${msg.get('login.btn.next')}</button>
        </div>
    </div>
</div>

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
    function setLocale(code) {
        var u = new URL(window.location.href);
        var c2 = String(code).replace('_', '-');
        u.searchParams.set('lang', code);
        u.searchParams.set('locale', code);
        u.searchParams.set('kc_locale', c2);
        u.searchParams.set('ui_locales', c2);
        window.location.href = u.toString();
    }
    function syncThemeIcon() {
        var dark = document.documentElement.dataset.theme === 'dark';
        var btn = document.getElementById('themeToggle');
        if (!btn) return;
        var chinese = document.documentElement.lang.indexOf('zh') === 0;
        var label = dark ? (chinese ? '切换到浅色' : 'Switch to light appearance') : (chinese ? '切换到深色' : 'Switch to dark appearance');
        btn.setAttribute('aria-label', label);
        btn.setAttribute('title', label);
    }
    function toggleLoginTheme() {
        var next = document.documentElement.dataset.theme === 'dark' ? 'light' : 'dark';
        document.documentElement.dataset.theme = next;
        try { localStorage.setItem('oci_theme', next); } catch (e) {}
        syncThemeIcon();
    }
    syncThemeIcon();
    (function () {
        var button = document.getElementById('loginPasswordToggle');
        var password = document.getElementById('password');
        if (!button || !password) return;
        button.addEventListener('click', function () {
            var showing = password.type === 'password';
            password.type = showing ? 'text' : 'password';
            button.setAttribute('aria-pressed', String(showing));
            button.setAttribute('aria-label', showing ? button.dataset.hideLabel : button.dataset.showLabel);
            password.focus({ preventScroll: true });
        });
    })();
</script>
<script src="/js/login/login_user_v1.js"></script>
<script src="/js/login/login_map.js?v=20260913b" defer></script>
</body>
</html>
