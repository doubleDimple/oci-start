<#import "layout.ftl" as layout>
<@layout.page title="${msg.get('mob.notify.telegram.title')}" activePage="notify-settings">

<!-- ══════════════ Telegram ══════════════ -->
<div class="mob-settings-section">
    <div class="mob-settings-section-header" onclick="mobSettingsToggle('ntTelegram')">
        <div class="mob-settings-section-title">
            <i class="fab fa-telegram-plane" style="color:#2CA5E0"></i>
            ${msg.get('mob.notify.telegram.title')}
        </div>
        <div style="display:flex;align-items:center;gap:10px">
            <label class="mob-sf-toggle" onclick="event.stopPropagation()">
                <input type="checkbox" id="tgEnabled" <#if (telegramConfig.enabled)!false>checked</#if>>
                <span class="mob-sf-toggle-slider"></span>
            </label>
            <i class="fas fa-chevron-down mob-settings-arrow" id="arrowNtTelegram"></i>
        </div>
    </div>
    <div class="mob-settings-body" id="ntTelegram" style="display:none">
        <div class="mob-sf-row">
            <label class="mob-sf-label">Bot Token</label>
            <input class="mob-sf-input" type="text" id="tgBotToken" value="${(telegramConfig.botToken)!''}" placeholder="${msg.get('mob.notify.telegram.title')}">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">Chat ID</label>
            <input class="mob-sf-input" type="text" id="tgChatId" value="${(telegramConfig.chatId)!''}" placeholder="Chat ID">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">Chat ${msg.get('mob.common.user.default')}</label>
            <input class="mob-sf-input" type="text" id="tgChatName" value="${(telegramConfig.chatName)!''}" placeholder="${msg.get('mob.common.user.default')}">
        </div>
        <div style="display:flex;gap:8px;margin-top:12px">
            <button class="mob-btn mob-btn-primary" style="flex:1;justify-content:center" onclick="ntSaveTelegram()">
                <i class="fas fa-save"></i> ${msg.get('mob.notify.save')}
            </button>
            <button class="mob-btn mob-btn-outline" style="flex:1;justify-content:center" onclick="ntTestTelegram()">
                <i class="fas fa-paper-plane"></i> ${msg.get('mob.notify.test')}
            </button>
        </div>
    </div>
</div>

<!-- ══════════════ Telegram 代理 ══════════════ -->
<div class="mob-settings-section">
    <div class="mob-settings-section-header" onclick="mobSettingsToggle('ntProxy')">
        <div class="mob-settings-section-title">
            <i class="fas fa-exchange-alt" style="color:#7289da"></i>
            ${msg.get('mob.notify.proxy.title')}
        </div>
        <div style="display:flex;align-items:center;gap:10px">
            <label class="mob-sf-toggle" onclick="event.stopPropagation()">
                <input type="checkbox" id="proxyEnabled" <#if (proxyConfig.enabled)!false>checked</#if>>
                <span class="mob-sf-toggle-slider"></span>
            </label>
            <i class="fas fa-chevron-down mob-settings-arrow" id="arrowNtProxy"></i>
        </div>
    </div>
    <div class="mob-settings-body" id="ntProxy" style="display:none">
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.notify.proxy.type')}</label>
            <select class="mob-sf-input" id="proxyType">
                <option value="HTTP" <#if (proxyConfig.type!'HTTP') == 'HTTP'>selected</#if>>HTTP</option>
                <option value="HTTPS" <#if (proxyConfig.type!'') == 'HTTPS'>selected</#if>>HTTPS</option>
                <option value="SOCKS5" <#if (proxyConfig.type!'') == 'SOCKS5'>selected</#if>>SOCKS5</option>
            </select>
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.notify.proxy.host')}</label>
            <input class="mob-sf-input" type="text" id="proxyHost" value="${(proxyConfig.host)!'127.0.0.1'}" placeholder="127.0.0.1">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.notify.proxy.port')}</label>
            <input class="mob-sf-input" type="number" id="proxyPort" value="${(proxyConfig.port)?string!'7890'}" placeholder="7890" maxlength="5">
        </div>
        <div style="display:flex;gap:8px;margin-top:12px">
            <button class="mob-btn mob-btn-primary" style="flex:1;justify-content:center" onclick="ntSaveProxy()">
                <i class="fas fa-save"></i> ${msg.get('mob.notify.save')}
            </button>
            <button class="mob-btn mob-btn-outline" style="flex:1;justify-content:center" onclick="ntTestProxy()">
                <i class="fas fa-plug"></i> ${msg.get('mob.notify.test.connection')}
            </button>
        </div>
    </div>
