using System.Net;
using System.Net.Http;
using System.Text;

namespace OciStart.Core;

/// <summary>HTTP client: Cookie session, form/JSON helpers. Mirrors Mac APIClient.</summary>
public sealed class ApiClient
{
    public static ApiClient Shared { get; } = new();

    private readonly CookieContainer _cookies = new();
    private readonly HttpClient _http;
    private readonly HttpClient _longHttp;

    public event Action? Unauthorized;

    private ApiClient()
    {
        var handler = new HttpClientHandler
        {
            CookieContainer = _cookies,
            UseCookies = true,
            AutomaticDecompression = DecompressionMethods.All,
            AllowAutoRedirect = true
        };
        _http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(60) };
        _http.DefaultRequestHeaders.TryAddWithoutValidation("Accept", "application/json, text/plain, */*");

        var longHandler = new HttpClientHandler
        {
            CookieContainer = _cookies,
            UseCookies = true,
            AutomaticDecompression = DecompressionMethods.All,
            AllowAutoRedirect = true
        };
        _longHttp = new HttpClient(longHandler) { Timeout = TimeSpan.FromSeconds(210) };
        _longHttp.DefaultRequestHeaders.TryAddWithoutValidation("Accept", "application/json, text/plain, */*");
    }

    public void ClearCookies()
    {
        try
        {
            var baseUrl = AppSession.Shared.ServerUrl;
            if (Uri.TryCreate(baseUrl, UriKind.Absolute, out var uri))
            {
                foreach (Cookie c in _cookies.GetCookies(uri))
                    c.Expired = true;
            }
        }
        catch { /* ignore */ }
    }

    /// <summary>Cookie header for server base URL (WS / WebView2).</summary>
    public string CookieHeaderForServer()
    {
        try
        {
            var baseUrl = AppSession.Shared.ServerUrl;
            if (!Uri.TryCreate(baseUrl, UriKind.Absolute, out var uri)) return "";
            return _cookies.GetCookieHeader(uri) ?? "";
        }
        catch
        {
            return "";
        }
    }

    public Uri MakeUrl(string baseUrl, string path, IReadOnlyDictionary<string, string>? query = null)
    {
        baseUrl = AppSession.Normalize(baseUrl).TrimEnd('/');
        if (string.IsNullOrWhiteSpace(path)) path = "/";
        if (!path.StartsWith('/')) path = "/" + path;

        if (query is { Count: > 0 })
        {
            var parts = query.Select(kv =>
                $"{Uri.EscapeDataString(kv.Key)}={Uri.EscapeDataString(kv.Value ?? "")}");
            path += (path.Contains('?', StringComparison.Ordinal) ? "&" : "?") + string.Join("&", parts);
        }
        return new Uri(baseUrl + path);
    }

    public Uri MakeUrl(string path, IReadOnlyDictionary<string, string>? query = null) =>
        MakeUrl(AppSession.Shared.ServerUrl, path, query);

    public async Task<byte[]> GetJsonAsync(
        string path,
        IReadOnlyDictionary<string, string>? query = null,
        bool longTimeout = false,
        CancellationToken ct = default)
    {
        var url = MakeUrl(path, query);
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.TryAddWithoutValidation("Accept", "application/json");
        req.Headers.TryAddWithoutValidation("X-Requested-With", "XMLHttpRequest");
        AttachCookie(req);
        var client = longTimeout ? _longHttp : _http;
        using var resp = await client.SendAsync(req, ct).ConfigureAwait(false);
        var data = await resp.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
        EnsureSuccess(resp, data);
        return data;
    }

    public async Task<string> GetHtmlAsync(string path, CancellationToken ct = default)
    {
        var url = MakeUrl(path);
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.TryAddWithoutValidation("Accept", "text/html");
        AttachCookie(req);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        var data = await resp.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
        if ((int)resp.StatusCode is < 200 or >= 400)
            throw ApiError.Server($"HTTP {(int)resp.StatusCode}");
        return Encoding.UTF8.GetString(data);
    }

    public async Task<byte[]> PostJsonAsync(
        string path,
        object? body = null,
        bool longTimeout = false,
        CancellationToken ct = default) =>
        await SendJsonAsync(HttpMethod.Post, path, body, longTimeout, ct).ConfigureAwait(false);

    public Task<byte[]> PutJsonAsync(string path, object? body = null, CancellationToken ct = default) =>
        SendJsonAsync(HttpMethod.Put, path, body, false, ct);

    public Task<byte[]> DeleteJsonAsync(string path, object? body = null, CancellationToken ct = default) =>
        SendJsonAsync(HttpMethod.Delete, path, body, false, ct);

    private async Task<byte[]> SendJsonAsync(
        HttpMethod method,
        string path,
        object? body,
        bool longTimeout,
        CancellationToken ct)
    {
        var url = MakeUrl(path);
        using var req = new HttpRequestMessage(method, url);
        req.Headers.TryAddWithoutValidation("Accept", "application/json");
        req.Headers.TryAddWithoutValidation("X-Requested-With", "XMLHttpRequest");
        if (body != null || method == HttpMethod.Post || method == HttpMethod.Put)
        {
            var json = body == null
                ? "{}"
                : body is string s
                    ? s
                    : Encoding.UTF8.GetString(JsonUtil.Serialize(body));
            req.Content = new StringContent(json, Encoding.UTF8, "application/json");
        }
        AttachCookie(req);
        var client = longTimeout ? _longHttp : _http;
        using var resp = await client.SendAsync(req, ct).ConfigureAwait(false);
        var data = await resp.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
        EnsureSuccess(resp, data);
        return data;
    }

    public async Task<(byte[] data, HttpStatusCode status)> PostFormAsync(
        string path,
        IReadOnlyDictionary<string, string> fields,
        CancellationToken ct = default)
    {
        var url = MakeUrl(path);
        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Headers.TryAddWithoutValidation("Accept", "application/json");
        req.Headers.TryAddWithoutValidation("X-Requested-With", "XMLHttpRequest");
        req.Content = new FormUrlEncodedContent(fields);
        AttachCookie(req);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        var data = await resp.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
        if (resp.StatusCode == HttpStatusCode.Unauthorized)
        {
            Unauthorized?.Invoke();
            throw ApiError.Unauthorized();
        }
        return (data, resp.StatusCode);
    }

    public async Task<(byte[] data, string? filename, IReadOnlyDictionary<string, string> headers)> DownloadAsync(
        string path,
        IReadOnlyDictionary<string, string>? query = null,
        CancellationToken ct = default)
    {
        var url = MakeUrl(path, query);
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.TryAddWithoutValidation("Accept", "*/*");
        req.Headers.TryAddWithoutValidation("X-Requested-With", "XMLHttpRequest");
        AttachCookie(req);
        using var resp = await _longHttp.SendAsync(req, ct).ConfigureAwait(false);
        var data = await resp.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
        EnsureSuccess(resp, data);
        string? filename = null;
        if (resp.Content.Headers.ContentDisposition?.FileName != null)
            filename = resp.Content.Headers.ContentDisposition.FileName.Trim('"');
        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var h in resp.Headers)
            headers[h.Key] = string.Join(",", h.Value);
        foreach (var h in resp.Content.Headers)
            headers[h.Key] = string.Join(",", h.Value);
        return (data, filename, headers);
    }

    public async Task<byte[]> PostMultipartAsync(
        string path,
        IReadOnlyDictionary<string, string> fields,
        string fileFieldName,
        string filePath,
        CancellationToken ct = default)
    {
        var url = MakeUrl(path);
        using var content = new MultipartFormDataContent();
        foreach (var (k, v) in fields)
            content.Add(new StringContent(v ?? ""), k);
        await using var fs = File.OpenRead(filePath);
        var streamContent = new StreamContent(fs);
        streamContent.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/octet-stream");
        content.Add(streamContent, fileFieldName, Path.GetFileName(filePath));

        using var req = new HttpRequestMessage(HttpMethod.Post, url) { Content = content };
        req.Headers.TryAddWithoutValidation("Accept", "application/json");
        req.Headers.TryAddWithoutValidation("X-Requested-With", "XMLHttpRequest");
        AttachCookie(req);
        using var resp = await _longHttp.SendAsync(req, ct).ConfigureAwait(false);
        var data = await resp.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
        EnsureSuccess(resp, data);
        return data;
    }

    public async Task<string> GetStringAsync(string path, CancellationToken ct = default)
    {
        var url = MakeUrl(path);
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        AttachCookie(req);
        using var resp = await _http.SendAsync(req, ct).ConfigureAwait(false);
        var data = await resp.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
        if ((int)resp.StatusCode is < 200 or >= 300)
            throw ApiError.Server($"HTTP {(int)resp.StatusCode}");
        return Encoding.UTF8.GetString(data);
    }

    /// <summary>SSE stream; yields each data line. Cancel via token.</summary>
    public async IAsyncEnumerable<string> StreamSseAsync(
        string path,
        IReadOnlyDictionary<string, string>? query = null,
        [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken ct = default)
    {
        await foreach (var (_, data) in StreamSseEventsAsync(path, query, ct).ConfigureAwait(false))
            yield return data;
    }

    /// <summary>SSE with event name (default "message"). Align Mac TenantSSEClient.</summary>
    public async IAsyncEnumerable<(string Event, string Data)> StreamSseEventsAsync(
        string path,
        IReadOnlyDictionary<string, string>? query = null,
        [System.Runtime.CompilerServices.EnumeratorCancellation] CancellationToken ct = default)
    {
        var url = MakeUrl(path, query);
        using var req = new HttpRequestMessage(HttpMethod.Get, url);
        req.Headers.TryAddWithoutValidation("Accept", "text/event-stream");
        req.Headers.TryAddWithoutValidation("Cache-Control", "no-cache");
        req.Headers.TryAddWithoutValidation("X-Requested-With", "XMLHttpRequest");
        AttachCookie(req);

        using var resp = await _longHttp.SendAsync(req, HttpCompletionOption.ResponseHeadersRead, ct)
            .ConfigureAwait(false);
        if (resp.StatusCode == System.Net.HttpStatusCode.Unauthorized)
        {
            Unauthorized?.Invoke();
            throw ApiError.Unauthorized();
        }
        resp.EnsureSuccessStatusCode();
        await using var stream = await resp.Content.ReadAsStreamAsync(ct).ConfigureAwait(false);
        using var reader = new System.IO.StreamReader(stream, Encoding.UTF8);
        var ev = "message";
        while (!ct.IsCancellationRequested)
        {
            var line = await reader.ReadLineAsync(ct).ConfigureAwait(false);
            if (line == null) yield break;
            if (line.Length == 0)
            {
                ev = "message";
                continue;
            }
            if (line.StartsWith(':')) continue;
            if (line.StartsWith("event:", StringComparison.OrdinalIgnoreCase))
            {
                ev = line[6..].Trim();
                if (string.IsNullOrEmpty(ev)) ev = "message";
                continue;
            }
            if (line.StartsWith("id:", StringComparison.OrdinalIgnoreCase)) continue;
            if (line.StartsWith("data:", StringComparison.OrdinalIgnoreCase))
            {
                var data = line[5..].TrimStart();
                if (!string.IsNullOrEmpty(data))
                    yield return (ev, data);
                continue;
            }
            if (!string.IsNullOrWhiteSpace(line))
                yield return (ev, line);
        }
    }

    /// <summary>POST JSON and return binary body + optional filename (SFTP download).</summary>
    public async Task<(byte[] data, string? filename)> PostDownloadAsync(
        string path,
        object body,
        CancellationToken ct = default)
    {
        var url = MakeUrl(path);
        using var req = new HttpRequestMessage(HttpMethod.Post, url);
        req.Headers.TryAddWithoutValidation("Accept", "application/octet-stream, */*");
        req.Headers.TryAddWithoutValidation("X-Requested-With", "XMLHttpRequest");
        var json = Encoding.UTF8.GetString(JsonUtil.Serialize(body));
        req.Content = new StringContent(json, Encoding.UTF8, "application/json");
        AttachCookie(req);
        using var resp = await _longHttp.SendAsync(req, ct).ConfigureAwait(false);
        var data = await resp.Content.ReadAsByteArrayAsync(ct).ConfigureAwait(false);
        EnsureSuccess(resp, data);
        string? filename = null;
        if (resp.Content.Headers.ContentDisposition?.FileNameStar != null)
            filename = resp.Content.Headers.ContentDisposition.FileNameStar;
        else if (resp.Content.Headers.ContentDisposition?.FileName != null)
            filename = resp.Content.Headers.ContentDisposition.FileName.Trim('"');
        if (string.IsNullOrEmpty(filename)
            && resp.Content.Headers.TryGetValues("Content-Disposition", out var cds))
        {
            var cd = string.Join(" ", cds);
            var idx = cd.IndexOf("filename*=UTF-8''", StringComparison.OrdinalIgnoreCase);
            if (idx >= 0)
            {
                var raw = cd[(idx + "filename*=UTF-8''".Length)..].Trim().TrimEnd(';');
                filename = Uri.UnescapeDataString(raw);
            }
        }
        return (data, filename);
    }

    public async Task<bool> PingLoginAsync(CancellationToken ct = default)
    {
        try
        {
            using var cts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            cts.CancelAfter(TimeSpan.FromSeconds(2));
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };
            var url = MakeUrl(AppSession.Shared.ServerUrl, "/login");
            using var resp = await http.GetAsync(url, cts.Token).ConfigureAwait(false);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private void AttachCookie(HttpRequestMessage req)
    {
        if (req.RequestUri == null) return;
        var header = _cookies.GetCookieHeader(req.RequestUri);
        if (!string.IsNullOrEmpty(header))
            req.Headers.TryAddWithoutValidation("Cookie", header);
    }

    private void EnsureSuccess(HttpResponseMessage resp, byte[] data)
    {
        if (resp.StatusCode == HttpStatusCode.Unauthorized)
        {
            Unauthorized?.Invoke();
            throw ApiError.Unauthorized();
        }

        var code = (int)resp.StatusCode;
        if (code is >= 200 and < 300) return;
        throw ApiError.Server(FriendlyServerMessage(data, code));
    }

    private static string FriendlyServerMessage(byte[] data, int status)
    {
        if (status == 404)
            return "接口不存在。请确认远程服务器已升级到与客户端匹配的版本。";

        try
        {
            var root = JsonUtil.Obj(data);
            if (root != null)
            {
                var msg = JsonUtil.Str(root, "message");
                if (string.IsNullOrEmpty(msg)) msg = JsonUtil.Str(root, "msg");
                if (string.IsNullOrEmpty(msg)) msg = JsonUtil.Str(root, "error");
                if (!string.IsNullOrEmpty(msg) && !IsGenericNotFound(msg))
                    return msg;
            }
        }
        catch { /* ignore */ }

        var raw = Encoding.UTF8.GetString(data).Trim();
        if (!string.IsNullOrEmpty(raw) && raw.Length < 240 && !IsGenericNotFound(raw))
            return raw;
        return "HTTP " + status;
    }

    private static bool IsGenericNotFound(string s)
    {
        var t = s.Trim().ToLowerInvariant();
        return t is "not found" or "notfound" || t.Contains("whitelabel error");
    }

    public static void EnsureApiOk(byte[] data, string fallback)
    {
        if (data.Length == 0) return;
        var root = JsonUtil.Obj(data);
        if (root == null) return;
        if (root.TryGetValue("success", out var suc) && !JsonUtil.Bool(suc))
            throw ApiError.Server(string.IsNullOrEmpty(JsonUtil.Str(root, "message"))
                ? fallback
                : JsonUtil.Str(root, "message"));
        if (root.TryGetValue("ok", out var ok) && !JsonUtil.Bool(ok))
            throw ApiError.Server(string.IsNullOrEmpty(JsonUtil.Str(root, "message"))
                ? fallback
                : JsonUtil.Str(root, "message"));
        var status = JsonUtil.Str(root, "status").ToLowerInvariant();
        if (status == "error")
            throw ApiError.Server(string.IsNullOrEmpty(JsonUtil.Str(root, "message"))
                ? fallback
                : JsonUtil.Str(root, "message"));
    }

    public static (bool ok, string message) SuccessMessage(byte[] data, string fallback)
    {
        var root = JsonUtil.Obj(data);
        if (root == null) return (true, fallback);
        if (root.TryGetValue("status", out _))
        {
            var st = JsonUtil.Str(root, "status").ToLowerInvariant();
            var msg = JsonUtil.Str(root, "message");
            if (string.IsNullOrEmpty(msg)) msg = fallback;
            return (st == "success", msg);
        }
        if (root.TryGetValue("success", out var suc))
        {
            var ok = JsonUtil.Bool(suc);
            var msg = JsonUtil.Str(root, "message");
            if (string.IsNullOrEmpty(msg)) msg = ok ? fallback : "失败";
            return (ok, msg);
        }
        return (true, fallback);
    }
}

public sealed class ApiEnvelope<T>
{
    public bool Success { get; set; }
    public string? Message { get; set; }
    public T? Data { get; set; }
    public int? Code { get; set; }
}
