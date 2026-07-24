using OciStart.Core;

namespace OciStart.Features.IpQuality;

public sealed class IpCheckConfigDto
{
    public bool Enabled { get; set; }
    public int CheckInterval { get; set; } = 1;
}

public sealed class VpsConfigDto
{
    public string Type { get; set; } = "";
    public bool Enabled { get; set; }
    public string ServerIp { get; set; } = "";
    public string Username { get; set; } = "root";
    public string Password { get; set; } = "";
    public int SshPort { get; set; } = 22;
}

public sealed class IpQualityConfigs
{
    public IpCheckConfigDto IpCheck { get; set; } = new();
    public VpsConfigDto Telecom { get; set; } = new() { Type = "telecom" };
    public VpsConfigDto Unicom { get; set; } = new() { Type = "unicom" };
    public VpsConfigDto Mobile { get; set; } = new() { Type = "mobile" };
}

public enum IpCarrier
{
    Telecom,
    Unicom,
    Mobile
}

public static class IpCarrierInfo
{
    public static string Raw(this IpCarrier c) => c switch
    {
        IpCarrier.Telecom => "telecom",
        IpCarrier.Unicom => "unicom",
        IpCarrier.Mobile => "mobile",
        _ => ""
    };

    public static string Title(this IpCarrier c) => c switch
    {
        IpCarrier.Telecom => "电信 VPS",
        IpCarrier.Unicom => "联通 VPS",
        IpCarrier.Mobile => "移动 VPS",
        _ => ""
    };

    public static string Subtitle(this IpCarrier c) => c switch
    {
        IpCarrier.Telecom => "China Telecom · SSH 探测节点",
        IpCarrier.Unicom => "China Unicom · SSH 探测节点",
        IpCarrier.Mobile => "China Mobile · SSH 探测节点",
        _ => ""
    };

    public static string Glyph(this IpCarrier c) => c switch
    {
        IpCarrier.Telecom => "📡",
        IpCarrier.Unicom => "🌐",
        IpCarrier.Mobile => "📱",
        _ => "•"
    };
}

public static class IpQualityJson
{
    public static IpQualityConfigs ParseConfigs(byte[] data)
    {
        var root = JsonUtil.Obj(data) ?? throw ApiError.Server("配置解析失败");
        if (root.TryGetValue("success", out var suc) && !JsonUtil.Bool(suc))
            throw ApiError.Server(string.IsNullOrEmpty(JsonUtil.Str(root, "message"))
                ? "加载配置失败"
                : JsonUtil.Str(root, "message"));

        var payload = root;
        if (root.TryGetValue("data", out var dataEl) && dataEl.ValueKind == System.Text.Json.JsonValueKind.Object)
            payload = JsonUtil.ToDict(dataEl);

        var outCfg = new IpQualityConfigs();
        if (payload.TryGetValue("ipCheck", out var ip) && ip.ValueKind == System.Text.Json.JsonValueKind.Object)
        {
            var d = JsonUtil.ToDict(ip);
            outCfg.IpCheck.Enabled = JsonUtil.Bool(d, "enabled");
            outCfg.IpCheck.CheckInterval = Math.Clamp(JsonUtil.Int(d, "checkInterval", 1), 1, 24);
        }
        outCfg.Telecom = ParseVps(payload, "telecom");
        outCfg.Unicom = ParseVps(payload, "unicom");
        outCfg.Mobile = ParseVps(payload, "mobile");
        return outCfg;
    }

    private static VpsConfigDto ParseVps(Dictionary<string, System.Text.Json.JsonElement> payload, string type)
    {
        var v = new VpsConfigDto { Type = type };
        if (!payload.TryGetValue(type, out var el) || el.ValueKind != System.Text.Json.JsonValueKind.Object)
            return v;
        var d = JsonUtil.ToDict(el);
        v.Enabled = JsonUtil.Bool(d, "enabled");
        v.ServerIp = JsonUtil.Str(d, "serverIp");
        v.Username = JsonUtil.Str(d, "username");
        if (string.IsNullOrEmpty(v.Username)) v.Username = "root";
        v.Password = JsonUtil.Str(d, "password");
        v.SshPort = JsonUtil.Int(d, "sshPort", 22);
        if (v.SshPort <= 0) v.SshPort = 22;
        return v;
    }

    public static string ParseTestResult(byte[] data)
    {
        if (data.Length == 0) return "连接成功";
        var root = JsonUtil.Obj(data);
        if (root == null) return "连接成功";
        if (root.TryGetValue("success", out var suc))
        {
            var msg = JsonUtil.Str(root, "message");
            if (string.IsNullOrEmpty(msg))
                msg = JsonUtil.Bool(suc) ? "SSH 连接成功" : "SSH 连接失败";
            if (!JsonUtil.Bool(suc)) throw ApiError.Server(msg);
            return msg;
        }
        return "连接成功";
    }
}
