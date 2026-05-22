<#macro page title="" activePage="">
<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <meta name="mobile-web-app-capable" content="yes">
    <meta name="apple-mobile-web-app-capable" content="yes">
    <meta name="_csrf" content="${_csrf.token}">
    <meta name="_csrf_header" content="${_csrf.headerName}">
    <title>${title} - OCI-START</title>
    <#noparse>
    <script>(function(){var t=localStorage.getItem('mob-theme')||'auto';var d=document.documentElement;d.setAttribute('data-theme',t==='auto'?(window.matchMedia('(prefers-color-scheme: dark)').matches?'dark':'light'):t);})();</script>
    </#noparse>
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/mobile-app.css">
</head>
<body>

<!-- 顶部 Header -->
<header class="mob-header">
    <!-- 左侧汉堡菜单 -->
    <button class="mob-header-action" onclick="mobOpenDrawer()" title="${msg.get('mob.drawer.features')}">
        <i class="fas fa-bars"></i>
    </button>
    <span class="mob-header-title">${title}</span>
    <!-- 版本更新提示 -->
    <button class="mob-header-action mob-update-badge-btn" id="mobUpdateBtn" onclick="mobShowVersionSheet()" title="${msg.get('mob.version.title')}" style="display:none;position:relative;color:var(--mob-status-green)">
        <i class="fas fa-arrow-circle-up"></i>
        <span class="mob-update-dot"></span>
    </button>
    <button class="mob-header-action" onclick="location.reload()" title="${msg.get('mob.common.refresh')}">
        <i class="fas fa-sync-alt"></i>
    </button>
    <!-- 折叠按钮组（铃铛 / 语言 / 主题）-->
    <div class="mob-header-expandable" id="mobHeaderExpandable">
        <button class="mob-header-action" id="mobBellBtn" onclick="mobOpenMessages()" title="${msg.get('mob.msg.center')}" style="position:relative">
            <i class="fas fa-bell"></i>
            <span class="mob-bell-dot" id="mobBellDot" style="display:none"></span>
        </button>
        <button class="mob-header-action" onclick="mobOpenLang()" title="${msg.get('mob.lang.title')}">
            <i class="fas fa-globe"></i>
        </button>
        <button class="mob-header-action" onclick="mobCycleTheme()" title="${msg.get('mob.drawer.settings')}">
            <i id="mobThemeIcon" class="fas fa-adjust"></i>
        </button>
    </div>
    <!-- 头像（点击展开/收起）-->
    <div class="mob-avatar" id="mobAvatarBtn" onclick="mobToggleHeaderActions()" title="${currentUsername!msg.get('mob.common.user.default')}">
        <#if currentUsername?has_content>${currentUsername?substring(0,1)?upper_case}<#else>U</#if>
    </div>
</header>

<!-- 主内容区 -->
<main class="mob-content" id="mobContent">
    <#nested>
</main>

<!-- 底部 Tab 导航 -->
<nav class="mob-tab-bar">
    <a href="/m/tenants" class="mob-tab-item <#if activePage == 'tenants'>active</#if>">
        <i class="fas fa-building"></i>
        <span>${msg.get('mob.tab.tenants')}</span>
    </a>
    <a href="/m/boot" class="mob-tab-item <#if activePage == 'boot'>active</#if>">
        <i class="fas fa-bolt"></i>
        <span>${msg.get('mob.tab.boot')}</span>
    </a>
    <a href="/m/instances" class="mob-tab-item <#if activePage == 'instances'>active</#if>">
        <i class="fas fa-server"></i>
        <span>${msg.get('mob.tab.instances')}</span>
    </a>
    <a href="/m/speedtest" class="mob-tab-item <#if activePage == 'speedtest'>active</#if>">
        <i class="fas fa-globe"></i>
        <span>${msg.get('mob.tab.speedtest')}</span>
    </a>
    <a href="/m/monitor" class="mob-tab-item <#if activePage == 'monitor'>active</#if>">
        <i class="fas fa-chart-bar"></i>
        <span>${msg.get('mob.tab.monitor')}</span>
    </a>
</nav>

<!-- ═══════════ 左侧抽屉 ═══════════ -->
<div class="mob-drawer-overlay" id="mobDrawerOverlay" onclick="mobCloseDrawer()"></div>
<div class="mob-drawer" id="mobDrawer">
    <div class="mob-drawer-header">
        <div class="mob-drawer-brand">
            <i class="fas fa-rocket"></i>
            <span>OCI-START</span>
        </div>
        <button class="mob-header-action" onclick="mobCloseDrawer()" style="flex-shrink:0">
            <i class="fas fa-times"></i>
        </button>
    </div>
    <div class="mob-drawer-user">
        <#if currentUsername?has_content>${currentUsername}<#else>${msg.get('mob.common.user.default')}</#if>
    </div>
    <nav class="mob-drawer-nav">
        <div class="mob-drawer-section-title">${msg.get('mob.drawer.features')}</div>
        <div class="mob-drawer-item" onclick="window.location.href='/m/arm-regions'">
            <span class="mob-drawer-item-icon" style="background:rgba(250,166,26,0.12);color:#faa61a"><i class="fas fa-signal"></i></span>
            <span>${msg.get('mob.drawer.boot.monitor')}</span>
            <i class="fas fa-chevron-right mob-drawer-item-arrow"></i>
        </div>
        <div class="mob-drawer-item" onclick="window.location.href='/m/ai'">
            <span class="mob-drawer-item-icon" style="background:rgba(114,137,218,0.12);color:#7289da"><i class="fas fa-lightbulb"></i></span>
            <span>${msg.get('mob.drawer.ai')}</span>
            <i class="fas fa-chevron-right mob-drawer-item-arrow"></i>
        </div>
        <div class="mob-drawer-item" onclick="window.location.href='/m/memo'">
            <span class="mob-drawer-item-icon" style="background:rgba(255,193,7,0.12);color:#ffc107"><i class="fas fa-sticky-note"></i></span>
            <span>${msg.get('mob.drawer.memo')}</span>
            <i class="fas fa-chevron-right mob-drawer-item-arrow"></i>
        </div>
        <div class="mob-drawer-item" onclick="mobCloseDrawer();mobOpenMessages()">
            <span class="mob-drawer-item-icon" style="background:rgba(91,138,240,0.12);color:#5b8af0"><i class="fas fa-bell"></i></span>
            <span>${msg.get('mob.drawer.messages')}</span>
            <span id="drawerBellBadge" style="display:none;background:#f04747;color:#fff;font-size:10px;border-radius:10px;padding:1px 6px;margin-left:auto;margin-right:6px"></span>
            <i class="fas fa-chevron-right mob-drawer-item-arrow"></i>
        </div>
        <div class="mob-drawer-item" onclick="mobCloseDrawer();mobOpenLang()">
            <span class="mob-drawer-item-icon" style="background:rgba(26,188,156,0.10);color:#1abc9c"><i class="fas fa-globe"></i></span>
            <span>${msg.get('mob.drawer.language')}</span>
            <i class="fas fa-chevron-right mob-drawer-item-arrow"></i>
        </div>
        <div class="mob-drawer-item" onclick="mobOpenSysLog()">
            <span class="mob-drawer-item-icon"><i class="fas fa-terminal"></i></span>
            <span>${msg.get('mob.drawer.syslog')}</span>
            <i class="fas fa-chevron-right mob-drawer-item-arrow"></i>
        </div>
        <div class="mob-drawer-item" onclick="window.location.href='/m/notify-settings'">
            <span class="mob-drawer-item-icon" style="background:rgba(26,188,156,0.12);color:#1abc9c"><i class="fas fa-bell"></i></span>
            <span>${msg.get('mob.drawer.notify')}</span>
            <i class="fas fa-chevron-right mob-drawer-item-arrow"></i>
        </div>
        <div class="mob-drawer-item" onclick="window.location.href='/m/mfa'">
            <span class="mob-drawer-item-icon" style="background:rgba(52,152,219,0.12);color:#3498db"><i class="fas fa-shield-alt"></i></span>
            <span>${msg.get('mob.drawer.mfa')}</span>
            <i class="fas fa-chevron-right mob-drawer-item-arrow"></i>
        </div>
        <div class="mob-drawer-item" onclick="window.location.href='/m/cloudflare'">
            <span class="mob-drawer-item-icon" style="background:rgba(243,128,32,0.12);color:#f38020"><i class="fas fa-cloud"></i></span>
            <span>${msg.get('mob.drawer.domain')}</span>
            <i class="fas fa-chevron-right mob-drawer-item-arrow"></i>
        </div>
        <div class="mob-drawer-item" onclick="window.location.href='/m/settings'">
            <span class="mob-drawer-item-icon"><i class="fas fa-cogs"></i></span>
            <span>${msg.get('mob.drawer.settings')}</span>
            <i class="fas fa-chevron-right mob-drawer-item-arrow"></i>
        </div>
        <div class="mob-drawer-item" onclick="mobShowAbout()">
            <span class="mob-drawer-item-icon"><i class="fas fa-info-circle"></i></span>
            <span>${msg.get('mob.drawer.about')}</span>
            <i class="fas fa-chevron-right mob-drawer-item-arrow"></i>
        </div>
        <div class="mob-drawer-section-title" style="margin-top:8px">${msg.get('mob.drawer.account')}</div>
        <div class="mob-drawer-item mob-drawer-item-danger" onclick="mobShowLogout()">
            <span class="mob-drawer-item-icon" style="background:rgba(240,71,71,0.12);color:#f04747"><i class="fas fa-sign-out-alt"></i></span>
            <span style="color:#f04747">${msg.get('mob.drawer.logout')}</span>
            <i class="fas fa-chevron-right mob-drawer-item-arrow"></i>
        </div>
    </nav>
