import directory from './regions'

export function mountLoginMap(root) {

    // Coordinates and scope come from the separately sourced public-region directory.
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

    var RAD = Math.PI / 180;
    var TAU = Math.PI * 2;
    var AXIAL_TILT = -0.409; // Real Earth axial tilt (~23.44° tilt to the right)
    var current = null;

    function getLandContinentIndex(longitude, latitude) {
        for (var k = 0; k < BOUNDS.length; k++) {
            var bounds = BOUNDS[k];
            if (longitude >= bounds.left && longitude <= bounds.right && latitude >= bounds.bottom && latitude <= bounds.top) {
                var polygon = bounds.polygon;
                var inside = false;
                for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
                    var a = polygon[i];
                    var b = polygon[j];
                    if ((a[1] > latitude) !== (b[1] > latitude) && longitude < (b[0] - a[0]) * (latitude - a[1]) / (b[1] - a[1]) + a[0]) inside = !inside;
                }
                if (inside) return k;
            }
        }
        return -1;
    }

    function coordinates(region) {
        return Math.abs(region.lat).toFixed(4) + '° ' + (region.lat < 0 ? 'S' : 'N')
            + ' · ' + Math.abs(region.lng).toFixed(4) + '° ' + (region.lng < 0 ? 'W' : 'E');
    }

    function hexToRgba(hex, alpha) {
        if (!hex) return 'rgba(47,224,166,' + alpha + ')';
        hex = hex.trim();
        if (hex.startsWith('rgba') || hex.startsWith('rgb')) return hex;
        if (hex.startsWith('#')) {
            var c = hex.substring(1);
            if (c.length === 3) c = c[0] + c[0] + c[1] + c[1] + c[2] + c[2];
            if (c.length === 6) {
                var r = parseInt(c.substring(0, 2), 16);
                var g = parseInt(c.substring(2, 4), 16);
                var b = parseInt(c.substring(4, 6), 16);
                return 'rgba(' + r + ',' + g + ',' + b + ',' + alpha + ')';
            }
        }
        return hex;
    }

    function buildLandDots() {
        var dots = [];
        for (var lat = -72; lat <= 76; lat += 2.4) {
            var phi = lat * RAD;
            var cosPhi = Math.cos(phi);
            if (cosPhi < 0.05) continue;
            var lngStep = 2.4 / cosPhi;
            for (var lng = -180; lng < 180; lng += lngStep) {
                var cIdx = getLandContinentIndex(lng, lat);
                if (cIdx >= 0) {
                    var lam = lng * RAD;
                    dots.push({
                        vx: cosPhi * Math.sin(lam),
                        vy: Math.sin(phi),
                        vz: cosPhi * Math.cos(lam),
                        continent: cIdx
                    });
                }
            }
        }
        LAND.forEach(function (polygon, k) {
            polygon.forEach(function (pt) {
                var lng = pt[0], lat = pt[1];
                var phi = lat * RAD, lam = lng * RAD;
                var cosPhi = Math.cos(phi);
                dots.push({
                    vx: cosPhi * Math.sin(lam),
                    vy: Math.sin(phi),
                    vz: cosPhi * Math.cos(lam),
                    continent: k
                });
            });
        });
        return dots;
    }

    function buildGraticules() {
        var lines = [];
        [-60, -30, 0, 30, 60].forEach(function (lat) {
            var line = [];
            var phi = lat * RAD;
            var cosPhi = Math.cos(phi);
            var sinPhi = Math.sin(phi);
            for (var lng = -180; lng <= 180; lng += 8) {
                var lam = lng * RAD;
                line.push({
                    vx: cosPhi * Math.sin(lam),
                    vy: sinPhi,
                    vz: cosPhi * Math.cos(lam)
                });
            }
            lines.push(line);
        });
        for (var lng = -180; lng < 180; lng += 30) {
            var line = [];
            var lam = lng * RAD;
            var sinLam = Math.sin(lam);
            var cosLam = Math.cos(lam);
            for (var lat = -80; lat <= 80; lat += 8) {
                var phi = lat * RAD;
                var cosPhi = Math.cos(phi);
                line.push({
                    vx: cosPhi * sinLam,
                    vy: Math.sin(phi),
                    vz: cosPhi * cosLam
                });
            }
            lines.push(line);
        }
        return lines;
    }

    var landDots = buildLandDots();
    var graticules = buildGraticules();

    function createGlobe(canvas, box, tooltip, count, list, unavailable) {
        var context = null;
        try { context = canvas.getContext('2d'); } catch (_) {}

        var width = 0;
        var height = 0;
        var radius = 0;
        var cx = 0;
        var cy = 0;
        var ratio = 1;
        var animationFrame = 0;
        var layoutFrame = 0;
        var elapsed = 0;
        var lastTime = 0;
        var disposed = false;
        var failed = !context;
        var visible = false;
        var inViewport = true;
        var hover = null;
        var selected = null;
        var directoryLocale = '';
        var palette = {};

        // 3D rotation state (Earth spin & camera pitch angle)
        var rotY = 0.3;  // Polar spin angle
        var rotX = 0.28; // View pitch tilt (~16 deg)
        var velY = 0;
        var velX = 0;
        var targetRotY = null;
        var targetRotX = null;

        // Pointer drag interaction
        var isPointerDown = false;
        var dragMoved = false;
        var startX = 0, startY = 0;
        var startRotY = 0, startRotX = 0;
        var lastPointerX = 0, lastPointerY = 0;

        var regions = REGIONS.map(function (region, index) {
            var phi = region.lat * RAD;
            var lam = region.lng * RAD;
            var cosPhi = Math.cos(phi);
            return Object.assign({
                vx: cosPhi * Math.sin(lam),
                vy: Math.sin(phi),
                vz: cosPhi * Math.cos(lam),
                screenX: 0, screenY: 0, visible: false, z2: 0,
                phase: index * 173
            }, region);
        });

        var locations = regions.filter(function (region, index) {
            return regions.findIndex(function (c) { return c.lat === region.lat && c.lng === region.lng; }) === index;
        });

        var routeCodes = ['us-phoenix-1', 'us-ashburn-1', 'uk-london-1', 'eu-frankfurt-1', 'me-jeddah-1', 'ap-mumbai-1', 'ap-singapore-1', 'ap-tokyo-1', 'ap-sydney-1'];
        var routeRegions = routeCodes.map(function (code) { return regions.find(function (r) { return r.code === code; }); }).filter(Boolean);
        var routes = [];
        for (var i = 0; i < routeRegions.length - 1; i++) {
            var rA = routeRegions[i];
            var rB = routeRegions[i + 1];
            var samples = [];
            var numSamples = 24;
            var dotVal = Math.max(-1, Math.min(1, rA.vx * rB.vx + rA.vy * rB.vy + rA.vz * rB.vz));
            var omega = Math.acos(dotVal);
            var sinOmega = Math.sin(omega);
            for (var s = 0; s <= numSamples; s++) {
                var t = s / numSamples;
                var scaleA = sinOmega > 0.001 ? Math.sin((1 - t) * omega) / sinOmega : (1 - t);
                var scaleB = sinOmega > 0.001 ? Math.sin(t * omega) / sinOmega : t;
                var vx = rA.vx * scaleA + rB.vx * scaleB;
                var vy = rA.vy * scaleA + rB.vy * scaleB;
                var vz = rA.vz * scaleA + rB.vz * scaleB;
                var h = 1 + 0.18 * Math.sin(Math.PI * t);
                samples.push({ vx: vx * h, vy: vy * h, vz: vz * h });
            }
            routes.push({ a: rA, b: rB, samples: samples });
        }

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

        Object.assign(canvas.style, { display: failed ? 'none' : 'block', width: '100%', cursor: 'grab', touchAction: 'none' });
        if (count) count.textContent = regions.length ? String(regions.length) : '—';
        if (unavailable) unavailable.hidden = regions.length > 0;
        var checkedAt = root.querySelector('#loginMapCheckedAt');
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
                var loc = document.createElement('span');
                loc.className = 'login-region-coordinates';
                loc.textContent = coordinates(region);
                button.append(name, code, loc);
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
            if (region) {
                targetRotY = -region.lng * RAD;
                targetRotX = region.lat * RAD * 0.5;
            }
            updateTooltip();
            if (reducedMotion) paint();
        }

        function onDirectorySelect(event) {
            var button = event.target instanceof Element && event.target.closest('button[data-region-code]');
            if (!button || !list || !list.contains(button)) return;
            hover = null;
            selectRegion(regions.find(function (r) { return r.code === button.dataset.regionCode; }) || null);
        }

        function readPalette() {
            var styles = getComputedStyle(box);
            function color(name, fallback) { return styles.getPropertyValue('--login-map-' + name).trim() || fallback; }
            var continents = [];
            for (var c = 0; c < 12; c++) {
                continents.push(color('c' + c, ''));
            }
            palette = {
                land: color('land', '#1e3140'), node: color('node', '#2fe0a6'),
                line: color('line', 'rgba(47,224,166,.28)'), text: color('text', '#e8eef4'),
                muted: color('muted', '#7d8f9d'), surface: color('surface', '#111922'),
                ocean: color('ocean', color('surface', '#111922')),
                oceanEdge: color('ocean-edge', ''),
                graticule: color('graticule', ''),
                continents: continents
            };
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
            if (!tooltip || !region || !region.visible || !visible || document.hidden) { hideTooltip(); return; }
            var colocated = regions.filter(function (c) { return c.lat === region.lat && c.lng === region.lng; });
            tooltipName.textContent = isChinese() ? region.zh : region.en;
            tooltipCode.textContent = colocated.map(function (c) { return c.code; }).join('\n');
            tooltipCoordinates.textContent = coordinates(region);
            tooltip.hidden = false;
            tooltip.style.display = 'block';
            tooltip.style.opacity = '1';
            tooltip.style.visibility = 'visible';
            tooltip.style.maxWidth = Math.max(80, Math.min(260, width - 16)) + 'px';
            var tooltipWidth = tooltip.offsetWidth;
            var tooltipHeight = tooltip.offsetHeight;
            var top = region.screenY - tooltipHeight - 12;
            if (top < 6) top = region.screenY + 12;
            tooltip.style.left = Math.max(6, Math.min(width - tooltipWidth - 6, region.screenX - tooltipWidth / 2)) + 'px';
            tooltip.style.top = Math.max(6, Math.min(height - tooltipHeight - 6, top)) + 'px';
        }

        function stopAnimation() {
            cancelAnimationFrame(animationFrame);
            animationFrame = 0;
            lastTime = 0;
        }

        function drawGlobe() {
            if (!visible || failed || disposed || document.hidden || !width || !height) return;
            context.setTransform(ratio, 0, 0, ratio, 0, 0);
            context.clearRect(0, 0, width, height);

            // Precalculate 3D Transformation matrices with 23.44° Axial Tilt
            var cosSpin = Math.cos(rotY), sinSpin = Math.sin(rotY);
            var cosTilt = Math.cos(AXIAL_TILT), sinTilt = Math.sin(AXIAL_TILT);
            var cosPitch = Math.cos(rotX), sinPitch = Math.sin(rotX);

            function project(vx, vy, vz) {
                // 1. Spin around Earth's polar Y axis
                var x1 = vx * cosSpin + vz * sinSpin;
                var y1 = vy;
                var z1 = -vx * sinSpin + vz * cosSpin;

                // 2. Apply Earth's 23.44° axial tilt around Z axis
                var x2 = x1 * cosTilt - y1 * sinTilt;
                var y2 = x1 * sinTilt + y1 * cosTilt;
                var z2 = z1;

                // 3. Apply view pitch tilt around X axis
                var x3 = x2;
                var y3 = y2 * cosPitch - z2 * sinPitch;
                var z3 = y2 * sinPitch + z2 * cosPitch;

                return {
                    sx: cx + x3 * radius,
                    sy: cy - y3 * radius,
                    z: z3
                };
            }

            // 1. Atmosphere Outer Glow
            var glowGrad = context.createRadialGradient(cx, cy, radius * 0.85, cx, cy, radius * 1.22);
            glowGrad.addColorStop(0, hexToRgba(palette.node, 0.14));
            glowGrad.addColorStop(0.7, hexToRgba(palette.node, 0.04));
            glowGrad.addColorStop(1, 'rgba(0,0,0,0)');
            context.fillStyle = glowGrad;
            context.beginPath();
            context.arc(cx, cy, radius * 1.22, 0, TAU);
            context.fill();

            // 2. 3D Globe Surface Fill
            var bodyGrad = context.createRadialGradient(
                cx - radius * 0.3, cy - radius * 0.3, radius * 0.1,
                cx, cy, radius
            );
            bodyGrad.addColorStop(0, palette.ocean);
            bodyGrad.addColorStop(0.65, palette.ocean);
            bodyGrad.addColorStop(1, palette.oceanEdge || hexToRgba(palette.land, 0.45));

            context.fillStyle = bodyGrad;
            context.beginPath();
            context.arc(cx, cy, radius, 0, TAU);
            context.fill();

            // Globe Atmosphere Rim Border
            context.strokeStyle = hexToRgba(palette.node, 0.35);
            context.lineWidth = 1.2;
            context.beginPath();
            context.arc(cx, cy, radius, 0, TAU);
            context.stroke();

            // Tilted Polar Axis Line (North - South Pole Axis)
            var poleNorth = project(0, 1.13, 0);
            var poleSouth = project(0, -1.13, 0);
            context.strokeStyle = hexToRgba(palette.node, 0.3);
            context.lineWidth = 1.0;
            context.setLineDash([4, 4]);
            context.beginPath();
            context.moveTo(poleNorth.sx, poleNorth.sy);
            context.lineTo(poleSouth.sx, poleSouth.sy);
            context.stroke();
            context.setLineDash([]);

            // 3. Graticule Lines (Parallels & Meridians)
            context.strokeStyle = palette.graticule || hexToRgba(palette.land, 0.2);
            context.lineWidth = 0.95;
            graticules.forEach(function (line) {
                context.beginPath();
                var drawing = false;
                line.forEach(function (pt) {
                    var p = project(pt.vx, pt.vy, pt.vz);
                    if (p.z > 0.02) {
                        if (!drawing) { context.moveTo(p.sx, p.sy); drawing = true; }
                        else { context.lineTo(p.sx, p.sy); }
                    } else { drawing = false; }
                });
                context.stroke();
            });

            // 4. Land Dots (Multi-Color Continents)
            var baseDotR = Math.max(0.9, radius * 0.009);
            for (var c = 0; c < 12; c++) {
                var cColor = palette.continents && palette.continents[c] ? palette.continents[c] : palette.land;
                context.fillStyle = cColor;
                context.beginPath();
                landDots.forEach(function (dot) {
                    if (dot.continent !== c) return;
                    var p = project(dot.vx, dot.vy, dot.vz);
                    if (p.z > 0.02) {
                        var r = baseDotR * (0.65 + p.z * 0.45);
                        context.moveTo(p.sx + r, p.sy);
                        context.arc(p.sx, p.sy, r, 0, TAU);
                    }
                });
                context.fill();
            }

            // 5. 3D Decorative Great-Circle Network Arcs
            routes.forEach(function (route, rIdx) {
                context.strokeStyle = palette.line;
                context.lineWidth = 1.0;
                context.beginPath();
                var drawing = false;
                route.samples.forEach(function (pt) {
                    var p = project(pt.vx, pt.vy, pt.vz);
                    if (p.z > 0.02) {
                        if (!drawing) { context.moveTo(p.sx, p.sy); drawing = true; }
                        else { context.lineTo(p.sx, p.sy); }
                    } else { drawing = false; }
                });
                context.stroke();

                // Traveling Light Particle along Arc
                if (!reducedMotion && route.samples.length) {
                    var progress = (elapsed / 3000 + rIdx * 0.22) % 1;
                    var sampleIdx = Math.floor(progress * (route.samples.length - 1));
                    var pt = route.samples[sampleIdx];
                    if (pt) {
                        var p = project(pt.vx, pt.vy, pt.vz);
                        if (p.z > 0.05) {
                            context.save();
                            context.globalAlpha = Math.sin(Math.PI * progress) * Math.min(1, p.z * 2);
                            context.fillStyle = palette.node;
                            context.shadowColor = palette.node;
                            context.shadowBlur = 8;
                            context.beginPath();
                            context.arc(p.sx, p.sy, 2.5, 0, TAU);
                            context.fill();
                            context.restore();
                        }
                    }
                }
            });

            // 6. Project & Render OCI Region Nodes
            locations.forEach(function (region) {
                var p = project(region.vx, region.vy, region.vz);

                region.z2 = p.z;
                region.screenX = p.sx;
                region.screenY = p.sy;
                region.visible = (p.z > 0.05);

                if (!region.visible) return;

                var active = activeRegion();
                var on = active && region.lat === active.lat && region.lng === active.lng;
                var depthAlpha = Math.min(1, p.z * 2.2);

                // Pulsing outer ring
                if (!reducedMotion) {
                    var progress = ((elapsed + region.phase) % 2400) / 2400;
                    context.strokeStyle = palette.node;
                    context.globalAlpha = (1 - progress) * (on ? 0.85 : 0.4) * depthAlpha;
                    context.lineWidth = 1.3;
                    context.beginPath();
                    context.arc(region.screenX, region.screenY, 4 + progress * (on ? 18 : 12), 0, TAU);
                    context.stroke();
                    context.globalAlpha = 1;
                }

                // Glowing Halo
                var glowR = on ? 18 : 12;
                var halo = context.createRadialGradient(region.screenX, region.screenY, 0, region.screenX, region.screenY, glowR);
                halo.addColorStop(0, palette.node);
                halo.addColorStop(1, 'rgba(0,0,0,0)');
                context.globalAlpha = (on ? 0.6 : 0.32) * depthAlpha;
                context.fillStyle = halo;
                context.beginPath();
                context.arc(region.screenX, region.screenY, glowR, 0, TAU);
                context.fill();
                context.globalAlpha = 1;

                // Core Dot & Bright White Beacon Center (Enlarged)
                context.fillStyle = palette.node;
                context.globalAlpha = depthAlpha;
                context.beginPath();
                context.arc(region.screenX, region.screenY, on ? 5.2 : 3.8, 0, TAU);
                context.fill();

                context.fillStyle = '#ffffff';
                context.beginPath();
                context.arc(region.screenX, region.screenY, on ? 2.5 : 1.8, 0, TAU);
                context.fill();
                context.globalAlpha = 1;
            });
        }

        function paint() {
            try { drawGlobe(); }
            catch (_) { failed = true; stopAnimation(); hideTooltip(); }
        }

        function tick(nowTime) {
            animationFrame = 0;
            if (disposed || failed || !visible || document.hidden) return;
            if (lastTime) elapsed += Math.min(50, nowTime - lastTime);
            lastTime = nowTime;

            // Handle Target Rotation Interpolation (when region clicked in list)
            if (targetRotY !== null && targetRotX !== null) {
                var diffY = Math.atan2(Math.sin(targetRotY - rotY), Math.cos(targetRotY - rotY));
                var diffX = targetRotX - rotX;
                rotY += diffY * 0.08;
                rotX += diffX * 0.08;
                if (Math.abs(diffY) < 0.001 && Math.abs(diffX) < 0.001) {
                    rotY = targetRotY;
                    rotX = targetRotX;
                    targetRotY = null;
                    targetRotX = null;
                }
            } else if (!isPointerDown && !reducedMotion) {
                // Auto spin & inertia momentum
                rotY += 0.0025 + velY;
                rotX += velX;
                velY *= 0.94;
                velX *= 0.94;
                rotX = Math.max(-0.8, Math.min(0.8, rotX));
            }

            paint();
            updateTooltip();
            startAnimation();
        }

        function startAnimation() {
            if (!disposed && !failed && visible && !document.hidden && !animationFrame) {
                animationFrame = requestAnimationFrame(tick);
            }
        }

        function refresh() {
            layoutFrame = 0;
            if (disposed) return;
            renderDirectory();
            if (failed) return;
            readPalette();

            var nextWidth = canvas.clientWidth || box.clientWidth || 400;
            var nextHeight = Math.max(240, Math.round(nextWidth * 0.72));
            var nextRatio = Math.min(window.devicePixelRatio || 1, 2);

            if (nextWidth !== width || nextHeight !== height || nextRatio !== ratio) {
                width = nextWidth;
                height = nextHeight;
                ratio = nextRatio;
                radius = Math.min(width, height) * 0.40;
                cx = width / 2;
                cy = height / 2;
                canvas.width = Math.max(1, Math.round(width * ratio));
                canvas.height = Math.max(1, Math.round(height * ratio));
                canvas.style.height = height + 'px';
            }

            var rect = canvas.getBoundingClientRect();
            var onscreen = rect.bottom > 0 && rect.top < window.innerHeight && rect.right > 0 && rect.left < window.innerWidth;
            visible = !document.hidden && onscreen && (!intersectionObserver || inViewport);
            if (!visible) { stopAnimation(); hideTooltip(); return; }

            paint();
            updateTooltip();
            startAnimation();
        }

        function requestRefresh() {
            if (disposed) return;
            if (document.hidden) { stopAnimation(); hideTooltip(); return; }
            if (!layoutFrame) layoutFrame = requestAnimationFrame(refresh);
        }

        function nearestRegion(clientX, clientY) {
            var rect = canvas.getBoundingClientRect();
            if (!rect.width || !rect.height) return null;
            var x = (clientX - rect.left) * width / rect.width;
            var y = (clientY - rect.top) * height / rect.height;
            var closest = null;
            var distance = 16 * 16;
            locations.forEach(function (region) {
                if (!region.visible) return;
                var d = Math.pow(region.screenX - x, 2) + Math.pow(region.screenY - y, 2);
                if (d < distance) { closest = region; distance = d; }
            });
            return closest;
        }

        function onPointerDown(event) {
            if (!visible || disposed || failed) return;
            isPointerDown = true;
            dragMoved = false;
            startX = event.clientX;
            startY = event.clientY;
            startRotY = rotY;
            startRotX = rotX;
            lastPointerX = event.clientX;
            lastPointerY = event.clientY;
            velY = 0;
            velX = 0;
            targetRotY = null;
            targetRotX = null;
            canvas.style.cursor = 'grabbing';
            try { canvas.setPointerCapture(event.pointerId); } catch (_) {}
        }

        function onPointerMove(event) {
            if (!visible || disposed || failed) return;
            if (isPointerDown) {
                var dx = event.clientX - startX;
                var dy = event.clientY - startY;
                if (Math.hypot(dx, dy) > 4) dragMoved = true;
                rotY = startRotY + dx * 0.006;
                rotX = Math.max(-0.8, Math.min(0.8, startRotX + dy * 0.006));
                velY = (event.clientX - lastPointerX) * 0.002;
                velX = (event.clientY - lastPointerY) * 0.002;
                lastPointerX = event.clientX;
                lastPointerY = event.clientY;
                paint();
                updateTooltip();
            } else {
                var closest = nearestRegion(event.clientX, event.clientY);
                canvas.style.cursor = closest ? 'pointer' : 'grab';
                if (hover === closest) return;
                hover = closest;
                updateTooltip();
                if (reducedMotion) paint();
            }
        }

        function onPointerUp(event) {
            if (!isPointerDown) return;
            isPointerDown = false;
            canvas.style.cursor = 'grab';
            try { canvas.releasePointerCapture(event.pointerId); } catch (_) {}
            if (!dragMoved) {
                hover = null;
                selectRegion(nearestRegion(event.clientX, event.clientY));
            }
        }

        function onPointerLeave() {
            if (!isPointerDown) {
                hover = null;
                updateTooltip();
                if (reducedMotion) paint();
            }
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
        function onContextRestored() { failed = !context; requestRefresh(); }

        canvas.addEventListener('pointerdown', onPointerDown);
        canvas.addEventListener('pointermove', onPointerMove);
        canvas.addEventListener('pointerup', onPointerUp);
        canvas.addEventListener('pointercancel', onPointerUp);
        canvas.addEventListener('pointerleave', onPointerLeave);

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

                canvas.removeEventListener('pointerdown', onPointerDown);
                canvas.removeEventListener('pointermove', onPointerMove);
                canvas.removeEventListener('pointerup', onPointerUp);
                canvas.removeEventListener('pointercancel', onPointerUp);
                canvas.removeEventListener('pointerleave', onPointerLeave);

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
                canvas.width = 1;
                canvas.height = 1;
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
        var canvas = root.querySelector('#loginRegionMap');
        var box = canvas && canvas.closest('.login-mapbox');
        if (!canvas || !box) return;
        current = createGlobe(canvas, box, root.querySelector('#loginMapTooltip'), root.querySelector('#loginMapRegionCount'), root.querySelector('#loginRegionList'), root.querySelector('#loginMapUnavailable'));
    }
    mount();
    return function () { if (current) current.dispose(); current = null; };
}
