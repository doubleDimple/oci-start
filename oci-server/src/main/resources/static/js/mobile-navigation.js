/**
 *
 * OCI-Start
 */
class EnhancedMobileNavigation {
    constructor() {
        this.currentCloudType = this.getCloudTypeFromUrl() || 1; // 从URL获取或默认Oracle
        this.currentTab = 'tenant';
        this.userDropdownOpen = false;
        this.isInitialized = false;

        this.cloudProviders = {
            1: {
                name: 'Oracle Cloud',
                icon: 'fab fa-oracle',
                iconColor: '#f80000', // 仅用于图标颜色
                menus: [
                    { id: 'tenant', icon: 'fas fa-server', text: '租户管理', url: '/tenants/list' },
                    { id: 'instance', icon: 'fas fa-desktop', text: '实例管理', url: '/oci/list' },
                    { id: 'grabbing', icon: 'fas fa-bolt', text: '抢机管理', url: '/boot/fullBootList' }
                ]
            }
            /*,
            2: {
                name: 'Google Cloud',
                icon: 'fab fa-google',
                iconColor: '#4285f4',
                menus: [
                    { id: 'project', icon: 'fas fa-server', text: '项目管理', url: '/gcp/projects' },
                    { id: 'compute', icon: 'fas fa-desktop', text: '计算引擎', url: '/gcp/compute' },
                    { id: 'storage', icon: 'fas fa-database', text: '存储管理', url: '/gcp/storage' }
                ]
            },
            3: {
                name: 'Microsoft Azure',
                icon: 'fab fa-microsoft',
                iconColor: '#0078d4',
                menus: [
                    { id: 'subscription', icon: 'fas fa-server', text: '订阅管理', url: '/azure/subscriptions' },
                    { id: 'vm', icon: 'fas fa-desktop', text: '虚拟机', url: '/azure/vm' },
                    { id: 'resource', icon: 'fas fa-layer-group', text: '资源组', url: '/azure/resources' }
                ]
            },
            4: {
                name: 'AWS',
                icon: 'fab fa-aws',
                iconColor: '#ff9900',
                menus: [
                    { id: 'account', icon: 'fas fa-server', text: '账户管理', url: '/aws/accounts' },
                    { id: 'ec2', icon: 'fas fa-desktop', text: 'EC2实例', url: '/aws/ec2' },
                    { id: 's3', icon: 'fas fa-database', text: 'S3存储', url: '/aws/s3' }
                ]
            }*/
        };

        this.init();
    }

    // 初始化
    init() {
        if (this.isInitialized) return;

        this.renderNavigationHTML();
        this.attachEventListeners();
        this.detectCurrentPage();
        this.updateTheme();
        this.isInitialized = true;

        console.log('Enhanced Mobile Navigation initialized');
    }

    // 获取云厂商Logo
    getCloudProviderLogo(type) {
        const logoMap = {
            1: '<img src="/images/oracle.png" alt="Oracle" style="width: 100%; height: 100%; object-fit: contain;">',
            2: '<img src="/images/google.png" alt="Google" style="width: 100%; height: 100%; object-fit: contain;">',
            3: '<img src="/images/azure.png" alt="Azure" style="width: 100%; height: 100%; object-fit: contain;">',
            4: '<img src="/images/aws.png" alt="AWS" style="width: 100%; height: 100%; object-fit: contain;">'
        };

        // 如果图片不存在，降级到图标
        return logoMap[type] || '<i class="' + this.cloudProviders[type].icon + '" style="color: ' + this.cloudProviders[type].iconColor + ';"></i>';
    }
    getCloudTypeFromUrl() {
        const urlParams = new URLSearchParams(window.location.search);
        const cloudType = parseInt(urlParams.get('cloudType'));
        return isNaN(cloudType) ? null : cloudType;
    }

