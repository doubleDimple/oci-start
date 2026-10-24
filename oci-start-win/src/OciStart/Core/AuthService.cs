using System.Net;
using System.Text.Json;

namespace OciStart.Core;

/// <summary>Login / logout / session probe — align Mac AuthService.</summary>
public sealed class AuthService
{
    private readonly ApiClient _api = ApiClient.Shared;

    public sealed class LoginResult
    {
        public bool? Success { get; set; }
        public string? RedirectUrl { get; set; }
        public string? Message { get; set; }
    }

    public async Task LoginAsync(
        string username,
        string password,
        string? verificationCode = null,
        string? mfaCode = null,
        bool rememberMe = true,
        CancellationToken ct = default)
    {
        var config = await _api.GetLoginBootstrapAsync(ct).ConfigureAwait(false);
        if (config.TurnstileEnabled)
            throw ApiError.Server("服务器已启用人机验证，请在浏览器中登录。");
        string encrypted;
        if (config.PublicKey != null)
            encrypted = RsaHelper.Encrypt(password, config.PublicKey)
                ?? throw ApiError.Server("登录公钥无效，请重试。");
        else if (config.UsesLegacyHtml)
            encrypted = password;
        else
            throw ApiError.InvalidResponse();

        var fields = new Dictionary<string, string>
        {
            ["username"] = username,
            ["password"] = encrypted,
            ["remember-me"] = rememberMe ? "true" : "false"
        };
        if (!string.IsNullOrWhiteSpace(verificationCode))
            fields["verificationCode"] = verificationCode!;
        if (!string.IsNullOrWhiteSpace(mfaCode))
            fields["mfaCode"] = mfaCode!;

        var (data, status) = await _api.PostFormAsync("/perform_login", fields, ct).ConfigureAwait(false);
        if (status == HttpStatusCode.Unauthorized)
        {
            var partial = JsonUtil.Deserialize<LoginResult>(data);
            throw ApiError.Server(partial?.Message ?? "用户名或密码错误");
        }

        if ((int)status is < 200 or >= 300)
            throw ApiError.Server($"登录失败 HTTP {(int)status}");

        if (data.Length == 0) return;

        var result = JsonUtil.Deserialize<LoginResult>(data);
        if (result?.Success == false)
            throw ApiError.Server(result.Message ?? "登录失败");
    }

    public async Task LogoutAsync(CancellationToken ct = default)
    {
        try
        {
            await _api.GetHtmlAsync("/logout", ct).ConfigureAwait(false);
        }
        catch
        {
            // best-effort
        }
        finally
        {
            _api.ClearCookies();
        }
    }

    public async Task<bool> ValidateSessionAsync(CancellationToken ct = default)
    {
        try
        {
            var data = await _api.GetJsonAsync("/api/userInfo", ct: ct).ConfigureAwait(false);
            var body = JsonUtil.Obj(data);
            if (body == null || !body.TryGetValue("success", out var success)
                || success.ValueKind != JsonValueKind.True || JsonUtil.Int(body, "code") != 200
                || !body.TryGetValue("data", out var user) || user.ValueKind != JsonValueKind.Object)
                return false;
            return user.TryGetProperty("username", out var username)
                && username.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(username.GetString());
        }
        catch
        {
            return false;
        }
    }
}
