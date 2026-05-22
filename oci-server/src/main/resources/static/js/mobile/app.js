/**
 * OCI-START 移动端核心 JS
 */

/* ── Sheet 状态 ─────────────────────────────────────── */
var _currentSheet = null;
var _quickBootTenantId = null;
var _quickBootRegion = null;

/* ── DD OS 数据 ─────────────────────────────────────── */
var _ddOsData = {
    'Alpine': [['3.19','alpine|3.19'],['3.20','alpine|3.20'],['3.21','alpine|3.21'],['3.22','alpine|3.22']],
    'Debian': [['9','debian|9'],['10','debian|10'],['11','debian|11'],['12','debian|12'],['13','debian|13']],
    'Ubuntu': [['16.04','ubuntu|16.04'],['18.04','ubuntu|18.04'],['20.04','ubuntu|20.04'],['22.04','ubuntu|22.04'],['24.04','ubuntu|24.04'],['25.10','ubuntu|25.10']],
    'RHEL':   [['CentOS 9','centos|9'],['CentOS 10','centos|10'],['Rocky 8','rocky|8'],['Rocky 9','rocky|9'],['Rocky 10','rocky|10'],
               ['AlmaLinux 8','almalinux|8'],['AlmaLinux 9','almalinux|9'],['AlmaLinux 10','almalinux|10'],
               ['Oracle 8','oracle|8'],['Oracle 9','oracle|9'],['Oracle 10','oracle|10'],
               ['Fedora 41','fedora|41'],['Fedora 42','fedora|42']],
    'Other':  [['Anolis 7','anolis|7'],['Anolis 8','anolis|8'],['Anolis 23','anolis|23'],
               ['OpenCloudOS 8','opencloudos|8'],['OpenCloudOS 9','opencloudos|9'],
               ['OpenEuler 20.03','openeuler|20.03'],['OpenEuler 22.03','openeuler|22.03'],
               ['OpenEuler 24.03','openeuler|24.03'],['OpenEuler 25.09','openeuler|25.09'],
               ['OpenSUSE 15.6','opensuse|15.6'],['OpenSUSE 16.0','opensuse|16.0'],
               ['OpenSUSE Tumbleweed','opensuse|tumbleweed'],
               ['NixOS 25.05','nixos|25.05'],['Kali Linux','kali|'],['Arch Linux','arch|'],
               ['Gentoo','gentoo|'],['AOSC','aosc|'],['FNOS','fnos|'],['Netboot.xyz','netboot.xyz|']]
};
var _ddSelectedFamily = '';

function ddPickFamily(family) {
    _ddSelectedFamily = family;
    document.querySelectorAll('.dd-family-btn').forEach(function(b) {
        b.classList.toggle('active', b.querySelector('span') && b.querySelector('span').textContent === family);
    });
    document.getElementById('instDDOsValue').value = '';
    document.getElementById('ddSelectedShow').style.display = 'none';
    document.getElementById('ddFamilyLabel').textContent = family;
    var versions = _ddOsData[family] || [];
    document.getElementById('ddVerGrid').innerHTML = versions.map(function(v) {
        return '<button class="dd-ver-btn" onclick="ddPickVersion(\'' + v[1].replace(/'/g,"\\'") + '\',\'' + v[0].replace(/'/g,"\\'") + '\')">' + v[0] + '</button>';
    }).join('');
    document.getElementById('ddVersionArea').style.display = 'block';
}

function ddPickVersion(value, label) {
    document.getElementById('instDDOsValue').value = value;
    document.querySelectorAll('.dd-ver-btn').forEach(function(b) {
        b.classList.toggle('active', b.textContent === label);
    });
    var badge = document.getElementById('ddSelectedShow');
    badge.textContent = '✓ ' + _ddSelectedFamily + ' ' + label;
    badge.style.display = 'block';
}

/* ── 打开/关闭 Sheet ─────────────────────────────────── */
function mobOpenSheet(sheetId) {
    if (_currentSheet) {
        document.getElementById(_currentSheet).classList.remove('active');
    }
    // 关闭日志 WS（如果切换到其他 sheet）
    if (_currentSheet === 'syslogSheet' && sheetId !== 'syslogSheet') {
        _syslogDisconnect();
    }
    _currentSheet = sheetId;
    document.getElementById('mobOverlay').classList.add('active');
    document.getElementById(sheetId).classList.add('active');
    document.body.style.overflow = 'hidden';
}

function mobCloseSheet() {
    if (_currentSheet === 'syslogSheet') {
        _syslogDisconnect();
    }
    if (_currentSheet) {
        document.getElementById(_currentSheet).classList.remove('active');
        _currentSheet = null;
    }
    document.getElementById('mobOverlay').classList.remove('active');
    document.body.style.overflow = '';
}

document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape') {
        closeRegionInstanceModal();
        mobCloseSheet();
        mobCloseModal();
        mobConfirmClose(false);
        _mobCloseUserMenu();
        mobCloseDrawer();
    }
});

/* ── 居中弹窗（消息/语言）─────────────────────────── */
var _currentModal = null;
function mobOpenModal(id) {
    if (_currentModal && _currentModal !== id) {
        document.getElementById(_currentModal).classList.remove('show');
    }
    _currentModal = id;
    document.getElementById('mobCenterMask').classList.add('show');
    document.getElementById(id).classList.add('show');
    document.body.style.overflow = 'hidden';
}
function mobCloseModal() {
    if (_currentModal) {
        document.getElementById(_currentModal).classList.remove('show');
        _currentModal = null;
    }
    var mask = document.getElementById('mobCenterMask');
    if (mask) mask.classList.remove('show');
    document.body.style.overflow = '';
}

/* ── 全局加载遮罩 ───────────────────────────────────── */
function mobShowLoading(msg) {
    var el = document.getElementById('mobGlobalLoading');
    var msgEl = document.getElementById('mobGlobalLoadingMsg');
    if (!el) return;
    if (msgEl) msgEl.textContent = msg || '处理中...';
    el.classList.add('show');
}

function mobHideLoading() {
    var el = document.getElementById('mobGlobalLoading');
    if (el) el.classList.remove('show');
}

/* ── Toast 提示 ─────────────────────────────────────── */
var _toastTimer = null;
function mobToast(msg, type) {
    var toast = document.getElementById('mobToast');
    if (!toast) return;
    toast.textContent = msg;
    toast.className = 'mob-toast show ' + (type || '');
    clearTimeout(_toastTimer);
    _toastTimer = setTimeout(function() {
        toast.classList.remove('show');
    }, 2500);
}

/* ── 通用复制（兼容 HTTP / HTTPS）──────────────────── */
function mobCopy(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(function() {
            mobToast('已复制 ' + text, 'success');
        }).catch(function() {
            _mobCopyFallback(text);
        });
    } else {
        _mobCopyFallback(text);
    }
}

function _mobCopyFallback(text) {
    var ta = document.createElement('textarea');
    ta.value = text;
    ta.style.cssText = 'position:fixed;top:0;left:0;opacity:0;';
    document.body.appendChild(ta);
    ta.focus();
    ta.select();
    try {
        document.execCommand('copy');
        mobToast('已复制 ' + text, 'success');
    } catch (e) {
        mobToast('复制失败，请手动复制', 'error');
    }
    document.body.removeChild(ta);
}

