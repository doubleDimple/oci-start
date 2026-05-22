<#import "layout.ftl" as layout>
<@layout.page title="${msg.get('mob.arm.search.placeholder')}" activePage="arm-regions">

<!-- 搜索框 -->
<div class="mob-search-wrap">
    <i class="fas fa-search mob-search-icon"></i>
    <input class="mob-search-input" id="armSearch" type="text" placeholder="${msg.get('mob.arm.search.placeholder')}" oninput="armFilter()">
</div>

<!-- 统计摘要 -->
<div class="mob-arm-stats" id="armStats" style="display:none">
    <div class="mob-arm-stat-card">
        <div class="mob-arm-stat-num" id="armStatTotal">-</div>
        <div class="mob-arm-stat-lbl">${msg.get('mob.arm.stat.all')}</div>
    </div>
    <div class="mob-arm-stat-card mob-arm-stat-open">
        <div class="mob-arm-stat-num" id="armStatOpen" style="color:#43b581">-</div>
        <div class="mob-arm-stat-lbl">${msg.get('mob.arm.stat.open')}</div>
    </div>
    <div class="mob-arm-stat-card">
        <div class="mob-arm-stat-num" id="armStatToday" style="color:#1abc9c">-</div>
        <div class="mob-arm-stat-lbl">${msg.get('mob.arm.stat.today')}</div>
    </div>
    <div class="mob-arm-stat-card">
        <div class="mob-arm-stat-num" id="armStatMine" style="color:#7289da">-</div>
        <div class="mob-arm-stat-lbl">${msg.get('mob.arm.stat.mine')}</div>
    </div>
</div>

<!-- 视图切换 -->
<div class="mob-chips" id="armViewChips" style="margin-bottom:10px;display:none">
    <button class="mob-chip active" id="armChipAll"  onclick="armSetView('all')">${msg.get('mob.arm.view.all')}</button>
    <button class="mob-chip" id="armChipOpen" onclick="armSetView('open')">${msg.get('mob.arm.view.open')}</button>
    <button class="mob-chip" id="armChipMine" onclick="armSetView('mine')">${msg.get('mob.arm.view.mine')}</button>
</div>

<!-- 洲际过滤 -->
<div class="mob-chips" id="armContChips" style="margin-bottom:12px;display:none;flex-wrap:wrap">
    <button class="mob-chip active" id="armCont_all" onclick="armSetContinent('all')">${msg.get('mob.arm.cont.all')}</button>
    <button class="mob-chip" id="armCont_asia" onclick="armSetContinent('asia')">${msg.get('mob.arm.cont.asia')}</button>
    <button class="mob-chip" id="armCont_europe" onclick="armSetContinent('europe')">${msg.get('mob.arm.cont.europe')}</button>
    <button class="mob-chip" id="armCont_america-north" onclick="armSetContinent('america-north')">${msg.get('mob.arm.cont.north-america')}</button>
    <button class="mob-chip" id="armCont_america-south" onclick="armSetContinent('america-south')">${msg.get('mob.arm.cont.south-america')}</button>
    <button class="mob-chip" id="armCont_middle-east" onclick="armSetContinent('middle-east')">${msg.get('mob.arm.cont.middle-east')}</button>
</div>

<!-- 加载中 -->
<div id="armLoading" class="mob-loading">
    <div class="mob-spinner"></div>
    <p>${msg.get('mob.loading')}</p>
</div>

<!-- 区域列表 -->
<div id="armList"></div>

<script>
var _armI18n = {
    loadFail:     "${msg.get('mob.arm.load.fail')}",
    empty:        "${msg.get('mob.arm.empty')}",
    badgeOpen:    "${msg.get('mob.arm.badge.open')}",
    badgeNo:      "${msg.get('mob.arm.badge.no')}",
    badgeMine:    "${msg.get('mob.arm.badge.mine')}",
    metricTotal:  "${msg.get('mob.arm.metric.total')}",
    metricMonthly:"${msg.get('mob.arm.metric.monthly')}",
    metricLast:   "${msg.get('mob.arm.metric.last')}",
    contAsia:     "${msg.get('mob.arm.cont.asia')}",
    contEurope:   "${msg.get('mob.arm.cont.europe')}",
    contNorth:    "${msg.get('mob.arm.cont.north-america')}",
    contSouth:    "${msg.get('mob.arm.cont.south-america')}",
    contMiddle:   "${msg.get('mob.arm.cont.middle-east')}"
};
</script>
<#noparse>
<script>
/* ── 数据状态 ─────────────────────────────── */
var _armAll      = [];   // armRecords
var _armMine     = [];   // my regions (region codes)
var _armMap      = {};   // regionCode → name
var _armView     = 'all';
var _armContinent = 'all';

