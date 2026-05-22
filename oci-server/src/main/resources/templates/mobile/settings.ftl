<#import "layout.ftl" as layout>
<@layout.page title="${msg.get('mob.settings.account.title')}" activePage="settings">

<!-- ══════════════ 账号安全 ══════════════ -->
<div class="mob-settings-section">
    <div class="mob-settings-section-header" onclick="mobSettingsToggle('secAccount')">
        <div class="mob-settings-section-title">
            <i class="fas fa-shield-alt" style="color:#1abc9c"></i>
            ${msg.get('mob.settings.account.title')}
        </div>
        <i class="fas fa-chevron-down mob-settings-arrow" id="arrowSecAccount"></i>
    </div>
    <div class="mob-settings-body" id="secAccount">
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.account.current')}</label>
            <input class="mob-sf-input" type="text" value="${currentUsername!''}" disabled>
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.account.current.pass')} <span style="color:#f04747">*</span></label>
            <input class="mob-sf-input" type="password" id="accCurrentPass" placeholder="${msg.get('mob.settings.account.current.pass')}">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.account.new.username')}</label>
            <input class="mob-sf-input" type="text" id="accNewUsername" placeholder="${msg.get('mob.settings.account.keep.empty')}">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.account.new.pass')}</label>
            <input class="mob-sf-input" type="password" id="accNewPass" placeholder="${msg.get('mob.settings.account.keep.empty')}">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.account.confirm.pass')}</label>
            <input class="mob-sf-input" type="password" id="accConfirmPass" placeholder="${msg.get('mob.settings.account.confirm.pass')}">
        </div>
        <button class="mob-btn mob-btn-primary mob-btn-full" style="margin-top:4px" onclick="settingsSaveAccount()">
            <i class="fas fa-save"></i> ${msg.get('mob.settings.account.save')}
        </button>
    </div>
</div>

<!-- ══════════════ GitHub OAuth ══════════════ -->
<div class="mob-settings-section">
    <div class="mob-settings-section-header" onclick="mobSettingsToggle('secGithub')">
        <div class="mob-settings-section-title">
            <i class="fab fa-github" style="color:#c9d1d9"></i>
            ${msg.get('mob.settings.github.title')}
        </div>
        <div style="display:flex;align-items:center;gap:10px">
            <label class="mob-sf-toggle" onclick="event.stopPropagation()">
                <input type="checkbox" id="githubEnabled" <#if (githubConfig.enabled)!false>checked</#if> onchange="settingsSaveGithub()">
                <span class="mob-sf-toggle-slider"></span>
            </label>
            <i class="fas fa-chevron-down mob-settings-arrow" id="arrowSecGithub"></i>
        </div>
    </div>
    <div class="mob-settings-body" id="secGithub" style="display:none">
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.github.username')}</label>
            <div style="display:flex;gap:8px">
                <input class="mob-sf-input" type="text" id="githubUsername" value="${(githubConfig.username)!''}" placeholder="${msg.get('mob.settings.github.username')}" style="flex:1">
                <button class="mob-btn mob-btn-outline mob-btn-sm" style="flex-shrink:0;white-space:nowrap" onclick="settingsFetchGithubId()">
                    <i class="fas fa-search"></i> ${msg.get('mob.settings.github.get.id')}
                </button>
            </div>
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.github.id')}</label>
            <input class="mob-sf-input" type="text" id="githubId" value="${(githubConfig.githubId)!''}" readonly placeholder="${msg.get('mob.settings.github.id')}">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.github.client.id')}</label>
            <input class="mob-sf-input" type="text" id="githubClientId" value="${(githubConfig.clientId)!''}" placeholder="GitHub App Client ID">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.github.client.secret')}</label>
            <input class="mob-sf-input" type="password" id="githubClientSecret" value="${(githubConfig.clientSecret)!''}" placeholder="Client Secret">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.github.redirect')}</label>
            <input class="mob-sf-input" type="text" id="githubRedirectUri" value="${(githubConfig.redirectUri)!''}" placeholder="http(s)://your-domain/api/github/callback">
        </div>
        <button class="mob-btn mob-btn-primary mob-btn-full" style="margin-top:4px" onclick="settingsSaveGithub()">
            <i class="fas fa-save"></i> ${msg.get('mob.settings.github.save')}
        </button>
    </div>
