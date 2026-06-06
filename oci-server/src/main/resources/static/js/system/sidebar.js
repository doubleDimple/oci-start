document.addEventListener('DOMContentLoaded', function() {
    initializeMenuToggle();
    expandMenusWithActiveChildren();

    initializeMenuVisibility();

    document.addEventListener('cloudProviderChanged', function(event) {
        const cloudType = event.detail.type;
        updateMenuVisibility(cloudType);
    });
});

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