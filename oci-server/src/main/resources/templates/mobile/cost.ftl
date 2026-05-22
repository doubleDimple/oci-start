<#import "layout.ftl" as layout>
<@layout.page title="账号花费" activePage="cost">

<style>
.mob-tf-stat-card {
    background:var(--mob-card);border-radius:12px;padding:12px 10px;
    text-align:center;border:1px solid var(--mob-border)
}
.mob-tf-stat-val   { font-size:18px;font-weight:700;line-height:1.2 }
.mob-tf-stat-label { font-size:11px;color:var(--mob-text-muted);margin-top:4px }
.mob-cost-item {
    background:var(--mob-card);border-radius:12px;padding:12px 14px;
    margin-bottom:8px;border:1px solid var(--mob-border)
}
</style>

<!-- 返回按钮（从租户页进入时显示） -->
<#if tenantId?has_content>
<div style="display:flex;align-items:center;gap:12px;margin-bottom:16px">
    <button onclick="window.location.href='/m/tenants?menuId='+encodeURIComponent(_costTenantId)" style="width:36px;height:36px;border-radius:50%;border:1.5px solid var(--mob-border);background:var(--mob-card);color:var(--mob-text);display:flex;align-items:center;justify-content:center;cursor:pointer;flex-shrink:0;padding:0">
        <i class="fas fa-chevron-left" style="font-size:13px"></i>
    </button>
    <div style="flex:1;min-width:0">
        <div style="font-size:16px;font-weight:700;color:var(--mob-text)">账号花费</div>
    </div>
</div>
</#if>

<!-- 查询条件卡片 -->
<div class="mob-card" style="margin-bottom:12px">
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:10px;margin-bottom:12px">
        <div>
            <div style="font-size:11px;color:var(--mob-text-muted);margin-bottom:4px">开始日期</div>
            <input type="date" id="costStartDate" class="mob-tf-input">
        </div>
        <div>
            <div style="font-size:11px;color:var(--mob-text-muted);margin-bottom:4px">结束日期</div>
            <input type="date" id="costEndDate" class="mob-tf-input">
        </div>
    </div>
    <div style="display:flex;align-items:center;gap:8px;margin-top:10px;margin-bottom:12px">
        <input type="checkbox" id="filterPositive" style="width:16px;height:16px;accent-color:var(--mob-accent)">
        <label for="filterPositive" style="font-size:12px;color:var(--mob-text)">只显示消费金额 &gt; 0 的记录</label>
    </div>
    <button class="mob-btn mob-btn-primary" style="width:100%" onclick="queryCost()">
        <i class="fas fa-search" style="margin-right:6px"></i>查询花费
    </button>
</div>

<!-- 汇总卡片 -->
<div id="costSummary" style="display:none;margin-bottom:12px">
    <div style="display:grid;grid-template-columns:repeat(2,1fr);gap:8px">
        <div class="mob-tf-stat-card">
            <div class="mob-tf-stat-val" id="costTotalDays" style="color:#5b8af0">0</div>
            <div class="mob-tf-stat-label">记录条数</div>
        </div>
        <div class="mob-tf-stat-card">
            <div class="mob-tf-stat-val" id="costTotalAmount" style="color:#43b581">$0.00</div>
            <div class="mob-tf-stat-label">总花费</div>
        </div>
    </div>
</div>

<!-- 加载状态 -->
<div id="costLoading" class="mob-loading" style="display:none">
    <div class="mob-spinner"></div>
    <p>查询中…</p>
</div>

<!-- 结果列表 -->
<div id="costList"></div>

