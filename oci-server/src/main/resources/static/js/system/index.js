let csrfToken, csrfHeaderName;

// 自动跳转相关变量
let countdownTimer = null;
let countdownSeconds = 60;
let autoRedirectEnabled = true;

const i18n = window.I18N;

// 页面加载时获取数据
document.addEventListener('DOMContentLoaded', function() {
    // 先计算项目发布天数
    calculateProjectDays();
    // 然后加载其他数据
    loadDashboardData();
    // 启动倒计时
    startCountdown();
});

// 启动倒计时
function startCountdown() {
    if (!autoRedirectEnabled) return;

    updateCountdownDisplay();

    countdownTimer = setInterval(function() {
        countdownSeconds--;
        updateCountdownDisplay();

        if (countdownSeconds <= 0) {
            goToTenants();
        }
    }, 1000);
}

// 更新倒计时显示（含环形进度）
function updateCountdownDisplay() {
    const countdownText = document.getElementById('countdown-text');
    if (countdownText) {
        if (autoRedirectEnabled) {
            countdownText.textContent = countdownSeconds;
        } else {
            countdownText.textContent = '—';
        }
    }
    // 更新 SVG 环进度
    const ring = document.getElementById('ring-progress');
    if (ring) {
        const total = 60;
        const circumference = 113; // 2π×18
        const offset = circumference * (1 - countdownSeconds / total);
        ring.style.strokeDashoffset = Math.max(0, offset);
    }
}

// 取消自动跳转
function cancelAutoRedirect() {
    autoRedirectEnabled = false;
    if (countdownTimer) {
        clearInterval(countdownTimer);
        countdownTimer = null;
    }

    updateCountdownDisplay();

    // 更新按钮状态
    const stayBtn = document.getElementById('stay-btn');
    if (stayBtn) {
        stayBtn.classList.add('disabled');
        stayBtn.innerHTML = '<i class="fas fa-check"></i><span>'+i18n.index_already_stopStep+'</span>';
    }
}

// 跳转到租户页面
function goToTenants() {
    // 清除倒计时
    if (countdownTimer) {
        clearInterval(countdownTimer);
    }

    // 添加跳转动画效果
    document.body.style.opacity = '0.8';
    document.body.style.transition = 'opacity 0.3s ease';

    setTimeout(function() {
        window.location.href = '/main?path=/boot/dashboard';
    }, 300);
}

// 计算项目发布天数
function calculateProjectDays() {
    const releaseDate = new Date('2024-10-01'); // 项目首次发布日期
    const today = new Date();
    const timeDiff = today.getTime() - releaseDate.getTime();
    const daysDiff = Math.floor(timeDiff / (1000 * 3600 * 24));

    // 添加动画效果
    animateValue(document.getElementById('project-days'), 0, daysDiff, 1000);
}

