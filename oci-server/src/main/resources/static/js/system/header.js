/* ── 主题切换（dark → light → system 循环） ── */
(function () {
    var KEY   = 'oci_theme';
    var CYCLE = ['dark', 'light', 'system'];
    var ICONS  = { dark: 'fa-moon',    light: 'fa-sun',  system: 'fa-desktop' };
    var TITLES = { dark: '暗色模式',   light: '亮色模式', system: '跟随系统'   };

    function resolved(t) {
        if (t !== 'system') return t;
        return window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
    }

    function applyToEl(el, theme) {
        if (el) el.dataset.theme = resolved(theme);
    }

    /* 同步 iframe 的 data-theme */
    window.syncFrameTheme = function (theme) {
        var frame = document.getElementById('biz-frame');
        if (!frame) return;
        try {
            var fdoc = frame.contentDocument || frame.contentWindow.document;
            if (fdoc && fdoc.documentElement) applyToEl(fdoc.documentElement, theme);
        } catch (e) {}
    };

    function applyTheme(theme) {
        localStorage.setItem(KEY, theme);
        applyToEl(document.documentElement, theme);
        window.syncFrameTheme(theme);
        var icon    = document.getElementById('themeIcon');
        var trigger = document.getElementById('themeTrigger');
        if (icon)    icon.className = 'fas ' + ICONS[theme] + ' nav-icon';
        if (trigger) trigger.title  = TITLES[theme];
    }

    window.cycleTheme = function () {
        var cur  = localStorage.getItem(KEY) || 'dark';
        var next = CYCLE[(CYCLE.indexOf(cur) + 1) % CYCLE.length];
        applyTheme(next);
    };

    if (window.matchMedia) {
        window.matchMedia('(prefers-color-scheme: light)').addEventListener('change', function () {
            if ((localStorage.getItem(KEY) || 'dark') === 'system') applyTheme('system');
        });
    }

    /* 尽早设置，避免闪烁 */
    applyTheme(localStorage.getItem(KEY) || 'dark');
    document.addEventListener('DOMContentLoaded', function () {
        applyTheme(localStorage.getItem(KEY) || 'dark');
    });
}());

// 当前选中的云厂商类型 (1:Oracle, 2:Google, etc.)
let currentProviderType = 1;
let currentLoadedUsername = '用户';

const i18n = window.I18N;

// 版本缓存
let cachedVersionInfo = {
    needUpdate: null,
    latestVersion: null
};

// 消息分页状态管理
let msgState = {
    pageNum: 1,
    pageSize: 5,
    totalPages: 0,
    totalElements: 0
};

document.addEventListener('DOMContentLoaded', function() {
    initializeCloudProvider();
    checkVersionStatusAjax();

    checkUnreadMessages();

    loadUserInfo();
    document.addEventListener('click', function(event) {
        handleMenuOutsideClick(event);
    });
});

function closeAllMenus() {
    const menus = ['languageDropdown', 'messageDropdown', 'userDropdownMenu'];
    menus.forEach(id => {
        const el = document.getElementById(id);
        if (el) el.classList.remove('show');
    });
    const arrow = document.querySelector('.dropdown-arrow');
    if (arrow) arrow.style.transform = 'rotate(0deg)';
    const overlay = document.getElementById('navCloseOverlay');
    if (overlay) overlay.style.display = 'none';
}

function showNavOverlay() {
    const overlay = document.getElementById('navCloseOverlay');
    if (overlay) overlay.style.display = 'block';
}


function handleMenuOutsideClick(event) {
    const configs = [
        { menuId: 'languageDropdown', triggerId: 'languageTrigger' },
        { menuId: 'messageDropdown', triggerId: 'messageTrigger' },
        { menuId: 'userDropdownMenu', triggerId: 'userWidget' }
    ];

    configs.forEach(config => {
        const menu = document.getElementById(config.menuId);
        const trigger = document.getElementById(config.triggerId);

        if (menu && menu.classList.contains('show')) {
            if (!menu.contains(event.target) && trigger && !trigger.contains(event.target)) {
                menu.classList.remove('show');
                if (config.menuId === 'userDropdownMenu') {
                    const arrow = document.querySelector('.dropdown-arrow');
                    if (arrow) arrow.style.transform = 'rotate(0deg)';
                }
            }
        }
    });
}

