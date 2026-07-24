using System.IO;
using System.Text;
using OciStart.Core;
using OciStart.Features.Shared;

namespace OciStart.Features.Tenants;

public sealed class TenantsService
{
    private readonly ApiClient _api = ApiClient.Shared;

    public async Task<TenantsListResponse> ListAsync(
        int page, int size, string? keyword, int cloudType, CancellationToken ct = default)
    {
        var q = new Dictionary<string, string>
        {
            ["page"] = page.ToString(),
            ["size"] = size.ToString(),
            ["cloudType"] = cloudType.ToString()
        };
        if (!string.IsNullOrWhiteSpace(keyword))
            q["keyword"] = keyword!;
        var raw = await _api.GetJsonAsync("/tenants/list/json", q, ct: ct).ConfigureAwait(false);
        return TenantsJson.ParseList(raw);
    }

    public async Task DeleteAsync(long tenantId, CancellationToken ct = default)
    {
        var raw = await _api.GetJsonAsync("/tenants/deleteApi",
            new Dictionary<string, string> { ["tenantId"] = tenantId.ToString() }, ct: ct).ConfigureAwait(false);
        ApiClient.EnsureApiOk(raw, "删除失败");
    }

    public async Task SyncOciAsync(long tenantId, CancellationToken ct = default)
    {
        var raw = await _api.GetJsonAsync("/tenants/syncOci",
            new Dictionary<string, string> { ["tenantId"] = tenantId.ToString() },
            longTimeout: true, ct: ct).ConfigureAwait(false);
        ApiClient.EnsureApiOk(raw, "同步失败");
    }

    public async Task UpdateCustomNameAsync(long tenantId, string defName, CancellationToken ct = default)
    {
        var raw = await _api.PostJsonAsync("/tenants/updateCustomName",
            new { tenantId = tenantId.ToString(), defName }, ct: ct).ConfigureAwait(false);
        ApiClient.EnsureApiOk(raw, "更新名称失败");
    }

    public async Task UpdateAccountCostAsync(long tenantId, string cost, CancellationToken ct = default)
    {
        var raw = await _api.PostJsonAsync("/tenants/updateAccountCost",
            new { tenantId = tenantId.ToString(), accountCost = cost }, ct: ct).ConfigureAwait(false);
        ApiClient.EnsureApiOk(raw, "更新费用失败");
    }

    /// <summary>POST multipart /tenants/save — 添加 API 配置.</summary>
    public async Task SaveTenantAsync(IReadOnlyDictionary<string, string> fields, string keyFilePath,
        CancellationToken ct = default)
    {
        var raw = await _api.PostMultipartAsync("/tenants/save", fields, "keyFileStr", keyFilePath, ct)
            .ConfigureAwait(false);
        ApiClient.EnsureApiOk(raw, "保存失败");
        var r = ApiClient.SuccessMessage(raw, "已保存");
        if (!r.ok) throw ApiError.Server(r.message);
    }

    /// <summary>POST /tenants/import — JSON 数组导入.</summary>
    public async Task ImportJsonAsync(byte[] jsonBytes, CancellationToken ct = default)
    {
        // validate array
        try
        {
            using var doc = System.Text.Json.JsonDocument.Parse(jsonBytes);
            if (doc.RootElement.ValueKind != System.Text.Json.JsonValueKind.Array)
                throw ApiError.Server("JSON 格式应为对象数组");
        }
        catch (ApiError) { throw; }
        catch
        {
            throw ApiError.Server("JSON 解析失败");
        }
        var text = Encoding.UTF8.GetString(jsonBytes);
        var raw = await _api.PostJsonAsync("/tenants/import", text, ct: ct).ConfigureAwait(false);
        ApiClient.EnsureApiOk(raw, "导入失败");
    }

    public async Task<List<TenantRegionOption>> ListRegionsAsync(long parentId, CancellationToken ct = default)
    {
        var raw = await _api.GetJsonAsync("/tenants/listRegions",
            new Dictionary<string, string> { ["parentId"] = parentId.ToString() }, ct: ct).ConfigureAwait(false);
        return TenantRegionOption.ParseList(raw);
    }

    public async Task<List<Dictionary<string, System.Text.Json.JsonElement>>> RegionListJsonAsync(
        long tenantId, CancellationToken ct = default)
    {
        var raw = await _api.GetJsonAsync("/tenants/regionList/json",
            new Dictionary<string, string> { ["tenantId"] = tenantId.ToString() }, ct: ct).ConfigureAwait(false);
        var (rows, _, _, _) = Common.Components.JsonPage.Parse(raw);
        return rows;
    }