</div>

<!-- ══════════════ Google OAuth ══════════════ -->
<div class="mob-settings-section">
    <div class="mob-settings-section-header" onclick="mobSettingsToggle('secGoogle')">
        <div class="mob-settings-section-title">
            <i class="fab fa-google" style="color:#4285f4"></i>
            ${msg.get('mob.settings.google.title')}
        </div>
        <div style="display:flex;align-items:center;gap:10px">
            <label class="mob-sf-toggle" onclick="event.stopPropagation()">
                <input type="checkbox" id="googleEnabled" <#if (googleConfig.enabled)!false>checked</#if> onchange="settingsSaveGoogle()">
                <span class="mob-sf-toggle-slider"></span>
            </label>
            <i class="fas fa-chevron-down mob-settings-arrow" id="arrowSecGoogle"></i>
        </div>
    </div>
    <div class="mob-settings-body" id="secGoogle" style="display:none">
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.google.email')} <span style="color:#f04747">*</span></label>
            <input class="mob-sf-input" type="text" id="googleEmail" value="${(googleConfig.email)!''}" placeholder="your@gmail.com">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.github.client.id')}</label>
            <input class="mob-sf-input" type="text" id="googleClientId" value="${(googleConfig.clientId)!''}" placeholder="Google OAuth Client ID">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.github.client.secret')}</label>
            <input class="mob-sf-input" type="password" id="googleClientSecret" value="${(googleConfig.clientSecret)!''}" placeholder="Client Secret">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.github.redirect')}</label>
            <input class="mob-sf-input" type="text" id="googleRedirectUri" value="${(googleConfig.redirectUri)!''}" placeholder="http(s)://your-domain/api/google/callback">
        </div>
        <button class="mob-btn mob-btn-primary mob-btn-full" style="margin-top:4px" onclick="settingsSaveGoogle()">
            <i class="fas fa-save"></i> ${msg.get('mob.settings.google.save')}
        </button>
    </div>
</div>

