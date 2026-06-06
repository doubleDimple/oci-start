<!DOCTYPE html>
<html>
<head>
    <title>OCI-START 管理系统</title>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
    <meta name="_csrf" content="${_csrf.token}">
    <meta name="_csrf_header" content="${_csrf.headerName}">
    <input type="hidden" name="_csrf" value="${_csrf.token}">

    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/app/header.css">
    <link rel="stylesheet" href="/css/app/sidebar.css">
    <style>
        html, body { margin: 0; padding: 0; overflow: hidden; background: #1a1d21; }
        [data-theme="light"] html, [data-theme="light"] body { background: #f0f4f8; }
        body { display: flex; flex-direction: column; height: 100vh; padding-top: 60px; box-sizing: border-box; }
        .admin-main > main {
            background-color: #1a1d21;
            margin-left: 180px;
            transition: margin-left 0.3s ease;
        }
        [data-theme="light"] .admin-main > main { background-color: #f0f4f8; }
        body.sidebar-collapsed .admin-main > main { margin-left: 0; }
        @media (max-width: 768px) { .admin-main > main { margin-left: 150px !important; } }
    </style>
    <script>
        /* 防闪烁：CSS 加载前立即设置外壳主题 + sidebar 折叠状态 */
        (function () {
            var t = localStorage.getItem('oci_theme') || 'dark';
            if (t === 'system') t = window.matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';
            document.documentElement.dataset.theme = t;
            if (localStorage.getItem('sidebar_collapsed') === '1') {
                document.documentElement.classList.add('preload-sidebar-collapsed');
            }
        })();
    </script>
    <!-- 移动端响应式适配层（放在已有样式之后，确保覆盖优先级正确） -->
    <link rel="stylesheet" href="/css/mobile.css">
</head>
<body>
<#include "common/header.ftl">

<!-- Transparent overlay — closes nav menus when user clicks in iframe area -->
<div id="navCloseOverlay" onclick="if(typeof closeAllMenus==='function')closeAllMenus();"
     style="display:none; position:fixed; top:60px; left:0; right:0; bottom:0; z-index:999;"></div>

<div class="admin-main" style="display: flex; flex: 1; min-height: 0;">
    <#include "common/sidebar.ftl">

    <main style="flex: 1; position: relative;">
        <iframe id="biz-frame" name="biz-frame" src="${initialPath!''}" frameborder="0" style="width: 100%; height: 100%;"></iframe>
    </main>
</div>

<footer class="global-footer">
    <div class="global-footer-center">
        <div class="footer-line1">© 2025 <strong>doubleDimple</strong>. All rights reserved.</div>
        <div class="footer-line2">
            <a href="https://github.com/doubleDimple" target="_blank" rel="noopener">
                <i class="fab fa-github"></i> github.com/doubleDimple
            </a>
        </div>
    </div>
</footer>

<!-- 移动端：侧边栏遮罩层 -->
<div class="mobile-overlay" id="mobileOverlay"></div>

<!-- 移动端：底部 Tab 导航栏（移动端 CSS 控制显示/隐藏） -->
<nav class="mobile-tab-bar" id="mobileTabBar" aria-label="移动端导航"></nav>

<!-- 在body结束前引入版本信息模块 -->
<#include "common/version_info.ftl">
<script src="/js/common/request.js"></script>
<script src="/js/system/sidebar.js"></script>
<!-- 移动端交互脚本 -->
<script src="/js/common/mobile.js"></script>
<script>
    document.getElementById('biz-frame').addEventListener('load', function () {
        if (typeof window.syncFrameTheme === 'function') {
            window.syncFrameTheme(localStorage.getItem('oci_theme') || 'dark');
        }
    });
</script>
</body>
</html>