/* ── 洲际映射 ─────────────────────────────── */
var CONT_MAP = {
    'ap-': 'asia', 'eu-': 'europe', 'uk-': 'europe', 'il-': 'europe',
    'me-': 'middle-east', 'af-': 'middle-east',
    'us-': 'america-north', 'ca-': 'america-north', 'mx-': 'america-north',
    'sa-': 'america-south'
};

function getContinent(code) {
    for (var pfx in CONT_MAP) {
        if (code.startsWith(pfx)) return CONT_MAP[pfx];
    }
    return 'other';
}

function getContLabel(cont) {
    var map = {
        'asia': _armI18n.contAsia,
        'europe': _armI18n.contEurope,
        'america-north': _armI18n.contNorth,
        'america-south': _armI18n.contSouth,
        'middle-east': _armI18n.contMiddle
    };
    return map[cont] || cont;
}

function isOpenToday(r) {
    if (!r.openTime) return false;
    var d = new Date(r.openTime);
    var now = new Date();
    return d.getFullYear() === now.getFullYear()
        && d.getMonth() === now.getMonth()
        && d.getDate() === now.getDate();
}

/* ── 加载数据 ─────────────────────────────── */
async function armLoad() {
    try {
        var [r1, r2] = await Promise.all([
            fetch('/resource/arm-data'),
            fetch('/resource/my-regions')
        ]);
        var j1 = await r1.json();
        var j2 = await r2.json();

        var d1 = (j1.data || {});
        _armAll  = d1.armRecords || [];
        _armMap  = d1.regionMap  || {};
        var mineData = (j2.data || {}).hasRecords || [];
        _armMine = mineData.map(function(r) { return r.regionKey || r.region || r; });

        document.getElementById('armLoading').style.display = 'none';
        document.getElementById('armStats').style.display = 'flex';
        document.getElementById('armViewChips').style.display = 'flex';
        document.getElementById('armContChips').style.display = 'flex';

        armUpdateStats();
        armFilter();
    } catch (e) {
        document.getElementById('armLoading').innerHTML =
            '<p style="color:#f04747;text-align:center">' + _armI18n.loadFail + ' ' + e.message + '</p>';
    }
}

/* ── 统计摘要 ─────────────────────────────── */
function armUpdateStats() {
    var full  = buildFullList();
    var open  = _armAll.filter(function(r) { return r.openCount > 0; });
    var today = _armAll.filter(isOpenToday);
    document.getElementById('armStatTotal').textContent = full.length;
    document.getElementById('armStatOpen').textContent  = open.length;
    document.getElementById('armStatToday').textContent = today.length;
    document.getElementById('armStatMine').textContent  = _armMine.length;
}

/* ── 视图 & 洲际切换 ─────────────────────── */
function armSetView(v) {
    _armView = v;
    ['all','open','mine'].forEach(function(id) {
        document.getElementById('armChip' + id.charAt(0).toUpperCase() + id.slice(1))
            .className = 'mob-chip' + (id === v ? ' active' : '');
    });
    armFilter();
}

function armSetContinent(c) {
    _armContinent = c;
    document.querySelectorAll('[id^="armCont_"]').forEach(function(el) {
        el.className = 'mob-chip';
    });
    document.getElementById('armCont_' + c).className = 'mob-chip active';
    armFilter();
}

/* ── 完整区域列表（有记录的 + 无记录的补全） ── */
function buildFullList() {
    var full = _armAll.slice();
    var added = {};
    _armAll.forEach(function(r) { added[r.region] = true; });
    Object.keys(_armMap).forEach(function(code) {
        if (!added[code]) {
            full.push({ region: code, openCount: 0, monthlyOpenCount: 0,
                        openTime: null, lastNotifyTime: null });
        }
    });
    return full;
}