<!-- ══════════════ MFA ══════════════ -->
<div class="mob-settings-section" style="margin-bottom:0">
    <div class="mob-settings-section-header" onclick="mobSettingsToggle('secMfa')">
        <div class="mob-settings-section-title">
            <i class="fas fa-mobile-alt" style="color:#faa61a"></i>
            ${msg.get('mob.settings.mfa.title')}
        </div>
        <div style="display:flex;align-items:center;gap:10px">
            <label class="mob-sf-toggle" onclick="event.stopPropagation()">
                <input type="checkbox" id="mfaEnabled" <#if (mfaConfig.enabled)!false>checked</#if> onchange="settingsSaveMfa()">
                <span class="mob-sf-toggle-slider"></span>
            </label>
            <i class="fas fa-chevron-down mob-settings-arrow" id="arrowSecMfa"></i>
        </div>
    </div>
    <div class="mob-settings-body" id="secMfa" style="display:none">
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.mfa.app.name')}</label>
            <input class="mob-sf-input" type="text" id="mfaIssuer" value="${(mfaConfig.issuer)!'OCI-Start Verify'}" placeholder="OCI-Start Verify">
        </div>
        <#if (mfaConfig.secretKey)??>
        <div class="mob-sf-row" style="flex-direction:column;align-items:flex-start;gap:10px">
            <label class="mob-sf-label">${msg.get('mob.settings.mfa.scan.qr')}</label>
            <div style="text-align:center;width:100%">
                <img src="data:image/png;base64,${mfaConfig.qrCode!''}" alt="MFA QR" style="max-width:180px;border-radius:12px;border:3px solid var(--mob-border)">
            </div>
            <div style="font-size:12px;color:var(--mob-text-muted)">${msg.get('mob.settings.mfa.qr.hint')}</div>
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.mfa.secret')}</label>
            <input class="mob-sf-input" type="text" value="${mfaConfig.secretKey!''}" readonly onclick="mobCopy('${mfaConfig.secretKey!''}')" style="font-size:11px;cursor:pointer" title="${msg.get('mob.settings.mfa.secret')}">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.settings.mfa.verify.code')}</label>
            <div style="display:flex;gap:8px">
                <input class="mob-sf-input" type="text" id="mfaVerifyCode" placeholder="${msg.get('mob.settings.mfa.verify.code')}" maxlength="6" style="flex:1;letter-spacing:4px;text-align:center" inputmode="numeric">
                <button class="mob-btn mob-btn-outline mob-btn-sm" style="flex-shrink:0;white-space:nowrap" onclick="settingsVerifyMfa()">
                    <i class="fas fa-check"></i> ${msg.get('mob.settings.mfa.verify')}
                </button>
            </div>
        </div>
        </#if>
        <div style="display:flex;gap:8px;margin-top:4px;flex-wrap:wrap">
            <button class="mob-btn mob-btn-primary" style="flex:1;justify-content:center;min-width:100px" onclick="settingsSaveMfa()">
                <i class="fas fa-save"></i> ${msg.get('mob.settings.mfa.save')}
            </button>
            <button class="mob-btn mob-btn-outline" style="flex:1;justify-content:center;min-width:100px" onclick="settingsRegenMfa()">
                <i class="fas fa-sync-alt"></i> ${msg.get('mob.settings.mfa.regen')}
            </button>
            <#if (mfaConfig.secretKey)??>
            <button class="mob-btn mob-btn-danger" style="width:100%;justify-content:center;margin-top:4px" onclick="settingsDeleteMfa()">
                <i class="fas fa-trash"></i> ${msg.get('mob.settings.mfa.delete')}
            </button>
            </#if>
        </div>
    </div>
</div>

<script>
var _settingsI18n = {
    noCurrentPass:     "${msg.get('mob.settings.acc.no.current.pass')}",
    needOneChange:     "${msg.get('mob.settings.acc.need.one.change')}",
    passMismatch:      "${msg.get('mob.settings.acc.pass.mismatch')}",
    saveOk:            "${msg.get('mob.settings.save.ok')}",
    saveFail:          "${msg.get('mob.settings.save.fail')}",
    githubNoUsername:  "${msg.get('mob.settings.github.no.username')}",
    githubIdFound:     "${msg.get('mob.settings.github.id.found')}",
    githubUserNotFound:"${msg.get('mob.settings.github.user.not.found')}",
    githubSaved:       "${msg.get('mob.settings.github.saved')}",
    googleSaved:       "${msg.get('mob.settings.google.saved')}",
    mfaSaved:          "${msg.get('mob.settings.mfa.saved')}",
    mfaRegenTitle:     "${msg.get('mob.settings.mfa.regen.confirm.title')}",
    mfaRegenMsg:       "${msg.get('mob.settings.mfa.regen.confirm.msg')}",
    mfaRegenOk:        "${msg.get('mob.settings.mfa.regen.ok')}",
    mfaRegenFail:      "${msg.get('mob.settings.mfa.regen.fail')}",
    mfaDeleteTitle:    "${msg.get('mob.settings.mfa.delete.confirm.title')}",
    mfaDeleteMsg:      "${msg.get('mob.settings.mfa.delete.confirm.msg')}",
    mfaDeleteOk:       "${msg.get('mob.settings.mfa.delete.ok')}",
    mfaDeleteFail:     "${msg.get('mob.settings.mfa.delete.fail')}",
    mfaCodeInvalid:    "${msg.get('mob.settings.mfa.code.invalid')}",
    mfaVerifyOk:       "${msg.get('mob.settings.mfa.verify.ok')}",
    mfaCodeWrong:      "${msg.get('mob.settings.mfa.code.wrong')}",
    mfaVerifyFail:     "${msg.get('mob.settings.mfa.verify.fail')}",
    saving:            "${msg.get('mob.common.saving')}",
    querying:          "${msg.get('mob.settings.querying')}",
    generating:        "${msg.get('mob.settings.generating')}",
    deleting:          "${msg.get('mob.settings.deleting')}",
    verifying:         "${msg.get('mob.settings.verifying')}",
    requestFail:       "${msg.get('mob.common.request.fail')}"
};
</script>
<#noparse>
<script>
/* ── 折叠展开 ─────────────────────────────────── */
function mobSettingsToggle(id) {
    var body  = document.getElementById(id);
    var arrow = document.getElementById('arrow' + id.charAt(0).toUpperCase() + id.slice(1));
    var open  = body.style.display !== 'none';
    body.style.display  = open ? 'none' : 'block';
    if (arrow) arrow.style.transform = open ? '' : 'rotate(180deg)';
}

