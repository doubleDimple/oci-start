<!DOCTYPE html>
<html lang="${currentLocale}">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <script>/* 防闪烁：提前设置主题 */
        (function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();
    </script>
    <title>${msg.get('login.page.title')}</title>
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/common/fa-fix.css">
    <link rel="stylesheet" href="/css/app/login_user.css">
    <script src="/js/common/jsencrypt.min.js"></script>
    <#if turnstileEnabled?? && turnstileEnabled>
    <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
    </#if>
    <style>
        :root{--bg:#ECEEF2;--panel:#F3F4F6;--card:#FFFFFF;--text:#111827;--muted:#6B7280;--line:#D1D5DB;--shadow:0 22px 60px rgba(15,23,42,.14);--r:26px}
        body{background:var(--bg)}
        .header,.footer{display:none}
        .page-container{min-height:100vh;display:flex;flex-direction:column}
        .main-content{flex:1;display:flex;align-items:center;justify-content:center;padding:36px 16px}

        .auth-shell{width:min(1240px,100%);min-height:760px;background:var(--card);border-radius:var(--r);box-shadow:var(--shadow);overflow:hidden;display:grid;grid-template-columns:1fr 1fr;position:relative}
        .auth-shell:before{content:"";position:absolute;top:0;bottom:0;left:50%;width:1px;background:rgba(17,24,39,.06)}

        .lang-selector{position:absolute;top:18px;right:18px;z-index:10;display:flex;gap:10px;align-items:center;padding:8px 12px;border-radius:999px;background:rgba(255,255,255,.92);backdrop-filter:saturate(140%) blur(8px);box-shadow:0 10px 26px rgba(15,23,42,.08)}
        .lang-item{color:var(--muted);cursor:pointer;font-size:13px;letter-spacing:.2px;user-select:none}
        .lang-item.active{color:var(--text);font-weight:700}
        .lang-divider{color:#E5E7EB}

        .hero-panel{background:var(--panel);display:flex;align-items:center;justify-content:center;padding:56px}
        .hero-inner{width:100%;display:flex;align-items:center;justify-content:center}
        #heroSvg{width:100%;max-width:520px;height:auto}

        .form-panel{background:var(--card);display:flex;align-items:stretch;justify-content:stretch}
        .login-card{width:100%;background:transparent;box-shadow:none;border-radius:0;padding:0}
        .form-panel .login-card{padding:86px 96px 74px;display:flex;flex-direction:column;justify-content:center}


        .brand{display:flex;align-items:center;gap:12px;margin-bottom:34px}
        .brand-badge{width:38px;height:38px;border-radius:12px;background:#111827;color:#fff;display:flex;align-items:center;justify-content:center;font-weight:900;font-size:16px;letter-spacing:.4px}
        .brand-text{display:flex;flex-direction:column;line-height:1.05}
        .brand-name{font-size:22px;font-weight:950;color:var(--text);letter-spacing:.2px}
        .brand-sub{margin-top:6px;font-size:13px;color:var(--muted);letter-spacing:.2px}
        .tab-group{background:transparent;border:none;box-shadow:none;margin-bottom:26px}
        .tab{background:transparent;border-radius:999px}
        .tab.active{background:rgba(17,24,39,.06)}

        .form-group{margin-bottom:26px}
        .form-group label{color:var(--text);font-weight:800;font-size:15px;letter-spacing:.2px;margin-bottom:12px}
        .input-container{background:transparent;border:none;border-radius:0;padding:0;display:flex;align-items:center}
        .input-icon{display:none}
        .form-control{background:transparent;border:none;border-bottom:1px solid var(--line);border-radius:0;box-shadow:none;padding:14px 0 16px 0;font-size:17px;color:var(--text)}
        .form-control:focus{outline:none;box-shadow:none;border-bottom:1px solid #111827}

        .auth-form{width:100% !important;max-width:none !important}
        .auth-form-single{width:100% !important;max-width:none !important}
        .form-group{width:100% !important}
        .input-container{width:100% !important}
        .input-container .form-control{flex:1 1 auto !important;min-width:0;width:100% !important}
        .verification-group{display:flex;align-items:center;gap:12px}
        .verification-input{flex:1 1 auto !important;min-width:0}
        .verification-input .form-control{width:100% !important}
        .btn-send-code{white-space:nowrap}

        .verification-group{gap:12px}
        .verification-input .form-control{border-bottom:1px solid var(--line)}

        .form-meta{display:flex;align-items:center;justify-content:space-between;gap:18px;margin:10px 0 30px;flex-wrap:nowrap}
        .remember-me{display:flex;align-items:center;gap:8px;margin:0;white-space:nowrap}
        .remember-me input{margin:0}
        .remember-me span{white-space:nowrap;font-size:14px;font-weight:700;color:var(--text)}
        .forgot-password-link{color:var(--muted);margin:0;font-size:14px;text-decoration:none;white-space:nowrap}
        .forgot-password-link:hover{color:var(--text)}

        .btn{border-radius:999px}
        .btn-primary{background:#111827;border:none;box-shadow:none;height:56px;font-size:16px}
        .btn-primary:hover{filter:brightness(.95)}
        .btn-github{background:#F3F4F6;color:#111827;border:1px solid #E5E7EB;height:56px;font-size:16px}
        .btn-github:hover{filter:brightness(.98)}
        .btn-send-code{border-radius:999px}

        @media (max-width:980px){
            .auth-shell{grid-template-columns:1fr;min-height:auto}
            .auth-shell:before{display:none}
            .hero-panel{display:none}
            .form-panel .login-card{padding:40px 26px}
            .lang-selector{position:fixed}
        }

        .modal-overlay{position:fixed;inset:0;display:none;align-items:center;justify-content:center;padding:18px;background:rgba(17,24,39,.45);backdrop-filter:saturate(140%) blur(8px);z-index:1200}
        .modal-overlay.active{display:flex}
        .modal-overlay.show{display:flex}
        .modal{width:min(560px,100%);background:var(--card);border-radius:24px;box-shadow:var(--shadow);border:1px solid rgba(17,24,39,.08);overflow:hidden}
        .modal-header{display:flex;align-items:center;justify-content:space-between;padding:18px 20px;background:rgba(17,24,39,.02);border-bottom:1px solid rgba(17,24,39,.08)}
        .modal-title{font-weight:800;color:var(--text)}
        .modal-close{background:transparent;border:none;color:var(--muted);font-size:16px;cursor:pointer;padding:8px;border-radius:999px}
        .modal-close:hover{background:rgba(17,24,39,.06);color:var(--text)}
        .modal-body{padding:18px 20px}
        .modal-actions{display:flex;gap:12px;justify-content:flex-end;padding:16px 20px;border-top:1px solid rgba(17,24,39,.08);background:rgba(17,24,39,.02)}
        .modal-box{padding:12px;background:rgba(17,24,39,.02);border:1px solid rgba(17,24,39,.08);border-radius:16px;font-size:14px;color:var(--text)}
        .modal-box-list{margin:8px 0 0 20px;color:var(--muted)}
        .modal-success{padding:16px;background:rgba(17,24,39,.02);border:1px solid rgba(17,24,39,.08);border-radius:16px;text-align:center}
        .modal-success-title{font-size:14px;color:var(--text);font-weight:700}
        .modal-success-sub{font-size:12px;color:var(--muted);margin-top:4px}
        @media (max-width:520px){.modal{border-radius:18px}.modal-header,.modal-body,.modal-actions{padding-left:16px;padding-right:16px}}

        /* --- hard override: make right panel inputs truly full width --- */
        html body .form-panel,
        html body .form-panel .login-card,
        html body .form-panel .login-card form,
        html body .form-panel .login-card #loginForm,
        html body .form-panel .login-card #registerForm{
            width:100% !important;
            max-width:none !important;
        }
        html body .form-panel .login-card{
            align-items:stretch !important;
        }
        html body .form-panel .login-card .form-group,
        html body .form-panel .login-card .input-container{
            width:100% !important;
            max-width:none !important;
        }
        html body .form-panel .login-card .form-control,
        html body .form-panel .login-card input,
        html body .form-panel .login-card textarea,
        html body .form-panel .login-card select{
            width:100% !important;
            max-width:none !important;
            min-width:0 !important;
            flex:1 1 auto !important;
            box-sizing:border-box !important;
        }
        html body .form-panel .login-card .verification-row{
            width:100% !important;
            max-width:none !important;
            display:flex !important;
            gap:12px !important;
        }
        html body .form-panel .login-card .verification-row .form-control{
            flex:1 1 auto !important;
        }


        /* --- forgot password modal: wider (landscape) + cleaner layout --- */
        html body .modal{width:min(920px,calc(100% - 64px))!important;max-width:920px!important}
        html body .modal-header{padding:16px 22px!important}
        html body .modal-body{padding:18px 28px!important}
        html body .modal-actions{padding:14px 22px!important}
        @media (min-width:900px){
            html body #resetStep1.active{display:grid!important;grid-template-columns:1fr 1fr;gap:16px 24px;align-items:start}
            html body #resetStep1.active .step-description{grid-column:1/-1;margin:0 0 6px}
            html body #resetStep1.active .form-group{margin:0}
            html body #resetStep1.active .verification-group{display:flex;gap:12px;align-items:center}
            html body #resetStep1.active .verification-input{flex:1;min-width:0}
            html body #resetStep1.active .btn-send-code{white-space:nowrap;flex:0 0 auto}

            html body #resetStep2.active{display:grid!important;grid-template-columns:1.2fr .8fr;gap:16px 24px;align-items:start}
            html body #resetStep2.active .step-description{grid-column:1/-1;margin:0 0 6px}
            html body #resetStep2.active .modal-box{margin:0}
            html body #resetStep2.active .modal-box-list{margin:0;padding-left:18px}

            html body #resetStep3.active{display:flex!important;flex-direction:row;align-items:center;justify-content:center;gap:24px}
            html body #resetStep3.active .step-description{margin:0}
            html body #resetStep3.active .modal-success{margin:0;width:min(440px,100%)}
        }


        /* --- modal fix: unify reset step1 inputs + keep code input visible --- */
        html body #forgotPasswordModal .modal .form-group{width:100% !important;max-width:none !important;margin:0 0 18px}
        html body #forgotPasswordModal .modal .input-container{width:100% !important;max-width:none !important;display:flex !important;align-items:center !important}
        html body #forgotPasswordModal .modal .form-control{width:100% !important;max-width:none !important;min-width:0 !important;flex:1 1 auto !important;box-sizing:border-box !important;height:56px !important;padding:14px 0 16px 0 !important}
        html body #forgotPasswordModal .modal .verification-group{width:100% !important;display:flex !important;align-items:center !important;gap:12px !important}
        html body #forgotPasswordModal .modal .verification-input{flex:1 1 auto !important;min-width:240px !important}
        html body #forgotPasswordModal .modal .verification-input .form-control{width:100% !important}
        html body #forgotPasswordModal .modal .btn-send-code{flex:0 0 200px !important;width:200px !important;height:56px !important;white-space:nowrap !important;border-radius:999px !important}

        @media (max-width:760px){
            html body #forgotPasswordModal .modal .verification-group{flex-wrap:wrap !important}
            html body #forgotPasswordModal .modal .btn-send-code{flex:1 1 100% !important;width:100% !important}
            html body #forgotPasswordModal .modal .verification-input{min-width:0 !important}
        }

        .modal-overlay .modal-content .form-actions,
        .modal-overlay .modal-content .modal-actions,
        #resetPasswordModal .form-actions,
        #resetPasswordModal .modal-actions{
            display:flex !important;
            gap:22px !important;
            align-items:stretch !important;
        }

        .modal-overlay .modal-content .form-actions > button,
        .modal-overlay .modal-content .form-actions > a,
        .modal-overlay .modal-content .modal-actions > button,
        .modal-overlay .modal-content .modal-actions > a,
        #resetPasswordModal .form-actions > button,
        #resetPasswordModal .form-actions > a,
        #resetPasswordModal .modal-actions > button,
        #resetPasswordModal .modal-actions > a{
            flex: 1 1 0 !important;
            width: 0 !important;
            height: 64px !important;
            border-radius: 999px !important;
            font-size: 18px !important;
            font-weight: 700 !important;
            padding: 0 24px !important;
            line-height: 64px !important;
            box-sizing: border-box !important;
        }

        html body #forgotPasswordModal .modal-actions{
            display:flex !important;
            gap:22px !important;
            align-items:stretch !important;
        }

        html body #forgotPasswordModal .modal-actions > button.btn-modal{
            flex: 1 1 0 !important;
            width: 0 !important;
            min-width: 0 !important;

            height: 64px !important;
            line-height: 64px !important;
            padding: 0 24px !important;

            border-radius: 999px !important;
            font-size: 18px !important;
            font-weight: 800 !important;
            box-sizing: border-box !important;
        }

        html body #forgotPasswordModal .modal-actions > button.btn-secondary.btn-modal{
            background:#F3F4F6 !important;
            color:#111827 !important;
            border:1px solid rgba(17,24,39,.10) !important;
        }

        html body #forgotPasswordModal .modal-actions > button.btn-primary.btn-modal{
            background:#111827 !important;
            color:#FFFFFF !important;
            border:none !important;
        }
        /* OAuth 一行双按钮 */
        .oauth-row{
            display:flex;
            gap:12px;
            margin-top:14px;
            flex-wrap:nowrap;           /* 强制不换行 */
        }

        .oauth-row .btn-oauth{
            flex:1 1 0;
            min-width:0;                /* 允许收缩，避免被内容撑破导致换行 */
            height:56px;
            display:flex;
            align-items:center;
            justify-content:center;
            gap:8px;
        }

        .oauth-row .btn-oauth span{
            white-space:nowrap;
            overflow:hidden;
            text-overflow:ellipsis;
        }

        /* Google 按钮样式（按你现有 btn-github 风格来） */
        .btn-google{
            background:#F3F4F6;
            color:#111827;
            border:1px solid #E5E7EB;
            height:56px;
            font-size:16px;
        }
        .btn-google:hover{filter:brightness(.98)}

        .oauth-row{
            display:flex;
            gap:16px;
            margin-top:14px;
            align-items:stretch;     /* 同高 */
            flex-wrap:nowrap;        /* 不换行 */
        }

        .oauth-row .btn-oauth{
            flex:1 1 0;
            width:auto !important;
            margin:0 !important;
            height:56px;
            display:flex;
            align-items:center;
            justify-content:center;
            gap:8px;
        }

        .btn-google{
            background:#F3F4F6;
            color:#111827;
            border:1px solid #E5E7EB;
            height:56px;
            font-size:16px;
        }

        /* ============================================================
           暗色模式覆盖 [data-theme="dark"]
           ============================================================ */
        [data-theme="dark"]{
            --bg:#1a1d21;--panel:#1e2124;--card:#22262b;
            --text:#cdd9e5;--muted:#768390;--line:#31363d;
            --shadow:0 22px 60px rgba(0,0,0,.55);
        }
        [data-theme="dark"] body{background:var(--bg)}
        [data-theme="dark"] .auth-shell{background:var(--card)}
        [data-theme="dark"] .auth-shell:before{background:rgba(255,255,255,.06)}
        [data-theme="dark"] .lang-selector{background:rgba(34,38,43,.95);box-shadow:0 10px 26px rgba(0,0,0,.3)}
        [data-theme="dark"] .lang-item{color:var(--muted)}
        [data-theme="dark"] .lang-item.active{color:var(--text)}
        [data-theme="dark"] .lang-divider{color:var(--line)}
        [data-theme="dark"] .hero-panel{background:var(--panel)}
        [data-theme="dark"] .form-control{
            color:var(--text);border-bottom-color:var(--line);
            background-color:transparent!important;
            color-scheme:dark;
        }
        [data-theme="dark"] .form-control::placeholder{color:var(--muted);opacity:1}
        [data-theme="dark"] .form-control:focus{border-bottom-color:#4d9eff;outline:none}
        /* 压制浏览器 autofill 强制白底 */
        [data-theme="dark"] .form-control:-webkit-autofill,
        [data-theme="dark"] .form-control:-webkit-autofill:hover,
        [data-theme="dark"] .form-control:-webkit-autofill:focus,
        [data-theme="dark"] .form-control:-webkit-autofill:active{
            -webkit-box-shadow:0 0 0 1000px #22262b inset!important;
            -webkit-text-fill-color:#cdd9e5!important;
            caret-color:#cdd9e5;
            transition:background-color 9999s ease 0s;
        }
        [data-theme="dark"] .tab-group{background:transparent}
        [data-theme="dark"] .tab{color:var(--text)}
        [data-theme="dark"] .tab.active{background:rgba(77,158,255,.15);color:#4d9eff}
        [data-theme="dark"] .brand-badge{background:#4d9eff;color:#fff}
        [data-theme="dark"] .btn-primary{background:#4d9eff;color:#fff}
        [data-theme="dark"] .btn-primary:hover{filter:brightness(.9)}
        [data-theme="dark"] .btn-github,
        [data-theme="dark"] .btn-google{background:#292d32;color:var(--text);border-color:var(--line)}
        [data-theme="dark"] .btn-github:hover,
        [data-theme="dark"] .btn-google:hover{filter:brightness(1.1)}
        [data-theme="dark"] .forgot-password-link{color:var(--muted)}
        [data-theme="dark"] .forgot-password-link:hover{color:var(--text)}
        [data-theme="dark"] .remember-me span{color:var(--text)}
        [data-theme="dark"] .step-description{background:rgba(255,255,255,.04);color:var(--muted);border-radius:8px;padding:12px}
        [data-theme="dark"] .modal-overlay{background:rgba(0,0,0,.65);backdrop-filter:saturate(140%) blur(8px)}
        [data-theme="dark"] .modal{background:var(--card);border:1px solid var(--line)}
        [data-theme="dark"] .modal-header{background:rgba(255,255,255,.03);border-bottom-color:var(--line)}
        [data-theme="dark"] .modal-actions{background:rgba(255,255,255,.03);border-top-color:var(--line)}
        [data-theme="dark"] .modal-close{color:var(--muted)}
        [data-theme="dark"] .modal-close:hover{background:rgba(255,255,255,.08);color:var(--text)}
        [data-theme="dark"] .modal-box{background:rgba(255,255,255,.04);border-color:var(--line)}
        [data-theme="dark"] .modal-box-list{color:var(--muted)}
        [data-theme="dark"] .modal-success{background:rgba(255,255,255,.04);border-color:var(--line)}
        [data-theme="dark"] .modal-steps::before{background:var(--line)}
        [data-theme="dark"] .step-circle{background:var(--card);border-color:var(--line);color:var(--muted)}
        [data-theme="dark"] #forgotPasswordModal .form-control{color:var(--text);border-bottom-color:var(--line)}
        [data-theme="dark"] #forgotPasswordModal .modal-actions>button.btn-secondary.btn-modal{
            background:#292d32!important;color:var(--text)!important;border-color:var(--line)!important}
        [data-theme="dark"] #forgotPasswordModal .modal-actions>button.btn-primary.btn-modal{
            background:#4d9eff!important;color:#fff!important;border:none!important}
        [data-theme="dark"] footer a{color:var(--muted)!important}

        /* --- 左侧角色：哭脸表情 --- */
        #heroSvg .mouth-sad,
        #heroSvg .tears{opacity:0;pointer-events:none;transition:opacity .28s ease}
        #heroSvg .mouth-happy{opacity:1;transition:opacity .28s ease}
        #heroSvg.is-crying .mouth-happy{opacity:0}
        #heroSvg.is-crying .mouth-sad,
        #heroSvg.is-crying .tears{opacity:1}
        #heroSvg.is-crying .tears .tear{
            transform-box:fill-box;
            transform-origin:center top;
            animation:heroTearDrop 1.1s ease-in infinite;
        }
        #heroSvg.is-crying .tears .tear:nth-child(2){animation-delay:.18s}
        #heroSvg.is-crying .tears .tear:nth-child(3){animation-delay:.36s}
        #heroSvg.is-crying .tears .tear:nth-child(4){animation-delay:.12s}
        #heroSvg.is-crying .tears .tear:nth-child(5){animation-delay:.28s}
        #heroSvg.is-crying .tears .tear:nth-child(6){animation-delay:.42s}
        #heroSvg.is-crying .tears .tear:nth-child(7){animation-delay:.2s}
        #heroSvg.is-crying .tears .tear:nth-child(8){animation-delay:.34s}
        @keyframes heroTearDrop{
            0%{opacity:0;transform:translateY(0)}
            20%{opacity:.95}
            100%{opacity:0;transform:translateY(14px)}
        }
        #heroSvg.is-crying{animation:heroCryShake .45s ease}
        @keyframes heroCryShake{
            0%,100%{transform:translateX(0)}
            25%{transform:translateX(-3px)}
            75%{transform:translateX(3px)}
        }

        /* 空输入框抖动提示 */
        .form-control.input-shake{
            animation:inputShake .45s ease;
            border-bottom-color:#ef4444 !important;
        }
        @keyframes inputShake{
            0%,100%{transform:translateX(0)}
            15%{transform:translateX(-8px)}
            30%{transform:translateX(8px)}
            45%{transform:translateX(-6px)}
            60%{transform:translateX(6px)}
            75%{transform:translateX(-3px)}
            90%{transform:translateX(3px)}
        }
        [data-theme="dark"] .form-control.input-shake{
            border-bottom-color:#f87171 !important;
        }

    </style>
</head>
<body>
<div class="page-container">
    <main class="main-content">
        <div class="auth-shell">
            <div class="lang-selector" data-current-locale="${currentLocale}">
                <span class="lang-item ${(currentLocale == 'zh_CN')?string('active', '')}" onclick="setLocale('zh_CN')">中文</span>
                <span class="lang-divider">|</span>
                <span class="lang-item ${(currentLocale == 'en_US')?string('active', '')}" onclick="setLocale('en_US')">English</span>
            </div>

            <section class="hero-panel" aria-hidden="true">
                <div class="hero-inner">
                    <svg id="heroSvg" viewBox="0 0 520 520" xmlns="http://www.w3.org/2000/svg">
                        <!-- 紫色角色 -->
                        <g>
                            <rect x="160" y="130" width="170" height="260" rx="18" fill="#5B3DF6"/>
                            <circle cx="215" cy="198" r="14" fill="#FFFFFF"/>
                            <circle cx="275" cy="198" r="14" fill="#FFFFFF"/>
                            <circle data-pupil="1" data-max="6" cx="215" cy="198" r="5.5" fill="#111827"/>
                            <circle data-pupil="1" data-max="6" cx="275" cy="198" r="5.5" fill="#111827"/>
                            <path class="mouth-happy" d="M232 230 C246 240 260 240 274 230" fill="none" stroke="#111827" stroke-width="8" stroke-linecap="round"/>
                            <path class="mouth-sad" d="M232 244 C246 232 260 232 274 244" fill="none" stroke="#111827" stroke-width="8" stroke-linecap="round"/>
                            <g class="tears">
                                <ellipse class="tear" cx="208" cy="218" rx="3.2" ry="5" fill="#7DD3FC"/>
                                <ellipse class="tear" cx="282" cy="218" rx="3.2" ry="5" fill="#7DD3FC"/>
                            </g>
                        </g>

                        <!-- 黑色角色 -->
                        <g>
                            <rect x="320" y="175" width="70" height="215" rx="16" fill="#111827"/>
                            <circle cx="342" cy="230" r="10" fill="#FFFFFF"/>
                            <circle cx="368" cy="230" r="10" fill="#FFFFFF"/>
                            <circle data-pupil="1" data-max="5" cx="342" cy="230" r="4" fill="#111827"/>
                            <circle data-pupil="1" data-max="5" cx="368" cy="230" r="4" fill="#111827"/>
                            <path class="mouth-happy" d="M346 252 L364 252" fill="none" stroke="#FFFFFF" stroke-width="4" stroke-linecap="round" opacity=".55"/>
                            <path class="mouth-sad" d="M346 258 C352 252 358 252 364 258" fill="none" stroke="#FFFFFF" stroke-width="4" stroke-linecap="round"/>
                            <g class="tears">
                                <ellipse class="tear" cx="338" cy="245" rx="2.4" ry="4" fill="#7DD3FC"/>
                                <ellipse class="tear" cx="372" cy="245" rx="2.4" ry="4" fill="#7DD3FC"/>
                            </g>
                        </g>

                        <!-- 黄色角色 -->
                        <g>
                            <rect x="396" y="220" width="108" height="190" rx="44" fill="#F4C21A"/>
                            <circle cx="430" cy="268" r="12" fill="#FFFFFF"/>
                            <circle cx="470" cy="268" r="12" fill="#FFFFFF"/>
                            <circle data-pupil="1" data-max="5" cx="430" cy="268" r="4.5" fill="#111827"/>
                            <circle data-pupil="1" data-max="5" cx="470" cy="268" r="4.5" fill="#111827"/>
                            <path class="mouth-happy" d="M434 298 L486 298" stroke="#111827" stroke-width="8" stroke-linecap="round"/>
                            <path class="mouth-sad" d="M438 308 C452 296 468 296 482 308" fill="none" stroke="#111827" stroke-width="8" stroke-linecap="round"/>
                            <g class="tears">
                                <ellipse class="tear" cx="424" cy="286" rx="3" ry="4.5" fill="#38BDF8"/>
                                <ellipse class="tear" cx="476" cy="286" rx="3" ry="4.5" fill="#38BDF8"/>
                            </g>
                        </g>

                        <!-- 橙色角色 -->
                        <g>
                            <path d="M70 410 C70 320 140 250 230 250 C320 250 390 320 390 410" fill="#FF7A3B"/>
                            <circle cx="160" cy="332" r="16" fill="#FFFFFF"/>
                            <circle cx="220" cy="332" r="16" fill="#FFFFFF"/>
                            <circle data-pupil="1" data-max="6" cx="160" cy="332" r="6" fill="#111827"/>
                            <circle data-pupil="1" data-max="6" cx="220" cy="332" r="6" fill="#111827"/>
                            <path class="mouth-happy" d="M170 368 C186 386 210 386 226 368" fill="none" stroke="#111827" stroke-width="10" stroke-linecap="round"/>
                            <path class="mouth-sad" d="M170 386 C186 368 210 368 226 386" fill="none" stroke="#111827" stroke-width="10" stroke-linecap="round"/>
                            <g class="tears">
                                <ellipse class="tear" cx="152" cy="354" rx="3.5" ry="5.5" fill="#7DD3FC"/>
                                <ellipse class="tear" cx="228" cy="354" rx="3.5" ry="5.5" fill="#7DD3FC"/>
                            </g>
                        </g>

                        <!-- oci-start 小条 -->
                        <g id="ociBuddy">
                            <rect x="10" y="350" width="140" height="60" rx="20" fill="#111827" opacity="0.92"/>
                            <circle cx="62" cy="372" r="12" fill="#FFFFFF"/>
                            <circle cx="98" cy="372" r="12" fill="#FFFFFF"/>
                            <circle data-pupil="1" data-max="8" cx="62" cy="372" r="5.5" fill="#111827"/>
                            <circle data-pupil="1" data-max="8" cx="98" cy="372" r="5.5" fill="#111827"/>
                            <path class="mouth-happy" d="M70 388 C76 392 84 392 90 388" fill="none" stroke="#FFFFFF" stroke-width="3" stroke-linecap="round" opacity=".7"/>
                            <path class="mouth-sad" d="M70 392 C76 388 84 388 90 392" fill="none" stroke="#FFFFFF" stroke-width="3" stroke-linecap="round"/>
                            <g class="tears">
                                <ellipse class="tear" cx="58" cy="386" rx="2.2" ry="3.5" fill="#7DD3FC"/>
                                <ellipse class="tear" cx="102" cy="386" rx="2.2" ry="3.5" fill="#7DD3FC"/>
                            </g>
                            <text x="80" y="398" text-anchor="middle"
                                  font-size="15"
                                  font-family="system-ui, -apple-system, Segoe UI, Roboto"
                                  font-weight="900"
                                  fill="#FFFFFF">oci-start</text>
                        </g>

                        <g opacity=".22">
                            <path d="M62 118 L98 94" stroke="#111827" stroke-width="8" stroke-linecap="round"/>
                            <path d="M92 136 L126 112" stroke="#111827" stroke-width="8" stroke-linecap="round"/>
                        </g>
                    </svg>
                </div>
            </section>

            <section class="form-panel">
                <div class="login-card">

                    <div class="brand">
                        <div class="brand-badge">OS</div>
                        <div class="brand-text">
                            <div class="brand-name">OCI-START</div>
                            <div class="brand-sub">Welcome back</div>
                        </div>
                    </div>

                    <#if allowRegister?? && allowRegister>
                        <div class="tab-group">
                            <div class="tab active" onclick="switchTab('login')">${msg.get('login.title')}</div>
                            <div class="tab" onclick="switchTab('register')">${msg.get('login.register')}</div>
                        </div>
                    </#if>

                    <form id="loginForm" method="post" action="/perform_login" novalidate class="auth-form ${(allowRegister?? && allowRegister)?string('active','auth-form-single')}">
                        <#if turnstileEnabled?? && turnstileEnabled>
                        <div id="turnstileContainer" style="margin-bottom:18px;text-align:center;">
                            <div class="cf-turnstile"
                                 data-sitekey="${turnstileSiteKey!''}"
                                 data-callback="onTurnstileSuccess"
                                 data-expired-callback="onTurnstileExpired"
                                 data-theme="light">
                            </div>
                            <div id="turnstileHint" style="font-size:12px;color:#9CA3AF;margin-top:8px;">完成验证后，登录表单将自动显示</div>
                        </div>
                        </#if>

                        <div id="loginFormContent"<#if turnstileEnabled?? && turnstileEnabled> style="display:none"</#if>>
                        <div class="form-group">
                            <label for="username">${msg.get('login.username')}</label>
                            <div class="input-container">
                                <input type="text" id="username" name="username" class="form-control" required placeholder="${msg.get('login.username.placeholder')}">
                                <i class="fas fa-user input-icon"></i>
                            </div>
                        </div>

                        <div class="form-group">
                            <label for="password">${msg.get('login.password')}</label>
                            <div class="input-container">
                                <input type="password" id="password" name="password" class="form-control" required placeholder="${msg.get('login.password.placeholder')}">
                                <i class="fas fa-lock input-icon"></i>
                            </div>
                        </div>

                        <div id="verificationGroup" style="display: none;">
                            <div class="form-group">
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
                            <div class="form-group">
                                <label for="mfaCode">${msg.get('login.mfa.code')}</label>
                                <div class="input-container">
                                    <input type="text" id="mfaCode" name="mfaCode" class="form-control" placeholder="${msg.get('login.mfa.code.placeholder')}" maxlength="6">
                                    <i class="fas fa-shield-alt input-icon"></i>
                                </div>
                            </div>
                        </div>

                        <div id="verificationChoice" style="display: none;">
                            <div class="form-group">
                                <label>${msg.get('login.verify.method')}</label>
                                <div class="tab-group" style="margin-bottom: 12px;">
                                    <div class="tab active" onclick="switchVerificationMethod('message')" id="messageTab">
                                        <i class="fas fa-envelope"></i> <span>${msg.get('login.verify.method.msg')}</span>
                                    </div>
                                    <div class="tab" onclick="switchVerificationMethod('mfa')" id="mfaTab">
                                        <i class="fas fa-shield-alt"></i> <span>${msg.get('login.verify.method.mfa')}</span>
                                    </div>
                                </div>
                            </div>
                        </div>

                        <div class="form-meta">
                            <label class="remember-me">
                                <input type="checkbox" name="remember-me" value="true">
                                <span>${msg.get('login.remember.me')}</span>
                            </label>
                            <a href="#" class="forgot-password-link" onclick="openForgotPasswordModal()">${msg.get('login.forgot.password')}</a>
                        </div>

                        <button type="submit" class="btn btn-primary" id="loginButton" disabled>
                            <i class="fas fa-sign-in-alt"></i> <span>${msg.get('login.btn.login')}</span>
                        </button>
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
                        </div><!-- /#loginFormContent -->
                    </form>

                    <#if allowRegister?? && allowRegister>
                        <form id="registerForm" method="post" action="/api/register-first-user" class="auth-form" style="display: none;">
                            <div class="form-group">
                                <label for="registerUsername">${msg.get('login.username')}</label>
                                <div class="input-container">
                                    <input type="text" id="registerUsername" name="username" class="form-control" required placeholder="${msg.get('login.username.placeholder')}">
                                    <i class="fas fa-user input-icon"></i>
                                </div>
                            </div>
                            <div class="form-group">
                                <label for="registerPassword">${msg.get('login.password')}</label>
                                <div class="input-container">
                                    <input type="password" id="registerPassword" name="password" class="form-control" required placeholder="${msg.get('login.password.placeholder')}">
                                    <i class="fas fa-lock input-icon"></i>
                                </div>
                            </div>
                            <div class="form-group">
                                <label for="confirmPassword">${msg.get('login.confirm.password')}</label>
                                <div class="input-container">
                                    <input type="password" id="confirmPassword" name="confirmPassword" class="form-control" required placeholder="${msg.get('login.confirm.password.placeholder')}">
                                    <i class="fas fa-lock input-icon"></i>
                                </div>
                            </div>
                            <button type="submit" class="btn btn-primary">
                                <i class="fas fa-user-plus"></i> <span>${msg.get('login.register')}</span>
                            </button>
                        </form>
                    </#if>
                </div>
            </section>
        </div>
    </main>
    <!-- 版权信息 -->
    <footer style="text-align:center;padding:14px 0 18px;font-size:12px;color:var(--muted)">
        &copy; 2025 <a href="https://github.com/doubleDimple" target="_blank" rel="noopener"
           style="color:var(--muted);text-decoration:none">doubleDimple</a>
        &nbsp;·&nbsp; OCI-START
    </footer>
</div>

<div id="forgotPasswordModal" class="modal-overlay">
    <div class="modal">
        <div class="modal-header">
            <div class="modal-title"><i class="fas fa-key"></i> ${msg.get('login.reset.title')}</div>
            <button type="button" class="modal-close" onclick="closeForgotPasswordModal()"><i class="fas fa-times"></i></button>
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
                <div class="form-group">
                    <label>${msg.get('login.username')}</label>
                    <div class="input-container">
                        <input type="text" id="resetUsername" class="form-control" placeholder="${msg.get('login.username.placeholder')}">
                        <i class="fas fa-user input-icon"></i>
                    </div>
                </div>
                <div class="form-group">
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
                <div class="form-group">
                    <label>${msg.get('login.reset.method.title')}</label>
                    <div class="modal-box">
                        <i class="fas fa-robot" style="color: var(--primary-color);"></i>
                        ${msg.get('login.reset.method.desc')}
                        <ul class="modal-box-list">
                            <li>${msg.get('login.reset.method.list1')}</li>
                            <li>${msg.get('login.reset.method.list2')}</li>
                        </ul>
                    </div>
                </div>
            </div>

            <div class="reset-step" id="resetStep3">
                <div class="step-description"><i class="fas fa-check-circle" style="color: var(--success-color);"></i> ${msg.get('login.reset.success')}</div>
                <div class="modal-success">
                    <i class="fas fa-paper-plane" style="font-size: 32px; color: var(--success-color); margin-bottom: 8px;"></i>
                    <div class="modal-success-title">${msg.get('login.reset.success')}</div>
                    <div class="modal-success-sub">${msg.get('login.reset.check.msg')}</div>
                </div>
            </div>
            <div id="resetMessage"></div>
        </div>

        <div class="modal-actions">
            <button type="button" class="btn btn-secondary btn-modal" onclick="closeForgotPasswordModal()">${msg.get('login.btn.cancel')}</button>
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
    function setLocale(code){var u=new URL(window.location.href);var c1=code;var c2=String(code).replace('_','-');u.searchParams.set('lang',c1);u.searchParams.set('locale',c1);u.searchParams.set('kc_locale',c2);u.searchParams.set('ui_locales',c2);window.location.href=u.toString()}

    /**
     * 左侧 SVG 角色：
     * - 眼球跟踪鼠标 / 输入框
     * - 密码框害羞低头
     * - 登录失败哭脸（window.setHeroMood）
     */
    (function () {
        var cryTimer = null;
        var isCrying = false;

        /** @param {'cry'|'normal'} mood @param {{duration?:number}} [opts] */
        window.setHeroMood = function (mood, opts) {
            var svg = document.getElementById('heroSvg');
            if (!svg) return;
            if (cryTimer) {
                clearTimeout(cryTimer);
                cryTimer = null;
            }
            if (mood === 'cry') {
                isCrying = true;
                svg.classList.remove('is-crying');
                // 重触发 shake 动画
                void svg.offsetWidth;
                svg.classList.add('is-crying');
                var duration = (opts && opts.duration) || 4200;
                cryTimer = setTimeout(function () {
                    window.setHeroMood('normal');
                }, duration);
            } else {
                isCrying = false;
                svg.classList.remove('is-crying');
            }
        };

        function initEyeTrack() {
            var svg = document.getElementById('heroSvg');
            if (!svg) return;

            var formPanel = document.querySelector('.form-panel');
            var pupils = [].slice.call(svg.querySelectorAll('[data-pupil]')).map(function (el) {
                return {
                    el: el,
                    parent: el.parentNode,
                    baseX: parseFloat(el.getAttribute('cx') || 0),
                    baseY: parseFloat(el.getAttribute('cy') || 0),
                    max: parseFloat(el.getAttribute('data-max') || 6),
                    ox: 0,
                    oy: 0
                };
            });
            if (!pupils.length) return;

            var targetX = null;
            var targetY = null;
            var hasPointer = false;
            var focusedInput = null;
            var shyMode = false;

            function setTarget(x, y) {
                targetX = x;
                targetY = y;
            }

            function clearTarget() {
                if (!focusedInput) {
                    targetX = null;
                    targetY = null;
                }
            }

            function lookAtInput(input) {
                if (!input) return;
                var rect = input.getBoundingClientRect();
                var x = rect.left + Math.min(rect.width * 0.35, 48);
                var y = rect.top + rect.height / 2;

                try {
                    if (typeof input.selectionStart === 'number' && input.type !== 'password') {
                        var style = window.getComputedStyle(input);
                        var mirror = document.createElement('span');
                        mirror.style.cssText = [
                            'position:absolute', 'visibility:hidden', 'white-space:pre',
                            'font:' + style.font, 'letter-spacing:' + style.letterSpacing,
                            'padding-left:' + style.paddingLeft, 'border-left:' + style.borderLeftWidth + ' solid transparent'
                        ].join(';');
                        var text = (input.value || '').slice(0, input.selectionStart);
                        mirror.textContent = text || '.';
                        document.body.appendChild(mirror);
                        var caretOffset = mirror.getBoundingClientRect().width;
                        document.body.removeChild(mirror);
                        if (!text) caretOffset = 0;
                        x = rect.left + parseFloat(style.paddingLeft || 0) + Math.min(caretOffset, rect.width - 12);
                    }
                } catch (e) { /* ignore */ }

                if (shyMode) {
                    x = rect.left + rect.width * 0.5;
                    y = rect.top + rect.height + 18;
                }

                setTarget(x, y);
            }

            function onPointerMove(e) {
                if (isCrying) return; // 哭脸时低头不追鼠标
                var p = (e.touches && e.touches[0]) ? e.touches[0] : e;
                if (typeof p.clientX !== 'number') return;
                hasPointer = true;
                if (shyMode && focusedInput) {
                    lookAtInput(focusedInput);
                    return;
                }
                setTarget(p.clientX, p.clientY);
            }

            function onPointerLeave() {
                hasPointer = false;
                if (focusedInput) {
                    lookAtInput(focusedInput);
                } else {
                    clearTarget();
                }
            }

            function isTrackableInput(el) {
                if (!el || el.tagName !== 'INPUT') return false;
                var t = (el.type || 'text').toLowerCase();
                return t === 'text' || t === 'password' || t === 'email' || t === 'tel' || t === 'number' || t === 'search';
            }

            function onFocusIn(e) {
                var el = e.target;
                if (!isTrackableInput(el)) return;
                if (formPanel && !formPanel.contains(el) && !el.closest('.modal-overlay')) return;
                focusedInput = el;
                shyMode = (el.type || '').toLowerCase() === 'password';
                if (!isCrying) lookAtInput(el);
            }

            function onFocusOut(e) {
                if (e.target !== focusedInput) return;
                focusedInput = null;
                shyMode = false;
                if (!hasPointer && !isCrying) clearTarget();
            }

            function onInputOrSelect(e) {
                // 用户开始改输入：收起哭脸
                if (isCrying && isTrackableInput(e.target)) {
                    window.setHeroMood('normal');
                }
                if (e.target === focusedInput && !isCrying) lookAtInput(focusedInput);
            }

            function tick() {
                pupils.forEach(function (p) {
                    var dx = 0, dy = 0;
                    if (isCrying) {
                        // 哭脸：瞳孔往下看
                        dx = 0;
                        dy = p.max;
                    } else if (targetX != null && targetY != null) {
                        var pt = svg.createSVGPoint();
                        pt.x = targetX;
                        pt.y = targetY;
                        var m = p.parent && p.parent.getScreenCTM ? p.parent.getScreenCTM() : null;
                        if (m) {
                            var lp = pt.matrixTransform(m.inverse());
                            dx = lp.x - p.baseX;
                            dy = lp.y - p.baseY;
                        }
                    }
                    var d = Math.sqrt(dx * dx + dy * dy) || 1;
                    var mm = Math.min(p.max, d);
                    var tx = dx / d * mm;
                    var ty = dy / d * mm;
                    if (shyMode && !isCrying) {
                        ty = Math.min(p.max, Math.max(ty, p.max * 0.55));
                    }
                    var ease = isCrying ? 0.2 : (focusedInput ? 0.28 : 0.22);
                    p.ox += (tx - p.ox) * ease;
                    p.oy += (ty - p.oy) * ease;
                    if (targetX == null && !isCrying) {
                        p.ox += (0 - p.ox) * 0.12;
                        p.oy += (0 - p.oy) * 0.12;
                    }
                    p.el.setAttribute('transform', 'translate(' + p.ox.toFixed(3) + ' ' + p.oy.toFixed(3) + ')');
                });
                requestAnimationFrame(tick);
            }

            document.addEventListener('mousemove', onPointerMove, { passive: true });
            document.addEventListener('pointermove', onPointerMove, { passive: true });
            document.addEventListener('touchmove', onPointerMove, { passive: true });
            document.addEventListener('mouseleave', onPointerLeave, { passive: true });
            window.addEventListener('blur', onPointerLeave, { passive: true });

            document.addEventListener('focusin', onFocusIn, true);
            document.addEventListener('focusout', onFocusOut, true);
            document.addEventListener('input', onInputOrSelect, true);
            document.addEventListener('keyup', onInputOrSelect, true);
            document.addEventListener('click', onInputOrSelect, true);
            document.addEventListener('select', onInputOrSelect, true);

            window.addEventListener('resize', function () {
                if (focusedInput && !isCrying) lookAtInput(focusedInput);
            }, { passive: true });

            requestAnimationFrame(tick);
        }

        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', initEyeTrack);
        } else {
            initEyeTrack();
        }
    })();
</script>
<script src="/js/login/login_user_v1.js"></script>
</body>
</html>
