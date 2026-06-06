document.addEventListener('DOMContentLoaded', function() {
    initializeMenuToggle();
    expandMenusWithActiveChildren();

    initializeMenuVisibility();
    initializeSidebarCollapse();

    document.addEventListener('cloudProviderChanged', function(event) {
        const cloudType = event.detail.type;
        updateMenuVisibility(cloudType);
    });
});

/**
 * 把 head 预设的 preload-sidebar-collapsed 转移到 body.sidebar-collapsed,
 * 这样 transition 才会作用于后续 toggle 动画(preload 阶段刻意不带动画,防闪烁)。
 * 同时给折叠按钮 / 搜索框绑定事件。
 */
function initializeSidebarCollapse() {
    var preload = document.documentElement.classList.contains('preload-sidebar-collapsed');
    if (preload) {
        document.body.classList.add('sidebar-collapsed');
        requestAnimationFrame(function () {
            document.documentElement.classList.remove('preload-sidebar-collapsed');
        });
    }

    var btn = document.getElementById('sidebarToggleBtn');
    if (btn && !btn._sidebarBound) {
        btn._sidebarBound = true;
        btn.addEventListener('click', function (e) {
            e.stopPropagation();
            toggleSidebar();
        });
    }

    initializeSidebarSearch();
}

/**
 * 切换侧边栏折叠状态,持久化到 localStorage
 * 折叠时如果有搜索关键词,清空搜索(否则收起后看不到效果)
 */
function toggleSidebar() {
    var collapsed = document.body.classList.toggle('sidebar-collapsed');
    try { localStorage.setItem('sidebar_collapsed', collapsed ? '1' : '0'); } catch (_) {}
    if (collapsed) {
        var input = document.getElementById('sidebarSearchInput');
        if (input && input.value) {
            input.value = '';
            applySidebarSearch('');
        }
    }
}

/* ============================================================
   侧边栏搜索:支持一级菜单(.nav-parent > .nav-link)和
   二级菜单(.nav-children > .nav-link)模糊匹配
   ============================================================ */
function initializeSidebarSearch() {
    var input = document.getElementById('sidebarSearchInput');
    var clearBtn = document.getElementById('sidebarSearchClear');
    if (!input || input._sidebarBound) return;
    input._sidebarBound = true;

    var wrapper = input.closest('.sidebar-search');

    input.addEventListener('input', function () {
        var kw = input.value.trim().toLowerCase();
        if (wrapper) wrapper.classList.toggle('has-value', kw.length > 0);
        applySidebarSearch(kw);
    });

    input.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') {
            input.value = '';
            if (wrapper) wrapper.classList.remove('has-value');
            applySidebarSearch('');
            input.blur();
        }
    });

    if (clearBtn) {
        clearBtn.addEventListener('click', function () {
            input.value = '';
            if (wrapper) wrapper.classList.remove('has-value');
            applySidebarSearch('');
            input.focus();
        });
    }
}

/**
 * 根据关键词过滤侧边栏菜单
 * @param {string} kw 关键词(已 lowercase + trim)
 */
function applySidebarSearch(kw) {
    var navParents = document.querySelectorAll('.sidebar .nav-parent');
    var emptyHint = document.getElementById('sidebarSearchEmpty');
    var anyVisible = false;

    navParents.forEach(function (parent) {
        var parentLink = parent.querySelector(':scope > .nav-link');
        var parentTextEl = parentLink ? parentLink.querySelector('span') : null;
        var parentText = parentTextEl ? parentTextEl.textContent.toLowerCase() : '';

        var children = parent.querySelectorAll('.nav-children > .nav-link');
        var anyChildMatch = false;

        if (!kw) {
            // 清空搜索:全部恢复
            parent.classList.remove('sidebar-hidden');
            children.forEach(function (c) { c.classList.remove('sidebar-hidden'); });
            anyVisible = true;
            return;
        }

        var parentMatch = parentText.indexOf(kw) !== -1;

        children.forEach(function (child) {
            var childSpan = child.querySelector('span');
            var childText = childSpan ? childSpan.textContent.toLowerCase() : '';
            var match = childText.indexOf(kw) !== -1;
            child.classList.toggle('sidebar-hidden', !match && !parentMatch);
            if (match) anyChildMatch = true;
        });

        if (parentMatch || anyChildMatch) {
            parent.classList.remove('sidebar-hidden');
            anyVisible = true;
            // 自动展开,让命中的二级菜单可见
            var navLink = parent.querySelector(':scope > .nav-link');
            var navChildren = parent.querySelector(':scope > .nav-children');
            if (navLink && navChildren && navLink.getAttribute('aria-expanded') !== 'true') {
                navLink.setAttribute('aria-expanded', 'true');
                navChildren.setAttribute('aria-hidden', 'false');
                navChildren.style.display = 'block';
                parent.classList.add('nav-expanded');
            }
        } else {
            parent.classList.add('sidebar-hidden');
        }
    });

    if (emptyHint) emptyHint.style.display = (kw && !anyVisible) ? 'block' : 'none';
}

function getSidebarCloudType() {
    const urlParams = new URLSearchParams(window.location.search);
    const urlType = urlParams.get('cloudType');
    if (urlType) {
        return parseInt(urlType);
    }

    try {
        const saved = localStorage.getItem('selectedCloudProvider');
        if (saved) {
            const data = JSON.parse(saved);
            return data.type || 1;
        }
    } catch (e) {
        console.error('Sidebar读取缓存失败', e);
    }

    return 1;
}

/**
 * 初始化菜单可见性
 */
function initializeMenuVisibility() {
    const currentType = getSidebarCloudType();
    updateMenuVisibility(currentType);
}

