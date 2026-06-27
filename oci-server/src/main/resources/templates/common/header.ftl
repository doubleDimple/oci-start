<meta name="_csrf" content="">
<meta name="_csrf_header" content="X-CSRF-TOKEN">

<div class="top-nav">
    <a href="/index" class="brand">
        <h1 class="brand-title">${siteLogoName!'OCI-START'}</h1>
    </a>

    <div class="top-nav-right">

        <button id="updateBtn" class="header-btn header-update-btn" onclick="executeUpdate()" style="display: none;">
            <i class="fas fa-arrow-circle-up" style="margin-right: 5px;"></i>
            <span>${msg.get('header.new.version')} (<span id="newVersionNumber"></span>)</span>
        </button>

        <div class="nav-icon-wrapper" id="themeTrigger" onclick="cycleTheme()" title="暗色">
            <div class="icon-inner">
                <i id="themeIcon" class="fas fa-moon nav-icon"></i>
            </div>
        </div>

        <div class="nav-icon-wrapper" id="languageTrigger" onclick="toggleLanguagePanel(event)">
            <div class="icon-inner">
                <i class="fas fa-globe nav-icon"></i>
            </div>
        </div>

        <div class="message-dropdown-menu" id="languageDropdown" style="width: 120px; right: 180px;">
            <div class="menu-item ${(currentLocale == 'zh_CN')?string('active-item', '')}" onclick="switchLanguage('zh_CN')">
                <span>简体中文</span>
            </div>
            <div class="menu-item ${(currentLocale == 'zh_TW')?string('active-item', '')}"
                 onclick="switchLanguage('zh_TW')">
                <span>繁體中文</span>
            </div>
            <div class="menu-item ${(currentLocale == 'en_US')?string('active-item', '')}" onclick="switchLanguage('en_US')">
                <span>English</span>
            </div>
        </div>

        <div class="nav-icon-wrapper" id="messageTrigger" onclick="toggleMessagePanel(event)">
            <div class="icon-inner">
                <i class="fas fa-bell nav-icon"></i>
                <span id="msgBadge" class="notification-dot" style="display: none;"></span>
            </div>
        </div>

        <div class="message-dropdown-menu" id="messageDropdown">
            <div class="msg-header">
                <span>${msg.get('header.message.center')}</span>
                <span class="mark-all-btn" onclick="markAllAsRead(event)">${msg.get('header.mark.all.read')}</span>
            </div>

            <div class="msg-list" id="msgListContainer">
                <div class="msg-loading">${msg.get('header.loading')}</div>
            </div>

            <div class="msg-footer">
                <button id="msgPrevBtn" class="msg-page-btn" onclick="changeMsgPage(-1)">上一页</button>
                <span id="msgPageInfo">1 / 1</span>
                <button id="msgNextBtn" class="msg-page-btn" onclick="changeMsgPage(1)">下一页</button>
            </div>
        </div>

        <div class="user-profile-widget" id="userWidget">
            <div class="user-trigger" onclick="toggleUserMenu(event)">
                <img src="/images/default-avatar.png?v=${ociVersion!'1'}"
                     onerror="this.src='https://ui-avatars.com/api/?name=Admin&background=random&color=fff'"
                     class="user-avatar" alt="User">

                <div class="user-info-text">
                    <span id="currentUserName" class="user-name-small" style="display: none;">Loading...</span>
                    <span id="headerCurrentProvider" class="current-provider-label">Loading...</span>
                </div>

                <i class="fas fa-caret-down dropdown-arrow"></i>
            </div>

            <div class="user-dropdown-menu" id="userDropdownMenu">
                <div class="menu-header">
                    <div id="welcomeMessage" class="menu-welcome-text">Loading...</div>
                </div>

                <div class="menu-divider"></div>

                <div class="menu-item" onclick="showAssetAnalysis()">
                    <div class="item-left">
                        <i class="fas fa-chart-pie menu-icon" style="color: #FFD700;"></i>
                        <span style="font-weight: bold;">${msg.get("header.asset")}</span>
                    </div>
                    <span id="userLevelBadge" class="lvl-badge lvl-1">Loading...</span>
                </div>

                <div class="menu-divider"></div>

                <div class="menu-label">${msg.get('header.change.cloud')}</div>

                <div id="provider-btn-1" class="menu-item" onclick="selectProvider(1, 'Oracle Cloud')">
                    <div class="item-left">
                        <i class="fas fa-cloud menu-icon"></i>
                        <span>Oracle Cloud</span>
                    </div>
                    <i class="fas fa-check check-icon"></i>
                </div>

                <div id="provider-btn-2" class="menu-item" onclick="selectProvider(2, 'Google Cloud')">
                    <div class="item-left">
                        <i class="fab fa-google menu-icon"></i>
                        <span>Google Cloud</span>
                    </div>
                    <i class="fas fa-check check-icon"></i>
                </div>

                <div class="menu-divider"></div>

                <#--<div class="menu-label">语言设置</div> <div class="menu-item ${(currentLocale == 'zh_CN')?string('active-item', '')}" onclick="switchLanguage('zh_CN')">
                    <div class="item-left">
                        <i class="fas fa-language menu-icon"></i> <span>中文</span>
                    </div>
                </div> <div class="menu-item ${(currentLocale == 'en_US')?string('active-item', '')}" onclick="switchLanguage('en_US')">
                    <div class="item-left">
                        <i class="fas fa-language menu-icon"></i> <span>English</span>
                    </div>
                </div>-->
                <div class="menu-divider"></div>

                <div class="menu-item" onclick="showVersionInfo()">
                    <div class="item-left">
                        <i class="fas fa-info-circle menu-icon"></i> <span>${msg.get('header.about')}</span>
                    </div>
                </div>

                <form action="/perform_logout" method="post" id="logoutFormMenu">
                    <div class="menu-item logout-item" onclick="document.getElementById('logoutFormMenu').submit();">
                        <div class="item-left">
                            <i class="fas fa-sign-out-alt menu-icon"></i> <span>${msg.get('header.logout')}</span>
                        </div>
                    </div>
                </form>
            </div>
        </div>
    </div>