</div>

<!-- ═══════════ 全局蒙层 ═══════════ -->
<div class="mob-overlay" id="mobOverlay" onclick="mobCloseSheet()"></div>

<!-- 快速开机 居中弹框 -->
<div class="mob-center-overlay" id="quickBootOverlay" style="display:none" onclick="closeQuickBoot(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-width:360px">
        <div class="mob-sheet-header">
            <div style="min-width:0;flex:1">
                <div class="mob-sheet-title" style="margin:0">${msg.get('mob.boot.quick.title')}</div>
                <div class="mob-sheet-subtitle" id="quickBootRegionLabel" style="margin:2px 0 0">${msg.get('mob.boot.quick.select')}</div>
            </div>
            <button class="mob-sheet-close" onclick="closeQuickBoot()"><i class="fas fa-times"></i></button>
        </div>
        <div style="padding:12px 16px 20px">
            <div class="mob-arch-grid">
                <div class="mob-arch-card" onclick="mobQuickBoot('ARM')">
                    <div class="mob-arch-name">ARM</div>
                    <div class="mob-arch-spec">${msg.get('mob.boot.arm.spec')}</div>
                </div>
                <div class="mob-arch-card" onclick="mobQuickBoot('AMD')">
                    <div class="mob-arch-name">AMD</div>
                    <div class="mob-arch-spec">${msg.get('mob.boot.amd.spec')}</div>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- 区域实例 居中弹框 -->
<div class="mob-center-overlay" id="regionInstanceModal" style="display:none" onclick="closeRegionInstanceModal(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-height:82vh">
        <div class="mob-sheet-header">
            <div style="min-width:0;flex:1">
                <div class="mob-sheet-title" id="regionInstanceTitle">${msg.get('mob.instance.list')}</div>
                <div class="mob-sheet-subtitle" id="regionInstanceSubtitle" style="margin:2px 0 0"></div>
            </div>
            <button class="mob-sheet-close" onclick="closeRegionInstanceModal()"><i class="fas fa-times"></i></button>
        </div>
        <div class="mob-sheet-body" id="regionInstanceContent" style="min-height:120px;max-height:calc(82vh - 130px);overflow-y:auto">
            <div class="mob-loading"><div class="mob-spinner"></div><p>${msg.get('mob.loading')}</p></div>
        </div>
        <div class="mob-sheet-footer" id="regionInstancePager" style="display:none;padding:10px 16px 16px">
            <div style="display:flex;align-items:center;justify-content:space-between;gap:8px">
                <button class="mob-btn mob-btn-outline mob-btn-sm" id="instPrevBtn" onclick="instChangePage(-1)">
                    <i class="fas fa-chevron-left"></i> ${msg.get('mob.page.prev')}
                </button>
                <span id="instPageInfo" style="font-size:13px;color:var(--mob-text-muted);white-space:nowrap"></span>
                <button class="mob-btn mob-btn-outline mob-btn-sm" id="instNextBtn" onclick="instChangePage(1)">
                    ${msg.get('mob.page.next')} <i class="fas fa-chevron-right"></i>
                </button>
            </div>
        </div>
    </div>
</div>

<!-- 实例 Action Sheet -->
<div class="mob-sheet" id="instanceActionSheet">
    <div class="mob-sheet-handle"></div>
    <div class="mob-sheet-title" id="instanceActionTitle">${msg.get('mob.instance.ops')}</div>
    <div class="mob-sheet-subtitle" id="instanceActionSubtitle"></div>
    <ul class="mob-action-list" id="instanceActionList"></ul>
</div>

<!-- 版本信息 Sheet -->
<div class="mob-sheet" id="versionSheet">
    <div class="mob-sheet-handle"></div>
    <div class="mob-sheet-title">${msg.get('mob.version.title')}</div>
    <div class="mob-version-info">
        <div class="mob-version-row">
            <span class="mob-version-label">${msg.get('mob.version.current')}</span>
            <span id="versionCurrent" class="mob-version-value">-</span>
        </div>
        <div class="mob-version-row">
            <span class="mob-version-label">${msg.get('mob.version.latest')}</span>
            <span id="versionLatest" class="mob-version-value mob-version-new">-</span>
        </div>
        <div class="mob-version-row">
            <span class="mob-version-label">${msg.get('mob.version.deploy')}</span>
            <span id="versionDeploy" class="mob-version-value">-</span>
        </div>
    </div>
    <div style="display:flex;gap:12px;margin-top:20px">
        <button class="mob-btn mob-btn-outline" style="flex:1" onclick="mobCloseSheet()">${msg.get('mob.version.close')}</button>
        <button class="mob-btn mob-btn-primary" style="flex:1" id="mobDoUpdateBtn" onclick="mobDoUpdate()">
            <i class="fas fa-download"></i> ${msg.get('mob.version.update')}
        </button>
    </div>
