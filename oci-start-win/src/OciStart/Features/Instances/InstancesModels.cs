using System.Text.Json;
using OciStart.Core;

namespace OciStart.Features.Instances;

/// <summary>
/// 一行实例（对齐 Mac InstanceItem / Web InstanceDetailsRes）。
/// Id = 本地 instance_detail 主键；InstanceId = OCI OCID。
/// </summary>
public sealed class InstanceItem
{
    public string Id { get; set; } = "";
    public long TenantId { get; set; }
    public string TenantIdStr { get; set; } = "";
    public string InstanceId { get; set; } = "";
    public string DisplayName { get; set; } = "";
    public string Shape { get; set; } = "";
    public string State { get; set; } = "";
    public int Ocpus { get; set; }
    public int MemoryInGBs { get; set; }
    public long BootVolumeSizeInGBs { get; set; }
    public string BootVolumeId { get; set; } = "";
    public string VpusPerGb { get; set; } = "0";
    public string PublicIps { get; set; } = "";
    public string PrivateIps { get; set; } = "";
    public string CpuAndMem { get; set; } = "/";
    public string RegionName { get; set; } = "";
    public string TenancyName { get; set; } = "";
    public string Remark { get; set; } = "";

    /// <summary>List display for tenancy with optional masking (align Mac namesHidden).</summary>
    public string TenancyDisplay { get; set; } = "";

    public string EffectiveTenantId =>
        !string.IsNullOrEmpty(TenantIdStr) ? TenantIdStr :
        TenantId > 0 ? TenantId.ToString() : "";

    public string StateLabel => State.ToLowerInvariant() switch
    {
        "running" => "运行中",
        "stopped" => "已停止",
        "starting" => "启动中",
        "stopping" => "停止中",
        "terminated" or "terminating" => "已终止",
        _ => string.IsNullOrEmpty(State) ? "未知" : State
    };

    public bool IsRunning => State.Equals("running", StringComparison.OrdinalIgnoreCase);
    public bool IsStopped => State.Equals("stopped", StringComparison.OrdinalIgnoreCase);
}

public sealed class InstancesListResponse
{
    public List<InstanceItem> Content { get; set; } = [];
    public int CurrentPage { get; set; }
    public int TotalPages { get; set; }
    public long TotalElements { get; set; }
    public int Size { get; set; } = 10;
}

/// <summary>系统重装 OS 选项（对齐 Web handleQuickDD / Mac InstanceDDOsOptions）.</summary>
public static class InstanceDdOsOptions
{
    public static readonly (string Id, string Title)[] All =
    [
        ("alpine|3.19", "Alpine 3.19"),
        ("alpine|3.20", "Alpine 3.20"),
        ("alpine|3.21", "Alpine 3.21"),
        ("alpine|3.22", "Alpine 3.22"),
        ("debian|9", "Debian 9"),
        ("debian|10", "Debian 10"),
        ("debian|11", "Debian 11"),
        ("debian|12", "Debian 12"),
        ("debian|13", "Debian 13"),
        ("ubuntu|16.04", "Ubuntu 16.04"),
        ("ubuntu|18.04", "Ubuntu 18.04"),
        ("ubuntu|20.04", "Ubuntu 20.04"),
        ("ubuntu|22.04", "Ubuntu 22.04"),
        ("ubuntu|24.04", "Ubuntu 24.04"),
        ("ubuntu|25.10", "Ubuntu 25.10"),
        ("centos|9", "CentOS 9"),
        ("centos|10", "CentOS 10"),
        ("rocky|8", "Rocky 8"),
        ("rocky|9", "Rocky 9"),
        ("rocky|10", "Rocky 10"),
        ("almalinux|8", "AlmaLinux 8"),
        ("almalinux|9", "AlmaLinux 9"),
        ("almalinux|10", "AlmaLinux 10"),
        ("oracle|8", "Oracle 8"),
        ("oracle|9", "Oracle 9"),
        ("oracle|10", "Oracle 10"),
        ("fedora|41", "Fedora 41"),
        ("fedora|42", "Fedora 42"),
        ("anolis|7", "Anolis 7"),
        ("anolis|8", "Anolis 8"),
        ("anolis|23", "Anolis 23"),
        ("opencloudos|8", "OpenCloudOS 8"),
        ("opencloudos|9", "OpenCloudOS 9"),
        ("openeuler|20.03", "OpenEuler 20.03"),
        ("openeuler|22.03", "OpenEuler 22.03"),
        ("openeuler|24.03", "OpenEuler 24.03"),
        ("openeuler|25.09", "OpenEuler 25.09"),
        ("opensuse|15.6", "OpenSUSE 15.6"),
        ("opensuse|16.0", "OpenSUSE 16.0"),
        ("opensuse|tumbleweed", "OpenSUSE Tumbleweed"),
        ("nixos|25.05", "NixOS 25.05"),
        ("kali|", "Kali Linux"),
        ("arch|", "Arch Linux"),
        ("gentoo|", "Gentoo"),
        ("aosc|", "AOSC"),
        ("fnos|", "FNOS"),
    ];
}

public static class InstanceJson
{
    public static InstancesListResponse ParseList(byte[] data)
    {
        var root = JsonUtil.Obj(data) ?? throw ApiError.Server("实例列表响应无效");
        var resp = new InstancesListResponse
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
            var ocpus = JsonUtil.Int(m, "ocpus");
            var mem = JsonUtil.Int(m, "memoryInGBs");
            var cm = JsonUtil.Str(m, "cpuAndMem");
            if (string.IsNullOrEmpty(cm) || cm == "/")
                cm = (ocpus > 0 || mem > 0) ? $"{ocpus}C{mem}G" : "/";

            var tenantIdStr = JsonUtil.Str(m, "tenantIdStr");
            if (string.IsNullOrEmpty(tenantIdStr))
                tenantIdStr = JsonUtil.Str(m, "tenantId");

            resp.Content.Add(new InstanceItem
            {
                Id = JsonUtil.Str(m, "id"),
                TenantId = JsonUtil.Int64(m, "tenantId"),
                TenantIdStr = tenantIdStr,
                InstanceId = JsonUtil.Str(m, "instanceId"),
                DisplayName = JsonUtil.Str(m, "displayName"),
                Shape = JsonUtil.Str(m, "shape"),
                State = JsonUtil.Str(m, "state"),
                Ocpus = ocpus,
                MemoryInGBs = mem,
                BootVolumeSizeInGBs = JsonUtil.Int64(m, "bootVolumeSizeInGBs"),
                BootVolumeId = JsonUtil.Str(m, "bootVolumeId"),
                VpusPerGb = string.IsNullOrEmpty(JsonUtil.Str(m, "vpusPerGB"))
                    ? "0"
                    : JsonUtil.Str(m, "vpusPerGB"),
                PublicIps = JsonUtil.Str(m, "publicIps"),
                PrivateIps = JsonUtil.Str(m, "privateIps"),
                CpuAndMem = cm,
                RegionName = JsonUtil.Str(m, "regionName"),
                TenancyName = JsonUtil.Str(m, "tenancyName"),
                Remark = JsonUtil.Str(m, "remark")
            });
        }
        return resp;
    }
}