    public async Task<List<Dictionary<string, System.Text.Json.JsonElement>>> ListUsersAsync(
        long tenantId, CancellationToken ct = default)
    {
        var raw = await _api.GetJsonAsync("/tenants/oracle-users",
            new Dictionary<string, string> { ["tenantId"] = tenantId.ToString() }, ct: ct).ConfigureAwait(false);
        var (rows, _, _, _) = Common.Components.JsonPage.Parse(raw);
        return rows;
    }

    public async Task<List<Dictionary<string, System.Text.Json.JsonElement>>> QueryCostAsync(
        long tenantId, CancellationToken ct = default)
    {
        var raw = await _api.PostJsonAsync("/cost/query", new { tenantId }, ct: ct).ConfigureAwait(false);
        var (rows, _, _, _) = Common.Components.JsonPage.Parse(raw);
        return rows;
    }

    public async Task<List<Dictionary<string, System.Text.Json.JsonElement>>> QueryQuotaAsync(
        long tenantId, string service = "compute", CancellationToken ct = default)
    {
        var raw = await _api.GetJsonAsync("/tenants/quota", new Dictionary<string, string>
        {
            ["tenantId"] = tenantId.ToString(),
            ["service"] = service
        }, ct: ct).ConfigureAwait(false);
        var (rows, _, _, _) = Common.Components.JsonPage.Parse(raw);
        return rows;
    }

    public async Task<(byte[] data, string? filename)> ExportAsync(CancellationToken ct = default)
    {
        var (data, filename, _) = await _api.DownloadAsync("/tenants/export", ct: ct).ConfigureAwait(false);
        return (data, filename);
    }

    public async Task StartAccountCheckAsync(CancellationToken ct = default)
    {
        try
        {
            var raw = await _api.PostJsonAsync("/tenants/accountCheck", new { }, ct: ct).ConfigureAwait(false);
            ApiClient.EnsureApiOk(raw, "账号检测失败");
        }
        catch
        {
            var raw = await _api.GetJsonAsync("/tenants/accountCheck", ct: ct).ConfigureAwait(false);
            ApiClient.EnsureApiOk(raw, "账号检测失败");
        }
    }

    // ── Audit ──

    public async Task<TenantAuditLogPage> AuditLogsAsync(
        long tenantId, string? start, string? end, string? pageToken, CancellationToken ct = default)
    {
        // Build JSON object without nulls (align Mac body)
        using var stream = new MemoryStream();
        using (var w = new System.Text.Json.Utf8JsonWriter(stream))
        {
            w.WriteStartObject();
            w.WriteString("tenantId", tenantId.ToString());
            if (!string.IsNullOrWhiteSpace(start)) w.WriteString("startDate", start);
            if (!string.IsNullOrWhiteSpace(end)) w.WriteString("endDate", end);
            if (!string.IsNullOrWhiteSpace(pageToken)) w.WriteString("pageToken", pageToken);
            if (string.IsNullOrWhiteSpace(start) && string.IsNullOrWhiteSpace(end))
                w.WriteNumber("days", 1);
            w.WriteEndObject();
        }
        var json = Encoding.UTF8.GetString(stream.ToArray());
        var raw = await _api.PostJsonAsync("/tenants/audit/log", json, longTimeout: true, ct: ct)
            .ConfigureAwait(false);
        return TenantsJson.ParseAudit(raw);
    }

    // ── Region subscribe ──

    public async Task<(int total, int subscribed, int unsubscribed)> RegionSummaryAsync(
        long tenantId, CancellationToken ct = default)
    {
        var raw = await _api.GetJsonAsync("/tenants/region-summary",
            new Dictionary<string, string> { ["tenantId"] = tenantId.ToString() }, ct: ct).ConfigureAwait(false);
        var root = JsonUtil.Obj(raw) ?? new();
        var data = root;
        if (root.TryGetValue("data", out var d) && d.ValueKind == System.Text.Json.JsonValueKind.Object)
            data = JsonUtil.ToDict(d);
        return (
            JsonUtil.Int(data, "totalRegions", JsonUtil.Int(data, "total")),
            JsonUtil.Int(data, "subscribedRegions", JsonUtil.Int(data, "subscribed")),
            JsonUtil.Int(data, "unsubscribedRegions", JsonUtil.Int(data, "unsubscribed"))
        );
    }

