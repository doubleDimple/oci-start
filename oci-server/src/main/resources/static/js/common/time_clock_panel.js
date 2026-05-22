
document.addEventListener("DOMContentLoaded", function () {

    const sysZone = document.getElementById("sysZoneHidden").dataset.zone;
    const bjZone = "Asia/Shanghai";

    const panel = document.getElementById("clockPanel");
    const btn = document.getElementById("showClocksBtn");

    const sysClock = document.getElementById("flipSys");
    const bjClock = document.getElementById("flipBj");
    const diffBox = document.getElementById("flipDiff");
    const sysZoneLabel = document.getElementById("sysZoneLabel");

    sysZoneLabel.textContent = sysZone;


    let nebulaInited = false;

    btn.addEventListener("click", () => {

        if (panel.classList.contains("hidden")) {

            // ---------- 展开 ----------
            panel.classList.remove("hidden");
            panel.style.maxHeight = "none";
            void panel.offsetHeight;
            panel.style.maxHeight = panel.scrollHeight + "px";

            setTimeout(() => {
                if (!nebulaInited) {
                    initNebula();
                    nebulaInited = true;
                }
            }, 350);

        } else {

            // ---------- 收起 ----------
            panel.style.maxHeight = panel.scrollHeight + "px";
            setTimeout(() => panel.style.maxHeight = "0px", 10);
            setTimeout(() => panel.classList.add("hidden"), 350);
        }
    });


    function initClock(container) {
        container.innerHTML = "";
        for (let i = 0; i < 8; i++) {
            const box = document.createElement("div");
            box.className = "flip-digit";

            const card = document.createElement("div");
            card.className = "flip-card";

            box.appendChild(card);
            container.appendChild(box);
        }
    }

    initClock(sysClock);
    initClock(bjClock);


    function fmt(date, zone) {
        return new Intl.DateTimeFormat("zh-CN", {
            hour12: false,
            timeZone: zone,
            hour: "2-digit",
            minute: "2-digit",
            second: "2-digit"
        }).format(date);
    }

    const sysCache = { value: "" };
    const bjCache = { value: "" };

    function updateClock(container, nowStr, oldStr) {
        if (!oldStr.value) oldStr.value = "--------";

        const newChars = nowStr.split("");
        const oldChars = oldStr.value.split("");
        const cards = container.querySelectorAll(".flip-card");

        newChars.forEach((c, i) => {
            if (c !== oldChars[i]) {
                cards[i].innerText = c;
                cards[i].classList.add("flip");
                setTimeout(() => cards[i].classList.remove("flip"), 500);
            }
        });

        oldStr.value = nowStr;
    }


    function getOffsetMinutes(zone) {
        const now = new Date();
        const local = new Date(now.toLocaleString("en-US", { timeZone: zone }));
        return (local - now) / 60000;
    }

    function getDiffHour(zoneA, zoneB) {
        return (getOffsetMinutes(zoneA) - getOffsetMinutes(zoneB)) / 60;
    }


    function tick() {
        const now = new Date();

        const sys = fmt(now, sysZone);
        const bj = fmt(now, bjZone);

        updateClock(sysClock, sys, sysCache);
        updateClock(bjClock, bj, bjCache);

        let diff = getDiffHour(sysZone, bjZone);
        if (Math.abs(diff) < 0.01) diff = 0;

        if (diff === 0) {
            diffBox.innerHTML = "北京时间同步";
        } else {
            const sign = diff > 0 ? "+" : "";
            const color = diff > 0 ? "#3fda8f" : "#ff6666";
            diffBox.innerHTML = `与北京相差： <span style="color:${color}">${sign}${diff.toFixed(1)} 小时</span>`;
        }

    }

    tick();
    setInterval(tick, 1000);
});


function initNebula() {

    const canvas = document.getElementById("nebulaCanvas");
    const ctx = canvas.getContext("2d");

    function resize() {
        canvas.width = canvas.offsetWidth;
        canvas.height = canvas.offsetHeight;
    }

    resize();
    window.addEventListener("resize", resize);

    let w = canvas.width;
    let h = canvas.height;

    // 粒子
    const COUNT = 80;
    const particles = [];
    for (let i = 0; i < COUNT; i++) {
        particles.push({
            x: Math.random() * w,
            y: Math.random() * h,
            vx: (Math.random() - 0.5) * 0.4,
            vy: (Math.random() - 0.5) * 0.4,
            r: 1 + Math.random() * 2,
            alpha: 0.2 + Math.random() * 0.6
        });
    }

    function draw() {
        w = canvas.width;
        h = canvas.height;

        ctx.clearRect(0, 0, w, h);

        const gradient = ctx.createRadialGradient(
            w * 0.7, h * 0.5, 10,
            w, h, w
        );

        gradient.addColorStop(0, "rgba(0,255,180,0.2)");
        gradient.addColorStop(1, "rgba(0,40,80,0.05)");
        ctx.fillStyle = gradient;
        ctx.fillRect(0, 0, w, h);

        particles.forEach(p => {
            p.x += p.vx;
            p.y += p.vy;

            if (p.x < 0 || p.x > w) p.vx *= -1;
            if (p.y < 0 || p.y > h) p.vy *= -1;

            ctx.beginPath();
            ctx.fillStyle = `rgba(0,255,200,`+ p.alpha+`)`;
            ctx.shadowBlur = 15;
            ctx.shadowColor = "rgba(0,255,180,0.9)";
            ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
            ctx.fill();
        });

        requestAnimationFrame(draw);
    }

    draw();
}