</div>

<!-- ══════════════ 钉钉 ══════════════ -->
<div class="mob-settings-section">
    <div class="mob-settings-section-header" onclick="mobSettingsToggle('ntDingTalk')">
        <div class="mob-settings-section-title">
            <i class="fas fa-comments" style="color:#2196f3"></i>
            ${msg.get('mob.notify.dingtalk.title')}
        </div>
        <div style="display:flex;align-items:center;gap:10px">
            <label class="mob-sf-toggle" onclick="event.stopPropagation()">
                <input type="checkbox" id="ddEnabled" <#if (dingTalkConfig.enabled)!false>checked</#if>>
                <span class="mob-sf-toggle-slider"></span>
            </label>
            <i class="fas fa-chevron-down mob-settings-arrow" id="arrowNtDingTalk"></i>
        </div>
    </div>
    <div class="mob-settings-body" id="ntDingTalk" style="display:none">
        <div class="mob-sf-row">
            <label class="mob-sf-label">Webhook</label>
            <input class="mob-sf-input" type="text" id="ddWebhook" value="${(dingTalkConfig.webhook)!''}" placeholder="https://oapi.dingtalk.com/robot/send?...">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">Secret</label>
            <input class="mob-sf-input" type="text" id="ddSecret" value="${(dingTalkConfig.secret)!''}" placeholder="SEC...">
        </div>
        <div style="display:flex;gap:8px;margin-top:12px">
            <button class="mob-btn mob-btn-primary" style="flex:1;justify-content:center" onclick="ntSaveDingTalk()">
                <i class="fas fa-save"></i> ${msg.get('mob.notify.save')}
            </button>
            <button class="mob-btn mob-btn-outline" style="flex:1;justify-content:center" onclick="ntTestDingTalk()">
                <i class="fas fa-paper-plane"></i> ${msg.get('mob.notify.test')}
            </button>
        </div>
    </div>
</div>

<!-- ══════════════ Bark ══════════════ -->
<div class="mob-settings-section">
    <div class="mob-settings-section-header" onclick="mobSettingsToggle('ntBark')">
        <div class="mob-settings-section-title">
            <i class="fas fa-bell" style="color:#ff9500"></i>
            ${msg.get('mob.notify.bark.title')}
        </div>
        <div style="display:flex;align-items:center;gap:10px">
            <label class="mob-sf-toggle" onclick="event.stopPropagation()">
                <input type="checkbox" id="barkEnabled" <#if (barkConfig.enabled)!false>checked</#if>>
                <span class="mob-sf-toggle-slider"></span>
            </label>
            <i class="fas fa-chevron-down mob-settings-arrow" id="arrowNtBark"></i>
        </div>
    </div>
    <div class="mob-settings-body" id="ntBark" style="display:none">
        <div class="mob-sf-row">
            <label class="mob-sf-label">Bark URL</label>
            <input class="mob-sf-input" type="text" id="barkUrl" value="${(barkConfig.url)!''}" placeholder="https://api.day.app">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">Device Key</label>
            <input class="mob-sf-input" type="text" id="barkDeviceKey" value="${(barkConfig.deviceKey)!''}" placeholder="Device Key">
        </div>
        <div style="display:flex;gap:8px;margin-top:12px">
            <button class="mob-btn mob-btn-primary" style="flex:1;justify-content:center" onclick="ntSaveBark()">
                <i class="fas fa-save"></i> ${msg.get('mob.notify.save')}
            </button>
            <button class="mob-btn mob-btn-outline" style="flex:1;justify-content:center" onclick="ntTestBark()">
                <i class="fas fa-paper-plane"></i> ${msg.get('mob.notify.test')}
            </button>
        </div>
    </div>
</div>

