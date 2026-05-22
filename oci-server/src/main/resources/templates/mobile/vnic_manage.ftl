<#import "layout.ftl" as layout>
<@layout.page title="${msg.get('net.config')}" activePage="">

<style>
/* ── 返回 ── */
.mvn-back {
    display: flex; align-items: center; gap: 8px;
    margin-bottom: 16px; color: var(--mob-accent);
    font-size: 14px; font-weight: 600; cursor: pointer; width: fit-content;
}
/* ── Stats 2×2 ── */
.mvn-stats {
    display: grid; grid-template-columns: repeat(2, 1fr);
    gap: 10px; margin-bottom: 18px;
}
.mvn-stat {
    background: var(--mob-card); border-radius: 14px;
    padding: 14px 12px; display: flex; align-items: center; gap: 12px;
    border: 1px solid var(--mob-border);
}
.mvn-stat-icon {
    width: 42px; height: 42px; border-radius: 12px; flex-shrink: 0;
    display: flex; align-items: center; justify-content: center; font-size: 18px;
}
.mvn-stat-icon.blue   { background: rgba(59,130,246,.12);  color: #3b82f6; }
.mvn-stat-icon.green  { background: rgba(67,181,129,.12);  color: #43b581; }
.mvn-stat-icon.purple { background: rgba(139,92,246,.12);  color: #8b5cf6; }
.mvn-stat-icon.amber  { background: rgba(240,180,41,.12);  color: #f0b429; }
.mvn-stat-val { font-size: 26px; font-weight: 700; color: var(--mob-text); line-height: 1; }
.mvn-stat-lbl { font-size: 11px; color: var(--mob-text-muted); margin-top: 3px; }
/* ── 工具栏 ── */
.mvn-toolbar {
    display: flex; align-items: center; gap: 10px;
    margin-bottom: 16px;
}
.mvn-toolbar-title {
    font-size: 15px; font-weight: 700; color: var(--mob-text); flex: 1;
}
/* ── 通用按钮 ── */
.mvn-btn {
    border: none; border-radius: 10px; padding: 9px 14px;
    font-size: 13px; font-weight: 600; cursor: pointer;
    display: inline-flex; align-items: center; gap: 6px;
    transition: opacity 0.15s, transform 0.12s;
}
.mvn-btn:active { opacity: 0.75; transform: scale(0.96); }
.mvn-btn-primary { background: var(--mob-accent); color: #fff; }
.mvn-btn-danger  { background: #f04747; color: #fff; }
.mvn-btn-warn    { background: #f0b429; color: #fff; }
.mvn-btn-outline { background: var(--mob-bg); color: var(--mob-text-muted); border: 1px solid var(--mob-border); }
.mvn-btn-sm { padding: 7px 11px; font-size: 12px; border-radius: 8px; }
.mvn-btn-icon { padding: 9px 12px; }
/* ── VNIC 卡片 ── */
.mvn-vnic-card {
    background: var(--mob-card); border-radius: 16px;
    margin-bottom: 12px; border: 1px solid var(--mob-border);
    overflow: hidden;
}
.mvn-vnic-head {
    display: flex; align-items: center; justify-content: space-between;
    padding: 12px 14px 10px;
    border-bottom: 1px solid var(--mob-border);
    background: var(--mob-bg);
}
.mvn-vnic-head-left { display: flex; align-items: center; gap: 7px; flex-wrap: wrap; }
.mvn-badge {
    font-size: 10px; font-weight: 700; padding: 3px 8px; border-radius: 20px;
}
.mvn-badge-primary   { background: rgba(59,130,246,.15);  color: #3b82f6; }
.mvn-badge-secondary { background: rgba(139,92,246,.15);  color: #8b5cf6; }
.mvn-badge-state     { background: rgba(67,181,129,.15);  color: #43b581; }
.mvn-badge-state.detached { background: rgba(240,71,71,.15); color: #f04747; }
.mvn-vnic-id {
    font-size: 11px; color: var(--mob-text-muted);
    font-family: monospace; margin-left: auto; flex-shrink: 0;
}
/* ── IP 区域 ── */
.mvn-ip-section { padding: 12px 14px 0; }
.mvn-ip-item {
    display: flex; align-items: center; gap: 10px;
    padding: 8px 10px; border-radius: 10px;
    background: var(--mob-bg); border: 1px solid var(--mob-border);
    margin-bottom: 8px;
}
.mvn-ip-icon {
    width: 28px; height: 28px; border-radius: 8px;
    display: flex; align-items: center; justify-content: center; font-size: 13px;
    flex-shrink: 0;
}
.mvn-ip-icon.pub  { background: rgba(59,130,246,.12); color: #3b82f6; }
.mvn-ip-icon.priv { background: rgba(114,118,125,.12); color: #72767d; }
.mvn-ip-text { flex: 1; min-width: 0; }
.mvn-ip-label { font-size: 10px; color: var(--mob-text-muted); font-weight: 600; text-transform: uppercase; }
.mvn-ip-value { font-size: 13px; font-family: monospace; color: var(--mob-text); font-weight: 500; }
.mvn-ip-copy { background: none; border: none; color: var(--mob-text-muted); cursor: pointer; padding: 4px; font-size: 13px; }
.mvn-ip-copy:active { color: var(--mob-accent); }
/* ── IPv6 区域 ── */
.mvn-ipv6-section { padding: 0 14px 12px; margin-top: 10px; }
.mvn-ipv6-head {
    display: flex; align-items: center; justify-content: space-between;
    margin-bottom: 8px;
}
.mvn-ipv6-label {
    font-size: 11px; font-weight: 700; color: var(--mob-text-muted);
    display: flex; align-items: center; gap: 5px;
}
.mvn-ipv6-item {
    display: flex; align-items: center; gap: 8px;
    padding: 7px 10px; border-radius: 9px;
    background: var(--mob-bg); border: 1px solid var(--mob-border);
    margin-bottom: 6px;
}
.mvn-ipv6-addr {
    flex: 1; font-size: 11px; font-family: monospace;
    color: var(--mob-text); word-break: break-all;
}
.mvn-ipv6-actions { display: flex; gap: 4px; flex-shrink: 0; }
.mvn-ipv6-btn { background: none; border: none; cursor: pointer; padding: 4px 6px; border-radius: 6px; font-size: 12px; }
.mvn-ipv6-btn.copy  { color: var(--mob-text-muted); }
.mvn-ipv6-btn.del   { color: #f04747; }
.mvn-ipv6-btn:active { opacity: 0.6; }
.mvn-ipv6-empty { font-size: 12px; color: var(--mob-text-muted); padding: 6px 2px; }
/* ── VNIC 操作按钮 ── */
.mvn-vnic-footer {
    display: flex; gap: 0;
    border-top: 1px solid var(--mob-border);
}
.mvn-vnic-action-btn {
    flex: 1; padding: 11px; border: none; background: transparent;
    font-size: 13px; font-weight: 600; cursor: pointer;
    display: flex; align-items: center; justify-content: center; gap: 6px;
    color: var(--mob-text-muted); transition: background 0.15s;
}
.mvn-vnic-action-btn + .mvn-vnic-action-btn { border-left: 1px solid var(--mob-border); }
.mvn-vnic-action-btn:active { background: var(--mob-bg); }
.mvn-vnic-action-btn.primary { color: var(--mob-accent); }
.mvn-vnic-action-btn.danger  { color: #f04747; }
/* ── 区块（创建/高级）── */
.mvn-section {
    background: var(--mob-card); border-radius: 16px;
    margin-bottom: 14px; border: 1px solid var(--mob-border);
    overflow: hidden;
}
.mvn-section-head {
    display: flex; align-items: center; gap: 8px;
    padding: 14px 14px 12px;
    border-bottom: 1px solid var(--mob-border);
    font-size: 14px; font-weight: 700; color: var(--mob-text);
}
.mvn-section-body { padding: 14px; }
.mvn-field-row { margin-bottom: 12px; }
.mvn-field-label { font-size: 11px; font-weight: 600; color: var(--mob-text-muted); margin-bottom: 5px; text-transform: uppercase; letter-spacing: 0.04em; }
.mvn-field-input {
    display: block; width: 100%; padding: 10px 12px;
    border: 1px solid var(--mob-border); border-radius: 10px;
    background: var(--mob-bg); color: var(--mob-text);
    font-size: 14px; box-sizing: border-box; outline: none;
}
.mvn-field-input:focus { border-color: var(--mob-accent); }
.mvn-field-hint { font-size: 11px; color: var(--mob-text-muted); margin-top: 4px; }
.mvn-adv-warn {
    font-size: 12px; color: var(--mob-text-muted); line-height: 1.7;
    padding: 10px; background: rgba(139,92,246,.06); border-radius: 10px;
    margin-bottom: 12px; border: 1px solid rgba(139,92,246,.12);
}
.mvn-adv-btn-row { display: flex; gap: 10px; flex-wrap: wrap; }
/* ── 状态横幅 ── */
.mvn-modal-status { font-size: 12px; padding: 7px 10px; border-radius: 8px; margin-top: 10px; text-align: center; display: none; }
.mvn-modal-status.ok  { background: rgba(67,181,129,.15);  color: #43b581; display: block; }
.mvn-modal-status.err { background: rgba(240,71,71,.15);   color: #f04747; display: block; }
.mvn-modal-status.ing { background: rgba(59,130,246,.12);  color: #3b82f6; display: block; }
/* ── 模态框 ── */
.mvn-modal-bg { display: none; position: fixed; inset: 0; background: rgba(0,0,0,.55); z-index: 9600; align-items: center; justify-content: center; }
.mvn-modal-bg.show { display: flex; }
.mvn-modal-card { width: calc(100% - 40px); max-width: 360px; background: var(--mob-card); border-radius: 16px; padding: 20px; max-height: 80vh; overflow-y: auto; box-shadow: 0 8px 32px rgba(0,0,0,.2); }
.mvn-modal-title { font-size: 15px; font-weight: 700; color: var(--mob-text); margin-bottom: 14px; }
.mvn-modal-btns { display: flex; gap: 10px; margin-top: 14px; }
.mvn-modal-cancel { flex: 1; padding: 10px; border-radius: 10px; border: 1px solid var(--mob-border); background: var(--mob-bg); color: var(--mob-text-muted); font-size: 14px; font-weight: 600; cursor: pointer; }
.mvn-modal-ok { flex: 1; padding: 10px; border-radius: 10px; border: none; background: var(--mob-accent,#1abc9c); color: #fff; font-size: 14px; font-weight: 600; cursor: pointer; }
.mvn-modal-danger { background: #f04747; }
/* ── Toast ── */
.mvn-toast { position: fixed; bottom: 80px; left: 50%; transform: translateX(-50%); background: #222; color: #fff; padding: 8px 18px; border-radius: 20px; font-size: 13px; z-index: 9999; opacity: 0; transition: opacity .3s; white-space: nowrap; pointer-events: none; }
.mvn-toast.show { opacity: 1; }
/* ── 加载 ── */
.mvn-loading { text-align: center; padding: 30px; color: var(--mob-text-muted); font-size: 13px; }
.mvn-loading i { font-size: 24px; margin-bottom: 8px; animation: spin 1s linear infinite; display: block; }
@keyframes spin { to { transform: rotate(360deg); } }
</style>

<!-- 返回 -->
<div class="mvn-back" onclick="history.back()">
    <i class="fas fa-chevron-left"></i>${msg.get('common.rollback')}
</div>

<!-- 统计 2×2 -->
<div class="mvn-stats" id="mvnStats">
    <div class="mvn-stat">
        <div class="mvn-stat-icon blue"><i class="fas fa-network-wired"></i></div>
        <div><div class="mvn-stat-val" id="mvnStatTotal">-</div><div class="mvn-stat-lbl">${msg.get('net.vncs')}</div></div>
    </div>
    <div class="mvn-stat">
        <div class="mvn-stat-icon green"><i class="fas fa-check-circle"></i></div>
        <div><div class="mvn-stat-val" id="mvnStatActive">-</div><div class="mvn-stat-lbl">${msg.get('net.activeVnic')}</div></div>
    </div>
    <div class="mvn-stat">
        <div class="mvn-stat-icon purple"><i class="fas fa-sitemap"></i></div>
        <div><div class="mvn-stat-val" id="mvnStatSecondary">-</div><div class="mvn-stat-lbl">${msg.get('net.otherVnic')}</div></div>
    </div>
    <div class="mvn-stat">
        <div class="mvn-stat-icon amber"><i class="fas fa-globe"></i></div>
        <div><div class="mvn-stat-val" id="mvnStatIpv6">-</div><div class="mvn-stat-lbl">${msg.get('machine.ipv6')}</div></div>
    </div>
</div>

<!-- 工具栏 -->
<div class="mvn-toolbar">
    <span class="mvn-toolbar-title">${msg.get('net.vncs')}</span>
    <button class="mvn-btn mvn-btn-outline mvn-btn-sm" onclick="mvnLoad()">
        <i class="fas fa-sync-alt"></i>${msg.get('email.refresh')}
    </button>
    <button class="mvn-btn mvn-btn-danger mvn-btn-sm" onclick="mvnOpenDeleteAll()" id="mvnDeleteAllBtn">
        <i class="fas fa-trash-alt"></i>${msg.get('net.deleteOtherVnic')}
    </button>
</div>

<!-- VNIC 列表 -->
<div id="mvnVnicList">
    <div class="mvn-loading"><i class="fas fa-spinner"></i>${msg.get('mob.loading')}</div>
</div>

<!-- 创建 VNIC -->
<div class="mvn-section">
    <div class="mvn-section-head">
        <i class="fas fa-plus-circle" style="color:var(--mob-accent)"></i>
        ${msg.get('net.createVnic')}
    </div>
    <div class="mvn-section-body">
        <div class="mvn-field-row">
            <div class="mvn-field-label">${msg.get('net.subnetId')}</div>
            <input class="mvn-field-input" id="mvnCreateSubnet" type="text" placeholder="${msg.get('net.sameSubnetId')}">
        </div>
        <div class="mvn-field-row">
            <div class="mvn-field-label">${msg.get('net.vncs')} (1-31)</div>
            <input class="mvn-field-input" id="mvnCreateCount" type="number" min="1" max="31" value="1">
            <div class="mvn-field-hint">${msg.get('net.vnicLimit')}</div>
        </div>
        <div class="mvn-field-row">
            <div class="mvn-field-label">${msg.get('net.vnicIpv6s')} (0-32)</div>
            <input class="mvn-field-input" id="mvnCreateIpv6Count" type="number" min="0" max="32" value="0">
            <div class="mvn-field-hint">${msg.get('net.vnicIpv6CountSummary')}</div>
        </div>
        <div id="mvnCreateStatus" class="mvn-modal-status"></div>
        <button class="mvn-btn mvn-btn-primary" onclick="mvnDoCreate()" id="mvnCreateBtn" style="width:100%;justify-content:center;margin-top:4px">
            <i class="fas fa-plus"></i>${msg.get('net.createVnic')}
        </button>
    </div>
</div>

<!-- 高级配置 -->
<div class="mvn-section">
    <div class="mvn-section-head">
        <i class="fas fa-balance-scale" style="color:#8b5cf6"></i>
        ${msg.get('net.advancedNetConfig')}
    </div>
    <div class="mvn-section-body">
        <div class="mvn-adv-warn">${msg.get('net.advancedNetConfigSummary')}</div>
        <div class="mvn-adv-btn-row">
            <button class="mvn-btn" onclick="mvnOpenLb()" style="background:#8b5cf6;color:#fff">
                <i class="fas fa-rocket"></i>${msg.get('net.activeLb')}
            </button>
            <button class="mvn-btn mvn-btn-warn" onclick="mvnOpenRestore()">
                <i class="fas fa-undo"></i>${msg.get('net.restoreLb')}
            </button>
        </div>
    </div>
</div>

<!-- ══ 模态框：Change IP ══ -->
<div id="mvnChangeIpModal" class="mvn-modal-bg" onclick="mvnCloseModal('mvnChangeIpModal',event)">
    <div class="mvn-modal-card" onclick="event.stopPropagation()">
        <div class="mvn-modal-title"><i class="fas fa-sync-alt"></i> ${msg.get('net.changeIp')}</div>
        <div class="mvn-field-row">
            <div class="mvn-field-label">CIDR（${msg.get('mob.inst.ops.cidr.add')}，可选）</div>
            <div id="mvnCidrList">
                <input class="mvn-field-input mvn-cidr-row" type="text" placeholder="e.g. 10.0.0.0/24" style="margin-bottom:6px">
            </div>
            <button onclick="mvnAddCidr()" style="font-size:12px;color:var(--mob-accent);background:none;border:none;cursor:pointer;padding:0;margin-top:4px">
                <i class="fas fa-plus"></i> ${msg.get('mob.inst.ops.cidr.add')}
            </button>
        </div>
        <div id="mvnChangeIpStatus" class="mvn-modal-status"></div>
        <div class="mvn-modal-btns">
            <button class="mvn-modal-cancel" onclick="mvnCloseModal('mvnChangeIpModal')">${msg.get('mob.common.cancel')}</button>
            <button class="mvn-modal-ok" onclick="mvnDoChangeIp()">${msg.get('mob.common.confirm')}</button>
        </div>
    </div>
</div>

<!-- ══ 模态框：Add IPv6 ══ -->
<div id="mvnAddIpv6Modal" class="mvn-modal-bg" onclick="mvnCloseModal('mvnAddIpv6Modal',event)">
    <div class="mvn-modal-card" onclick="event.stopPropagation()">
        <div class="mvn-modal-title"><i class="fas fa-globe"></i> ${msg.get('net.vnicAddIpv6')}</div>
        <div class="mvn-field-row">
            <div class="mvn-field-label">${msg.get('net.ipv6Counts')} (1-32)</div>
            <input class="mvn-field-input" id="mvnAddIpv6Count" type="number" min="1" max="32" value="1">
            <div class="mvn-field-hint">${msg.get('net.ipv6CountsLimit')}</div>
        </div>
        <div id="mvnAddIpv6Status" class="mvn-modal-status"></div>
        <div class="mvn-modal-btns">
            <button class="mvn-modal-cancel" onclick="mvnCloseModal('mvnAddIpv6Modal')">${msg.get('mob.common.cancel')}</button>
            <button class="mvn-modal-ok" onclick="mvnDoAddIpv6()">${msg.get('mob.common.confirm')}</button>
        </div>
    </div>
</div>

<!-- ══ 模态框：Delete VNIC confirm ══ -->
<div id="mvnDeleteVnicModal" class="mvn-modal-bg" onclick="mvnCloseModal('mvnDeleteVnicModal',event)">
    <div class="mvn-modal-card" onclick="event.stopPropagation()">
        <div class="mvn-modal-title" style="color:#f04747"><i class="fas fa-exclamation-triangle"></i> ${msg.get('net.deleteVnic')}</div>
        <p style="font-size:13px;color:var(--mob-text-muted);margin-bottom:14px">${msg.get('net.deleteVnicDes')}</p>
        <div id="mvnDeleteVnicStatus" class="mvn-modal-status"></div>
        <div class="mvn-modal-btns">
            <button class="mvn-modal-cancel" onclick="mvnCloseModal('mvnDeleteVnicModal')">${msg.get('mob.common.cancel')}</button>
            <button class="mvn-modal-ok mvn-modal-danger" onclick="mvnDoDeleteVnic()">${msg.get('net.deleteVnicConfirm')}</button>
        </div>
    </div>
</div>

<!-- ══ 模态框：Delete All Secondary ══ -->
<div id="mvnDeleteAllModal" class="mvn-modal-bg" onclick="mvnCloseModal('mvnDeleteAllModal',event)">
    <div class="mvn-modal-card" onclick="event.stopPropagation()">
        <div class="mvn-modal-title" style="color:#f04747"><i class="fas fa-trash-alt"></i> ${msg.get('net.deleteOtherVnic')}</div>
        <p style="font-size:13px;color:var(--mob-text-muted);margin-bottom:14px">${msg.get('net.deleteOtherVnicDes')}</p>
        <div id="mvnDeleteAllStatus" class="mvn-modal-status"></div>
        <div class="mvn-modal-btns">
            <button class="mvn-modal-cancel" onclick="mvnCloseModal('mvnDeleteAllModal')">${msg.get('mob.common.cancel')}</button>
            <button class="mvn-modal-ok mvn-modal-danger" onclick="mvnDoDeleteAll()">${msg.get('mob.common.confirm')}</button>
        </div>
    </div>
</div>

<!-- ══ 模态框：Load Balancer ══ -->
<div id="mvnLbModal" class="mvn-modal-bg" onclick="mvnCloseModal('mvnLbModal',event)">
    <div class="mvn-modal-card" onclick="event.stopPropagation()">
        <div class="mvn-modal-title"><i class="fas fa-rocket"></i> ${msg.get('net.startLb')}</div>
        <div id="mvnLbInitial">
            <div style="font-size:12px;color:var(--mob-text-muted);line-height:1.7;padding:10px;background:rgba(59,130,246,.08);border-radius:8px;margin-bottom:14px">
                <strong>${msg.get('net.toast')}：</strong>
                <ul style="padding-left:16px;margin:6px 0">
                    <li>${msg.get('net.toast1')}</li>
                    <li>${msg.get('net.toast2')}</li>
                    <li>${msg.get('net.toast3')}</li>
                </ul>
            </div>
            <div class="mvn-modal-btns">
                <button class="mvn-modal-cancel" onclick="mvnCloseModal('mvnLbModal')">${msg.get('mob.common.cancel')}</button>
                <button class="mvn-modal-ok" style="background:#8b5cf6" onclick="mvnDoLb()">${msg.get('mob.common.confirm')}</button>
            </div>
        </div>
        <div id="mvnLbProgress" style="display:none">
            <div id="mvnLbSteps" style="display:flex;flex-direction:column;gap:10px;margin-bottom:14px"></div>
        </div>
        <div id="mvnLbStatus" class="mvn-modal-status"></div>
    </div>
</div>

<!-- ══ 模态框：Restore Network ══ -->
<div id="mvnRestoreModal" class="mvn-modal-bg" onclick="mvnCloseModal('mvnRestoreModal',event)">
    <div class="mvn-modal-card" onclick="event.stopPropagation()">
        <div class="mvn-modal-title" style="color:#f0b429"><i class="fas fa-undo"></i> ${msg.get('net.restoreLb')}</div>
        <div id="mvnRestoreInitial">
            <div style="font-size:12px;color:var(--mob-text-muted);line-height:1.7;padding:10px;background:rgba(240,71,71,.08);border-radius:8px;margin-bottom:14px;border:1px solid rgba(240,71,71,.15)">
                <strong style="color:#f04747">${msg.get('net.toast4')}</strong>
                <p style="margin:4px 0">${msg.get('net.toast5')}</p>
                <ul style="padding-left:16px;margin:6px 0">
                    <li>${msg.get('net.toast7')}</li>
                    <li>${msg.get('net.toast8')}</li>
                    <li>${msg.get('net.toast9')}</li>
                </ul>
            </div>
            <div class="mvn-modal-btns">
                <button class="mvn-modal-cancel" onclick="mvnCloseModal('mvnRestoreModal')">${msg.get('mob.common.cancel')}</button>
                <button class="mvn-modal-ok mvn-modal-danger" onclick="mvnDoRestore()">${msg.get('mob.common.confirm')}</button>
            </div>
        </div>
        <div id="mvnRestoreProgress" style="display:none">
            <div id="mvnRestoreSteps" style="display:flex;flex-direction:column;gap:10px;margin-bottom:14px"></div>
        </div>
        <div id="mvnRestoreStatus" class="mvn-modal-status"></div>
    </div>
</div>

<!-- Toast -->
<div class="mvn-toast" id="mvnToast"></div>

<input type="hidden" id="mvnInstanceId" value="${instanceId!''}">

<script>
var _mvnInstanceId = document.getElementById('mvnInstanceId').value;
var _mvnData = {};
var _mvnCurrentVnicId = '';
var _mvnCurrentIpv6 = '';

function _mvnCsrf() {
    var m = document.querySelector('meta[name="_csrf"]');
    return m ? m.getAttribute('content') : '';
}
function _mvnPost(url, body, cb) {
    fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': _mvnCsrf() },
        body: JSON.stringify(body)
    }).then(function(r) { return r.json(); })
      .then(cb)
      .catch(function(e) { cb({ success: false, message: e.message }); });
}
function mvnToast(msg, type) {
    var t = document.getElementById('mvnToast');
    t.textContent = msg;
    t.style.background = type === 'err' ? '#f04747' : (type === 'ok' ? '#43b581' : '#222');
    t.classList.add('show');
    setTimeout(function() { t.classList.remove('show'); }, 2800);
}
function _mvnStatus(elId, msg, type) {
    var el = document.getElementById(elId);
    if (!el) return;
    el.textContent = msg;
    el.className = 'mvn-modal-status ' + (type || 'ing');
}
function mvnCloseModal(id, e) {
    if (e && e.target !== document.getElementById(id)) return;
    document.getElementById(id).classList.remove('show');
}
function mvnOpenModal(id) { document.getElementById(id).classList.add('show'); }

/* ── Load VNIC data ── */
function mvnLoad() {
    document.getElementById('mvnVnicList').innerHTML =
        '<div class="mvn-loading"><i class="fas fa-spinner"></i>${msg.get('mob.loading')?js_string}</div>';
    fetch('/oci/vnic/loadData?instanceId=' + encodeURIComponent(_mvnInstanceId))
        .then(function(r) { return r.json(); })
        .then(function(json) {
            if (!json.success) { throw new Error(json.message || 'Failed'); }
            _mvnData = json.data || {};
            mvnRenderStats(_mvnData.statistics || {});
            mvnRenderVnics(_mvnData.vnicList || []);
            var pv = _mvnData.primaryVnic;
            if (pv && pv.subnetId && !document.getElementById('mvnCreateSubnet').value) {
                document.getElementById('mvnCreateSubnet').value = pv.subnetId;
            }
        })
        .catch(function(e) {
            document.getElementById('mvnVnicList').innerHTML =
                '<div style="color:#f04747;text-align:center;padding:20px;font-size:13px">' + e.message + '</div>';
        });
}

function mvnRenderStats(s) {
    document.getElementById('mvnStatTotal').textContent     = s.totalVnicCount || 0;
    document.getElementById('mvnStatActive').textContent    = s.activeVnicCount || 0;
    document.getElementById('mvnStatSecondary').textContent = s.secondaryVnicCount || 0;
    document.getElementById('mvnStatIpv6').textContent      = s.totalIpv6Count || 0;
}

function mvnEsc(s) {
    if (!s) return '';
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}
function mvnShort(s, n) { return s && s.length > n ? '...' + s.slice(-n) : (s || '—'); }

function mvnRenderVnics(list) {
    if (!list || list.length === 0) {
        document.getElementById('mvnVnicList').innerHTML =
            '<div class="mvn-loading">${msg.get('net.noOtherVnic')?js_string}</div>';
        return;
    }
    document.getElementById('mvnVnicList').innerHTML = list.map(function(v) {
        var isPrimary  = v.isPrimary;
        var attached   = (v.lifecycleState || '').toUpperCase() === 'ATTACHED';
        var stateClass = attached ? '' : ' detached';

        /* ── Head ── */
        var head = '<div class="mvn-vnic-head">'
            + '<div class="mvn-vnic-head-left">'
            + '<span class="mvn-badge ' + (isPrimary ? 'mvn-badge-primary' : 'mvn-badge-secondary') + '">'
            + (isPrimary ? '${msg.get('net.homeVnic')?js_string}' : '${msg.get('net.otherVnic')?js_string}')
            + '</span>'
            + '<span class="mvn-badge mvn-badge-state' + stateClass + '">' + mvnEsc(v.lifecycleState) + '</span>'
            + '</div>'
            + '<span class="mvn-vnic-id">' + mvnShort(v.vnicId, 10) + '</span>'
            + '</div>';

        /* ── IP section ── */
        var ips = '';
        if (v.publicIp) {
            ips += '<div class="mvn-ip-item">'
                + '<span class="mvn-ip-icon pub"><i class="fas fa-globe"></i></span>'
                + '<div class="mvn-ip-text">'
                + '<div class="mvn-ip-label">Public IP</div>'
                + '<div class="mvn-ip-value">' + mvnEsc(v.publicIp) + '</div>'
                + '</div>'
                + '<button class="mvn-ip-copy" onclick="mvnCopyText(\'' + mvnEsc(v.publicIp) + '\')"><i class="fas fa-copy"></i></button>'
                + '</div>';
        }
        if (v.privateIp) {
            ips += '<div class="mvn-ip-item">'
                + '<span class="mvn-ip-icon priv"><i class="fas fa-lock"></i></span>'
                + '<div class="mvn-ip-text">'
                + '<div class="mvn-ip-label">Private IP</div>'
                + '<div class="mvn-ip-value">' + mvnEsc(v.privateIp) + '</div>'
                + '</div>'
                + '<button class="mvn-ip-copy" onclick="mvnCopyText(\'' + mvnEsc(v.privateIp) + '\')"><i class="fas fa-copy"></i></button>'
                + '</div>';
        }
        var ipSection = ips ? '<div class="mvn-ip-section">' + ips + '</div>' : '';

        /* ── IPv6 section ── */
        var ipv6AddBtn = '<button class="mvn-btn mvn-btn-primary mvn-btn-sm" onclick="mvnOpenAddIpv6(\'' + mvnEsc(v.vnicId) + '\')">'
            + '<i class="fas fa-plus"></i>${msg.get('net.vnicAddIpv6')?js_string}</button>';
        var ipv6Head = '<div class="mvn-ipv6-head">'
            + '<span class="mvn-ipv6-label"><i class="fas fa-globe" style="color:#f0b429"></i>IPv6</span>'
            + ipv6AddBtn + '</div>';
        var ipv6Body = '';
        if (v.ipv6Addresses && v.ipv6Addresses.length) {
            ipv6Body = v.ipv6Addresses.map(function(ip, i) {
                var ipv6Id = (v.ipv6Ids && v.ipv6Ids[i]) ? v.ipv6Ids[i] : '';
                return '<div class="mvn-ipv6-item">'
                    + '<span class="mvn-ipv6-addr">' + mvnEsc(ip) + '</span>'
                    + '<div class="mvn-ipv6-actions">'
                    + '<button class="mvn-ipv6-btn copy" onclick="mvnCopyText(\'' + mvnEsc(ip) + '\')"><i class="fas fa-copy"></i></button>'
                    + '<button class="mvn-ipv6-btn del" onclick="mvnOpenDeleteIpv6(\'' + mvnEsc(v.vnicId) + '\',\'' + mvnEsc(ip) + '\')"><i class="fas fa-times"></i></button>'
                    + '</div></div>';
            }).join('');
        } else {
            ipv6Body = '<div class="mvn-ipv6-empty">${msg.get('net.noOtherVnic')?js_string}</div>';
        }
        var ipv6Section = '<div class="mvn-ipv6-section">' + ipv6Head + ipv6Body + '</div>';

        /* ── Footer actions ── */
        var footer = '<div class="mvn-vnic-footer">'
            + '<button class="mvn-vnic-action-btn primary" onclick="mvnOpenChangeIp(\'' + mvnEsc(v.vnicId) + '\')">'
            + '<i class="fas fa-sync-alt"></i>${msg.get('net.changeIp')?js_string}</button>';
        if (!isPrimary) {
            footer += '<button class="mvn-vnic-action-btn danger" onclick="mvnOpenDeleteVnic(\'' + mvnEsc(v.vnicId) + '\')">'
                + '<i class="fas fa-trash-alt"></i>${msg.get('net.deleteVnic')?js_string}</button>';
        }
        footer += '</div>';

        return '<div class="mvn-vnic-card">' + head + ipSection + ipv6Section + footer + '</div>';
    }).join('');
}

function mvnCopyText(s) {
    navigator.clipboard.writeText(s).then(function() { mvnToast('Copied!', 'ok'); }).catch(function() {
        var ta = document.createElement('textarea'); ta.value = s; document.body.appendChild(ta);
        ta.select(); document.execCommand('copy'); document.body.removeChild(ta);
        mvnToast('Copied!', 'ok');
    });
}

/* ── Change IP ── */
function mvnOpenChangeIp(vnicId) {
    _mvnCurrentVnicId = vnicId;
    document.getElementById('mvnCidrList').innerHTML =
        '<input class="mvn-field-input mvn-cidr-row" type="text" placeholder="e.g. 10.0.0.0/24" style="margin-bottom:6px">';
    var st = document.getElementById('mvnChangeIpStatus');
    st.style.display = 'none'; st.className = 'mvn-modal-status';
    mvnOpenModal('mvnChangeIpModal');
}
function mvnAddCidr() {
    var list = document.getElementById('mvnCidrList');
    var wrap = document.createElement('div');
    wrap.style.cssText = 'display:flex;gap:6px;margin-bottom:6px';
    wrap.innerHTML = '<input class="mvn-field-input mvn-cidr-row" type="text" placeholder="CIDR" style="flex:1">'
        + '<button type="button" onclick="this.parentElement.remove()" style="background:none;border:none;color:#f04747;font-size:15px;cursor:pointer"><i class="fas fa-times"></i></button>';
    list.appendChild(wrap);
}
function mvnDoChangeIp() {
    var cidrInputs = document.querySelectorAll('.mvn-cidr-row');
    var cidrRanges = Array.from(cidrInputs).map(function(el) { return el.value.trim(); }).filter(Boolean);
    _mvnStatus('mvnChangeIpStatus', '${msg.get('mob.inst.ops.starting')?js_string}', 'ing');
    _mvnPost('/oci/vnic/changeSpecIp',
        { instanceId: _mvnInstanceId, vnicId: _mvnCurrentVnicId, cidrRanges: cidrRanges, preferredIp: null },
        function(json) {
            if (json.status === 'success' || json.success) {
                var msg = '${msg.get('mob.inst.ops.success')?js_string}';
                if (json.details) msg += ' → ' + json.details.newIp;
                _mvnStatus('mvnChangeIpStatus', msg, 'ok');
                setTimeout(function() { mvnCloseModal('mvnChangeIpModal'); mvnLoad(); }, 1800);
            } else {
                _mvnStatus('mvnChangeIpStatus', json.message || '${msg.get('mob.inst.ops.fail')?js_string}', 'err');
            }
        });
}

/* ── Add IPv6 ── */
function mvnOpenAddIpv6(vnicId) {
    _mvnCurrentVnicId = vnicId;
    document.getElementById('mvnAddIpv6Count').value = 1;
    var st = document.getElementById('mvnAddIpv6Status');
    st.style.display = 'none'; st.className = 'mvn-modal-status';
    mvnOpenModal('mvnAddIpv6Modal');
}
function mvnDoAddIpv6() {
    var count = parseInt(document.getElementById('mvnAddIpv6Count').value) || 1;
    _mvnStatus('mvnAddIpv6Status', '${msg.get('mob.inst.ops.starting')?js_string}', 'ing');
    _mvnPost('/oci/vnic/createIpv6',
        { instanceId: _mvnInstanceId, vnicId: _mvnCurrentVnicId, ipv6Count: count },
        function(json) {
            if (json.success) {
                _mvnStatus('mvnAddIpv6Status', json.message || '${msg.get('mob.inst.ops.success')?js_string}', 'ok');
                setTimeout(function() { mvnCloseModal('mvnAddIpv6Modal'); mvnLoad(); }, 1800);
            } else {
                _mvnStatus('mvnAddIpv6Status', json.message || '${msg.get('mob.inst.ops.fail')?js_string}', 'err');
            }
        });
}

/* ── Delete IPv6 ── */
function mvnOpenDeleteIpv6(vnicId, ipv6) {
    if (!confirm('Delete IPv6: ' + ipv6 + '?')) return;
    _mvnPost('/oci/vnic/deleteIpv6', { instanceId: _mvnInstanceId, vnicId: vnicId, ipv6Address: ipv6 },
        function(json) {
            mvnToast(json.success ? '${msg.get('mob.inst.ops.success')?js_string}' : (json.message || '${msg.get('mob.inst.ops.fail')?js_string}'),
                json.success ? 'ok' : 'err');
            if (json.success) setTimeout(mvnLoad, 600);
        });
}

/* ── Delete VNIC ── */
function mvnOpenDeleteVnic(vnicId) {
    _mvnCurrentVnicId = vnicId;
    var st = document.getElementById('mvnDeleteVnicStatus');
    st.style.display = 'none'; st.className = 'mvn-modal-status';
    mvnOpenModal('mvnDeleteVnicModal');
}
function mvnDoDeleteVnic() {
    _mvnStatus('mvnDeleteVnicStatus', '${msg.get('mob.inst.ops.starting')?js_string}', 'ing');
    _mvnPost('/oci/vnic/delete', { instanceId: _mvnInstanceId, vnicId: _mvnCurrentVnicId },
        function(json) {
            if (json.success) {
                _mvnStatus('mvnDeleteVnicStatus', json.message || '${msg.get('mob.inst.ops.success')?js_string}', 'ok');
                setTimeout(function() { mvnCloseModal('mvnDeleteVnicModal'); mvnLoad(); }, 1500);
            } else {
                _mvnStatus('mvnDeleteVnicStatus', json.message || '${msg.get('mob.inst.ops.fail')?js_string}', 'err');
            }
        });
}

/* ── Delete All Secondary ── */
function mvnOpenDeleteAll() { mvnOpenModal('mvnDeleteAllModal'); }
function mvnDoDeleteAll() {
    _mvnStatus('mvnDeleteAllStatus', '${msg.get('mob.inst.ops.starting')?js_string}', 'ing');
    _mvnPost('/oci/vnic/deleteAllSecondary', { instanceId: _mvnInstanceId },
        function(json) {
            if (json.success) {
                _mvnStatus('mvnDeleteAllStatus', json.message || '${msg.get('mob.inst.ops.success')?js_string}', 'ok');
                setTimeout(function() { mvnCloseModal('mvnDeleteAllModal'); mvnLoad(); }, 1500);
            } else {
                _mvnStatus('mvnDeleteAllStatus', json.message || '${msg.get('mob.inst.ops.fail')?js_string}', 'err');
            }
        });
}

/* ── Create VNIC ── */
function mvnDoCreate() {
    var subnetId  = document.getElementById('mvnCreateSubnet').value.trim();
    var count     = parseInt(document.getElementById('mvnCreateCount').value) || 1;
    var ipv6Count = parseInt(document.getElementById('mvnCreateIpv6Count').value) || 0;
    if (!subnetId) { mvnToast('${msg.get('net.subnetId')?js_string}?', 'err'); return; }
    _mvnStatus('mvnCreateStatus', '${msg.get('mob.inst.ops.starting')?js_string}', 'ing');
    document.getElementById('mvnCreateBtn').disabled = true;
    _mvnPost('/oci/vnic/create',
        { instanceId: _mvnInstanceId, subnetId: subnetId, vnicCount: count, ipv6CountPerVnic: ipv6Count },
        function(json) {
            document.getElementById('mvnCreateBtn').disabled = false;
            if (json.success) {
                var detail = json.details || {};
                var m = detail.summary || json.message || '${msg.get('mob.inst.ops.success')?js_string}';
                _mvnStatus('mvnCreateStatus', m, 'ok');
                setTimeout(mvnLoad, 1800);
            } else {
                _mvnStatus('mvnCreateStatus', json.message || '${msg.get('mob.inst.ops.fail')?js_string}', 'err');
            }
        });
}

/* ── LB Config ── */
function mvnOpenLb() {
    document.getElementById('mvnLbInitial').style.display = 'block';
    document.getElementById('mvnLbProgress').style.display = 'none';
    var st = document.getElementById('mvnLbStatus'); st.style.display = 'none'; st.className = 'mvn-modal-status';
    mvnOpenModal('mvnLbModal');
}
function mvnDoLb() {
    document.getElementById('mvnLbInitial').style.display = 'none';
    document.getElementById('mvnLbProgress').style.display = 'block';
    var steps = ['${msg.get('net.createNetGateway')?js_string}','${msg.get('net.createRouteTable')?js_string}',
                 '${msg.get('net.refreshNet')?js_string}','${msg.get('net.createLb')?js_string}','${msg.get('net.finish')?js_string}'];
    document.getElementById('mvnLbSteps').innerHTML = steps.map(function(s, i) {
        return '<div id="mvnLbStep' + i + '" style="display:flex;align-items:center;gap:8px;font-size:13px;color:var(--mob-text-muted)">'
            + '<i class="fas fa-circle" style="font-size:8px"></i><span>' + s + '</span></div>';
    }).join('');
    _mvnStatus('mvnLbStatus', '${msg.get('net.starting')?js_string}', 'ing');
    _mvnPost('/oci/vnic/network/configureLoadBalancer', { instanceId: _mvnInstanceId },
        function(json) {
            if (json.success) {
                _mvnStatus('mvnLbStatus', json.message || '${msg.get('mob.inst.ops.success')?js_string}', 'ok');
                steps.forEach(function(_, i) {
                    var el = document.getElementById('mvnLbStep' + i);
                    if (el) el.style.color = '#43b581';
                });
            } else {
                _mvnStatus('mvnLbStatus', json.message || '${msg.get('mob.inst.ops.fail')?js_string}', 'err');
            }
        });
}

/* ── Restore Network ── */
function mvnOpenRestore() {
    document.getElementById('mvnRestoreInitial').style.display = 'block';
    document.getElementById('mvnRestoreProgress').style.display = 'none';
    var st = document.getElementById('mvnRestoreStatus'); st.style.display = 'none'; st.className = 'mvn-modal-status';
    mvnOpenModal('mvnRestoreModal');
}
function mvnDoRestore() {
    document.getElementById('mvnRestoreInitial').style.display = 'none';
    document.getElementById('mvnRestoreProgress').style.display = 'block';
    var steps = ['${msg.get('net.checkConfig')?js_string}','${msg.get('net.deleteLb')?js_string}',
                 '${msg.get('net.deleteNetGateway')?js_string}','${msg.get('net.restoreRoute')?js_string}','${msg.get('common.finish')?js_string}'];
    document.getElementById('mvnRestoreSteps').innerHTML = steps.map(function(s, i) {
        return '<div id="mvnRStep' + i + '" style="display:flex;align-items:center;gap:8px;font-size:13px;color:var(--mob-text-muted)">'
            + '<i class="fas fa-circle" style="font-size:8px"></i><span>' + s + '</span></div>';
    }).join('');
    _mvnStatus('mvnRestoreStatus', '${msg.get('net.starting')?js_string}', 'ing');
    _mvnPost('/oci/vnic/network/restoreNetwork', { instanceId: _mvnInstanceId },
        function(json) {
            if (json.success) {
                _mvnStatus('mvnRestoreStatus', json.message || '${msg.get('mob.inst.ops.success')?js_string}', 'ok');
                steps.forEach(function(_, i) {
                    var el = document.getElementById('mvnRStep' + i);
                    if (el) el.style.color = '#43b581';
                });
            } else {
                _mvnStatus('mvnRestoreStatus', json.message || '${msg.get('mob.inst.ops.fail')?js_string}', 'err');
            }
        });
}

document.addEventListener('DOMContentLoaded', mvnLoad);
</script>

</@layout.page>