function getCsrfConfig() {
    const token = document.querySelector('meta[name="_csrf"]')?.getAttribute('content');
    const header = document.querySelector('meta[name="_csrf_header"]')?.getAttribute('content');
    return { token, header };
}

function checkUnreadMessages() {
    const badge = document.getElementById('msgBadge');
    const csrf = getCsrfConfig();

    fetch('/sysMessage/countUnread', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrf.header]: csrf.token
        },
        body: JSON.stringify({})
    })
        .then(r => r.json())
        .then(res => {
            if (res.success) {
                const count = res.data || 0;

                if (count > 0) {
                    badge.style.display = 'block';
                    badge.textContent = count > 99 ? '99+' : count;
                } else {
                    badge.style.display = 'none';
                }
            }
        })
        .catch(error => {
            console.error('获取消息数量失败:', error);
        });
}

function toggleMessagePanel(event) {
    if (event) event.stopPropagation();
    const menu = document.getElementById('messageDropdown');
    const isShowing = menu.classList.contains('show');

    closeAllMenus();

    if (!isShowing) {
        menu.classList.add('show');
        showNavOverlay();
        msgState.pageNum = 1;
        loadMessageList();
    }
}

function loadMessageList() {
    const container = document.getElementById('msgListContainer');
    container.innerHTML = '<div class="msg-loading"><i class="fas fa-spinner fa-spin"></i> 加载中...</div>';

    const csrf = getCsrfConfig();
    const reqBody = {
        pageNum: msgState.pageNum,
        pageSize: msgState.pageSize
        // 这里不传 readStatus，查询全部状态
    };

    fetch('/sysMessage/list', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrf.header]: csrf.token
        },
        body: JSON.stringify(reqBody)
    })
        .then(r => r.json())
        .then(res => {
            if (res.success) {
                renderMessages(res.data);
            } else {
                container.innerHTML = '<div class="msg-empty">加载失败: ' + res.message + '</div>';
            }
        })
        .catch(e => {
            console.error(e);
            container.innerHTML = '<div class="msg-empty">网络错误</div>';
        });
}

function renderMessages(pageData) {
    const container = document.getElementById('msgListContainer');
    const { content, totalPages, totalElements } = pageData;

    msgState.totalPages = totalPages;
    msgState.totalElements = totalElements;

    if (!content || content.length === 0) {
        container.innerHTML = '<div class="msg-empty">暂无消息</div>';
        updatePaginationUI();
        return;
    }

    let html = '';
    content.forEach(msg => {
        // readStatus: 0未读, 1已读
        const isUnread = (msg.readStatus === 0);
        const unreadClass = isUnread ? 'unread' : '';
        let timeStr = msg.createTime ? msg.createTime.replace('T', ' ') : '';

        html += `
            <div class="msg-item ${unreadClass}">
                <div class="msg-content-wrapper" onclick="openMessageDetail('${msg.businessId}')">
                    <div class="msg-title">
                        ${msg.subject}
                    </div>
                    <div class="msg-time">${timeStr}</div>
                </div>
                
                <div class="msg-actions">
                    <button class="delete-msg-btn" 
                            title="删除消息" 
                            onclick="deleteMessageItem(event, '${msg.businessId}')">
                        <i class="fas fa-trash-alt"></i>
                    </button>
                </div>
            </div>
        `;
    });

    container.innerHTML = html;
    updatePaginationUI();
}

