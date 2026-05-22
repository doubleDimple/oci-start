<#import "layout.ftl" as layout>
<@layout.page title="${msg.get('mob.mfa.title')}" activePage="mfa">

<#assign avatarColors = ['#1abc9c','#3498db','#9b59b6','#e67e22','#e74c3c','#2ecc71','#f39c12','#16a085']>

<!-- 搜索栏 -->
<div class="mob-mfa-search-bar">
    <i class="fas fa-search mob-mfa-search-icon"></i>
    <input type="text" class="mob-mfa-search-input" id="mobMfaSearch"
           placeholder="${msg.get('mfa.search.placeholder')}" oninput="mobMfaFilter()">
</div>

<!-- 统计栏 -->
<div class="mob-mfa-stat-bar" id="mobMfaStatBar">
    <span id="mobMfaCount">
        <#if otpKeys??>${otpKeys?size}<#else>0</#if>
    </span>
    ${msg.get('mfa.table.unit')}
    <span class="mob-mfa-refresh-hint">
        · ${msg.get('mfa.table.refresh_tip')} <span id="mobMfaCountdown">30</span>s
    </span>
</div>

<!-- 密钥卡片列表 -->
<div id="mobMfaList">
    <#if otpKeys?? && (otpKeys?size > 0)>
        <#list otpKeys as key>
        <div class="mob-mfa-swipe-wrap">
            <div class="mob-mfa-card" data-name="${key.keyName}" data-issuer="${key.issuer!'mfa-start'}">
                <!-- 头像 -->
                <div class="mob-mfa-avatar" style="background:${avatarColors[key?index % 8]}">
                    ${key.keyName?substring(0,1)?upper_case}
                </div>
                <!-- 中间信息 -->
                <div class="mob-mfa-mid">
                    <div class="mob-mfa-name">${key.keyName}</div>
                    <div class="mob-mfa-issuer">${key.issuer!'mfa-start'}</div>
                    <div class="mob-mfa-code-row" onclick="mobMfaCopyCode(this)">
                        <span class="mob-mfa-code-val" data-secret="${key.secretKey}">
                            ···   ···
                        </span>
                        <i class="fas fa-copy mob-mfa-copy-btn"></i>
                    </div>
                </div>
                <!-- 右侧环形计时 -->
                <div class="mob-mfa-right">
                    <div class="mob-mfa-ring-wrap">
                        <svg class="mob-mfa-ring" viewBox="0 0 36 36">
                            <circle class="mob-mfa-ring-track" cx="18" cy="18" r="15.9"/>
                            <circle class="mob-mfa-ring-arc" cx="18" cy="18" r="15.9"/>
                        </svg>
                        <span class="mob-mfa-time-label">30</span>
                    </div>
                </div>
            </div>
            <!-- 左滑显示的删除按钮 -->
            <button class="mob-mfa-swipe-del" onclick="mobMfaDelete('${key.keyName}')">
                <i class="fas fa-trash-alt"></i>
                <span>删除</span>
            </button>
        </div>
        </#list>
    <#else>
    <!-- 空状态 -->
    <div class="mob-mfa-empty" id="mobMfaEmpty">
        <div class="mob-mfa-empty-icon"><i class="fas fa-shield-alt"></i></div>
        <div class="mob-mfa-empty-title">${msg.get('mfa.table.empty')}</div>
        <div class="mob-mfa-empty-sub">点击右下角 <i class="fas fa-plus-circle" style="color:var(--mob-primary)"></i> 按钮添加</div>
    </div>
    </#if>
</div>

<!-- FAB 添加按钮 -->
<button class="mob-mfa-fab" onclick="mobMfaOpenAdd()" title="${msg.get('mfa.action.add')}">
    <i class="fas fa-plus"></i>
</button>

<!-- ══════════ 添加密钥 Bottom Sheet ══════════ -->
<div class="mob-mfa-overlay" id="mobMfaOverlay" onclick="mobMfaCloseAdd()"></div>