    // 渲染导航HTML
    renderNavigationHTML() {
        // 检查是否已存在导航栏，避免重复渲染
        if (document.getElementById('enhancedTopNav')) return;

        const showBack = this.shouldShowBackButton();

        // 渲染顶部导航栏
        const topNavHTML = `
            <!-- 增强版顶部导航栏 -->
            <div class="enhanced-top-nav" id="enhancedTopNav">
                <div class="enhanced-top-nav-content">
                    <!-- 左侧 -->
                    <div class="enhanced-nav-left">
                        ${showBack ? `
                            <button class="enhanced-back-btn" id="enhancedBackBtn">
                                <i class="fas fa-arrow-left"></i>
                            </button>
                        ` : ''}
                        <div class="enhanced-cloud-switcher" id="enhancedCloudSwitcher">
                            ${Object.entries(this.cloudProviders).map(([type, provider]) => `
                                <div class="enhanced-cloud-btn ${type == this.currentCloudType ? 'active' : ''}" 
                                     data-type="${type}" data-name="${provider.name}" title="${provider.name}">
                                    <div class="enhanced-cloud-logo">
                                        ${this.getCloudProviderLogo(type)}
                                    </div>
                                </div>
                            `).join('')}
                        </div>
                    </div>

                   

                    <!-- 右侧：操作按钮和用户菜单 -->
                    <div class="enhanced-nav-right">
                        <button class="enhanced-top-action-btn" id="enhancedRefreshBtn" title="刷新">
                            <i class="fas fa-sync-alt"></i>
                        </button>
                        <button class="enhanced-top-action-btn" id="enhancedNotificationBtn" title="通知">
                            <i class="fas fa-bell"></i>
                        </button>
                        <div class="enhanced-user-menu">
                            <div class="enhanced-user-avatar" id="enhancedUserAvatar">
                                <i class="fas fa-user"></i>
                            </div>
                            <div class="enhanced-user-dropdown" id="enhancedUserDropdown">
                                <!--<button class="enhanced-dropdown-item" data-action="profile">
                                    <i class="fas fa-user-circle"></i>
                                    个人资料
                                </button>
                                <button class="enhanced-dropdown-item" data-action="settings">
                                    <i class="fas fa-cog"></i>
                                    系统设置
                                </button>
                                <button class="enhanced-dropdown-item" data-action="darkmode">
                                    <i class="fas fa-moon"></i>
                                    深色模式
                                </button>
                                <div class="enhanced-dropdown-divider"></div>
                                <button class="enhanced-dropdown-item" data-action="help">
                                    <i class="fas fa-question-circle"></i>
                                    帮助中心
                                </button>
                                <button class="enhanced-dropdown-item" data-action="about">
                                    <i class="fas fa-info-circle"></i>
                                    关于我们
                                </button>-->
                                <div class="enhanced-dropdown-divider"></div>
                                <button class="enhanced-dropdown-item danger" data-action="logout">
                                    <i class="fas fa-sign-out-alt"></i>
                                    退出登录
                                </button>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        `;

        // 插入到页面顶部
        document.body.insertAdjacentHTML('afterbegin', topNavHTML);

        // 渲染底部导航栏（替换现有的或创建新的）
        this.renderBottomNav();

        // 添加加载遮罩
        if (!document.getElementById('enhancedLoadingOverlay')) {
            const loadingHTML = `
                <div class="enhanced-loading-overlay" id="enhancedLoadingOverlay">
                    <div class="enhanced-loading-spinner"></div>
                </div>
            `;
            document.body.insertAdjacentHTML('beforeend', loadingHTML);
        }

        // 调整现有主内容区域的padding
        this.adjustMainContent();
    }

    // 判断是否显示返回按钮
    shouldShowBackButton() {
        const path = window.location.pathname;
        const mainPages = ['/tenants/list', '/oci/list', '/boot/fullBootList'];
        return !mainPages.some(page => path.includes(page));
    }

    // 获取页面标题
    getPageTitle() {
        const path = window.location.pathname;

        if (path.includes('/tenants/list')) return '租户管理';
        if (path.includes('/tenants/regionList')) return '租户详情';
        if (path.includes('/oci/list')) return '实例管理';
        if (path.includes('/boot/fullBootList')) return '抢机管理';

        // 默认根据云厂商显示
        return this.cloudProviders[this.currentCloudType]?.name || '管理控制台';
    }