function updatePaginationUI() {
    const prevBtn = document.getElementById('msgPrevBtn');
    const nextBtn = document.getElementById('msgNextBtn');
    const pageInfo = document.getElementById('msgPageInfo');

    const current = msgState.pageNum;
    const total = msgState.totalPages || 1;

    if(pageInfo) pageInfo.textContent = `${current} / ${total}`;

    if(prevBtn) prevBtn.disabled = (current <= 1);
    if(nextBtn) nextBtn.disabled = (current >= total);
}

function changeMsgPage(delta) {
    const newPage = msgState.pageNum + delta;
    if (newPage > 0 && newPage <= msgState.totalPages) {
        msgState.pageNum = newPage;
        loadMessageList();
    }
}

function openMessageDetail(businessId) {
    const csrf = getCsrfConfig();
    Swal.fire({
        title: '正在读取...',
        allowOutsideClick: false,
        didOpen: () => { Swal.showLoading(); }
    });

    fetch('/sysMessage/get', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrf.header]: csrf.token
        },
        body: JSON.stringify({ businessId: businessId })
    })
        .then(r => r.json())
        .then(res => {
            if (res.success) {
                const msg = res.data;
                const timeStr = msg.createTime ? msg.createTime.replace('T', ' ') : '';

                // --- 核心逻辑：拆分首行与正文 ---
                let contentHtml = '';
                const rawContent = msg.content || '';
                const firstLineIndex = rawContent.indexOf('\n');

                if (firstLineIndex !== -1) {
                    // 提取第一行并居中
                    const firstLine = rawContent.substring(0, firstLineIndex);
                    // 提取剩余内容
                    const otherContent = rawContent.substring(firstLineIndex + 1);

                    contentHtml = `
                    <div style="text-align: center; font-size: 16px; font-weight: bold; color: #1a1a1a; margin-bottom: 15px; line-height: 1.4;">
                        ${firstLine}
                    </div>
                    <div style="text-align: left; font-size: 14px; line-height: 1.8; color: #333; white-space: pre-wrap; word-break: break-all; border-top: 1px dashed #eee; padding-top: 15px;">${otherContent}</div>
                `;
                } else {
                    // 如果没有换行符，则全量居中或按原样显示
                    contentHtml = `<div style="text-align: center; font-size: 14px; white-space: pre-wrap;">${rawContent}</div>`;
                }

                Swal.fire({
                    title: msg.subject,
                    html: `
                <div style="text-align: left; padding: 0 5px;">
                    <div style="color: #999; font-size: 12px; margin-bottom: 12px; border-bottom: 1px solid #eee; padding-bottom: 8px;">
                        <i class="far fa-clock"></i> ${timeStr}
                        <span style="float: right; color: #1890ff; font-weight:bold;">${msg.messageType || '系统消息'}</span>
                    </div>
                    <div style="background: #ffffff; padding: 5px; border-radius: 4px;">
                        ${contentHtml}
                    </div>
                </div>
            `,
                    width: 600,
                    showCloseButton: true,
                    confirmButtonText: '关闭',
                    confirmButtonColor: '#3085d6',
                    didClose: () => {
                        const menu = document.getElementById('messageDropdown');
                        if(menu && menu.classList.contains('show')){
                            loadMessageList();
                        }
                        checkUnreadMessages();
                    }
                });
            } else {
                Swal.fire('读取失败', res.message, 'error');
            }
        })
        .catch(e => {
            console.error('Message detail error:', e);
            Swal.fire('网络错误', '无法获取消息详情', 'error');
        });
}

function markAllAsRead(event) {
    // 阻止事件传播，如果它是从下拉菜单中的按钮触发的
    if(event) event.stopPropagation();

    const csrf = getCsrfConfig();

    // 直接执行请求，无需任何弹出提示
    fetch('/sysMessage/read', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrf.header]: csrf.token
        }
    })
        .then(r => r.json())
        .then(res => {
            if (res.success) {
                loadMessageList();
                checkUnreadMessages();
            }else{
                console.error('标记全部已读失败:', res.message);
            }
        })
        .catch(error => {
             console.error('标记全部已读网络错误:', error);
        });
}