/* ── 密码生成 ───────────────────────────────────────── */
function _mobGenPassword() {
    var chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    var pwd = '';
    pwd += 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'[Math.floor(Math.random() * 26)];
    pwd += 'abcdefghijklmnopqrstuvwxyz'[Math.floor(Math.random() * 26)];
    pwd += '0123456789'[Math.floor(Math.random() * 10)];
    for (var i = 3; i < 16; i++) {
        pwd += chars[Math.floor(Math.random() * chars.length)];
    }
    return pwd.split('').sort(function() { return Math.random() - 0.5; }).join('');
}

/* ── 左侧抽屉菜单 ────────────────────────────────────── */
function mobOpenDrawer() {
    document.getElementById('mobDrawer').classList.add('open');
    document.getElementById('mobDrawerOverlay').classList.add('open');
    document.body.style.overflow = 'hidden';
}

function mobCloseDrawer() {
    document.getElementById('mobDrawer').classList.remove('open');
    document.getElementById('mobDrawerOverlay').classList.remove('open');
    document.body.style.overflow = '';
}

/* ── 关于 Sheet ──────────────────────────────────────── */
function mobShowAbout() {
    mobCloseDrawer();
    var cur = document.getElementById('versionCurrent');
    var lat = document.getElementById('versionLatest');
    var aCur = document.getElementById('aboutVersionCurrent');
    var aLat = document.getElementById('aboutVersionLatest');
    if (aCur && cur) aCur.textContent = cur.textContent;
    if (aLat && lat) aLat.textContent = lat.textContent;
    mobOpenSheet('aboutSheet');
}

/* ── 用户下拉菜单 ────────────────────────────────────── */
function mobToggleUserMenu(e) {
    e.stopPropagation();
    var menu = document.getElementById('mobUserMenu');
    if (!menu) return;
    var isOpen = menu.classList.contains('open');
    if (isOpen) {
        menu.classList.remove('open');
    } else {
        menu.classList.add('open');
        setTimeout(function() {
            document.addEventListener('click', _mobCloseMenuOnce);
        }, 0);
    }
}

function _mobCloseUserMenu() {
    var menu = document.getElementById('mobUserMenu');
    if (menu) menu.classList.remove('open');
}

function _mobCloseMenuOnce() {
    _mobCloseUserMenu();
    document.removeEventListener('click', _mobCloseMenuOnce);
}

/* ── 全局确认对话框 ──────────────────────────────────── */
var _mobConfirmResolve = null;

function mobConfirm(title, msg) {
    return new Promise(function(resolve) {
        _mobConfirmResolve = resolve;
        document.getElementById('mobConfirmTitle').textContent = title;
        document.getElementById('mobConfirmMsg').textContent = msg;
        document.getElementById('mobConfirmMask').classList.add('show');
        document.getElementById('mobConfirmSheet').classList.add('show');
    });
}

function mobConfirmClose(result) {
    var mask  = document.getElementById('mobConfirmMask');
    var sheet = document.getElementById('mobConfirmSheet');
    if (mask)  mask.classList.remove('show');
    if (sheet) sheet.classList.remove('show');
    if (_mobConfirmResolve) {
        _mobConfirmResolve(result);
        _mobConfirmResolve = null;
    }
}

/* ── 快速开机 ──────────────────────────────────────── */
function showQuickBoot(tenantId, region) {
    _quickBootTenantId = tenantId;
    _quickBootRegion = region;
    document.getElementById('quickBootRegionLabel').textContent = region + ' · 选择架构开始抢机';
    document.getElementById('quickBootOverlay').style.display = 'flex';
    document.body.style.overflow = 'hidden';
}

function closeQuickBoot(e) {
    if (e && e.target !== document.getElementById('quickBootOverlay')) return;
    document.getElementById('quickBootOverlay').style.display = 'none';
    document.body.style.overflow = '';
}

async function mobQuickBoot(arch) {
    if (!_quickBootTenantId) return;

    document.getElementById('quickBootOverlay').style.display = 'none';
    document.body.style.overflow = '';
    mobShowLoading('正在创建 ' + arch + ' 开机任务...');

    var csrf = document.querySelector('meta[name="_csrf"]').content;
    var csrfHeader = document.querySelector('meta[name="_csrf_header"]').content;

    var params = {
        tenantId:     _quickBootTenantId,
        architecture: arch,
        ocpu:         arch === 'ARM' ? 1 : 1,
        memory:       arch === 'ARM' ? 6 : 1,
        disk:         50,
        loopTime:     60,
        instanceCount: 1,
        rootPassword: _mobGenPassword()
    };

    var body = Object.keys(params).map(function(k) {
        return encodeURIComponent(k) + '=' + encodeURIComponent(params[k]);
    }).join('&');

    try {
        var res = await fetch('/tenants/boot/save', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                [csrfHeader]: csrf
            },
            body: body
        });
        var json = await res.json();
        mobHideLoading();
        if (json.success || json.code === 200) {
            mobToast('已添加 ' + arch + ' 开机任务', 'success');
            setTimeout(function() { window.location.href = '/m/boot'; }, 1000);
        } else {
            mobToast(json.message || '创建失败', 'error');
        }
    } catch (e) {
        mobHideLoading();
        mobToast('网络错误，请重试', 'error');
    }
}

/* ── 区域实例列表（居中弹框 + 分页）────────────────── */
var _instList      = [];
var _instPage      = 1;
var _instPerPage   = 4;
var _instPageItems = [];   // 当前分页数据
var _currentOpsInst = null; // 当前操作的实例对象
var _opsInputSubmitFn = null; // 通用输入框确认回调
var _instDDEs      = null;  // DD SSE EventSource

async function showRegionInstances(tenantId, region) {
    _instCurrentTenantId = tenantId;
    _instCurrentRegion   = region;
    _instList = [];
    _instPage = 1;
    document.getElementById('regionInstanceTitle').textContent = region + ' 实例';
    document.getElementById('regionInstanceSubtitle').textContent = '加载中...';
    document.getElementById('regionInstanceContent').innerHTML =
        '<div class="mob-loading"><div class="mob-spinner"></div><p>加载中...</p></div>';
    document.getElementById('regionInstancePager').style.display = 'none';
    document.getElementById('regionInstanceModal').style.display = 'flex';
    document.body.style.overflow = 'hidden';

    try {
        var res  = await fetch('/m/api/regions/' + tenantId + '/instances?size=200');
        var json = await res.json();
        var data = json.data || {};
        _instList = data.list || [];

        var total = data.total || _instList.length;
        document.getElementById('regionInstanceSubtitle').textContent = '共 ' + total + ' 个实例';

        if (_instList.length === 0) {
            document.getElementById('regionInstanceContent').innerHTML =
                '<div class="mob-empty"><i class="fas fa-server"></i><p>该区域暂无实例</p></div>';
            return;
        }
        _renderInstPage();
    } catch (e) {
        document.getElementById('regionInstanceContent').innerHTML =
            '<p style="color:#f04747;text-align:center;padding:20px">加载失败: ' + e.message + '</p>';
        document.getElementById('regionInstanceSubtitle').textContent = '';
    }
}