    // 渲染底部导航
    renderBottomNav() {
        const menus = this.cloudProviders[this.currentCloudType].menus;
        let bottomNav = document.getElementById('bottomNav') || document.getElementById('enhancedBottomNav');

        // 如果没有底部导航，创建一个
        if (!bottomNav) {
            bottomNav = document.createElement('div');
            bottomNav.id = 'enhancedBottomNav';
            bottomNav.className = 'enhanced-bottom-nav';
            document.body.appendChild(bottomNav);
        } else {
            // 更新现有底部导航的类名
            bottomNav.className = 'enhanced-bottom-nav';
        }

        bottomNav.innerHTML = menus.map(menu => `
            <div class="enhanced-nav-item ${menu.id === this.currentTab ? 'active' : ''}" 
                 data-tab="${menu.id}" data-url="${menu.url}">
                <div class="enhanced-nav-icon">
                    <i class="${menu.icon}"></i>
                </div>
                <div class="enhanced-nav-text">${menu.text}</div>
            </div>
        `).join('');

        // 绑定底部导航点击事件
        bottomNav.querySelectorAll('.enhanced-nav-item').forEach(item => {
            item.addEventListener('click', (e) => {
                const tab = e.currentTarget.dataset.tab;
                const url = e.currentTarget.dataset.url;
                this.handleTabClick(tab, url);
            });
        });
    }

    // 调整主内容区域
    adjustMainContent() {
        // 获取所有可能的主内容区域
        const mainContentSelectors = [
            '.main-content',
            '.enhanced-main-content',
            'body > div:not(.enhanced-top-nav):not(.enhanced-bottom-nav):not(.enhanced-loading-overlay)'
        ];

        mainContentSelectors.forEach(selector => {
            const elements = document.querySelectorAll(selector);
            elements.forEach(element => {
                if (!element.classList.contains('enhanced-main-content')) {
                    element.classList.add('enhanced-main-content');
                }
            });
        });

        // 移除body的额外padding，避免双重间距
        document.body.style.paddingTop = '0';
    }

    // 绑定事件监听器
    attachEventListeners() {
        // 云厂商切换
        document.addEventListener('click', (e) => {
            const cloudBtn = e.target.closest('.enhanced-cloud-btn');
            if (cloudBtn) {
                const cloudType = parseInt(cloudBtn.dataset.type);
                this.switchCloudProvider(cloudType);
            }
        });

        // 返回按钮
        document.addEventListener('click', (e) => {
            if (e.target.closest('#enhancedBackBtn')) {
                this.goBack();
            }
        });

        // 用户菜单
        document.addEventListener('click', (e) => {
            if (e.target.closest('#enhancedUserAvatar')) {
                e.stopPropagation();
                this.toggleUserDropdown();
            } else if (!e.target.closest('#enhancedUserDropdown')) {
                this.closeUserDropdown();
            }
        });

        // 下拉菜单项
        document.addEventListener('click', (e) => {
            const dropdownItem = e.target.closest('.enhanced-dropdown-item');
            if (dropdownItem) {
                const action = dropdownItem.dataset.action;
                this.handleDropdownAction(action);
            }
        });

        // 刷新按钮
        document.addEventListener('click', (e) => {
            if (e.target.closest('#enhancedRefreshBtn')) {
                this.handleRefresh();
            }
        });

        // 通知按钮
        document.addEventListener('click', (e) => {
            if (e.target.closest('#enhancedNotificationBtn')) {
                this.showNotifications();
            }
        });

        // 阻止用户下拉菜单点击事件冒泡
        document.addEventListener('click', (e) => {
            const dropdown = e.target.closest('#enhancedUserDropdown');
            if (dropdown) {
                e.stopPropagation();
            }
        });
    }

