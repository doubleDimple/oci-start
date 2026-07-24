using OciStart.Core;
using OciStart.Features.Shared;

namespace OciStart.Features.Instances;

/// <summary>Network layer for `/oci/*` — align Mac InstancesService.</summary>
public sealed class InstancesService
{
    private readonly ApiClient _api = ApiClient.Shared;

    public async Task<InstancesListResponse> ListAsync(int page, int size, string? tenantId = null, CancellationToken ct = default)
    {
        var q = new Dictionary<string, string>
        {
            ["page"] = page.ToString(),
            ["size"] = size.ToString()
        };
        if (!string.IsNullOrWhiteSpace(tenantId))
            q["tenantId"] = tenantId!;
        var raw = await _api.GetJsonAsync("/oci/list/json", q, ct: ct).ConfigureAwait(false);
        return InstanceJson.ParseList(raw);
    }

    public async Task<List<TenantRegionOption>> ListParentTenantsAsync(CancellationToken ct = default)
    {
        var raw = await _api.GetJsonAsync("/tenants/listParentTenants", ct: ct).ConfigureAwait(false);
        return TenantRegionOption.ParseList(raw);
    }

    public async Task<List<TenantRegionOption>> ListRegionsAsync(string parentId, CancellationToken ct = default)
    {
        var raw = await _api.GetJsonAsync("/tenants/listRegions",
            new Dictionary<string, string> { ["parentId"] = parentId }, ct: ct).ConfigureAwait(false);
        return TenantRegionOption.ParseList(raw);
    }

    public async Task<(byte[] data, string? filename)> ExportAsync(CancellationToken ct = default)
    {
        var (data, filename, _) = await _api.DownloadAsync("/oci/export", ct: ct).ConfigureAwait(false);
        return (data, filename);
    }

    public Task<string> StartAsync(string localId, CancellationToken ct = default) =>
        PostAction("/oci/startInstance", new { instanceId = localId }, "实例启动请求已发送", ct);

    public Task<string> StopAsync(string localId, CancellationToken ct = default) =>
        PostAction("/oci/stopInstance", new { instanceId = localId }, "实例停止请求已发送", ct);

    public Task<string> SendTerminateCodeAsync(string localId, CancellationToken ct = default) =>
        PostAction("/oci/sendVerificationCode", new { instanceId = localId }, "验证码已发送", ct);

    public Task<string> TerminateAsync(string localId, string code, CancellationToken ct = default) =>
        PostAction("/oci/terminateInstance", new { instanceId = localId, verificationCode = code }, "实例终止请求已发送", ct);

    public Task<string> UpdateNameAsync(string localId, string newName, CancellationToken ct = default) =>
        PostAction("/oci/updateName", new { instanceId = localId, newName }, "名称已更新", ct);

    public Task<string> UpdateRemarkAsync(string localId, string remark, CancellationToken ct = default)
    {
        if (!long.TryParse(localId, out var id))
            throw ApiError.Server("实例ID无效");
        return PostAction("/oci/updateRemark", new { instanceId = id, remark }, "备注已更新", ct);
    }

    public Task<string> UpdateConfigAsync(string localId, int cpu, int memory, CancellationToken ct = default) =>
        PostAction("/oci/updateConfig", new { instanceId = localId, cpu, memory }, "配置更新成功", ct);

    public Task<string> UpdateBootVolumeAsync(string localId, long sizeGb, CancellationToken ct = default) =>
        PostAction("/oci/updateBootVolume", new { instanceId = localId, bootVolumeSize = sizeGb, expand = true },
            "引导卷更新成功", ct);