<!-- ══════════════ 飞书 ══════════════ -->
<div class="mob-settings-section">
    <div class="mob-settings-section-header" onclick="mobSettingsToggle('ntFeishu')">
        <div class="mob-settings-section-title">
            <i class="fas fa-comments" style="color:#3370ff"></i>
            ${msg.get('mob.notify.feishu.title')}
        </div>
        <div style="display:flex;align-items:center;gap:10px">
            <label class="mob-sf-toggle" onclick="event.stopPropagation()">
                <input type="checkbox" id="fsEnabled" <#if (feishuConfig.enabled)!false>checked</#if>>
                <span class="mob-sf-toggle-slider"></span>
            </label>
            <i class="fas fa-chevron-down mob-settings-arrow" id="arrowNtFeishu"></i>
        </div>
    </div>
    <div class="mob-settings-body" id="ntFeishu" style="display:none">
        <div class="mob-sf-row">
            <label class="mob-sf-label">Webhook</label>
            <input class="mob-sf-input" type="text" id="fsWebhook" value="${(feishuConfig.webhook)!''}" placeholder="https://open.feishu.cn/open-apis/bot/v2/hook/...">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.notify.secret.optional')}</label>
            <input class="mob-sf-input" type="text" id="fsSecret" value="${(feishuConfig.secret)!''}" placeholder="${msg.get('mob.notify.secret.optional')}">
        </div>
        <div style="display:flex;gap:8px;margin-top:12px">
            <button class="mob-btn mob-btn-primary" style="flex:1;justify-content:center" onclick="ntSaveFeishu()">
                <i class="fas fa-save"></i> ${msg.get('mob.notify.save')}
            </button>
            <button class="mob-btn mob-btn-outline" style="flex:1;justify-content:center" onclick="ntTestFeishu()">
                <i class="fas fa-paper-plane"></i> ${msg.get('mob.notify.test')}
            </button>
        </div>
    </div>
</div>

<!-- ══════════════ 定时任务 ══════════════ -->
<div class="mob-settings-section" style="margin-bottom:0">
    <div class="mob-settings-section-header" onclick="mobSettingsToggle('ntTask')">
        <div class="mob-settings-section-title">
            <i class="fas fa-clock" style="color:#43b581"></i>
            ${msg.get('mob.notify.task.title')}
        </div>
        <div style="display:flex;align-items:center;gap:10px">
            <label class="mob-sf-toggle" onclick="event.stopPropagation()">
                <input type="checkbox" id="taskEnabled" <#if (taskConfig.enabled)!false>checked</#if>>
                <span class="mob-sf-toggle-slider"></span>
            </label>
            <i class="fas fa-chevron-down mob-settings-arrow" id="arrowNtTask"></i>
        </div>
    </div>
    <div class="mob-settings-body" id="ntTask" style="display:none">
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.notify.task.hour')}</label>
            <input class="mob-sf-input" type="number" id="taskHour" value="${(taskConfig.executeHour)?string!'8'}" min="0" max="23" placeholder="8">
        </div>
        <div class="mob-sf-row">
            <label class="mob-sf-label">${msg.get('mob.notify.secret.optional')}</label>
            <input class="mob-sf-input" type="text" id="taskSecret" value="${(taskConfig.notificationSecret)!''}" placeholder="${msg.get('mob.notify.secret.optional')}">
        </div>
        <div class="mob-sf-row" style="gap:12px">
            <label class="mob-sf-label">${msg.get('mob.notify.task.content')}</label>
            <label class="mob-notify-check">
                <input type="checkbox" id="taskAccount" <#if (taskConfig.enableAccountCheck)!false>checked</#if>>
                <span>${msg.get('mob.notify.task.account')}</span>
            </label>
            <label class="mob-notify-check">
                <input type="checkbox" id="taskBootLog" <#if (taskConfig.enableBootLog)!false>checked</#if>>
                <span>${msg.get('mob.notify.task.boot.log')}</span>
            </label>
            <label class="mob-notify-check">
                <input type="checkbox" id="taskCost" <#if (taskConfig.enableCostCheck)!false>checked</#if>>
                <span>${msg.get('mob.notify.task.cost')}</span>
            </label>
        </div>
        <button class="mob-btn mob-btn-primary mob-btn-full" style="margin-top:12px" onclick="ntSaveTask()">
            <i class="fas fa-save"></i> ${msg.get('mob.notify.task.save')}
        </button>
    </div>
</div>