function initializeCloudProvider() {
    const urlParams = new URLSearchParams(window.location.search);
    const urlCloudType = urlParams.get('cloudType');

    let type;

    if (urlCloudType) {
        type = parseInt(urlCloudType);
    } else {
        const savedProvider = localStorage.getItem('selectedCloudProvider');
        if (savedProvider) {
            try {
                const provider = JSON.parse(savedProvider);
                type = provider.type || 1;
            } catch (error) {
                type = 1;
            }
        } else {
            type = 1;
        }
    }

    const providerData = getProviderData(type);
    currentProviderType = type;

    updateSelectedProvider(type, providerData.name);
    saveProviderToStorage(type, providerData.name);
}

function getProviderData(type) {
    switch (type) {
        case 1: return { name: 'Oracle Cloud' };
        case 2: return { name: 'Google Cloud' };
        case 3: return { name: 'Azure Cloud' };
        case 4: return { name: 'Amazon Cloud' };
        default: return { name: 'Oracle Cloud' };
    }
}

function selectProvider(type, name) {
    if (currentProviderType === type) {
        closeUserMenu();
        return;
    }

    currentProviderType = type;
    updateSelectedProvider(type, name);
    saveProviderToStorage(type, name);
    closeUserMenu();

    // 1. 定义不同云厂商对应的默认子页面路径
    const defaultPages = {
        1: '/tenants/list',
        2: '/tenants/list',
        3: '/azure/vms',
        4: '/aws/ec2'
    };
    const subPath = defaultPages[type] || '/boot/dashboard';

    // 2. 执行全量刷新跳转
    showProviderSwitchNotification(name, () => {
        window.location.href = `/main?path=${encodeURIComponent(subPath)}&cloudType=${type}`;
    });
}

function updateSelectedProvider(type, name) {
    const headerLabel = document.getElementById('headerCurrentProvider');
    if (headerLabel) {
        headerLabel.textContent = name;
    }

    document.querySelectorAll('.menu-item').forEach(item => {
        item.classList.remove('active-provider');
    });

    const activeBtn = document.getElementById('provider-btn-' + type);
    if (activeBtn) {
        activeBtn.classList.add('active-provider');
    }
}

function saveProviderToStorage(type, name) {
    const data = { type, name };
    localStorage.setItem('selectedCloudProvider', JSON.stringify(data));
}

function showProviderSwitchNotification(providerName, callback) {
    if (typeof Swal !== 'undefined') {
        Swal.fire({
            title: '切换云厂商',
            text: `正在切换到 ${providerName}...`,
            icon: 'info',
            showConfirmButton: false,
            timer: 800,
            timerProgressBar: true,
            didOpen: () => { Swal.showLoading(); }
        }).then(() => {
            callback();
        });
    } else {
        callback();
    }
}

function toggleUserMenu(event) {
    if (event) event.stopPropagation();
    const menu = document.getElementById('userDropdownMenu');
    const arrow = document.querySelector('.dropdown-arrow');
    const isShowing = menu.classList.contains('show');

    closeAllMenus();

    if (!isShowing) {
        menu.classList.add('show');
        if (arrow) arrow.style.transform = 'rotate(180deg)';
        showNavOverlay();
    }
}

function closeUserMenu() {
    closeAllMenus();
}