    public async Task<string> UpdateVpuAsync(
        string bootVolumeId, string tenantId, string instanceDetailId, int vpus, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(bootVolumeId))
            throw ApiError.Server("引导卷 ID 为空，无法更新 VPU");
        object body;
        if (long.TryParse(instanceDetailId, out var detailId))
            body = new { vpusPerGB = vpus, tenantId, instanceDetailId = detailId };
        else
            body = new { vpusPerGB = vpus, tenantId };
        var raw = await _api.PutJsonAsync($"/tenants/update-volumes/{bootVolumeId}", body, ct)
            .ConfigureAwait(false);
        var r = ApiClient.SuccessMessage(raw, "VPU 已更新");
        if (!r.ok) throw ApiError.Server(r.message);
        return r.message;
    }

    public async Task<string> ChangeSpecIpAsync(string localId, IReadOnlyList<string> cidrRanges, CancellationToken ct = default)
    {
        if (!long.TryParse(localId, out var tid))
            throw ApiError.Server("实例ID无效");
        var raw = await _api.PostJsonAsync("/oci/changeSpecIp", new
        {
            tenantId = tid,
            cidrRanges
        }, ct: ct).ConfigureAwait(false);
        var r = ApiClient.SuccessMessage(raw, "IP 切换成功");
        if (!r.ok) throw ApiError.Server(r.message);
        return r.message;
    }

    public Task<string> EnableIpv6Async(string localId, CancellationToken ct = default) =>
        PostAction("/oci/enableIpv6", new { tenantId = localId }, "IPv6 操作成功", ct);

    public async Task<string> DeleteLocalRecordAsync(string localId, CancellationToken ct = default)
    {
        if (!long.TryParse(localId, out var id))
            throw ApiError.Server("实例ID无效");
        return await PostAction("/oci/deleteInstanceRecord", new { id }, "本地记录已删除", ct).ConfigureAwait(false);
    }

    public Task<string> HeavyRestartAsync(string ociOrLocalId, string tenantId, CancellationToken ct = default) =>
        PostAction("/oci/console/heavyNewRestart", new
        {
            instanceId = ociOrLocalId,
            tenantId
        }, "重引导请求已发送", ct);

    public async Task<(bool ok, string message, string log, string binary)> InstallWebsockifyAsync(
        CancellationToken ct = default)
    {
        var raw = await _api.PostJsonAsync("/oci/console/websockify/install", new { }, longTimeout: true, ct: ct)
            .ConfigureAwait(false);
        var root = JsonUtil.Obj(raw) ?? new();
        var ok = JsonUtil.Bool(root, "success") || JsonUtil.Bool(root, "installed");
        var msg = JsonUtil.Str(root, "message");
        var log = JsonUtil.Str(root, "log");
        if (string.IsNullOrEmpty(log)) log = JsonUtil.Str(root, "output");
        var binary = JsonUtil.Str(root, "binary");
        if (string.IsNullOrEmpty(binary)) binary = JsonUtil.Str(root, "path");
        return (ok, msg, log, binary);
    }

    public async IAsyncEnumerable<(string Event, string Data)> StreamQuickDdAsync(
        string instanceId,
        string osType,
        string osVersion,
        string password,
        [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken ct = default)
    {
        var q = new Dictionary<string, string>
        {
            ["instanceId"] = instanceId,
            ["osType"] = osType,
            ["osVersion"] = osVersion,
            ["ddPassword"] = password
        };
        await foreach (var ev in _api.StreamSseEventsAsync("/oci/instance/quickDD", q, ct).ConfigureAwait(false))
            yield return ev;
    }

    public async Task<(string username, string host, string port, string password)> LoadSshConfigAsync(
        string localId, CancellationToken ct = default)
    {
        var raw = await _api.GetJsonAsync($"/oci/ssh/config/{localId}", ct: ct).ConfigureAwait(false);
        var root = JsonUtil.Obj(raw) ?? new();
        if (root.TryGetValue("success", out var sucEl) && !JsonUtil.Bool(sucEl))
            return ("root", "", "22", "");
        var data = root;
        if (root.TryGetValue("data", out var d) && d.ValueKind == System.Text.Json.JsonValueKind.Object)
            data = JsonUtil.ToDict(d);
        var user = JsonUtil.Str(data, "username");
        if (string.IsNullOrEmpty(user)) user = "root";
        var host = JsonUtil.Str(data, "host");
        var port = JsonUtil.Str(data, "port");
        if (string.IsNullOrEmpty(port)) port = "22";
        var pass = JsonUtil.Str(data, "sshPassword");
        if (string.IsNullOrEmpty(pass)) pass = JsonUtil.Str(data, "password");
        return (user, host, port, pass);
    }

    public Task SaveSshConfigAsync(string localId, string username, string port, string password, CancellationToken ct = default) =>
        PostAction("/oci/ssh/config", new
        {
            instanceId = localId,
            username,
            port,
            password
        }, "SSH 配置已保存", ct);

    public async Task<string> SftpUploadAsync(
        string host, int port, string username, string password, string remotePath, string localFile,
        CancellationToken ct = default)
    {
        var raw = await _api.PostMultipartAsync("/oci/sftp/upload", new Dictionary<string, string>
        {
            ["host"] = host,
            ["port"] = port.ToString(),
            ["username"] = username,
            ["password"] = password,
            ["remotePath"] = remotePath
        }, "file", localFile, ct).ConfigureAwait(false);
        var r = ApiClient.SuccessMessage(raw, "上传成功");
        if (!r.ok) throw ApiError.Server(r.message);
        var root = JsonUtil.Obj(raw);
        if (root != null)
        {
            var dataMsg = JsonUtil.Str(root, "data");
            if (!string.IsNullOrEmpty(dataMsg)) return dataMsg;
        }
        return r.message;
    }

    public async Task<(byte[] data, string filename)> SftpDownloadAsync(
        string host, int port, string username, string password, string remotePath,
        CancellationToken ct = default)
    {
        var (data, filename) = await _api.PostDownloadAsync("/oci/sftp/download", new
        {
            host,
            port,
            username,
            password,
            remotePath
        }, ct).ConfigureAwait(false);
        if (string.IsNullOrEmpty(filename))
        {
            var slash = remotePath.LastIndexOf('/');
            filename = slash >= 0 && slash < remotePath.Length - 1
                ? remotePath[(slash + 1)..]
                : "download";
        }
        return (data, filename!);
    }

    public async Task<string> StartConsoleAsync(string localId, CancellationToken ct = default)
    {
        var raw = await _api.PostJsonAsync("/oci/console/start", new { instanceId = localId }, ct: ct)
            .ConfigureAwait(false);
        var r = ApiClient.SuccessMessage(raw, "控制台会话已创建");
        if (!r.ok) throw ApiError.Server(r.message);
        var root = JsonUtil.Obj(raw);
        if (root != null && root.TryGetValue("data", out var data) && data.ValueKind == System.Text.Json.JsonValueKind.Object)
        {
            var m = JsonUtil.ToDict(data);
            var url = Common.Components.JsonPage.Pick(m, "vncUrl", "url", "wsUrl");
            if (!string.IsNullOrEmpty(url)) return url;
        }
        return r.message;
    }

    public async Task<List<Dictionary<string, System.Text.Json.JsonElement>>> ListVnicsAsync(
        string localId, CancellationToken ct = default)
    {
        byte[] raw;
        try
        {
            raw = await _api.GetJsonAsync($"/oci/vnic/list", new Dictionary<string, string>
            {
                ["instanceId"] = localId
            }, ct: ct).ConfigureAwait(false);
        }
        catch
        {
            raw = await _api.GetJsonAsync($"/oci/instance/{localId}/vnics", ct: ct).ConfigureAwait(false);
        }
        var (rows, _, _, _) = Common.Components.JsonPage.Parse(raw);
        return rows;
    }

    private async Task<string> PostAction(string path, object body, string fallback, CancellationToken ct)
    {
        var raw = await _api.PostJsonAsync(path, body, ct: ct).ConfigureAwait(false);
        var r = ApiClient.SuccessMessage(raw, fallback);
        if (!r.ok) throw ApiError.Server(r.message);
        return r.message;
    }
}