</div>

<link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
<script src="/js/sweetalert2.min.js"></script>
<link rel="preload" href="/css/all.min.css" as="style" onload="this.rel='stylesheet'">
<link rel="preload" href="/css/common/loading.css" as="style" onload="this.rel='stylesheet'">
<link rel="preload" href="/css/app/header.css" as="style" onload="this.rel='stylesheet'">
<noscript>
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/common/fa-fix.css">
</noscript>
<script>
    window.I18N = {
        header_welcome: "${msg.get('header.welcome')}",
        version_updateVersion: "${msg.get('version.updateVersion')}",
        version_restore: "${msg.get('version.restore')}",
        version_sendingUpdate: "${msg.get('version.sendingUpdate')}",
        version_sysRestore: "${msg.get('version.sysRestore')}",
        version_loadNewVersion: "${msg.get('version.loadNewVersion')}",
        version_noRefresh: "${msg.get('version.noRefresh')}",
        header_closeReport: "${msg.get('header.closeReport')}",
        header_report: "${msg.get('header.report')}",
        header_accetTotal: "${msg.get('header.accetTotal')}",
        header_upgreadeTotal: "${msg.get('header.upgreadeTotal')}",
        header_freeTotal: "${msg.get('header.freeTotal')}",
        header_accountCost: "${msg.get('header.accountCost')}",
        ai_analyze: "${msg.get('ai.analyze')}",
        ai_analyzeRes: "${msg.get('ai.analyzeRes')}",
        ai_analyzeRetry: "${msg.get('ai.analyzeRetry')}",
        version_update: "${msg.get('version.update')}"

    };
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/system/header.js"></script>

<!-- 消息详情 modal(无遮罩浮窗) -->
<div id="messageDetailModal" class="app-modal">
    <div class="app-modal-content">
        <button class="app-modal-close" onclick="closeMessageDetailModal()" title="关闭">
            <i class="fas fa-times"></i>
        </button>
        <div class="app-modal-header">
            <h2 id="messageDetailTitle">消息详情</h2>
            <div class="app-modal-meta" id="messageDetailMeta"></div>
        </div>
        <div class="app-modal-body" id="messageDetailBody"></div>
        <div class="app-modal-footer">
            <button class="app-modal-btn" onclick="closeMessageDetailModal()">关闭</button>
        </div>
    </div>
</div>

<!-- 资产分析 modal(无遮罩浮窗,wide 900px) -->
<div id="assetAnalysisModal" class="app-modal">
    <div class="app-modal-content app-modal-wide">
        <button class="app-modal-close" onclick="closeAssetAnalysisModal()" title="关闭">
            <i class="fas fa-times"></i>
        </button>
        <div class="app-modal-header">
            <h2 id="assetAnalysisTitle">云资产报告</h2>
            <div class="app-modal-meta" id="assetAnalysisMeta"></div>
        </div>
        <div class="app-modal-body" id="assetAnalysisBody"></div>
        <div class="app-modal-footer" id="assetAnalysisFooter"></div>
    </div>
</div>
