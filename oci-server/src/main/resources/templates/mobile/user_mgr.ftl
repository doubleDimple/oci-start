<#import "layout.ftl" as layout>
<@layout.page title="用户管理" activePage="tenants">

<style>
/* ── 分段控制器（iOS 风格）──────────────────────── */
.um-tab-bar { display:flex;gap:2px;background:rgba(118,118,128,0.12);border-radius:11px;padding:2px;margin-bottom:16px }
.um-tab-btn { flex:1;padding:8px 4px;border-radius:9px;border:none;font-size:12px;font-weight:600;cursor:pointer;transition:all .22s cubic-bezier(.34,1.26,.64,1);display:flex;align-items:center;justify-content:center;gap:5px;background:transparent;color:rgba(60,60,67,0.6) }
html[data-theme="dark"] .um-tab-btn { color:rgba(235,235,245,0.55) }
.um-tab-btn.active { background:#fff;color:#1abc9c;box-shadow:0 1px 4px rgba(0,0,0,0.13),0 1px 2px rgba(0,0,0,0.08) }
html[data-theme="dark"] .um-tab-btn.active { background:rgba(255,255,255,0.14);color:#1abc9c;box-shadow:0 1px 4px rgba(0,0,0,0.3) }
.um-action-row { display:flex;gap:6px;margin-bottom:12px;align-items:center }
.um-icon-btn { height:34px;padding:0 12px;border-radius:8px;border:1.5px solid var(--mob-border);background:var(--mob-card);color:var(--mob-text);cursor:pointer;display:flex;align-items:center;gap:5px;font-size:12px;font-weight:600;flex-shrink:0 }
.um-icon-btn.green { border-color:rgba(26,188,156,0.4);background:rgba(26,188,156,0.1);color:#1abc9c }
.um-icon-btn.blue  { border-color:rgba(91,138,240,0.4);background:rgba(91,138,240,0.1);color:#5b8af0 }
.um-user-card { background:var(--mob-card);border-radius:12px;padding:14px;margin-bottom:10px;border:1px solid var(--mob-border) }
.um-user-avatar { width:38px;height:38px;border-radius:50%;background:rgba(26,188,156,0.15);color:#1abc9c;display:flex;align-items:center;justify-content:center;font-size:15px;font-weight:700;flex-shrink:0 }
.um-badge { display:inline-block;font-size:10px;font-weight:700;padding:2px 7px;border-radius:10px;flex-shrink:0 }
.um-badge.um-state-active { background:rgba(67,181,129,0.15);color:#43b581 }
.um-badge.um-state-inactive { background:rgba(240,71,71,0.1);color:#f04747 }
.um-email-row { display:flex;align-items:center;gap:8px;padding:10px 0;border-bottom:1px solid var(--mob-border) }
.um-email-row:last-child { border-bottom:none }
</style>

<!-- 顶部返回栏 -->
<div style="display:flex;align-items:center;gap:12px;margin-bottom:16px">
    <button onclick="window.location.href='/m/tenants?menuId='+encodeURIComponent(_umTenantId)"
            style="width:36px;height:36px;border-radius:50%;border:1.5px solid var(--mob-border);background:var(--mob-card);color:var(--mob-text);display:flex;align-items:center;justify-content:center;cursor:pointer;flex-shrink:0;padding:0">
        <i class="fas fa-chevron-left" style="font-size:13px"></i>
    </button>
    <div style="flex:1;min-width:0">
        <div style="font-size:16px;font-weight:700;color:var(--mob-text)">用户管理</div>
        <div style="font-size:11px;color:var(--mob-text-muted);overflow:hidden;text-overflow:ellipsis;white-space:nowrap" id="umTenantName">—</div>
    </div>
</div>

<!-- Tab 切换 -->
<div class="um-tab-bar">
    <button class="um-tab-btn active" id="umTabBtnUsers" onclick="umSwitchTab('users')">
        <i class="fas fa-users"></i>用户
    </button>
    <button class="um-tab-btn" id="umTabBtnNotify" onclick="umSwitchTab('notify')">
        <i class="fas fa-envelope"></i>邮箱
    </button>
    <button class="um-tab-btn" id="umTabBtnMfa" onclick="umSwitchTab('mfa')">
        <i class="fas fa-shield-alt"></i>MFA
    </button>
</div>

<!-- ═══════════ Tab: 用户 ═══════════ -->
<div id="umTabUsers">
    <!-- 操作栏 -->
    <div class="um-action-row">
        <button class="um-icon-btn green" onclick="toggleAddForm()">
            <i class="fas fa-plus"></i>新建用户
        </button>
        <button class="um-icon-btn" onclick="loadUsers()" title="刷新">
            <i class="fas fa-sync-alt"></i>
        </button>
        <button class="um-icon-btn blue" onclick="openPasswordPolicy()" title="密码策略">
            <i class="fas fa-key"></i>密码策略
        </button>
    </div>

    <!-- 添加用户表单 -->
    <div id="addUserForm" style="display:none;margin-bottom:12px">
        <div class="mob-card" style="padding:14px">
            <div style="font-size:13px;font-weight:700;color:var(--mob-text);margin-bottom:12px">
                <i class="fas fa-user-plus" style="color:#1abc9c;margin-right:6px"></i>新建用户
            </div>
            <div style="margin-bottom:10px">
                <div style="font-size:11px;color:var(--mob-text-muted);margin-bottom:4px">用户名</div>
                <input type="text" id="newUsername" class="mob-tf-input" placeholder="输入用户名" style="width:100%;box-sizing:border-box">
            </div>
            <div style="margin-bottom:10px">
                <div style="font-size:11px;color:var(--mob-text-muted);margin-bottom:4px">邮箱</div>
                <input type="email" id="newEmail" class="mob-tf-input" placeholder="输入邮箱" style="width:100%;box-sizing:border-box">
            </div>
            <div style="margin-bottom:14px;display:flex;align-items:center;gap:8px">
                <input type="checkbox" id="emailAsUsername" style="width:16px;height:16px;accent-color:var(--mob-accent)">
                <label for="emailAsUsername" style="font-size:12px;color:var(--mob-text)">以邮箱作为用户名</label>
            </div>
            <div style="display:flex;gap:8px">
                <button class="mob-btn mob-btn-outline" style="flex:1" onclick="toggleAddForm()">取消</button>
                <button class="mob-btn" style="flex:1;background:#1abc9c;color:#fff;border:none" onclick="createUser()">创建</button>
            </div>
        </div>
    </div>

    <div class="mob-loading" id="umLoading"><div class="mob-spinner"></div></div>
    <div id="umList"></div>
</div>

<!-- ═══════════ Tab: 通知邮箱 ═══════════ -->
<div id="umTabNotify" style="display:none">
    <div class="mob-card" style="padding:14px;margin-bottom:12px">
        <div style="display:flex;align-items:center;gap:8px;margin-bottom:12px">
            <i class="fas fa-bell" style="color:#5b8af0"></i>
            <span style="font-size:14px;font-weight:700;color:var(--mob-text)">通知收件人</span>
            <button class="um-icon-btn" onclick="loadNotifyEmails()" style="margin-left:auto;height:28px;padding:0 10px;font-size:11px">
                <i class="fas fa-sync-alt"></i>
            </button>
        </div>
        <div id="ntLoading" class="mob-loading" style="display:none"><div class="mob-spinner"></div></div>
        <div id="ntEmailList"></div>
        <div style="display:flex;gap:8px;margin-top:12px">
            <input type="email" id="ntNewEmail" class="mob-tf-input" placeholder="添加邮箱地址" style="flex:1">
            <button class="um-icon-btn green" onclick="ntAddEmail()" style="height:36px">
                <i class="fas fa-plus"></i>添加
            </button>
        </div>
    </div>
    <button class="mob-btn" style="width:100%;background:var(--mob-accent);color:#fff;border:none" onclick="ntSave()">
        <i class="fas fa-save" style="margin-right:6px"></i>保存设置
    </button>
</div>

<!-- ═══════════ Tab: MFA 管理 ═══════════ -->
<div id="umTabMfa" style="display:none">
    <div class="mob-loading" id="mfaLoading"><div class="mob-spinner"></div></div>
    <div id="mfaContent" style="display:none">
        <!-- 状态卡 -->
        <div class="mob-card" style="padding:16px;margin-bottom:10px">
            <div style="display:flex;align-items:center;gap:12px;margin-bottom:14px">
                <div id="mfaStatusIcon" style="width:44px;height:44px;border-radius:50%;background:rgba(91,138,240,0.1);color:#5b8af0;display:flex;align-items:center;justify-content:center;font-size:20px;flex-shrink:0">
                    <i class="fas fa-shield-alt"></i>
                </div>
                <div style="flex:1">
                    <div style="font-size:14px;font-weight:700;color:var(--mob-text)">MFA 状态</div>
                    <div id="mfaStatusText" style="font-size:12px;color:var(--mob-text-muted);margin-top:2px">加载中…</div>
                </div>
                <button class="um-icon-btn" onclick="loadMfa()" style="height:30px;padding:0 10px;font-size:11px">
                    <i class="fas fa-sync-alt"></i>刷新
                </button>
            </div>
            <!-- 邮箱 MFA -->
            <div style="border-top:1px solid var(--mob-border);padding-top:12px;margin-bottom:12px">
                <div style="font-size:12px;font-weight:600;color:var(--mob-text-muted);margin-bottom:8px">
                    <i class="fas fa-envelope" style="margin-right:4px"></i>邮箱 MFA
                </div>
                <div style="display:flex;gap:8px">
                    <button class="mob-btn mob-btn-sm" style="flex:1;background:rgba(67,181,129,0.15);color:#43b581;border:1px solid rgba(67,181,129,0.3)" onclick="setMfaEmail(true)">
                        <i class="fas fa-toggle-on" style="margin-right:4px"></i>启用
                    </button>
                    <button class="mob-btn mob-btn-sm" style="flex:1;background:rgba(240,71,71,0.1);color:#f04747;border:1px solid rgba(240,71,71,0.2)" onclick="setMfaEmail(false)">
                        <i class="fas fa-toggle-off" style="margin-right:4px"></i>关闭
                    </button>
                </div>
            </div>
            <!-- 重置 MFA -->
            <div style="border-top:1px solid var(--mob-border);padding-top:12px">
                <div style="font-size:12px;font-weight:600;color:var(--mob-text-muted);margin-bottom:6px">
                    <i class="fas fa-redo" style="margin-right:4px"></i>一键重置 MFA
                </div>
                <div style="font-size:11px;color:var(--mob-text-muted);margin-bottom:10px">
                    重置后用户下次登录需重新注册 MFA 设备。
                </div>
                <button class="mob-btn" style="width:100%;background:rgba(250,166,26,0.15);color:#faa61a;border:1px solid rgba(250,166,26,0.3)" onclick="confirmResetMfa()">
                    <i class="fas fa-redo" style="margin-right:6px"></i>执行重置
                </button>
            </div>
        </div>
    </div>
</div>

<!-- ══════════ 弹窗区域 ══════════ -->

<!-- 操作结果弹窗 -->
<div id="umResultModal" class="mob-center-overlay" style="display:none" onclick="closeUmResult(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-width:340px">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title" id="umResultTitle">操作结果</div>
            <button class="mob-sheet-close" onclick="closeUmResult()"><i class="fas fa-times"></i></button>
        </div>
        <div id="umResultBody" style="padding:16px"></div>
        <div style="padding:0 16px 16px">
            <button class="mob-btn" style="width:100%;background:var(--mob-accent);color:#fff;border:none" onclick="closeUmResult()">知道了</button>
        </div>
    </div>
</div>

<!-- 删除用户确认 -->
<div id="umDeleteModal" class="mob-center-overlay" style="display:none" onclick="closeUmDelete(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-width:320px">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title" style="color:#f04747"><i class="fas fa-exclamation-triangle" style="margin-right:6px"></i>确认删除</div>
        </div>
        <div style="padding:16px;font-size:14px;color:var(--mob-text)">
            确认删除用户 <strong id="umDeleteName" style="color:#f04747;word-break:break-all"></strong> 吗？
        </div>
        <div style="padding:0 16px 16px;display:flex;gap:8px">
            <button class="mob-btn mob-btn-outline" style="flex:1" onclick="closeUmDelete()">取消</button>
            <button class="mob-btn" style="flex:1;background:#f04747;color:#fff;border:none" onclick="doDeleteUser()">删除</button>
        </div>
    </div>
</div>

<!-- 重置密码确认 -->
<div id="umResetModal" class="mob-center-overlay" style="display:none" onclick="closeUmReset(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-width:320px">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title" style="color:#5b8af0"><i class="fas fa-key" style="margin-right:6px"></i>确认重置密码</div>
        </div>
        <div style="padding:16px;font-size:14px;color:var(--mob-text)">
            确认重置用户 <strong id="umResetName" style="color:#5b8af0;word-break:break-all"></strong> 的密码吗？操作后将生成临时密码。
        </div>
        <div style="padding:0 16px 16px;display:flex;gap:8px">
            <button class="mob-btn mob-btn-outline" style="flex:1" onclick="closeUmReset()">取消</button>
            <button class="mob-btn" style="flex:1;background:#5b8af0;color:#fff;border:none" onclick="doResetPassword()">确认重置</button>
        </div>
    </div>
</div>

<!-- 重置 MFA 确认 -->
<div id="mfaResetModal" class="mob-center-overlay" style="display:none" onclick="closeMfaReset(event)">
    <div class="mob-center-dialog" onclick="event.stopPropagation()" style="max-width:320px">
        <div class="mob-sheet-header">
            <div class="mob-sheet-title" style="color:#faa61a"><i class="fas fa-exclamation-triangle" style="margin-right:6px"></i>确认重置 MFA</div>
        </div>
        <div style="padding:16px;font-size:13px;color:var(--mob-text)">
            此操作将重置该账号所有用户的 MFA 设备，用户下次登录需重新注册。
        </div>
        <div style="padding:0 16px 16px;display:flex;gap:8px">
            <button class="mob-btn mob-btn-outline" style="flex:1" onclick="closeMfaReset()">取消</button>
            <button class="mob-btn" style="flex:1;background:#faa61a;color:#fff;border:none" onclick="doResetMfa()">确认重置</button>
        </div>
    </div>
</div>

<!-- 密码策略 居中弹框 -->
<div class="mob-tn-overlay" id="policyOverlay" onclick="closePolicySheet()"></div>
<div class="mob-tn-sheet mob-policy-modal" id="policySheet">
    <div style="padding:16px 16px 20px">
        <div style="font-size:16px;font-weight:700;color:var(--mob-text);margin-bottom:4px">
            <i class="fas fa-key" style="color:#5b8af0;margin-right:8px"></i>密码策略
        </div>
        <div style="font-size:11px;color:var(--mob-text-muted);margin-bottom:16px" id="policySubtitle">—</div>
        <div id="policyLoading" class="mob-loading" style="display:none"><div class="mob-spinner"></div></div>
        <div id="policyBody">
            <div style="display:flex;align-items:center;gap:10px;padding:14px;background:var(--mob-bg);border-radius:10px;margin-bottom:10px">
                <div style="flex:1">
                    <div style="font-size:13px;font-weight:600;color:var(--mob-text)">启用密码过期</div>
                    <div style="font-size:11px;color:var(--mob-text-muted);margin-top:2px">密码定期过期，强制用户更新</div>
                </div>
                <label style="position:relative;display:inline-block;width:48px;height:28px;cursor:pointer;flex-shrink:0">
                    <input type="checkbox" id="policyExpiry" style="opacity:0;width:0;height:0" onchange="toggleExpiryDays()">
                    <span id="policyExpiryTrack" style="position:absolute;inset:0;border-radius:28px;background:#bbb;border:2px solid #aaa;transition:.25s;cursor:pointer"></span>
                    <span id="policyExpiryThumb" style="position:absolute;left:3px;top:3px;width:22px;height:22px;border-radius:50%;background:#fff;transition:.25s;box-shadow:0 1px 4px rgba(0,0,0,0.35)"></span>
                </label>
            </div>
            <div id="policyDaysRow" style="display:none;padding:14px;background:var(--mob-bg);border-radius:10px;margin-bottom:16px">
                <div style="font-size:12px;color:var(--mob-text-muted);margin-bottom:6px">设置密码过期天数（0-365天）</div>
                <input type="number" id="policyDays" class="mob-tf-input" min="0" max="365" value="120" style="width:100%;box-sizing:border-box">
                <div style="font-size:11px;color:var(--mob-text-muted);margin-top:6px">当过期天数设置为0时，代表密码永不过期</div>
            </div>
            <button id="policyBtn" class="mob-btn" style="width:100%;background:linear-gradient(135deg,#1abc9c,#16a085);color:#fff;border:none;padding:13px;font-size:14px;font-weight:600;border-radius:12px;cursor:pointer;box-shadow:0 3px 12px rgba(26,188,156,0.35)" onclick="savePasswordPolicy()">
                <i class="fas fa-save" style="margin-right:6px"></i>保存策略
            </button>
        </div>
    </div>
</div>

<script>
var _umTenantId   = '${tenantId!}';
var _umTenantName = '${tenantName!}';
var _umDeleteUserId   = null;
var _umDeleteUserName = null;
var _ntEmails = [];
</script>
<#noparse>
<script>
document.getElementById('umTenantName').textContent = _umTenantName || '—';

/* ══════════════════════════════
   Tab 切换
══════════════════════════════ */
var _umActiveTab = 'users';
var _umTabLoaded = {};
function umSwitchTab(tab) {
    _umActiveTab = tab;
    ['users','notify','mfa'].forEach(function(t) {
        var cap = t.charAt(0).toUpperCase() + t.slice(1);
        document.getElementById('umTab' + cap).style.display = t === tab ? '' : 'none';
        document.getElementById('umTabBtn' + cap).classList.toggle('active', t === tab);
    });
    if (tab === 'users'  && !_umTabLoaded.users)  { loadUsers(); }
    if (tab === 'notify' && !_umTabLoaded.notify)  { loadNotifyEmails(); }
    if (tab === 'mfa'    && !_umTabLoaded.mfa)     { loadMfa(); }
}

/* ══════════════════════════════
   用户管理
══════════════════════════════ */
async function loadUsers() {
    document.getElementById('umLoading').style.display = '';
    document.getElementById('umList').innerHTML = '';
    try {
        var res  = await fetch('/tenants/oracle-users?tenantId=' + encodeURIComponent(_umTenantId));
        var data = await res.json();
        _umTabLoaded.users = true;
        renderUsers(Array.isArray(data) ? data : []);
    } catch(e) {
        document.getElementById('umLoading').style.display = 'none';
        document.getElementById('umList').innerHTML =
            '<p style="color:#f04747;text-align:center;padding:24px">加载失败: ' + escHtml(e.message) + '</p>';
    }
}

function renderUsers(users) {
    document.getElementById('umLoading').style.display = 'none';
    if (!users || users.length === 0) {
        document.getElementById('umList').innerHTML =
            '<p style="text-align:center;color:var(--mob-text-muted);padding:40px 0">暂无用户数据</p>';
        return;
    }
    document.getElementById('umList').innerHTML = users.map(function(u) {
        var isActive = (u.lifecycleState || '').toUpperCase() === 'ACTIVE';
        var name  = u.name || u.username || '—';
        var email = u.email || '—';
        var cTime = u.timeCreated ? String(u.timeCreated).substring(0, 10) : '—';
        var lTime = u.lastSuccessfulLoginTime ? String(u.lastSuccessfulLoginTime).substring(0, 10) : '—';
        var initial = name.substring(0,1).toUpperCase();
        var uid = escId(u.id || '');
        var uname = escAttr(name);
        return '<div class="um-user-card">'
            + '<div style="display:flex;align-items:center;gap:10px;margin-bottom:10px">'
            + '<div class="um-user-avatar">' + escHtml(initial) + '</div>'
            + '<div style="flex:1;min-width:0">'
            + '<div style="font-size:14px;font-weight:700;color:var(--mob-text);overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + escHtml(name) + '</div>'
            + '<div style="font-size:11px;color:var(--mob-text-muted);margin-top:1px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + escHtml(email) + '</div>'
            + '<div style="font-size:10px;color:var(--mob-text-muted);margin-top:2px">创建 ' + escHtml(cTime) + ' · 登录 ' + escHtml(lTime) + '</div>'
            + '</div>'
            + '<span class="um-badge ' + (isActive ? 'um-state-active' : 'um-state-inactive') + '">' + escHtml(u.lifecycleState || '—') + '</span>'
            + '</div>'
            + '<div style="display:flex;gap:6px;justify-content:flex-end">'
            + '<button class="um-icon-btn" style="height:30px;padding:0 14px;font-size:11px" onclick="resetPassword(\'' + uid + '\',\'' + uname + '\')">'
            + '<i class="fas fa-key" style="margin-right:5px"></i>重置密码</button>'
            + '<button class="um-icon-btn" style="height:30px;padding:0 14px;font-size:11px;border-color:rgba(240,71,71,0.3);background:rgba(240,71,71,0.08);color:#f04747" onclick="confirmDelete(\'' + uid + '\',\'' + uname + '\')">'
            + '<i class="fas fa-trash-alt" style="margin-right:5px"></i>删除</button>'
            + '</div>'
            + '</div>';
    }).join('');
}

function toggleAddForm() {
    var form = document.getElementById('addUserForm');
    form.style.display = form.style.display === 'none' ? '' : 'none';
}

async function createUser() {
    var email   = document.getElementById('newEmail').value.trim();
    var useEmail = document.getElementById('emailAsUsername').checked;
    var username = useEmail ? email : document.getElementById('newUsername').value.trim();
    if (!username) { umToast('请输入用户名', 'warn'); return; }
    if (!email)    { umToast('请输入邮箱', 'warn'); return; }
    var csrf = (document.querySelector('meta[name="_csrf"]')||{}).content||'';
    try {
        var res  = await fetch('/tenants/oracle-users', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
            body: JSON.stringify({ tenantId: _umTenantId, username: username, email: email })
        });
        var json = await res.json();
        if (json.success || json.username) {
            toggleAddForm();
            document.getElementById('umResultTitle').textContent = '用户创建成功';
            document.getElementById('umResultBody').innerHTML =
                '<div style="font-size:13px;line-height:2">'
                + '<div><span style="color:var(--mob-text-muted)">用户名：</span><strong>' + escHtml(json.username || username) + '</strong></div>'
                + '<div><span style="color:var(--mob-text-muted)">临时密码：</span><code style="color:#f04747;background:var(--mob-bg);padding:2px 6px;border-radius:4px">' + escHtml(json.password || '—') + '</code></div>'
                + '</div>';
            document.getElementById('umResultModal').style.display = 'flex';
            _umTabLoaded.users = false;
            loadUsers();
        } else {
            umToast(json.message || '创建失败', 'error');
        }
    } catch(e) { umToast('创建失败: ' + e.message, 'error'); }
}

var _umResetUserId = null, _umResetUserName = null;
function resetPassword(userId, userName) {
    _umResetUserId   = userId;
    _umResetUserName = userName;
    document.getElementById('umResetName').textContent = userName;
    document.getElementById('umResetModal').style.display = 'flex';
}
function closeUmReset(e) {
    if (e && e.target !== document.getElementById('umResetModal')) return;
    document.getElementById('umResetModal').style.display = 'none';
}
async function doResetPassword() {
    if (!_umResetUserId) return;
    document.getElementById('umResetModal').style.display = 'none';
    var csrf = (document.querySelector('meta[name="_csrf"]')||{}).content||'';
    umToast('正在重置密码…', 'info');
    try {
        var res  = await fetch('/tenants/oracle-users/resetPassword', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
            body: JSON.stringify({ tenantId: _umTenantId, userId: _umResetUserId, userName: _umResetUserName })
        });
        var json = await res.json();
        if (json.success) {
            var d = json.data || {};
            document.getElementById('umResultTitle').textContent = '密码重置成功';
            document.getElementById('umResultBody').innerHTML =
                '<div style="font-size:13px;line-height:2">'
                + '<div><span style="color:var(--mob-text-muted)">用户名：</span><strong>' + escHtml(d.loginUser || _umResetUserName) + '</strong></div>'
                + '<div><span style="color:var(--mob-text-muted)">临时密码：</span><code style="color:#f04747;background:var(--mob-bg);padding:2px 6px;border-radius:4px">' + escHtml(d.temporaryPassword || '—') + '</code></div>'
                + '</div>';
            document.getElementById('umResultModal').style.display = 'flex';
        } else {
            umToast(json.message || '重置失败', 'error');
        }
    } catch(e) { umToast('重置失败: ' + e.message, 'error'); }
}

function confirmDelete(userId, userName) {
    _umDeleteUserId   = userId;
    _umDeleteUserName = userName;
    document.getElementById('umDeleteName').textContent = userName;
    document.getElementById('umDeleteModal').style.display = 'flex';
}
function closeUmDelete(e) {
    if (e && e.target !== document.getElementById('umDeleteModal')) return;
    document.getElementById('umDeleteModal').style.display = 'none';
}
async function doDeleteUser() {
    if (!_umDeleteUserId) return;
    var csrf = (document.querySelector('meta[name="_csrf"]')||{}).content||'';
    document.getElementById('umDeleteModal').style.display = 'none';
    try {
        var res  = await fetch('/tenants/oracle-users/deleteUser', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
            body: JSON.stringify({ tenantId: _umTenantId, userId: _umDeleteUserId })
        });
        var json = await res.json();
        if (json.success) { umToast('删除成功', 'success'); _umTabLoaded.users=false; loadUsers(); }
        else umToast(json.message || '删除失败', 'error');
    } catch(e) { umToast('删除失败: ' + e.message, 'error'); }
}
function closeUmResult(e) {
    if (e && e.target !== document.getElementById('umResultModal')) return;
    document.getElementById('umResultModal').style.display = 'none';
}

/* ══════════════════════════════
   密码策略
══════════════════════════════ */
function openPasswordPolicy() {
    document.getElementById('policyOverlay').classList.add('active');
    document.getElementById('policySheet').classList.add('active');
    document.body.style.overflow = 'hidden';
    loadPasswordPolicy();
}
function closePolicySheet() {
    document.getElementById('policyOverlay').classList.remove('active');
    document.getElementById('policySheet').classList.remove('active');
    document.body.style.overflow = '';
    var btn = document.getElementById('policyBtn');
    btn.disabled = false;
    btn.innerHTML = '<i class="fas fa-save" style="margin-right:6px"></i>保存策略';
}

async function loadPasswordPolicy() {
    document.getElementById('policyLoading').style.display = '';
    document.getElementById('policyBody').style.display = 'none';
    var csrf = (document.querySelector('meta[name="_csrf"]')||{}).content||'';
    try {
        var res  = await fetch('/tenants/oracle-users/getPasspolicy', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
            body: JSON.stringify({ tenantId: _umTenantId })
        });
        var json = await res.json();
        var policies = json.data || [];
        document.getElementById('policyLoading').style.display = 'none';
        document.getElementById('policyBody').style.display = '';
        if (Array.isArray(policies) && policies.length > 0) {
            var p = policies[0];
            var enableExpiry = !!p.enablePasswordExpiry;
            document.getElementById('policySubtitle').textContent = p.name || '默认策略';
            setExpiryToggle(enableExpiry);
            document.getElementById('policyDays').value = p.expiryDays == null ? 120 : p.expiryDays;
        } else {
            document.getElementById('policySubtitle').textContent = '默认策略';
            setExpiryToggle(false);
        }
    } catch(e) {
        document.getElementById('policyLoading').style.display = 'none';
        document.getElementById('policyBody').style.display = '';
        umToast('加载策略失败: ' + e.message, 'error');
    }
}

function setExpiryToggle(on) {
    document.getElementById('policyExpiry').checked = on;
    var track = document.getElementById('policyExpiryTrack');
    track.style.background = on ? '#1abc9c' : '#bbb';
    track.style.borderColor  = on ? '#17a589' : '#aaa';
    document.getElementById('policyExpiryThumb').style.left = on ? '23px' : '3px';
    document.getElementById('policyDaysRow').style.display = on ? '' : 'none';
}
function toggleExpiryDays() {
    var on = document.getElementById('policyExpiry').checked;
    setExpiryToggle(on);
}

async function savePasswordPolicy() {
    var btn = document.getElementById('policyBtn');
    btn.disabled = true;
    btn.innerHTML = '<i class="fas fa-spinner fa-spin" style="margin-right:6px"></i>保存中…';
    var enableExpiry = document.getElementById('policyExpiry').checked;
    var parsedDays = parseInt(document.getElementById('policyDays').value, 10);
    var days = isNaN(parsedDays) ? 120 : parsedDays;
    if (enableExpiry && (days < 0 || days > 365)) {
        umToast('过期天数必须在0-365之间', 'error');
        resetPolicyButton();
        return;
    }
    var csrf = (document.querySelector('meta[name="_csrf"]')||{}).content||'';
    try {
        var res  = await fetch('/tenants/oracle-users/password-policy', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
            body: JSON.stringify({ tenantId: _umTenantId, enablePasswordExpiry: enableExpiry, expiryDays: days })
        });
        var json = await res.json();
        if (json.success || json.code === 200) {
            umToast('策略保存成功', 'success');
            closePolicySheet();
        } else {
            umToast(json.message || '保存失败', 'error');
            btn.disabled = false;
            btn.innerHTML = '<i class="fas fa-save" style="margin-right:6px"></i>保存策略';
        }
    } catch(e) {
        umToast('保存失败: ' + e.message, 'error');
        btn.disabled = false;
        btn.innerHTML = '<i class="fas fa-save" style="margin-right:6px"></i>保存策略';
    }
}

/* ══════════════════════════════
   通知邮箱
══════════════════════════════ */
async function loadNotifyEmails() {
    document.getElementById('ntLoading').style.display = '';
    document.getElementById('ntEmailList').innerHTML = '';
    _ntEmails = [];
    var csrf = (document.querySelector('meta[name="_csrf"]')||{}).content||'';
    try {
        var res  = await fetch('/tenants/notification/recipients', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
            body: JSON.stringify({ tenantId: _umTenantId })
        });
        var json = await res.json();
        _umTabLoaded.notify = true;
        var emails = json.recipients || json.data || [];
        if (Array.isArray(emails)) {
            _ntEmails = emails.map(function(e) { return typeof e === 'string' ? e : (e.email || String(e)); });
        }
        renderNtEmails();
    } catch(e) {
        document.getElementById('ntLoading').style.display = 'none';
        document.getElementById('ntEmailList').innerHTML =
            '<p style="color:#f04747;font-size:12px;text-align:center;padding:12px">加载失败: ' + escHtml(e.message) + '</p>';
    }
}

function renderNtEmails() {
    document.getElementById('ntLoading').style.display = 'none';
    if (_ntEmails.length === 0) {
        document.getElementById('ntEmailList').innerHTML =
            '<p style="color:var(--mob-text-muted);font-size:12px;text-align:center;padding:16px 0">暂无通知邮箱</p>';
        return;
    }
    document.getElementById('ntEmailList').innerHTML = _ntEmails.map(function(email, idx) {
        return '<div class="um-email-row">'
            + '<i class="fas fa-envelope" style="color:#5b8af0;font-size:13px;flex-shrink:0"></i>'
            + '<span style="flex:1;font-size:13px;color:var(--mob-text);overflow:hidden;text-overflow:ellipsis;white-space:nowrap">' + escHtml(email) + '</span>'
            + '<button class="um-icon-btn" style="border-color:rgba(240,71,71,0.3);background:rgba(240,71,71,0.08);color:#f04747;height:28px;padding:0 10px;font-size:11px;flex-shrink:0" onclick="ntRemoveEmail(' + idx + ')"><i class="fas fa-trash-alt" style="margin-right:4px"></i>删除</button>'
            + '</div>';
    }).join('');
}

function ntAddEmail() {
    var v = (document.getElementById('ntNewEmail').value || '').trim();
    if (!v || !v.includes('@')) { umToast('请输入有效邮箱', 'warn'); return; }
    if (_ntEmails.indexOf(v) >= 0) { umToast('邮箱已存在', 'warn'); return; }
    _ntEmails.push(v);
    document.getElementById('ntNewEmail').value = '';
    renderNtEmails();
}

function ntRemoveEmail(idx) {
    _ntEmails.splice(idx, 1);
    renderNtEmails();
}

async function ntSave() {
    var csrf = (document.querySelector('meta[name="_csrf"]')||{}).content||'';
    try {
        var res  = await fetch('/tenants/notification/update', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
            body: JSON.stringify({ tenantId: _umTenantId, emails: _ntEmails })
        });
        var json = await res.json();
        if (json.success || json.code === 200) umToast('保存成功', 'success');
        else umToast(json.message || '保存失败', 'error');
    } catch(e) { umToast('保存失败: ' + e.message, 'error'); }
}