function _renderInstPage() {
    var total      = _instList.length;
    var totalPages = Math.max(1, Math.ceil(total / _instPerPage));
    _instPage      = Math.min(Math.max(1, _instPage), totalPages);

    var start = (_instPage - 1) * _instPerPage;
    var items = _instList.slice(start, start + _instPerPage);
    _instPageItems = items;

    var i18n = window.MOB_I18N || {};

    var html = '<div class="mirc-list">' +
        items.map(function(inst, idx) {
            var state     = (inst.state || '').toUpperCase();
            var isRunning = state === 'RUNNING';
            var isProv    = state === 'PROVISIONING' || state === 'STARTING' || state === 'STOPPING';
            var dotCls    = isRunning ? 'mirc-dot-green' : (isProv ? 'mirc-dot-yellow' : 'mirc-dot-gray');
            var badgeCls  = isRunning ? 'running' : (isProv ? 'starting' : 'stopped');
            var stateLabel= isRunning ? (i18n.instStateRunning || 'RUNNING')
                          : (isProv   ? (i18n.instStateStarting || 'BUSY')
                                      : (i18n.instStateStopped  || 'STOPPED'));
            var ip   = inst.publicIps || '';
            var arch = inst.architecture || '';
            var name = inst.displayName || inst.instanceId || (i18n.unnamed || '未命名');
            var spec = (inst.ocpus || '?') + 'C·' + (inst.memoryInGBs || '?') + 'G';
            var shapeShort = (inst.shape || '')
                .replace('VM.Standard.', '').replace('VM.Optimized3.', '')
                .replace('VM.DenseIO2.', '').replace('VM.DenseIO3.', '').replace('VM.', '');
            var detail = [arch, shapeShort, spec].filter(Boolean).join(' · ');

            var startStopBtn;
            if (isProv) {
                startStopBtn = '<button class="mirc-qa busy" disabled>'
                    + '<i class="fas fa-circle-notch fa-spin"></i>'
                    + '<span>' + (i18n.instActionBusy || '处理中') + '</span></button>';
            } else if (isRunning) {
                startStopBtn = '<button class="mirc-qa stop" onclick="instCardOp(' + idx + ',\'stop\')">'
                    + '<i class="fas fa-stop-circle"></i><span>' + (i18n.opsStop || '停止') + '</span></button>';
            } else {
                startStopBtn = '<button class="mirc-qa start" onclick="instCardOp(' + idx + ',\'start\')">'
                    + '<i class="fas fa-play-circle"></i><span>' + (i18n.opsStart || '启动') + '</span></button>';
            }

            return '<div class="mirc-card">'
                // ── 顶部信息区 ──
                + '<div class="mirc-head">'
                +   '<span class="mirc-dot ' + dotCls + '"></span>'
                +   '<div class="mirc-meta">'
                +     '<div class="mirc-name">' + escHtmlSafe(name) + '</div>'
                +     '<div class="mirc-sub">'
                +       (ip ? '<span class="mirc-ip">' + escHtmlSafe(ip) + '</span>'
                             + '<button class="mirc-copy-btn" onclick="mobCopy(\'' + escHtmlSafe(ip) + '\')">'
                             + '<i class="fas fa-copy"></i></button>' : '')
                +       (detail ? '<span class="mirc-spec">' + escHtmlSafe(detail) + '</span>' : '')
                +     '</div>'
                +   '</div>'
                +   '<span class="mirc-badge ' + badgeCls + '">' + stateLabel + '</span>'
                + '</div>'
                // ── 快捷操作栏 ──
                + '<div class="mirc-actions">'
                +   startStopBtn
                +   '<button class="mirc-qa config" onclick="instCardOp(' + idx + ',\'config\')">'
                +     '<i class="fas fa-cog"></i><span>' + (i18n.opsConfig || '配置') + '</span></button>'
                +   '<button class="mirc-qa ip" onclick="instCardOp(' + idx + ',\'changeip\')">'
                +     '<i class="fas fa-sync-alt"></i><span>' + (i18n.opsChangeIp || '换IP') + '</span></button>'
                +   '<button class="mirc-qa rescue" onclick="instCardOp(' + idx + ',\'rescue\')">'
                +     '<i class="fas fa-life-ring"></i><span>' + (i18n.opsRescue || '救援') + '</span></button>'
                +   '<button class="mirc-qa terminate" onclick="instCardOp(' + idx + ',\'terminate\')">'
                +     '<i class="fas fa-trash-alt"></i><span>' + (i18n.opsTerminate || '终止') + '</span></button>'
                +   '<button class="mirc-qa more" onclick="instOpenOps(' + idx + ')">'
                +     '<i class="fas fa-ellipsis-h"></i><span>' + (i18n.opsMore || '更多') + '</span></button>'
                + '</div>'
                + '</div>';
        }).join('') + '</div>';

    document.getElementById('regionInstanceContent').innerHTML = html;
    document.getElementById('regionInstanceContent').scrollTop = 0;

    var pager = document.getElementById('regionInstancePager');
    if (totalPages <= 1) { pager.style.display = 'none'; return; }
    pager.style.display = '';
    document.getElementById('instPageInfo').textContent = _instPage + ' / ' + totalPages;
    document.getElementById('instPrevBtn').disabled = _instPage <= 1;
    document.getElementById('instNextBtn').disabled = _instPage >= totalPages;
}

function instChangePage(delta) {
    _instPage += delta;
    _renderInstPage();
}

function closeRegionInstanceModal(e) {
    if (e && e.target !== document.getElementById('regionInstanceModal')) return;
    document.getElementById('regionInstanceModal').style.display = 'none';
    document.body.style.overflow = '';
}

/* ═══════════════════════════════════════════════════
   实例操作菜单
   ═══════════════════════════════════════════════════ */

/* 卡片上快捷操作入口：先绑定实例，再调用对应操作 */
function instCardOp(idx, type) {
    _currentOpsInst = _instPageItems[idx];
    switch (type) {
        case 'start':    instOpsStart();          break;
        case 'stop':     instOpsStop();           break;
        case 'config':   instOpsOpenConfig();     break;
        case 'changeip': instOpsOpenChangeIp();   break;
        case 'rescue':   instOpsOpenRescue();     break;
        case 'terminate':instOpsOpenTerminate();  break;
    }
}

