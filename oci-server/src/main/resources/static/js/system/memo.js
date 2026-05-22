let csrfToken, csrfHeaderName;

// 全局变量
let quill;
let currentEditingId = null;
const API_BASE = '/api/memos';

const i18n = window.I18N;
function toggleNoteEditor() {
    const editorCard = document.getElementById('noteEditorCard');
    const toggleBtn = document.getElementById('toggleEditorBtn');

    if (editorCard.style.display === 'none') {
        // 显示编辑器
        editorCard.style.display = 'block';
        toggleBtn.innerHTML = '<i class="fas fa-minus"></i>'+ i18n.memo_editor_hide;;

        // 滚动到编辑器
        setTimeout(function() {
            editorCard.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
            document.getElementById('noteTitle').focus();
        }, 100);
    } else {
        // 隐藏编辑器
        hideNoteEditor();
    }
}

// 隐藏笔记编辑器
function hideNoteEditor() {
    const editorCard = document.getElementById('noteEditorCard');
    const toggleBtn = document.getElementById('toggleEditorBtn');

    editorCard.style.display = 'none';
    toggleBtn.innerHTML = '<i class="fas fa-plus"></i>'+ i18n.memo_editor_show;

    // 如果在编辑模式，取消编辑
    if (currentEditingId) {
        cancelEdit();
    } else {
        clearEditor();
    }
}

// 初始化富文本编辑器
function initQuillEditor() {
    quill = new Quill('#editor', {
        modules: {
            toolbar: '#toolbar'
        },
        theme: 'snow',
        placeholder: i18n.memo_form_content_placeholder
    });
}

// 获取CSRF token
function getCSRFToken() {
    const token = document.querySelector('meta[name="_csrf"]');
    const header = document.querySelector('meta[name="_csrf_header"]');
    return {
        token: token ? token.getAttribute('content') : null,
        header: header ? header.getAttribute('content') : 'X-CSRF-TOKEN'
    };
}

function showErrorAlert(message) {
    Swal.fire({
        icon: 'error',
        title: 'Error',
        text: message,
        confirmButtonText: i18n.common_confirm
    });
}

async function apiRequest(url, options) {
    options = options || {};

    const csrf = getCSRFToken();
    const defaultOptions = {
        headers: {
            'Content-Type': 'application/json'
        }
    };

    if (csrf.token) {
        defaultOptions.headers[csrf.header] = csrf.token;
    }

    const finalOptions = {
        headers: Object.assign({}, defaultOptions.headers, options.headers || {})
    };

    if (options.method) finalOptions.method = options.method;
    if (options.body) finalOptions.body = options.body;

    try {
        const response = await fetch(url, finalOptions);
        if (!response.ok) {
            const errorText = await response.text();
            throw new Error(errorText || 'HTTP ' + response.status);
        }

        const contentType = response.headers.get('content-type');
        if (contentType && contentType.includes('application/json')) {
            return await response.json();
        }
        return null;
    } catch (error) {
        console.error('API请求失败:', error);
        throw error;
    } finally {
        hideLoading();
    }
}

// 获取所有笔记
async function getNotes() {
    try {
        const notes = await apiRequest(API_BASE);
        return notes || [];
    } catch (error) {
        showErrorAlert('获取笔记失败: ' + error.message);
        return [];
    }
}

// 保存笔记
async function saveNote() {
    const title = document.getElementById('noteTitle').value.trim();
    const summary = document.getElementById('noteSummary').value.trim();
    const htmlContent = quill.root.innerHTML;
    const textContent = quill.getText().trim();

    if (!title) {
        showErrorAlert(i18n.memo_msg_title_required);
        return;
    }

    if (!textContent) {
        showErrorAlert(i18n.memo_msg_content_required);
        return;
    }

    const saveBtn = document.getElementById('saveBtn');
    const originalText = saveBtn.innerHTML;

    try {
        saveBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> ' + i18n.memo_msg_save_loading;
        saveBtn.disabled = true;

        const memo = {
            title: title,
            summary: summary,
            content: textContent,
            htmlContent: htmlContent
        };

        await apiRequest(API_BASE, {
            method: 'POST',
            body: JSON.stringify(memo)
        });

        clearEditor();
        await renderNotes();

        // 保存成功后隐藏编辑器
        hideNoteEditor();
    } catch (error) {
        showErrorAlert(i18n.memo_msg_save_fail);
    } finally {
        saveBtn.innerHTML = originalText;
        saveBtn.disabled = false;
    }
}

