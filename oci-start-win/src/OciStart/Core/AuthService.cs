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
        var html = await _api.GetHtmlAsync("/login", ct).ConfigureAwait(false);
        var pub = RsaHelper.ExtractPublicKeyFromLoginHtml(html);
        var encrypted = pub != null
            ? (RsaHelper.Encrypt(password, pub) ?? password)
            : password;

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
            var data = await _api.GetJsonAsync("/boot/dashboard-stats", ct: ct).ConfigureAwait(false);
            return data.Length > 0;
        }
        catch (ApiError e) when (e.ErrorKind == ApiError.Kind.Unauthorized)
        {
            return false;
        }
        catch
        {
            try
            {
                var html = await _api.GetHtmlAsync("/index", ct).ConfigureAwait(false);
                return !html.Contains("/login", StringComparison.OrdinalIgnoreCase)
                       || html.Contains("dashboard", StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                return false;
            }
        }
    }
}