/* 「更多」底部菜单 — 仅展示次要操作 */
function instOpenOps(idx) {
    var inst = _instPageItems[idx];
    if (!inst) return;
    _currentOpsInst = inst;
    var i18n  = window.MOB_I18N || {};
    var state = (inst.state || '').toUpperCase();
    var isRunning = state === 'RUNNING';
    var isProv    = state === 'PROVISIONING' || state === 'STARTING' || state === 'STOPPING';
    var dotCls    = isRunning ? 'running' : (isProv ? 'starting' : 'stopped');

    // state dot
    document.getElementById('instOpsStateDot').className = 'inst-ops-state-dot ' + dotCls;

    // instance name
    document.getElementById('instOpsName').textContent = inst.displayName || inst.instanceId || '—';

    // subtitle: IP + shape abbreviation
    var parts = [];
    if (inst.publicIp) parts.push(inst.publicIp);
    else if (inst.privateIp) parts.push(inst.privateIp);
    if (inst.shape) parts.push(inst.shape.replace('VM.Standard.', '').replace('VM.Optimized3.', ''));
    document.getElementById('instOpsSubtitle').textContent = parts.join(' · ');

    // state badge — use i18n labels (same as card)
    var badge = document.getElementById('instOpsStateBadge');
    badge.textContent = isRunning ? (i18n.instStateRunning || '运行中')
                      : (isProv   ? (i18n.instStateStarting || '处理中')
                                  : (i18n.instStateStopped  || '已停止'));
    badge.className = 'inst-ops-state-badge ' + dotCls;

    var actions = [
        { icon: 'fa-edit',        cls: 'info',    label: i18n.opsRename  || '修改名称',  fn: 'instOpsOpenRename()' },
        { icon: 'fa-hdd',         cls: 'info',    label: i18n.opsDisk    || '修改磁盘',  fn: 'instOpsOpenDisk()' },
        { icon: 'fa-sticky-note', cls: 'teal',    label: i18n.opsRemark  || '修改备注',  fn: 'instOpsOpenRemark()' },
        { icon: 'fa-globe',       cls: 'warning', label: i18n.opsIpv6    || 'IPv6管理',  fn: 'instOpsOpenIpv6()' },
        { icon: 'fa-sitemap',     cls: 'purple',  label: i18n.opsNetwork || '网络管理',  fn: 'instOpsOpenNetwork()' },
        { icon: 'fa-undo',        cls: 'purple',  label: i18n.opsDd      || '一键DD',    fn: 'instOpsOpenDD()' },
    ];

    document.getElementById('instOpsActions').innerHTML = actions.map(function(a) {
        return '<button class="inst-ops-grid-btn ' + a.cls + '" onclick="' + a.fn + '">'
            + '<span class="inst-ops-grid-icon"><i class="fas ' + a.icon + '"></i></span>'
            + '<span class="inst-ops-grid-lbl">' + a.label + '</span>'
            + '</button>';
    }).join('');

    document.getElementById('instOpsOverlay').classList.add('show');
}

function instCloseOps() {
    document.getElementById('instOpsOverlay').classList.remove('show');
}

/* ── CSRF helper ── */
function _opsCsrf() {
    var m = document.querySelector('meta[name="_csrf"]');
    return m ? m.getAttribute('content') : '';
}
function _opsPost(url, body, cb) {
    var csrf = _opsCsrf();
    fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
        body: JSON.stringify(body)
    }).then(function(r) { return r.json(); })
      .then(cb)
      .catch(function(e) { cb({ success: false, message: e.message }); });
}

/* ── 启动 / 停止 ── */
function instOpsStart() {
    instCloseOps();
    var inst = _currentOpsInst;
    var i18n = window.MOB_I18N || {};
    mobToast(i18n.opsStarting || '正在启动...', 'info');
    _opsPost('/oci/startInstance', { instanceId: inst.id }, function(json) {
        if (json.success) {
            mobToast(i18n.opsStartOk || '启动请求已发送', 'success');
            setTimeout(function() { showRegionInstances(_instCurrentTenantId, _instCurrentRegion); }, 2500);
        } else {
            mobToast((json.message || i18n.opsFail || '操作失败'), 'error');
        }
    });
}

function instOpsStop() {
    instCloseOps();
    var inst = _currentOpsInst;
    var i18n = window.MOB_I18N || {};
    mobToast(i18n.opsStopping || '正在停止...', 'info');
    _opsPost('/oci/stopInstance', { instanceId: inst.id }, function(json) {
        if (json.success) {
            mobToast(i18n.opsStopOk || '停止请求已发送', 'success');
            setTimeout(function() { showRegionInstances(_instCurrentTenantId, _instCurrentRegion); }, 2500);
        } else {
            mobToast((json.message || i18n.opsFail || '操作失败'), 'error');
        }
    });
}

/* ── 通用输入弹框 ── */
function _opsShowInput(title, bodyHtml, okFn) {
    instCloseOps();
    document.getElementById('instOpsInputTitle').textContent = title;
    document.getElementById('instOpsInputBody').innerHTML = bodyHtml;
    var st = document.getElementById('instOpsInputStatus');
    st.style.display = 'none'; st.className = '';
    document.getElementById('instOpsInputOkBtn').disabled = false;
    _opsInputSubmitFn = okFn;
    document.getElementById('instOpsInputOverlay').classList.add('show');
}
function instCloseInput(e) {
    if (e && e.target !== document.getElementById('instOpsInputOverlay')) return;
    document.getElementById('instOpsInputOverlay').classList.remove('show');
    _opsInputSubmitFn = null;
}
function instOpsDoSubmit() {
    if (_opsInputSubmitFn) _opsInputSubmitFn();
}
function _opsInputSetStatus(msg, type) {
    var el = document.getElementById('instOpsInputStatus');
    el.textContent = msg;
    el.className = type === 'ok' ? 'inst-ops-status-ok' : (type === 'err' ? 'inst-ops-status-err' : 'inst-ops-status-ing');
    el.style.display = 'block';
}

/* ── 修改名称 ── */
function instOpsOpenRename() {
    var inst = _currentOpsInst;
    var i18n = window.MOB_I18N || {};
    _opsShowInput(i18n.opsRename || '修改名称',
        '<input id="opsRenameInput" class="inst-ops-field" type="text" value="' + escHtmlSafe(inst.displayName || '') + '" placeholder="' + (i18n.opsRenamePh || '请输入新名称') + '">',
        function() {
            var name = (document.getElementById('opsRenameInput').value || '').trim();
            if (!name) return;
            _opsInputSetStatus(i18n.opsStarting || '提交中...', 'ing');
            document.getElementById('instOpsInputOkBtn').disabled = true;
            _opsPost('/oci/updateName', { instanceId: inst.id, newName: name }, function(json) {
                if (json.success) {
                    _opsInputSetStatus(i18n.opsSuccess || '成功', 'ok');
                    setTimeout(function() { instCloseInput(); _opsRefresh(); }, 1500);
                } else {
                    _opsInputSetStatus(json.message || i18n.opsFail || '失败', 'err');
                    document.getElementById('instOpsInputOkBtn').disabled = false;
                }
            });
        }
    );
}

/* ── 修改配置 CPU/MEM ── */
function instOpsOpenConfig() {
    var inst = _currentOpsInst;
    var i18n = window.MOB_I18N || {};
    _opsShowInput(i18n.opsConfig || '修改配置',
        '<div style="margin-bottom:10px"><label style="font-size:12px;color:var(--mob-text-muted)">CPU (1-24)</label>'
        + '<input id="opsCpuInput" class="inst-ops-field" type="number" min="1" max="24" step="1" value="' + (inst.ocpus || 1) + '" style="margin-top:4px"></div>'
        + '<div><label style="font-size:12px;color:var(--mob-text-muted)">MEM GB (1-256)</label>'
        + '<input id="opsMemInput" class="inst-ops-field" type="number" min="1" max="256" step="1" value="' + (inst.memoryInGBs || 6) + '" style="margin-top:4px"></div>',
        function() {
            var cpu = parseInt(document.getElementById('opsCpuInput').value);
            var mem = parseInt(document.getElementById('opsMemInput').value);
            if (!cpu || !mem) return;
            _opsInputSetStatus(i18n.opsStarting || '提交中...', 'ing');
            document.getElementById('instOpsInputOkBtn').disabled = true;
            _opsPost('/oci/updateConfig', { instanceId: inst.id, cpu: cpu, memory: mem }, function(json) {
                if (json.success) {
                    _opsInputSetStatus(i18n.opsSuccess || '成功', 'ok');
                    setTimeout(function() { instCloseInput(); _opsRefresh(); }, 1500);
                } else {
                    _opsInputSetStatus(json.message || i18n.opsFail || '失败', 'err');
                    document.getElementById('instOpsInputOkBtn').disabled = false;
                }
            });
        }
    );
}

