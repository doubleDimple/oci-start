namespace OciStart.Core;

/// <summary>
/// Runtime paths. Data dir must avoid problematic characters for H2/JDBC
/// (align Mac: use ~/.ocistart style path under user profile).
/// </summary>
public static class AppPaths
{
    public const int DefaultPort = 9856;
    public const string LocalDefaultUrl = "http://localhost:9856";

    /// <summary>%USERPROFILE%\.ocistart — DB, upload, optional upgraded server.jar, logs.</summary>
    public static string DataDir
    {
        get
        {
            var dir = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
                ".ocistart");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string UploadDir
    {
        get
        {
            var dir = Path.Combine(DataDir, "upload");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string BackendLogFile => Path.Combine(DataDir, "backend.log");

    public static string ControllerLogFile => Path.Combine(DataDir, "backend-controller.log");

    /// <summary>Optional hot-upgraded jar preferred over bundled.</summary>
    public static string UpgradedServerJar => Path.Combine(DataDir, "server.jar");

    /// <summary>Directory of the running exe (publish / installed layout).</summary>
    public static string AppDirectory =>
        AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar);

    public static string? ResolveBundledServerJar()
    {
        var upgraded = UpgradedServerJar;
        if (File.Exists(upgraded))
            return upgraded;

        var bundled = Path.Combine(AppDirectory, "server.jar");
        return File.Exists(bundled) ? bundled : null;
    }

    public static string? ResolveJavaExecutable()
    {
        var candidates = new[]
        {
            Path.Combine(AppDirectory, "jre", "bin", "java.exe"),
            Path.Combine(AppDirectory, "jre-x86_64", "bin", "java.exe"),
            Path.Combine(AppDirectory, "runtime", "bin", "java.exe")
        };

        foreach (var path in candidates)
        {
            if (File.Exists(path))
                return path;
        }

        // Dev fallback: JAVA_HOME or PATH
        var home = Environment.GetEnvironmentVariable("JAVA_HOME");
        if (!string.IsNullOrWhiteSpace(home))
        {
            var fromHome = Path.Combine(home, "bin", "java.exe");
            if (File.Exists(fromHome))
                return fromHome;
        }

        return null;
    }
}
