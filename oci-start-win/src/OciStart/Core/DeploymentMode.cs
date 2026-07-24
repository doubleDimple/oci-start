namespace OciStart.Core;

/// <summary>Local embedded backend vs already-deployed remote server.</summary>
public enum DeploymentMode
{
    Local,
    Remote
}

public static class DeploymentModeExtensions
{
    public static bool IsRemote(this DeploymentMode mode) => mode == DeploymentMode.Remote;

    public static string ToStorage(this DeploymentMode mode) =>
        mode == DeploymentMode.Remote ? "remote" : "local";

    public static DeploymentMode FromStorage(string? raw) =>
        string.Equals(raw, "remote", StringComparison.OrdinalIgnoreCase)
            ? DeploymentMode.Remote
            : DeploymentMode.Local;
}
