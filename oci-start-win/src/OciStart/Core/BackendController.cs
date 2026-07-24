using System.ComponentModel;
using System.Diagnostics;
using System.Net.Http;
using System.Runtime.CompilerServices;
using System.Text;

namespace OciStart.Core;

/// <summary>
/// Optional embedded Spring Boot. Dev without jar/jre can treat external :9856 as ready.
/// Mirrors oci-start-mac BackendController.
/// </summary>
public sealed class BackendController : INotifyPropertyChanged
{
    public static BackendController Shared { get; } = new();

    private readonly object _processLock = new();
    private Process? _process;
    private long _startEpoch;
    private BackendState _state = BackendState.Idle;

    private BackendController() { }

    public event PropertyChangedEventHandler? PropertyChanged;

    public BackendState State
    {
        get => _state;
        private set
        {
            _state = value;
            OnPropertyChanged();
            OnPropertyChanged(nameof(IsReadyForLogin));
            OnPropertyChanged(nameof(StatusText));
        }
    }

    public bool IsReadyForLogin => State.IsReady;

    public string StatusText => State.Status switch
    {
        BackendStatus.Idle => "未启动",
        BackendStatus.Starting => "正在启动后端…",
        BackendStatus.Ready => "后端就绪",
        BackendStatus.Failed => State.ErrorMessage ?? "后端失败",
        _ => ""
    };

    public async Task StartAsync(CancellationToken ct = default)
    {
        if (State.Status is BackendStatus.Ready or BackendStatus.Starting)
            return;

        State = BackendState.Starting;
        var epoch = Interlocked.Increment(ref _startEpoch);

        var probe = $"http://127.0.0.1:{AppPaths.DefaultPort}/login";
        if (await PingAsync(probe, ct).ConfigureAwait(false))
        {
            if (epoch != Interlocked.Read(ref _startEpoch)) return;
            State = BackendState.Ready;
            AppendLog($"port {AppPaths.DefaultPort} already up → ready");
            return;
        }

        var java = AppPaths.ResolveJavaExecutable();
        var jar = AppPaths.ResolveBundledServerJar();
        if (java == null || jar == null)
        {
            // Xcode/dev equivalent: no embedded runtime → external mode ready
            if (epoch != Interlocked.Read(ref _startEpoch)) return;
            State = BackendState.Ready;
            AppendLog("no embedded jre/jar → external mode ready");
            return;
        }

        var dataDir = AppPaths.DataDir;
        var uploadDir = AppPaths.UploadDir;
        var dbFile = Path.Combine(dataDir, "vps_db").Replace('\\', '/');
        var dbUrl = $"jdbc:h2:file:{dbFile};DB_CLOSE_ON_EXIT=FALSE;MODE=MySQL";

        var logFile = AppPaths.BackendLogFile;
        try
        {
            await File.AppendAllTextAsync(
                logFile,
                $"{Environment.NewLine}---- start {DateTime.Now:O} ----{Environment.NewLine}",
                ct).ConfigureAwait(false);
        }
        catch
        {
            // ignore log header failures
        }

        var psi = new ProcessStartInfo
        {
            FileName = java,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            WorkingDirectory = dataDir,
            StandardOutputEncoding = Encoding.UTF8,
            StandardErrorEncoding = Encoding.UTF8
        };
        psi.ArgumentList.Add("-Xmx512m");
        psi.ArgumentList.Add("-Dfile.encoding=UTF-8");
        psi.ArgumentList.Add($"-Dserver.port={AppPaths.DefaultPort}");
        psi.ArgumentList.Add($"-Dspring.datasource.url={dbUrl}");
        psi.ArgumentList.Add("-Dspring.datasource.driver-class-name=org.h2.Driver");
        psi.ArgumentList.Add($"-DbaseFile.filePath={uploadDir.TrimEnd('\\')}/");
        psi.ArgumentList.Add("-jar");
        psi.ArgumentList.Add(jar);

        Process proc;
        try
        {
            proc = new Process { StartInfo = psi, EnableRaisingEvents = true };
            proc.OutputDataReceived += (_, e) =>
            {
                if (e.Data != null) TryAppendBackendLog(e.Data);
            };
            proc.ErrorDataReceived += (_, e) =>
            {
                if (e.Data != null) TryAppendBackendLog(e.Data);
            };
            if (!proc.Start())
                throw new InvalidOperationException("Process.Start returned false");
            proc.BeginOutputReadLine();
            proc.BeginErrorReadLine();
        }
        catch (Exception ex)
        {
            if (epoch != Interlocked.Read(ref _startEpoch)) return;
            State = BackendState.Failed("启动 Java 失败：" + ex.Message);
            AppendLog("spawn failed: " + ex);
            return;
        }

        lock (_processLock)
        {
            _process = proc;
        }

        AppendLog($"spawned java pid={proc.Id} jar={Path.GetFileName(jar)}");

        for (var i = 0; i < 90; i++)
        {
            await Task.Delay(1000, ct).ConfigureAwait(false);
            if (epoch != Interlocked.Read(ref _startEpoch))
            {
                AppendLog($"start cancelled after {i + 1}s");
                return;
            }

            if (await PingAsync(probe, ct).ConfigureAwait(false))
            {
                if (epoch != Interlocked.Read(ref _startEpoch)) return;
                State = BackendState.Ready;
                AppendLog($"ready after {i + 1}s");
                return;
            }

            if (proc.HasExited)
            {
                if (epoch != Interlocked.Read(ref _startEpoch)) return;
                State = BackendState.Failed(
                    $"后端进程退出 (code={proc.ExitCode})，见 %USERPROFILE%\\.ocistart\\backend.log");
                AppendLog($"java exited code={proc.ExitCode}");
                return;
            }
        }

        if (epoch != Interlocked.Read(ref _startEpoch)) return;
        State = BackendState.Failed("后端启动超时（90 秒），见 backend.log");
        AppendLog("timeout 90s");
    }

    public void Stop()
    {
        AppendLog("stop requested");
        Interlocked.Increment(ref _startEpoch);

        Process? proc;
        lock (_processLock)
        {
            proc = _process;
            _process = null;
        }

        if (proc != null)
        {
            try
            {
                if (!proc.HasExited)
                {
                    AppendLog($"terminating tracked java pid={proc.Id}");
                    proc.Kill(entireProcessTree: true);
                    proc.WaitForExit(3000);
                }
            }
            catch (Exception ex)
            {
                AppendLog("terminate error: " + ex.Message);
            }
            finally
            {
                proc.Dispose();
            }
        }

        State = BackendState.Idle;
        AppendLog("stop finished → state=idle");
    }

    private static async Task<bool> PingAsync(string url, CancellationToken ct)
    {
        try
        {
            using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };
            using var resp = await http.GetAsync(url, ct).ConfigureAwait(false);
            return true;
        }
        catch
        {
            return false;
        }
    }

    private static void TryAppendBackendLog(string line)
    {
        try
        {
            File.AppendAllText(AppPaths.BackendLogFile, line + Environment.NewLine);
        }
        catch
        {
            // ignore
        }
    }

    private static void AppendLog(string msg)
    {
        try
        {
            var line = $"{DateTime.Now:O}  {msg}{Environment.NewLine}";
            File.AppendAllText(AppPaths.ControllerLogFile, line);
        }
        catch
        {
            // ignore
        }
    }

    private void OnPropertyChanged([CallerMemberName] string? name = null) =>
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}
