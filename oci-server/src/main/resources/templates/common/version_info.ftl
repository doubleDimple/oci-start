<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Version Info Modal</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }

        .version-modal {
            display: none; position: fixed;
            top: 0; left: 0; width: 100%; height: 100%;
            background: rgba(15, 23, 42, 0.7); backdrop-filter: blur(10px);
            z-index: 99999; justify-content: center; align-items: center; padding: 20px;
        }

        .version-modal-content {
            background: #ffffff; border-radius: 28px;
            width: 750px;
            max-width: 95%;
            box-shadow: 0 30px 60px -12px rgba(0, 0, 0, 0.4);
            animation: modalFadeIn 0.5s cubic-bezier(0.16, 1, 0.3, 1);
            position: relative; overflow: hidden;
        }

        @keyframes modalFadeIn {
            from { opacity: 0; transform: scale(0.95) translateY(10px); }
            to { opacity: 1; transform: scale(1) translateY(0); }
        }

        .version-modal-close {
            position: absolute; right: 20px; top: 20px;
            background: #f1f5f9; border: none; color: #64748b;
            width: 36px; height: 36px; border-radius: 50%; cursor: pointer;
            z-index: 10; transition: 0.2s;
        }
        .version-modal-close:hover { background: #fee2e2; color: #ef4444; transform: rotate(90deg); }
        .modal-top-section {
            display: flex; align-items: center; padding: 40px 40px 30px; gap: 30px;
        }

        .app-branding { display: flex; align-items: center; gap: 20px; flex: 1; }
        .app-icon {
            width: 70px; height: 70px;
            background: linear-gradient(135deg, #e0f2fe 0%, #bae6fd 100%);
            color: #0ea5e9; border-radius: 20px;
            display: flex; align-items: center; justify-content: center;
            font-size: 32px; flex-shrink: 0;
            box-shadow: 0 10px 15px -3px rgba(14, 165, 233, 0.2);
        }

        .version-status-compact {
            display: flex; background: #f8fafc; border-radius: 18px;
            padding: 15px 25px; border: 1px solid #edf2f7; gap: 30px;
        }
        .status-item { text-align: left; }
        .status-label { display: block; color: #94a3b8; font-size: 11px; font-weight: 700; text-transform: uppercase; margin-bottom: 2px; }
        .status-value { font-weight: 800; color: #1e293b; font-family: monospace; font-size: 16px; }

        .links-row {
            display: flex; gap: 12px; padding: 0 40px 30px;
        }
        .btn-link-item {
            flex: 1; display: flex; align-items: center; justify-content: center; gap: 8px;
            padding: 12px; border-radius: 12px; background: #fff; border: 1px solid #e2e8f0;
            text-decoration: none; color: #475569; font-size: 13px; transition: 0.2s;
        }
        .btn-link-item:hover { border-color: #0ea5e9; color: #0ea5e9; background: #f0f9ff; transform: translateY(-2px); }

        .donate-area {
            background: linear-gradient(180deg, #f8fafc 0%, #f1f5f9 100%);
            padding: 30px 40px 40px; border-top: 1px solid #edf2f7;
        }
        .donate-header {
            display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px;
        }
        .donate-header h4 { color: #334155; font-size: 15px; font-weight: 700; }
        .donate-header span { color: #94a3b8; font-size: 12px; }

        .donate-grid-wide {
            display: grid; grid-template-columns: 1fr 1fr; gap: 20px;
        }
        .donate-card-wide {
            background: #ffffff; border-radius: 20px; padding: 15px;
            display: flex; align-items: center; gap: 20px;
            box-shadow: 0 4px 6px -1px rgba(0,0,0,0.05); transition: 0.3s;
        }
        .donate-card-wide:hover { transform: scale(1.02); box-shadow: 0 20px 25px -5px rgba(0,0,0,0.1); }

        .qr-thumb {
            width: 100px; height: 100px; background: #f8fafc; border-radius: 12px;
            padding: 6px; flex-shrink: 0; cursor: zoom-in;
        }
        .qr-thumb img { width: 100%; height: 100%; object-fit: contain; }

        .donate-info-right { flex: 1; text-align: left; }
        .method-tag {
            font-size: 14px; font-weight: 700; color: #1e293b;
            display: flex; align-items: center; gap: 6px; margin-bottom: 8px;
        }
        .copy-pill {
            display: inline-block; background: #f1f5f9; padding: 6px 12px;
            border-radius: 8px; font-size: 11px; color: #64748b; cursor: pointer;
            transition: 0.2s; border: 1px solid transparent;
        }
        .copy-pill:hover { background: #e2e8f0; border-color: #cbd5e1; color: #0f172a; }

        /* 版本 Tag */
        .v-tag { padding: 2px 6px; border-radius: 5px; font-size: 10px; margin-left: 5px; }
        .v-tag-new { background: #fef9c3; color: #854d0e; }
        .v-tag-ok { background: #dcfce7; color: #166534; }

        /* 图片放大灯箱 */
        .viewer-overlay {
            display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%;
            background: rgba(0,0,0,0.9); backdrop-filter: blur(15px); z-index: 100000;
            justify-content: center; align-items: center; cursor: zoom-out;
        }
        .viewer-overlay img { max-width: 90%; max-height: 80vh; border-radius: 12px; animation: zoomIn 0.3s; }
        @keyframes zoomIn { from { transform: scale(0.8); } to { transform: scale(1); } }

        /* ── Dark mode overrides ── */
        [data-theme="dark"] .version-modal-content {
            background: #1e2430;
            box-shadow: 0 30px 60px -12px rgba(0,0,0,0.7);
        }
        [data-theme="dark"] .version-modal-close {
            background: #2a3144;
            color: #94a3b8;
        }
        [data-theme="dark"] .version-modal-close:hover {
            background: rgba(239,68,68,0.15);
            color: #f87171;
        }
        [data-theme="dark"] .version-status-compact {
            background: #252d3d;
            border-color: #2e3a4e;
        }
        [data-theme="dark"] .status-label { color: #6b7fa3; }
        [data-theme="dark"] .status-value { color: #e2e8f0; }
        [data-theme="dark"] .version-status-compact > div[style] { background: #2e3a4e !important; }

        [data-theme="dark"] .btn-link-item {
            background: #252d3d;
            border-color: #2e3a4e;
            color: #94a3b8;
        }
        [data-theme="dark"] .btn-link-item:hover {
            border-color: #0ea5e9;
            color: #38bdf8;
            background: rgba(14,165,233,0.08);
        }

        [data-theme="dark"] .donate-area {
            background: linear-gradient(180deg, #1a2133 0%, #161e2e 100%);
            border-top-color: #2e3a4e;
        }
        [data-theme="dark"] .donate-header h4 { color: #cbd5e1; }
        [data-theme="dark"] .donate-header span { color: #6b7fa3; }

        [data-theme="dark"] .donate-card-wide {
            background: #252d3d;
            box-shadow: 0 4px 6px -1px rgba(0,0,0,0.3);
        }
        [data-theme="dark"] .qr-thumb { background: #1e2430; }

        [data-theme="dark"] .method-tag { color: #e2e8f0; }
        [data-theme="dark"] .copy-pill {
            background: #2e3a4e;
            color: #94a3b8;
        }
        [data-theme="dark"] .copy-pill:hover {
            background: #374357;
            border-color: #4a5568;
            color: #e2e8f0;
        }
        [data-theme="dark"] h3[style] { color: #e2e8f0 !important; }
        [data-theme="dark"] p[style]  { color: #6b7fa3 !important; }
        [data-theme="dark"] .v-tag-new { background: rgba(234,179,8,0.15);  color: #fbbf24; }
        [data-theme="dark"] .v-tag-ok  { background: rgba(34,197,94,0.15);  color: #4ade80; }
    </style>
</head>
<body>

<#--<div style="padding: 50px; text-align: center;">
    <button onclick="showVersionInfo()" style="padding: 12px 28px; border-radius: 12px; cursor: pointer; background: #0ea5e9; color: white; border: none; font-weight: 600;">查看版本信息</button>
</div>-->

<div id="version-info-modal" class="version-modal">
    <div class="version-modal-content">
        <button class="version-modal-close" onclick="closeVersionModal()"><i class="fas fa-times"></i></button>

        <div class="modal-top-section">
            <div class="app-branding">
                <div class="app-icon"><i class="fas fa-rocket"></i></div>
                <div>
                    <h3 style="color: #0f172a; font-size: 24px; font-weight: 800;">Oci-Start</h3>
                    <p style="color: #94a3b8; font-size: 13px;">Created by doubleDimple</p>
                </div>
            </div>
            <div class="version-status-compact">
                <div class="status-item">
                    <span class="status-label">Current</span>
                    <div id="current-version" class="status-value">加载中...</div>
                </div>
                <div style="width: 1px; background: #e2e8f0;"></div>
                <div class="status-item">
                    <span class="status-label">Latest</span>
                    <div id="latest-version" class="status-value">加载中...</div>
                </div>
            </div>
        </div>

        <div class="links-row">
            <a href="https://github.com/doubleDimple/oci-start" target="_blank" class="btn-link-item"><i class="fab fa-github"></i><span>开源仓库</span></a>
            <a href="https://t.me/+M7XhteVCMMU5ZDhh" target="_blank" class="btn-link-item"><i class="fab fa-telegram"></i><span>Telegram</span></a>
            <a href="https://github.com/doubleDimple/oci-start/releases" target="_blank" class="btn-link-item"><i class="fas fa-file-code"></i><span>更新日志</span></a>
        </div>

        <div class="donate-area">
            <div class="donate-header">
                <h4>请作者喝杯咖啡 <i class="fas fa-coffee" style="color:#f43f5e"></i></h4>
                <span>点击二维码可放大预览</span>
            </div>
            <div class="donate-grid-wide">
                <div class="donate-card-wide">
                    <div class="qr-thumb" onclick="zoomImage(this)">
                        <img src="/images/weixin.JPG" alt="微信支付">
                    </div>
                    <div class="donate-info-right">
                        <div class="method-tag"><i class="fab fa-weixin" style="color: #07C160;"></i> 微信支付</div>
                        <p style="font-size: 12px; color: #94a3b8;">扫码赞赏支持</p>
                    </div>
                </div>
                <div class="donate-card-wide">
                    <div class="qr-thumb" onclick="zoomImage(this)">
                        <img src="/images/binance_qr.jpg" alt="币安打赏">
                    </div>
                    <div class="donate-info-right">
                        <div class="method-tag"><i class="fas fa-coins" style="color: #F3BA2F;"></i> 币安/USDT</div>
                        <div class="copy-pill" onclick="copyAddress('TMHTdWVm6ThvhihWqM1ViSDKMMsGcCBHtT', event)">
                            <i class="far fa-copy"></i> TRC20 复制地址
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<div id="viewer-overlay" class="viewer-overlay" onclick="this.style.display='none'">
    <img id="viewer-img" src="">
</div>

<script>
    function showVersionInfo() {
        const modal = document.getElementById('version-info-modal');
        if (modal) {
            modal.style.display = 'flex';
            document.body.style.overflow = 'hidden';
            fetchVersionInfo();
        }
    }

    function closeVersionModal() {
        const modal = document.getElementById('version-info-modal');
        if (modal) {
            modal.style.display = 'none';
            document.body.style.overflow = '';
        }
    }

    function zoomImage(el) {
        const src = el.querySelector('img').src;
        document.getElementById('viewer-img').src = src;
        document.getElementById('viewer-overlay').style.display = 'flex';
    }

    function copyAddress(text, e) {
        if (!text) return;

        navigator.clipboard.writeText(text).then(() => {
            const btn = e.currentTarget;
            const oldHtml = btn.innerHTML;

            btn.innerHTML = '<i class="fas fa-check"></i> 已复制';
            btn.style.color = '#10b981';

            setTimeout(() => {
                btn.innerHTML = oldHtml;
                btn.style.color = '';
            }, 2000);
        }).catch(err => {
            console.error('复制失败:', err);
        });
    }

    function fetchVersionInfo() {
        fetch('/api/version/check').then(res => res.json()).then(data => {
            const cur = document.getElementById('current-version');
            const lat = document.getElementById('latest-version');
            if(cur) cur.innerHTML = data.currentVersion + (data.needUpdate ? '<span class="v-tag v-tag-new">UPDATE</span>' : '<span class="v-tag v-tag-ok">LATEST</span>');
            if(lat) lat.textContent = data.latestVersion || data.currentVersion;
        }).catch(() => {
            document.getElementById('current-version').textContent = 'v1.0.0';
        });
    }

    document.addEventListener('DOMContentLoaded', () => {
        const modal = document.getElementById('version-info-modal');
        modal.addEventListener('click', (e) => { if(e.target === modal) closeVersionModal(); });
        document.addEventListener('keydown', (e) => { if(e.key === 'Escape') { closeVersionModal(); document.getElementById('viewer-overlay').style.display='none'; }});
    });
</script>

</body>
</html>