function updateMenuVisibility(cloudType) {
    const allCloudMenus = document.querySelectorAll('.cloud-menu');

    allCloudMenus.forEach(menu => {
        const supportedTypesStr = menu.getAttribute('data-cloud-types');

        if (supportedTypesStr) {
            const types = supportedTypesStr.split(',').map(t => parseInt(t.trim()));
            const shouldShow = types.includes(cloudType);

            if (shouldShow) {
                showMenuItem(menu);
            } else {
                hideMenuItem(menu);
            }
        }
    });

    updateMenuLinks(cloudType);
}

function initializeMenuToggle() {
    const navParents = document.querySelectorAll('.nav-parent');

    navParents.forEach(parent => {
        const navLink = parent.querySelector('.nav-link');
        const navChildren = parent.querySelector('.nav-children');

        if (navLink && navChildren) {
            if (!navLink.getAttribute('aria-expanded')) {
                navLink.setAttribute('aria-expanded', 'false');
            }
            if (!parent.classList.contains('nav-active') && !navLink.classList.contains('active')) {
                navChildren.setAttribute('aria-hidden', 'true');
                navChildren.style.display = 'none';
            }

            navLink.addEventListener('click', function(e) {
                const href = this.getAttribute('href');
                if (this.tagName === 'A' && href && href !== '#' && href !== 'javascript:;') {
                    return;
                }

                e.preventDefault();
                e.stopPropagation();

                toggleMenu(this, navChildren);
            });

            const childLinks = navChildren.querySelectorAll('.nav-link');
            childLinks.forEach(link => {
                link.addEventListener('click', function(e) {
                    e.stopPropagation();
                });
            });
        }
    });

    const allLinks = document.querySelectorAll('.nav-link');
    allLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            const href = this.getAttribute('href');
            if (href && href !== '#' && href !== 'javascript:;') {
                // 移除所有旧的高亮
                allLinks.forEach(l => l.classList.remove('active'));
                // 给当前点击的加上高亮
                this.classList.add('active');
            }
        });
    });
}

function expandMenusWithActiveChildren() {
    const navParents = document.querySelectorAll('.nav-parent');

    navParents.forEach(parent => {
        const navLink = parent.querySelector('.nav-link');
        const navChildren = parent.querySelector('.nav-children');

        if (navLink && navChildren) {
            const activeChild = navChildren.querySelector('.nav-link.active');
            const isParentActive = parent.classList.contains('nav-active');

            if (activeChild || isParentActive) {
                navLink.setAttribute('aria-expanded', 'true');
                navChildren.setAttribute('aria-hidden', 'false');
                navChildren.style.display = 'block'; // 确保是 block
                parent.classList.add('nav-expanded');
            }
        }
    });
}

function toggleMenu(navLink, navChildren) {
    // 折叠态下点击一级菜单:先展开 sidebar,然后强制 expand 当前 menu
    // (而不是 toggle —— 折叠状态下子菜单不可见,toggle 语义无意义)
    if (document.body.classList.contains('sidebar-collapsed')) {
        toggleSidebar();
        // 等下一帧再 expand,确保 CSS 已切换、navChildren 不再被 display:none 强制隐藏
        requestAnimationFrame(function () {
            expandMenu(navLink, navChildren);
        });
        return;
    }

    const isExpanded = navLink.getAttribute('aria-expanded') === 'true';
    if (isExpanded) {
        collapseMenu(navLink, navChildren);
    } else {
        expandMenu(navLink, navChildren);
    }
}

function expandMenu(navLink, navChildren) {
    document.querySelectorAll('.nav-parent').forEach(function (other) {
        const oc = other.querySelector('.nav-children');
        const ol = other.querySelector('.nav-link');
        if (oc && oc !== navChildren && ol && ol.getAttribute('aria-expanded') === 'true') {
            collapseMenu(ol, oc);
        }
    });

    navLink.setAttribute('aria-expanded', 'true');
    navChildren.setAttribute('aria-hidden', 'false');
    navChildren.style.display = 'block';
    navLink.closest('.nav-parent').classList.add('nav-expanded');

    const firstChild = findFirstVisibleChildLink(navChildren);
    if (firstChild) firstChild.click();
}

function findFirstVisibleChildLink(navChildren) {
    const links = navChildren.querySelectorAll('.nav-link[href]');
    for (let i = 0; i < links.length; i++) {
        const el = links[i];
        const href = el.getAttribute('href');
        if (!href || href === '#' || href.indexOf('javascript:') === 0) continue;
        if (el.offsetParent === null) continue;
        return el;
    }
    return null;
}

function collapseMenu(navLink, navChildren) {
    navLink.setAttribute('aria-expanded', 'false');
    navChildren.setAttribute('aria-hidden', 'true');
    navChildren.style.display = 'none';
    navLink.closest('.nav-parent').classList.remove('nav-expanded');
}

// 显示菜单项
function showMenuItem(menuItem) {
    menuItem.style.display = '';
    menuItem.classList.remove('hiding');
    menuItem.classList.add('showing');
}

function hideMenuItem(menuItem) {
    menuItem.style.display = 'none';
    menuItem.classList.remove('showing');
}

function updateMenuLinks(cloudType) {
    const menuLinks = document.querySelectorAll('.nav-link');

    menuLinks.forEach(link => {
        const href = link.getAttribute('href');
        if (href && !href.startsWith('#') && !href.startsWith('javascript')) {
            try {
                const url = new URL(href, window.location.origin);
                url.searchParams.set('cloudType', cloudType);
                link.setAttribute('href', url.pathname + url.search);
            } catch(e) {
            }
        }
    });
}