/**
 * mobile.js - 移动端交互逻辑
 * 职责：底部 Tab 切换、侧边栏抽屉开关
 * 原则：不干扰桌面端任何逻辑，仅在移动端宽度下激活
 * Author: doubleDimple
 */
(function () {
    'use strict';

    var MOBILE_BREAKPOINT = 768;

    /* ---- 工具：是否移动端 ---- */
    function isMobile() {
        return window.innerWidth <= MOBILE_BREAKPOINT;
    }

    /* ---- 等待 DOM 就绪 ---- */
    function ready(fn) {
        if (document.readyState !== 'loading') {
            fn();
        } else {
            document.addEventListener('DOMContentLoaded', fn);
        }
    }

    /* ============================================================
       侧边栏抽屉控制
       ============================================================ */
    var sidebarOpen = false;

    function openSidebar() {
        var sidebar = document.querySelector('.sidebar');
        var overlay = document.getElementById('mobileOverlay');
        if (!sidebar || !overlay) return;
        sidebar.classList.add('mobile-sidebar-open');
        overlay.classList.add('active');
        sidebarOpen = true;
        document.body.style.overflow = 'hidden';
    }

    function closeSidebar() {
        var sidebar = document.querySelector('.sidebar');
        var overlay = document.getElementById('mobileOverlay');
        if (!sidebar || !overlay) return;
        sidebar.classList.remove('mobile-sidebar-open');
        overlay.classList.remove('active');
        sidebarOpen = false;
        document.body.style.overflow = '';
    }

    function toggleSidebar() {
        if (sidebarOpen) {
            closeSidebar();
        } else {
            openSidebar();
        }
    }

    /* ============================================================
       底部 Tab 栏：切换激活态 + 加载页面到 iframe
       ============================================================ */
    var tabItems = [];

    function setActiveTab(index) {
        tabItems.forEach(function (item, i) {
            if (i === index) {
                item.classList.add('active');
            } else {
                item.classList.remove('active');
            }
        });
    }

    function loadFrame(url) {
        var frame = document.getElementById('biz-frame');
        if (frame && url) {
            frame.src = url;
        }
    }

    /* ============================================================
       Tab 配置
       ============================================================ */
    var TAB_CONFIG = [
        {
            icon: 'fas fa-chart-pie',
            label: '仪表盘',
            labelKey: 'tab.dashboard',
            url: '/boot/dashboard'
        },
        {
            icon: 'fas fa-server',
            label: '实例',
            labelKey: 'tab.instances',
            url: '/boot/fullBootList'
        },
        /*{
            icon: 'fas fa-chart-line',
            label: '监控',
            labelKey: 'tab.monitor',
            url: '/oci/monitoring'
        },
        {
            icon: 'fas fa-comments',
            label: 'AI',
            labelKey: 'tab.chat',
            url: '/system/chat'
        },*/
        {
            icon: 'fas fa-bars',
            label: '更多',
            labelKey: 'tab.more',
            url: null  // 打开侧边栏
        }
    ];

    /* 从 window.I18N 取翻译，fallback 到默认文字 */
    function getTabLabel(tab) {
        if (window.I18N && window.I18N[tab.labelKey]) {
            return window.I18N[tab.labelKey];
        }
        return tab.label;
    }

    /* ============================================================
       构建底部 Tab 栏 DOM
       ============================================================ */
    function buildTabBar() {
        var tabBar = document.getElementById('mobileTabBar');
        if (!tabBar) return;

        TAB_CONFIG.forEach(function (tab, index) {
            var btn = document.createElement('button');
            btn.className = 'mobile-tab-item';
            btn.setAttribute('type', 'button');
            btn.setAttribute('aria-label', getTabLabel(tab));
            btn.innerHTML =
                '<i class="' + tab.icon + '"></i>' +
                '<span>' + getTabLabel(tab) + '</span>';

            btn.addEventListener('click', function () {
                if (tab.url === null) {
                    /* "更多" 按钮：打开侧边栏 */
                    toggleSidebar();
                    /* 打开时高亮，关闭时取消高亮 */
                    if (sidebarOpen) {
                        setActiveTab(index);
                    } else {
                        /* 回到上一个激活的 tab */
                        setActiveTab(window._mobileLastTabIndex || 0);
                    }
                } else {
                    loadFrame(tab.url);
                    setActiveTab(index);
                    window._mobileLastTabIndex = index;
                    /* 如果侧边栏是打开的，关掉它 */
                    if (sidebarOpen) {
                        closeSidebar();
                    }
                }
            });

            tabItems.push(btn);
            tabBar.appendChild(btn);
        });

        /* 默认激活第一项（仪表盘） */
        if (tabItems.length > 0) {
            tabItems[0].classList.add('active');
            window._mobileLastTabIndex = 0;
        }
    }

    /* ============================================================
       侧边栏内链接点击后自动关闭抽屉
       ============================================================ */
    function bindSidebarLinks() {
        var sidebar = document.querySelector('.sidebar');
        if (!sidebar) return;

        sidebar.addEventListener('click', function (e) {
            if (!isMobile()) return;
            /* 找到最近的 a.nav-link */
            var link = e.target.closest('a.nav-link[href]');
            if (link && link.getAttribute('target') === 'biz-frame') {
                /* 延迟一帧，让 iframe 先开始加载再关闭 */
                setTimeout(function () {
                    closeSidebar();
                    /* 高亮"更多"按钮取消，回到无特定 tab 高亮 */
                    setActiveTab(-1);
                }, 50);
            }
        });
    }

    /* ============================================================
       窗口尺寸变化：桌面端恢复
       ============================================================ */
    function onResize() {
        if (!isMobile()) {
            closeSidebar();
        }
    }

    /* ============================================================
       初始化入口
       ============================================================ */
    ready(function () {
        if (!isMobile()) return;  /* 桌面端完全不执行 */

        buildTabBar();
        bindSidebarLinks();

        /* 遮罩点击关闭侧边栏 */
        var overlay = document.getElementById('mobileOverlay');
        if (overlay) {
            overlay.addEventListener('click', closeSidebar);
        }

        /* 窗口大小变化处理 */
        var resizeTimer;
        window.addEventListener('resize', function () {
            clearTimeout(resizeTimer);
            resizeTimer = setTimeout(onResize, 200);
        });
    });

    /* 暴露给外部调用（如侧边栏内的汉堡按钮） */
    window.MobileNav = {
        open: openSidebar,
        close: closeSidebar,
        toggle: toggleSidebar
    };

})();