/* ── 修改磁盘 ── */
function instOpsOpenDisk() {
    var inst = _currentOpsInst;
    var i18n = window.MOB_I18N || {};
    var cur  = inst.bootVolumeSizeInGBs || 50;
    _opsShowInput(i18n.opsDisk || '修改磁盘',
        '<div><label style="font-size:12px;color:var(--mob-text-muted)">当前: ' + cur + ' GB &nbsp;|&nbsp; 最小: 47 GB</label>'
        + '<input id="opsDiskInput" class="inst-ops-field" type="number" min="47" step="1" value="' + cur + '" style="margin-top:4px"></div>',
        function() {
            var newSize = parseInt(document.getElementById('opsDiskInput').value);
            if (!newSize || newSize < 47) return;
            var expand  = newSize >= cur;
            _opsInputSetStatus(i18n.opsStarting || '提交中...', 'ing');
            document.getElementById('instOpsInputOkBtn').disabled = true;
            _opsPost('/oci/updateBootVolume', { instanceId: inst.id, bootVolumeSize: newSize, expand: expand }, function(json) {
                if (json.success) {
                    _opsInputSetStatus(json.message || i18n.opsSuccess || '成功', 'ok');
                    setTimeout(function() { instCloseInput(); _opsRefresh(); }, 1500);
                } else {
                    _opsInputSetStatus(json.message || i18n.opsFail || '失败', 'err');
                    document.getElementById('instOpsInputOkBtn').disabled = false;
                }
            });
        }
    );
}

/* ── 修改备注 ── */
function instOpsOpenRemark() {
    var inst = _currentOpsInst;
    var i18n = window.MOB_I18N || {};
    _opsShowInput(i18n.opsRemark || '修改备注',
        '<textarea id="opsRemarkInput" class="inst-ops-field" rows="3" placeholder="' + (i18n.opsRemarkPh || '请输入备注') + '" style="resize:none">' + escHtmlSafe(inst.remark || '') + '</textarea>',
        function() {
            var remark = document.getElementById('opsRemarkInput').value || '';
            _opsInputSetStatus(i18n.opsStarting || '提交中...', 'ing');
            document.getElementById('instOpsInputOkBtn').disabled = true;
            _opsPost('/oci/updateRemark', { instanceId: inst.id, remark: remark }, function(json) {
                if (json.success) {
                    _opsInputSetStatus(i18n.opsSuccess || '成功', 'ok');
                    setTimeout(function() { instCloseInput(); _opsRefresh(); }, 1500);
                } else {
                    _opsInputSetStatus(json.message || i18n.opsFail || '失败', 'err');
                    document.getElementById('instOpsInputOkBtn').disabled = false;
                }
            });
        }
    );
}

/* ── 更换IP ── */
function instOpsOpenChangeIp() {
    var inst = _currentOpsInst;
    var i18n = window.MOB_I18N || {};
    _opsShowInput(i18n.opsChangeIp || '更换IP',
        '<div id="opsCidrList">'
        + '<input class="inst-ops-field ops-cidr-input" type="text" placeholder="CIDR (可选, 如 10.0.0.0/24)" style="margin-bottom:6px">'
        + '</div>'
        + '<button type="button" onclick="instOpsAddCidr()" style="font-size:12px;color:var(--mob-accent);background:none;border:none;padding:0;cursor:pointer;margin-bottom:4px">'
        + '<i class="fas fa-plus"></i> ' + (i18n.opsCidrAdd || '添加CIDR') + '</button>',
        function() {
            var cidrInputs = document.querySelectorAll('.ops-cidr-input');
            var cidrRanges = Array.from(cidrInputs).map(function(el) { return el.value.trim(); }).filter(Boolean);
            _opsInputSetStatus(i18n.opsStarting || '提交中...', 'ing');
            document.getElementById('instOpsInputOkBtn').disabled = true;
            _opsPost('/oci/changeSpecIp', { tenantId: inst.id, cidrRanges: cidrRanges }, function(json) {
                if (json.status === 'success' || json.success) {
                    var msg = i18n.opsSuccess || '成功';
                    if (json.details) msg += ' → ' + json.details.newIp;
                    _opsInputSetStatus(msg, 'ok');
                    setTimeout(function() { instCloseInput(); _opsRefresh(); }, 2000);
                } else {
                    _opsInputSetStatus(json.message || i18n.opsFail || '失败', 'err');
                    document.getElementById('instOpsInputOkBtn').disabled = false;
                }
            });
        }
    );
}
function instOpsAddCidr() {
    var list = document.getElementById('opsCidrList');
    if (!list) return;
    var wrapper = document.createElement('div');
    wrapper.style.display = 'flex'; wrapper.style.gap = '6px'; wrapper.style.marginBottom = '6px';
    wrapper.innerHTML = '<input class="inst-ops-field ops-cidr-input" type="text" placeholder="CIDR" style="flex:1">'
        + '<button type="button" onclick="this.parentElement.remove()" style="background:none;border:none;color:#f04747;font-size:15px;cursor:pointer;flex-shrink:0"><i class="fas fa-times"></i></button>';
    list.appendChild(wrapper);
}

/* ── IPv6 ── */
function instOpsOpenIpv6() {
    var inst = _currentOpsInst;
    var i18n = window.MOB_I18N || {};
    var hasIpv6 = inst.ipv6Addresses && inst.ipv6Addresses.trim();
    _opsShowInput(i18n.opsIpv6 || 'IPv6管理',
        '<p style="font-size:13px;color:var(--mob-text-muted);margin-bottom:8px">'
        + (i18n.opsIpv6Confirm || '确认为此实例开启/刷新 IPv6？') + '</p>'
        + (hasIpv6 ? '<div style="font-size:12px;padding:8px;background:var(--mob-bg);border-radius:8px;word-break:break-all;font-family:monospace">' + escHtmlSafe(inst.ipv6Addresses) + '</div>' : ''),
        function() {
            _opsInputSetStatus(i18n.opsStarting || '提交中...', 'ing');
            document.getElementById('instOpsInputOkBtn').disabled = true;
            _opsPost('/oci/enableIpv6', { tenantId: inst.id }, function(json) {
                if (json.status === 'success' || json.success) {
                    var msg = i18n.opsSuccess || '成功';
                    if (json.details && json.details.ipv6Address) msg += ': ' + json.details.ipv6Address;
                    _opsInputSetStatus(msg, 'ok');
                    setTimeout(function() { instCloseInput(); _opsRefresh(); }, 2000);
                } else {
                    _opsInputSetStatus(json.message || i18n.opsFail || '失败', 'err');
                    document.getElementById('instOpsInputOkBtn').disabled = false;
                }
            });
        }
    );
}

/* ── 网络管理（移动端专属页面）── */
function instOpsOpenNetwork() {
    var inst = _currentOpsInst;
    if (!inst || !inst.instanceId) { mobToast('实例 OCI ID 无效', 'error'); return; }
    instCloseOps();
    window.location.href = '/m/vnic/manage?instanceId=' + encodeURIComponent(inst.instanceId);
}