// 更新笔记
async function updateNote() {
    if (!currentEditingId) {
        showErrorAlert(i18n.memo_msg_no_editing);
        return;
    }

    const title = document.getElementById('noteTitle').value.trim();
    const summary = document.getElementById('noteSummary').value.trim();
    const htmlContent = quill.root.innerHTML;
    const textContent = quill.getText().trim();

    if (!title) {showErrorAlert(i18n.memo_msg_title_required);return;}
    if (!textContent) {showErrorAlert(i18n.memo_msg_content_required);return;}

    const updateBtn = document.getElementById('updateBtn');
    const originalText = updateBtn.innerHTML;

    try {
        updateBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i>'+ i18n.memo_msg_update_loading;
        updateBtn.disabled = true;

        const memo = {
            title: title,
            summary: summary,
            content: textContent,
            htmlContent: htmlContent
        };

        await apiRequest(API_BASE + '/' + currentEditingId, {
            method: 'PUT',
            body: JSON.stringify(memo)
        });

        clearEditor();
        cancelEdit();
        await renderNotes();
    } catch (error) {
        showErrorAlert(i18n.memo_msg_update_fail);
    } finally {
        updateBtn.innerHTML = originalText;
        updateBtn.disabled = false;
    }
}

// 删除笔记
async function deleteNote(id, event) {
    event.stopPropagation();

    const result = await Swal.fire({
        title: i18n.memo_msg_delete_confirm,
        icon: 'warning',
        showCancelButton: true,
        confirmButtonColor: '#ff6b6b',
        cancelButtonColor: '#6c757d',
        confirmButtonText: i18n.common_confirm,
        cancelButtonText: i18n.common_cancel
    });

    if (result.isConfirmed) {
        try {
            await apiRequest(API_BASE + '/' + id, {
                method: 'DELETE'
            });

            if (currentEditingId === id) {
                cancelEdit();
                clearEditor();
            }

            await renderNotes();
        } catch (error) {
            showErrorAlert(i18n.memo_msg_delete_fail);
        }
    }
}

// 编辑笔记
async function editNote(id, event) {
    event.stopPropagation();

    try {
        const memo = await apiRequest(API_BASE + '/' + id);
        if (memo) {
            document.getElementById('noteTitle').value = memo.title;

            // 设置富文本内容
            if (memo.htmlContent) {
                quill.root.innerHTML = memo.htmlContent;
            } else {
                quill.setText(memo.content || '');
            }

            // 切换到编辑模式
            currentEditingId = id;
            document.getElementById('editorTitle').textContent = i18n.memo_editor_title_edit;
            document.getElementById('saveBtn').style.display = 'none';
            document.getElementById('updateBtn').style.display = 'inline-flex';
            document.getElementById('cancelBtn').style.display = 'inline-flex';

            // 显示编辑器（如果隐藏的话）
            const editorCard = document.getElementById('noteEditorCard');
            const toggleBtn = document.getElementById('toggleEditorBtn');
            if (editorCard.style.display === 'none') {
                editorCard.style.display = 'block';
                toggleBtn.innerHTML = '<i class="fas fa-minus"></i> '+ i18n.memo_editor_hide;
            }

            // 滚动到编辑器
            document.querySelector('.note-editor-card').scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
            document.getElementById('noteTitle').focus();
        }
    } catch (error) {
        showErrorAlert(i18n.memo_msg_load_fail);
    }
}

// 取消编辑
function cancelEdit() {
    currentEditingId = null;
    document.getElementById('editorTitle').textContent = i18n.memo_editor_title_create;
    document.getElementById('saveBtn').style.display = 'inline-flex';
    document.getElementById('updateBtn').style.display = 'none';
    document.getElementById('cancelBtn').style.display = 'none';
    clearEditor();

    // 取消编辑后隐藏编辑器
    hideNoteEditor();
}

// 清空编辑器
function clearEditor() {
    document.getElementById('noteTitle').value = '';
    document.getElementById('noteSummary').value = '';
    quill.setContents([]);
}

// 查看笔记详情
async function viewNote(id) {
    try {
        const memo = await apiRequest(API_BASE + '/' + id);
        if (memo) {
            await Swal.fire({
                title: memo.title,
                html: '<div style="text-align: left; max-height: 400px; overflow-y: auto;">' +
                    '<div style="margin-bottom: 15px; padding: 10px; background: #f8f9fa; border-radius: 4px; font-size: 12px; color: #666;">' +
                    '<div><i class="fas fa-clock"></i> ' + i18n.memo_detail_create_time + formatDate(memo.createTime) + '</div>' +
                    '<div style="margin-top: 5px;"><i class="fas fa-edit"></i> ' + i18n.memo_detail_update_time + formatDate(memo.updateTime) + '</div>' +
                    (memo.summary ? '<div style="margin-top: 5px;"><i class="fas fa-info-circle"></i> ' + i18n.memo_detail_summary + escapeHtml(memo.summary) + '</div>' : '') +
                    '</div>' +
                    '<div style="border: 1px solid #e0e0e0; border-radius: 4px; padding: 15px; background: white;">' +
                    (memo.htmlContent || escapeHtml(memo.content || '')) +
                    '</div>' +
                    '</div>',
                width: '80%',
                maxWidth: '800px',
                showCancelButton: true,
                confirmButtonText: '<i class="fas fa-edit"></i> ' + i18n.memo_btn_edit,
                cancelButtonText: '<i class="fas fa-times"></i> ' + i18n.memo_btn_close,
                confirmButtonColor: '#2196f3',
                cancelButtonColor: '#6c757d'
            }).then(function(result) {
                if (result.isConfirmed) {
                    editNote(id, { stopPropagation: function() {} });
                }
            });
        }
    } catch (error) {
        showErrorAlert(i18n.memo_msg_load_fail);
    }
}

