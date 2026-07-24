using System.Windows;
using OciStart.Core;

namespace OciStart;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        // Do NOT auto-start embedded Java here.
        // Align Mac: only start after user chose Local (or restored Local mode).
        _ = AppSession.Shared;
        _ = BackendController.Shared;
    }

    protected override void OnExit(ExitEventArgs e)
    {
        try
        {
            BackendController.Shared.Stop();
        }
        catch
        {
            // best-effort shutdown
        }

        base.OnExit(e);
    }
}
