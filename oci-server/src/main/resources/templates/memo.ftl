<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <meta name="_csrf" content="${_csrf.token}"/>
    <meta name="_csrf_header" content="${_csrf.headerName}"/>
    <input type="hidden" name="_csrf" value="${_csrf.token}">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>VPS管理系统 - 系统设置</title>
    <script>
        (function(){var t=localStorage.getItem('oci_theme');if(t)document.documentElement.dataset.theme=t;})();
    </script>
    <link rel="stylesheet" href="/css/all.min.css">
    <link href="/css/sweetalert2.min.css" rel="stylesheet">
    <link href="/css/quill.snow.css" rel="stylesheet">
    <link rel="stylesheet" href="/css/app/memo.css">
    <link rel="stylesheet" href="/css/common/loading.css">
</head>
<body>

<#--<#include "common/header.ftl" />-->

<div class="layout">
    <#--<#include "common/sidebar.ftl" />-->

    <!-- Main Content -->
    <main class="main-content">
        <div class="settings-container">
            <!-- 页面标题和添加按钮 -->
            <div class="page-header">
                <h1 class="page-title">
                    <i class="fas fa-sticky-note"></i>
                    <span>${msg.get('memo.title.main')}</span>
                </h1>
                <button class="btn btn-primary" onclick="toggleNoteEditor()" id="toggleEditorBtn">
                    <i class="fas fa-plus"></i> ${msg.get('memo.editor.show')}
                </button>
            </div>

            <!-- 笔记编辑器卡片 -->
            <div class="note-editor-card" id="noteEditorCard" style="display: none;">'
                <div class="note-editor-header">
                    <h2 class="editor-title">
                        <i class="fas fa-pen-fancy"></i>
                        <span id="editorTitle">${msg.get('memo.editor.title.create')}</span>
                    </h2>
                </div>
                <div class="note-editor-body">
                    <form id="noteForm">
                        <div class="form-group">
                            <label class="form-label" for="noteTitle">${msg.get('memo.form.title')}</label>
                            <input type="text" id="noteTitle" class="form-control" placeholder="${msg.get('memo.form.title.placeholder')}" required>
                        </div>

                        <div class="form-group">
                            <label class="form-label" for="noteSummary">${msg.get('memo.form.summary')}</label>
                            <textarea id="noteSummary" class="form-control" rows="2" placeholder="${msg.get('memo.form.summary.placeholder')}" maxlength="200"></textarea>
                            <small class="form-tip">${msg.get('memo.form.summary.tip')}</small>
                        </div>

                        <div class="form-group">
                            <label class="form-label" for="noteContent">${msg.get('memo.form.content')}</label>
                            <div id="noteEditor">
                                <div id="toolbar">
                                    <span class="ql-formats">
                                        <select class="ql-font"></select>
                                        <select class="ql-size"></select>
                                    </span>
                                    <span class="ql-formats">
                                        <button class="ql-bold"></button>
                                        <button class="ql-italic"></button>
                                        <button class="ql-underline"></button>
                                        <button class="ql-strike"></button>
                                    </span>
                                    <span class="ql-formats">
                                        <select class="ql-color"></select>
                                        <select class="ql-background"></select>
                                    </span>
                                    <span class="ql-formats">
                                        <button class="ql-header" value="1"></button>
                                        <button class="ql-header" value="2"></button>
                                        <button class="ql-blockquote"></button>
                                        <button class="ql-code-block"></button>
                                    </span>
                                    <span class="ql-formats">
                                        <button class="ql-list" value="ordered"></button>
                                        <button class="ql-list" value="bullet"></button>
                                        <button class="ql-indent" value="-1"></button>
                                        <button class="ql-indent" value="+1"></button>
                                    </span>
                                    <span class="ql-formats">
                                        <button class="ql-link"></button>
                                        <button class="ql-image"></button>
                                    </span>
                                    <span class="ql-formats">
                                        <button class="ql-clean"></button>
                                    </span>
                                </div>
                                <div id="editor" style="min-height: 200px;"></div>
                            </div>
                        </div>

                        <div class="button-group">
                            <button type="button" class="btn btn-primary" onclick="saveNote()" id="saveBtn">
                                <i class="fas fa-save"></i> ${msg.get('memo.btn.save')}
                            </button>
                            <button type="button" class="btn btn-success" onclick="updateNote()" id="updateBtn" style="display: none;">
                                <i class="fas fa-edit"></i> ${msg.get('memo.btn.update')}
                            </button>
                            <button type="button" class="btn btn-secondary" onclick="cancelEdit()" id="cancelBtn" style="display: none;">
                                <i class="fas fa-times"></i> ${msg.get('memo.btn.cancel')}
                            </button>
                            <button type="button" class="btn btn-secondary" onclick="clearEditor()">
                                <i class="fas fa-eraser"></i> ${msg.get('memo.btn.clear')}
                            </button>
                            <button type="button" class="btn btn-secondary" onclick="hideNoteEditor()">
                                <i class="fas fa-times"></i> ${msg.get('memo.btn.close')}
                            </button>
                        </div>
                    </form>
                </div>
            </div>

            <!-- 笔记网格 -->
            <div class="notes-grid" id="notesGrid">
                <div class="notes-status loading">
                    <div class="loading-spinner"></div>
                    <div>${msg.get('memo.status.loading')}</div>
                </div>
            </div>
        </div>
    </main>