    // 切换云厂商
    switchCloudProvider(cloudType) {
        if (cloudType === this.currentCloudType || !this.cloudProviders[cloudType]) return;

        this.showLoading();

        // 更新当前云厂商
        this.currentCloudType = cloudType;

        // 更新按钮状态
        document.querySelectorAll('.enhanced-cloud-btn').forEach(btn => {
            btn.classList.remove('active');
            if (parseInt(btn.dataset.type) === cloudType) {
                btn.classList.add('active');
            }
        });

        // 重新渲染底部导航
        this.renderBottomNav();

        // 更新主题
        this.updateTheme();

        // 模拟加载过程
        setTimeout(() => {
            this.hideLoading();
            this.showToast(`已切换到 ${this.cloudProviders[cloudType].name}`, 'success');

            // 跳转到对应云厂商的首页
            const firstMenu = this.cloudProviders[cloudType].menus[0];
            const url = new URL(firstMenu.url + '?mobile=true', window.location.origin);
            url.searchParams.set('cloudType', cloudType);
            window.location.href = url.toString();
        }, 1000);
    }

    // 更新主题 - 移除主题切换，保持统一配色
    updateTheme() {
        // 不再切换主题，保持统一的配色方案
        // 只需要重新渲染底部导航以显示不同的菜单
        console.log('当前云厂商:', this.cloudProviders[this.currentCloudType].name);
    }

    // 处理标签页点击
    handleTabClick(tab, url) {
        if (tab === this.currentTab) return;

        this.setCurrentTab(tab);

        // 短暂延迟后跳转
        setTimeout(() => {
            const targetUrl = new URL(url + '?mobile=true', window.location.origin);
            targetUrl.searchParams.set('cloudType', this.currentCloudType);
            window.location.href = targetUrl.toString();
        }, 150);
    }

    // 设置当前标签页
    setCurrentTab(tab) {
        this.currentTab = tab;
        document.querySelectorAll('.enhanced-nav-item, .nav-item').forEach(item => {
            item.classList.remove('active');
            if (item.dataset.tab === tab) {
                item.classList.add('active');
            }
        });
    }

    // 检测当前页面
    detectCurrentPage() {
        const path = window.location.pathname;

        if (path.includes('/tenants/')) {
            this.setCurrentTab('tenant');
        } else if (path.includes('/oci/') || path.includes('/compute/') || path.includes('/vm/') || path.includes('/ec2/')) {
            this.setCurrentTab('instance');
        } else if (path.includes('/boot/') || path.includes('/grabbing/')) {
            this.setCurrentTab('grabbing');
        } else if (path.includes('/gcp/projects') || path.includes('/azure/subscriptions') || path.includes('/aws/accounts')) {
            this.setCurrentTab('project');
        } else if (path.includes('/gcp/compute') || path.includes('/azure/vm') || path.includes('/aws/ec2')) {
            this.setCurrentTab('compute');
        } else if (path.includes('/gcp/storage') || path.includes('/azure/resource') || path.includes('/aws/s3')) {
            this.setCurrentTab('storage');
        }
    }

    // 返回上一页
    goBack() {
        if (window.history.length > 1) {
            window.history.back();
        } else {
            // 如果没有历史记录，跳转到首页
            const firstMenu = this.cloudProviders[this.currentCloudType].menus[0];
            const url = new URL(firstMenu.url + '?mobile=true', window.location.origin);
            url.searchParams.set('cloudType', this.currentCloudType);
            window.location.href = url.toString();
        }
    }

    // 用户菜单相关
    toggleUserDropdown() {
        const dropdown = document.getElementById('enhancedUserDropdown');
        this.userDropdownOpen = !this.userDropdownOpen;

        if (this.userDropdownOpen) {
            dropdown.classList.add('show');
        } else {
            dropdown.classList.remove('show');
        }
    }

    closeUserDropdown() {
        if (this.userDropdownOpen) {
            const dropdown = document.getElementById('enhancedUserDropdown');
            if (dropdown) {
                dropdown.classList.remove('show');
            }
            this.userDropdownOpen = false;
        }
    }