/* ── 工具 ─────────────────────────────────────── */
function _csrf()       { return document.querySelector('meta[name="_csrf"]').content; }
function _csrfHeader() { return document.querySelector('meta[name="_csrf_header"]').content; }

async function _post(url, body) {
    var headers = { 'Content-Type': 'application/json' };
    headers[_csrfHeader()] = _csrf();
    var res = await fetch(url, { method: 'POST', headers: headers, body: JSON.stringify(body) });
    if (!res.ok) {
        var text = await res.text();
        throw new Error(text || res.statusText);
    }
    return res;
}

async function _delete(url) {
    var headers = {};
    headers[_csrfHeader()] = _csrf();
    var res = await fetch(url, { method: 'DELETE', headers: headers });
    if (!res.ok) throw new Error(res.statusText);
    return res;
}

/* ── 账号安全 ─────────────────────────────────── */
async function settingsSaveAccount() {
    var current = document.getElementById('accCurrentPass').value.trim();
    var newUser = document.getElementById('accNewUsername').value.trim();
    var newPass = document.getElementById('accNewPass').value.trim();
    var confPass = document.getElementById('accConfirmPass').value.trim();

    if (!current) { mobToast(_settingsI18n.noCurrentPass, 'error'); return; }
    if (!newUser && !newPass) { mobToast(_settingsI18n.needOneChange, 'error'); return; }
    if (newPass && newPass !== confPass) { mobToast(_settingsI18n.passMismatch, 'error'); return; }

    mobShowLoading(_settingsI18n.saving);
    try {
        await _post('/api/system/updatePassword', {
            currentPassword: current,
            newUsername: newUser || null,
            newPassword: newPass || null,
            confirmPassword: confPass || null
        });
        mobToast(_settingsI18n.saveOk, 'success');
        document.getElementById('accCurrentPass').value = '';
        document.getElementById('accNewPass').value = '';
        document.getElementById('accConfirmPass').value = '';
    } catch (e) {
        mobToast(e.message || _settingsI18n.saveFail, 'error');
    } finally {
        mobHideLoading();
    }
}

/* ── GitHub ───────────────────────────────────── */
async function settingsFetchGithubId() {
    var username = document.getElementById('githubUsername').value.trim();
    if (!username) { mobToast(_settingsI18n.githubNoUsername, 'error'); return; }
    mobShowLoading(_settingsI18n.querying);
    try {
        var res  = await fetch('https://api.github.com/users/' + encodeURIComponent(username));
        var json = await res.json();
        if (json.id) {
            document.getElementById('githubId').value = json.id;
            mobToast(_settingsI18n.githubIdFound + ' ' + json.id, 'success');
        } else {
            mobToast(_settingsI18n.githubUserNotFound, 'error');
        }
    } catch (e) {
        mobToast(_settingsI18n.requestFail, 'error');
    } finally {
        mobHideLoading();
    }
}

