(function () {
    'use strict';

    // Decorative public-region illustration from design/oci-start-login.html.
    // The routes illustrate the prototype's motion, not account data or live traffic.
    var LAND = [
        [[-168,65],[-165,60],[-158,57],[-152,58],[-146,60],[-138,59],[-131,53],[-125,49],[-124,42],[-120,34],[-117,32],[-110,24],[-105,20],[-97,16],[-92,15],[-88,16],[-87,21],[-91,21],[-95,19],[-97,23],[-97,26],[-94,29],[-89,29],[-84,30],[-81,25],[-80,32],[-76,35],[-70,42],[-67,45],[-60,47],[-56,51],[-56,54],[-64,60],[-78,62],[-78,55],[-82,55],[-86,66],[-95,68],[-105,68],[-115,70],[-125,70],[-135,69],[-145,70],[-156,71],[-166,68]],
        [[-45,60],[-52,64],[-53,68],[-62,70],[-68,76],[-62,82],[-40,83],[-24,80],[-20,73],[-30,68],[-42,61]],
        [[-81,-4],[-79,0],[-77,8],[-72,12],[-62,10],[-60,8],[-52,5],[-50,0],[-44,-2],[-38,-5],[-35,-8],[-39,-13],[-39,-18],[-48,-25],[-53,-34],[-58,-38],[-62,-40],[-65,-45],[-68,-50],[-70,-54],[-75,-52],[-74,-45],[-73,-37],[-71,-30],[-70,-20],[-75,-15],[-81,-6]],
        [[-17,15],[-16,20],[-12,28],[-10,32],[-5,36],[10,37],[20,32],[28,31],[33,28],[35,23],[38,18],[43,12],[51,12],[51,5],[42,-1],[40,-10],[35,-20],[32,-26],[27,-34],[20,-35],[18,-30],[13,-20],[9,-1],[3,6],[-8,4],[-13,9]],
        [[-10,36],[-9,43],[-2,48],[3,51],[6,53],[9,54],[11,58],[16,60],[22,60],[30,60],[28,66],[21,70],[32,71],[46,68],[62,70],[76,73],[92,75],[106,77],[116,74],[132,72],[146,70],[160,70],[170,66],[179,65],[172,60],[162,58],[155,52],[142,48],[135,43],[130,35],[122,32],[120,25],[110,20],[105,10],[100,6],[97,16],[90,22],[82,17],[77,8],[72,20],[66,25],[57,25],[50,30],[45,37],[36,36],[30,41],[26,38],[22,40],[16,38],[13,45],[8,44],[3,42],[-2,37]],
        [[95,5],[105,-6],[115,-9],[125,-9],[135,-5],[141,-3],[141,-9],[131,-8],[120,-10],[110,-8],[100,0]],
        [[113,-22],[114,-35],[118,-35],[129,-32],[137,-35],[141,-38],[147,-39],[151,-37],[153,-28],[145,-15],[142,-11],[136,-12],[130,-11],[125,-14],[118,-20]],
        [[172,-41],[174,-37],[178,-38],[176,-41],[174,-46],[168,-46],[167,-44]],
        [[130,31],[134,34],[139,35],[141,39],[145,44],[142,42],[137,37],[132,34]],
        [[-5,50],[-6,55],[-3,58],[-1,56],[1,53],[1,51],[-4,50]],
        [[43,-12],[50,-15],[50,-25],[45,-25],[43,-17]],
        [[120,18],[124,18],[126,10],[122,6],[119,11]]
    ];
    var REGIONS = [
        { code: 'ap-tokyo-1', zh: '东京', en: 'Tokyo', lat: 35.68, lng: 139.69 },
        { code: 'ap-osaka-1', zh: '大阪', en: 'Osaka', lat: 34.69, lng: 135.50 },
        { code: 'ap-seoul-1', zh: '首尔', en: 'Seoul', lat: 37.57, lng: 126.98 },
        { code: 'ap-singapore-1', zh: '新加坡', en: 'Singapore', lat: 1.35, lng: 103.82 },
        { code: 'ap-mumbai-1', zh: '孟买', en: 'Mumbai', lat: 19.08, lng: 72.88 },
        { code: 'ap-sydney-1', zh: '悉尼', en: 'Sydney', lat: -33.87, lng: 151.21 },
        { code: 'eu-frankfurt-1', zh: '法兰克福', en: 'Frankfurt', lat: 50.11, lng: 8.68 },
        { code: 'eu-amsterdam-1', zh: '阿姆斯特丹', en: 'Amsterdam', lat: 52.37, lng: 4.90 },
        { code: 'uk-london-1', zh: '伦敦', en: 'London', lat: 51.51, lng: -0.13 },
        { code: 'eu-zurich-1', zh: '苏黎世', en: 'Zurich', lat: 47.38, lng: 8.54 },
        { code: 'us-ashburn-1', zh: '阿什本', en: 'Ashburn', lat: 39.04, lng: -77.49 },
        { code: 'us-phoenix-1', zh: '凤凰城', en: 'Phoenix', lat: 33.45, lng: -112.07 },
        { code: 'us-sanjose-1', zh: '圣何塞', en: 'San Jose', lat: 37.34, lng: -121.89 },
        { code: 'ca-toronto-1', zh: '多伦多', en: 'Toronto', lat: 43.65, lng: -79.38 },
        { code: 'sa-saopaulo-1', zh: '圣保罗', en: 'São Paulo', lat: -23.55, lng: -46.63 },
        { code: 'me-jeddah-1', zh: '吉达', en: 'Jeddah', lat: 21.49, lng: 39.19 },
        { code: 'af-johannesburg-1', zh: '约翰内斯堡', en: 'Johannesburg', lat: -26.20, lng: 28.05 }
    ];
    var BOUNDS = LAND.map(function (polygon) {
        return {
            polygon: polygon,
            left: Math.min.apply(null, polygon.map(function (point) { return point[0]; })),
            right: Math.max.apply(null, polygon.map(function (point) { return point[0]; })),
            bottom: Math.min.apply(null, polygon.map(function (point) { return point[1]; })),
            top: Math.max.apply(null, polygon.map(function (point) { return point[1]; }))
        };
    });
    var TOP = 78;
    var BOTTOM = -52;
    var SPAN = TOP - BOTTOM;
    var TAU = Math.PI * 2;
    var current = null;

    function isLand(longitude, latitude) {
        return BOUNDS.some(function (bounds) {
            if (longitude < bounds.left || longitude > bounds.right || latitude < bounds.bottom || latitude > bounds.top) return false;
            var polygon = bounds.polygon;
            var inside = false;
            for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
                var a = polygon[i];
                var b = polygon[j];
                if ((a[1] > latitude) !== (b[1] > latitude) && longitude < (b[0] - a[0]) * (latitude - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
            }
            return inside;
        });
    }

    function createMap(canvas, box, tooltip, count) {
        var context = canvas.getContext('2d');
        var base = document.createElement('canvas');
        var baseContext = base.getContext('2d');
        if (!context || !baseContext) return null;

        var width = 0;
        var height = 0;
        var ratio = 1;
        var animationFrame = 0;
        var layoutFrame = 0;
        var elapsed = 0;
        var lastTime = 0;
        var disposed = false;
        var failed = false;
        var visible = false;
        var inViewport = true;
        var baseDirty = true;
        var hover = null;
        var palette = {};
        var regions = REGIONS.map(function (region, index) {
            return Object.assign({ x: 0, y: 0, phase: index * 173 }, region);
        });
        var routes = [];
        var resizeObserver = null;
        var intersectionObserver = null;
        var themeObserver = null;
        var motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
        var reducedMotion = motionQuery.matches;
        var tooltipName = document.createElement('strong');
        var tooltipCode = document.createElement('span');
        if (tooltip) {
            tooltip.replaceChildren(tooltipName, tooltipCode);
            tooltip.setAttribute('aria-hidden', 'true');
            tooltipName.style.display = 'block';
            tooltipCode.style.display = 'block';
            Object.assign(tooltip.style, { transform: 'none', pointerEvents: 'none', maxWidth: '260px' });
        }
        canvas.setAttribute('aria-hidden', 'true');
        Object.assign(canvas.style, { display: 'block', width: '100%', cursor: 'default' });

        function readPalette() {
            var styles = getComputedStyle(box);
            function color(name, fallback) { return styles.getPropertyValue('--login-map-' + name).trim() || fallback; }
            var next = {
                land: color('land', '#1e3140'), node: color('node', '#2fe0a6'),
                line: color('line', 'rgba(47,224,166,.28)'), text: color('text', '#e8eef4'),
                muted: color('muted', '#7d8f9d'), surface: color('surface', '#111922')
            };
            if (next.land !== palette.land || next.line !== palette.line) baseDirty = true;
            palette = next;
            if (tooltip) {
                tooltip.style.background = palette.surface;
                tooltip.style.color = palette.text;
                tooltipCode.style.color = palette.muted;
            }
        }
        function hideTooltip() {
            if (!tooltip) return;
            tooltip.hidden = true;
            tooltip.style.display = 'none';
            tooltip.style.opacity = '0';
            tooltip.style.visibility = 'hidden';
        }
        function updateTooltip() {
            if (!tooltip || !hover || !visible || document.hidden) { hideTooltip(); return; }
            var chinese = (document.documentElement.lang || 'zh').toLowerCase().indexOf('zh') === 0;
            tooltipName.textContent = chinese ? hover.zh : hover.en;
            tooltipCode.textContent = hover.code;
            tooltip.hidden = false;
            tooltip.style.display = 'block';
            tooltip.style.opacity = '1';
            tooltip.style.visibility = 'visible';
            tooltip.style.maxWidth = Math.max(80, Math.min(260, width - 16)) + 'px';
            var tooltipWidth = tooltip.offsetWidth;
            var tooltipHeight = tooltip.offsetHeight;
            var top = hover.y - tooltipHeight - 12;
            if (top < 6) top = hover.y + 12;
            tooltip.style.left = Math.max(6, Math.min(width - tooltipWidth - 6, hover.x - tooltipWidth / 2)) + 'px';
            tooltip.style.top = Math.max(6, Math.min(height - tooltipHeight - 6, top)) + 'px';
        }
        function stopAnimation() {
            cancelAnimationFrame(animationFrame);
            animationFrame = 0;
            lastTime = 0;
        }
        function buildBase() {
            base.width = Math.max(1, Math.round(width * ratio));
            base.height = Math.max(1, Math.round(height * ratio));
            baseContext.setTransform(ratio, 0, 0, ratio, 0, 0);
            baseContext.clearRect(0, 0, width, height);
            baseContext.fillStyle = palette.land;
            var step = width > 620 ? 5 : 6;
            var radius = Math.max(.7, step * .21);
            baseContext.beginPath();
            for (var y = step / 2; y < height; y += step) {
                var latitude = TOP - y / height * SPAN;
                for (var x = step / 2; x < width; x += step) {
                    if (!isLand(x / width * 360 - 180, latitude)) continue;
                    baseContext.moveTo(x + radius, y);
                    baseContext.arc(x, y, radius, 0, TAU);
                }
            }
            baseContext.fill();
            baseContext.strokeStyle = palette.line;
            baseContext.lineWidth = .85;
            routes.forEach(function (route) {
                baseContext.beginPath();
                baseContext.moveTo(route.a.x, route.a.y);
                baseContext.quadraticCurveTo(route.x, route.y, route.b.x, route.b.y);
                baseContext.stroke();
            });
            baseDirty = false;
        }
        function draw() {
            if (!visible || failed || disposed || document.hidden || !width || !height) return;
            if (baseDirty) buildBase();
            context.setTransform(ratio, 0, 0, ratio, 0, 0);
            context.clearRect(0, 0, width, height);
            context.drawImage(base, 0, 0, width, height);
            if (!reducedMotion) {
                routes.forEach(function (route, index) {
                    var progress = (elapsed / 3200 + index * .17) % 1;
                    var inverse = 1 - progress;
                    var x = inverse * inverse * route.a.x + 2 * inverse * progress * route.x + progress * progress * route.b.x;
                    var y = inverse * inverse * route.a.y + 2 * inverse * progress * route.y + progress * progress * route.b.y;
                    context.save();
                    context.globalAlpha = Math.sin(Math.PI * progress) * .85;
                    context.fillStyle = palette.node;
                    context.shadowColor = palette.node;
                    context.shadowBlur = 5;
                    context.beginPath();
                    context.arc(x, y, 1.55, 0, TAU);
                    context.fill();
                    context.restore();
                });
            }
            regions.forEach(function (region) {
                var on = region === hover;
                if (!reducedMotion) {
                    var progress = ((elapsed + region.phase) % 2400) / 2400;
                    context.strokeStyle = palette.node;
                    context.globalAlpha = (1 - progress) * (on ? .7 : .32);
                    context.lineWidth = 1.1;
                    context.beginPath();
                    context.arc(region.x, region.y, 2.5 + progress * (on ? 15 : 10), 0, TAU);
                    context.stroke();
                    context.globalAlpha = 1;
                }
                var radius = on ? 12 : 8;
                var glow = context.createRadialGradient(region.x, region.y, 0, region.x, region.y, radius);
                glow.addColorStop(0, palette.node);
                glow.addColorStop(1, 'rgba(0,0,0,0)');
                context.globalAlpha = on ? .45 : .26;
                context.fillStyle = glow;
                context.beginPath();
                context.arc(region.x, region.y, radius, 0, TAU);
                context.fill();
                context.globalAlpha = 1;
                context.fillStyle = palette.node;
                context.beginPath();
                context.arc(region.x, region.y, on ? 3.2 : 2.3, 0, TAU);
                context.fill();
            });
        }
        function paint() {
            try { draw(); }
            catch (_) { failed = true; stopAnimation(); hideTooltip(); }
        }
        function tick(now) {
            animationFrame = 0;
            if (disposed || failed || !visible || document.hidden || reducedMotion) return;
            if (lastTime) elapsed += Math.min(50, now - lastTime);
            lastTime = now;
            paint();
            startAnimation();
        }
        function startAnimation() {
            if (!disposed && !failed && visible && !document.hidden && !reducedMotion && !animationFrame) animationFrame = requestAnimationFrame(tick);
        }
        function refresh() {
            layoutFrame = 0;
            if (disposed || failed) return;
            readPalette();
            var boxStyle = getComputedStyle(box);
            var nextWidth = canvas.clientWidth || box.clientWidth;
            var hasLayout = nextWidth > 0 && canvas.getClientRects().length > 0 && boxStyle.visibility !== 'hidden' && boxStyle.visibility !== 'collapse';
            if (!hasLayout) {
                visible = false;
                stopAnimation();
                hideTooltip();
                return;
            }
            var nextHeight = Math.max(1, Math.round(nextWidth * SPAN / 360));
            var nextRatio = Math.min(window.devicePixelRatio || 1, 2);
            if (nextWidth !== width || nextHeight !== height || nextRatio !== ratio) {
                width = nextWidth;
                height = nextHeight;
                ratio = nextRatio;
                canvas.width = Math.max(1, Math.round(width * ratio));
                canvas.height = Math.max(1, Math.round(height * ratio));
                canvas.style.height = height + 'px';
                regions.forEach(function (region) {
                    region.x = (region.lng + 180) / 360 * width;
                    region.y = (TOP - region.lat) / SPAN * height;
                });
                routes = regions.slice(1).map(function (region, index) {
                    var previous = regions[index];
                    var dx = region.x - previous.x;
                    var dy = region.y - previous.y;
                    return { a: previous, b: region, x: (previous.x + region.x) / 2 - dy * .22, y: (previous.y + region.y) / 2 + dx * .22 };
                });
                baseDirty = true;
                if (count) count.textContent = String(regions.filter(function (region) { return region.x >= 0 && region.x <= width && region.y >= 0 && region.y <= height; }).length);
            }
            var rect = canvas.getBoundingClientRect();
            var onscreen = rect.bottom > 0 && rect.top < window.innerHeight && rect.right > 0 && rect.left < window.innerWidth;
            visible = !document.hidden && onscreen && (!intersectionObserver || inViewport);
            if (!visible) { stopAnimation(); hideTooltip(); return; }
            if (reducedMotion) stopAnimation();
            paint();
            updateTooltip();
            startAnimation();
        }
        function requestRefresh() {
            if (disposed) return;
            if (document.hidden) { stopAnimation(); hideTooltip(); return; }
            if (!layoutFrame) layoutFrame = requestAnimationFrame(refresh);
        }
        function onMove(event) {
            if (!visible || disposed || failed || event.pointerType === 'touch') return;
            var rect = canvas.getBoundingClientRect();
            if (!rect.width || !rect.height) return;
            var x = (event.clientX - rect.left) * width / rect.width;
            var y = (event.clientY - rect.top) * height / rect.height;
            var closest = null;
            var distance = 14 * 14;
            regions.forEach(function (region) {
                var candidate = Math.pow(region.x - x, 2) + Math.pow(region.y - y, 2);
                if (candidate < distance) { closest = region; distance = candidate; }
            });
            if (hover === closest) return;
            hover = closest;
            updateTooltip();
            if (reducedMotion) paint();
        }
        function onLeave() {
            hover = null;
            hideTooltip();
            if (reducedMotion) paint();
        }
        function onVisibility() {
            if (document.hidden) {
                stopAnimation();
                cancelAnimationFrame(layoutFrame);
                layoutFrame = 0;
                hideTooltip();
            } else requestRefresh();
        }
        function onMotionChange() { reducedMotion = motionQuery.matches; requestRefresh(); }
        function onContextLost(event) { event.preventDefault(); failed = true; stopAnimation(); hideTooltip(); }
        function onContextRestored() { failed = false; baseDirty = true; requestRefresh(); }

        canvas.addEventListener('pointermove', onMove, { passive: true });
        canvas.addEventListener('pointerleave', onLeave, { passive: true });
        canvas.addEventListener('contextlost', onContextLost);
        canvas.addEventListener('contextrestored', onContextRestored);
        window.addEventListener('resize', requestRefresh, { passive: true });
        document.addEventListener('visibilitychange', onVisibility);
        if (motionQuery.addEventListener) motionQuery.addEventListener('change', onMotionChange);
        else motionQuery.addListener(onMotionChange);
        if (window.ResizeObserver) {
            resizeObserver = new ResizeObserver(requestRefresh);
            resizeObserver.observe(box);
        }
        if (window.IntersectionObserver) {
            intersectionObserver = new IntersectionObserver(function (entries) {
                if (disposed) return;
                inViewport = entries.some(function (entry) { return entry.isIntersecting; });
                if (!inViewport) { visible = false; stopAnimation(); hideTooltip(); }
                else requestRefresh();
            });
            intersectionObserver.observe(canvas);
        } else window.addEventListener('scroll', requestRefresh, { passive: true, capture: true });
        if (window.MutationObserver) {
            themeObserver = new MutationObserver(requestRefresh);
            themeObserver.observe(document.documentElement, { attributes: true, attributeFilter: ['data-theme', 'class', 'style', 'lang'] });
            if (document.body) themeObserver.observe(document.body, { attributes: true, attributeFilter: ['data-theme', 'class', 'style'] });
        }
        hideTooltip();
        refresh();

        return {
            dispose: function () {
                if (disposed) return;
                disposed = true;
                stopAnimation();
                cancelAnimationFrame(layoutFrame);
                layoutFrame = 0;
                if (resizeObserver) resizeObserver.disconnect();
                if (intersectionObserver) intersectionObserver.disconnect();
                if (themeObserver) themeObserver.disconnect();
                if (motionQuery.removeEventListener) motionQuery.removeEventListener('change', onMotionChange);
                else motionQuery.removeListener(onMotionChange);
                canvas.removeEventListener('pointermove', onMove);
                canvas.removeEventListener('pointerleave', onLeave);
                canvas.removeEventListener('contextlost', onContextLost);
                canvas.removeEventListener('contextrestored', onContextRestored);
                window.removeEventListener('resize', requestRefresh);
                window.removeEventListener('scroll', requestRefresh, true);
                document.removeEventListener('visibilitychange', onVisibility);
                hideTooltip();
                context.clearRect(0, 0, canvas.width, canvas.height);
                canvas.width = base.width = 1;
                canvas.height = base.height = 1;
                regions = [];
                routes = [];
                hover = null;
            }
        };
    }

    function mount() {
        if (current) return;
        var canvas = document.getElementById('loginRegionMap');
        var box = canvas && canvas.closest('.login-mapbox');
        if (!canvas || !box) return;
        current = createMap(canvas, box, document.getElementById('loginMapTooltip'), document.getElementById('loginMapRegionCount'));
    }
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', mount, { once: true });
    else mount();
    window.addEventListener('pagehide', function () {
        if (current) current.dispose();
        current = null;
    });
    window.addEventListener('pageshow', function (event) { if (event.persisted) mount(); });
})();