    // 下拉菜单操作处理
    handleDropdownAction(action) {
        switch(action) {
            case 'profile':
                this.showToast('个人资料功能开发中...', 'info');
                break;
            case 'settings':
                this.showToast('系统设置功能开发中...', 'info');
                break;
            case 'darkmode':
                this.toggleDarkMode();
                break;
            case 'help':
                this.showToast('帮助中心功能开发中...', 'info');
                break;
            case 'logout':
                this.handleLogout();
                break;
        }

        this.closeUserDropdown();
    }

    // 获取CSRF令牌的方法
    getCSRFToken() {
        // 优先从meta标签获取
        const metaCSRF = document.querySelector('meta[name="_csrf"]');
        if (metaCSRF) {
            return metaCSRF.getAttribute('content');
        }

        // 从隐藏的input获取
        const inputCSRF = document.querySelector('input[name="_csrf"]');
        if (inputCSRF) {
            return inputCSRF.value;
        }

        // 从页面中的任何表单获取
        const formCSRF = document.querySelector('form input[name="_csrf"]');
        if (formCSRF) {
            return formCSRF.value;
        }

        return null;
    }

    // 获取CSRF参数名的方法
    getCSRFParameterName() {
        // 从meta标签获取
        const metaCSRFName = document.querySelector('meta[name="_csrf_parameter"]');
        if (metaCSRFName) {
            return metaCSRFName.getAttribute('content');
        }

        // 默认参数名
        return '_csrf';
    }

    // 退出登录 - 根据PC端的实现修改
    handleLogout() {
        if (typeof Swal !== 'undefined') {
            Swal.fire({
                title: '确认退出',
                text: '确定要退出当前账户吗？',
                icon: 'question',
                showCancelButton: true,
                confirmButtonText: '确定退出',
                cancelButtonText: '取消',
                confirmButtonColor: '#dc3545',
                cancelButtonColor: '#6c757d'
            }).then((result) => {
                if (result.isConfirmed) {
                    this.executeLogout();
                }
            });
        } else {
            this.executeLogout();
        }

        this.closeUserDropdown();
    }

    // 执行退出登录操作
    executeLogout() {
        this.showLoading();

        // 获取CSRF令牌和参数名
        const csrfToken = this.getCSRFToken();
        const csrfParamName = this.getCSRFParameterName();

        if (csrfToken) {
            // 使用POST请求退出，参考PC端的实现
            const form = document.createElement('form');
            form.method = 'POST';
            form.action = '/perform_logout';
            form.style.display = 'none';

            // 添加CSRF token
            const csrfInput = document.createElement('input');
            csrfInput.type = 'hidden';
            csrfInput.name = csrfParamName;
            csrfInput.value = csrfToken;
            form.appendChild(csrfInput);

            // 提交表单
            document.body.appendChild(form);

            try {
                form.submit();
            } catch (error) {
                console.error('表单提交失败:', error);
                // 如果表单提交失败，尝试其他方式
                this.fallbackLogout();
            }
        } else {
            // 如果没有CSRF token，尝试其他退出方式
            console.warn('未找到CSRF token，尝试备用退出方式');
            this.fallbackLogout();
        }
    }

