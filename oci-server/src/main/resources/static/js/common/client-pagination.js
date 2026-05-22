/**
 * ClientPagination — 客户端分页组件
 * 复用 pagination.ftl 的 HTML 结构和 CSS 类名，适用于一次性返回全量数据的场景
 *
 * 用法：
 *   const pg = new ClientPagination({
 *     data: [],
 *     pageSize: 20,
 *     tbodyEl: '#costTableBody',       // tbody 选择器或 DOM 元素
 *     paginationEl: '#costPagination',  // 分页容器选择器或 DOM 元素
 *     renderRow: (item) => `<tr>...</tr>`,
 *     emptyHtml: '<tr><td ...>暂无数据</td></tr>',
 *     i18n: { show, item, prev, next, jump, page, total }  // 可选
 *   });
 *   pg.setData(list);   // 设置数据并渲染
 */
class ClientPagination {
    constructor(options) {
        this.data = options.data || [];
        this.pageSize = options.pageSize || 20;
        this.tbody = typeof options.tbodyEl === 'string'
            ? document.querySelector(options.tbodyEl)
            : options.tbodyEl;
        this.paginationEl = typeof options.paginationEl === 'string'
            ? document.querySelector(options.paginationEl)
            : options.paginationEl;
        this.renderRow = options.renderRow;
        this.emptyHtml = options.emptyHtml ||
            '<tr><td colspan="100" style="text-align:center;padding:20px;color:var(--text-secondary)">暂无数据</td></tr>';
        this.i18n = Object.assign({
            show: '显示', item: '条', prev: '上一页', next: '下一页',
            jump: '跳至', page: '页', total: '共'
        }, options.i18n);
        this.currentPage = 1;
    }

    /** 重新设置数据并从第一页开始渲染 */
    setData(data) {
        this.data = data;
        this.currentPage = 1;
        this.render();
    }

    get totalPages() {
        return Math.max(1, Math.ceil(this.data.length / this.pageSize));
    }

    render() {
        this._renderRows();
        this._renderPagination();
    }

    _renderRows() {
        if (!this.tbody) return;
        const start = (this.currentPage - 1) * this.pageSize;
        const slice = this.data.slice(start, start + this.pageSize);
        this.tbody.innerHTML = slice.length
            ? slice.map(this.renderRow).join('')
            : this.emptyHtml;
    }

    _goToPage(page) {
        if (page < 1 || page > this.totalPages || page === this.currentPage) return;
        this.currentPage = page;
        this.render();
    }

    _renderPagination() {
        if (!this.paginationEl) return;
        const total = this.totalPages;
        const cur = this.currentPage;
        const len = this.data.length;
        const { show, item, prev, next, jump, page: pageText, total: totalText } = this.i18n;

        // 数据为空或只有一页时隐藏分页
        if (len === 0) { this.paginationEl.innerHTML = ''; return; }

        let html = `<div class="pagination-container"><div class="pagination-wrapper">`;

        /* ── 每页条数 ── */
        html += `
        <div class="page-size-selector">
            <span class="page-size-label">${show}</span>
            <div class="select-wrapper">
                <select class="page-size-select" id="cpg-size-select">
                    ${[10, 20, 50, 100].map(s =>
                        `<option value="${s}"${s === this.pageSize ? ' selected' : ''}>${s}</option>`
                    ).join('')}
                </select>
                <i class="fas fa-chevron-down select-arrow"></i>
            </div>
            <span class="page-size-label">${item}</span>
        </div>`;

        /* ── 导航按钮 ── */
        html += `<div class="pagination-nav">
            <button class="pagination-btn nav-btn prev-btn${cur === 1 ? ' disabled' : ''}"
                    ${cur === 1 ? 'disabled' : ''} data-page="${cur - 1}">
                <i class="fas fa-chevron-left"></i>
                <span class="btn-text">${prev}</span>
            </button>
            <div class="page-numbers">`;

        // 滑动窗口页码
        let sp = Math.max(1, cur - 2);
        let ep = Math.min(total, sp + 4);
        if (ep - sp < 4) sp = Math.max(1, ep - 4);

        if (sp > 1) {
            html += `<button class="pagination-btn page-btn" data-page="1">1</button>`;
            if (sp > 2) html += `<span class="pagination-ellipsis"><i class="fas fa-ellipsis-h"></i></span>`;
        }
        for (let i = sp; i <= ep; i++) {
            html += `<button class="pagination-btn page-btn${i === cur ? ' active' : ''}" data-page="${i}">${i}</button>`;
        }
        if (ep < total) {
            if (ep < total - 1) html += `<span class="pagination-ellipsis"><i class="fas fa-ellipsis-h"></i></span>`;
            html += `<button class="pagination-btn page-btn" data-page="${total}">${total}</button>`;
        }

        html += `</div>
            <button class="pagination-btn nav-btn next-btn${cur === total ? ' disabled' : ''}"
                    ${cur === total ? 'disabled' : ''} data-page="${cur + 1}">
                <span class="btn-text">${next}</span>
                <i class="fas fa-chevron-right"></i>
            </button>
        </div>`;

        /* ── 跳转 + 统计 ── */
        html += `
        <div class="pagination-info">
            <div class="page-jump">
                <span class="jump-label">${jump}</span>
                <input type="number" class="jump-input" id="cpg-jump-input"
                       min="1" max="${total}" placeholder="${cur}">
                <span class="jump-label">${pageText}</span>
                <button class="jump-btn" id="cpg-jump-btn">
                    <i class="fas fa-arrow-right"></i>
                </button>
            </div>
            <div class="total-info">
                <span class="total-text">${totalText} <strong>${len}</strong> ${item}</span>
                <span class="page-info">第 <strong>${cur}</strong> / <strong>${total}</strong> ${pageText}</span>
            </div>
        </div>`;

        html += `</div></div>`;
        this.paginationEl.innerHTML = html;

        /* ── 事件绑定 ── */
        this.paginationEl.querySelectorAll('.pagination-btn:not(.disabled)').forEach(btn => {
            const p = parseInt(btn.dataset.page);
            if (!isNaN(p)) btn.addEventListener('click', () => this._goToPage(p));
        });

        const sizeSelect = this.paginationEl.querySelector('#cpg-size-select');
        if (sizeSelect) {
            sizeSelect.addEventListener('change', () => {
                this.pageSize = parseInt(sizeSelect.value);
                this.currentPage = 1;
                this.render();
            });
        }

        const jumpInput = this.paginationEl.querySelector('#cpg-jump-input');
        const jumpBtn = this.paginationEl.querySelector('#cpg-jump-btn');
        if (jumpBtn && jumpInput) {
            jumpBtn.addEventListener('click', () => this._goToPage(parseInt(jumpInput.value)));
            jumpInput.addEventListener('keypress', e => { if (e.key === 'Enter') jumpBtn.click(); });
        }
    }
}