<div class="mob-mfa-sheet" id="mobMfaSheet">
    <div class="mob-sheet-handle"></div>
    <div class="mob-sheet-title">${msg.get('mfa.form.add_title')}</div>

    <!-- 选项卡 -->
    <div class="mob-mfa-tabs">
        <button class="mob-mfa-tab active" id="mobMfaTabBtnManual" onclick="mobMfaSwitchTab('manual')">
            <i class="fas fa-keyboard"></i> ${msg.get('mob.mfa.tab.manual')}
        </button>
        <button class="mob-mfa-tab" id="mobMfaTabBtnScan" onclick="mobMfaSwitchTab('scan')">
            <i class="fas fa-qrcode"></i> ${msg.get('mob.mfa.tab.scan')}
        </button>
    </div>

    <!-- 手动输入 Tab -->
    <div id="mobMfaPanelManual">
        <div class="mob-sf-row" style="margin-bottom:12px">
            <label class="mob-sf-label">${msg.get('mfa.form.label_name')} <span style="color:#e74c3c">*</span></label>
            <input class="mob-sf-input" type="text" id="mobMfaInputName"
                   placeholder="${msg.get('mfa.form.placeholder_name')}">
        </div>
        <div class="mob-sf-row" style="margin-bottom:18px">
            <label class="mob-sf-label">${msg.get('mfa.form.label_secret')} <span style="color:#e74c3c">*</span></label>
            <input class="mob-sf-input" type="text" id="mobMfaInputSecret"
                   placeholder="${msg.get('mfa.form.placeholder_secret')}"
                   autocomplete="off" autocorrect="off" spellcheck="false">
        </div>
        <button class="mob-btn mob-btn-primary mob-btn-full" onclick="mobMfaSaveManual()">
            <i class="fas fa-save"></i> ${msg.get('mfa.action.save')}
        </button>
    </div>

    <!-- 扫码 Tab -->
    <div id="mobMfaPanelScan" style="display:none">
        <!-- 摄像头区域 -->
        <div class="mob-mfa-scan-wrap" id="mobMfaScanWrap">
            <video id="mobMfaScanVideo" class="mob-mfa-scan-video" autoplay muted playsinline></video>
            <canvas id="mobMfaScanCanvas" style="display:none"></canvas>
            <!-- 取景框 -->
            <div class="mob-mfa-scan-frame">
                <div class="mob-mfa-corner tl"></div>
                <div class="mob-mfa-corner tr"></div>
                <div class="mob-mfa-corner bl"></div>
                <div class="mob-mfa-corner br"></div>
                <div class="mob-mfa-scan-line"></div>
            </div>
            <div class="mob-mfa-scan-hint">${msg.get('mob.mfa.scan.hint')}</div>
        </div>
        <!-- 权限提示（默认隐藏，相机权限被拒时显示） -->
        <div class="mob-mfa-cam-deny" id="mobMfaCamDeny" style="display:none">
            <i class="fas fa-camera-slash" style="font-size:32px;margin-bottom:8px;color:var(--mob-text-muted)"></i>
            <div style="font-size:13px;color:var(--mob-text-muted);text-align:center">
                ${msg.get('mob.mfa.scan.no_camera')}
            </div>
        </div>
        <!-- 分割线 -->
        <div class="mob-mfa-divider">
            <div class="mob-mfa-divider-line"></div>
            <span class="mob-mfa-divider-text">${msg.get('mob.mfa.or')}</span>
            <div class="mob-mfa-divider-line"></div>
        </div>
        <!-- 上传图片 -->
        <label class="mob-btn mob-btn-outline mob-btn-full" style="cursor:pointer;justify-content:center">
            <i class="fas fa-image"></i> ${msg.get('mob.mfa.upload.btn')}
            <input type="file" id="mobMfaFileInput" accept="image/*" style="display:none"
                   onchange="mobMfaUploadFile(this)">
        </label>
    </div>
</div>

