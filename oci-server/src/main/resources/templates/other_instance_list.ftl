<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 云实例管理</title>
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600&display=swap" rel="stylesheet">
-->
    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/app/other_instance_list.css">

    <!-- SweetAlert2 CSS -->
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/common/sweetalert-overrides.css" rel="stylesheet">
    <!-- SweetAlert2 JS -->
    <script src="/js/sweetalert2.min.js"></script>

    <#include "common/pagination.ftl" />

</head>
<body>
<#--<#include "common/version_info.ftl">-->

<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
    <div class="page-card">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-cloud"></i>
                <span>云实例管理</span>
            </h1>
        </div>

        <!-- Cloud Type Selector -->
        <#--<div class="cloud-type-selector">
            <label for="cloudTypeSelect">云厂商类型：</label>
            <select id="cloudTypeSelect" onchange="changeCloudType()">
                <option value="2" ${(cloudType == 2)?string('selected', '')}>GCP (Google Cloud Platform)</option>
            </select>
        </div>-->

        <!-- Table View -->
        <div class="table-view">
            <table class="table">
                <thead>
                <tr>
                    <th>实例名称</th>
                    <th>所属租户</th>
                    <th>云类型</th>
                    <th>配置</th>
                    <th>架构</th>
                    <th>磁盘</th>
                    <th>状态</th>
                    <th>公网IP</th>
                    <th>root密码</th>
                    <th>操作</th>
                </tr>
                </thead>
                <tbody>
                <#list instances as instance>
                    <tr>
                        <td>
                            <span class="truncate" onclick="toggleText(this)" data-fulltext="${instance.instanceName}">${instance.instanceName}</span>
                        </td>
                        <td>
                            <span class="truncate" onclick="toggleText(this)" data-fulltext="${instance.defName}">${instance.defName}</span>
                        </td>
                        <td>
                            <#if instance.cloudType == 2>
                                <span class="cloud-badge gcp">GCP</span>
                            <#elseif instance.cloudType == 3>
                                <span class="cloud-badge azure">Azure</span>
                            <#elseif instance.cloudType == 4>
                                <span class="cloud-badge aws">AWS</span>
                            </#if>
                        </td>
                        <td>
                            <span>${instance.ocpu}核/${instance.memory}GB</span>
                        </td>
                        <td>
                            <span>${instance.architecture!'未知'}</span>
                        </td>
                        <td>
                            <span>${instance.disk}GB</span>
                        </td>
                        <td>
                            <#if instance.status == 0>
                                <span class="status-badge status-stopped">未开机</span>
                            <#elseif instance.status == 1>
                                <span class="status-badge status-pending">开机中</span>
                            <#elseif instance.status == 2>
                                <span class="status-badge status-running">已开机</span>
                            <#else>
                                <span class="status-badge">未知</span>
                            </#if>
                        </td>
                        <td>
                            <span class="truncate" onclick="toggleText(this)" data-fulltext="${instance.publicIp}">${instance.publicIp}</span>
                            <button class="btn-copy-password" onclick="copyToClipboard('${instance.publicIp}', this, 'IP地址')" title="复制IP地址">
                                <i class="fas fa-copy"></i>
                            </button>
                        </td>
                        <td>
                            <span class="truncate" onclick="toggleText(this)" data-fulltext="${instance.rootPassword}">${instance.rootPassword}</span>
                            <button class="btn-copy-password" onclick="copyToClipboard('${instance.rootPassword}', this, '密码')" title="复制密码">
                                <i class="fas fa-copy"></i>
                            </button>
                        </td>
                        <#--<td>
                            <span class="truncate" onclick="toggleText(this)" data-fulltext="${instance.formattedCreatedAt}">${instance.formattedCreatedAt}</span>
                        </td>-->
                        <td>
                            <button class="btn-change-ip"
                                    onclick="changeInstanceIp('${instance.bootId}', ${instance.cloudType})"
                                    title="切换实例IP地址"
                                    ${(instance.status != 2)?string('disabled', '')}>
                                <i class="fas fa-exchange-alt"></i>
                                切换IP
                            </button>
                            <button class="btn-refresh" onclick="refreshInstance('${instance.bootId}', ${instance.cloudType})" title="刷新实例状态">
                                <i class="fas fa-sync-alt"></i>
                                刷新
                            </button>
                            <button class="btn-terminate" onclick="terminateInstance('${instance.bootId}', ${instance.cloudType})" title="终止实例">
                                <i class="fas fa-stop-circle"></i>
                                终止
                            </button>
                        </td>
                    </tr>
                </#list>
                </tbody>
            </table>
        </div>

        <!-- 空状态提示 -->
        <#if !instances?has_content>
            <div style="text-align: center; padding: 60px 20px; color: var(--text-secondary);">
                <i class="fas fa-cloud" style="font-size: 48px; margin-bottom: 20px; opacity: 0.3;"></i>
                <h3 style="margin-bottom: 10px;">暂无实例</h3>
                <p>当前云厂商类型下没有找到任何实例</p>
            </div>
        </#if>

        <!-- Pagination -->
        <@pagination
        url="/other/instances/list"
        page=currentPage
        size=size
        totalPages=totalPages
        totalElements=totalElements
        textShow=msg.get("page.show")
        textItem=msg.get("page.item")
        textPrev=msg.get("page.prev")
        textNext=msg.get("page.next")
        textJump=msg.get("page.jump")
        textPage=msg.get("page.page")
        textTotal=msg.get("page.total")
        />

    </div><!-- /.page-card -->
    </main>