/* ── 系统救援（移动端专属页面）── */
function instOpsOpenRescue() {
    var inst = _currentOpsInst;
    if (!inst || !inst.id) { mobToast('实例 ID 无效', 'error'); return; }
    instCloseOps();
    window.location.href = '/m/sysHelp?instanceId=' + encodeURIComponent(inst.id);
}

/* ── 终止实例（两步）── */
function instOpsOpenTerminate() {
    instCloseOps();
    document.getElementById('instTermStep1').style.display = 'block';
    document.getElementById('instTermStep2').style.display = 'none';
    var st = document.getElementById('instTermStatus');
    st.style.display = 'none'; st.className = '';
    document.getElementById('instOpsTermOverlay').classList.add('show');
}
function instCloseTerminate(e) {
    if (e && e.target !== document.getElementById('instOpsTermOverlay')) return;
    document.getElementById('instOpsTermOverlay').classList.remove('show');
}
function instTermSendCode() {
    var inst = _currentOpsInst;
    var i18n = window.MOB_I18N || {};
    var st   = document.getElementById('instTermStatus');
    st.textContent = i18n.opsStarting || '发送中...';
    st.className = 'inst-ops-status-ing'; st.style.display = 'block';
    _opsPost('/oci/sendVerificationCode', { instanceId: inst.id }, function(json) {
        if (json.success) {
            document.getElementById('instTermStep1').style.display = 'none';
            document.getElementById('instTermStep2').style.display = 'block';
            st.style.display = 'none';
        } else {
            st.textContent = json.message || i18n.opsFail || '发送失败';
            st.className = 'inst-ops-status-err';
        }
    });
}
function instTermConfirm() {
    var inst = _currentOpsInst;
    var i18n = window.MOB_I18N || {};
    var code = (document.getElementById('instTermCodeInput').value || '').trim();
    if (!code) return;
    var st = document.getElementById('instTermStatus');
    st.textContent = i18n.opsStarting || '提交中...';
    st.className = 'inst-ops-status-ing'; st.style.display = 'block';
    _opsPost('/oci/terminateInstance', { instanceId: inst.id, verificationCode: code }, function(json) {
        if (json.success) {
            st.textContent = i18n.opsSuccess || '终止请求已发送';
            st.className = 'inst-ops-status-ok';
            setTimeout(function() {
                instCloseTerminate();
                _opsRefresh();
            }, 1800);
        } else {
            st.textContent = json.message || i18n.opsFail || '终止失败';
            st.className = 'inst-ops-status-err';
        }
    });
}

/* ── 一键DD ── */
function instOpsOpenDD() {
    instCloseOps();
    document.getElementById('instDDStep1').style.display = 'block';
    document.getElementById('instDDStep2').style.display = 'none';
    // reset two-level OS picker
    document.getElementById('instDDOsValue').value = '';
    document.getElementById('ddVersionArea').style.display = 'none';
    document.getElementById('ddSelectedShow').style.display = 'none';
    document.querySelectorAll('.dd-family-btn').forEach(function(b) { b.classList.remove('active'); });
    document.querySelectorAll('.dd-ver-btn').forEach(function(b) { b.classList.remove('active'); });
    _ddSelectedFamily = '';
    document.getElementById('instDDPassword').value = '';
    document.getElementById('instDDPwdIcon').className = 'fas fa-eye';
    document.getElementById('instDDPassword').type = 'password';
    document.getElementById('instOpsDDOverlay').classList.add('show');
}
function instCloseDd(e) {
    if (e && e.target !== document.getElementById('instOpsDDOverlay')) return;
    if (_instDDEs) { _instDDEs.close(); _instDDEs = null; }
    document.getElementById('instOpsDDOverlay').classList.remove('show');
}
function instDDTogglePwd() {
    var inp = document.getElementById('instDDPassword');
    var ico = document.getElementById('instDDPwdIcon');
    if (inp.type === 'password') {
        inp.type = 'text'; ico.className = 'fas fa-eye-slash';
    } else {
        inp.type = 'password'; ico.className = 'fas fa-eye';
    }
}
function instDDStart() {
    var inst = _currentOpsInst;
    var i18n = window.MOB_I18N || {};
    var osVal = document.getElementById('instDDOsValue').value;
    var pwd   = document.getElementById('instDDPassword').value;
    if (!osVal) { mobToast(i18n.opsRenamePh || '请选择操作系统', 'error'); return; }
    var parts = osVal.split('|');
    var osName = parts[0]; var osVersion = parts[1] || '';
    var params = new URLSearchParams({
        instanceId: inst.id,
        osName:     osName,
        osVersion:  osVersion,
        password:   pwd
    });
    document.getElementById('instDDStep1').style.display = 'none';
    document.getElementById('instDDStep2').style.display = 'block';
    var log = document.getElementById('instDDLog');
    log.innerHTML = '';
    var closeBtn = document.getElementById('instDDCloseBtn');
    closeBtn.disabled = true;

    if (_instDDEs) { _instDDEs.close(); }
    _instDDEs = new EventSource('/oci/instance/quickDD?' + params.toString());
    _instDDEs.onmessage = function(e) {
        log.innerHTML += escHtmlSafe(e.data) + '<br>';
        log.scrollTop = log.scrollHeight;
    };
    _instDDEs.addEventListener('error', function(e) {
        if (e.data) { log.innerHTML += '<span style="color:#f04747">' + escHtmlSafe(e.data) + '</span><br>'; }
        _instDDEs.close(); _instDDEs = null;
        closeBtn.disabled = false;
    });
    _instDDEs.onerror = function() {
        if (_instDDEs && _instDDEs.readyState === EventSource.CLOSED) {
            closeBtn.disabled = false;
        }
    };
}

/* ── 刷新当前区域实例列表 ── */
var _instCurrentTenantId = '';
var _instCurrentRegion   = '';
function _opsRefresh() {
    if (_instCurrentTenantId) showRegionInstances(_instCurrentTenantId, _instCurrentRegion);
}

