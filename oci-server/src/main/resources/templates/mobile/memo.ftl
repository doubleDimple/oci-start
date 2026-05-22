<#import "layout.ftl" as layout>
<@layout.page title="笔记本" activePage="memo">

<style>
/* ── 笔记列表 ──────────────────────── */
.mob-memo-list { padding: 0 0 80px; }
.mob-memo-card {
    background: var(--mob-card);
    border: 1px solid var(--mob-border);
    border-radius: 12px;
    padding: 14px;
    margin-bottom: 10px;
    cursor: pointer;
}
.mob-memo-card:active { opacity: .85; }
.mob-memo-title { font-size: 15px; font-weight: 600; color: var(--mob-text); margin-bottom: 4px; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
.mob-memo-preview { font-size: 12px; color: var(--mob-text-muted); line-height: 1.5; display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; min-height: 18px; }
.mob-memo-footer { display: flex; align-items: center; justify-content: space-between; margin-top: 10px; }
.mob-memo-time { font-size: 11px; color: var(--mob-text-muted); }
.mob-memo-actions { display: flex; gap: 6px; }
.mob-memo-btn { padding: 4px 10px; border-radius: 6px; border: none; font-size: 11px; font-weight: 600; cursor: pointer; display: flex; align-items: center; gap: 3px; }
.mob-memo-btn-edit { background: rgba(91,138,240,0.15); color: #5b8af0; }
.mob-memo-btn-del  { background: rgba(240,71,71,0.12); color: #f04747; }
/* ── 空状态 ──────────────────────── */
.mob-memo-empty { text-align: center; padding: 60px 20px; color: var(--mob-text-muted); }
.mob-memo-empty i { font-size: 48px; margin-bottom: 12px; display: block; opacity: .4; }
/* ── FAB ──────────────────────── */
.mob-memo-fab {
    position: fixed; bottom: 72px; right: 20px; z-index: 200;
    width: 52px; height: 52px; border-radius: 50%;
    background: #1abc9c; color: #fff; border: none;
    font-size: 22px; box-shadow: 0 4px 16px rgba(26,188,156,.45);
    display: flex; align-items: center; justify-content: center; cursor: pointer;
}
/* ── 表单字段 ──────────────────────── */
.mob-memo-field { margin-bottom: 14px; }
.mob-memo-field label { display: block; font-size: 12px; font-weight: 600; color: var(--mob-text-muted); margin-bottom: 6px; }
.mob-memo-input {
    width: 100%; padding: 10px 12px; border-radius: 8px;
    border: 1px solid var(--mob-border); background: var(--mob-bg);
    color: var(--mob-text); font-size: 14px; outline: none;
    font-family: inherit; box-sizing: border-box;
}
.mob-memo-input:focus { border-color: #1abc9c; }
.mob-memo-textarea { resize: vertical; min-height: 140px; }
/* ── 查看弹框 ──────────────────────── */
.mob-memo-view-body {
    font-size: 14px; color: var(--mob-text); line-height: 1.75;
    white-space: pre-wrap; word-break: break-word;
    overflow-y: auto;
    flex: 1;
    padding: 0 16px 4px;
}
</style>

<!-- 笔记列表 -->
<div class="mob-memo-list" id="memoList">
    <div class="mob-memo-empty"><div class="mob-spinner"></div></div>
</div>

<!-- FAB -->
<button class="mob-memo-fab" onclick="memoOpenEdit(null)" title="新建笔记">
    <i class="fas fa-plus"></i>
</button>

<!-- ── 居中编辑弹框 ── -->
<div class="mob-center-overlay" id="memoEditModal" style="display:none" onclick="memoCloseEdit(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-height:90vh;overflow-y:auto">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title" id="memoEditModalTitle" style="margin:0;padding:0;border:none">新建笔记</div>
            <button class="mob-sheet-close" onclick="memoCloseEdit()"><i class="fas fa-times"></i></button>
        </div>
        <div class="mob-sheet-body">
            <div class="mob-memo-field">
                <label>标题 <span style="color:#f04747">*</span></label>
                <input id="memoTitleInput" class="mob-memo-input" type="text" placeholder="请输入标题" maxlength="100">
            </div>
            <div class="mob-memo-field">
                <label>摘要（可选）</label>
                <input id="memoSummaryInput" class="mob-memo-input" type="text" placeholder="简短描述" maxlength="200">
            </div>
            <div class="mob-memo-field">
                <label>内容 <span style="color:#f04747">*</span></label>
                <textarea id="memoContentInput" class="mob-memo-input mob-memo-textarea" placeholder="请输入笔记内容..."></textarea>
            </div>
            <div style="display:flex;gap:10px;margin-top:4px">
                <button class="mob-btn mob-btn-primary" style="flex:1" onclick="memoSave()" id="memoSaveBtn">
                    <i class="fas fa-save"></i> 保存
                </button>
                <button class="mob-btn mob-btn-outline" style="flex:1" onclick="memoCloseEdit()">取消</button>
            </div>
        </div>
    </div>
</div>

<!-- ── 查看 居中弹框 ── -->
<div class="mob-center-overlay" id="memoViewModal" style="display:none" onclick="memoCloseView(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()"
         style="max-height:88vh;display:flex;flex-direction:column;overflow:hidden">
        <!-- 标题栏（固定） -->
        <div class="mob-sheet-header" style="flex-shrink:0">
            <div style="min-width:0;flex:1">
                <div class="mob-sheet-title" id="memoViewTitle" style="margin:0;font-size:16px"></div>
                <div style="font-size:11px;color:var(--mob-text-muted);margin-top:2px" id="memoViewMeta"></div>
            </div>
            <button class="mob-sheet-close" onclick="memoCloseView()"><i class="fas fa-times"></i></button>
        </div>
        <!-- 内容区（可滚动，内容多时自动撑开直到 max-height） -->
        <div class="mob-memo-view-body" id="memoViewBody" style="padding:14px 16px;min-height:60px"></div>
        <!-- 底部按钮（固定） -->
        <div style="flex-shrink:0;display:flex;gap:10px;padding:12px 16px 16px;border-top:1px solid var(--mob-border)">
            <button class="mob-btn mob-btn-primary" style="flex:1" onclick="memoViewEdit()">
                <i class="fas fa-edit"></i> 编辑
            </button>
            <button class="mob-btn mob-btn-outline" style="flex:1" onclick="memoCloseView()">关闭</button>
        </div>
    </div>
</div>

<#noparse>
<script>
(function() {
    var _csrf = document.querySelector('meta[name="_csrf"]').content;
    var _csrfHeader = document.querySelector('meta[name="_csrf_header"]').content;
    var _editId = null;
    var _viewMemo = null;

    function fmtTime(str) {
        if (!str) return '';
        try {
            var d = new Date(str);
            if (isNaN(d)) return str;
            var now = new Date();
            var diff = Math.floor((now - d) / 1000);
            if (diff < 60) return '刚刚';
            if (diff < 3600) return Math.floor(diff / 60) + '分钟前';
            if (diff < 86400) return Math.floor(diff / 3600) + '小时前';
            var days = Math.floor(diff / 86400);
            if (days < 7) return days + '天前';
            return (d.getMonth() + 1) + '/' + d.getDate() + ' ' +
                String(d.getHours()).padStart(2, '0') + ':' + String(d.getMinutes()).padStart(2, '0');
        } catch (e) { return str; }
    }

    function escHtml(s) {
        var d = document.createElement('div');
        d.textContent = s || '';
        return d.innerHTML;
    }

    async function apiFetch(url, opts) {
        opts = opts || {};
        var headers = { 'Content-Type': 'application/json' };
        headers[_csrfHeader] = _csrf;
        var resp = await fetch(url, {
            method: opts.method || 'GET',
            headers: headers,
            body: opts.body ? JSON.stringify(opts.body) : undefined
        });
        if (!resp.ok) throw new Error('HTTP ' + resp.status);
        var ct = resp.headers.get('content-type') || '';
        if (ct.includes('application/json')) return resp.json();
        return null;
    }

    async function loadMemos() {
        var list = document.getElementById('memoList');
        list.innerHTML = '<div class="mob-memo-empty"><div class="mob-spinner"></div></div>';
        try {
            var memos = await apiFetch('/api/memos');
            if (!memos || memos.length === 0) {
                list.innerHTML = '<div class="mob-memo-empty"><i class="fas fa-sticky-note"></i><div>暂无笔记，点击右下角 + 新建</div></div>';
                return;
            }
            var html = '';
            for (var i = 0; i < memos.length; i++) {
                var m = memos[i];
                var preview = m.summary || m.content || '';
                if (preview.length > 80) preview = preview.substring(0, 80) + '…';
                html += '<div class="mob-memo-card" onclick="window.memoView(' + m.id + ')">' +
                    '<div class="mob-memo-title">' + escHtml(m.title) + '</div>' +
                    '<div class="mob-memo-preview">' + escHtml(preview) + '</div>' +
                    '<div class="mob-memo-footer">' +
                    '<span class="mob-memo-time"><i class="fas fa-clock" style="margin-right:3px"></i>' + fmtTime(m.createTime) + '</span>' +
                    '<div class="mob-memo-actions">' +
                    '<button class="mob-memo-btn mob-memo-btn-edit" onclick="event.stopPropagation();window.memoEdit(' + m.id + ')"><i class="fas fa-edit"></i> 编辑</button>' +
                    '<button class="mob-memo-btn mob-memo-btn-del" onclick="event.stopPropagation();window.memoDel(' + m.id + ')"><i class="fas fa-trash"></i> 删除</button>' +
                    '</div></div></div>';
            }
            list.innerHTML = html;
        } catch (e) {
            list.innerHTML = '<div class="mob-memo-empty"><i class="fas fa-exclamation-triangle"></i><div>加载失败，请刷新重试</div></div>';
        }
    }

    window.memoOpenEdit = function(id) {
        _editId = id;
        document.getElementById('memoEditModalTitle').textContent = id ? '编辑笔记' : '新建笔记';
        document.getElementById('memoTitleInput').value = '';
        document.getElementById('memoSummaryInput').value = '';
        document.getElementById('memoContentInput').value = '';
        if (id) {
            apiFetch('/api/memos/' + id).then(function(m) {
                document.getElementById('memoTitleInput').value = m.title || '';
                document.getElementById('memoSummaryInput').value = m.summary || '';
                document.getElementById('memoContentInput').value = m.content || '';
            }).catch(function() {});
        }
        document.getElementById('memoEditModal').style.display = 'flex';
        document.body.style.overflow = 'hidden';
        setTimeout(function() { document.getElementById('memoTitleInput').focus(); }, 100);
    };

    window.memoCloseEdit = function(e) {
        if (e && e.target !== document.getElementById('memoEditModal')) return;
        document.getElementById('memoEditModal').style.display = 'none';
        document.body.style.overflow = '';
    };

    window.memoSave = function() {
        var title = document.getElementById('memoTitleInput').value.trim();
        var summary = document.getElementById('memoSummaryInput').value.trim();
        var content = document.getElementById('memoContentInput').value.trim();
        if (!title) { mobToast('请填写标题', 'error'); return; }
        if (!content) { mobToast('请填写内容', 'error'); return; }
        var btn = document.getElementById('memoSaveBtn');
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> 保存中';
        var body = { title: title, summary: summary, content: content };
        var method = _editId ? 'PUT' : 'POST';
        var url = _editId ? '/api/memos/' + _editId : '/api/memos';
        apiFetch(url, { method: method, body: body }).then(function() {
            document.getElementById('memoEditModal').style.display = 'none';
            document.body.style.overflow = '';
            loadMemos();
            mobToast(_editId ? '已更新' : '已保存', 'success');
        }).catch(function() {
            mobToast('保存失败', 'error');
        }).finally(function() {
            btn.disabled = false;
            btn.innerHTML = '<i class="fas fa-save"></i> 保存';
        });
    };

    window.memoView = function(id) {
        document.getElementById('memoViewTitle').textContent = '加载中…';
        document.getElementById('memoViewMeta').textContent = '';
        document.getElementById('memoViewBody').textContent = '';
        document.getElementById('memoViewModal').style.display = 'flex';
        document.body.style.overflow = 'hidden';
        apiFetch('/api/memos/' + id).then(function(m) {
            _viewMemo = m;
            document.getElementById('memoViewTitle').textContent = m.title || '';
            document.getElementById('memoViewMeta').textContent =
                '创建：' + fmtTime(m.createTime) +
                (m.updateTime && m.updateTime !== m.createTime ? '  ·  更新：' + fmtTime(m.updateTime) : '');
            document.getElementById('memoViewBody').textContent = m.content || '';
        }).catch(function() {
            document.getElementById('memoViewTitle').textContent = '加载失败';
        });
    };

    window.memoCloseView = function(e) {
        if (e && e.target !== document.getElementById('memoViewModal')) return;
        document.getElementById('memoViewModal').style.display = 'none';
        document.body.style.overflow = '';
        _viewMemo = null;
    };

    window.memoViewEdit = function() {
        if (!_viewMemo) return;
        var id = _viewMemo.id;
        document.getElementById('memoViewModal').style.display = 'none';
        document.body.style.overflow = '';
        _viewMemo = null;
        window.memoOpenEdit(id);
    };

    window.memoEdit = function(id) {
        window.memoOpenEdit(id);
    };

    window.memoDel = async function(id) {
        var ok = await mobConfirm('删除笔记', '确认要删除这条笔记吗？删除后无法恢复。');
        if (!ok) return;
        try {
            await apiFetch('/api/memos/' + id, { method: 'DELETE' });
            loadMemos();
            mobToast('已删除', 'success');
        } catch (e) {
            mobToast('删除失败', 'error');
        }
    };

    document.addEventListener('DOMContentLoaded', loadMemos);
})();
</script>
</#noparse>

</@layout.page>
