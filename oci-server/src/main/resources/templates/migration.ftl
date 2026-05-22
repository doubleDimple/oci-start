<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 数据迁移</title>

    <!-- CSRF -->
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">

    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link rel="stylesheet" href="/css/app/migration.css">
    <link rel="stylesheet" href="/css/common/loading.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <script src="/js/sweetalert2.min.js"></script>
</head>

<body>

<!-- 顶部导航栏 -->
<#--<#include "common/header.ftl" />-->

<div class="layout">

    <!-- 左侧菜单 -->
    <#--<#include "common/sidebar.ftl" />-->

    <!-- 主体内容 -->
    <main class="main-content">

        <!-- 全局提示 -->
        <div id="errorAlert" class="alert alert-error">
            <i class="fas fa-exclamation-circle"></i>
            <span id="errorMessage"></span>
        </div>
        <div id="successAlert" class="alert alert-success">
            <i class="fas fa-check-circle"></i>
            <span id="successMessage"></span>
        </div>

        <div class="page-card">

            <!-- 页面标题 -->
            <div class="page-header">
                <h1 class="page-title">
                    <i class="fas fa-exchange-alt"></i>
                    <span>${msg.get('migration.export.title')} &amp; ${msg.get('migration.import.title')}</span>
                </h1>
                <p class="page-description">
                    <i class="fas fa-shield-alt"></i>
                    ${msg.get('migration.export.encrypted_label')} ${msg.get('migration.export.encrypted_desc')}
                </p>
            </div>

            <!-- 两列卡片布局 -->
            <div class="migration-grid">

                <!-- ═══════════ 数据导出卡片 ═══════════ -->
                <div class="migration-card">
                    <div class="migration-card-header export-header">
                        <h3 class="migration-card-title">
                            <i class="fas fa-file-export"></i>
                            ${msg.get('migration.export.title')}
                        </h3>
                        <span class="migration-card-badge badge-export">
                            <i class="fas fa-download"></i> Export
                        </span>
                    </div>

                    <div class="migration-card-body">
                        <div class="migration-info-box">
                            <i class="fas fa-info-circle migration-info-icon"></i>
                            <p class="migration-info-text">${msg.get('migration.export.desc')}</p>
                        </div>

                        <div class="migration-steps">
                            <div class="migration-step">
                                <span class="step-num">1</span>
                                <span class="step-text">${msg.get('migration.export.encrypted_label')}</span>
                            </div>
                            <div class="migration-step">
                                <span class="step-num">2</span>
                                <span class="step-text">${msg.get('migration.export.encrypted_desc')}</span>
                            </div>
                        </div>
                    </div>

                    <div class="migration-card-footer">
                        <button id="btnExportEncrypted" class="btn btn-export">
                            <i class="fas fa-lock"></i> ${msg.get('migration.export.btn')}
                        </button>
                    </div>
                </div>

                <!-- ═══════════ 数据导入卡片 ═══════════ -->
                <div class="migration-card">
                    <div class="migration-card-header import-header">
                        <h3 class="migration-card-title">
                            <i class="fas fa-file-import"></i>
                            ${msg.get('migration.import.title')}
                        </h3>
                        <span class="migration-card-badge badge-import">
                            <i class="fas fa-upload"></i> Import
                        </span>
                    </div>

                    <div class="migration-card-body">

                        <!-- 导入模式 -->
                        <div class="form-group">
                            <label class="form-label">
                                <i class="fas fa-sliders-h"></i>
                                ${msg.get('migration.import.mode')}
                            </label>
                            <div class="import-mode-row">
                                <label class="import-mode-option">
                                    <input type="radio" name="importMode" value="encrypted">
                                    <span class="import-mode-label">
                                        <i class="fas fa-file-archive"></i>
                                        ${msg.get('migration.import.mode.file')}
                                    </span>
                                </label>
                            </div>
                        </div>

                        <!-- 文件上传区 -->
                        <div class="form-group">
                            <label class="form-label">
                                <i class="fas fa-paperclip"></i>
                                ${msg.get('migration.import.select_file')}
                            </label>
                            <div class="file-input-wrapper">
                                <label class="file-input-label" id="fileDropArea">
                                    <i class="fas fa-cloud-upload-alt file-upload-icon"></i>
                                    <span id="fileLabelText" class="file-upload-text">${msg.get('migration.import.drag_tip')}</span>
                                    <span class="file-upload-hint">.enc</span>
                                    <input type="file" id="sqlFileInput" accept=".enc">
                                </label>
                            </div>
                        </div>

                        <!-- Master Key 输入 -->
                        <div class="form-group" id="masterKeyGroup" style="display:none;">
                            <label class="form-label" for="masterKeyInput">
                                <i class="fas fa-key"></i>
                                ${msg.get('migration.import.secret_label')}
                            </label>
                            <div class="master-key-wrapper">
                                <i class="fas fa-lock master-key-prefix-icon"></i>
                                <input type="text"
                                       class="form-control form-control-prefixed"
                                       id="masterKeyInput"
                                       placeholder="${msg.get('migration.import.secret_placeholder')}">
                            </div>
                        </div>

                    </div>

                    <div class="migration-card-footer">
                        <button id="btnImport" class="btn btn-import">
                            <i class="fas fa-upload"></i> ${msg.get('migration.import.btn')}
                        </button>
                    </div>
                </div>

            </div><!-- /.migration-grid -->
        </div><!-- /.page-card -->
    </main>
</div>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script>
    window.migrationI18n = {
        exporting: "${msg.get('migration.js.exporting')?js_string}",
        exportSuccess: "${msg.get('migration.js.export_success')?js_string}",
        exportFail: "${msg.get('migration.js.export_fail')?js_string}",
        importing: "${msg.get('migration.js.importing')?js_string}",
        importSuccess: "${msg.get('migration.js.import_success')?js_string}",
        importFail: "${msg.get('migration.js.import_fail')?js_string}",
        noFile: "${msg.get('migration.js.no_file')?js_string}",
        noSecret: "${msg.get('migration.js.no_secret')?js_string}",
        selectedFile: "${msg.get('migration.js.selected_file')?js_string}",
        dragTipEnc: "${msg.get('migration.import.drag_tip_enc')?js_string}",
        swalTitle: "${msg.get('migration.swal.title')?js_string}",
        swalDesc: "${msg.get('migration.swal.desc')?js_string}",
        swalBtn: "${msg.get('migration.swal.btn')?js_string}",
        swalFileGenerated: "${msg.get('migration.swal.file_generated')?js_string}",
    };
</script>
<script src="/js/system/migration.js"></script>
</body>
</html>