/* ── 通用 HTML 转义 ──────────────────────────────── */
function escHtmlSafe(s) {
    if (!s) return '';
    return String(s)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

/* ── 版本更新检查 ────────────────────────────────── */
function mobShowVersionSheet() { mobOpenSheet('versionSheet'); }

async function mobCheckVersion() {
    try {
        var res = await fetch('/api/version/check', { signal: AbortSignal.timeout(5000) });
        if (!res.ok) return;
        var data = await res.json();
        var btn = document.getElementById('mobUpdateBtn');
        var cur = document.getElementById('versionCurrent');
        var lat = document.getElementById('versionLatest');
        var dep = document.getElementById('versionDeploy');
        if (cur) cur.textContent = data.currentVersion || '-';
        if (lat) lat.textContent = data.latestVersion || '-';
        if (dep) dep.textContent = data.deployType || '-';
        if (btn && data.needUpdate) btn.style.display = 'flex';
    } catch (e) { /* 静默失败 */ }
}

async function mobDoUpdate() {
    var csrf = document.querySelector('meta[name="_csrf"]').content;
    var csrfHeader = document.querySelector('meta[name="_csrf_header"]').content;
    var doUpdateBtn = document.getElementById('mobDoUpdateBtn');
    if (doUpdateBtn) { doUpdateBtn.disabled = true; doUpdateBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> 更新中...'; }
    try {
        var res = await fetch('/api/version/execute-update', {
            method: 'POST',
            headers: { [csrfHeader]: csrf }
        });
        var json = await res.json();
        mobCloseSheet();
        if (json.success || json.code === 200) {
            mobToast('更新成功，应用即将重启', 'success');
        } else {
            mobToast(json.message || '更新失败', 'error');
        }
    } catch (e) {
        mobToast('请求失败', 'error');
    } finally {
        if (doUpdateBtn) { doUpdateBtn.disabled = false; doUpdateBtn.innerHTML = '<i class="fas fa-download"></i> 立即更新'; }
    }
}

/* ── 退出登录（使用专属确认弹框）──────────────── */
function mobShowLogout() {
    mobCloseDrawer();
    document.getElementById('mobLogoutOverlay').classList.add('show');
}
function mobLogoutCancel() {
    document.getElementById('mobLogoutOverlay').classList.remove('show');
}
function mobLogoutOk() {
    document.getElementById('mobLogoutOverlay').classList.remove('show');
    mobDoLogout();
}

async function mobDoLogout() {
    var csrf = document.querySelector('meta[name="_csrf"]').content;
    var csrfHeader = document.querySelector('meta[name="_csrf_header"]').content;
    try {
        await fetch('/perform_logout', { method: 'POST', headers: { [csrfHeader]: csrf } });
    } catch (e) { /* ignore */ }
    window.location.href = '/login?logout';
}

/* ── 系统日志 WebSocket ──────────────────────────── */
var _syslogWs = null;

function mobOpenSysLog() {
    mobCloseDrawer();
    document.getElementById('syslogContent').innerHTML = '';
    mobOpenSheet('syslogSheet');
    _syslogConnect();
}

function _syslogConnect() {
    _syslogDisconnect();
    _syslogSetStatus(false, '连接中...');
    var protocol = window.location.protocol === 'https:' ? 'wss://' : 'ws://';
    try {
        var ws = new WebSocket(protocol + window.location.host + '/log/ws');
        _syslogWs = ws;
        ws.onopen = function() { _syslogSetStatus(true, '已连接'); };
        ws.onmessage = function(ev) { _syslogAppend(ev.data); };
        ws.onerror = function() { _syslogSetStatus(false, '连接异常'); };
        ws.onclose = function() {
            _syslogWs = null;
            _syslogSetStatus(false, '已断开');
        };
    } catch (e) {
        _syslogSetStatus(false, '不支持');
    }
}

function _syslogDisconnect() {
    if (_syslogWs) {
        try { _syslogWs.close(); } catch (e) {}
        _syslogWs = null;
    }
}

function _syslogSetStatus(connected, text) {
    var dot = document.getElementById('syslogDot');
    var txt = document.getElementById('syslogStatusTxt');
    if (dot) dot.className = 'mob-syslog-dot' + (connected ? ' connected' : '');
    if (txt) txt.textContent = text || (connected ? '已连接' : '未连接');
}

function _syslogAppend(line) {
    var content = document.getElementById('syslogContent');
    var wrap    = document.getElementById('syslogWrap');
    if (!content) return;

    var div = document.createElement('div');
    div.className = 'mob-syslog-line';
    var lower = line.toLowerCase();
    if (lower.includes(' error') || lower.includes('[error]')) {
        div.classList.add('error');
    } else if (lower.includes(' warn') || lower.includes('[warn]')) {
        div.classList.add('warn');
    } else if (lower.includes(' info') || lower.includes('[info]')) {
        div.classList.add('info');
    }
    div.textContent = line;
    content.appendChild(div);

    // 限制最多 500 行
    while (content.children.length > 500) {
        content.removeChild(content.firstChild);
    }
    // 自动滚到底部
    if (wrap) wrap.scrollTop = wrap.scrollHeight;
}

/* ── 主题切换（暗/亮/跟随系统）──────────────────── */
var _mobMQ = window.matchMedia('(prefers-color-scheme: dark)');

function _mobApplyTheme(mode) {
    var effective = mode === 'auto' ? (_mobMQ.matches ? 'dark' : 'light') : mode;
    document.documentElement.setAttribute('data-theme', effective);
}

function _mobUpdateThemeIcon(mode) {
    var el = document.getElementById('mobThemeIcon');
    if (!el) return;
    if (mode === 'dark')       { el.className = 'fas fa-moon'; }
    else if (mode === 'light') { el.className = 'fas fa-sun'; }
    else                       { el.className = 'fas fa-adjust'; }
}

function _mobThemeAutoHandler() { _mobApplyTheme('auto'); }

function mobThemeInit() {
    var saved = localStorage.getItem('mob-theme') || 'auto';
    _mobApplyTheme(saved);
    _mobUpdateThemeIcon(saved);
    if (saved === 'auto') _mobMQ.addEventListener('change', _mobThemeAutoHandler);
}

function mobCycleTheme() {
    var cur  = localStorage.getItem('mob-theme') || 'auto';
    var next = cur === 'auto' ? 'dark' : (cur === 'dark' ? 'light' : 'auto');
    localStorage.setItem('mob-theme', next);
    _mobMQ.removeEventListener('change', _mobThemeAutoHandler);
    _mobApplyTheme(next);
    _mobUpdateThemeIcon(next);
    if (next === 'auto') _mobMQ.addEventListener('change', _mobThemeAutoHandler);
    var labels = { dark: '已切换：暗色', light: '已切换：亮色', auto: '已切换：跟随系统' };
    mobToast(labels[next], 'success');
}

mobThemeInit();

/* ════════════════════════════════════════════════════════════
   Header 折叠按钮组
   ════════════════════════════════════════════════════════════ */
function mobToggleHeaderActions() {
    var expandable = document.getElementById('mobHeaderExpandable');
    var avatar     = document.getElementById('mobAvatarBtn');
    if (!expandable) return;
    var isOpen = expandable.classList.contains('open');
    if (isOpen) {
        expandable.classList.remove('open');
        avatar && avatar.classList.remove('expanded');
    } else {
        expandable.classList.add('open');
        avatar && avatar.classList.add('expanded');
    }
}

/* 点击 header 外部区域时自动收起 */
document.addEventListener('click', function(e) {
    var expandable = document.getElementById('mobHeaderExpandable');
    var avatar     = document.getElementById('mobAvatarBtn');
    if (!expandable || !expandable.classList.contains('open')) return;
    if (!expandable.contains(e.target) && e.target !== avatar && !avatar.contains(e.target)) {
        expandable.classList.remove('open');
        avatar && avatar.classList.remove('expanded');
    }
});

/* ════════════════════════════════════════════════════════════
   通用工具
   ════════════════════════════════════════════════════════════ */
function getCsrf() {
    var meta = document.querySelector('meta[name="_csrf"]');
    var headerMeta = document.querySelector('meta[name="_csrf_header"]');
    return {
        token: meta ? meta.getAttribute('content') : '',
        header: headerMeta ? headerMeta.getAttribute('content') : 'X-CSRF-TOKEN'
    };
}

function escHtml(s) {
    if (!s) return '';
    return String(s)
        .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function _postJson(url, body) {
    var c = getCsrf();
    var headers = { 'Content-Type': 'application/json' };
    headers[c.header] = c.token;
    return fetch(url, { method: 'POST', headers: headers, body: body ? JSON.stringify(body) : undefined })
        .then(function(r) { return r.json(); });
}

/* ════════════════════════════════════════════════════════════
   消息中心
   ════════════════════════════════════════════════════════════ */
var _msgPage = 1, _msgTotalPages = 1;

function mobOpenMessages() {
    mobOpenModal('msgCenterSheet');
    _mobMsgShowList();
    mobLoadMessages(1);
}

function _mobMsgShowList() {
    document.getElementById('msgListView').style.display   = '';
    document.getElementById('msgDetailView').style.display = 'none';
    document.getElementById('msgBackBtn').style.display    = 'none';
    document.getElementById('msgMarkBtn').style.display    = '';
    document.getElementById('msgPagination').style.display = '';
}

function _mobMsgShowDetail() {
    document.getElementById('msgListView').style.display   = 'none';
    document.getElementById('msgDetailView').style.display = 'flex';
    document.getElementById('msgBackBtn').style.display    = '';
    document.getElementById('msgMarkBtn').style.display    = 'none';
    document.getElementById('msgPagination').style.display = 'none';
}

function mobLoadMessages(page) {
    var i18n = window.MOB_I18N || {};
    _msgPage = page || 1;
    document.getElementById('msgListWrap').innerHTML =
        '<div class="mob-loading"><div class="mob-spinner"></div><p>' + (i18n.msgLoading || '加载中...') + '</p></div>';
    _postJson('/sysMessage/list', { pageNum: _msgPage, pageSize: 4 })
        .then(function(res) { mobRenderMessages(res.data || {}); })
        .catch(function() {
            document.getElementById('msgListWrap').innerHTML =
                '<div style="text-align:center;color:var(--mob-text-muted);padding:20px">' + (i18n.msgLoadFail || '加载失败') + '</div>';
        });
}

function mobRenderMessages(pageData) {
    var items = pageData.content || [];
    _msgTotalPages = pageData.totalPages || 1;
    _msgPage = (pageData.number || 0) + 1;
    document.getElementById('msgPageInfo').textContent = _msgPage + ' / ' + _msgTotalPages;
    document.getElementById('msgPrevBtn').disabled = _msgPage <= 1;
    document.getElementById('msgNextBtn').disabled = _msgPage >= _msgTotalPages;

    var i18n = window.MOB_I18N || {};
    if (!items.length) {
        document.getElementById('msgListWrap').innerHTML =
            '<div style="text-align:center;color:var(--mob-text-muted);padding:32px 0">'
            + '<i class="fas fa-inbox" style="font-size:36px;opacity:0.3;display:block;margin-bottom:10px"></i>'
            + (i18n.msgEmpty || '暂无消息') + '</div>';
        return;
    }
    document.getElementById('msgListWrap').innerHTML = items.map(function(m) {
        var unread  = m.readStatus === 0;
        var preview = (m.content || '').replace(/<[^>]*>/g, '').substring(0, 60);
        var time    = (m.createTime || '').substring(0, 16).replace('T', ' ');
        return '<div class="mob-msg-item" onclick="mobViewMsg(\'' + escHtml(m.businessId) + '\')">'
            + '<div class="mob-msg-dot' + (unread ? '' : ' mob-msg-dot-read') + '"></div>'
            + '<div class="mob-msg-body">'
            + '<div class="mob-msg-subject' + (unread ? '' : ' mob-msg-subject-read') + '">' + escHtml(m.subject || '(无标题)') + '</div>'
            + '<div class="mob-msg-time">' + escHtml(time) + '</div>'
            + '<div class="mob-msg-preview">' + escHtml(preview) + '</div>'
            + '</div>'
            + '<button class="mob-msg-del-btn" onclick="event.stopPropagation();mobDeleteMsg(\'' + escHtml(m.businessId) + '\')">'
            + '<i class="fas fa-trash-alt"></i></button>'
            + '</div>';
    }).join('');
}

function mobMsgPage(dir) {
    var next = _msgPage + dir;
    if (next < 1 || next > _msgTotalPages) return;
    mobLoadMessages(next);
}

function mobMarkAllRead() {
    var i18n = window.MOB_I18N || {};
    _postJson('/sysMessage/read')
        .then(function() {
            mobToast(i18n.msgMarkOk || '已全部标为已读', 'success');
            mobLoadMessages(_msgPage);
            var dot = document.getElementById('mobBellDot');
            if (dot) dot.style.display = 'none';
        }).catch(function() { mobToast(i18n.msgOpFail || '操作失败', 'error'); });
}

function mobDeleteMsg(businessId) {
    var i18n = window.MOB_I18N || {};
    _postJson('/sysMessage/del', { businessId: businessId })
        .then(function(res) {
            if (res.success) {
                mobToast(i18n.msgDeleteOk || '已删除', 'success');
                mobLoadMessages(_msgPage);
            } else {
                mobToast(res.message || i18n.msgDeleteFail || '删除失败', 'error');
            }
        }).catch(function() { mobToast(i18n.msgDeleteFail || '删除失败', 'error'); });
}

function mobViewMsg(businessId) {
    var i18n = window.MOB_I18N || {};
    document.getElementById('msgDetailContent').innerHTML =
        '<div class="mob-loading"><div class="mob-spinner"></div><p>' + (i18n.msgLoading || '加载中...') + '</p></div>';
    _mobMsgShowDetail();
    _postJson('/sysMessage/get', { businessId: businessId })
        .then(function(res) {
            var m    = res.data || {};
            var time = (m.createTime || '').substring(0, 16).replace('T', ' ');
            document.getElementById('msgDetailContent').innerHTML =
                '<div class="mob-msg-detail-subject">' + escHtml(m.subject || '(无标题)') + '</div>'
                + '<div class="mob-msg-detail-meta">' + escHtml(time) + '</div>'
                + '<div class="mob-msg-detail-content">' + (m.content || '（无内容）') + '</div>';
            mobCheckUnread();
        }).catch(function() { mobToast(i18n.msgLoadFail || '加载失败', 'error'); });
}

function mobBackToMessages() {
    _mobMsgShowList();
    mobLoadMessages(_msgPage);
}

/* 未读数轮询 */
function mobCheckUnread() {
    _postJson('/sysMessage/countUnread')
        .then(function(res) {
            var count = (typeof res.data === 'number') ? res.data : 0;
            var dot = document.getElementById('mobBellDot');
            if (dot) dot.style.display = count > 0 ? '' : 'none';
            var badge = document.getElementById('drawerBellBadge');
            if (badge) { badge.textContent = count > 99 ? '99+' : count; badge.style.display = count > 0 ? '' : 'none'; }
        }).catch(function() {});
}
document.addEventListener('DOMContentLoaded', function() {
    mobCheckUnread();
    setInterval(mobCheckUnread, 60000);
});

/* ════════════════════════════════════════════════════════════
   语言切换
   ════════════════════════════════════════════════════════════ */
function mobOpenLang() { mobOpenModal('langSheet'); }

function mobSwitchLang(locale) {
    var url = new URL(window.location.href);
    url.searchParams.set('lang', locale);
    window.location.href = url.toString();
}
mobCheckVersion();

/* ── 图片灯箱 ── */
function mobOpenLightbox(src) {
    var lb  = document.getElementById('mobImgLightbox');
    var img = document.getElementById('mobImgLightboxImg');
    if (!lb || !img) return;
    img.src = src;
    lb.classList.add('show');
    document.body.style.overflow = 'hidden';
}
function mobCloseLightbox() {
    var lb = document.getElementById('mobImgLightbox');
    if (lb) lb.classList.remove('show');
    document.body.style.overflow = '';
}