</div>

<!-- 关于 Sheet -->
<div class="mob-sheet mob-sheet-about" id="aboutSheet">
    <div class="mob-sheet-handle"></div>
    <!-- 品牌区 -->
    <div class="mob-about-brand">
        <div class="mob-about-icon"><i class="fas fa-rocket"></i></div>
        <div class="mob-about-name">OCI-START</div>
        <div class="mob-about-author">Created by doubleDimple</div>
    </div>
    <!-- 版本信息 -->
    <div class="mob-version-info" style="margin:16px 0">
        <div class="mob-version-row">
            <span class="mob-version-label">${msg.get('mob.version.current')}</span>
            <span id="aboutVersionCurrent" class="mob-version-value">-</span>
        </div>
        <div class="mob-version-row">
            <span class="mob-version-label">${msg.get('mob.version.latest')}</span>
            <span id="aboutVersionLatest" class="mob-version-value mob-version-new">-</span>
        </div>
    </div>
    <!-- 外链 -->
    <div class="mob-about-links">
        <a href="https://github.com/doubleDimple/oci-start" target="_blank" class="mob-about-link">
            <i class="fab fa-github"></i> GitHub
        </a>
        <a href="https://t.me/+M7XhteVCMMU5ZDhh" target="_blank" class="mob-about-link">
            <i class="fab fa-telegram"></i> Telegram
        </a>
        <a href="https://github.com/doubleDimple/oci-start/releases" target="_blank" class="mob-about-link">
            <i class="fas fa-scroll"></i> ${msg.get('mob.about.changelog')}
        </a>
    </div>
    <!-- 捐赠 -->
    <div class="mob-about-donate-section">
        <div class="mob-about-donate-title">☕ ${msg.get('mob.about.donate')}</div>
        <div class="mob-about-donate-desc">
            这个项目完全由个人利用业余时间开发和维护。<br>
            如果它帮到了你，一杯咖啡的支持就是最大的鼓励 🙏
        </div>
        <div class="mob-about-donate-grid">
            <div class="mob-about-qr">
                <img src="/images/weixin.JPG" alt="${msg.get('mob.about.wechat')}" onclick="mobOpenLightbox(this.src)">
                <span>${msg.get('mob.about.wechat')}</span>
                <span class="mob-about-qr-hint">点击放大</span>
            </div>
            <div class="mob-about-qr">
                <img src="/images/binance_qr.jpg" alt="USDT" onclick="mobOpenLightbox(this.src)">
                <span>USDT (TRC20)</span>
                <span class="mob-about-qr-hint">点击放大</span>
            </div>
        </div>
    </div>
    <div class="mob-about-trc20" onclick="mobCopy('TMHTdWVm6ThvhihWqM1ViSDKMMsGcCBHtT')">
        <span class="mob-about-trc20-addr">TMHTdWVm6ThvhihWqM1ViSDKMMsGcCBHtT</span>
        <i class="fas fa-copy"></i>
    </div>
    <button class="mob-btn mob-btn-outline mob-btn-full" style="margin-top:16px" onclick="mobCloseSheet()">${msg.get('mob.common.close')}</button>
</div>

<!-- 图片灯箱 -->
<div class="mob-img-lightbox" id="mobImgLightbox" onclick="mobCloseLightbox()">
    <button class="mob-img-lightbox-close" onclick="mobCloseLightbox()"><i class="fas fa-times"></i></button>
    <img id="mobImgLightboxImg" src="" alt="">
</div>

<!-- 系统日志 Sheet -->
<div class="mob-sheet mob-sheet-tall" id="syslogSheet">
    <div class="mob-sheet-handle"></div>
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:10px">
        <div class="mob-sheet-title" style="margin:0">${msg.get('mob.syslog.title')}</div>
        <div class="mob-syslog-status-bar">
            <span class="mob-syslog-dot" id="syslogDot"></span>
            <span id="syslogStatusTxt" style="font-size:12px;color:var(--mob-text-muted)">${msg.get('mob.common.disconnected')}</span>
        </div>
    </div>
    <div class="mob-syslog-wrap" id="syslogWrap">
        <div id="syslogContent"></div>
    </div>
    <div style="display:flex;gap:8px;margin-top:10px">
        <button class="mob-btn mob-btn-outline mob-btn-sm" style="flex:1" onclick="document.getElementById('syslogContent').innerHTML=''">
            <i class="fas fa-eraser"></i> ${msg.get('mob.syslog.clear')}
        </button>
        <button class="mob-btn mob-btn-outline mob-btn-sm" style="flex:1" onclick="mobCloseSheet()">
            <i class="fas fa-times"></i> ${msg.get('mob.common.close')}
        </button>
    </div>
</div>

<!-- ═══════════ 居中蒙层（消息/语言）═══════════ -->
<div class="mob-center-mask" id="mobCenterMask" onclick="mobCloseModal()"></div>

<!-- ═══════════ 消息中心 居中弹窗 ═══════════ -->
<div class="mob-center-modal" id="msgCenterSheet">
    <!-- 列表视图 -->
    <div id="msgListView">
        <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px">
            <div class="mob-sheet-title" style="margin:0">${msg.get('mob.msg.center')}</div>
            <div style="display:flex;gap:8px">
                <button id="msgMarkBtn" class="mob-btn mob-btn-outline mob-btn-sm" onclick="mobMarkAllRead()">
                    <i class="fas fa-check-double"></i> ${msg.get('mob.msg.mark.all')}
                </button>
                <button class="mob-btn mob-btn-outline mob-btn-sm" onclick="mobCloseModal()">
                    <i class="fas fa-times"></i>
                </button>
            </div>
        </div>
        <div id="msgListWrap" style="overflow-y:auto;min-height:80px">
            <div class="mob-loading"><div class="mob-spinner"></div><p>${msg.get('mob.msg.loading')}</p></div>
        </div>
        <div id="msgPagination" style="display:flex;align-items:center;justify-content:center;gap:12px;margin-top:10px">
            <button class="mob-btn mob-btn-outline mob-btn-sm" id="msgPrevBtn" onclick="mobMsgPage(-1)">${msg.get('mob.msg.prev')}</button>
            <span id="msgPageInfo" style="font-size:12px;color:var(--mob-text-muted)">1 / 1</span>
            <button class="mob-btn mob-btn-outline mob-btn-sm" id="msgNextBtn" onclick="mobMsgPage(1)">${msg.get('mob.msg.next')}</button>
        </div>
    </div>
    <!-- 详情视图（默认隐藏） -->
    <div id="msgDetailView" style="display:none;flex-direction:column">
        <div style="display:flex;align-items:center;gap:8px;margin-bottom:14px">
            <button id="msgBackBtn" class="mob-btn mob-btn-outline mob-btn-sm" onclick="mobBackToMessages()" style="display:none">
                <i class="fas fa-arrow-left"></i> ${msg.get('mob.msg.back')}
            </button>
            <div class="mob-sheet-title" style="margin:0;flex:1">${msg.get('mob.msg.detail')}</div>
            <button class="mob-btn mob-btn-outline mob-btn-sm" onclick="mobCloseModal()">
                <i class="fas fa-times"></i>
            </button>
        </div>
        <div id="msgDetailContent" style="overflow-y:auto;max-height:55vh"></div>
    </div>