function switchLanguage(locale) {
    const currentUrl = new URL(window.location);
    currentUrl.searchParams.set('lang', locale);
    window.location.href = currentUrl.toString();
}
function checkVersionStatusAjax() {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), 5000);

    fetch('/api/version/check', {
        method: 'GET',
        headers: { 'Content-Type': 'application/json', 'X-Requested-With': 'XMLHttpRequest' },
        signal: controller.signal
    })
        .then(r => {
            clearTimeout(timeoutId);
            if (!r.ok) throw new Error(r.status);
            return r.json();
        })
        .then(data => {
            const updateBtn = document.getElementById('updateBtn');
            const numSpan = document.getElementById('newVersionNumber');
            if (!updateBtn || !numSpan) return;

            const needUpdate = data && data.needUpdate;
            const latestVersion = needUpdate ? (data.latestVersion || '') : '';

            if (cachedVersionInfo.needUpdate === needUpdate && cachedVersionInfo.latestVersion === latestVersion) return;
            cachedVersionInfo.needUpdate = needUpdate;
            cachedVersionInfo.latestVersion = latestVersion;

            if (needUpdate) {
                updateBtn.style.display = 'flex';
                numSpan.textContent = latestVersion;
            } else {
                updateBtn.style.display = 'none';
            }
        })
        .catch(e => {
            clearTimeout(timeoutId);
            if (e.name !== 'AbortError') console.warn('版本检查跳过');
        });
}

function executeUpdate() {
    // 复用 getCsrfConfig
    const csrf = getCsrfConfig();
    const newVersion = document.getElementById('newVersionNumber')?.textContent;
    if(!csrf.token || !newVersion) return;

    Swal.fire({
        title: i18n.version_update,
        html: i18n.version_updateVersion+` <b>${newVersion}</b> ?<br/><span style="color:red;font-size:12px;">`+i18n.version_restore+`</span>`,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonText: i18n.version_update
    }).then((result) => {
        if (result.isConfirmed) performUpdateAjax(csrf.token, newVersion);
    });
}

function performUpdateAjax(csrfToken, newVersion) {
    const updateBtn = document.getElementById('updateBtn');
    if(updateBtn) {
        updateBtn.disabled = true;
        updateBtn.innerHTML = '<i class="fas fa-sync fa-spin"></i> Updating...';
    }

    // 初始加载状态
    Swal.fire({
        title: i18n.version_sendingUpdate,
        allowOutsideClick: false,
        didOpen: () => Swal.showLoading()
    });

    fetch('/api/version/execute-update', {
        method: 'POST',
        headers: {
            'X-CSRF-TOKEN': csrfToken,
            'Content-Type': 'application/json',
            'X-Requested-With': 'XMLHttpRequest'
        },
        body: JSON.stringify({ version: newVersion, timestamp: Date.now() })
    })
        .then(r => r.json())
        .then(data => {
            if (data.success) {
                startRestartCountdown();
            } else {
                throw new Error(data.message);
            }
        })
        .catch(err => {
            Swal.fire('error', err.message, 'error');
            if(updateBtn) {
                updateBtn.disabled = false;
                updateBtn.innerHTML = `<span><i class="fas fa-arrow-circle-up"></i> ${messages?.headerNewVersion||'新版'} (${newVersion})</span>`;
            }
        });
}

function loadUserInfo(){
    const userNameElement = document.getElementById('currentUserName');
    const welcomeElement = document.getElementById('welcomeMessage');

    if (!userNameElement) {
        console.warn('Element with id "currentUserName" not found.');
        return;
    }

    userNameElement.textContent = 'loading';
    if (welcomeElement) {
        welcomeElement.textContent = '正在获取用户信息...';
    }

    fetch('/api/userInfo', {
        method: 'GET',
        headers: {}
    })
        .then(response => {
            if (!response.ok) {
                throw new Error(`HTTP error! Status: ${response.status}`);
            }
            return response.json();
        })
        .then(data => {
            if (data.success && data.data && data.data.username) {
                const username = data.data.username;

                userNameElement.textContent = username;

                if (welcomeElement) {
                    welcomeElement.textContent = i18n.header_welcome+`, ${username}`;
                    currentLoadedUsername = username;
                }
            } else {
                userNameElement.textContent = data.message || 'error';
                if (welcomeElement) {
                    welcomeElement.textContent = data.message || 'error';
                }
                console.error('Failed to get username:', data.message);
            }
        })
        .catch(error => {
            userNameElement.textContent = 'error';
            if (welcomeElement) {
                welcomeElement.textContent = 'error';
            }
            console.error('Error fetching user info:', error);
        });
}