/* ══════════════════════════════
   MFA 管理
══════════════════════════════ */
async function loadMfa() {
    document.getElementById('mfaLoading').style.display = '';
    document.getElementById('mfaContent').style.display = 'none';
    try {
        var res  = await fetch('/tenants/mfa/status?tenantId=' + encodeURIComponent(_umTenantId));
        var json = await res.json();
        _umTabLoaded.mfa = true;
        var data = json.data || json || {};
        renderMfaStatus(data);
    } catch(e) {
        document.getElementById('mfaLoading').style.display = 'none';
        umToast('MFA 状态加载失败: ' + e.message, 'error');
    }
}

function renderMfaStatus(data) {
    document.getElementById('mfaLoading').style.display = 'none';
    document.getElementById('mfaContent').style.display = '';
    var emailEnabled = data.emailEnabled || data.mfaEnabled || false;
    var icon = document.getElementById('mfaStatusIcon');
    var text = document.getElementById('mfaStatusText');
    if (emailEnabled) {
        icon.style.background = 'rgba(67,181,129,0.15)';
        icon.style.color      = '#43b581';
        text.style.color      = '#43b581';
        text.textContent      = '邮箱 MFA 已启用';
    } else {
        icon.style.background = 'rgba(91,138,240,0.1)';
        icon.style.color      = '#5b8af0';
        text.style.color      = 'var(--mob-text-muted)';
        text.textContent      = '邮箱 MFA 未启用';
    }
}