</div>

<!-- ═══════════ 语言选择 居中弹窗 ═══════════ -->
<div class="mob-center-modal" id="langSheet" style="max-width:280px">
    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:16px">
        <div class="mob-sheet-title" style="margin:0">${msg.get('mob.lang.title')}</div>
        <button class="mob-btn mob-btn-outline mob-btn-sm" onclick="mobCloseModal()">
            <i class="fas fa-times"></i>
        </button>
    </div>
    <div class="mob-lang-item <#if currentLocale == 'zh_CN'>mob-lang-item-active</#if>" onclick="mobSwitchLang('zh_CN')">
        <span>简体中文</span>
        <#if currentLocale == 'zh_CN'><i class="fas fa-check" style="color:var(--mob-primary)"></i></#if>
    </div>
    <div class="mob-lang-item <#if currentLocale == 'zh_TW'>mob-lang-item-active</#if>" onclick="mobSwitchLang('zh_TW')">
        <span>繁體中文</span>
        <#if currentLocale == 'zh_TW'><i class="fas fa-check" style="color:var(--mob-primary)"></i></#if>
    </div>
    <div class="mob-lang-item <#if currentLocale == 'en_US'>mob-lang-item-active</#if>" onclick="mobSwitchLang('en_US')">
        <span>English</span>
        <#if currentLocale == 'en_US'><i class="fas fa-check" style="color:var(--mob-primary)"></i></#if>
    </div>
</div>

<!-- Toast 提示 -->
<div class="mob-toast" id="mobToast"></div>

<!-- 全局加载遮罩（无黑色背景，只浮动卡片）-->
<div class="mob-global-loading" id="mobGlobalLoading">
    <div class="mob-global-loading-box">
        <div class="mob-global-loading-spinner"></div>
        <div class="mob-global-loading-msg" id="mobGlobalLoadingMsg">${msg.get('mob.processing')}</div>
    </div>
</div>

<!-- 全局确认对话框 -->
<div class="mob-confirm-mask" id="mobConfirmMask" onclick="mobConfirmClose(false)"></div>
<div class="mob-confirm-sheet" id="mobConfirmSheet">
    <div class="mob-confirm-icon"><i class="fas fa-exclamation-triangle" id="mobConfirmIcon"></i></div>
    <div class="mob-confirm-title" id="mobConfirmTitle">${msg.get('mob.common.confirm.title')}</div>
    <div class="mob-confirm-msg" id="mobConfirmMsg"></div>
    <div class="mob-confirm-actions">
        <button class="mob-btn mob-btn-outline" onclick="mobConfirmClose(false)">${msg.get('mob.common.cancel')}</button>
        <button class="mob-btn mob-btn-danger" id="mobConfirmOkBtn" onclick="mobConfirmClose(true)">${msg.get('mob.common.confirm.ok')}</button>
    </div>
</div>

<!-- 退出登录确认弹框 -->
<div id="mobLogoutOverlay" class="mob-logout-overlay" onclick="mobLogoutCancel()">
    <div class="mob-logout-sheet" onclick="event.stopPropagation()">
        <div class="mob-logout-icon-wrap">
            <i class="fas fa-sign-out-alt"></i>
        </div>
        <div class="mob-logout-title">${msg.get('mob.drawer.logout')}</div>
        <div class="mob-logout-msg">${msg.get('mob.logout.confirm.msg')}</div>
        <div class="mob-logout-btns">
            <button class="mob-logout-btn mob-logout-cancel" onclick="mobLogoutCancel()">${msg.get('mob.common.cancel')}</button>
            <button class="mob-logout-btn mob-logout-ok" onclick="mobLogoutOk()">${msg.get('mob.common.confirm')}</button>
        </div>
    </div>
