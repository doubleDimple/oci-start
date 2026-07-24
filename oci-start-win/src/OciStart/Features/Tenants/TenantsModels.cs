using System.Text.Json;
using OciStart.Core;

namespace OciStart.Features.Tenants;

public sealed class TenantItem
{
    public long Id { get; set; }
    public string TenantId { get; set; } = "";
    public string UserName { get; set; } = "";
    public string Region { get; set; } = "";
    public string DefName { get; set; } = "";
    public string TenancyName { get; set; } = "";
    public string AccountTypeName { get; set; } = "";
    public string AccountCost { get; set; } = "";
    public int CloudType { get; set; } = 1;
    public bool IsHomeRegion { get; set; } = true;
    public bool ApiSynced { get; set; }
    public bool ProxyBound { get; set; }
    public string DisplayName =>
        !string.IsNullOrWhiteSpace(DefName) ? DefName
        : !string.IsNullOrWhiteSpace(TenancyName) ? TenancyName
        : UserName;
}

public sealed class TenantsListResponse
{
    public List<TenantItem> Content { get; set; } = [];
    public int CurrentPage { get; set; }
    public int TotalPages { get; set; }
    public long TotalElements { get; set; }
    public int Size { get; set; } = 10;
}

public sealed class TenantAuditLogEntry
{
    public string EventType { get; set; } = "";
    public string UserName { get; set; } = "";
    public string IpAddress { get; set; } = "";
    public string ClientEnv { get; set; } = "";
    public string EventTime { get; set; } = "";
    public string ResponseStatus { get; set; } = "";
    public bool IsError =>
        !string.IsNullOrEmpty(ResponseStatus) && ResponseStatus != "200";
}

public sealed class TenantAuditLogPage
{
    public List<TenantAuditLogEntry> Items { get; set; } = [];
    public string? NextPageToken { get; set; }
}

public sealed class TenantSubscribedRegion
{
    public string RegionKey { get; set; } = "";
    public string RegionName { get; set; } = "";
    public string Status { get; set; } = "";
    public bool IsHomeRegion { get; set; }
    public string Display => string.IsNullOrEmpty(RegionName) ? RegionKey : RegionName;
}

public sealed class TenantUnsubscribedRegion
{
    public string Key { get; set; } = "";
    public string Name { get; set; } = "";
    public string CnName { get; set; } = "";
    public bool IsSelected { get; set; }
    public string Display =>
        !string.IsNullOrEmpty(CnName) ? $"{CnName} ({Name})"
        : !string.IsNullOrEmpty(Name) ? Name
        : Key;
}

public sealed class TenantTrafficRow
{
    public string InstanceId { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string Region { get; set; } = "";
    public string PublicIp { get; set; } = "";
    public string TimePoint { get; set; } = "";
    public double IngressBytes { get; set; }
    public double EgressBytes { get; set; }
    public double TotalBytes { get; set; }
    public string Title =>
        !string.IsNullOrEmpty(DisplayName) ? DisplayName
        : !string.IsNullOrEmpty(InstanceId) ? InstanceId
        : "—";
    public string IngressGb => FormatGb(IngressBytes);
    public string EgressGb => FormatGb(EgressBytes);
    public string TotalGb => FormatGb(TotalBytes > 0 ? TotalBytes : IngressBytes + EgressBytes);
    private static string FormatGb(double b) => $"{b / 1_073_741_824.0:F2} GB";
}

public sealed class TenantImageInfo
{
    public string ImageId { get; set; } = "";
    public string OperatingSystem { get; set; } = "";
    public string OperatingSystemVersion { get; set; } = "";
    public string Label =>
        string.IsNullOrEmpty(OperatingSystemVersion)
            ? OperatingSystem
            : $"{OperatingSystem} {OperatingSystemVersion}";
}

public static class TenantsJson
{
    public static TenantsListResponse ParseList(byte[] data)
    {
        var root = JsonUtil.Obj(data) ?? throw ApiError.Server("租户列表响应无效");
        var resp = new TenantsListResponse
        {
            CurrentPage = JsonUtil.Int(root, "currentPage"),
            TotalPages = JsonUtil.Int(root, "totalPages"),
            TotalElements = JsonUtil.Int64(root, "totalElements"),
            Size = JsonUtil.Int(root, "size", 10)
        };
        if (resp.Size <= 0) resp.Size = 10;

        if (!root.TryGetValue("content", out var arr) || arr.ValueKind != JsonValueKind.Array)
            return resp;

        foreach (var el in arr.EnumerateArray())
        {
            if (el.ValueKind != JsonValueKind.Object) continue;
            var m = JsonUtil.ToDict(el);
            resp.Content.Add(new TenantItem
            {
                Id = JsonUtil.Int64(m, "id"),
                TenantId = JsonUtil.Str(m, "tenantId"),
                UserName = JsonUtil.Str(m, "userName"),
                Region = JsonUtil.Str(m, "region"),
                DefName = JsonUtil.Str(m, "defName"),
                TenancyName = JsonUtil.Str(m, "tenancyName"),
                AccountTypeName = JsonUtil.Str(m, "accountTypeName"),
                AccountCost = JsonUtil.Str(m, "accountCost"),
                CloudType = JsonUtil.Int(m, "cloudType", 1),
                IsHomeRegion = m.ContainsKey("isHomeRegion")
                    ? JsonUtil.Bool(m, "isHomeRegion")
                    : JsonUtil.Bool(m, "homeRegion"),
                ApiSynced = JsonUtil.Bool(m, "apiSynced"),
                ProxyBound = JsonUtil.Bool(m, "proxyBound")
            });
        }
        return resp;
    }

