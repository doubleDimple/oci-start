// ================================
// 通用加载动画模块
// ================================
let loadingStartTimeNow = 0;

function showLoading(text = '正在加载中...') {
    loadingStartTimeNow = Date.now();

    // 如果已经存在，不重复创建
    if (document.querySelector('.loading-overlay')) return;

    const overlay = document.createElement('div');
    overlay.className = 'loading-overlay';
    overlay.innerHTML = `
        <div class="loading-container">
            <div class="loading-spinner"></div>
            <div class="loading-text">${text}</div>
        </div>
    `;
    document.body.appendChild(overlay);
}

function hideLoading() {
    const overlay = document.querySelector('.loading-overlay');
    if (!overlay) return;

    const elapsed = Date.now() - loadingStartTimeNow;
    const minDisplay = 600; // 控制最小显示时间防止闪烁

    const delay = elapsed < minDisplay ? minDisplay - elapsed : 0;
    setTimeout(() => overlay.remove(), delay);
}