async function settingsSaveGithub() {
    mobShowLoading(_settingsI18n.saving);
    try {
        await _post('/api/system/updateGithubConfig', {
            enabled:      document.getElementById('githubEnabled').checked,
            username:     document.getElementById('githubUsername').value.trim(),
            githubId:     document.getElementById('githubId').value.trim(),
            clientId:     document.getElementById('githubClientId').value.trim(),
            clientSecret: document.getElementById('githubClientSecret').value.trim(),
            redirectUri:  document.getElementById('githubRedirectUri').value.trim()
        });
        mobToast(_settingsI18n.githubSaved, 'success');
    } catch (e) {
        mobToast(e.message || _settingsI18n.saveFail, 'error');
    } finally {
        mobHideLoading();
    }
}

/* ── Google ───────────────────────────────────── */
async function settingsSaveGoogle() {
    mobShowLoading(_settingsI18n.saving);
    try {
        await _post('/api/system/updateGoogleConfig', {
            enabled:      document.getElementById('googleEnabled').checked,
            email:        document.getElementById('googleEmail').value.trim(),
            clientId:     document.getElementById('googleClientId').value.trim(),
            clientSecret: document.getElementById('googleClientSecret').value.trim(),
            redirectUri:  document.getElementById('googleRedirectUri').value.trim()
        });
        mobToast(_settingsI18n.googleSaved, 'success');
    } catch (e) {
        mobToast(e.message || _settingsI18n.saveFail, 'error');
    } finally {
        mobHideLoading();
    }
}

/* ── MFA ──────────────────────────────────────── */
async function settingsSaveMfa() {
    mobShowLoading(_settingsI18n.saving);
    try {
        await _post('/api/system/updateMfaConfig', {
            enabled: document.getElementById('mfaEnabled').checked,
            issuer:  document.getElementById('mfaIssuer').value.trim()
        });
        mobToast(_settingsI18n.mfaSaved, 'success');
    } catch (e) {
        mobToast(e.message || _settingsI18n.saveFail, 'error');
    } finally {
        mobHideLoading();
    }
}

async function settingsRegenMfa() {
    var ok = await mobConfirm(_settingsI18n.mfaRegenTitle, _settingsI18n.mfaRegenMsg);
    if (!ok) return;
    mobShowLoading(_settingsI18n.generating);
    try {
        await _post('/api/system/regenerateMfaSecret', {});
        mobToast(_settingsI18n.mfaRegenOk, 'success');
        setTimeout(function() { location.reload(); }, 1500);
    } catch (e) {
        mobToast(e.message || _settingsI18n.mfaRegenFail, 'error');
    } finally {
        mobHideLoading();
    }
}

async function settingsDeleteMfa() {
    var ok = await mobConfirm(_settingsI18n.mfaDeleteTitle, _settingsI18n.mfaDeleteMsg);
    if (!ok) return;
    mobShowLoading(_settingsI18n.deleting);
    try {
        await _delete('/api/system/deleteMfaConfig');
        mobToast(_settingsI18n.mfaDeleteOk, 'success');
        setTimeout(function() { location.reload(); }, 1500);
    } catch (e) {
        mobToast(e.message || _settingsI18n.mfaDeleteFail, 'error');
    } finally {
        mobHideLoading();
    }
}

async function settingsVerifyMfa() {
    var code = document.getElementById('mfaVerifyCode').value.trim();
    if (!code || code.length !== 6) { mobToast(_settingsI18n.mfaCodeInvalid, 'error'); return; }
    mobShowLoading(_settingsI18n.verifying);
    try {
        var headers = { 'Content-Type': 'application/json' };
        headers[_csrfHeader()] = _csrf();
        var res  = await fetch('/api/system/verifyMfaCode', {
            method: 'POST',
            headers: headers,
            body: JSON.stringify({ code: code })
        });
        var json = await res.json();
        if (json && json.success !== false) {
            mobToast(_settingsI18n.mfaVerifyOk, 'success');
        } else {
            mobToast(_settingsI18n.mfaCodeWrong, 'error');
        }
    } catch (e) {
        mobToast(_settingsI18n.mfaVerifyFail, 'error');
    } finally {
        mobHideLoading();
    }
}
</script>
</#noparse>

</@layout.page>
