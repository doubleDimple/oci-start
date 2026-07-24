using System.ComponentModel;
using System.Runtime.CompilerServices;

namespace OciStart.Core;

/// <summary>
/// Authentication + shell chrome state (no business list caches).
/// Mirrors oci-start-mac AppSession.
/// </summary>
public sealed class AppSession : INotifyPropertyChanged
{
    public static AppSession Shared { get; } = new();

    private const string ServerUrlKey = "serverURL";
    private const string RemoteUrlKey = "remoteServerURL";
    private const string DeploymentModeKey = "deploymentMode";
    private const string DeploymentChosenKey = "deploymentModeChosen";
    private const string UserKey = "lastUsername";
    private const string CloudKey = "cloudProvider";

    private bool _isLoggedIn;
    private bool _isBusy;
    private string? _lastError;
    private string _username = "";
    private string _siteName = "OCI-START";
    private int _cloudProvider = 1;
    private DeploymentMode _deploymentMode = DeploymentMode.Local;
    private bool _modeActivated;

    private AppSession()
    {
        _username = SettingsStore.GetString(UserKey) ?? "";
        var storedCloud = SettingsStore.GetInt(CloudKey);
        _cloudProvider = storedCloud == 0 ? 1 : storedCloud;
        _deploymentMode = DeploymentModeExtensions.FromStorage(SettingsStore.GetString(DeploymentModeKey));
        AlignServerUrlForMode(_deploymentMode);
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public bool IsLoggedIn
    {
        get => _isLoggedIn;
        private set => SetField(ref _isLoggedIn, value);
    }

    public bool IsBusy
    {
        get => _isBusy;
        private set => SetField(ref _isBusy, value);
    }

    public string? LastError
    {
        get => _lastError;
        set => SetField(ref _lastError, value);
    }

    public string Username
    {
        get => _username;
        private set
        {
            if (SetField(ref _username, value))
                SettingsStore.SetString(UserKey, value);
        }
    }

    public string SiteName
    {
        get => _siteName;
        set => SetField(ref _siteName, value);
    }

    /// <summary>1=Oracle 2=GCP 3=Azure 4=AWS</summary>
    public int CloudProvider
    {
        get => _cloudProvider;
        set
        {
            if (SetField(ref _cloudProvider, value))
                SettingsStore.SetInt(CloudKey, value);
        }
    }

    public DeploymentMode DeploymentMode
    {
        get => _deploymentMode;
        private set => SetField(ref _deploymentMode, value);
    }

    /// <summary>This session has entered a chosen mode (first pick or restore).</summary>
    public bool ModeActivated
    {
        get => _modeActivated;
        private set => SetField(ref _modeActivated, value);
    }

    public bool HasChosenDeploymentMode => SettingsStore.GetBool(DeploymentChosenKey);

    public bool IsRemoteDeployment => DeploymentMode.IsRemote();

    public string ServerUrl
    {
        get => Normalize(SettingsStore.GetString(ServerUrlKey) ?? AppPaths.LocalDefaultUrl);
        set
        {
            var normalized = Normalize(value);
            SettingsStore.SetString(ServerUrlKey, normalized);
            if (!IsLocalServerUrl(normalized))
                SettingsStore.SetString(RemoteUrlKey, normalized);
            OnPropertyChanged();
        }
    }

    public string LastRemoteServerUrl
    {
        get
        {
            var raw = SettingsStore.GetString(RemoteUrlKey) ?? "";
            var n = Normalize(string.IsNullOrWhiteSpace(raw) ? "https://" : raw);
            return IsLocalServerUrl(n) ? "https://" : n;
        }
        set
        {
            var n = Normalize(value);
            if (IsLocalServerUrl(n)) return;
            SettingsStore.SetString(RemoteUrlKey, n);
            OnPropertyChanged();
        }
    }

    public string CloudProviderName => CloudProvider switch
    {
        2 => "Google Cloud",
        3 => "Azure",
        4 => "AWS",
        _ => "Oracle Cloud"
    };

    /// <summary>
    /// Switch deployment mode and align server URL.
    /// Does not start/stop Java — caller owns backend lifecycle.
    /// </summary>
    public void SetDeploymentMode(DeploymentMode mode, bool userChosen = true)
    {
        if (userChosen)
            SettingsStore.SetBool(DeploymentChosenKey, true);

        if (mode == DeploymentMode)
        {
            AlignServerUrlForMode(mode);
            ModeActivated = true;
            return;
        }

        if (DeploymentMode == DeploymentMode.Remote && mode == DeploymentMode.Local)
        {
            if (!IsLocalServerUrl(ServerUrl))
                LastRemoteServerUrl = ServerUrl;
        }

        DeploymentMode = mode;
        SettingsStore.SetString(DeploymentModeKey, mode.ToStorage());
        AlignServerUrlForMode(mode);
        ModeActivated = true;
    }

    public void MarkLoggedIn(string username)
    {
        Username = username;
        IsLoggedIn = true;
        LastError = null;
    }

    public void Logout()
    {
        IsLoggedIn = false;
        LastError = null;
        ApiClient.Shared.ClearCookies();
    }

    public void SetBusy(bool busy) => IsBusy = busy;

    private void AlignServerUrlForMode(DeploymentMode mode)
    {
        switch (mode)
        {
            case DeploymentMode.Local:
                if (!IsLocalServerUrl(ServerUrl))
                    LastRemoteServerUrl = ServerUrl;
                SettingsStore.SetString(ServerUrlKey, AppPaths.LocalDefaultUrl);
                OnPropertyChanged(nameof(ServerUrl));
                break;
            case DeploymentMode.Remote:
                if (IsLocalServerUrl(ServerUrl))
                {
                    var restored = LastRemoteServerUrl;
                    SettingsStore.SetString(
                        ServerUrlKey,
                        restored == "https://" ? restored : Normalize(restored));
                    OnPropertyChanged(nameof(ServerUrl));
                }
                break;
        }
    }

    /// <summary>Keep scheme://host:port only — strip /login /index etc.</summary>
    public static string Normalize(string raw)
    {
        var s = (raw ?? "").Trim();
        if (string.IsNullOrEmpty(s))
            return AppPaths.LocalDefaultUrl;

        if (!s.Contains("://", StringComparison.Ordinal))
            s = "http://" + s;

        if (!Uri.TryCreate(s, UriKind.Absolute, out var uri) ||
            (uri.Scheme != Uri.UriSchemeHttp && uri.Scheme != Uri.UriSchemeHttps))
            return s.TrimEnd('/');

        var port = uri.IsDefaultPort ? "" : ":" + uri.Port;
        return $"{uri.Scheme}://{uri.Host}{port}";
    }

    public static bool IsLocalServerUrl(string url)
    {
        var n = Normalize(url);
        return n.StartsWith("http://localhost:", StringComparison.OrdinalIgnoreCase)
               || n.StartsWith("http://127.0.0.1:", StringComparison.OrdinalIgnoreCase)
               || string.Equals(n, "http://localhost", StringComparison.OrdinalIgnoreCase)
               || string.Equals(n, "http://127.0.0.1", StringComparison.OrdinalIgnoreCase);
    }

    private bool SetField<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
            return false;
        field = value;
        OnPropertyChanged(name);
        return true;
    }

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
