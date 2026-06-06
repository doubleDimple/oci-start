<aside class="sidebar">
    <!-- 顶部:搜索框 -->
    <div class="sidebar-top">
        <div class="sidebar-search">
            <i class="fas fa-search sidebar-search-icon"></i>
            <input type="text" id="sidebarSearchInput" class="sidebar-search-input"
                   placeholder="搜索菜单..." autocomplete="off" spellcheck="false">
            <button type="button" id="sidebarSearchClear" class="sidebar-search-clear" title="清空" aria-label="清空">
                <i class="fas fa-times"></i>
            </button>
        </div>
    </div>
    <div class="sidebar-empty-hint" id="sidebarSearchEmpty" style="display:none;">
        无匹配菜单
    </div>
    <nav>
        <!-- 服务管理菜单 -->
        <div class="nav-parent <#if activePage == 'api-records'>expanded</#if>">
            <a class="nav-link" aria-expanded="false">
                <span><i class="fas fa-server"></i>${msg.get('sidebar.service.management')}</span>
                <i class="fas fa-chevron-down arrow"></i>
            </a>
            <div class="nav-children" aria-hidden="true">
                <!-- 通用菜单项 -->
                <a href="/boot/dashboard" target="biz-frame"  class="nav-link <#if activePage == 'api-dashboard'>active</#if>">
                    <i class="fas fa-chart-pie"></i>
                    <span>${msg.get('sidebar.system.monitor')}</span>
                </a>
                <a href="/resource/list" target="biz-frame" class="nav-link <#if activePage == 'api-records'>active</#if> cloud-menu" data-cloud-types="1">
                    <i class="fas fa-globe"></i>
                    <span>${msg.get('sidebar.oci.regions')}</span>
                </a>
                <a href="/tenants/list" target="biz-frame" class="nav-link <#if activePage == 'api-management'>active</#if> cloud-menu" data-cloud-types="1">
                    <i class="fas fa-users"></i>
                    <span>${msg.get('sidebar.oci.tenants')}</span>
                </a>
                <a href="/oci/list" target="biz-frame" class="nav-link <#if activePage == 'api-ociMachineList'>active</#if> cloud-menu" data-cloud-types="1">
                    <i class="fas fa-server"></i>
                    <span>${msg.get('sidebar.oci.instances')}</span>
                </a>
                <a href="/email/management" target="biz-frame" class="nav-link <#if activePage == 'oci-email-management'>active</#if> cloud-menu" data-cloud-types="1">
                    <i class="fas fa-envelope"></i>
                    <span>${msg.get('sidebar.oci.email')}</span>
                </a>
                <a href="/oci/storage/page" target="biz-frame" class="nav-link <#if activePage == 'oci-object-storage'>active</#if> cloud-menu" data-cloud-types="1">
                    <i class="fas fa-database"></i>
                    <span>${msg.get('sidebar.oci.storage')}</span>
                </a>
                <a href="/boot/fullBootList" target="biz-frame"  class="nav-link <#if activePage == 'api-fullBootList'>active</#if> cloud-menu" data-cloud-types="1">
                    <i class="fas fa-play-circle"></i>
                    <span>${msg.get('sidebar.oci.boot')}</span>
                </a>
                <a href="/system/ai/models" target="biz-frame" class="nav-link <#if activePage == 'ai-models'>active</#if> cloud-menu" data-cloud-types="1">
                    <i class="fas fa-brain"></i>
                    <span>${msg.get('sidebar.oci.ai')!'OCI AI管理'}</span>
                </a>

                <a href="/delayTest" target="biz-frame"  class="nav-link <#if activePage == 'api-delayTest'>active</#if> cloud-menu" data-cloud-types="1">
                    <i class="fas fa-tachometer-alt"></i>
                    <span>${msg.get("speedTest.test")}</span>
                </a>

                <a href="/main?path=/system/openLogs&active=api-openLog" target="_blank" rel="noopener noreferrer" class="nav-link <#if activePage == 'api-openLog'>active</#if> cloud-menu" data-cloud-types="1">
                    <i class="fas fa-tachometer-alt"></i>
                    <span>${msg.get("tencent.ociLog")}</span>
                </a>

                <!-- GCP菜单 -->
                <a href="/tenants/list" target="biz-frame" class="nav-link <#if activePage == 'api-management'>active</#if> cloud-menu" data-cloud-types="2">
                    <i class="fab fa-google"></i>
                    <span>${msg.get('sidebar.gcp.accounts')}</span>
                </a>
                <a href="/other/instances/list" target="biz-frame" class="nav-link <#if activePage == 'api-ociBootList'>active</#if> cloud-menu" data-cloud-types="2">
                    <i class="fas fa-server"></i>
                    <span>${msg.get('sidebar.gcp.instances')}</span>
                </a>

                <!-- Azure菜单 -->
                <a href="/azure/vms" target="biz-frame" class="nav-link cloud-menu" data-cloud-types="3">
                    <i class="fab fa-microsoft"></i>
                    <span>${msg.get('sidebar.azure.vms')}</span>
                </a>
                <a href="/azure/resources" target="biz-frame" class="nav-link cloud-menu" data-cloud-types="3">
                    <i class="fas fa-layer-group"></i>
                    <span>${msg.get('sidebar.azure.resources')}</span>
                </a>
                <a href="/azure/storage" target="biz-frame" class="nav-link cloud-menu" data-cloud-types="3">
                    <i class="fas fa-hdd"></i>
                    <span>${msg.get('sidebar.azure.storage')}</span>
                </a>
                <a href="/azure/networks" target="biz-frame" class="nav-link cloud-menu" data-cloud-types="3">
                    <i class="fas fa-network-wired"></i>
                    <span>${msg.get('sidebar.azure.networks')}</span>
                </a>

                <!-- AWS菜单 -->
                <a href="/aws/ec2" target="biz-frame" class="nav-link cloud-menu" data-cloud-types="4">
                    <i class="fab fa-aws"></i>
                    <span>${msg.get('sidebar.aws.ec2')}</span>
                </a>
                <a href="/aws/s3" target="biz-frame" class="nav-link cloud-menu" data-cloud-types="4">
                    <i class="fas fa-cloud-upload-alt"></i>
                    <span>${msg.get('sidebar.aws.s3')}</span>
                </a>
                <a href="/aws/lambda" target="biz-frame" class="nav-link cloud-menu" data-cloud-types="4">
                    <i class="fas fa-code"></i>
                    <span>${msg.get('sidebar.aws.lambda')}</span>
                </a>
                <a href="/aws/rds" target="biz-frame" class="nav-link cloud-menu" data-cloud-types="4">
                    <i class="fas fa-database"></i>
                    <span>${msg.get('sidebar.aws.rds')}</span>
                </a>
            </div>
        </div>

        <!-- 代理管理菜单 -->
        <div class="nav-parent">
            <a class="nav-link" aria-expanded="false">
                <span><i class="fas fa-exchange-alt"></i>${msg.get('sidebar.proxy.management')}</span>
                <i class="fas fa-chevron-down arrow"></i>
            </a>
            <div class="nav-children"  aria-hidden="true">
                <a href="/system/domainSettings" target="biz-frame" class="nav-link <#if activePage == 'domain-settings'>active</#if>">
                    <i class="fas fa-key"></i>
                    <span>${msg.get('sidebar.key.config')}</span>
                </a>
                <a href="/dns/cloudflare" target="biz-frame" class="nav-link <#if activePage == 'cloudflare-servers'>active</#if>">
                    <i class="fas fa-globe"></i>
                    <span>${msg.get('sidebar.cf.management')}</span>
                </a>
                <a href="/dns/edgeone" target="biz-frame" class="nav-link <#if activePage == 'edgeOne-servers'>active</#if>">
                    <i class="fas fa-globe"></i>
                    <span>${msg.get('sidebar.eo.management')}</span>
                </a>
               <#-- <a href="/ssl/nginx/management" target="biz-frame" class="nav-link <#if activePage == 'nginx-management'>active</#if>">
                    <i class="fas fa-server"></i>
                    <span>${msg.get('sidebar.nginx.management')}</span>
                </a>-->
            </div>
        </div>

        <!-- VPS管理菜单 -->
        <div class="nav-parent">
            <a class="nav-link" aria-expanded="false">
                <span><i class="fas fa-server"></i>${msg.get('sidebar.vps.management')}</span>
                <i class="fas fa-chevron-down arrow"></i>
            </a>
            <div class="nav-children" aria-hidden="true">
                <a href="/vps/instances/list" target="biz-frame" class="nav-link <#if activePage == 'vps-instances'>active</#if>">
                    <i class="fas fa-list"></i>
                    <span>${msg.get('sidebar.instance.list')}</span>
                </a>
            </div>
        </div>

        <!-- 系统管理菜单 -->
        <div class="nav-parent">
            <a class="nav-link" aria-expanded="false">
                <span><i class="fas fa-cog"></i>${msg.get('sidebar.system.management')}</span>
                <i class="fas fa-chevron-down arrow"></i>
            </a>
            <div class="nav-children" aria-hidden="true">
                <a href="/system/ipSettings" target="biz-frame" class="nav-link  <#if activePage == 'ip-settings'>active</#if> cloud-menu" data-cloud-types="1">
                    <i class="fas fa-shield-alt"></i>
                    <span>${msg.get('sidebar.quality.management')}</span>
                </a>
                <a href="/main?path=/system/logs&active=api-logs" target="_blank" rel="noopener noreferrer" class="nav-link <#if activePage == 'api-logs'>active</#if>">
                    <i class="fas fa-file-alt"></i>
                    <span>${msg.get('sidebar.system.logs')}</span>
                </a>
                <a href="/system/settings" target="biz-frame" class="nav-link <#if activePage == 'api-settings'>active</#if>">
                    <i class="fas fa-sliders-h"></i>
                    <span>${msg.get('sidebar.security.management')}</span>
                </a>
                <#--<a href="/mfa/page" class="nav-link <#if activePage == 'api-mfa'>active</#if>">
                    <i class="fas fa-mobile-alt"></i>
                    <span>${messages.mfaBackup!'MFA备份'}</span>
                </a>-->
                <a href="/vpnProxy/page" target="biz-frame" class="nav-link <#if activePage == 'vpnProxy-management'>active</#if>">
                    <i class="fas fa-exchange-alt"></i>
                    <span>${msg.get('sidebar.proxy.config')}</span>
                </a>
            </div>
        </div>

        <!-- 我的工具菜单 -->
        <div class="nav-parent">
            <a class="nav-link" aria-expanded="false">
                <span><i class="fas fa-cog"></i>${msg.get('sidebar.my.tools')}</span>
                <i class="fas fa-chevron-down arrow"></i>
            </a>
            <div class="nav-children" aria-hidden="true">
                <a href="/system/notifySettings" target="biz-frame" class="nav-link <#if activePage == 'api-notifySettings'>active</#if>">
                    <i class="fas fa-bell"></i>
                    <span>${msg.get('sidebar.notify.management')}</span>
                </a>
                <a href="/system/memPage" target="biz-frame" class="nav-link <#if activePage == 'api-memPage'>active</#if>">
                    <i class="fas fa-book"></i>
                    <span>${msg.get('sidebar.note.management')}</span>
                </a>
                <a href="/migration/migPage" target="biz-frame" class="nav-link <#if activePage == 'api-migPage'>active</#if>">
                    <i class="fas fa-arrows-alt-h"></i>
                    <span>${msg.get('sidebar.data.migration')}</span>
                </a>
                <a href="/mfa/page" target="biz-frame" class="nav-link <#if activePage == 'api-mfa'>active</#if>">
                    <i class="fas fa-mobile-alt"></i>
                    <span>${msg.get('sidebar.mfa.backup')}</span>
                </a>
                <#--<a href="/ssh/terminal" class="nav-link <#if activePage == 'ssh-terminal'>active</#if>">
                    <i class="fas fa-terminal"></i>
                    <span>${messages.sshTerminal!'终端连接'}</span>
                </a>-->
            </div>
        </div>

        <!-- 开发者管理菜单 -->
        <div class="nav-parent">
            <a class="nav-link" aria-expanded="false">
                <span><i class="fas fa-code"></i>${msg.get('sidebar.dev.config')}</span>
                <i class="fas fa-chevron-down arrow"></i>
            </a>
            <div class="nav-children" aria-hidden="true">
                <a href="/system/apiTokens" target="biz-frame" class="nav-link <#if activePage == 'api-tokens'>active</#if>">
                    <i class="fas fa-key"></i>
                    <span>${msg.get('sidebar.token.config')}</span>
                </a>
            </div>
        </div>
        <#--<div class="nav-parent">
            <a class="nav-link" aria-expanded="false">
                <span><i class="fas fa-info-circle"></i>${messages.projectDescription!'项目说明'}</span>
                <i class="fas fa-chevron-down arrow"></i>
            </a>
            <div class="nav-children" aria-hidden="true">
                <a href="/about/author" target="biz-frame" class="nav-link <#if activePage == 'about-author'>active</#if>">
                    <i class="fas fa-user"></i>
                    <span>${messages.aboutAuthor!'关于项目'}</span>
                </a>
            </div>
        </div>-->
    </nav>
    <!-- 底部:折叠按钮 -->
    <div class="sidebar-bottom">
        <button type="button" id="sidebarToggleBtn" class="sidebar-collapse-btn"
                aria-label="切换菜单" title="收起/展开">
            <i class="fas fa-chevron-left" id="sidebarToggleIcon"></i>
        </button>
    </div>
</aside>

<link rel="stylesheet" href="/css/app/sidebar.css">