// 渲染笔记列表
async function renderNotes() {
    const notesGrid = document.getElementById('notesGrid');

    try {
        // 显示加载状态
        notesGrid.innerHTML =
            '<div class="notes-status loading">' +
            '<div class="loading-spinner"></div>' +
            '<div>' + i18n.memo_status_loading + '</div>' +
            '</div>';

        const notes = await getNotes();

        if (notes.length === 0) {
            notesGrid.innerHTML =
                '<div class="notes-status no-notes">' +
                '<div class="no-notes-icon"><i class="fas fa-sticky-note"></i></div>' +
                '<div class="no-notes-text">' + i18n.memo_status_empty + '</div>' +
                '</div>';
            return;
        }

        // 渲染笔记卡片
        let htmlStr = '';
        for (let i = 0; i < notes.length; i++) {
            const note = notes[i];
            const formattedDate = formatDate(note.createTime || note.date);
            const textPreview = (note.summary && note.summary.length > 80) ?
                note.summary.substring(0, 80) + '...' : (note.summary || '');

            htmlStr += '<div class="note-card" onclick="viewNote(' + note.id + ')">' +
                '<div class="note-card-header">' +
                '<h4 class="note-card-title">' + escapeHtml(note.title) + '</h4>' +
                '<div class="note-card-date"><i class="fas fa-clock"></i>' + formattedDate + '</div>' +
                '</div>' +
                '<div class="note-card-body">' +
                '<div class="note-card-preview">' + escapeHtml(textPreview) + '</div>' +
                '</div>' +
                '<div class="note-card-footer">' +
                '<button class="note-action-btn btn-edit" onclick="editNote(' + note.id + ', event)">' +
                '<i class="fas fa-edit"></i> ' + i18n.memo_btn_edit + '</button>' +
                '<button class="note-action-btn btn-delete" onclick="deleteNote(' + note.id + ', event)">' +
                '<i class="fas fa-trash"></i> ' + i18n.memo_btn_delete + '</button>' +
                '</div>' +
                '</div>';
        }

        notesGrid.innerHTML = htmlStr;
    } catch (error) {
        notesGrid.innerHTML =
            '<div class="notes-status">' +
            '<div style="color: var(--accent-red); margin-bottom: 8px;"><i class="fas fa-exclamation-triangle"></i></div>' +
            '<div>' + i18n.memo_status_load_error + ' ' + error.message + '</div>' +
            '<button class="btn btn-primary" onclick="renderNotes()" style="margin-top: 12px;">' +
            '<i class="fas fa-redo"></i> ' + i18n.memo_btn_retry + '</button>' +
            '</div>';
    }
}

// 格式化日期
function formatDate(dateString) {
    if (!dateString) return '???';
    try {
        const date = new Date(dateString);
        if (isNaN(date.getTime())) return dateString;
        const now = new Date();
        const diff = now - date;
        const days = Math.floor(diff / (1000 * 60 * 60 * 24));
        if (days === 0) return date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
        else if (days === 1) return 'Yesterday ' + date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' });
        else if (days < 7) return days + ' days ago';
        else return date.toLocaleDateString('zh-CN', { year: 'numeric', month: '2-digit', day: '2-digit' });
    } catch (e) { return dateString; }
}

// HTML转义函数
function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
}

// 页面初始化
document.addEventListener('DOMContentLoaded', function() {
    csrfToken = document.querySelector('meta[name="_csrf"]').content;
    csrfHeaderName = document.querySelector('meta[name="_csrf_header"]').content;
    // 初始化富文本编辑器
    initQuillEditor();

    // 初始化加载笔记
    renderNotes();

    // 侧边栏功能
    const navParents = document.querySelectorAll('.nav-parent');
    for (let i = 0; i < navParents.length; i++) {
        const parent = navParents[i];
        const parentLink = parent.querySelector('.nav-link');
        if (parentLink) {
            parentLink.addEventListener('click', function(e) {
                e.preventDefault();
                parent.classList.toggle('expanded');
            });
        }
    }

    // 展开当前活动菜单
    const activeLink = document.querySelector('.nav-link.active');
    if (activeLink) {
        const parent = activeLink.closest('.nav-parent');
        if (parent) {
            parent.classList.add('expanded');
        }
    }

    // 添加键盘快捷键支持
    document.addEventListener('keydown', function(e) {
        // Ctrl+Enter 或 Cmd+Enter 快速保存/更新
        if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') {
            e.preventDefault();
            if (currentEditingId) {
                updateNote();
            } else {
                saveNote();
            }
        }

        // Esc 取消编辑
        if (e.key === 'Escape' && currentEditingId) {
            e.preventDefault();
            cancelEdit();
        }
    });
});
