<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <script>(function(){var t=localStorage.getItem('oci_theme')||'dark';if(t==='system')t=window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';document.documentElement.dataset.theme=t;})();</script>
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
    <title>VPS管理系统 - OCI AI管理</title>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
    <link rel="stylesheet" href="/css/common/loading.css">
    <link rel="stylesheet" href="/css/common/custom-select.css">
    <link rel="stylesheet" href="/css/app/notification_settings.css">
    <link rel="stylesheet" href="/css/app/ai_model_config.css">
    <style>
        .layout { padding-top: 0; }
        .main-content { margin-left: 0; padding: 20px 24px; background: var(--main-bg); }
    </style>
</head>
<body>
<div class="layout">
    <main class="main-content">
        <div class="page-card">

            <!-- 页面标题 -->
            <div class="page-header">
                <h1 class="page-title">
                    <i class="fas fa-brain"></i>
                    <span>${msg.get('sidebar.oci.ai')!'OCI AI管理'}</span>
                </h1>
            </div>

            <!-- 租户选择栏 -->
            <div class="ai-filter-bar">
                <span class="ai-filter-label">${msg.get('aiModel.tenant')!'租户'}</span>
                <div class="ai-filter-select">
                    <select id="tenantSelect"
                            data-custom-select
                            data-searchable
                            data-placeholder="${msg.get('aiModel.selectTenant')!'选择租户'}"
                            onchange="onTenantChange()">
                        <option value="">${msg.get('aiModel.selectTenant')!'选择租户'}</option>
                    </select>
                </div>
                <div id="leftLoading" class="panel-spinner" style="display:none">
                    <i class="fas fa-spinner fa-spin"></i>
                </div>
            </div>

            <!-- 左右双面板 -->
            <div class="ai-grid">

                <!-- ── 左侧：可用 AI 模型 ── -->
                <div class="panel-card">
                    <div class="panel-header">
                        <h3 class="panel-title">
                            <i class="fas fa-robot"></i>
                            ${msg.get('aiModel.availableModels')!'可用 AI 模型'}
                        </h3>
                    </div>
                    <div class="panel-body">
                        <!-- 模型卡片列表 -->
                        <div id="modelList">
                            <div class="empty-state">
                                <i class="fas fa-hand-point-up fa-2x"></i>
                                <p>${msg.get('aiModel.selectTenantFirst')!'请先选择租户查看可用模型'}</p>
                            </div>
                        </div>

                        <!-- 分页 -->
                        <div class="ai-pagination" id="modelPagination" style="display:none">
                            <button class="page-btn" id="modelPrevBtn" onclick="changeModelPage(-1)">
                                <i class="fas fa-chevron-left"></i>
                            </button>
                            <span class="page-info" id="modelPageInfo">1 / 1</span>
                            <button class="page-btn" id="modelNextBtn" onclick="changeModelPage(1)">
                                <i class="fas fa-chevron-right"></i>
                            </button>
                        </div>
                    </div>
                </div>

                <!-- ── 右侧：已配置的模型 ── -->
                <div class="panel-card">
                    <div class="panel-header">
                        <h3 class="panel-title">
                            <i class="fas fa-cog"></i>
                            ${msg.get('aiModel.configuredModels')!'已配置的模型'}
                        </h3>
                        <div class="panel-actions">
                            <span class="tenant-link-label">
                                <i class="fas fa-link"></i>
                                ${msg.get('aiModel.linkTenant')!'关联租户'}
                            </span>
                            <label class="switch" title="${msg.get('aiModel.linkTenant')!'关联租户'}">
                                <input type="checkbox" id="tenantLinkToggle" onchange="onTenantLinkToggle()">
                                <span class="slider"></span>
                            </label>
                            <div class="panel-divider"></div>
                            <label class="switch" title="${msg.get('aiModel.enableAllAi')!'启用/禁用全部'}">
                                <input type="checkbox" id="masterToggle">
                                <span class="slider"></span>
                            </label>
                            <button class="btn btn-sm btn-secondary" onclick="loadConfigs()" title="${msg.get('storage.btn.refresh')!'刷新'}">
                                <i class="fas fa-sync-alt"></i>
                            </button>
                        </div>
                    </div>
                    <div class="panel-body">
                        <!-- 配置卡片列表 -->
                        <div id="configList">
                            <div class="empty-state">
                                <i class="fas fa-spinner fa-spin fa-2x"></i>
                            </div>
                        </div>

                        <!-- 分页 -->
                        <div class="ai-pagination" id="configPagination" style="display:none">
                            <button class="page-btn" id="configPrevBtn" onclick="changeConfigPage(-1)">
                                <i class="fas fa-chevron-left"></i>
                            </button>
                            <span class="page-info" id="configPageInfo">1 / 1</span>
                            <button class="page-btn" id="configNextBtn" onclick="changeConfigPage(1)">
                                <i class="fas fa-chevron-right"></i>
                            </button>
                        </div>
                    </div>
                </div>

            </div><!-- /.ai-grid -->
        </div><!-- /.page-card -->
    </main>
</div>

<script>
    window.I18N = {
        common_confirm:          "${msg.get('common.confirm')?js_string}",
        common_cancel:           "${msg.get('common.cancel')?js_string}",
        common_loadFail:         "${msg.get('common.loadFail')?js_string}",
        common_delete:           "${msg.get('common.delete')?js_string}",
        common_start:            "${msg.get('common.start')?js_string}",
        common_stop:             "${msg.get('common.stop')?js_string}",
        common_saving:           "${msg.get('common.saving')?js_string}",
        aiModel_noModel:         "${msg.get('aiModel.noModel')?js_string}",
        aiModel_loading:         "${msg.get('aiModel.loading')?js_string}",
        aiModel_deleteSuccess:   "${msg.get('aiModel.deleteSuccess')?js_string}",
        aiModel_delete_title:    "${msg.get('mfa.confirm.delete_title')?js_string}",
        aiModel_enableAllAi:     "${msg.get('aiModel.enableAllAi')?js_string}",
        aiModel_disableAllAi:    "${msg.get('aiModel.disableAllAi')?js_string}",
        aiModel_exeAllAi:        "${msg.get('aiModel.exeAllAi')?js_string}",
        aiModel_exeDisAllAi:     "${msg.get('aiModel.exeDisAllAi')?js_string}",
        aiModel_modelChange:     "${msg.get('aiModel.modelChange')?js_string}",
        aiModel_added:           "${msg.get('aiModel.added')?js_string}",
        aiModel_tenant:          "${msg.get('aiModel.tenant')?js_string}",
        aiModel_provider:        "${msg.get('aiModel.provider')?js_string}",
        aiModel_model:           "${msg.get('aiModel.model')?js_string}",
        aiModel_name:            "${msg.get('aiModel.name')?js_string}",
        aiModel_region:          "${msg.get('aiModel.region')?js_string}",
        aiModel_noAvailableModel:"${msg.get('aiModel.noAvailableModel')?js_string}",
        aiModel_addToConfig:     "${msg.get('aiModel.addToConfig')!'添加配置'}",
        aiModel_alreadyAdded:    "${msg.get('aiModel.alreadyAdded')!'已添加'}",
        aiModel_noModelForTenant:"${msg.get('aiModel.noModelForTenant')!'该租户暂无可用 AI 模型'}",
        aiModel_selectTenantFirst:"${msg.get('aiModel.selectTenantFirst')!'请先选择租户查看可用模型'}",
    };
</script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/common/custom-select.js"></script>
<script src="/js/system/ai_model_config.js"></script>
</body>
</html>
