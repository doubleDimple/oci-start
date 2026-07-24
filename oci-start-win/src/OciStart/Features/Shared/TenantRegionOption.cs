using OciStart.Core;

namespace OciStart.Features.Shared;

public sealed class TenantRegionOption
{
    public string Id { get; set; } = "";
    public string UserName { get; set; } = "";
    public string TenancyName { get; set; } = "";
    public string Region { get; set; } = "";
    public bool IsHomeRegion { get; set; }

    public string DisplayLabel
    {
        get
        {
            if (!string.IsNullOrEmpty(UserName)) return UserName;
            if (!string.IsNullOrEmpty(TenancyName)) return TenancyName;
            if (!string.IsNullOrEmpty(Region)) return Region;
            return Id;
        }
    }

    public static List<TenantRegionOption> ParseList(byte[] raw)
    {
        var (rows, _, _, _) = Common.Components.JsonPage.Parse(raw);
        return rows.Select(m => new TenantRegionOption
        {
            Id = Common.Components.JsonPage.Pick(m, "id", "tenantId"),
            UserName = Common.Components.JsonPage.Pick(m, "userName", "name"),
            TenancyName = Common.Components.JsonPage.Pick(m, "tenancyName", "tenancy"),
            Region = Common.Components.JsonPage.Pick(m, "region", "regionName"),
            IsHomeRegion = JsonUtil.Bool(m, "isHomeRegion") || JsonUtil.Bool(m, "homeRegion")
        }).Where(x => !string.IsNullOrEmpty(x.Id)).ToList();
    }
}
