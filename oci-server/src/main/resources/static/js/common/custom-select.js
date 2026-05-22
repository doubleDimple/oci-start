/**
 * CustomSelect — 公共自定义下拉组件
 *
 * 使用方式：
 *   1. 自动：给 <select> 添加 data-custom-select 属性，页面加载后自动初始化
 *   2. 手动：CustomSelect.init(selectEl [, options])
 *   3. 批量：CustomSelect.initAll(container)  — container 默认 document
 *
 * 支持的 data 属性（写在 <select> 上）：
 *   data-custom-select          — 标记为自动初始化
 *   data-placeholder="请选择"   — 未选中时的提示文字
 *   data-searchable             — 启用搜索过滤
 *   data-page-size="10"         — 启用分页，每页 N 条（0 = 不分页）
 *   data-max-width="300px"      — 限制触发器最大宽度
 *
 * 与原生 select 完全兼容：
 *   - JS 对 select.innerHTML / appendChild / selectedIndex 的操作
 *     会通过 MutationObserver 自动同步到自定义 UI
 *   - JS 监听的 select.onchange / addEventListener('change') 正常触发
 *   - select.value 赋值后调用 CustomSelect.refresh(selectEl) 可手动刷新显示
 */
(function (global) {
    'use strict';

    /* ── 内部工具 ── */
    function qs(sel, ctx) { return (ctx || document).querySelector(sel); }

    /* ── 单实例初始化 ── */
    function init(selectEl, opts) {
        if (!selectEl || selectEl.tagName !== 'SELECT') return;
        if (selectEl._csInited) return;
        selectEl._csInited = true;

        opts = opts || {};
        var placeholder = selectEl.dataset.placeholder || opts.placeholder || '';
        var searchable   = selectEl.hasAttribute('data-searchable') || !!opts.searchable;
        var maxWidth     = selectEl.dataset.maxWidth || opts.maxWidth || '';
        var pageSize     = parseInt(selectEl.dataset.pageSize || opts.pageSize || '0', 10) || 0;

        /* 分页状态 */
        var _page = 1;
        var _keyword = '';
        var _filteredOpts = [];

        /* 隐藏原生 select，但保留在 DOM 中供 JS 操作 */
        selectEl.style.display = 'none';

        /* ── 构建 wrapper ── */
        var wrapper = document.createElement('div');
        wrapper.className = 'cs-wrapper';
        if (maxWidth) wrapper.style.maxWidth = maxWidth;
        selectEl.parentNode.insertBefore(wrapper, selectEl);
        wrapper.appendChild(selectEl); // select 移入 wrapper

        /* ── 触发器 ── */
        var trigger = document.createElement('div');
        trigger.className = 'cs-trigger';
        trigger.setAttribute('tabindex', '0');
        trigger.setAttribute('role', 'combobox');
        trigger.setAttribute('aria-haspopup', 'listbox');
        trigger.setAttribute('aria-expanded', 'false');
        trigger.innerHTML =
            '<span class="cs-text placeholder"></span>' +
            '<i class="fas fa-chevron-down cs-arrow"></i>';
        wrapper.appendChild(trigger);

        var csText = trigger.querySelector('.cs-text');

        /* ── 下拉列表 ── */
        var dropdown = document.createElement('div');
        dropdown.className = 'cs-dropdown';
        dropdown.setAttribute('role', 'listbox');
        wrapper.appendChild(dropdown);

        /* ── 搜索框（可选） ── */
        var searchInput = null;
        if (searchable) {
            var searchBox = document.createElement('div');
            searchBox.className = 'cs-search';
            searchInput = document.createElement('input');
            searchInput.type = 'text';
            searchInput.placeholder = '搜索...';
            searchBox.appendChild(searchInput);
            dropdown.appendChild(searchBox);

            searchInput.addEventListener('input', function () {
                _keyword = this.value.trim().toLowerCase();
                if (pageSize) {
                    renderPage();
                } else {
                    var kw = _keyword;
                    dropdown.querySelectorAll('.cs-option').forEach(function (opt) {
                        var match = opt.textContent.toLowerCase().indexOf(kw) !== -1;
                        opt.classList.toggle('hidden', !match);
                    });
                    var noResult = qs('.cs-no-result', dropdown);
                    var hasVisible = dropdown.querySelectorAll('.cs-option:not(.hidden)').length > 0;
                    if (noResult) noResult.style.display = hasVisible ? 'none' : 'block';
                }
            });

            searchInput.addEventListener('click', function (e) { e.stopPropagation(); });
            searchInput.addEventListener('keydown', function (e) { e.stopPropagation(); });
        }

        /* ── 滚动分页：条目容器 + 加载提示 ── */
        var itemsContainer = null;
        var loadMoreEl = null;
        var _visibleCount = 0;

        if (pageSize) {
            itemsContainer = document.createElement('div');
            itemsContainer.className = 'cs-items';
            dropdown.appendChild(itemsContainer);

            loadMoreEl = null; // 不显示提示，静默加载

            /* 滚动到底部时追加下一批 */
            itemsContainer.addEventListener('scroll', function() {
                if (this.scrollHeight - this.scrollTop - this.clientHeight < 30) {
                    _appendItems();
                }
            });
        }

        /* 创建一个可点击条目 */
        function _makeItem(opt) {
            var item = document.createElement('div');
            item.className = 'cs-option' + (opt.value === selectEl.value ? ' selected' : '');
            item.textContent = opt.textContent;
            item.dataset.value = opt.value;
            item.setAttribute('role', 'option');
            item.addEventListener('click', function(e) {
                e.stopPropagation();
                selectEl.value = this.dataset.value;
                selectEl.dispatchEvent(new Event('change', { bubbles: true }));
                updateDisplay();
                close();
            });
            return item;
        }

        /* 追加下一批条目到列表末尾，若容器仍未溢出则继续追加 */
        function _appendItems() {
            if (!itemsContainer || _visibleCount >= _filteredOpts.length) return;
            var end = Math.min(_filteredOpts.length, _visibleCount + pageSize);
            for (var i = _visibleCount; i < end; i++) {
                itemsContainer.appendChild(_makeItem(_filteredOpts[i]));
            }
            _visibleCount = end;
            /* 如果内容没有超出容器高度（无滚动条），继续追加下一批 */
            if (_visibleCount < _filteredOpts.length &&
                itemsContainer.scrollHeight <= itemsContainer.clientHeight) {
                _appendItems();
            }
        }

        /* 重置并渲染第一批 */
        function renderPage() {
            if (!pageSize || !itemsContainer) return;

            /* 重新过滤 */
            var allOpts = Array.from(selectEl.options).filter(function(opt) {
                return opt.value !== '' && !opt.disabled;
            });
            _filteredOpts = _keyword
                ? allOpts.filter(function(opt) {
                    return opt.textContent.toLowerCase().indexOf(_keyword) !== -1;
                  })
                : allOpts;

            /* 清空并重置计数 */
            itemsContainer.innerHTML = '';
            _visibleCount = 0;

            if (_filteredOpts.length === 0) {
                var empty = document.createElement('div');
                empty.className = 'cs-no-result';
                empty.textContent = '无匹配项';
                itemsContainer.appendChild(empty);
                if (loadMoreEl) loadMoreEl.style.display = 'none';
            } else {
                _appendItems();
            }
        }

        /* ── 同步 options → 自定义列表（无分页模式） ── */
        function syncOptions() {
            if (pageSize) {
                /* 滚动分页模式：重置并渲染第一批 */
                renderPage();
                updateDisplay();
                return;
            }

            /* 保留搜索框 */
            while (dropdown.lastChild &&
                   !dropdown.lastChild.classList.contains('cs-search')) {
                dropdown.removeChild(dropdown.lastChild);
            }

            var hasOpts = false;
            Array.from(selectEl.options).forEach(function (opt) {
                var item = document.createElement('div');
                var isEmpty = opt.value === '' || opt.disabled;
                item.className = 'cs-option' +
                    (isEmpty ? ' is-placeholder' : '') +
                    (opt.selected && !isEmpty ? ' selected' : '');
                item.textContent = opt.textContent;
                item.dataset.value = opt.value;
                item.setAttribute('role', 'option');
                item.setAttribute('aria-selected', String(!!opt.selected));

                item.addEventListener('click', function (e) {
                    e.stopPropagation();
                    selectEl.value = this.dataset.value;
                    selectEl.dispatchEvent(new Event('change', { bubbles: true }));
                    updateDisplay();
                    close();
                });

                dropdown.appendChild(item);
                if (!isEmpty) hasOpts = true;
            });

            /* 无结果占位（搜索时用） */
            if (searchable) {
                var nr = document.createElement('div');
                nr.className = 'cs-no-result';
                nr.textContent = '无匹配项';
                nr.style.display = 'none';
                dropdown.appendChild(nr);
            }

            updateDisplay();
        }

        /* ── 刷新触发器显示文字 ── */
        function updateDisplay() {
            var idx = selectEl.selectedIndex;
            var selOpt = idx >= 0 ? selectEl.options[idx] : null;
            var isPlaceholder = !selOpt || selOpt.value === '' || selOpt.disabled;

            if (isPlaceholder) {
                csText.textContent = placeholder ||
                    (selOpt ? selOpt.textContent : '');
                csText.classList.add('placeholder');
            } else {
                csText.textContent = selOpt.textContent;
                csText.classList.remove('placeholder');
            }

            if (!pageSize) {
                /* 同步选中高亮（无分页模式） */
                dropdown.querySelectorAll('.cs-option').forEach(function (item) {
                    var active = item.dataset.value === selectEl.value && !isPlaceholder;
                    item.classList.toggle('selected', active);
                    item.setAttribute('aria-selected', String(active));
                });
            }
        }

        /* ── 开 / 关 ── */
        function open() {
            if (selectEl.disabled) return;
            /* 关闭其他已打开的 */
            document.querySelectorAll('.cs-wrapper.open').forEach(function (w) {
                if (w !== wrapper) w.classList.remove('open');
            });
            wrapper.classList.add('open');
            trigger.setAttribute('aria-expanded', 'true');
            if (pageSize) {
                _keyword = '';
                renderPage();
                itemsContainer.scrollTop = 0;
            }
            if (searchInput) { searchInput.value = ''; searchInput.focus(); }
            /* 让选中项滚动可见（无分页模式） */
            if (!pageSize) {
                var sel = qs('.cs-option.selected', dropdown);
                if (sel) sel.scrollIntoView({ block: 'nearest' });
            }
        }

        function close() {
            wrapper.classList.remove('open');
            trigger.setAttribute('aria-expanded', 'false');
        }

        /* ── 事件绑定 ── */
        trigger.addEventListener('click', function (e) {
            e.stopPropagation();
            wrapper.classList.contains('open') ? close() : open();
        });

        /* 键盘支持 */
        trigger.addEventListener('keydown', function (e) {
            if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                wrapper.classList.contains('open') ? close() : open();
            } else if (e.key === 'Escape') {
                close();
            }
        });

        document.addEventListener('click', function () { close(); });

        /* ── MutationObserver：监听 select options 变化 ── */
        var observer = new MutationObserver(syncOptions);
        observer.observe(selectEl, { childList: true, subtree: true, attributes: true });

        /* disabled 状态同步 */
        var disabledObs = new MutationObserver(function () {
            wrapper.classList.toggle('disabled', selectEl.disabled);
        });
        disabledObs.observe(selectEl, { attributes: true, attributeFilter: ['disabled'] });

        /* ── 暴露 refresh 方法（供外部手动触发） ── */
        selectEl._csRefresh = updateDisplay;

        /* ── 初始渲染 ── */
        syncOptions();
    }

    /* ── 批量初始化 ── */
    function initAll(container) {
        var ctx = container || document;
        ctx.querySelectorAll('select[data-custom-select]').forEach(function (el) {
            init(el);
        });
    }

    /* ── 手动刷新（外部赋值 select.value 后调用） ── */
    function refresh(selectEl) {
        if (selectEl && selectEl._csRefresh) selectEl._csRefresh();
    }

    /* ── DOM 就绪自动初始化 ── */
    function ready(fn) {
        if (document.readyState !== 'loading') fn();
        else document.addEventListener('DOMContentLoaded', fn);
    }

    ready(function () { initAll(document); });

    /* ── 导出公共 API ── */
    global.CustomSelect = { init: init, initAll: initAll, refresh: refresh };

})(window);