<script>
var _ntI18n = {
    saving:          "${msg.get('mob.common.saving')}",
    sending:         "${msg.get('mob.notify.sending')}",
    testingConn:     "${msg.get('mob.notify.testing.conn')}",
    msgSent:         "${msg.get('mob.notify.msg.sent')}",
    telegramSaved:   "${msg.get('mob.notify.telegram.saved')}",
    proxySaved:      "${msg.get('mob.notify.proxy.saved')}",
    proxyConnOk:     "${msg.get('mob.notify.proxy.conn.ok')}",
    proxyConnFail:   "${msg.get('mob.notify.proxy.conn.fail')}",
    proxyTestFail:   "${msg.get('mob.notify.proxy.test.fail')}",
    dingtalkSaved:   "${msg.get('mob.notify.dingtalk.saved')}",
    barkSaved:       "${msg.get('mob.notify.bark.saved')}",
    feishuSaved:     "${msg.get('mob.notify.feishu.saved')}",
    taskSaved:       "${msg.get('mob.notify.task.saved')}",
    taskHourRange:   "${msg.get('mob.notify.task.hour.range')}",
    webhookFormat:   "${msg.get('mob.notify.webhook.format')}",
    saveFail:        "${msg.get('mob.notify.save.fail')}",
    sendFail:        "${msg.get('mob.notify.send.fail')}"
};
</script>
<#noparse>
<script>
/* ── 折叠展开 ── */
function mobSettingsToggle(id) {
    var body  = document.getElementById(id);
    var key   = id.charAt(0).toUpperCase() + id.slice(1);
    var arrow = document.getElementById('arrow' + key);
    var open  = body.style.display !== 'none';
    body.style.display  = open ? 'none' : 'block';
    if (arrow) arrow.style.transform = open ? '' : 'rotate(180deg)';
}

/* ── CSRF 工具 ── */
function _nt_csrf()       { return document.querySelector('meta[name="_csrf"]').content; }
function _nt_csrfHeader() { return document.querySelector('meta[name="_csrf_header"]').content; }

async function _ntPost(url, body) {
    var h = { 'Content-Type': 'application/json' };
    h[_nt_csrfHeader()] = _nt_csrf();
    var res = await fetch(url, { method: 'POST', headers: h, body: JSON.stringify(body) });
    if (!res.ok) { var t = await res.text(); throw new Error(t || res.statusText); }
    return res;
}

/* ── Telegram ── */
async function ntSaveTelegram() {
    mobShowLoading(_ntI18n.saving);
    try {
        await _ntPost('/api/system/updateTelegramConfig', {
            enabled:  document.getElementById('tgEnabled').checked,
            botToken: document.getElementById('tgBotToken').value.trim(),
            chatId:   document.getElementById('tgChatId').value.trim(),
            chatName: document.getElementById('tgChatName').value.trim()
        });
        mobToast(_ntI18n.telegramSaved, 'success');
    } catch(e) { mobToast(e.message || _ntI18n.saveFail, 'error'); }
    finally { mobHideLoading(); }
}

async function ntTestTelegram() {
    mobShowLoading(_ntI18n.sending);
    try {
        await _ntPost('/api/system/testTgTalk', {});
        mobToast(_ntI18n.msgSent, 'success');
    } catch(e) { mobToast(e.message || _ntI18n.sendFail, 'error'); }
    finally { mobHideLoading(); }
}

/* ── 代理 ── */
async function ntSaveProxy() {
    mobShowLoading(_ntI18n.saving);
    try {
        await _ntPost('/api/system/updateProxyConfig', {
            enabled: document.getElementById('proxyEnabled').checked,
            type:    document.getElementById('proxyType').value,
            host:    document.getElementById('proxyHost').value.trim(),
            port:    parseInt(document.getElementById('proxyPort').value) || 7890
        });
        mobToast(_ntI18n.proxySaved, 'success');
    } catch(e) { mobToast(e.message || _ntI18n.saveFail, 'error'); }
    finally { mobHideLoading(); }
}

async function ntTestProxy() {
    mobShowLoading(_ntI18n.testingConn);
    try {
        var res = await fetch('/api/system/testProxyConnection', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', [_nt_csrfHeader()]: _nt_csrf() },
            body: JSON.stringify({
                enabled: true,
                type:  document.getElementById('proxyType').value,
                host:  document.getElementById('proxyHost').value.trim(),
                port:  parseInt(document.getElementById('proxyPort').value) || 7890
            })
        });
        var json = await res.json();
        mobToast(json.message || (json.success ? _ntI18n.proxyConnOk : _ntI18n.proxyConnFail), json.success ? 'success' : 'error');
    } catch(e) { mobToast(_ntI18n.proxyTestFail, 'error'); }
    finally { mobHideLoading(); }
}