</div>
<style>
.mob-logout-overlay {
    display: none;
    position: fixed; inset: 0;
    background: rgba(0,0,0,0.55);
    z-index: 99999;
    align-items: center; justify-content: center;
}
.mob-logout-overlay.show { display: flex; }
.mob-logout-sheet {
    width: calc(100% - 48px); max-width: 320px;
    background: var(--mob-card, #fff);
    border-radius: 16px;
    padding: 28px 20px 20px;
    text-align: center;
    box-shadow: 0 8px 32px rgba(0,0,0,0.25);
}
.mob-logout-icon-wrap {
    width: 56px; height: 56px;
    border-radius: 50%;
    background: rgba(240,71,71,0.12);
    color: #f04747;
    display: flex; align-items: center; justify-content: center;
    margin: 0 auto 14px;
    font-size: 26px;
}
.mob-logout-title {
    font-size: 16px; font-weight: 700;
    color: var(--mob-text, #111); margin-bottom: 8px;
}
.mob-logout-msg {
    font-size: 13px; color: var(--mob-text-muted, #666);
    line-height: 1.6; margin-bottom: 22px;
}
.mob-logout-btns { display: flex; gap: 10px; }
.mob-logout-btn {
    flex: 1; padding: 11px 0;
    border-radius: 12px; border: none;
    font-size: 14px; font-weight: 600;
    cursor: pointer;
}
.mob-logout-cancel {
    background: var(--mob-bg, #f5f5f5);
    color: var(--mob-text-muted, #666);
    border: 1px solid var(--mob-border, #ddd);
}
.mob-logout-ok {
    background: #f04747;
    color: #fff;
}
</style>

<!-- ═══════ 实例更多操作（底部弹出）═══════ -->
<div id="instOpsOverlay" class="inst-ops-overlay" onclick="instCloseOps()">
    <div class="inst-ops-sheet" onclick="event.stopPropagation()">
        <!-- 拖拽把手 -->
        <div class="inst-ops-handle"></div>
        <!-- 实例信息卡 -->
        <div class="inst-ops-info-card">
            <div class="inst-ops-info-left">
                <span class="inst-ops-state-dot" id="instOpsStateDot"></span>
                <div>
                    <div class="inst-ops-name" id="instOpsName"></div>
                    <div class="inst-ops-subtitle" id="instOpsSubtitle"></div>
                </div>
            </div>
            <span class="inst-ops-state-badge" id="instOpsStateBadge"></span>
        </div>
        <!-- 宫格操作区 -->
        <div class="inst-ops-grid-section">
            <div class="inst-ops-grid-label">${msg.get('mob.inst.ops.more')}</div>
            <div id="instOpsActions" class="inst-ops-grid"></div>
        </div>
        <!-- 取消按钮 -->
        <button class="inst-ops-cancel-btn" onclick="instCloseOps()">${msg.get('mob.common.cancel')}</button>
    </div>
</div>

<!-- ═══════ 实例操作通用输入弹框 ═══════ -->
<div id="instOpsInputOverlay" class="inst-ops-modal-bg" onclick="instCloseInput(event)">
    <div class="inst-ops-modal-card" onclick="event.stopPropagation()">
        <div class="inst-ops-modal-title" id="instOpsInputTitle"></div>
        <div id="instOpsInputBody" style="margin-bottom:14px"></div>
        <div id="instOpsInputStatus" style="display:none;font-size:12px;padding:6px 10px;border-radius:8px;margin-bottom:10px;text-align:center"></div>
        <div class="inst-ops-modal-btns">
            <button class="inst-ops-modal-cancel" onclick="instCloseInput()">${msg.get('mob.common.cancel')}</button>
            <button class="inst-ops-modal-ok" id="instOpsInputOkBtn" onclick="instOpsDoSubmit()">${msg.get('mob.common.confirm')}</button>
        </div>
    </div>
</div>

<!-- ═══════ 终止实例弹框（两步验证）═══════ -->
<div id="instOpsTermOverlay" class="inst-ops-modal-bg" onclick="instCloseTerminate(event)">
    <div class="inst-ops-modal-card" onclick="event.stopPropagation()">
        <div class="inst-ops-modal-title" style="color:#f04747"><i class="fas fa-exclamation-triangle"></i> ${msg.get('mob.inst.ops.terminate')}</div>
        <div id="instTermStep1">
            <p style="font-size:13px;color:#f04747;line-height:1.6;margin-bottom:14px">${msg.get('mob.inst.ops.termwarn')}</p>
            <div class="inst-ops-modal-btns">
                <button class="inst-ops-modal-cancel" onclick="instCloseTerminate()">${msg.get('mob.common.cancel')}</button>
                <button class="inst-ops-modal-ok inst-ops-modal-danger" onclick="instTermSendCode()">${msg.get('mob.inst.ops.sendcode')}</button>
            </div>
        </div>
        <div id="instTermStep2" style="display:none">
            <input id="instTermCodeInput" type="text" class="inst-ops-field" placeholder="${msg.get('mob.inst.ops.code.ph')}" style="margin-bottom:14px">
            <div class="inst-ops-modal-btns">
                <button class="inst-ops-modal-cancel" onclick="instCloseTerminate()">${msg.get('mob.common.cancel')}</button>
                <button class="inst-ops-modal-ok inst-ops-modal-danger" onclick="instTermConfirm()">${msg.get('mob.inst.ops.termconfirm')}</button>
            </div>
        </div>
        <div id="instTermStatus" style="display:none;font-size:12px;padding:6px 10px;border-radius:8px;margin-top:10px;text-align:center"></div>
    </div>
</div>

<!-- ═══════ 一键DD弹框 ═══════ -->
<div id="instOpsDDOverlay" class="inst-ops-modal-bg" onclick="instCloseDd(event)">
    <div class="inst-ops-modal-card inst-ops-dd-card" onclick="event.stopPropagation()">
        <div class="inst-ops-modal-title"><i class="fas fa-undo"></i> ${msg.get('mob.inst.ops.dd')}</div>
        <div id="instDDStep1">
            <!-- ── 二级 OS 选择器 ── -->
            <div id="instDDOsPicker" style="margin-bottom:10px">
                <div class="dd-picker-step">${msg.get('ins.plzOs')}</div>
                <div class="dd-family-grid" id="ddFamilyGrid">
                    <button class="dd-family-btn" onclick="ddPickFamily('Alpine')">
                        <i class="fas fa-snowflake"></i><span>Alpine</span>
                    </button>
                    <button class="dd-family-btn" onclick="ddPickFamily('Debian')">
                        <i class="fas fa-circle-notch"></i><span>Debian</span>
                    </button>
                    <button class="dd-family-btn" onclick="ddPickFamily('Ubuntu')">
                        <i class="fab fa-ubuntu"></i><span>Ubuntu</span>
                    </button>
                    <button class="dd-family-btn" onclick="ddPickFamily('RHEL')">
                        <i class="fas fa-fire"></i><span>RHEL</span>
                    </button>
                    <button class="dd-family-btn" onclick="ddPickFamily('Other')">
                        <i class="fas fa-cubes"></i><span>其他</span>
                    </button>
                </div>
                <div id="ddVersionArea" style="display:none;margin-top:10px">
                    <div class="dd-picker-step dd-picker-step-2">${msg.get('ins.plzOs')} › <span id="ddFamilyLabel"></span></div>
                    <div class="dd-ver-grid" id="ddVerGrid"></div>
                </div>
                <input type="hidden" id="instDDOsValue">
                <div id="ddSelectedShow" class="dd-selected-badge" style="display:none"></div>
            </div>
            <div style="position:relative;margin-bottom:10px">
                <input id="instDDPassword" type="password" class="inst-ops-field" placeholder="${msg.get('mob.inst.ops.rename.ph')}">
                <button type="button" onclick="instDDTogglePwd()" style="position:absolute;right:10px;top:50%;transform:translateY(-50%);background:none;border:none;color:var(--mob-text-muted);cursor:pointer">
                    <i class="fas fa-eye" id="instDDPwdIcon"></i>
                </button>
            </div>
            <div style="padding:10px 12px;border:1px solid rgba(240,71,71,0.4);border-radius:8px;font-size:12px;color:var(--mob-text-muted);line-height:1.7">
                <strong style="color:#f04747">${msg.get('machine.notice')}：</strong>${msg.get('mob.inst.ops.ddwarn')}
            </div>
            <div class="inst-ops-modal-btns" style="margin-top:14px">
                <button class="inst-ops-modal-cancel" onclick="instCloseDd()">${msg.get('mob.common.cancel')}</button>
                <button class="inst-ops-modal-ok" onclick="instDDStart()">${msg.get('mob.inst.ops.ddstart')}</button>
            </div>
        </div>
        <div id="instDDStep2" style="display:none">
            <div id="instDDLog" style="height:220px;overflow-y:auto;font-size:11px;font-family:monospace;line-height:1.6;background:var(--mob-bg);border-radius:8px;padding:10px;color:var(--mob-text);margin-bottom:10px"></div>
            <button id="instDDCloseBtn" class="inst-ops-modal-cancel" style="width:100%" disabled onclick="instCloseDd()">${msg.get('mob.common.close')}</button>
        </div>
    </div>
</div>

<style>
/* ── 实例操作底部菜单 ── */
.inst-ops-overlay {
    display: none; position: fixed; inset: 0;
    background: rgba(0,0,0,0.5); z-index: 9000;
    align-items: flex-end; justify-content: center;
}
.inst-ops-overlay.show { display: flex; }
.inst-ops-sheet {
    width: 100%; background: var(--mob-card, #fff);
    border-radius: 20px 20px 0 0;
    padding: 10px 0 calc(env(safe-area-inset-bottom) + 16px);
    max-height: 85vh; overflow-y: auto;
}
.inst-ops-handle {
    width: 36px; height: 4px; border-radius: 2px;
    background: var(--mob-border, #ddd);
    margin: 0 auto 12px;
}
/* ── 实例信息卡（更多弹窗顶部）── */
.inst-ops-info-card {
    display: flex; align-items: center; justify-content: space-between;
    margin: 0 16px 16px;
    padding: 12px 14px;
    background: var(--mob-bg);
    border-radius: 14px;
    border: 1px solid var(--mob-border);
}
.inst-ops-info-left {
    display: flex; align-items: center; gap: 10px; min-width: 0; flex: 1;
}
.inst-ops-state-dot {
    width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0;
}
.inst-ops-state-dot.running  { background: #43b581; box-shadow: 0 0 0 3px rgba(67,181,129,.2); }
.inst-ops-state-dot.stopped  { background: #72767d; }
.inst-ops-state-dot.starting { background: #f0b429; box-shadow: 0 0 0 3px rgba(240,180,41,.2); animation: mirc-pulse 1.4s ease-in-out infinite; }
.inst-ops-name {
    font-size: 14px; font-weight: 600; color: var(--mob-text);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 160px;
}
.inst-ops-subtitle {
    font-size: 11px; color: var(--mob-text-muted); margin-top: 2px; font-family: monospace;
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis; max-width: 180px;
}
.inst-ops-state-badge {
    font-size: 11px; font-weight: 600;
    padding: 3px 8px; border-radius: 6px;
    white-space: nowrap; flex-shrink: 0; margin-left: 8px;
}
.inst-ops-state-badge.running  { background: rgba(67,181,129,.15);  color: #43b581; }
.inst-ops-state-badge.stopped  { background: rgba(114,118,125,.12); color: #72767d; }
.inst-ops-state-badge.starting { background: rgba(240,180,41,.15);  color: #f0b429; }
/* ── 宫格操作区 ── */
.inst-ops-grid-section { padding: 0 16px; }
.inst-ops-grid-label {
    font-size: 11px; font-weight: 600; color: var(--mob-text-muted);
    text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 10px;
}
.inst-ops-grid {
    display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px;
}
.inst-ops-grid-btn {
    display: flex; flex-direction: column; align-items: center;
    gap: 4px; padding: 8px 2px;
    border: 1px solid var(--mob-border); background: var(--mob-bg);
    border-radius: 10px; cursor: pointer;
    transition: transform 0.15s, opacity 0.15s;
}
.inst-ops-grid-btn:active { transform: scale(0.93); opacity: 0.75; }
.inst-ops-grid-icon {
    width: 28px; height: 28px; border-radius: 8px;
    display: flex; align-items: center; justify-content: center; font-size: 13px;
}
.inst-ops-grid-lbl {
    font-size: 10px; font-weight: 500; color: var(--mob-text);
    line-height: 1.2; text-align: center;
}
.inst-ops-grid-btn.info    .inst-ops-grid-icon { background: rgba(59,130,246,.12);  color: #3b82f6; }
.inst-ops-grid-btn.teal    .inst-ops-grid-icon { background: rgba(20,184,166,.12);  color: #14b8a6; }
.inst-ops-grid-btn.purple  .inst-ops-grid-icon { background: rgba(139,92,246,.12);  color: #8b5cf6; }
.inst-ops-grid-btn.warning .inst-ops-grid-icon { background: rgba(240,180,41,.12);  color: #f0b429; }
.inst-ops-grid-btn.danger  .inst-ops-grid-icon { background: rgba(240,71,71,.12);   color: #f04747; }
.inst-ops-grid-btn.success .inst-ops-grid-icon { background: rgba(67,181,129,.12);  color: #43b581; }
.inst-ops-cancel-btn {
    display: block; width: calc(100% - 32px); margin: 8px 16px 0;
    padding: 13px; border-radius: 12px; border: none;
    background: var(--mob-bg); color: var(--mob-text-muted);
    font-size: 15px; font-weight: 600; cursor: pointer;
}

/* ── 实例操作通用弹框 ── */
.inst-ops-modal-bg {
    display: none; position: fixed; inset: 0;
    background: rgba(0,0,0,0.55); z-index: 9500;
    align-items: center; justify-content: center;
}
.inst-ops-modal-bg.show { display: flex; }
.inst-ops-modal-card {
    width: calc(100% - 40px); max-width: 360px;
    background: var(--mob-card, #fff); border-radius: 16px;
    padding: 20px; box-shadow: 0 8px 32px rgba(0,0,0,0.25);
    max-height: 85vh; overflow-y: auto;
}
.inst-ops-dd-card { max-width: 400px; }
/* ── DD 二级 OS 选择器 ── */
.dd-picker-step {
    font-size: 11px; font-weight: 600; color: var(--mob-text-muted);
    text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 8px;
}
.dd-picker-step-2 { margin-top: 0; color: var(--mob-accent); }
.dd-family-grid { display: grid; grid-template-columns: repeat(5, 1fr); gap: 6px; }
.dd-family-btn {
    display: flex; flex-direction: column; align-items: center; gap: 4px;
    padding: 10px 2px; border: 1px solid var(--mob-border); border-radius: 11px;
    background: var(--mob-bg); color: var(--mob-text-muted); font-size: 11px;
    cursor: pointer; transition: all 0.15s; line-height: 1;
}
.dd-family-btn i { font-size: 17px; }
.dd-family-btn.active { border-color: var(--mob-accent); color: var(--mob-accent); background: rgba(26,188,156,0.08); }
.dd-family-btn:active { transform: scale(0.93); }
.dd-ver-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; }
.dd-ver-btn {
    padding: 8px 4px; border: 1px solid var(--mob-border); border-radius: 10px;
    background: var(--mob-bg); color: var(--mob-text); font-size: 12px;
    cursor: pointer; text-align: center; transition: all 0.15s;
}
.dd-ver-btn.active { border-color: var(--mob-accent); color: var(--mob-accent); background: rgba(26,188,156,0.08); font-weight: 600; }
.dd-ver-btn:active { transform: scale(0.93); }
.dd-selected-badge {
    font-size: 12px; padding: 6px 12px; margin-top: 8px;
    background: rgba(67,181,129,0.12); color: #43b581;
    border-radius: 8px; text-align: center; font-weight: 600;
}
.inst-ops-modal-title {
    font-size: 16px; font-weight: 700; color: var(--mob-text);
    margin-bottom: 14px;
}
.inst-ops-field {
    display: block; width: 100%; padding: 10px 12px;
    border: 1px solid var(--mob-border, #ddd); border-radius: 10px;
    background: var(--mob-bg); color: var(--mob-text);
    font-size: 14px; box-sizing: border-box;
    outline: none;
}
.inst-ops-field:focus { border-color: var(--mob-accent); }
.inst-ops-modal-btns { display: flex; gap: 10px; }
.inst-ops-modal-cancel {
    flex: 1; padding: 11px 0; border-radius: 10px; border: none;
    background: var(--mob-bg); color: var(--mob-text-muted);
    font-size: 14px; font-weight: 600; cursor: pointer;
    border: 1px solid var(--mob-border);
}
.inst-ops-modal-ok {
    flex: 1; padding: 11px 0; border-radius: 10px; border: none;
    background: var(--mob-accent, #1abc9c); color: #fff;
    font-size: 14px; font-weight: 600; cursor: pointer;
}
.inst-ops-modal-danger { background: #f04747; }
.inst-ops-status-ok   { background: rgba(67,181,129,0.15); color: #43b581; }
.inst-ops-status-err  { background: rgba(240,71,71,0.15);  color: #f04747; }
.inst-ops-status-ing  { background: rgba(59,130,246,0.12); color: #3b82f6; }
/* ═══════════════════════════════════════════
   区域实例卡片（重设计）
   ═══════════════════════════════════════════ */
.mirc-list { display:flex; flex-direction:column; gap:10px; }
.mirc-card {
    background: var(--mob-card);
    border-radius: 16px;
    overflow: hidden;
    border: 1px solid var(--mob-border);
    box-shadow: 0 2px 8px rgba(0,0,0,.06);
    transition: box-shadow .2s;
}
/* 顶部信息区 */
.mirc-head {
    display: flex; align-items: center; gap: 10px;
    padding: 13px 14px 11px;
}
.mirc-dot {
    width: 9px; height: 9px; border-radius: 50%; flex-shrink: 0;
}
.mirc-dot-green  { background: #43b581; box-shadow: 0 0 0 3px rgba(67,181,129,.2); }
.mirc-dot-gray   { background: #72767d; }
.mirc-dot-yellow { background: #f0b429; box-shadow: 0 0 0 3px rgba(240,180,41,.2); animation: mirc-pulse 1.4s ease-in-out infinite; }
@keyframes mirc-pulse { 0%,100%{opacity:1} 50%{opacity:.5} }
.mirc-meta { flex:1; min-width:0; }
.mirc-name {
    font-size: 14px; font-weight: 700; color: var(--mob-text);
    white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
    margin-bottom: 4px;
}
.mirc-sub {
    display: flex; align-items: center; gap: 5px;
    font-size: 11px; color: var(--mob-text-muted);
}
.mirc-ip { font-family: monospace; color: var(--mob-text); font-size: 12px; }
.mirc-copy-btn {
    background: none; border: none; cursor: pointer; padding: 1px 3px;
    color: var(--mob-text-muted); font-size: 10px; border-radius: 4px;
    transition: color .15s;
}
.mirc-copy-btn:active { color: var(--mob-accent); }
.mirc-spec { color: var(--mob-text-muted); }
.mirc-badge {
    font-size: 10px; font-weight: 700; padding: 3px 9px;
    border-radius: 20px; flex-shrink: 0; letter-spacing: 0.4px;
}
.mirc-badge.running  { background: rgba(67,181,129,.15); color: #43b581; }
.mirc-badge.stopped  { background: rgba(114,118,125,.12); color: #72767d; }
.mirc-badge.starting { background: rgba(240,180,41,.15);  color: #f0b429; }
/* 快捷操作栏 */
.mirc-actions {
    display: flex; gap: 0;
    border-top: 1px solid var(--mob-border);
    overflow-x: auto; -webkit-overflow-scrolling: touch;
    scrollbar-width: none;
    padding: 1px 0;
}
.mirc-actions::-webkit-scrollbar { display: none; }
.mirc-qa {
    display: flex; flex-direction: column; align-items: center; gap: 4px;
    padding: 10px 0; min-width: 58px; flex: 1;
    border: none; background: transparent; cursor: pointer;
    font-size: 11px; font-weight: 600; transition: background .15s;
    border-right: 1px solid var(--mob-border);
    flex-shrink: 0;
}
.mirc-qa:last-child { border-right: none; }
.mirc-qa:active { background: var(--mob-bg); }
.mirc-qa:disabled { opacity: .4; cursor: not-allowed; }
.mirc-qa i { font-size: 15px; transition: transform .15s; }
.mirc-qa:active i { transform: scale(.88); }
.mirc-qa span { line-height: 1; }
.mirc-qa.start    { color: #43b581; }
.mirc-qa.stop     { color: #f0b429; }
.mirc-qa.config   { color: #8b5cf6; }
.mirc-qa.ip       { color: #3b82f6; }
.mirc-qa.rescue   { color: #14b8a6; }
.mirc-qa.terminate{ color: #f04747; }
.mirc-qa.more     { color: var(--mob-text-muted); }
.mirc-qa.busy     { color: var(--mob-text-muted); }
</style>

<!-- 全局 i18n 注入（供 JS 使用） -->
<script>
window.MOB_I18N = {
    loading:           "${msg.get('mob.loading')}",
    processing:        "${msg.get('mob.processing')}",
    close:             "${msg.get('mob.common.close')}",
    cancel:            "${msg.get('mob.common.cancel')}",
    confirm:           "${msg.get('mob.common.confirm')}",
    back:              "${msg.get('mob.common.back')}",
    save:              "${msg.get('mob.common.save')}",
    disconnected:      "${msg.get('mob.common.disconnected')}",
    connected:         "${msg.get('mob.common.connected')}",
    requestFail:       "${msg.get('mob.common.request.fail')}",
    networkError:      "${msg.get('mob.common.network.error')}",
    opFail:            "${msg.get('mob.common.op.fail')}",
    // message center
    msgLoading:        "${msg.get('mob.msg.loading')}",
    msgLoadFail:       "${msg.get('mob.msg.load.fail')}",
    msgEmpty:          "${msg.get('mob.msg.empty')}",
    msgMarkOk:         "${msg.get('mob.msg.mark.ok')}",
    msgOpFail:         "${msg.get('mob.msg.op.fail')}",
    msgDeleteOk:       "${msg.get('mob.msg.delete.ok')}",
    msgDeleteFail:     "${msg.get('mob.msg.delete.fail')}",
    // instances
    instEmpty:         "${msg.get('mob.inst.empty')}",
    instLoadFail:      "${msg.get('mob.inst.load.fail')}",
    instStateRunning:  "${msg.get('mob.inst.state.running')}",
    instStateStarting: "${msg.get('mob.inst.state.starting')}",
    instStateStopped:  "${msg.get('mob.inst.state.stopped')}",
    instStop:          "${msg.get('mob.inst.action.stop')}",
    instStart:         "${msg.get('mob.inst.action.start')}",
    instBusy:          "${msg.get('mob.inst.action.busy')}",
    instCopy:          "${msg.get('mob.inst.copy')}",
    instNoIp:          "${msg.get('mob.inst.no.ip')}",
    instStartSending:  "${msg.get('mob.inst.start.sending')}",
    instStopSending:   "${msg.get('mob.inst.stop.sending')}",
    instActionSent:    "${msg.get('mob.inst.action.sent')}",
    instActionFail:    "${msg.get('mob.inst.action.fail')}",
    instNetworkError:  "${msg.get('mob.inst.network.error')}",
    instUnnamed:       "${msg.get('mob.inst.unnamed')}",
    // tenants
    tenantEmpty:       "${msg.get('mob.tenant.empty')}",
    tenantLoadFail:    "${msg.get('mob.tenant.load.fail')}",
    tenantRegionsFail: "${msg.get('mob.tenant.regions.load.fail')}",
    tenantNoRegions:   "${msg.get('mob.tenant.no.regions')}",
    tenantRegionCount: "${msg.get('mob.tenant.region.count')}",
    tenantInstCount:   "${msg.get('mob.tenant.instance.count')}",
    tenantBoot:        "${msg.get('mob.tenant.boot')}",
    tenantInstances:   "${msg.get('mob.tenant.instances')}",
    tenantUpdatePrefix:"${msg.get('mob.tenant.update.prefix')}",
    tenantUpdateOk:    "${msg.get('mob.tenant.update.success')}",
    tenantUpdateFail:  "${msg.get('mob.tenant.update.fail')}",
    tenantConnErr:     "${msg.get('mob.tenant.connect.error')}",
    tenantCheckErr:    "${msg.get('mob.tenant.check.error')}",
    tenantDisconnect:  "${msg.get('mob.tenant.check.disconnect')}",
    tenantComplete:    "${msg.get('mob.tenant.check.complete')}",
    tenantPreparing:   "${msg.get('mob.tenant.preparing')}",
    tenantCheckDone:   "${msg.get('mob.tenant.check.done')}",
    tenantChecking:    "${msg.get('mob.tenant.checking')}",
    tenantTotal:       "${msg.get('mob.tenant.total.accounts')}",
    tenantActive:      "${msg.get('mob.tenant.active.accounts')}",
    tenantInactive:    "${msg.get('mob.tenant.inactive.accounts')}",
    // boot
    bootEmpty:         "${msg.get('mob.boot.empty')}",
    bootLoadFail:      "${msg.get('mob.boot.load.fail')}",
    bootRunning:       "${msg.get('mob.boot.status.running')}",
    bootStopped:       "${msg.get('mob.boot.status.stopped')}",
    bootTaskCount:     "${msg.get('mob.boot.task.count')}",
    bootGroupRunning:  "${msg.get('mob.boot.group.running')}",
    bootStopAll:       "${msg.get('mob.boot.stop.all')}",
    bootStartAll:      "${msg.get('mob.boot.start.all')}",
    bootDetails:       "${msg.get('mob.boot.details')}",
    bootDelete:        "${msg.get('mob.boot.delete')}",
    bootNoSubtasks:    "${msg.get('mob.boot.no.subtasks')}",
    bootStartOk:       "${msg.get('mob.boot.start.ok')}",
    bootStartFail:     "${msg.get('mob.boot.start.fail')}",
    bootStopOk:        "${msg.get('mob.boot.stop.ok')}",
    bootStopFail:      "${msg.get('mob.boot.stop.fail')}",
    bootDeleteOk:      "${msg.get('mob.boot.delete.ok')}",
    bootDeleteAllOk:   "${msg.get('mob.boot.delete.all.ok')}",
    bootDeleteFail:    "${msg.get('mob.boot.delete.fail')}",
    bootSubtaskFail:   "${msg.get('mob.boot.subtask.load.fail')}",
    bootConfirmDel:    "${msg.get('mob.boot.confirm.delete.single')}",
    bootConfirmDelMsg: "${msg.get('mob.boot.confirm.delete.single.msg')}",
    bootConfirmDelAll: "${msg.get('mob.boot.confirm.delete.all')}",
    bootConfirmDelAllMsg:"${msg.get('mob.boot.confirm.delete.all.msg')}",
    bootToday:         "${msg.get('mob.boot.today')}",
    bootTimes:         "${msg.get('mob.boot.times')}",
    bootTaskPrefix:    "${msg.get('mob.boot.task.prefix')}",
    // arm regions
    armEmpty:          "${msg.get('mob.arm.empty')}",
    armLoadFail:       "${msg.get('mob.arm.load.fail')}",
    armBadgeOpen:      "${msg.get('mob.arm.badge.open')}",
    armBadgeNo:        "${msg.get('mob.arm.badge.no')}",
    armBadgeMine:      "${msg.get('mob.arm.badge.mine')}",
    armMetricTotal:    "${msg.get('mob.arm.metric.total')}",
    armMetricMonthly:  "${msg.get('mob.arm.metric.monthly')}",
    armMetricLast:     "${msg.get('mob.arm.metric.last')}",
    armContAsia:       "${msg.get('mob.arm.cont.asia')}",
    armContEurope:     "${msg.get('mob.arm.cont.europe')}",
    armContNorthAm:    "${msg.get('mob.arm.cont.north-america')}",
    armContSouthAm:    "${msg.get('mob.arm.cont.south-america')}",
    armContMiddleEast: "${msg.get('mob.arm.cont.middle-east')}",
    // monitor
    monitorLoading:    "${msg.get('mob.monitor.loading')}",
    monitorLoadFail:   "${msg.get('mob.monitor.load.fail')}",
    monitorUpdatedAt:  "${msg.get('mob.monitor.updated.at')}",
    monitorNoSwap:     "${msg.get('mob.monitor.no.swap')}",
    monitorCores:      "${msg.get('mob.monitor.cores')}",
    monitorProcesses:  "${msg.get('mob.monitor.processes')}",
    monitorDay:        "${msg.get('mob.monitor.day')}",
    monitorHour:       "${msg.get('mob.monitor.hour')}",
    monitorMin:        "${msg.get('mob.monitor.min')}",
    // speedtest
    speedDetecting:    "${msg.get('mob.speed.detecting')}",
    speedNoNodes:      "${msg.get('mob.speed.no.nodes')}",
    speedLoadFail:     "${msg.get('mob.speed.load.fail')}",
    speedTesting:      "${msg.get('mob.speed.testing')}",
    speedRetry:        "${msg.get('mob.speed.retry')}",
    // instance ops
    opsMore:       "${msg.get('mob.inst.ops.more')}",
    opsRename:     "${msg.get('mob.inst.ops.rename')}",
    opsConfig:     "${msg.get('mob.inst.ops.config')}",
    opsDisk:       "${msg.get('mob.inst.ops.disk')}",
    opsRemark:     "${msg.get('mob.inst.ops.remark')}",
    opsChangeIp:   "${msg.get('mob.inst.ops.changeip')}",
    opsIpv6:       "${msg.get('mob.inst.ops.ipv6')}",
    opsNetwork:    "${msg.get('mob.inst.ops.network')}",
    opsRescue:     "${msg.get('mob.inst.ops.rescue')}",
    opsDd:         "${msg.get('mob.inst.ops.dd')}",
    opsTerminate:  "${msg.get('mob.inst.ops.terminate')}",
    opsSuccess:    "${msg.get('mob.inst.ops.success')}",
    opsFail:       "${msg.get('mob.inst.ops.fail')}",
    opsTermwarn:   "${msg.get('mob.inst.ops.termwarn')}",
    opsSendCode:   "${msg.get('mob.inst.ops.sendcode')}",
    opsTermConfirm:"${msg.get('mob.inst.ops.termconfirm')}",
    opsDdStart:    "${msg.get('mob.inst.ops.ddstart')}",
    opsDdWarn:     "${msg.get('mob.inst.ops.ddwarn')}",
    opsStarting:   "${msg.get('mob.inst.ops.starting')}",
    opsStopping:   "${msg.get('mob.inst.ops.stopping')}",
    opsStartOk:    "${msg.get('mob.inst.ops.startok')}",
    opsStopOk:     "${msg.get('mob.inst.ops.stopok')}",
    opsRenamePh:   "${msg.get('mob.inst.ops.rename.ph')}",
    opsRemarkPh:   "${msg.get('mob.inst.ops.remark.ph')}",
    opsCodePh:     "${msg.get('mob.inst.ops.code.ph')}",
    opsIpv6Confirm:"${msg.get('mob.inst.ops.ipv6.confirm')}",
    opsCidrAdd:    "${msg.get('mob.inst.ops.cidr.add')}",
    opsStart:      "${msg.get('mob.inst.action.start')}",
    opsStop:       "${msg.get('mob.inst.action.stop')}",
    cancel:        "${msg.get('mob.common.cancel')}",
    confirm:       "${msg.get('mob.common.confirm')}"
};
</script>

<script src="/js/common/jquery.min.js"></script>
<script src="/js/mobile/app.js"></script>
</body>
</html>
</#macro>
