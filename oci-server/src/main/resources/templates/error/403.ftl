<!DOCTYPE html>
<html lang="zh">
<head>
    <meta charset="UTF-8">
    <title>403 访问受限 - OCI-START</title>
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
<#--
    <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;600;700&display=swap" rel="stylesheet">
-->
    <style>
        * {margin:0; padding:0; box-sizing:border-box;}

        body {
            font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
            height: 100vh;
            width: 100vw;
            display: flex;
            flex-direction: column;
            justify-content: center;
            align-items: center;
            text-align: center;
            overflow: hidden;
            color: #ffffff;
            background: linear-gradient(120deg, #0d1b2a, #1b263b, #0d1b2a);
            background-size: 300% 300%;
            animation: gradientFlow 15s ease infinite;
        }

        @keyframes gradientFlow {
            0% { background-position: 0% 50%; }
            50% { background-position: 100% 50%; }
            100% { background-position: 0% 50%; }
        }

        .error-code {
            font-size: 180px;
            font-weight: 800;
            color: #fca311;
            line-height: 1;
            animation: pulse 3s ease-in-out infinite;
        }

        @keyframes pulse {
            0%, 100% { opacity: 1; transform: scale(1); }
            50% { opacity: 0.8; transform: scale(1.05); }
        }

        .error-title {
            font-size: 42px;
            font-weight: 600;
            margin-top: 10px;
            margin-bottom: 15px;
            color: #e0e0e0;
            animation: fadeIn 1.5s ease forwards;
        }

        .error-message {
            font-size: 18px;
            color: #b8c3cc;
            margin-bottom: 40px;
            opacity: 0;
            animation: fadeUp 1.8s ease 0.3s forwards;
        }

        .info-box {
            background: rgba(255, 255, 255, 0.05);
            border-radius: 12px;
            padding: 22px 40px;
            text-align: left;
            min-width: 340px;
            display: flex;
            flex-direction: column;
            gap: 10px;
            opacity: 0;
            transform: translateY(20px);
            animation: fadeUp 1.8s ease 0.6s forwards;
        }

        .info-row {
            display: flex;
            justify-content: space-between;
            border-bottom: 1px solid rgba(255,255,255,0.08);
            padding-bottom: 6px;
        }

        .info-label {
            color: #a8dadc;
            font-size: 15px;
        }

        .info-value {
            color: #fca311;
            font-weight: 600;
            font-size: 15px;
        }

        footer {
            position: absolute;
            bottom: 30px;
            color: #8fa3b7;
            font-size: 14px;
            opacity: 0;
            animation: fadeIn 2s ease 1s forwards;
        }

        @keyframes fadeUp {
            0% { opacity: 0; transform: translateY(30px); }
            100% { opacity: 1; transform: translateY(0); }
        }

        @keyframes fadeIn {
            0% { opacity: 0; }
            100% { opacity: 1; }
        }

        @media (max-width: 600px) {
            .error-code { font-size: 120px; }
            .error-title { font-size: 30px; }
            .info-box { padding: 18px 25px; min-width: 280px; }
        }
    </style>
</head>
<body>
<div class="content">
    <div class="error-code">403</div>
    <div class="error-title">访问受限</div>
    <div class="error-message">
        <#if message??>
            ${message}
        <#else>
            您的 IP 已被封禁，请联系管理员。
        </#if>
    </div>

    <div class="info-box">
        <div class="info-row">
            <div class="info-label">时间：</div>
            <div class="info-value" id="currentTime">${.now?string("yyyy-MM-dd HH:mm:ss")}</div>
        </div>
        <#if code??>
            <div class="info-row">
                <div class="info-label">错误代码：</div>
                <div class="info-value">${code}</div>
            </div>
        </#if>
        <#if ip??>
            <div class="info-row">
                <div class="info-label">访问 IP：</div>
                <div class="info-value">${ip}</div>
            </div>
        </#if>
    </div>
</div>

<footer>© 2025 OCI-START</footer>

<script>
    function updateTime() {
        var now = new Date();
        function pad(n) { return n < 10 ? '0' + n : n; }
        var formatted = now.getFullYear() + '-' +
            pad(now.getMonth() + 1) + '-' +
            pad(now.getDate()) + ' ' +
            pad(now.getHours()) + ':' +
            pad(now.getMinutes()) + ':' +
            pad(now.getSeconds());
        document.getElementById("currentTime").textContent = formatted;
    }
    updateTime();
    setInterval(updateTime, 1000);
</script>
</body>
</html>