<script>
var _costTenantId = '${tenantId!}';
</script>
<#noparse>
<script>
(function() {
    var _costRawList = [];   // 保存原始完整列表，供 checkbox 切换时复用

    // 初始化日期：默认本月
    var now = new Date();
    var y   = now.getFullYear();
    var m   = String(now.getMonth() + 1).padStart(2, '0');
    document.getElementById('costStartDate').value = y + '-' + m + '-01';
    document.getElementById('costEndDate').value   = now.toISOString().split('T')[0];

    // checkbox 切换时直接用缓存数据重新渲染
    document.getElementById('filterPositive').addEventListener('change', function() {
        if (_costRawList.length > 0) renderCost(_costRawList);
    });

    window.queryCost = async function() {
        var startDate = document.getElementById('costStartDate').value;
        var endDate   = document.getElementById('costEndDate').value;
        if (!startDate || !endDate) { costToast('请选择日期范围', 'warn'); return; }

        document.getElementById('costLoading').style.display  = '';
        document.getElementById('costSummary').style.display  = 'none';
        document.getElementById('costList').innerHTML         = '';
        _costRawList = [];

        try {
            var csrf = (document.querySelector('meta[name="_csrf"]')||{}).content||'';
            var body = { startDate: startDate, endDate: endDate };
            if (_costTenantId) body.tenantId = _costTenantId;

            var res  = await fetch('/cost/query', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'X-CSRF-TOKEN': csrf },
                body: JSON.stringify(body)
            });
            var json = await res.json();
            var data = json.data || json;
            _costRawList = Array.isArray(data) ? data : (data.list || data.items || []);
            renderCost(_costRawList);
        } catch(e) {
            document.getElementById('costLoading').style.display = 'none';
            document.getElementById('costList').innerHTML =
                '<p style="text-align:center;color:#f04747;padding:24px">查询失败: ' + escHtml(e.message) + '</p>';
        }
    };

    function renderCost(list) {
        document.getElementById('costLoading').style.display = 'none';
        var filterPositive = document.getElementById('filterPositive').checked;
        if (filterPositive) {
            list = list.filter(function(item) {
                var v = parseFloat(item.amount || item.cost || item.totalAmount || item.value || 0);
                return !isNaN(v) && v > 0;
            });
        }
        if (!list || list.length === 0) {
            document.getElementById('costList').innerHTML =
                '<div style="text-align:center;padding:40px 0">'
                + '<i class="fas fa-coins" style="font-size:48px;opacity:0.2;display:block;margin-bottom:12px"></i>'
                + '<p style="color:var(--mob-text-muted)">暂无花费数据</p></div>';
            return;
        }

        // 计算总金额
        var total = 0;
        list.forEach(function(item) {
            var v = parseFloat(item.amount || item.cost || item.totalAmount || item.value || 0);
            if (!isNaN(v)) total += v;
        });
        document.getElementById('costTotalDays').textContent   = list.length;
        document.getElementById('costTotalAmount').textContent = '$' + total.toFixed(4);
        document.getElementById('costSummary').style.display   = '';

        // 找最大值用于绘制进度条
        var maxVal = 0;
        list.forEach(function(item) {
            var v = parseFloat(item.amount || item.cost || item.totalAmount || item.value || 0);
            if (!isNaN(v) && v > maxVal) maxVal = v;
        });

        document.getElementById('costList').innerHTML = list.map(function(item) {
            var date    = item.date || item.day || item.timeUsageStarted || item.startDate || '—';
            var amount  = parseFloat(item.amount || item.cost || item.totalAmount || item.value || 0);
            var svc     = item.service || item.serviceName || item.resourceType || '';
            var region  = item.region || '';
            var pct     = maxVal > 0 ? (amount / maxVal * 100) : 0;
            var barColor = amount > 1 ? '#f04747' : (amount > 0.1 ? '#faa61a' : '#43b581');
            return '<div class="mob-cost-item">'
                + '<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:6px">'
                + '<div>'
                + '<div style="font-size:13px;font-weight:600;color:var(--mob-text)">' + escHtml(String(date)) + '</div>'
                + (svc ? '<div style="font-size:11px;color:var(--mob-text-muted);margin-top:1px">' + escHtml(svc) + (region ? ' · ' + escHtml(region) : '') + '</div>' : '')
                + '</div>'
                + '<div style="font-size:16px;font-weight:700;color:' + barColor + '">'
                + '$' + amount.toFixed(4)
                + '</div>'
                + '</div>'
                + '<div style="background:var(--mob-bg);border-radius:4px;overflow:hidden;height:5px">'
                + '<div style="height:5px;width:' + pct.toFixed(1) + '%;background:' + barColor + ';border-radius:4px;transition:width .5s"></div>'
                + '</div>'
                + '</div>';
        }).join('');
    }

    function escHtml(s) {
        if (!s) return '';
        return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    }

    function costToast(msg, type) {
        var t = document.createElement('div');
        t.style.cssText = 'position:fixed;bottom:80px;left:50%;transform:translateX(-50%);background:'
            + (type==='error'||type==='warn'?'#faa61a':'#43b581')
            + ';color:#fff;padding:10px 20px;border-radius:20px;font-size:13px;z-index:9999;white-space:nowrap;box-shadow:0 4px 12px rgba(0,0,0,0.3)';
        t.textContent = msg;
        document.body.appendChild(t);
        setTimeout(function() { t.remove(); }, 2500);
    }

    // 若有 tenantId 则自动查询
    if (_costTenantId) {
        document.addEventListener('DOMContentLoaded', function() {
            queryCost();
        });
    }
})();
</script>
</#noparse>

</@layout.page>
