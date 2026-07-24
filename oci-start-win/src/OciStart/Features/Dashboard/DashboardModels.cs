using OciStart.Core;

namespace OciStart.Features.Dashboard;

public sealed class DashboardStats
{
    public long TotalApiCalls { get; set; }
    public long TotalBootInstances { get; set; }
    public long TotalAttempts { get; set; }
    public long SuccessfulAttempts { get; set; }
    public long SuccessRate { get; set; }
    public long FailCounts { get; set; }
}

public sealed class SystemMetrics
{
    public double CpuUsage { get; set; }
    public double MemoryUsage { get; set; }
    public double TotalMemory { get; set; }
    public double UsedMemory { get; set; }
    public double DiskUsage { get; set; }
    public double DiskTotal { get; set; }
    public double DiskUsed { get; set; }
    public double UploadSpeed { get; set; }
    public double DownloadSpeed { get; set; }
    public double SystemUptime { get; set; }
    public string OsName { get; set; } = "";
    public string Hostname { get; set; } = "";
    public string Timestamp { get; set; } = "";
    public string CpuModel { get; set; } = "";
}

public static class DashboardFormat
{
    public static string MemoryMb(double mb)
    {
        var bytes = mb * 1024 * 1024;
        return Size(bytes);
    }

    public static string Size(double bytes)
    {
        if (bytes <= 0) return "0 B";
        string[] sizes = ["B", "KB", "MB", "GB", "TB"];
        var i = Math.Clamp((int)Math.Floor(Math.Log(bytes) / Math.Log(1024)), 0, sizes.Length - 1);
        return $"{bytes / Math.Pow(1024, i):0.00} {sizes[i]}";
    }

    public static string Speed(double kbps) =>
        kbps < 1024 ? $"{kbps:0.00} KB/s" : $"{kbps / 1024:0.00} MB/s";

    public static string Uptime(double seconds)
    {
        var s = (long)seconds;
        var days = s / 86400;
        var hours = (s % 86400) / 3600;
        var minutes = (s % 3600) / 60;
        return $"{days}天 {hours}时 {minutes}分";
    }

    public static T ExtractData<T>(byte[] raw) where T : class, new()
    {
        var env = JsonUtil.Deserialize<ApiEnvelope<T>>(raw);
        if (env != null)
        {
            if (!env.Success && env.Data == null)
                throw ApiError.Server(env.Message ?? "请求失败");
            if (env.Data != null) return env.Data;
        }
        var direct = JsonUtil.Deserialize<T>(raw);
        return direct ?? new T();
    }
}