    public static TenantAuditLogPage ParseAudit(byte[] data)
    {
        var page = new TenantAuditLogPage();
        var root = JsonUtil.Obj(data);
        if (root == null) return page;

        if (root.TryGetValue("success", out var suc) && !JsonUtil.Bool(suc))
        {
            var msg = JsonUtil.Str(root, "message");
            if (string.IsNullOrEmpty(msg)) msg = "审计日志查询失败";
            throw ApiError.Server(msg);
        }

        // ApiResponse.data = OciPageResult{ data, nextPageToken } | list
        JsonElement payload = default;
        var hasPayload = false;
        if (root.TryGetValue("data", out var dataEl))
        {
            payload = dataEl;
            hasPayload = true;
        }

        if (hasPayload && payload.ValueKind == JsonValueKind.Object)
        {
            var d = JsonUtil.ToDict(payload);
            page.NextPageToken = NullIfEmpty(JsonUtil.Str(d, "nextPageToken"));
            if (TryArray(d, out var list, "data", "items", "logs", "content"))
                page.Items = ParseAuditList(list);
            return page;
        }

        if (hasPayload && payload.ValueKind == JsonValueKind.Array)
        {
            page.Items = ParseAuditList(payload);
            return page;
        }

        if (root.TryGetValue("content", out var c) && c.ValueKind == JsonValueKind.Array)
            page.Items = ParseAuditList(c);
        return page;
    }

    private static List<TenantAuditLogEntry> ParseAuditList(JsonElement arr)
    {
        var list = new List<TenantAuditLogEntry>();
        foreach (var el in arr.EnumerateArray())
        {
            if (el.ValueKind != JsonValueKind.Object) continue;
            var m = JsonUtil.ToDict(el);
            list.Add(new TenantAuditLogEntry
            {
                EventType = Pick(m, "eventType", "eventName", "type"),
                UserName = Pick(m, "userName", "principalName", "user"),
                IpAddress = Pick(m, "ipAddress", "sourceIP", "sourceIp", "ip"),
                ClientEnv = Pick(m, "clientEnv", "message"),
                EventTime = Pick(m, "eventTime", "time"),
                ResponseStatus = Pick(m, "responseStatus", "status")
            });
        }
        return list;
    }

    public static List<TenantSubscribedRegion> ParseSubscribed(byte[] data)
    {
        var list = new List<TenantSubscribedRegion>();
        foreach (var m in AsObjectList(data))
        {
            var status = JsonUtil.Str(m, "status");
            if (string.IsNullOrEmpty(status) && m.TryGetValue("status", out var st)
                && st.ValueKind == JsonValueKind.Object)
                status = JsonUtil.Str(JsonUtil.ToDict(st), "value");
            list.Add(new TenantSubscribedRegion
            {
                RegionKey = JsonUtil.Str(m, "regionKey"),
                RegionName = JsonUtil.Str(m, "regionName"),
                Status = status,
                IsHomeRegion = JsonUtil.Bool(m, "isHomeRegion")
            });
        }
        return list;
    }

    public static List<TenantUnsubscribedRegion> ParseUnsubscribed(byte[] data)
    {
        var list = new List<TenantUnsubscribedRegion>();
        // may be ApiResponse.data = [...]
        var root = JsonUtil.Obj(data);
        JsonElement arrEl = default;
        var hasArr = false;
        if (root != null && root.TryGetValue("data", out var d) && d.ValueKind == JsonValueKind.Array)
        {
            arrEl = d;
            hasArr = true;
        }
        else
        {
            try
            {
                using var doc = JsonDocument.Parse(data);
                if (doc.RootElement.ValueKind == JsonValueKind.Array)
                {
                    arrEl = doc.RootElement.Clone();
                    hasArr = true;
                }
            }
            catch { /* ignore */ }
        }
        if (!hasArr) return list;
        foreach (var el in arrEl.EnumerateArray())
        {
            if (el.ValueKind != JsonValueKind.Object) continue;
            var m = JsonUtil.ToDict(el);
            list.Add(new TenantUnsubscribedRegion
            {
                Key = JsonUtil.Str(m, "key"),
                Name = JsonUtil.Str(m, "name"),
                CnName = JsonUtil.Str(m, "cnName")
            });
        }
        return list;
    }