    // 备用退出方式
    fallbackLogout() {
        // 尝试使用fetch请求
        fetch('/perform_logout', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: new URLSearchParams({
                [this.getCSRFParameterName()]: this.getCSRFToken() || ''
            })
        }).then(response => {
            if (response.ok || response.redirected) {
                window.location.href = '/login';
            } else {
                throw new Error('退出请求失败');
            }
        }).catch(error => {
            console.error('退出失败:', error);
            // 最后的备用方案，直接跳转到登录页
            window.location.href = '/login';
        });
    }

    // 刷新页面
    handleRefresh() {
        const refreshIcon = document.querySelector('#enhancedRefreshBtn i');
        if (refreshIcon) {
            refreshIcon.classList.add('fa-spin');
        }

        // 如果页面有自定义的刷新函数，优先调用
        if (typeof window.refreshData === 'function') {
            window.refreshData();
        } else {
            setTimeout(() => {
                window.location.reload();
            }, 500);
        }
    }

    // 显示通知
    showNotifications() {
        this.showToast('通知中心能开发中...', 'info');
    }

    // 深色模式切换
    toggleDarkMode() {
        this.showToast('深色模式功能开发中...', 'info');
    }

    // 显示加载
    showLoading() {
        const overlay = document.getElementById('enhancedLoadingOverlay');
        if (overlay) {
            overlay.style.display = 'flex';
        }
    }

    // 隐藏加载
    hideLoading() {
        const overlay = document.getElementById('enhancedLoadingOverlay');
        if (overlay) {
            overlay.style.display = 'none';
        }
    }

    // Toast提示
    showToast(message, type = 'info') {
        const toast = document.createElement('div');
        toast.className = `enhanced-toast ${type}`;
        toast.textContent = message;
        document.body.appendChild(toast);

        setTimeout(() => {
            toast.classList.add('show');
        }, 100);

        setTimeout(() => {
            toast.classList.remove('show');
            setTimeout(() => {
                if (toast.parentNode) {
                    document.body.removeChild(toast);
                }
            }, 300);
        }, 3000);
    }

    // ===== 公共API方法 =====

    // 设置页面标题
    setPageTitle(title) {
        const titleElement = document.getElementById('enhancedPageTitle');
        if (titleElement) {
            titleElement.textContent = title;
        }
    }

    // 获取当前云厂商信息
    getCurrentCloudProvider() {
        return this.cloudProviders[this.currentCloudType];
    }

    // 更新云厂商类型
    updateCloudType(cloudType) {
        if (this.cloudProviders[cloudType] && cloudType !== this.currentCloudType) {
            this.currentCloudType = cloudType;
            this.renderBottomNav();
            // 移除主题更新，保持统一配色

            // 更新云厂商按钮状态
            document.querySelectorAll('.enhanced-cloud-btn').forEach(btn => {
                btn.classList.remove('active');
                if (parseInt(btn.dataset.type) === cloudType) {
                    btn.classList.add('active');
                }
            });
        }
    }

    // 设置当前标签页（公共API）
    setActiveTab(tab) {
        this.setCurrentTab(tab);
    }

    // 显示通知数量
    setNotificationCount(count) {
        const notificationBtn = document.getElementById('enhancedNotificationBtn');
        if (!notificationBtn) return;

        const existingBadge = notificationBtn.querySelector('.enhanced-notification-badge');

        if (existingBadge) {
            existingBadge.remove();
        }

        if (count > 0) {
            const badge = document.createElement('div');
            badge.className = 'enhanced-notification-badge';
            badge.textContent = count > 99 ? '99+' : count;
            notificationBtn.appendChild(badge);
        }
    }

    // 兼容旧版本API
    navigateToTenant() {
        const url = new URL('/tenants/list?mobile=true', window.location.origin);
        url.searchParams.set('cloudType', this.currentCloudType);
        window.location.href = url.toString();
    }

    navigateToInstance() {
        const instanceMenu = this.cloudProviders[this.currentCloudType].menus.find(m =>
            m.id === 'instance' || m.id === 'compute' || m.id === 'vm' || m.id === 'ec2'
        );
        if (instanceMenu) {
            const url = new URL(instanceMenu.url + '?mobile=true', window.location.origin);
            url.searchParams.set('cloudType', this.currentCloudType);
            window.location.href = url.toString();
        }
    }

    navigateToGrabbing() {
        const url = new URL('/boot/fullBootList?mobile=true', window.location.origin);
        url.searchParams.set('cloudType', this.currentCloudType);
        window.location.href = url.toString();
    }

    // ===== 分页组件相关方法 =====

    // 创建分页组件
    createPagination(containerId, options = {}) {
        const container = document.getElementById(containerId);
        if (!container) {
            console.error('分页容器不存在:', containerId);
            return null;
        }

        // 移除现有分页组件
        const existingPagination = container.querySelector('.mobile-pagination');
        if (existingPagination) {
            existingPagination.remove();
        }

        const pagination = new MobilePagination(options);
        pagination.render(container);
        return pagination;
    }
}