function deleteMessageItem(event, businessId) {
    if (event) event.stopPropagation();

    const csrf = getCsrfConfig();

    fetch('/sysMessage/del', {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json',
            [csrf.header]: csrf.token
        },
        body: JSON.stringify({
            businessId: businessId
        })
    })
        .then(r => r.json())
        .then(res => {
            Swal.close();

            if (res.success) {
                const Toast = Swal.mixin({
                    toast: true,
                    position: 'top-end',
                    showConfirmButton: false,
                    timer: 2000,
                    timerProgressBar: true
                });
                loadMessageList();
                checkUnreadMessages();

            } else {
                console.error('删除失败:', res.message);
            }
        })
        .catch(e => {
            console.error('删除失败:', res.message);
        });
}

function startRestartCountdown() {
    let timerInterval;
    const countdownSeconds = 90;

    Swal.fire({
        title: i18n.version_sysRestore,
        html: `
            <div style="font-size: 14px; color: #555; margin-bottom: 10px;">
                `+i18n.version_loadNewVersion+`
            </div>
            <div style="font-size: 24px; font-weight: bold; color: #1890ff;">
                <b id="restart-timer">${countdownSeconds}</b> s
            </div>
            <div style="font-size: 12px; color: #999; margin-top: 10px;">
                `+i18n.version_noRefresh+`
            </div>
        `,
        timer: countdownSeconds * 1000,
        timerProgressBar: true,
        allowOutsideClick: false,
        allowEscapeKey: false,
        showConfirmButton: false,
        icon: 'info',
        didOpen: () => {
            const b = Swal.getHtmlContainer().querySelector('#restart-timer');
            timerInterval = setInterval(() => {
                if (b) {
                    const timeLeft = Math.ceil(Swal.getTimerLeft() / 1000);
                    b.textContent = timeLeft;
                }
            }, 100);
        },
        willClose: () => {
            clearInterval(timerInterval);
        }
    }).then((result) => {
        if (result.dismiss === Swal.DismissReason.timer) {
            location.href = '/login';
        }
    });
}

function toggleLanguagePanel(event) {
    if (event) event.stopPropagation();
    const menu = document.getElementById('languageDropdown');
    const isShowing = menu.classList.contains('show');

    closeAllMenus();

    if (!isShowing) {
        menu.classList.add('show');
        showNavOverlay();
    }
}

/**
 * 显示资产分析报告
 */
function showAssetAnalysis() {
    closeUserMenu();
    const cloudType = typeof currentProviderType !== 'undefined' ? currentProviderType : '';
    Swal.fire({
        title: 'loading',
        allowOutsideClick: false,
        didOpen: () => { Swal.showLoading(); }
    });
    fetch('/tenants/asset/analysis?cloudType='+cloudType)
        .then(r => r.json())
        .then(res => {
            if (res.success) {
                const data = res.data;
                const computedLevel = calculateOracleLevel(data.totalCount);
                updateHeaderLevelBadge(computedLevel, data.levelTitle);
                renderAssetModal(data);
            } else {
                Swal.fire('error', res.message, 'error');
            }
        })
        .catch(e => {
            const mockData = {
                totalCount: 12,
                upgradeCount: 4,
                freeCount: 8,
                totalCost: '1,240.50',
                level: 3,
                levelTitle: '👑 LEVEL V'
            };
            renderAssetModal(mockData);
        });
}