async function setMfaEmail(enable) {
    var csrf = (document.querySelector('meta[name="_csrf"]')||{}).content||'';
    try {
        var res  = await fetch('/tenants/mfa/email', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
            body: JSON.stringify({ tenantId: _umTenantId, enableEmail: enable })
        });
        var json = await res.json();
        if (json.success || json.code === 200) {
            umToast(enable ? '邮箱 MFA 已启用' : '邮箱 MFA 已关闭', 'success');
            _umTabLoaded.mfa = false;
            loadMfa();
        } else {
            umToast(json.message || '操作失败', 'error');
        }
    } catch(e) { umToast('操作失败: ' + e.message, 'error'); }
}

function confirmResetMfa() {
    document.getElementById('mfaResetModal').style.display = 'flex';
}
function closeMfaReset(e) {
    if (e && e.target !== document.getElementById('mfaResetModal')) return;
    document.getElementById('mfaResetModal').style.display = 'none';
}
async function doResetMfa() {
    document.getElementById('mfaResetModal').style.display = 'none';
    var csrf = (document.querySelector('meta[name="_csrf"]')||{}).content||'';
    try {
        var res  = await fetch('/tenants/resetAccountFactor?tenantId=' + encodeURIComponent(_umTenantId), {
            method: 'POST',
            headers: { 'X-CSRF-TOKEN': csrf }
        });
        var json = await res.json();
        if (json.success || json.code === 200) umToast('MFA 已重置', 'success');
        else umToast(json.message || '重置失败', 'error');
    } catch(e) { umToast('重置失败: ' + e.message, 'error'); }
}

/* ══ 工具 ══ */
function escHtml(s) {
    if (!s) return '';
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function escId(s)   { return String(s||'').replace(/'/g,"\\'"); }
function escAttr(s) { return String(s||'').replace(/'/g,"\\'").replace(/"/g,'&quot;'); }

function umToast(msg, type) {
    var t = document.createElement('div');
    t.style.cssText = 'position:fixed;bottom:80px;left:50%;transform:translateX(-50%);background:'
        + (type==='error'?'#f04747':type==='warn'?'#faa61a':'#43b581')
        + ';color:#fff;padding:10px 20px;border-radius:20px;font-size:13px;z-index:9999;white-space:nowrap;box-shadow:0 4px 12px rgba(0,0,0,0.3)';
    t.textContent = msg;
    document.body.appendChild(t);
    setTimeout(function() { t.remove(); }, 2800);
}

if (_umTenantId) loadUsers();
</script>
</#noparse>

</@layout.page>
