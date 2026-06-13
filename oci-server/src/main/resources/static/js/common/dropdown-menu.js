/**
 * dropdown-menu.js
 * 1. 支持静态页面自动初始化
 * 2. 支持动态表格手动调用
 * 3. 点击选项后自动关闭菜单
 * 4. panel 关闭后归还原始 DOM 位置，避免多租户行相互干扰
 */
(function() {
    let currentOpen = null;

    const openLeftFixed = (toggle, panel) => {
        if (panel.parentElement !== document.body) {
            // 记录原始位置，关闭时归还
            panel._origParent  = panel.parentElement;
            panel._origSibling = panel.nextSibling;
            document.body.appendChild(panel);
        }

        panel.classList.add('floating', 'show');
        panel.style.display = 'flex';

        const t  = toggle.getBoundingClientRect();
        const p  = panel.getBoundingClientRect();
        const vh = window.innerHeight;
        const gap = 10;

        let left = t.left - p.width - gap;
        left = Math.max(8, left);

        let top = t.top;
        if (top + p.height > vh - 8) top = Math.max(8, vh - p.height - 8);
        if (top < 8) top = 8;

        panel.style.left     = `${left}px`;
        panel.style.top      = `${top}px`;
        panel.style.position = 'fixed';
        panel.style.zIndex   = '9999';
    };

    const closeAll = () => {
        document.querySelectorAll('.dropdown-panel.show').forEach(p => {
            p.classList.remove('show', 'floating');
            p.removeAttribute('style');
            // 归还 panel 到原始 DOM 位置
            if (p._origParent) {
                if (p._origSibling && p._origSibling.parentNode === p._origParent) {
                    p._origParent.insertBefore(p, p._origSibling);
                } else {
                    p._origParent.appendChild(p);
                }
                p._origParent  = null;
                p._origSibling = null;
            }
        });
        currentOpen = null;
    };

    const handleToggleLogic = (toggle, e) => {
        if (e) e.stopPropagation();

        let id    = toggle.dataset.dropdownId;
        let panel = null;

        if (id) {
            panel = document.querySelector(`.dropdown-panel[data-dropdown-id="${id}"]`);
            if (!panel) panel = toggle.nextElementSibling;
        } else {
            panel = toggle.nextElementSibling;
            if (panel) {
                id = `dropdown-${Date.now()}-${Math.random().toString(36).substr(2, 5)}`;
                toggle.dataset.dropdownId = id;
                panel.dataset.dropdownId  = id;
            }
        }

        if (!panel) return;

        const isAlreadyOpen = panel.classList.contains('show');
        closeAll();

        if (!isAlreadyOpen) {
            openLeftFixed(toggle, panel);
            currentOpen = { toggle, panel };
        }
    };

    document.addEventListener('DOMContentLoaded', () => {
        document.querySelectorAll('.dropdown').forEach((dropdown, idx) => {
            const toggle = dropdown.querySelector('.dropdown-toggle');
            const panel  = dropdown.querySelector('.dropdown-panel');
            if (toggle && panel) {
                const id = `static-dropdown-${idx}`;
                toggle.dataset.dropdownId = id;
                panel.dataset.dropdownId  = id;
                toggle.addEventListener('click', (e) => handleToggleLogic(toggle, e));
            }
        });

        document.addEventListener('click', (e) => {
            if (e.target.closest('.dropdown-item')) { closeAll(); return; }
            if (!e.target.closest('.dropdown') && !e.target.closest('.dropdown-panel')) {
                closeAll();
            }
        });

        const recompute = () => {
            if (!currentOpen || !currentOpen.panel.classList.contains('show')) return;
            if (document.body.contains(currentOpen.toggle)) {
                openLeftFixed(currentOpen.toggle, currentOpen.panel);
            } else {
                closeAll();
            }
        };
        window.addEventListener('resize', recompute);
        window.addEventListener('scroll', recompute, true);
    });

    window.handleDynamicToggle = function(btn, event) {
        handleToggleLogic(btn, event);
    };

})();