// ===== 移动端分页组件类 =====
class MobilePagination {
    constructor(options = {}) {
        this.currentPage = options.currentPage || 1;
        this.totalPages = options.totalPages || 1;
        this.totalElements = options.totalElements || 0;
        this.size = options.size || 10;
        this.onPageChange = options.onPageChange || function() {};
        this.loading = false;
        this.container = null;

        // 配置选项
        this.options = {
            showInfo: options.showInfo !== false, // 默认显示信息
            compact: options.compact || false,    // 紧凑模式
            position: options.position || 'sticky' // sticky | static
        };
    }

    // 渲染分页组件到指定容器
    render(container) {
        this.container = container;

        const paginationHTML = this.generateHTML();
        container.insertAdjacentHTML('beforeend', paginationHTML);

        this.bindEvents();
        this.updateUI();
    }

    // 生成分页HTML
    generateHTML() {
        const compactClass = this.options.compact ? 'compact' : '';
        const positionStyle = this.options.position === 'static' ? 'position: static;' : '';

        return `
            <div class="mobile-pagination ${compactClass}" id="mobilePagination_${Date.now()}" style="${positionStyle}">
                <!-- 加载状态 -->
                <div class="pagination-loading" id="paginationLoading">
                    <span class="pagination-loading-spinner"></span>
                    加载中...
                </div>

                ${this.options.showInfo ? `
                <!-- 分页信息 -->
                <div class="pagination-info" id="paginationInfo">
                    第 1-${this.size} 条，共 ${this.totalElements} 条记录
                </div>
                ` : ''}

                <!-- 分页控制 -->
                <div class="pagination-controls">
                    <!-- 上一页按钮 -->
                    <button class="pagination-btn" id="prevBtn">
                        <i class="fas fa-chevron-left"></i>
                        上一页
                    </button>

                    <!-- 页码选择器 -->
                    <div class="page-selector">
                        <div class="page-input-group">
                            <input type="number" class="page-input" id="pageInput" value="${this.currentPage}" min="1" max="${this.totalPages}">
                            <span class="page-total">/ <span id="totalPages">${this.totalPages}</span></span>
                        </div>
                        <button class="quick-jump-btn" id="jumpBtn">跳转</button>
                    </div>

                    <!-- 下一页按钮 -->
                    <button class="pagination-btn" id="nextBtn">
                        下一页
                        <i class="fas fa-chevron-right"></i>
                    </button>
                </div>
            </div>
        `;
    }

    // 绑定事件
    bindEvents() {
        if (!this.container) return;

        const pagination = this.container.querySelector('.mobile-pagination');
        if (!pagination) return;

        // 获取元素
        this.loadingEl = pagination.querySelector('.pagination-loading');
        this.infoEl = pagination.querySelector('.pagination-info');
        this.prevBtn = pagination.querySelector('#prevBtn');
        this.nextBtn = pagination.querySelector('#nextBtn');
        this.pageInput = pagination.querySelector('#pageInput');
        this.totalPagesEl = pagination.querySelector('#totalPages');
        this.jumpBtn = pagination.querySelector('#jumpBtn');

        // 上一页
        this.prevBtn?.addEventListener('click', () => {
            if (this.currentPage > 1 && !this.loading) {
                this.goToPage(this.currentPage - 1);
            }
        });

        // 下一页
        this.nextBtn?.addEventListener('click', () => {
            if (this.currentPage < this.totalPages && !this.loading) {
                this.goToPage(this.currentPage + 1);
            }
        });

        // 跳转按钮
        this.jumpBtn?.addEventListener('click', () => {
            const targetPage = parseInt(this.pageInput.value);
            if (targetPage >= 1 && targetPage <= this.totalPages && targetPage !== this.currentPage && !this.loading) {
                this.goToPage(targetPage);
            }
        });

        // 输入框回车跳转
        this.pageInput?.addEventListener('keypress', (e) => {
            if (e.key === 'Enter') {
                this.jumpBtn?.click();
            }
        });

        // 输入框失焦时自动修正
        this.pageInput?.addEventListener('blur', () => {
            let value = parseInt(this.pageInput.value);
            if (isNaN(value) || value < 1) {
                this.pageInput.value = 1;
            } else if (value > this.totalPages) {
                this.pageInput.value = this.totalPages;
            }
        });
    }