</div>

<script>
    window.I18N = {
        memo_editor_show: "${msg.get('memo.editor.show')}",
        memo_editor_hide: "${msg.get('memo.editor.hide')}",
        memo_editor_title_create: "${msg.get('memo.editor.title.create')}",
        memo_editor_title_edit: "${msg.get('memo.editor.title.edit')}",
        memo_msg_title_required: "${msg.get('memo.msg.title.required')}",
        memo_msg_content_required: "${msg.get('memo.msg.content.required')}",
        memo_msg_no_editing: "${msg.get('memo.msg.no.editing')}",
        memo_msg_save_loading: "${msg.get('memo.msg.save.loading')}",
        memo_msg_update_loading: "${msg.get('memo.msg.update.loading')}",
        memo_msg_save_success: "${msg.get('memo.msg.save.success')}",
        memo_msg_save_fail: "${msg.get('memo.msg.save.fail')}",
        memo_msg_update_success: "${msg.get('memo.msg.update.success')}",
        memo_msg_update_fail: "${msg.get('memo.msg.update.fail')}",
        memo_msg_delete_confirm: "${msg.get('memo.msg.delete.confirm')}",
        memo_msg_delete_warning: "${msg.get('memo.msg.delete.warning')}",
        memo_msg_delete_success: "${msg.get('memo.msg.delete.success')}",
        memo_msg_delete_fail: "${msg.get('memo.msg.delete.fail')}",
        memo_msg_load_fail: "${msg.get('memo.msg.load.fail')}",
        memo_status_loading: "${msg.get('memo.status.loading')}",
        memo_status_empty: "${msg.get('memo.status.empty')}",
        memo_status_load_error: "${msg.get('memo.status.load.fail')}",
        memo_detail_create_time: "${msg.get('memo.detail.create.time')}",
        memo_detail_update_time: "${msg.get('memo.detail.update.time')}",
        memo_detail_summary: "${msg.get('memo.detail.summary')}",
        memo_btn_edit: "${msg.get('memo.btn.edit')}",
        memo_btn_delete: "${msg.get('memo.btn.delete')}",
        memo_btn_retry: "${msg.get('memo.btn.retry')}",
        memo_btn_close: "${msg.get('memo.btn.close')}",
        memo_form_content_placeholder: "${msg.get('memo.form.content.placeholder')}",
        common_confirm: "${msg.get('common.confirm')}",
        common_cancel: "${msg.get('common.cancel')}",
        common_delete: "${msg.get('common.delete')}"
    };
</script>
<script src="/js/sweetalert2.min.js"></script>
<!-- Quill 富文本编辑器 JS -->
<script src="https://cdn.quilljs.com/1.3.6/quill.min.js"></script>
<script src="/js/common/request.js"></script>
<script src="/js/common/loading.js"></script>
<script src="/js/system/memo.js"></script>
</body>
</html>
