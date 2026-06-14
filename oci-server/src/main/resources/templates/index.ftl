<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="_csrf" content="">
    <meta name="_csrf_header" content="X-CSRF-TOKEN">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OCI-START - 欢迎页面</title>
    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/app/index.css">
</head>
<body>

<!-- ── Hero Header ── -->
<header class="hero">
    <div class="hero-bg-grid"></div>
    <div class="hero-orb hero-orb-1"></div>
    <div class="hero-orb hero-orb-2"></div>
    <div class="hero-inner">
        <div class="hero-brand">
            <div class="hero-logo">
                <i class="fas fa-cloud"></i>
            </div>
            <div class="hero-text">
                <h1>${msg.get('index.welcome.title')}</h1>
                <p>${msg.get('index.welcome.subtitle')}</p>
            </div>
        </div>
        <div class="hero-actions">
            <div class="countdown-ring">
                <svg viewBox="0 0 44 44" class="ring-svg">
                    <circle cx="22" cy="22" r="18" class="ring-track"/>
                    <circle cx="22" cy="22" r="18" class="ring-progress" id="ring-progress"/>
                </svg>
                <span class="ring-label" id="countdown-text">60${msg.get('index.redirect.suffix')}</span>
            </div>
            <div class="hero-btns">
                <button class="hero-btn" onclick="cancelAutoRedirect()" id="stay-btn">
                    <i class="fas fa-pause"></i>
                    <span>${msg.get('index.btn.stay')}</span>
                </button>
                <button class="hero-btn hero-btn-primary" onclick="goToTenants()">
                    <i class="fas fa-arrow-right"></i>
                    <span>${msg.get('index.btn.go')}</span>
                </button>
            </div>
        </div>
    </div>
</header>

<!-- ── Stats Banner ── -->
<section class="stats-banner">
    <div class="container">
        <div class="stats-row">
            <div class="scard animate-up">
                <div class="scard-icon" style="background:linear-gradient(135deg,#3d5a80,#5b7fa6);">
                    <i class="fas fa-rocket"></i>
                </div>
                <div class="scard-body">
                    <div class="scard-num" id="total-boot-count">${msg.get('common.loading')}</div>
                    <div class="scard-label">${msg.get('index.openCount')}</div>
                </div>
            </div>
            <div class="scard animate-up delay-1">
                <div class="scard-icon" style="background:linear-gradient(135deg,#f59e0b,#fbbf24);">
                    <i class="fas fa-heart"></i>
                </div>
                <div class="scard-body">
                    <div class="scard-num" id="donations-count">29</div>
                    <div class="scard-label">${msg.get('index.stats.donors')}</div>
                </div>
            </div>
            <div class="scard animate-up delay-2">
                <div class="scard-icon" style="background:linear-gradient(135deg,#2f80b0,#4a9cc7);">
                    <i class="fas fa-star"></i>
                </div>
                <div class="scard-body">
                    <div class="scard-num" id="github-stars">${msg.get('common.loading')}</div>
                    <div class="scard-label">GitHub Stars</div>
                </div>
            </div>
        </div>
        <p class="stats-desc">${msg.get('index.stats.desc')}</p>
    </div>
</section>

