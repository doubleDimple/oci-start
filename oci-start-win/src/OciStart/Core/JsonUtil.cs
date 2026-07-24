using System.Text.Json;

namespace OciStart.Core;

/// <summary>Flexible JSON helpers for mixed server payloads (Jackson quirks).</summary>
public static class JsonUtil
{
    public static readonly JsonSerializerOptions Options = new()
    {
        PropertyNameCaseInsensitive = true,
        PropertyNamingPolicy = JsonNamingPolicy.CamelCase
    };

    public static Dictionary<string, JsonElement>? Obj(byte[] data)
    {
        try
        {
            using var doc = JsonDocument.Parse(data);
            if (doc.RootElement.ValueKind != JsonValueKind.Object) return null;
            return ToDict(doc.RootElement);
        }
        catch
        {
            return null;
        }
    }

    public static Dictionary<string, JsonElement> ToDict(JsonElement el)
    {
        var d = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
        foreach (var p in el.EnumerateObject())
            d[p.Name] = p.Value.Clone();
        return d;
    }

    public static string Str(JsonElement? el)
    {
        if (el == null) return "";
        var e = el.Value;
        return e.ValueKind switch
        {
            JsonValueKind.String => e.GetString() ?? "",
            JsonValueKind.Number => e.ToString(),
            JsonValueKind.True => "true",
            JsonValueKind.False => "false",
            JsonValueKind.Null => "",
            _ => e.ToString()
        };
    }

    public static string Str(Dictionary<string, JsonElement> d, string key) =>
        d.TryGetValue(key, out var v) ? Str(v) : "";

    public static int Int(JsonElement? el, int fallback = 0)
    {
        if (el == null) return fallback;
        var e = el.Value;
        if (e.ValueKind == JsonValueKind.Number && e.TryGetInt32(out var i)) return i;
        if (e.ValueKind == JsonValueKind.Number && e.TryGetInt64(out var l)) return (int)l;
        if (e.ValueKind == JsonValueKind.String && int.TryParse(e.GetString(), out var s)) return s;
        return fallback;
    }

    public static int Int(Dictionary<string, JsonElement> d, string key, int fallback = 0) =>
        d.TryGetValue(key, out var v) ? Int(v, fallback) : fallback;

    public static long Int64(JsonElement? el, long fallback = 0)
    {
        if (el == null) return fallback;
        var e = el.Value;
        if (e.ValueKind == JsonValueKind.Number && e.TryGetInt64(out var l)) return l;
        if (e.ValueKind == JsonValueKind.Number && e.TryGetDouble(out var dbl)) return (long)dbl;
        if (e.ValueKind == JsonValueKind.String && long.TryParse(e.GetString(), out var s)) return s;
        return fallback;
    }

    public static long Int64(Dictionary<string, JsonElement> d, string key, long fallback = 0) =>
        d.TryGetValue(key, out var v) ? Int64(v, fallback) : fallback;

    public static double Dbl(JsonElement? el, double fallback = 0)
    {
        if (el == null) return fallback;
        var e = el.Value;
        if (e.ValueKind == JsonValueKind.Number && e.TryGetDouble(out var d)) return d;
        if (e.ValueKind == JsonValueKind.String && double.TryParse(e.GetString(), out var s)) return s;
        return fallback;
    }

    public static double Dbl(Dictionary<string, JsonElement> d, string key, double fallback = 0) =>
        d.TryGetValue(key, out var v) ? Dbl(v, fallback) : fallback;

    public static bool Bool(JsonElement? el)
    {
        if (el == null) return false;
        var e = el.Value;
        if (e.ValueKind == JsonValueKind.True) return true;
        if (e.ValueKind == JsonValueKind.False) return false;
        if (e.ValueKind == JsonValueKind.Number) return Int64(e) != 0;
        if (e.ValueKind == JsonValueKind.String)
        {
            var s = (e.GetString() ?? "").Trim().ToLowerInvariant();
            return s is "1" or "true" or "yes";
        }
        return false;
    }

    public static bool Bool(Dictionary<string, JsonElement> d, string key) =>
        d.TryGetValue(key, out var v) && Bool(v);

    public static T? Deserialize<T>(byte[] data)
    {
        try
        {
            return JsonSerializer.Deserialize<T>(data, Options);
        }
        catch
        {
            return default;
        }
    }

    public static byte[] Serialize(object body) =>
        JsonSerializer.SerializeToUtf8Bytes(body, Options);
}
