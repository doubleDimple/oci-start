<#macro pagination url page size totalPages totalElements
        textShow textItem textPrev textNext textJump textPage textTotal>
    <div class="pagination-container">
        <div class="pagination-wrapper">
            <div class="page-size-selector">
                <span class="page-size-label">${textShow}</span>
                <!-- Hidden input keeps pageSizeSelect value for gotoPage() JS -->
                <input type="hidden" id="pageSizeSelect" value="${size}">
                <div class="page-size-dropdown" id="pageSizeDropdown">
                    <button class="page-size-btn" onclick="togglePageSizeDropdown(event)" type="button">
                        <span id="pageSizeBtnLabel">${size}</span>
                        <i class="fas fa-chevron-down page-size-arrow" id="pageSizeArrow"></i>
                    </button>
                    <div class="page-size-panel" id="pageSizePanel" style="display:none;">
                        <#list [10,20,30] as item>
                            <button type="button" class="page-size-item <#if size == item>active</#if>"
                                    onclick="selectPageSize(${item}, '${url}', ${page})">${item}</button>
                        </#list>
                    </div>
                </div>
                <#--<span class="page-size-label">${textItem}</span>-->
            </div>

            <div class="pagination-nav">
                <button type="button" onclick="gotoPage(${page-1}, '${url}')"
                        class="pagination-btn nav-btn prev-btn <#if page lte 0>disabled</#if>"
                        <#if page lte 0>disabled</#if> aria-label="${textPrev}">
                    <i class="fas fa-chevron-left"></i>
                    <span class="btn-text">${textPrev}</span>
                </button>

                <div class="page-numbers">
                    <#if totalPages lte 7>
                        <#list 0..totalPages-1 as i>
                            <button type="button" onclick="gotoPage(${i}, '${url}')"
                                    class="pagination-btn page-btn <#if page == i>active</#if>">
                                ${i + 1}
                            </button>
                        </#list>
                    <#else>
                        <#if page gt 2>
                            <button type="button" onclick="gotoPage(0, '${url}')"
                                    class="pagination-btn page-btn <#if page == 0>active</#if>">1</button>
                            <#if page gt 3>
                                <span class="pagination-ellipsis"><i class="fas fa-ellipsis-h"></i></span>
                            </#if>
                        </#if>

                        <#assign startPage = (page - 2 lt 0)?then(0, page - 2)>
                        <#assign endPage = (page + 2 gte totalPages)?then(totalPages - 1, page + 2)>

                        <#list startPage..endPage as i>
                            <button type="button" onclick="gotoPage(${i}, '${url}')"
                                    class="pagination-btn page-btn <#if page == i>active</#if>">
                                ${i + 1}
                            </button>
                        </#list>

                        <#if page lt totalPages - 3>
                            <#if page lt totalPages - 4>
                                <span class="pagination-ellipsis"><i class="fas fa-ellipsis-h"></i></span>
                            </#if>
                            <button type="button" onclick="gotoPage(${totalPages-1}, '${url}')"
                                    class="pagination-btn page-btn <#if page == totalPages-1>active</#if>">
                                ${totalPages}
                            </button>
                        </#if>
                    </#if>
                </div>

                <button type="button" onclick="gotoPage(${(page + 1)}, '${url}')"
                        class="pagination-btn nav-btn next-btn <#if page gte (totalPages - 1)>disabled</#if>"
                        <#if page gte (totalPages - 1)>disabled</#if> aria-label="${textNext}">
                    <span class="btn-text">${textNext}</span>
                    <i class="fas fa-chevron-right"></i>
                </button>
            </div>

            <div class="pagination-info">
                <div class="page-jump">
                    <span class="jump-label">${textJump}</span>
                    <input type="number" id="jumpPageInput"
                           class="jump-input"
                           placeholder="${page + 1}"
                           min="1" max="${totalPages}"
                           onkeypress="handleJumpKeyPress(event, '${url}')">
                    <span class="jump-label">${textPage}</span>
                    <button type="button" onclick="jumpToPage('${url}')" class="jump-btn">
                        <i class="fas fa-arrow-right"></i>
                    </button>
                </div>

                <div class="total-info">
                    <span class="total-text">${textTotal} <strong>${totalElements}</strong> ${msg.get("page.ele")!"条"}</span>
                    <span class="page-info">${msg.get("detail.to")!"第"} <strong>${page + 1}</strong> / <strong>${totalPages}</strong> ${textPage}</span>
                </div>
            </div>
        </div>
    </div>

    <style>
        .pagination-container {
            margin: 20px 0;
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
            user-select: none;
        }

        .pagination-wrapper {
            display: flex;
            justify-content: space-between;
            align-items: center;
            gap: 24px;
            padding: 16px 20px;
            background: #ffffff;
            border: 1px solid #e5e7eb;
            border-radius: 12px;
            box-shadow: 0 1px 3px rgba(0, 0, 0, 0.05);
            flex-wrap: wrap;
        }

        /* 每页显示数量选择器 */
        .page-size-selector {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 14px;
            color: #6b7280;
            white-space: nowrap;
        }

        .page-size-label {
            font-weight: 500;
        }

        /* ── Custom page-size dropdown ── */
        .page-size-dropdown {
            position: relative;
            display: inline-block;
        }

        .page-size-btn {
            display: inline-flex;
            align-items: center;
            gap: 6px;
            padding: 8px 12px;
            background: #f9fafb;
            border: 1px solid #d1d5db;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 500;
            color: #374151;
            cursor: pointer;
            transition: all 0.2s ease;
            min-width: 70px;
        }

        .page-size-btn:hover {
            border-color: #1abc9c;
            background: #ffffff;
        }

        .page-size-btn.open {
            border-color: #1abc9c;
            box-shadow: 0 0 0 3px rgba(26, 188, 156, 0.1);
        }

        .page-size-arrow {
            font-size: 11px;
            color: #9ca3af;
            transition: transform 0.15s, color 0.2s;
            margin-left: auto;
        }

        .page-size-btn.open .page-size-arrow,
        .page-size-btn:hover .page-size-arrow {
            color: #1abc9c;
        }

        .page-size-btn.open .page-size-arrow { transform: rotate(180deg); }

        .page-size-panel {
            position: absolute;
            top: calc(100% + 4px);
            left: 0;
            min-width: 100%;
            background: #ffffff;
            border: 1px solid #d1d5db;
            border-radius: 8px;
            box-shadow: 0 8px 20px rgba(0,0,0,0.1);
            z-index: 3000;
            overflow: hidden;
        }

        .page-size-item {
            display: block;
            width: 100%;
            padding: 8px 14px;
            background: none;
            border: none;
            text-align: left;
            font-size: 14px;
            font-weight: 500;
            color: #374151;
            cursor: pointer;
            transition: background 0.12s, color 0.12s;
        }

        .page-size-item:hover { background: #f1f5f9; color: #1abc9c; }
        .page-size-item.active { color: #1abc9c; font-weight: 600; }

        /* 分页导航 */
        .pagination-nav {
            display: flex;
            align-items: center;
            gap: 4px;
        }

        .page-numbers {
            display: flex;
            align-items: center;
            gap: 2px;
            margin: 0 8px;
        }

        /* 分页按钮基础样式 */
        .pagination-btn {
            border: none;
            background: none;
            cursor: pointer;
            transition: all 0.2s ease;
            font-family: inherit;
            text-decoration: none;
            outline: none;
            user-select: none;
        }

        /* 导航按钮 (上一页/下一页) */
        .nav-btn {
            display: flex;
            align-items: center;
            gap: 6px;
            padding: 10px 14px;
            background: #f8fafc;
            border: 1px solid #e2e8f0;
            border-radius: 8px;
            color: #64748b;
            font-size: 14px;
            font-weight: 500;
        }

        .nav-btn:hover:not(.disabled) {
            background: #1abc9c;
            border-color: #1abc9c;
            color: white;
            transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(26, 188, 156, 0.3);
        }

        .nav-btn.disabled {
            opacity: 0.4;
            cursor: not-allowed;
            background: #f1f5f9;
            color: #94a3b8;
        }

        .nav-btn .btn-text {
            font-weight: 500;
        }

        /* 页码按钮 */
        .page-btn {
            min-width: 40px;
            height: 40px;
            display: flex;
            align-items: center;
            justify-content: center;
            border-radius: 8px;
            font-size: 14px;
            font-weight: 500;
            color: #64748b;
            background: transparent;
            position: relative;
        }

        .page-btn:hover:not(.active) {
            background: #f1f5f9;
            color: #374151;
            transform: translateY(-1px);
        }

        .page-btn.active {
            background: linear-gradient(135deg, #1abc9c 0%, #16a085 100%);
            color: white;
            box-shadow: 0 4px 12px rgba(26, 188, 156, 0.4);
            transform: translateY(-1px);
        }

        .page-btn.active::before {
            content: '';
            position: absolute;
            inset: -2px;
            background: linear-gradient(135deg, #1abc9c, #16a085);
            border-radius: 10px;
            z-index: -1;
            opacity: 0.2;
        }

        /* 省略号 */
        .pagination-ellipsis {
            display: flex;
            align-items: center;
            justify-content: center;
            width: 40px;
            height: 40px;
            color: #9ca3af;
            font-size: 12px;
        }

        /* 分页信息区域 */
        .pagination-info {
            display: flex;
            align-items: center;
            gap: 20px;
            flex-wrap: wrap;
        }

        /* 跳转页码 */
        .page-jump {
            display: flex;
            align-items: center;
            gap: 8px;
            font-size: 14px;
            color: #6b7280;
        }

        .jump-label {
            font-weight: 500;
            white-space: nowrap;
        }

        .jump-input {
            width: 60px;
            padding: 8px 12px;
            border: 1px solid #d1d5db;
            border-radius: 8px;
            background: #f9fafb;
            text-align: center;
            font-size: 14px;
            font-weight: 500;
            color: #374151;
            transition: all 0.2s ease;
        }

        .jump-input:focus {
            outline: none;
            border-color: #1abc9c;
            background: white;
            box-shadow: 0 0 0 3px rgba(26, 188, 156, 0.1);
        }

        .jump-input::placeholder {
            color: #9ca3af;
        }

        .jump-btn {
            width: 32px;
            height: 32px;
            display: flex;
            align-items: center;
            justify-content: center;
            background: linear-gradient(135deg, #1abc9c 0%, #16a085 100%);
            border: none;
            border-radius: 8px;
            color: white;
            cursor: pointer;
            transition: all 0.2s ease;
            font-size: 12px;
        }

        .jump-btn:hover {
            transform: translateY(-1px);
            box-shadow: 0 4px 12px rgba(26, 188, 156, 0.4);
        }

        .jump-btn:active {
            transform: translateY(0);
        }

        /* 总数信息 */
        .total-info {
            display: flex;
            align-items: center;
            gap: 12px;
            font-size: 14px;
            color: #6b7280;
        }

        .info-item {
            display: flex;
            align-items: center;
            gap: 4px;
            white-space: nowrap;
        }

        .info-label {
            color: #6b7280;
            font-weight: 400;
        }

        .info-value {
            color: #1abc9c;
            font-weight: 600;
            font-size: 15px;
            min-width: 20px;
            text-align: center;
        }

        .info-divider {
            color: #d1d5db;
            font-weight: 300;
            margin: 0 4px;
        }

        /* 响应式设计 */
        @media (max-width: 1024px) {
            .pagination-wrapper {
                gap: 16px;
            }

            .pagination-info {
                gap: 16px;
            }
        }

        @media (max-width: 768px) {
            .pagination-wrapper {
                flex-direction: column;
                align-items: stretch;
                gap: 16px;
                padding: 16px;
            }

            .page-size-selector {
                justify-content: center;
            }

            .pagination-nav {
                justify-content: center;
                flex-wrap: wrap;
                gap: 8px;
            }

            .page-numbers {
                order: 2;
                margin: 8px 0;
            }

            .prev-btn {
                order: 1;
            }

            .next-btn {
                order: 3;
            }

            .pagination-info {
                flex-direction: column;
                align-items: center;
                gap: 12px;
            }

            .total-info {
                text-align: center;
            }

            /* 移动端隐藏按钮文字 */
            .nav-btn .btn-text {
                display: none;
            }

            .nav-btn {
                min-width: 44px;
                padding: 12px;
            }
        }

        @media (max-width: 480px) {
            .page-btn {
                min-width: 36px;
                height: 36px;
                font-size: 13px;
            }

            .pagination-ellipsis {
                width: 36px;
                height: 36px;
            }

            .page-numbers {
                gap: 1px;
            }
        }

        /* 深色模式适配（与站点 data-theme 同步） */
        [data-theme="dark"] .pagination-wrapper {
            background: #22262b;
            border-color: #31363d;
            color: #cdd9e5;
        }

        [data-theme="dark"] .page-size-label,
        [data-theme="dark"] .page-size-selector {
            color: #768390;
        }

        [data-theme="dark"] .page-size-btn {
            background: #292d32;
            border-color: #31363d;
            color: #cdd9e5;
        }

        [data-theme="dark"] .page-size-btn:hover,
        [data-theme="dark"] .page-size-btn.open {
            background: #31363d;
            border-color: #4d9eff;
        }

        [data-theme="dark"] .page-size-arrow { color: #768390; }

        [data-theme="dark"] .page-size-panel {
            background: #1f2229;
            border-color: #31363d;
            box-shadow: 0 8px 20px rgba(0,0,0,0.4);
        }

        [data-theme="dark"] .page-size-item { color: #cdd9e5; }
        [data-theme="dark"] .page-size-item:hover { background: #252c36; color: #4d9eff; }
        [data-theme="dark"] .page-size-item.active { color: #4d9eff; }

        [data-theme="dark"] .nav-btn {
            background: #292d32;
            border-color: #31363d;
            color: #cdd9e5;
        }

        [data-theme="dark"] .nav-btn.disabled {
            background: #1e2227;
            color: #4a5568;
        }

        [data-theme="dark"] .page-btn { color: #cdd9e5; }

        [data-theme="dark"] .page-btn:hover:not(.active) {
            background: #292d32;
            color: #cdd9e5;
        }

        [data-theme="dark"] .pagination-ellipsis { color: #4a5568; }

        [data-theme="dark"] .jump-label,
        [data-theme="dark"] .page-jump { color: #768390; }

        [data-theme="dark"] .jump-input {
            background: #292d32;
            border-color: #31363d;
            color: #cdd9e5;
        }

        [data-theme="dark"] .jump-input:focus {
            background: #31363d;
            border-color: #4d9eff;
            box-shadow: 0 0 0 3px rgba(77,158,255,.12);
        }

        [data-theme="dark"] .jump-input::placeholder { color: #4a5568; }

        [data-theme="dark"] .total-info,
        [data-theme="dark"] .page-info { color: #768390; }

        [data-theme="dark"] .total-info strong,
        [data-theme="dark"] .page-info strong { color: #cdd9e5; }

        /* 添加微动画效果 */
        .pagination-btn {
            position: relative;
            overflow: hidden;
        }

        .pagination-btn::before {
            content: '';
            position: absolute;
            top: 50%;
            left: 50%;
            width: 0;
            height: 0;
            background: rgba(255, 255, 255, 0.2);
            border-radius: 50%;
            transform: translate(-50%, -50%);
            transition: width 0.3s ease, height 0.3s ease;
        }

        .pagination-btn:active::before {
            width: 100px;
            height: 100px;
        }
    </style>

    <script>
        const totalPages = ${totalPages};

        function togglePageSizeDropdown(event) {
            event.stopPropagation();
            var panel = document.getElementById('pageSizePanel');
            var btn = document.querySelector('.page-size-btn');
            var isOpen = panel.style.display !== 'none';
            panel.style.display = isOpen ? 'none' : 'block';
            if (btn) btn.classList.toggle('open', !isOpen);
        }

        function selectPageSize(newSize, url, currentPage) {
            var hidden = document.getElementById('pageSizeSelect');
            if (hidden) hidden.value = newSize;
            var panel = document.getElementById('pageSizePanel');
            var btn = document.querySelector('.page-size-btn');
            var label = document.getElementById('pageSizeBtnLabel');
            if (panel) panel.style.display = 'none';
            if (btn) btn.classList.remove('open');
            if (label) label.textContent = newSize;
            changePageSize(newSize, url, currentPage);
        }

        document.addEventListener('click', function() {
            var panel = document.getElementById('pageSizePanel');
            var btn = document.querySelector('.page-size-btn');
            if (panel) panel.style.display = 'none';
            if (btn) btn.classList.remove('open');
        });

        function gotoPage(targetPage, url) {
            const size = document.getElementById('pageSizeSelect').value;
            if (targetPage < 0 || targetPage >= totalPages) return;

            // 添加加载状态
            const buttons = document.querySelectorAll('.pagination-btn');
            buttons.forEach(btn => btn.style.pointerEvents = 'none');

            window.location.replace(url + '?page=' + targetPage + '&size=' + size);
        }

        function jumpToPage(url) {
            const input = document.getElementById('jumpPageInput');
            let targetPage = parseInt(input.value) - 1;
            const size = document.getElementById('pageSizeSelect').value;

            if (isNaN(targetPage) || targetPage < 0 || targetPage >= totalPages) {
                input.style.borderColor = '#ef4444';
                input.style.boxShadow = '0 0 0 3px rgba(239, 68, 68, 0.1)';
                setTimeout(() => {
                    input.style.borderColor = '#d1d5db';
                    input.style.boxShadow = 'none';
                }, 2000);
                return;
            }
            const jumpBtn = document.querySelector('.jump-btn');
            jumpBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i>';

            window.location.replace(url + '?page=' + targetPage + '&size=' + size);
        }

        function changePageSize(newSize, url, currentPage) {
            const newTotalPages = Math.ceil(${totalElements} / newSize);
            const newPage = Math.min(currentPage, newTotalPages - 1);

            window.location.replace(url + '?page=' + newPage + '&size=' + newSize);
        }

        function handleJumpKeyPress(event, url) {
            if (event.key === 'Enter') {
                jumpToPage(url);
            }
        }
        document.addEventListener('DOMContentLoaded', function() {
            const jumpInput = document.getElementById('jumpPageInput');
            if (jumpInput) {
                jumpInput.value = ${page + 1};
            }
        });
    </script>
</#macro>