    public static List<TenantTrafficRow> ParseTraffic(byte[] data)
    {
        var list = new List<TenantTrafficRow>();
        foreach (var m in AsObjectList(data))
        {
            var ingress = JsonUtil.Dbl(m, "ingressBytes");
            var egress = JsonUtil.Dbl(m, "egressBytes");
            var total = JsonUtil.Dbl(m, "totalBytes");
            if (total <= 0) total = ingress + egress;
            list.Add(new TenantTrafficRow
            {
                InstanceId = JsonUtil.Str(m, "instanceId"),
                DisplayName = FirstNonEmpty(JsonUtil.Str(m, "displayName"), JsonUtil.Str(m, "instanceName")),
                Region = JsonUtil.Str(m, "region"),
                PublicIp = FirstNonEmpty(JsonUtil.Str(m, "publicIp"), JsonUtil.Str(m, "publicIps")),
                TimePoint = JsonUtil.Str(m, "timePoint"),
                IngressBytes = ingress,
                EgressBytes = egress,
                TotalBytes = total
            });
        }
        return list;
    }

    public static List<TenantImageInfo> ParseImages(byte[] data)
    {
        var list = new List<TenantImageInfo>();
        var root = JsonUtil.Obj(data);
        JsonElement arr = default;
        var has = false;
        if (root != null && root.TryGetValue("data", out var d))
        {
            if (d.ValueKind == JsonValueKind.Array) { arr = d; has = true; }
        }
        if (!has)
        {
            try
            {
                using var doc = JsonDocument.Parse(data);
                if (doc.RootElement.ValueKind == JsonValueKind.Array)
                {
                    arr = doc.RootElement.Clone();
                    has = true;
                }
            }
            catch { /* ignore */ }
        }
        if (!has) return list;
        foreach (var el in arr.EnumerateArray())
        {
            if (el.ValueKind != JsonValueKind.Object) continue;
            var m = JsonUtil.ToDict(el);
            list.Add(new TenantImageInfo
            {
                ImageId = JsonUtil.Str(m, "imageId"),
                OperatingSystem = JsonUtil.Str(m, "operatingSystem"),
                OperatingSystemVersion = JsonUtil.Str(m, "operatingSystemVersion")
            });
        }
        return list;
    }

    private static List<Dictionary<string, JsonElement>> AsObjectList(byte[] data)
    {
        var list = new List<Dictionary<string, JsonElement>>();
        try
        {
            using var doc = JsonDocument.Parse(data);
            var root = doc.RootElement;
            if (root.ValueKind == JsonValueKind.Array)
            {
                foreach (var el in root.EnumerateArray())
                    if (el.ValueKind == JsonValueKind.Object)
                        list.Add(JsonUtil.ToDict(el));
                return list;
            }
            if (root.ValueKind == JsonValueKind.Object)
            {
                var d = JsonUtil.ToDict(root);
                if (TryArray(d, out var arr, "data", "content", "items", "rows"))
                {
                    foreach (var el in arr.EnumerateArray())
                        if (el.ValueKind == JsonValueKind.Object)
                            list.Add(JsonUtil.ToDict(el));
                }
            }
        }
        catch { /* ignore */ }
        return list;
    }

    private static bool TryArray(Dictionary<string, JsonElement> d, out JsonElement arr, params string[] keys)
    {
        foreach (var k in keys)
        {
            if (d.TryGetValue(k, out var el) && el.ValueKind == JsonValueKind.Array)
            {
                arr = el;
                return true;
            }
        }
        arr = default;
        return false;
    }

    private static string Pick(Dictionary<string, JsonElement> m, params string[] keys)
    {
        foreach (var k in keys)
        {
            var s = JsonUtil.Str(m, k);
            if (!string.IsNullOrEmpty(s)) return s;
        }
        return "";
    }

    private static string FirstNonEmpty(params string[] ss)
    {
        foreach (var s in ss)
            if (!string.IsNullOrEmpty(s)) return s;
        return "";
    }

    private static string? NullIfEmpty(string s) =>
        string.IsNullOrWhiteSpace(s) ? null : s;
}