/* ── 钉钉 ── */
async function ntSaveDingTalk() {
    var webhook = document.getElementById('ddWebhook').value.trim();
    if (webhook && !webhook.startsWith('https://oapi.dingtalk.com/robot/send')) {
        mobToast(_ntI18n.webhookFormat, 'error'); return;
    }
    mobShowLoading(_ntI18n.saving);
    try {
        await _ntPost('/api/system/updateDingTalkConfig', {
            enabled: document.getElementById('ddEnabled').checked,
            webhook: webhook,
            secret:  document.getElementById('ddSecret').value.trim()
        });
        mobToast(_ntI18n.dingtalkSaved, 'success');
    } catch(e) { mobToast(e.message || _ntI18n.saveFail, 'error'); }
    finally { mobHideLoading(); }
}

async function ntTestDingTalk() {
    mobShowLoading(_ntI18n.sending);
    try {
        await _ntPost('/api/system/testDingTalk', {});
        mobToast(_ntI18n.msgSent, 'success');
    } catch(e) { mobToast(e.message || _ntI18n.sendFail, 'error'); }
    finally { mobHideLoading(); }
}

/* ── Bark ── */
async function ntSaveBark() {
    mobShowLoading(_ntI18n.saving);
    try {
        await _ntPost('/api/system/updateBarkConfig', {
            enabled:   document.getElementById('barkEnabled').checked,
            url:       document.getElementById('barkUrl').value.trim(),
            deviceKey: document.getElementById('barkDeviceKey').value.trim()
        });
        mobToast(_ntI18n.barkSaved, 'success');
    } catch(e) { mobToast(e.message || _ntI18n.saveFail, 'error'); }
    finally { mobHideLoading(); }
}

async function ntTestBark() {
    mobShowLoading(_ntI18n.sending);
    try {
        await _ntPost('/api/system/testBark', {});
        mobToast(_ntI18n.msgSent, 'success');
    } catch(e) { mobToast(e.message || _ntI18n.sendFail, 'error'); }
    finally { mobHideLoading(); }
}

/* ── 飞书 ── */
async function ntSaveFeishu() {
    mobShowLoading(_ntI18n.saving);
    try {
        await _ntPost('/api/system/updateFeishuConfig', {
            enabled: document.getElementById('fsEnabled').checked,
            webhook: document.getElementById('fsWebhook').value.trim(),
            secret:  document.getElementById('fsSecret').value.trim()
        });
        mobToast(_ntI18n.feishuSaved, 'success');
    } catch(e) { mobToast(e.message || _ntI18n.saveFail, 'error'); }
    finally { mobHideLoading(); }
}

async function ntTestFeishu() {
    mobShowLoading(_ntI18n.sending);
    try {
        await _ntPost('/api/system/testFeishu', {});
        mobToast(_ntI18n.msgSent, 'success');
    } catch(e) { mobToast(e.message || _ntI18n.sendFail, 'error'); }
    finally { mobHideLoading(); }
}

/* ── 定时任务 ── */
async function ntSaveTask() {
    var hour = parseInt(document.getElementById('taskHour').value);
    if (isNaN(hour) || hour < 0 || hour > 23) {
        mobToast(_ntI18n.taskHourRange, 'error'); return;
    }
    mobShowLoading(_ntI18n.saving);
    try {
        await _ntPost('/api/system/updateTaskConfig', {
            enabled:              document.getElementById('taskEnabled').checked,
            executeHour:          hour,
            notificationSecret:   document.getElementById('taskSecret').value.trim(),
            enableAccountCheck:   document.getElementById('taskAccount').checked,
            enableBootLog:        document.getElementById('taskBootLog').checked,
            enableCostCheck:      document.getElementById('taskCost').checked
        });
        mobToast(_ntI18n.taskSaved, 'success');
    } catch(e) { mobToast(e.message || _ntI18n.saveFail, 'error'); }
    finally { mobHideLoading(); }
}
</script>
</#noparse>

</@layout.page>
