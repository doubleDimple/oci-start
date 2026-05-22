
document.addEventListener('DOMContentLoaded', function() {
    // 1. 处理密码显示/隐藏
    document.querySelectorAll('.password-field').forEach(element => {
        element.addEventListener('click', function() {
            const password = this.getAttribute('data-password');
            if (this.textContent === '********') {
                this.textContent = password;
            } else {
                this.textContent = '********';
            }
        });
    });

    // 2. 处理可截断文本的展开/收起
    document.querySelectorAll('.truncate:not(.password-field)').forEach(element => {
        const fullText = element.getAttribute('data-fulltext');
        if (fullText && fullText.length > 15) {
            element.textContent = fullText.substring(0, 15) + '...';
        }

        element.addEventListener('click', function() {
            const fullText = this.getAttribute('data-fulltext');
            const isExpanded = this.getAttribute('data-expanded') === 'true';

            if (isExpanded) {
                this.textContent = fullText.length > 15 ?
                    fullText.substring(0, 15) + '...' : fullText;
                this.setAttribute('data-expanded', 'false');
            } else {
                this.textContent = fullText;
                this.setAttribute('data-expanded', 'true');
            }
        });
    });

    // 3. IP地址复制功能
    document.querySelectorAll('td:nth-child(10) .truncate').forEach(cell => {
        const ip = cell.getAttribute('data-fulltext');
        if (ip && ip !== 'null' && ip !== '') {
            cell.style.cursor = 'pointer';
            cell.setAttribute('title', '点击复制IP地址');
            cell.addEventListener('click', (e) => {
                e.stopPropagation();
                navigator.clipboard.writeText(ip).then(() => {
                    showToast('IP地址已复制到剪贴板');
                }).catch(() => {
                    showToast('复制失败，请手动复制');
                });
            });
        }
    });

    // 4. 表单提交处理
    document.querySelectorAll('form').forEach(form => {
        form.addEventListener('submit', function(e) {
            const button = this.querySelector('button');
            if (button && !button.disabled) {
                if (button.classList.contains('btn-danger')) {
                    if (!confirm('确定要删除此实例吗？此操作不可恢复。')) {
                        e.preventDefault();
                        return;
                    }
                }

                button.disabled = true;
                const icon = button.querySelector('i');
                const originalClass = icon.className;
                icon.className = 'fas fa-spinner fa-spin';

                setTimeout(() => {
                    button.disabled = false;
                    icon.className = originalClass;
                }, 30000);
            }
        });
    });

    // 5. Toast提示功能
    function showToast(message, duration = 3000) {
        const existingToast = document.querySelector('.toast');
        if (existingToast) {
            existingToast.remove();
        }

        const toast = document.createElement('div');
        toast.className = 'toast';
        toast.textContent = message;
        document.body.appendChild(toast);

        setTimeout(() => {
            toast.style.opacity = '0';
            setTimeout(() => {
                document.body.removeChild(toast);
            }, 300);
        }, duration);
    }

    // 6. 按钮状态管理
    function updateButtonStates() {
        document.querySelectorAll('tr').forEach(row => {
            const statusBadge = row.querySelector('.status-badge');
            if (statusBadge) {
                const startButton = row.querySelector('.btn-primary');
                const stopButton = row.querySelector('.btn-warning');

                if (startButton && stopButton) {
                    // 获取实例状态
                    const isOffline = statusBadge.textContent.trim() === '未开机';
                    const isStarting = statusBadge.textContent.trim() === '开机中';

                    // 只有在未开机状态才能启动
                    startButton.disabled = !isOffline;

                    // 只有在开机中状态才能停止
                    stopButton.disabled = !isStarting;

                    // 更新按钮的title提示
                    startButton.title = isOffline ? '开始抢机' : '只能在未开机状态下启动';
                    stopButton.title = isStarting ? '停止抢机' : '只能在开机中状态下停止';
                }
            }
        });
    }

    // 初始化按钮状态
    updateButtonStates();
});

document.addEventListener('DOMContentLoaded', function() {
    // 获取所有父级菜单
    const navParents = document.querySelectorAll('.nav-parent');

    // 为每个父级菜单添加点击事件
    navParents.forEach(parent => {
        const parentLink = parent.querySelector('.nav-link');
        parentLink.addEventListener('click', (e) => {
            e.preventDefault();
            // 切换当前菜单的展开状态
            parent.classList.toggle('expanded');
        });
    });

    // 找到当前活动的子菜单项，并展开其父级菜单
    const activeLink = document.querySelector('.nav-link.active');
    if (activeLink) {
        const parent = activeLink.closest('.nav-parent');
        if (parent) {
            parent.classList.add('expanded');
        }
    }
});