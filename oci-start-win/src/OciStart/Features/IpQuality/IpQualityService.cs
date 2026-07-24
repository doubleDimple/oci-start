using OciStart.Core;

namespace OciStart.Features.IpQuality;

public sealed class IpQualityService
{
    private readonly ApiClient _api = ApiClient.Shared;

    public async Task<IpQualityConfigs> FetchConfigsAsync(CancellationToken ct = default)
    {
        var raw = await _api.GetJsonAsync("/api/system/ipSettingsConfigs", ct: ct).ConfigureAwait(false);
        return IpQualityJson.ParseConfigs(raw);
    }

    public async Task UpdateIpCheckAsync(bool enabled, int checkInterval, CancellationToken ct = default)
    {
        var raw = await _api.PostJsonAsync("/api/system/updateIpCheckConfig", new
        {
            enabled,
            checkInterval
        }, ct: ct).ConfigureAwait(false);
        ApiClient.EnsureApiOk(raw, "保存 IP 检测配置失败");
    }

    public async Task SaveVpsAsync(VpsConfigDto config, CancellationToken ct = default)
    {
        var raw = await _api.PostJsonAsync("/system/vps/saveConfig", new
        {
            type = config.Type,
            enabled = config.Enabled,
            serverIp = config.ServerIp,
            username = config.Username,
            password = config.Password,
            sshPort = config.SshPort
        }, ct: ct).ConfigureAwait(false);
        ApiClient.EnsureApiOk(raw, "保存 VPS 配置失败");
    }

    public async Task<string> TestConnectionAsync(VpsConfigDto config, CancellationToken ct = default)
    {
        var raw = await _api.PostJsonAsync("/system/vps/testConnection", new
        {
            type = config.Type,
            serverIp = config.ServerIp,
            username = config.Username,
            password = config.Password,
            sshPort = config.SshPort
        }, ct: ct).ConfigureAwait(false);
        return IpQualityJson.ParseTestResult(raw);
    }
}