    // 跳转到指定页面
    goToPage(page) {
        if (page === this.currentPage || this.loading) return;

        this.showLoading();
        this.onPageChange(page, this.size);
    }

    // 更新分页数据
    updatePagination(data) {
        this.currentPage = data.currentPage;
        this.totalPages = data.totalPages;
        this.totalElements = data.totalElements;
        this.size = data.size;

        this.updateUI();
        this.hideLoading();
    }

    // 更新UI
    updateUI() {
        // 更新页码信息
        if (this.infoEl) {
            const start = (this.currentPage - 1) * this.size + 1;
            const end = Math.min(this.currentPage * this.size, this.totalElements);
            this.infoEl.textContent = `第 ${start}-${end} 条，共 ${this.totalElements} 条记录`;
        }

        // 更新按钮状态
        if (this.prevBtn) this.prevBtn.disabled = this.currentPage <= 1;
        if (this.nextBtn) this.nextBtn.disabled = this.currentPage >= this.totalPages;

        // 更新页码输入框
        if (this.pageInput) {
            this.pageInput.value = this.currentPage;
            this.pageInput.max = this.totalPages;
        }
        if (this.totalPagesEl) {
            this.totalPagesEl.textContent = this.totalPages;
        }

        // 如果只有一页，隐藏分页控件
        if (this.container) {
            const pagination = this.container.querySelector('.mobile-pagination');
            if (pagination) {
                if (this.totalPages <= 1) {
                    pagination.style.display = 'none';
                } else {
                    pagination.style.display = 'block';
                }
            }
        }
    }

    // 显示加载状态
    showLoading() {
        this.loading = true;
        if (this.loadingEl) this.loadingEl.classList.add('show');
        if (this.prevBtn) this.prevBtn.disabled = true;
        if (this.nextBtn) this.nextBtn.disabled = true;
        if (this.jumpBtn) this.jumpBtn.disabled = true;
    }

    // 隐藏加载状态
    hideLoading() {
        this.loading = false;
        if (this.loadingEl) this.loadingEl.classList.remove('show');
        if (this.jumpBtn) this.jumpBtn.disabled = false;
        this.updateUI(); // 重新更新按钮状态
    }

    // 公共方法：外部调用更新分页数据
    update(data) {
        this.updatePagination(data);
    }

    // 获取当前分页状态
    getState() {
        return {
            currentPage: this.currentPage,
            totalPages: this.totalPages,
            totalElements: this.totalElements,
            size: this.size
        };
    }

    // 销毁分页组件
    destroy() {
        if (this.container) {
            const pagination = this.container.querySelector('.mobile-pagination');
            if (pagination) {
                pagination.remove();
            }
        }
    }
}

// 初始化导航系统
let mobileNav;

// 确保在DOM加载完成后初始化
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', function() {
        mobileNav = new EnhancedMobileNavigation();
        window.mobileNav = mobileNav;
        window.MobilePagination = MobilePagination;
    });
} else {
    mobileNav = new EnhancedMobileNavigation();
    window.mobileNav = mobileNav;
    window.MobilePagination = MobilePagination;
}

// 兼容性：暴露到全局供其他页面使用
window.showToast = function(message, type) {
    if (window.mobileNav) {
        window.mobileNav.showToast(message, type);
    } else {
        console.log('Toast:', message);
    }
};

// 全局分页创建函数
window.createMobilePagination = function(containerId, options) {
    if (window.mobileNav) {
        return window.mobileNav.createPagination(containerId, options);
    }
    return null;
};

// 导出类供其他模块使用
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { EnhancedMobileNavigation, MobilePagination };
}