<!-- ── Feature Categories ── -->
<section class="features-section">
    <div class="container">
        <div class="section-head">
            <div class="section-tag">FEATURES</div>
            <h2>${msg.get('index.stats.thanks')}</h2>
        </div>
        <div class="feat-grid">

            <!-- 实例管理 -->
            <div class="feat-card animate-up">
                <div class="feat-card-header" style="--cat-color:#7c3aed;">
                    <div class="feat-cat-icon"><i class="fas fa-server"></i></div>
                    <span>实例管理</span>
                </div>
                <ul class="feat-list">
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.batchBoot')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.lifecycle')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.rescue')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.diskReset')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.instanceTerminate')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.sshTerm')}</li>
                </ul>
            </div>

            <!-- 存储 & 网络 -->
            <div class="feat-card animate-up delay-1">
                <div class="feat-card-header" style="--cat-color:#0ea5e9;">
                    <div class="feat-cat-icon"><i class="fas fa-network-wired"></i></div>
                    <span>存储 &amp; 网络</span>
                </div>
                <ul class="feat-list">
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.volumeTune')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.networkConfig')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.ipv6Switch')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.ipCheck')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.cfMgmt')}</li>
                </ul>
            </div>

            <!-- 监控 & 计费 -->
            <div class="feat-card animate-up delay-2">
                <div class="feat-card-header" style="--cat-color:#f59e0b;">
                    <div class="feat-cat-icon"><i class="fas fa-chart-bar"></i></div>
                    <span>监控 &amp; 计费</span>
                </div>
                <ul class="feat-list">
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.trafficQuery')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.trafficAlert')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.trafficMonitor')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.costQuery')}</li>
                </ul>
            </div>

            <!-- 账号 & 安全 -->
            <div class="feat-card animate-up delay-1">
                <div class="feat-card-header" style="--cat-color:#ef4444;">
                    <div class="feat-cat-icon"><i class="fas fa-shield-alt"></i></div>
                    <span>账号 &amp; 安全</span>
                </div>
                <ul class="feat-list">
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.multiRegion')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.securityRule')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.userMgmt')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.mfaMgmt')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.auditLog')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.loginMgmt')}</li>
                </ul>
            </div>

            <!-- 系统 & 集成 -->
            <div class="feat-card animate-up delay-2">
                <div class="feat-card-header" style="--cat-color:#10b981;">
                    <div class="feat-cat-icon"><i class="fas fa-cogs"></i></div>
                    <span>系统 &amp; 集成</span>
                </div>
                <ul class="feat-list">
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.emailSupport')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.notification')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.dbFree')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.dbOneClick')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.aiMgmt')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.apiDev')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.migration')}</li>
                    <li><i class="fas fa-check-circle"></i>${msg.get('index.feature.tenantExport')}</li>
                </ul>
            </div>

        </div>
        <p class="feat-more">${msg.get('index.stats.moreComing')}</p>
    </div>
</section>

<!-- ── Version Section ── -->
<section class="version-section">
    <div class="container">
        <div class="version-card">
            <div class="version-card-left">
                <div class="version-icon-wrap">
                    <i class="fas fa-code-branch"></i>
                </div>
                <div>
                    <h3>${msg.get('index.version.title')}</h3>
                    <p>${msg.get('index.version.subtitle')}</p>
                </div>
                <div class="version-badge">
                    <i class="fas fa-check-circle"></i>
                    ${msg.get('index.version.badgeLatest')}
                </div>
            </div>
            <div class="version-details">
                <div class="vd-item">
                    <span class="vd-label">${msg.get('index.version.current')}</span>
                    <span class="vd-val" id="current-version">${msg.get('common.loading')}</span>
                </div>
                <div class="vd-item">
                    <span class="vd-label">${msg.get('index.version.latest')}</span>
                    <span class="vd-val" id="latest-version">${msg.get('common.loading')}</span>
                </div>
                <div class="vd-item">
                    <span class="vd-label">${msg.get('index.version.releaseDate')}</span>
                    <span class="vd-val" id="release-date">2024-10-01</span>
                </div>
                <div class="vd-item">
                    <span class="vd-label">${msg.get('index.version.status')}</span>
                    <span class="vd-val vd-status" id="version-status">${msg.get('index.version.checking')}</span>
                </div>
            </div>
            <div class="quick-links">
                <a href="https://github.com/doubleDimple/oci-start/releases" target="_blank" class="ql-btn ql-primary">
                    <i class="fas fa-download"></i>${msg.get('index.version.btnCheck')}
                </a>
                <a href="https://github.com/doubleDimple/oci-start" target="_blank" class="ql-btn">
                    <i class="fab fa-github"></i>${msg.get('index.version.btnRepo')}
                </a>
                <a href="https://blogger.objboy.com/" target="_blank" class="ql-btn">
                    <i class="fas fa-blog"></i>${msg.get('index.version.btnBlog')}
                </a>
                <a href="https://t.me/+M7XhteVCMMU5ZDhh" target="_blank" class="ql-btn">
                    <i class="fab fa-telegram"></i>${msg.get('index.version.btnTG')}
                </a>
            </div>
        </div>
    </div>