/* ── 过滤 & 渲染 ─────────────────────────── */
function armFilter() {
    var kw = document.getElementById('armSearch').value.trim().toLowerCase();
    var list = buildFullList().filter(function(r) {
        if (_armView === 'open' && !(r.openCount > 0)) return false;
        if (_armView === 'mine' && !_armMine.includes(r.region)) return false;
        if (_armContinent !== 'all' && getContinent(r.region) !== _armContinent) return false;
        if (kw) {
            var name = (_armMap[r.region] || r.region || '').toLowerCase();
            if (!name.includes(kw) && !r.region.toLowerCase().includes(kw)) return false;
        }
        return true;
    });

    list.sort(function(a, b) {
        var aOpen = a.openCount > 0, bOpen = b.openCount > 0;
        if (bOpen !== aOpen) return bOpen ? 1 : -1;
        if (aOpen && bOpen) {
            var ta = a.lastNotifyTime || a.openTime || '';
            var tb = b.lastNotifyTime || b.openTime || '';
            return tb.localeCompare(ta);
        }
        return a.region.localeCompare(b.region);
    });

    armRender(list);
}

function armRender(list) {
    var el = document.getElementById('armList');
    if (!list || list.length === 0) {
        el.innerHTML = '<div class="mob-empty"><i class="fas fa-globe-asia"></i><p>' + _armI18n.empty + '</p></div>';
        return;
    }
    el.innerHTML = list.map(function(r) {
        var isOpen  = r.openCount > 0;
        var isMine  = _armMine.includes(r.region);
        var name    = escA(_armMap[r.region] || r.region);
        var code    = escA(r.region);
        var cont    = getContinent(r.region);
        var contLbl = getContLabel(cont);
        var lastTime = r.lastNotifyTime ? fmtTime(r.lastNotifyTime) : '--';

        return '<div class="mob-arm-card' + (isOpen ? ' mob-arm-card-open' : '') + '">'
            + '<div class="mob-arm-card-header">'
            +   '<div class="mob-arm-card-title-wrap">'
            +     '<div class="mob-arm-card-name">' + name + '</div>'
            +     '<div class="mob-arm-card-code">'
            +       '<code>' + code + '</code>'
            +       '<span class="mob-arm-cont-tag">' + contLbl + '</span>'
            +     '</div>'
            +   '</div>'
            +   '<div class="mob-arm-card-badges">'
            +     (isOpen ? '<span class="mob-badge mob-arm-badge-open">' + _armI18n.badgeOpen + '</span>' : '<span class="mob-badge mob-badge-gray">' + _armI18n.badgeNo + '</span>')
            +     (isMine ? '<span class="mob-badge mob-arm-badge-mine">' + _armI18n.badgeMine + '</span>' : '')
            +   '</div>'
            + '</div>'
            + '<div class="mob-arm-card-metrics">'
            +   '<div class="mob-arm-metric">'
            +     '<div class="mob-arm-metric-num">' + (r.openCount || 0) + '</div>'
            +     '<div class="mob-arm-metric-lbl">' + _armI18n.metricTotal + '</div>'
            +   '</div>'
            +   '<div class="mob-arm-metric">'
            +     '<div class="mob-arm-metric-num">' + (r.monthlyOpenCount || 0) + '</div>'
            +     '<div class="mob-arm-metric-lbl">' + _armI18n.metricMonthly + '</div>'
            +   '</div>'
            +   '<div class="mob-arm-metric">'
            +     '<div class="mob-arm-metric-num mob-arm-metric-time">' + lastTime + '</div>'
            +     '<div class="mob-arm-metric-lbl">' + _armI18n.metricLast + '</div>'
            +   '</div>'
            + '</div>'
            + '</div>';
    }).join('');
}

/* ── 工具 ─────────────────────────────────── */
function fmtTime(s) {
    if (!s) return '--';
    try {
        var d = new Date(s);
        var yyyy = d.getFullYear();
        var mo = String(d.getMonth()+1).padStart(2,'0');
        var dd = String(d.getDate()).padStart(2,'0');
        var hh = String(d.getHours()).padStart(2,'0');
        var mm = String(d.getMinutes()).padStart(2,'0');
        return yyyy + '-' + mo + '-' + dd + ' ' + hh + ':' + mm;
    } catch(e) { return s; }
}

function escA(s) {
    if (!s) return '';
    return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
}

armLoad();
/* 每5分钟自动刷新 */
setInterval(armLoad, 5 * 60 * 1000);
</script>
</#noparse>

</@layout.page>