function updateHeaderLevelBadge(level, title) {
    const badge = document.getElementById('userLevelBadge');
    if (!badge) return;

    badge.className = 'lvl-badge'; // 重置类名

    const configs = {
        1: { name: '初级云玩家', icon: '👤' },
        2: { name: '中级云达人', icon: '🥉' },
        3: { name: '高级架构师', icon: '🥈' },
        4: { name: '资深资源商', icon: '🏅' },
        5: { name: '核心合伙人', icon: '🎖️' },
        6: { name: '顶级运营商', icon: '🔱' },
        7: { name: '巅峰掌控者', icon: '🔥' },
        8: { name: '至尊领航员', icon: '💎' },
        9: { name: 'Oracle 主宰者', icon: '👑' }
    };

    const currentLvl = Math.min(Math.max(parseInt(level) || 1, 1), 9);
    const config = configs[currentLvl];

    badge.classList.add(`lvl-${currentLvl}`);
    badge.innerHTML = `<span style="margin-right:4px;">${config.icon}</span> ${title || config.name}`;
}

function renderAssetModal(data) {
    const currentCount = data.totalCount || 0;
    const lvl = calculateOracleLevel(currentCount);

    const rankConfigs = {
        1: { name: '初级云玩家', icon: '👤' },
        2: { name: '中级云达人', icon: '🥉' },
        3: { name: '高级架构师', icon: '🥈' },
        4: { name: '资深资源商', icon: '🏅' },
        5: { name: '核心运营商', icon: '🎖️' },
        6: { name: '顶级运营商', icon: '🔱' },
        7: { name: '超级云达人', icon: '🔥' },
        8: { name: '至尊领航员', icon: '💎' },
        9: { name: '顶级云管家', icon: '👑' }
    };

    const config = rankConfigs[lvl];

    Swal.fire({
        title: '<div style="text-align: left; font-size: 18px; font-weight: 600; color: #1a1a1a; border-left: 4px solid #1abc9c; padding-left: 12px; margin-left: 5px; white-space: nowrap;">'+window.I18N.header_report+'</div>',
        width: '900px',
        padding: '1.5rem',
        showConfirmButton: true,
        confirmButtonText: window.I18N.header_closeReport,
        confirmButtonColor: '#1e2124',
        html: `
            <div style="padding: 10px 5px; font-family: -apple-system, sans-serif;">
                <div style="display: flex; align-items: stretch; border: 1px solid #e0e0e0; border-radius: 4px; overflow: hidden; background: #fff;">
                     <div style="flex: 0 0 200px; background: #f8f9fa; padding: 25px 15px; text-align: center; border-right: 1px solid #eee; display: flex; flex-direction: column; justify-content: center; align-items: center;">
                        <div style="font-size: 11px; color: #888; text-transform: uppercase; letter-spacing: 1.5px; margin-bottom: 12px; white-space: nowrap;">Account Level</div>
                        
                        <div class="lvl-badge lvl-${lvl}" style="font-size: 14px; padding: 6px 16px; margin-bottom: 8px; transform: scale(1.2);">
                             <span style="margin-right:5px;">${config.icon}</span> ${config.name}
                        </div>
                        
                        <div style="margin-top: 10px; font-size: 12px; color: #999; font-weight: 600;">
                            Scale: Lvl.${lvl}
                        </div>
                    </div>

                    <div style="flex: 1; display: flex; align-items: center; justify-content: space-around; padding: 20px 10px;">
                        <div style="flex: 1; border-right: 1px solid #f0f0f0; padding: 0 10px; text-align: center;">
                            <div style="font-size: 12px; color: #666;">${window.I18N.header_accetTotal}</div>
                            <div style="font-size: 24px; font-weight: 600;">${data.totalCount}</div>
                        </div>
                        <div style="flex: 1; border-right: 1px solid #f0f0f0; padding: 0 10px; text-align: center;">
                            <div style="font-size: 12px; color: #666;">${window.I18N.header_upgreadeTotal}</div>
                            <div style="font-size: 24px; font-weight: 600; color: #2196f3;">${data.upgradeCount}</div>
                        </div>
                        <div style="flex: 1; border-right: 1px solid #f0f0f0; padding: 0 10px; text-align: center;">
                            <div style="font-size: 12px; color: #666;">${window.I18N.header_freeTotal}</div>
                            <div style="font-size: 24px; font-weight: 600;">${data.freeCount}</div>
                        </div>
                        <div style="flex: 1; padding: 0 10px; text-align: center;">
                            <div style="font-size: 12px; color: #666;">${window.I18N.header_accountCost}</div>
                            <div style="font-size: 24px; font-weight: 600; color: #1abc9c;">${data.totalCost}</div>
                        </div>
                    </div>
                </div>

                <div id="aiAnalysisResult" style="margin-top: 20px; border-top: 1px dashed #eee; padding-top: 15px; text-align: left; display: none;">
                    <div style="margin-bottom: 10px; font-weight: bold; color: #6c5ce7; font-size: 14px;">
                        <i class="fas fa-robot"></i> ${window.I18N.ai_analyzeRes}：
                    </div>
                    <div id="aiContentText" style="
                        background: #f9f9f9; 
                        padding: 15px; 
                        border-radius: 6px; 
                        font-size: 13px; 
                        line-height: 1.8; 
                        color: #2d3436; 
                        white-space: pre-wrap; 
                        word-break: break-all;
                        font-family: 'Monaco', 'Menlo', 'Consolas', monospace;
                        border: 1px solid #f0f0f0;
                        max-height: 400px;
                        overflow-y: auto;
                    "></div>
                </div>

                <div style="margin-top: 20px; display: flex; justify-content: space-between; align-items: center;">
                    <div style="font-size: 11px; color: #999;">
                        <i class="fas fa-clock"></i> ${new Date().toLocaleString()}
                    </div>
                    <button id="aiAnalyzeBtn" onclick="executeAiAuditStream()" style="
                        background: #6c5ce7; color: white; border: none; padding: 8px 20px; border-radius: 4px; cursor: pointer; font-size: 13px;
                    ">
                        <i class="fas fa-magic"></i> ${window.I18N.ai_analyze}
                    </button>
                </div>
            </div>
        `
    });
}


