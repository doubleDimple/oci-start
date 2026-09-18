import directory from './regions'

export function mountLoginMap(root) {

    // Coordinates and scope come from the separately sourced public-region directory.
    // Curves are decorative, not account data, network topology or live traffic.
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
    var REGIONS = directory && Array.isArray(directory.regions) ? directory.regions : [];
    var ids = new Set();
    // Never silently drop malformed entries and then label the rest a full directory.
    var validDirectory = REGIONS.length > 0 && REGIONS.every(function (region) {
        if (!region || typeof region.code !== 'string' || !/^[a-z0-9-]+$/.test(region.code) || ids.has(region.code)) return false;
        ids.add(region.code);
        return typeof region.zh === 'string' && typeof region.en === 'string'
            && Number.isFinite(region.lat) && Math.abs(region.lat) <= 90
            && Number.isFinite(region.lng) && Math.abs(region.lng) <= 180;
    });
    if (!validDirectory) REGIONS = [];
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

    function coordinates(region) {
        return Math.abs(region.lat).toFixed(4) + '° ' + (region.lat < 0 ? 'S' : 'N')
            + ' · ' + Math.abs(region.lng).toFixed(4) + '° ' + (region.lng < 0 ? 'W' : 'E');
    }

    function createMap(canvas, box, tooltip, count, list, unavailable) {
        var base = document.createElement('canvas');
        var context = null;
        var baseContext = null;
        try {
            context = canvas.getContext('2d');
            baseContext = base.getContext('2d');
        } catch (_) {
            // Keep the sourced directory usable even when canvas is unavailable.
        }

        var width = 0;
        var height = 0;
        var ratio = 1;
        var animationFrame = 0;
        var layoutFrame = 0;
        var elapsed = 0;
        var lastTime = 0;
        var disposed = false;
        var failed = !context || !baseContext;
        var visible = false;
        var inViewport = true;
        var baseDirty = true;
        var hover = null;
        var selected = null;
        var directoryLocale = '';
        var palette = {};
        var regions = REGIONS.map(function (region, index) {
            return Object.assign({ x: 0, y: 0, phase: index * 173 }, region);
        });
        var locations = regions.filter(function (region, index) {
            return regions.findIndex(function (candidate) { return candidate.lat === region.lat && candidate.lng === region.lng; }) === index;
        });
        var routes = [];
        var resizeObserver = null;
        var intersectionObserver = null;
        var themeObserver = null;
        var motionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
        var reducedMotion = motionQuery.matches;
        var tooltipName = document.createElement('strong');
        var tooltipCode = document.createElement('span');
        var tooltipCoordinates = document.createElement('span');
        if (tooltip) {
            tooltip.replaceChildren(tooltipName, tooltipCode, tooltipCoordinates);
            tooltip.setAttribute('aria-hidden', 'true');
            tooltipName.style.display = 'block';
            tooltipCode.style.display = 'block';
            Object.assign(tooltip.style, { transform: 'none', pointerEvents: 'none', maxWidth: '260px' });
        }
        Object.assign(canvas.style, { display: failed ? 'none' : 'block', width: '100%', cursor: 'default' });
        if (count) count.textContent = regions.length ? String(regions.length) : '—';
        if (unavailable) unavailable.hidden = regions.length > 0;
        var checkedAt = root.querySelector('#' + 'loginMapCheckedAt');
        if (checkedAt && validDirectory && /^\d{4}-\d{2}-\d{2}$/.test(directory.checkedAt)) {
            checkedAt.dateTime = directory.checkedAt;
            checkedAt.textContent = directory.checkedAt;
        }

        function isChinese() { return (document.documentElement.lang || 'zh').toLowerCase().indexOf('zh') === 0; }
        function activeRegion() { return hover || selected; }
        function renderDirectory() {
            var language = isChinese() ? 'zh' : 'en';
            if (!list || directoryLocale === language) return;
            directoryLocale = language;
            var fragment = document.createDocumentFragment();
            regions.forEach(function (region) {
                var item = document.createElement('li');
                var button = document.createElement('button');
                button.type = 'button';
                button.className = 'login-region-button';
                button.dataset.regionCode = region.code;
                button.setAttribute('aria-pressed', region === selected ? 'true' : 'false');
                var name = document.createElement('span');
                name.className = 'login-region-name';
                name.textContent = region[language];
                var code = document.createElement('span');
                code.className = 'login-region-code';
                code.textContent = region.code;
                var location = document.createElement('span');
                location.className = 'login-region-coordinates';
                location.textContent = coordinates(region);
                button.append(name, code, location);
                item.appendChild(button);
                fragment.appendChild(item);
            });
            list.replaceChildren(fragment);
        }
        function selectRegion(region) {
            selected = region;
            if (list) list.querySelectorAll('button[data-region-code]').forEach(function (button) {
                button.setAttribute('aria-pressed', region && button.dataset.regionCode === region.code ? 'true' : 'false');
            });
            updateTooltip();
            if (reducedMotion) paint();
        }
        function onDirectorySelect(event) {
            var button = event.target instanceof Element && event.target.closest('button[data-region-code]');
            if (!button || !list || !list.contains(button)) return;
            hover = null;
            selectRegion(regions.find(function (region) { return region.code === button.dataset.regionCode; }) || null);
        }

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
                tooltipCoordinates.style.color = palette.muted;
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
            var region = activeRegion();
            if (!tooltip || !region || !visible || document.hidden) { hideTooltip(); return; }
            var colocated = regions.filter(function (candidate) { return candidate.lat === region.lat && candidate.lng === region.lng; });
            tooltipName.textContent = isChinese() ? region.zh : region.en;
            tooltipCode.textContent = colocated.map(function (candidate) { return candidate.code; }).join('\n');
            tooltipCoordinates.textContent = coordinates(region);
            tooltip.hidden = false;
            tooltip.style.display = 'block';
            tooltip.style.opacity = '1';
            tooltip.style.visibility = 'visible';
            tooltip.style.maxWidth = Math.max(80, Math.min(260, width - 16)) + 'px';
            var tooltipWidth = tooltip.offsetWidth;
            var tooltipHeight = tooltip.offsetHeight;
            var top = region.y - tooltipHeight - 12;
            if (top < 6) top = region.y + 12;
            tooltip.style.left = Math.max(6, Math.min(width - tooltipWidth - 6, region.x - tooltipWidth / 2)) + 'px';
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
            locations.forEach(function (region) {
                var active = activeRegion();
                var on = active && region.lat === active.lat && region.lng === active.lng;
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
            if (disposed) return;
            renderDirectory();
            if (failed) return;
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
                // A bounded set of decorative routes avoids drawing a dense graph as the directory grows.
                var routeCodes = ['us-phoenix-1', 'us-ashburn-1', 'uk-london-1', 'eu-frankfurt-1', 'me-jeddah-1', 'ap-mumbai-1', 'ap-singapore-1', 'ap-tokyo-1', 'ap-sydney-1'];
                var routeRegions = routeCodes.map(function (code) { return regions.find(function (region) { return region.code === code; }); }).filter(Boolean);
                routes = routeRegions.slice(1).map(function (region, index) {
                    var previous = routeRegions[index];
                    var dx = region.x - previous.x;
                    var dy = region.y - previous.y;
                    return { a: previous, b: region, x: (previous.x + region.x) / 2 - dy * .22, y: (previous.y + region.y) / 2 + dx * .22 };
                });
                baseDirty = true;
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
        function nearestRegion(event) {
            var rect = canvas.getBoundingClientRect();
            if (!rect.width || !rect.height) return null;
            var x = (event.clientX - rect.left) * width / rect.width;
            var y = (event.clientY - rect.top) * height / rect.height;
            var closest = null;
            var distance = 14 * 14;
            locations.forEach(function (region) {
                var candidate = Math.pow(region.x - x, 2) + Math.pow(region.y - y, 2);
                if (candidate < distance) { closest = region; distance = candidate; }
            });
            return closest;
        }
        function onMove(event) {
            if (!visible || disposed || failed || event.pointerType === 'touch') return;
            var closest = nearestRegion(event);
            if (hover === closest) return;
            hover = closest;
            updateTooltip();
            if (reducedMotion) paint();
        }
        function onMapClick(event) {
            if (!visible || disposed || failed) return;
            hover = null;
            selectRegion(nearestRegion(event));
        }
        function onLeave() {
            hover = null;
            updateTooltip();
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
        function onContextRestored() { failed = !context || !baseContext; baseDirty = true; requestRefresh(); }

        canvas.addEventListener('pointermove', onMove, { passive: true });
        canvas.addEventListener('pointerleave', onLeave, { passive: true });
        canvas.addEventListener('click', onMapClick);
        if (list) {
            list.addEventListener('click', onDirectorySelect);
            list.addEventListener('focusin', onDirectorySelect);
        }
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
                canvas.removeEventListener('click', onMapClick);
                if (list) {
                    list.removeEventListener('click', onDirectorySelect);
                    list.removeEventListener('focusin', onDirectorySelect);
                    list.replaceChildren();
                }
                canvas.removeEventListener('contextlost', onContextLost);
                canvas.removeEventListener('contextrestored', onContextRestored);
                window.removeEventListener('resize', requestRefresh);
                window.removeEventListener('scroll', requestRefresh, true);
                document.removeEventListener('visibilitychange', onVisibility);
                hideTooltip();
                if (context) context.clearRect(0, 0, canvas.width, canvas.height);
                canvas.width = base.width = 1;
                canvas.height = base.height = 1;
                regions = [];
                locations = [];
                routes = [];
                hover = null;
                selected = null;
            }
        };
    }

    function mount() {
        if (current) return;
        var canvas = root.querySelector('#' + 'loginRegionMap');
        var box = canvas && canvas.closest('.login-mapbox');
        if (!canvas || !box) return;
        current = createMap(canvas, box, root.querySelector('#' + 'loginMapTooltip'), root.querySelector('#' + 'loginMapRegionCount'), root.querySelector('#' + 'loginRegionList'), root.querySelector('#' + 'loginMapUnavailable'));
    }
    mount();
    return () => { if (current) current.dispose(); current = null; };
}