</div>

<!-- CSRF Token -->
<div style="display: none;">
</div>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script>
    // 定义全局常量，使用?c确保数字格式正确
    const TENANT_ID = ${tenantId?c};

    // 页面初始化
    document.addEventListener('DOMContentLoaded', () => {
        // 初始化文本截断
        initTextTruncation();
        // 初始化侧边栏
        initSidebar();
    });

    // 云厂商类型切换
    function changeCloudType() {
        const cloudType = document.getElementById('cloudTypeSelect').value;
        const currentUrl = new URL(window.location);
        currentUrl.searchParams.set('cloudType', cloudType);
        currentUrl.searchParams.set('page', '0'); // 重置到第一页
        window.location.href = currentUrl.toString();
    }

    // 文本截断切换
    function toggleText(element) {
        const fullText = element.getAttribute('data-fulltext');
        const isTruncated = element.getAttribute('data-truncated') === 'true';

        if (isTruncated) {
            element.textContent = fullText.length > 15 ? fullText.substring(0, 15) + '...' : fullText;
            element.setAttribute('data-truncated', 'false');
        } else {
            element.textContent = fullText;
            element.setAttribute('data-truncated', 'true');
        }
    }

    // 初始化文本截断
    function initTextTruncation() {
        const truncateElements = document.querySelectorAll('.truncate');
        truncateElements.forEach(element => {
            const fullText = element.textContent.trim();
            element.setAttribute('data-fulltext', fullText);
            if (fullText.length > 15) {
                element.textContent = fullText.substring(0, 15) + '...';
                element.setAttribute('data-truncated', 'false');
            } else {
                element.setAttribute('data-truncated', 'true');
            }
        });
    }

    // 初始化侧边栏
    function initSidebar() {
        const navParents = document.querySelectorAll('.nav-parent');
        navParents.forEach(parent => {
            const parentLink = parent.querySelector('.nav-link');
            parentLink.addEventListener('click', (e) => {
                e.preventDefault();
                parent.classList.toggle('expanded');
            });
        });

        // 展开当前活动菜单
        const activeLink = document.querySelector('.nav-link.active');
        if (activeLink) {
            const parent = activeLink.closest('.nav-parent');
            if (parent) {
                parent.classList.add('expanded');
            }
        }
    }

    // 终止实例功能
    function terminateInstance(bootId, cloudType) {
        Swal.fire({
            title: '⚠️ 警告',
            html: '<p style="color: var(--accent-red); font-weight: bold;">此操作将永久删除实例及其数据，且不可恢复！</p><p style="margin-top: 10px;">确定要终止这个实例吗？</p>',
            icon: 'warning',
            showCancelButton: true,
            confirmButtonColor: '#ff6b6b',
            cancelButtonColor: '#6c757d',
            confirmButtonText: '确认终止',
            cancelButtonText: '取消',
            reverseButtons: true
        }).then((result) => {
            if (result.isConfirmed) {
                // 显示加载状态
                Swal.fire({
                    title: '正在终止实例...',
                    allowOutsideClick: false,
                    didOpen: () => {
                        Swal.showLoading();
                    }
                });

                // 获取CSRF令牌
                const csrfToken = document.querySelector('input[name="_csrf"]').value;

                // 发送删除请求
                fetch(`/other/instances/`+ bootId+`/delete`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-TOKEN': csrfToken
                    },
                    body: JSON.stringify({
                        tenantId: TENANT_ID,  // 使用全局常量
                        cloudType: cloudType
                    })
                })
                    .then(response => response.json())
                    .then(data => {
                        if (data.success) {
                            Swal.fire({
                                title: '终止成功！',
                                text: '实例已成功终止',
                                icon: 'success',
                                timer: 2000,
                                showConfirmButton: false
                            }).then(() => {
                                location.reload();
                            });
                        } else {
                            Swal.fire({
                                title: '终止失败',
                                text: data.message || '未知错误',
                                icon: 'error'
                            });
                        }
                    })
                    .catch(error => {
                        console.error('终止实例失败:', error);
                        Swal.fire({
                            title: '网络错误',
                            text: '请检查网络连接后重试',
                            icon: 'error'
                        });
                    });
            }
        });
    }

    // 刷新实例状态功能
    function refreshInstance(bootId, cloudType) {
        Swal.fire({
            title: '刷新实例状态',
            text: '正在获取最新的实例状态信息...',
            icon: 'info',
            showCancelButton: true,
            confirmButtonColor: '#2196f3',
            cancelButtonColor: '#6c757d',
            confirmButtonText: '确认刷新',
            cancelButtonText: '取消'
        }).then((result) => {
            if (result.isConfirmed) {
                // 显示加载状态
                Swal.fire({
                    title: '正在刷新状态...',
                    allowOutsideClick: false,
                    didOpen: () => {
                        Swal.showLoading();
                    }
                });

                // 获取CSRF令牌
                const csrfToken = document.querySelector('input[name="_csrf"]').value;

                // 发送刷新请求
                fetch(`/other/instances/`+ bootId+`/refresh`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-TOKEN': csrfToken
                    },
                    body: JSON.stringify({
                        tenantId: TENANT_ID,  // 使用全局常量
                        cloudType: cloudType
                    })
                })
                    .then(response => response.json())
                    .then(data => {
                        if (data.success) {
                            Swal.fire({
                                title: '刷新成功！',
                                text: '实例状态已更新',
                                icon: 'success',
                                timer: 2000,
                                showConfirmButton: false
                            }).then(() => {
                                location.reload();
                            });
                        } else {
                            Swal.fire({
                                title: '刷新失败',
                                text: data.message || '未知错误',
                                icon: 'error'
                            });
                        }
                    })
                    .catch(error => {
                        console.error('刷新实例状态失败:', error);
                        Swal.fire({
                            title: '网络错误',
                            text: '请检查网络连接后重试',
                            icon: 'error'
                        });
                    });
            }
        });
    }

    function copyToClipboard(text, buttonElement, type) {
        // 尝试使用现代的 Clipboard API
        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(text).then(() => {
                showCopySuccess(buttonElement, type);
            }).catch(() => {
                // 如果 Clipboard API 失败，使用传统方法
                fallbackCopyTextToClipboard(text, buttonElement, type);
            });
        } else {
            // 不支持 Clipboard API 或非安全上下文，使用传统方法
            fallbackCopyTextToClipboard(text, buttonElement, type);
        }
    }

    function fallbackCopyTextToClipboard(text, buttonElement, type) {
        const textArea = document.createElement("textarea");
        textArea.value = text;

        // 设置样式使其不可见但不影响布局
        textArea.style.position = 'fixed';
        textArea.style.top = '0';
        textArea.style.left = '0';
        textArea.style.width = '2em';
        textArea.style.height = '2em';
        textArea.style.padding = '0';
        textArea.style.border = 'none';
        textArea.style.outline = 'none';
        textArea.style.boxShadow = 'none';
        textArea.style.background = 'transparent';
        textArea.style.fontSize = '16px'; // 防止 iOS 缩放

        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();

        try {
            const successful = document.execCommand('copy');
            if (successful) {
                showCopySuccess(buttonElement, type);
            } else {
                showCopyError(type);
            }
        } catch (err) {
            console.error('复制失败:', err);
            showCopyError(type);
        }

        document.body.removeChild(textArea);
    }

    function showCopyError(type) {
        Swal.fire({
            toast: true,
            position: 'top-end',
            showConfirmButton: false,
            timer: 2000,
            icon: 'error',
            title: `复制失败`,
            text: '请手动选择并复制',
            timerProgressBar: true
        });
    }

    function showCopySuccess(buttonElement, type) {
        const icon = buttonElement.querySelector('i');
        const originalClass = icon.className;

        // 更新按钮状态
        buttonElement.classList.add('copied');
        icon.className = 'fas fa-check';

        // 显示成功提示
        Swal.fire({
            toast: true,
            position: 'top-end',
            showConfirmButton: false,
            timer: 1500,
            icon: 'success',
            title: type+`已复制`,
            timerProgressBar: true
        });

        // 2秒后恢复按钮状态
        setTimeout(() => {
            buttonElement.classList.remove('copied');
            icon.className = originalClass;
        }, 2000);
    }

    // 简单的复制密码功能
    function copyThisPassword(password, buttonElement) {
        copyToClipboard(password, buttonElement, '密码');
    }

    // 切换实例IP功能
    function changeInstanceIp(bootId, cloudType) {
        Swal.fire({
            title: '切换实例IP',
            html: `
            <div style="text-align: left; margin: 20px 0;">
                <p style="margin-bottom: 15px; color: var(--text-secondary);">
                    <i class="fas fa-info-circle" style="color: var(--accent-blue); margin-right: 8px;"></i>
                    此操作将为实例分配新的外部IP地址
                </p>
                <div style="background: var(--surface-2); padding: 15px; border-radius: 5px; margin: 15px 0;">
                    <p style="margin: 5px 0; font-size: 14px;"><strong>注意事项：</strong></p>
                    <ul style="margin: 8px 0; padding-left: 20px; font-size: 13px; color: var(--text-secondary);">
                        <li>原IP地址将被释放，无法恢复</li>
                        <li>新IP地址将随机分配</li>
                        <li>切换过程中可能有短暂的网络中断</li>
                        <li>请确保实例处于运行状态</li>
                    </ul>
                </div>
                <p style="color: var(--accent-red); font-weight: bold; margin-top: 15px;">
                    确定要切换此实例的IP地址吗？
                </p>
            </div>
        `,
            icon: 'question',
            showCancelButton: true,
            confirmButtonColor: '#1abc9c',
            cancelButtonColor: '#6c757d',
            confirmButtonText: '<i class="fas fa-exchange-alt"></i> 确认切换',
            cancelButtonText: '取消',
            reverseButtons: true,
            width: '480px'
        }).then((result) => {
            if (result.isConfirmed) {
                // 显示加载状态
                Swal.fire({
                    title: '正在切换IP地址...',
                    html: `
                    <div style="text-align: center; padding: 20px;">
                        <div style="margin-bottom: 15px;">
                            <i class="fas fa-exchange-alt fa-2x" style="color: var(--accent-green); animation: pulse 1.5s infinite;"></i>
                        </div>
                        <p style="color: var(--text-secondary); margin: 0;">请稍候，正在为实例分配新的IP地址...</p>
                    </div>
                `,
                    allowOutsideClick: false,
                    showConfirmButton: false,
                    didOpen: () => {
                        // 添加动画效果
                        const style = document.createElement('style');
                        style.textContent = `
                        @keyframes pulse {
                            0% { transform: scale(1); opacity: 1; }
                            50% { transform: scale(1.1); opacity: 0.7; }
                            100% { transform: scale(1); opacity: 1; }
                        }
                    `;
                        document.head.appendChild(style);
                    }
                });

                // 获取CSRF令牌
                const csrfToken = document.querySelector('input[name="_csrf"]').value;

                // 发送切换IP请求
                fetch(`/other/instances/` + bootId + `/changeIp`, {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-CSRF-TOKEN': csrfToken
                    },
                    body: JSON.stringify({
                        tenantId: TENANT_ID,
                        cloudType: cloudType
                    })
                })
                    .then(response => response.json())
                    .then(data => {
                        if (data.success) {
                            Swal.fire({
                                title: '切换成功！',
                                html: `
                            <div style="text-align: center; padding: 20px;">
                                <div style="margin-bottom: 15px;">
                                    <i class="fas fa-check-circle fa-3x" style="color: var(--accent-green);"></i>
                                </div>
                                <p style="color: var(--text-secondary); margin: 10px 0;">实例IP地址已成功切换</p>
                                <p style="color: var(--text-secondary); font-size: 13px;">页面将自动刷新以显示新的IP地址</p>
                            </div>
                        `,
                                icon: 'success',
                                timer: 3000,
                                showConfirmButton: false,
                                timerProgressBar: true
                            }).then(() => {
                                location.reload();
                            });
                        } else {
                            let errorMessage = data.message || '未知错误';
                            let errorDetails = '';

                            // 根据不同的错误类型显示不同的提示
                            if (errorMessage.includes('NOT_FOUND')) {
                                errorDetails = '实例可能已被删除或不存在';
                            } else if (errorMessage.includes('状态')) {
                                errorDetails = '请确保实例处于运行状态';
                            }

                            Swal.fire({
                                title: '切换失败',
                                html: `
                            <div style="text-align: center; padding: 20px;">
                                <div style="margin-bottom: 15px;">
                                    <i class="fas fa-exclamation-triangle fa-2x" style="color: #ff6b6b;"></i>
                                </div>
                                <p style="color: var(--text-secondary); margin: 10px 0;">`+ errorMessage+`</p>
                        </div>
                            `,
                        icon: 'error',
                        confirmButtonColor: '#ff6b6b'
                    });
                }
            })
            .catch(error => {
                console.error('切换IP失败:', error);
                Swal.fire({
                    title: '网络错误',
                    html: `
                            <div style="text-align: center; padding: 20px;">
                                <div style="margin-bottom: 15px;">
                                <i class="fas fa-wifi fa-2x" style="color: var(--accent-red);"></i>
                        </div>
                            <p style="color: var(--text-secondary); margin: 10px 0;">网络连接出现问题</p>
                            <p style="color: var(--text-secondary); font-size: 13px;">请检查网络连接后重试</p>
                        </div>
                            `,
                    icon: 'error',
                    confirmButtonColor: '#ff6b6b'
                });
            });
        }
    });
}
</script>

</body>
</html>