    public async Task<List<TenantSubscribedRegion>> SubscribedRegionsAsync(long tenantId, CancellationToken ct = default)
    {
        var raw = await _api.GetJsonAsync("/tenants/subscribed-regions-data",
            new Dictionary<string, string> { ["tenantId"] = tenantId.ToString() }, ct: ct).ConfigureAwait(false);
        return TenantsJson.ParseSubscribed(raw);
    }

    public async Task<List<TenantUnsubscribedRegion>> UnsubscribedRegionsAsync(long tenantId, CancellationToken ct = default)
    {
        var raw = await _api.GetJsonAsync("/tenants/unsubscribed-regions",
            new Dictionary<string, string> { ["tenantId"] = tenantId.ToString() }, ct: ct).ConfigureAwait(false);
        return TenantsJson.ParseUnsubscribed(raw);
    }

    public async Task<string> SubscribeRegionsAsync(long tenantId, IReadOnlyList<string> regionKeys,
        CancellationToken ct = default)
    {
        var raw = await _api.PostJsonAsync("/tenants/subscribe-regions", new
        {
            tenantId,
            regionKeys
        }, longTimeout: true, ct: ct).ConfigureAwait(false);
        var r = ApiClient.SuccessMessage(raw, "订阅完成");
        if (!r.ok) throw ApiError.Server(r.message);
        return r.message;
    }

    // ── Traffic ──

    public async Task<List<TenantTrafficRow>> InstanceTrafficAsync(
        IReadOnlyList<string> tenantIds, string start, string end, string period = "1h",
        CancellationToken ct = default)
    {
        var raw = await _api.PostJsonAsync("/monitor/api/instances/traffic", new
        {
            tenantIds,
            startDate = start,
            endDate = end,
            period
        }, longTimeout: true, ct: ct).ConfigureAwait(false);
        return TenantsJson.ParseTraffic(raw);
    }

    public async Task<double> MonitorTrafficThresholdAsync(long tenantId, CancellationToken ct = default)
    {
        try
        {
            var raw = await _api.GetJsonAsync("/monitor/api/traffic/alert",
                new Dictionary<string, string> { ["tenantId"] = tenantId.ToString() }, ct: ct).ConfigureAwait(false);
            var root = JsonUtil.Obj(raw) ?? new();
            if (root.TryGetValue("data", out var d) && d.ValueKind == System.Text.Json.JsonValueKind.Object)
            {
                var m = JsonUtil.ToDict(d);
                var t = JsonUtil.Dbl(m, "threshold");
                if (t > 0) return t;
            }
            var t2 = JsonUtil.Dbl(root, "threshold");
            return t2 > 0 ? t2 : 10240;
        }
        catch
        {
            return 10240;
        }
    }

    public async Task SaveTrafficAlertAsync(long tenantId, double threshold, bool autoShutdown, bool stats,
        CancellationToken ct = default)
    {
        var raw = await _api.PostJsonAsync("/tenants/traffic-alert", new
        {
            tenantId,
            threshold,
            autoShutdown,
            statisticsEnabled = stats,
            enabled = true
        }, ct: ct).ConfigureAwait(false);
        var r = ApiClient.SuccessMessage(raw, "已保存");
        if (!r.ok) throw ApiError.Server(r.message);
    }

    // ── Boot create ──

    public async Task<List<TenantImageInfo>> QuerySystemImagesAsync(long tenantId, string shapeType,
        CancellationToken ct = default)
    {
        var raw = await _api.PostJsonAsync("/tenants/querySystemImages", new
        {
            tenantId = tenantId.ToString(),
            shapeType
        }, ct: ct).ConfigureAwait(false);
        return TenantsJson.ParseImages(raw);
    }

    public async Task SaveBootInstanceAsync(IReadOnlyDictionary<string, string> fields, CancellationToken ct = default)
    {
        var (data, status) = await _api.PostFormAsync("/tenants/boot/save", fields, ct).ConfigureAwait(false);
        if ((int)status is < 200 or >= 300)
            throw ApiError.Server(Encoding.UTF8.GetString(data));
        ApiClient.EnsureApiOk(data, "保存失败");
        var r = ApiClient.SuccessMessage(data, "开机任务已创建");
        if (!r.ok) throw ApiError.Server(r.message);
    }
}