async function executeAiAuditStream() {
    const btn = document.getElementById('aiAnalyzeBtn');
    const container = document.getElementById('aiAnalysisResult');
    const contentBox = document.getElementById('aiContentText');

    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> loading...';
    container.style.display = 'block';
    contentBox.innerText = '';

    try {
        const response = await fetch('/tenants/analyze');
        const reader = response.body.getReader();
        const decoder = new TextDecoder();
        let fullText = "";
        let lineBuffer = "";
        while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            lineBuffer += decoder.decode(value, { stream: true });
            let lines = lineBuffer.split('\n');
            lineBuffer = lines.pop();
            for (let line of lines) {
                let trimmedLine = line.trim();
                if (!trimmedLine) continue;

                if (trimmedLine.startsWith('data:')) {
                    let content = line.substring(line.indexOf(':') + 1);
                    fullText += content.trim() + "\n";
                    contentBox.innerText = fullText;
                    const swalContainer = document.querySelector('.swal2-html-container');
                    if (swalContainer) {
                        swalContainer.scrollTop = swalContainer.scrollHeight;
                    }
                }
            }
        }
        if (lineBuffer.startsWith('data:')) {
            fullText += lineBuffer.substring(lineBuffer.indexOf(':') + 1).trim() + "\n";
            contentBox.innerText = fullText;
        }

    } catch (error) {
        contentBox.innerText = "error: " + error.message;
    } finally {
        btn.disabled = false;
        btn.innerHTML = '<i class="fas fa-robot"></i> '+i18n.ai_analyzeRetry;
    }
}

function calculateOracleLevel(count) {
    if (count >= 201) return 9;
    if (count >= 121) return 8;
    if (count >= 81) return 7;
    if (count >= 51) return 6;
    if (count >= 26) return 5;
    if (count >= 11) return 4;
    if (count >= 5) return 3;
    if (count >= 3) return 2;
    return 1;
}