<script>
(function() {
    /* ── 全局状态 ─────────────────────── */
    var _csrf       = document.querySelector('meta[name="_csrf"]').content;
    var _csrfHeader = document.querySelector('meta[name="_csrf_header"]').content;
    var _otpTimer   = null;
    var _camStream  = null;
    var _scanning   = false;
    var _tab        = 'manual';

    /* ── OTP 更新 ──────────────────────── */
    function startOtpLoop() {
        refreshOtpCodes();
        _otpTimer = setInterval(function() {
            var left = 30 - (Math.floor(Date.now() / 1000) % 30);
            var el = document.getElementById('mobMfaCountdown');
            if (el) el.textContent = left;
            // 更新环形进度
            document.querySelectorAll('.mob-mfa-card').forEach(function(card) {
                updateRing(card, left);
            });
            if (left === 30) refreshOtpCodes();
        }, 1000);
    }

    function refreshOtpCodes() {
        var codeEls = document.querySelectorAll('.mob-mfa-code-val[data-secret]');
        if (!codeEls.length) return;
        var secrets = Array.from(codeEls).map(function(el) {
            return el.getAttribute('data-secret');
        }).filter(Boolean);
        if (!secrets.length) return;

        fetch('/generate-otp-batch', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                [_csrfHeader]: _csrf
            },
            body: JSON.stringify({ secretKeys: secrets })
        })
        .then(function(r) { return r.json(); })
        .then(function(data) {
            var map = {};
            data.forEach(function(item) { map[item.secretKey] = item.otpCode; });
            codeEls.forEach(function(el) {
                var code = map[el.getAttribute('data-secret')];
                if (code) {
                    // 格式化为 "123 456"
                    el.textContent = code.substring(0,3) + '  ' + code.substring(3);
                }
            });
        })
        .catch(function(e) { console.error('OTP refresh error', e); });
    }

    /* ── 环形计时器 ───────────────────── */
    function updateRing(card, timeLeft) {
        var arc     = card.querySelector('.mob-mfa-ring-arc');
        var lbl     = card.querySelector('.mob-mfa-time-label');
        var codeVal = card.querySelector('.mob-mfa-code-val');
        if (!arc) return;
        var offset = 100 - (timeLeft / 30 * 100);
        arc.style.strokeDashoffset = offset;
        lbl.textContent = timeLeft;
        var isWarn   = timeLeft <= 10 && timeLeft > 5;
        var isDanger = timeLeft <= 5;
        arc.classList.toggle('warn',   isWarn);
        arc.classList.toggle('danger', isDanger);
        if (codeVal) {
            codeVal.classList.toggle('mob-mfa-code-warn',   isWarn);
            codeVal.classList.toggle('mob-mfa-code-danger', isDanger || (timeLeft <= 10));
        }
    }

    /* ── 复制 OTP ─────────────────────── */
    window.mobMfaCopyCode = function(row) {
        var val = row.querySelector('.mob-mfa-code-val');
        if (!val) return;
        var code = (val.textContent || '').replace(/\s/g, '');
        if (!code || code.includes('·')) return;
        mobCopy(code);
    };

    /* ── 删除 ─────────────────────────── */
    window.mobMfaDelete = function(keyName) {
        mobConfirm('${msg.get('mfa.confirm.delete_title')}', keyName).then(function(ok) {
            if (!ok) return;
            fetch('/delete-key', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    [_csrfHeader]: _csrf
                },
                body: JSON.stringify({ keyName: keyName })
            })
            .then(function(r) { if (r.ok) location.reload(); })
            .catch(function(e) { mobToast('删除失败: ' + e.message, 'error'); });
        });
    };

    /* ── 搜索过滤 ─────────────────────── */
    window.mobMfaFilter = function() {
        var q = (document.getElementById('mobMfaSearch').value || '').toLowerCase();
        var cards = document.querySelectorAll('.mob-mfa-card');
        var n = 0;
        cards.forEach(function(c) {
            var name   = (c.getAttribute('data-name')   || '').toLowerCase();
            var issuer = (c.getAttribute('data-issuer') || '').toLowerCase();
            var show = !q || name.includes(q) || issuer.includes(q);
            c.style.display = show ? '' : 'none';
            if (show) n++;
        });
        var cnt = document.getElementById('mobMfaCount');
        if (cnt) cnt.textContent = n;
    };

    /* ── 打开 / 关闭 Add Sheet ─────────── */
    window.mobMfaOpenAdd = function() {
        document.getElementById('mobMfaOverlay').classList.add('active');
        document.getElementById('mobMfaSheet').classList.add('active');
        document.body.style.overflow = 'hidden';
        // 默认手动 tab
        mobMfaSwitchTab('manual');
    };

    window.mobMfaCloseAdd = function() {
        document.getElementById('mobMfaOverlay').classList.remove('active');
        document.getElementById('mobMfaSheet').classList.remove('active');
        document.body.style.overflow = '';
        stopCamera();
    };

    /* ── 切换 Tab ────────────────────── */
    window.mobMfaSwitchTab = function(tab) {
        _tab = tab;
        var isManual = tab === 'manual';
        document.getElementById('mobMfaTabBtnManual').classList.toggle('active', isManual);
        document.getElementById('mobMfaTabBtnScan').classList.toggle('active', !isManual);
        document.getElementById('mobMfaPanelManual').style.display = isManual ? '' : 'none';
        document.getElementById('mobMfaPanelScan').style.display   = isManual ? 'none' : '';
        if (!isManual) {
            startCamera();
        } else {
            stopCamera();
        }
    };

    /* ── 懒加载 jsQR ──────────────────── */
    var _jsQRLoaded = false;
    function loadJsQR(callback) {
        if (typeof jsQR !== 'undefined') { callback(); return; }
        if (_jsQRLoaded) { var t = setInterval(function() { if (typeof jsQR !== 'undefined') { clearInterval(t); callback(); } }, 50); return; }
        _jsQRLoaded = true;
        var s = document.createElement('script');
        s.src = 'https://cdn.jsdelivr.net/npm/jsqr@1.4.0/dist/jsQR.min.js';
        s.onload = callback;
        s.onerror = function() { mobToast('扫码组件加载失败，请检查网络', 'error'); _jsQRLoaded = false; };
        document.head.appendChild(s);
    }

    /* ── 摄像头扫码 ───────────────────── */
    function startCamera() {
        if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
            showCamDeny(); return;
        }
        loadJsQR(function() {
        navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } })
        .then(function(stream) {
            _camStream = stream;
            _scanning  = true;
            var video = document.getElementById('mobMfaScanVideo');
            video.srcObject = stream;
            video.play();
            document.getElementById('mobMfaScanWrap').style.display = '';
            document.getElementById('mobMfaCamDeny').style.display  = 'none';
            requestAnimationFrame(scanFrame);
        })
        .catch(function() { showCamDeny(); });
        }); // end loadJsQR
    }

    function stopCamera() {
        _scanning = false;
        if (_camStream) {
            _camStream.getTracks().forEach(function(t) { t.stop(); });
            _camStream = null;
        }
        var video = document.getElementById('mobMfaScanVideo');
        if (video) video.srcObject = null;
    }

    function showCamDeny() {
        document.getElementById('mobMfaScanWrap').style.display = 'none';
        document.getElementById('mobMfaCamDeny').style.display  = '';
    }

    function scanFrame() {
        if (!_scanning) return;
        var video = document.getElementById('mobMfaScanVideo');
        var canvas = document.getElementById('mobMfaScanCanvas');
        if (video && video.readyState >= video.HAVE_ENOUGH_DATA && typeof jsQR !== 'undefined') {
            canvas.width  = video.videoWidth;
            canvas.height = video.videoHeight;
            var ctx = canvas.getContext('2d');
            ctx.drawImage(video, 0, 0);
            var imgData = ctx.getImageData(0, 0, canvas.width, canvas.height);
            var result  = jsQR(imgData.data, imgData.width, imgData.height);
            if (result && result.data) {
                handleQRResult(result.data);
                return;
            }
        }
        requestAnimationFrame(scanFrame);
    }

    function handleQRResult(url) {
        stopCamera();
        try {
            if (url.startsWith('otpauth://')) {
                var uri    = new URL(url);
                var secret = new URLSearchParams(uri.search).get('secret') || '';
                // label: "issuer:account" or just "account"
                var label  = decodeURIComponent(uri.pathname.replace('/totp/', '').replace('/hotp/', ''));
                var account = label.includes(':') ? label.split(':')[1] : label;
                // 切回手动 tab 填充
                mobMfaSwitchTab('manual');
                document.getElementById('mobMfaInputName').value   = account;
                document.getElementById('mobMfaInputSecret').value = secret;
                mobToast('扫码成功，请确认信息后保存 🎉', 'success');
            } else if (url.startsWith('otpauth-migration://')) {
                // Google 迁移码：转服务端处理（通过 canvas 生成 blob）
                mobToast('检测到 Google 迁移码，正在上传处理...', 'success');
                uploadUrlAsBlob(url);
            } else {
                mobToast('不支持的二维码格式', 'error');
                startCamera();
            }
        } catch(e) {
            mobToast('解析失败: ' + e.message, 'error');
            startCamera();
        }
    }

    // 将摄像头扫到的 URL 直接发给服务端解析
    function uploadUrlAsBlob(url) {
        var formData = new FormData();
        formData.append('qrUrl', url);
        formData.append('_csrf', _csrf);
        fetch('/save-secret', {
            method: 'POST',
            headers: { [_csrfHeader]: _csrf },
            body: formData
        })
        .then(function(r) {
            if (r.ok || r.redirected) {
                mobMfaCloseAdd();
                location.reload();
            } else {
                mobToast('保存失败（状态 ' + r.status + '），请重试', 'error');
            }
        })
        .catch(function(e) { mobToast('保存异常: ' + e.message, 'error'); });
    }

    /* ── 从相册上传 QR 图片 ──────────── */
    window.mobMfaUploadFile = function(input) {
        var file = input.files[0];
        if (!file) return;
        // 重置 input，方便重复选同一文件
        input.value = '';

        mobToast('正在处理图片...', 'success');

        var reader = new FileReader();
        reader.onload = function(e) {
            var img = new Image();
            img.onload = function() {
                // 压缩到最大 1200px（QR 码识别无需高清）
                var MAX = 1200;
                var w = img.width, h = img.height;
                if (w > MAX || h > MAX) {
                    if (w >= h) { h = Math.round(h * MAX / w); w = MAX; }
                    else        { w = Math.round(w * MAX / h); h = MAX; }
                }
                var canvas = document.createElement('canvas');
                canvas.width = w; canvas.height = h;
                canvas.getContext('2d').drawImage(img, 0, 0, w, h);
                canvas.toBlob(function(blob) {
                    var formData = new FormData();
                    formData.append('keyName', 'scan_' + Date.now());
                    formData.append('qrCode', blob, 'qr.jpg');
                    formData.append('_csrf', _csrf);
                    mobToast('正在解析二维码...', 'success');
                    fetch('/save-secret', {
                        method: 'POST',
                        headers: { [_csrfHeader]: _csrf },
                        body: formData
                    })
                    .then(function(r) {
                        if (r.ok || r.redirected) {
                            mobMfaCloseAdd();
                            location.reload();
                        } else {
                            mobToast('上传失败（状态 ' + r.status + '），请重试', 'error');
                        }
                    })
                    .catch(function(e) { mobToast('上传异常: ' + e.message, 'error'); });
                }, 'image/jpeg', 0.92);
            };
            img.onerror = function() { mobToast('图片读取失败，请重试', 'error'); };
            img.src = e.target.result;
        };
        reader.onerror = function() { mobToast('文件读取失败，请重试', 'error'); };
        reader.readAsDataURL(file);
    };

    /* ── 手动保存 ─────────────────────── */
    window.mobMfaSaveManual = function() {
        var name   = (document.getElementById('mobMfaInputName').value   || '').trim();
        var secret = (document.getElementById('mobMfaInputSecret').value || '').trim();
        if (!name)   { mobToast('${msg.get('mfa.form.require_name')}',   'error'); return; }
        if (!secret) { mobToast('${msg.get('mfa.form.require_secret')}', 'error'); return; }
        var formData = new FormData();
        formData.append('keyName',   name);
        formData.append('secretKey', secret);
        formData.append('_csrf',     _csrf);
        fetch('/save-secret', {
            method: 'POST',
            headers: { [_csrfHeader]: _csrf },
            body: formData
        })
        .then(function(r) {
            if (r.ok || r.redirected) {
                mobMfaCloseAdd();
                location.reload();
            } else {
                mobToast('保存失败，请重试', 'error');
            }
        })
        .catch(function(e) { mobToast('保存异常: ' + e.message, 'error'); });
    };

    /* ── 左滑删除 ────────────────────── */
    var SWIPE_THRESHOLD = 40;   // 触发展开的最小滑动距离
    var SWIPE_WIDTH     = 80;   // 删除按钮宽度

    function initSwipe(card) {
        var startX, startY, isDragging = false, isOpen = false;

        card.addEventListener('touchstart', function(e) {
            startX = e.touches[0].clientX;
            startY = e.touches[0].clientY;
            isDragging = false;
            card.style.transition = 'none';
        }, { passive: true });

        card.addEventListener('touchmove', function(e) {
            var dx = e.touches[0].clientX - startX;
            var dy = e.touches[0].clientY - startY;
            // 若纵向滑动更多则忽略（让页面正常滚动）
            if (!isDragging && Math.abs(dy) > Math.abs(dx)) return;
            if (Math.abs(dx) > 5) isDragging = true;
            if (!isDragging) return;

            var base  = isOpen ? -SWIPE_WIDTH : 0;
            var moved = Math.max(-SWIPE_WIDTH, Math.min(0, base + dx));
            card.style.transform = 'translateX(' + moved + 'px)';
        }, { passive: true });

        card.addEventListener('touchend', function(e) {
            if (!isDragging) return;
            card.style.transition = '';
            var dx  = e.changedTouches[0].clientX - startX;
            var base = isOpen ? -SWIPE_WIDTH : 0;
            var net  = base + dx;
            if (net < -SWIPE_THRESHOLD) {
                // 关闭其他已展开的
                closeAllSwipes(card);
                card.style.transform = 'translateX(-' + SWIPE_WIDTH + 'px)';
                isOpen = true;
            } else {
                card.style.transform = 'translateX(0)';
                isOpen = false;
            }
        }, { passive: true });

        // 点击卡片空白处收回
        card.addEventListener('click', function() {
            if (isOpen) {
                card.style.transform = 'translateX(0)';
                isOpen = false;
            }
        });

        card._swipeClose = function() {
            card.style.transition = '';
            card.style.transform  = 'translateX(0)';
            isOpen = false;
        };
    }

    function closeAllSwipes(except) {
        document.querySelectorAll('.mob-mfa-card').forEach(function(c) {
            if (c !== except && c._swipeClose) c._swipeClose();
        });
    }

    // 点击页面其他区域收起所有
    document.addEventListener('touchstart', function(e) {
        if (!e.target.closest('.mob-mfa-swipe-wrap')) {
            closeAllSwipes(null);
        }
    }, { passive: true });

    /* ── 初始化 ──────────────────────── */
    document.addEventListener('DOMContentLoaded', function() {
        // 初始化环形
        var left = 30 - (Math.floor(Date.now() / 1000) % 30);
        document.querySelectorAll('.mob-mfa-card').forEach(function(c) {
            updateRing(c, left);
            initSwipe(c);
        });
        startOtpLoop();
    });

    window.addEventListener('beforeunload', function() {
        if (_otpTimer) clearInterval(_otpTimer);
        stopCamera();
    });
})();
</script>

</@layout.page>