// 加载仪表板数据
function loadDashboardData() {
    // 获取CSRF Token
    const csrfToken = getCSRFToken();
    const csrfHeader = getCSRFHeader();

    const headers = {
        'Content-Type': 'application/json'
    };
    if (csrfToken) {
        headers[csrfHeader] = csrfToken;
    };

    fetch('/bootOpenCount', {
        method: 'GET',
        headers: headers
    })
        .then(response => response.json())
        .then(res => {
            if (res.success && res.data !== undefined) {
                const bootElement = document.getElementById('total-boot-count');
                if (bootElement) {
                    animateNumber(bootElement, 0, res.data + 2000, 1500, true);
                }
            }
        })
        .catch(error => {
            console.error('获取开机统计失败:', error);
            const bootElement = document.getElementById('total-boot-count');
            if (bootElement) bootElement.textContent = '获取失败';
        });

    // 获取统计数据
    fetch('/api/dashboard/stats', {
        method: 'GET',
        headers: headers
    })
        .then(response => response.json())
        .then(data => {
            // 更新安装次数 - 添加动画效果
           /* if (data.installCount !== undefined) {
                const installElement = document.getElementById('install-count');
                const currentValue = parseInt(installElement.textContent) || 0;
                animateNumber(installElement, currentValue, data.installCount, 1500, true);
            }*/

            // 更新GitHub Stars - 添加动画效果
            if (data.githubStars !== undefined) {
                const starsElement = document.getElementById('github-stars');
                const currentValue = parseInt(starsElement.textContent) || 0;
                animateNumber(starsElement, currentValue, data.githubStars, 1200, true);
            }
        })
        .catch(error => {
            console.error('获取统计数据失败:', error);
            document.getElementById('install-count').textContent = '获取失败';
            document.getElementById('github-stars').textContent = '获取失败';
        });

    // 获取版本信息
    fetch('/api/version/check', {
        method: 'GET',
        headers: headers
    })
        .then(response => response.json())
        .then(data => {
            // 更新当前版本
            if (data.currentVersion) {
                document.getElementById('current-version').textContent = data.currentVersion;
            }

            // 更新最新版本
            if (data.latestVersion) {
                document.getElementById('latest-version').textContent = data.latestVersion;
            }

            // 更新发布日期
            if (data.releaseDate) {
                document.getElementById('release-date').textContent = data.releaseDate;
            }

            // 更新版本状态
            const statusElement = document.getElementById('version-status');
            const versionBadge = document.querySelector('.version-badge');

            if (data.needUpdate) {
                statusElement.textContent = i18n.index_newVersion_use;
                statusElement.style.color = 'var(--warning-color)';
                versionBadge.innerHTML = '<i class="fas fa-exclamation-circle"></i>'+i18n.index_newVersion_change;
                versionBadge.style.background = 'linear-gradient(45deg, var(--warning-color), #e17055)';
            } else {
                statusElement.textContent = i18n.index_already_newVersion;
                statusElement.style.color = 'var(--success-color)';
                versionBadge.innerHTML = '<i class="fas fa-check-circle"></i>'+i18n.index_newVersion;
            }
        })
        .catch(error => {
            console.error('获取版本信息失败:', error);
            document.getElementById('current-version').textContent = '获取失败';
            document.getElementById('latest-version').textContent = '获取失败';
            document.getElementById('release-date').textContent = '获取失败';
            document.getElementById('version-status').textContent = '检查失败';
        });
}

// 获取CSRF Token
function getCSRFToken() {
    const csrfTokenMeta = document.querySelector('meta[name="_csrf"]');
    return csrfTokenMeta ? csrfTokenMeta.getAttribute('content') : '';
}

// 获取CSRF Header
function getCSRFHeader() {
    const csrfHeaderMeta = document.querySelector('meta[name="_csrf_header"]');
    return csrfHeaderMeta ? csrfHeaderMeta.getAttribute('content') : 'X-CSRF-TOKEN';
}

// 格式化数字显示
function formatNumber(num) {
    if (num >= 1000000) {
        return (num / 1000000).toFixed(1) + 'M';
    } else if (num >= 1000) {
        return (num / 1000).toFixed(1) + 'K';
    }
    return num.toString();
}

// 添加数字动画效果
function animateNumber(element, start, end, duration, shouldFormat = false) {
    const range = end - start;
    const startTime = performance.now();

    function updateValue(currentTime) {
        const elapsed = currentTime - startTime;
        const progress = Math.min(elapsed / duration, 1);

        // 使用缓动函数让动画更自然
        const easeOutQuart = 1 - Math.pow(1 - progress, 4);
        const current = start + (range * easeOutQuart);

        if (shouldFormat) {
            element.textContent = formatNumber(Math.floor(current));
        } else {
            element.textContent = Math.floor(current);
        }

        if (progress < 1) {
            requestAnimationFrame(updateValue);
        } else {
            // 确保最终值准确
            if (shouldFormat) {
                element.textContent = formatNumber(end);
            } else {
                element.textContent = end;
            }
        }
    }

    requestAnimationFrame(updateValue);
}

// 简单的数字动画（用于项目天数）
function animateValue(element, start, end, duration) {
    animateNumber(element, start, end, duration, false);
}

// ESC键快速跳转
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        goToTenants();
    }
});