</section>

<!-- ── Donation Section ── -->
<section class="donation-section">
    <div class="container">
        <div class="section-head">
            <div class="section-tag">DONORS</div>
            <h2>${msg.get('index.donation.title')}</h2>
            <p>${msg.get('index.donation.subtitle')}</p>
        </div>

        <div class="donation-stats-row">
            <div class="ds-card">
                <i class="fas fa-users ds-icon" style="color:#3d5a80;"></i>
                <div class="ds-num">30</div>
                <div class="ds-label">${msg.get('index.donation.labelDonors')}</div>
            </div>
            <div class="ds-card">
                <i class="fas fa-yen-sign ds-icon" style="color:#f59e0b;"></i>
                <div class="ds-num">¥1609.08</div>
                <div class="ds-label">${msg.get('index.donation.labelAmount')}</div>
            </div>
            <div class="ds-card">
                <i class="fas fa-cloud ds-icon" style="color:#2f80b0;"></i>
                <div class="ds-num">8</div>
                <div class="ds-label">${msg.get('index.donation.labelAccounts')}</div>
            </div>
            <div class="ds-card">
                <i class="fas fa-calendar-alt ds-icon" style="color:#10b981;"></i>
                <div class="ds-num" id="project-days">0</div>
                <div class="ds-label">${msg.get('index.donation.labelDays')}</div>
            </div>
        </div>

        <div class="dtable-wrap">
            <div class="dtable-header">
                <i class="fas fa-heart"></i>
                <span>${msg.get('index.donation.tableTitle')}</span>
            </div>
            <div class="dtable-scroll">
                <table class="dtable">
                    <thead>
                    <tr>
                        <th>#</th>
                        <th>${msg.get('index.donation.tableName')}</th>
                        <th>${msg.get('index.donation.tableContent')}</th>
                        <th>${msg.get('index.donation.tableDate')}</th>
                    </tr>
                    </thead>
                    <tbody>
                    <tr class="donor-top-1">
                        <td><span class="rank-badge rank-1">30</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-purple">D</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill">¥28.28</span></td>
                        <td class="date-cell">2026-04-12</td>
                    </tr>
                    <tr class="donor-top-1">
                        <td><span class="rank-badge rank-1">29</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-purple">D</div><span>@doufuru</span></div></td>
                        <td><span class="amount-pill">¥30</span></td>
                        <td class="date-cell">2026-02-09</td>
                    </tr>
                    <tr class="donor-top-2">
                        <td><span class="rank-badge rank-2">28</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-amber">N</div><span>Noah Ting(@NoahTing55)</span></div></td>
                        <td><span class="amount-pill amount-lg">¥200</span></td>
                        <td class="date-cell">2026-01-25</td>
                    </tr>
                    <tr class="donor-top-3">
                        <td><span class="rank-badge rank-3">27</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-teal">安</div><span>安安(@ananitsme)</span></div></td>
                        <td><span class="amount-pill">¥50</span></td>
                        <td class="date-cell">2025-12-29</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">26</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill">¥30</span></td>
                        <td class="date-cell">2025-11-02</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">25</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-blue">范</div><span>范(@yuchenfan492)</span></div></td>
                        <td><span class="amount-pill">¥30</span></td>
                        <td class="date-cell">2025-10-26</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">24</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-teal">安</div><span>安安(@ananitsme)</span></div></td>
                        <td><span class="amount-pill">¥50</span></td>
                        <td class="date-cell">2025-10-25</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">23</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-amber">柯</div><span>柯南(@KN_001)</span></div></td>
                        <td><span class="amount-pill amount-lg">¥200</span></td>
                        <td class="date-cell">2025-10-25</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">22</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-purple">X</div><span>@xwbay</span></div></td>
                        <td><span class="amount-pill">¥88</span></td>
                        <td class="date-cell">2025-10-18</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">21</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill amount-sm">¥10</span></td>
                        <td class="date-cell">2025-09-21</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">20</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-amber">柯</div><span>柯南(@KN_001)</span></div></td>
                        <td><span class="amount-pill amount-lg">¥100</span></td>
                        <td class="date-cell">2025-09-13</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">19</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-amber">柯</div><span>柯南(@KN_001)</span></div></td>
                        <td><span class="amount-pill amount-cloud">GCP账号</span></td>
                        <td class="date-cell">2025-07-15</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">18</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-blue">R</div><span>Riva Milne</span></div></td>
                        <td><span class="amount-pill amount-cloud">GCP账号</span></td>
                        <td class="date-cell">2025-07-15</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">17</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-purple">J</div><span>Ja3pez</span></div></td>
                        <td><span class="amount-pill">¥30</span></td>
                        <td class="date-cell">2025-07-15</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">16</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill">¥50</span></td>
                        <td class="date-cell">2025-07-15</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">15</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill amount-lg">¥215</span></td>
                        <td class="date-cell">2025-07-14</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">14</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill amount-cloud">云账号</span></td>
                        <td class="date-cell">2025-04-13</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">13</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill amount-cloud">云账号</span></td>
                        <td class="date-cell">2025-04-13</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">12</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-teal">X</div><span>xdfaka</span></div></td>
                        <td><span class="amount-pill">¥68</span></td>
                        <td class="date-cell">2025-04-13</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">11</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill amount-cloud">云账号</span></td>
                        <td class="date-cell">2025-04-07</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">10</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill">¥50</span></td>
                        <td class="date-cell">2025-04-05</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">9</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill amount-sm">¥9.9</span></td>
                        <td class="date-cell">2025-04-01</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">8</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill amount-sm">¥10</span></td>
                        <td class="date-cell">2025-04-01</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">7</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill amount-cloud">云账号</span></td>
                        <td class="date-cell">2025-03-25</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">6</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-amber">柯</div><span>柯南(@KN_001)</span></div></td>
                        <td><span class="amount-pill amount-cloud">云账号</span></td>
                        <td class="date-cell">2025-03-15</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">5</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill amount-cloud">云账号</span></td>
                        <td class="date-cell">2025-03-08</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">4</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill amount-sm">¥9.9</span></td>
                        <td class="date-cell">2025-03-06</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">3</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-amber">柯</div><span>柯南(@KN_001)</span></div></td>
                        <td><span class="amount-pill amount-lg">¥100</span></td>
                        <td class="date-cell">2025-03-01</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">2</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill amount-lg">¥200</span></td>
                        <td class="date-cell">2025-02-15</td>
                    </tr>
                    <tr>
                        <td><span class="rank-num">1</span></td>
                        <td><div class="donor-cell"><div class="donor-avatar av-gray">匿</div><span>匿名用户</span></div></td>
                        <td><span class="amount-pill">¥50</span></td>
                        <td class="date-cell">2024-11-05</td>
                    </tr>
                    </tbody>
                </table>
            </div>
        </div>
    </div>
</section>

<!-- ── Footer ── -->
<footer class="footer">
    <div class="container footer-inner">
        <p>&copy; 2024-2026 OCI-START VPS Management System. Made with <i class="fas fa-heart" style="color:#f87171;"></i> by doubleDimple</p>
        <a href="https://blogger.objboy.com/" target="_blank" class="footer-link">
            <i class="fas fa-blog"></i>${msg.get("index.footer.blog")}
        </a>
    </div>
</footer>

<script>
    window.I18N = {
        index_newVersion_change: "${msg.get('index.newVersion.change')}",
        index_newVersion_use: "${msg.get('index.newVersion.use')}",
        index_already_newVersion: "${msg.get('index.already.newVersion')}",
        index_newVersion: "${msg.get('index.newVersion')}",
        index_redirect_suffix: "${msg.get('index.redirect.suffix')}",
        index_cancel_autoStep: "${msg.get('index.cancel.autoStep')}",
        index_already_stopStep: "${msg.get('index.already.stopStep')}",
    };
</script>
<script src="/js/system/index.js"></script>
</body>
</html>
