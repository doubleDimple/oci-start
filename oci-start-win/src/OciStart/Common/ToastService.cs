using System.Windows;

namespace OciStart.Common;

/// <summary>Simple toast / message host (align Mac ToastCenter).</summary>
public static class ToastService
{
    public static void Info(string message) =>
        Show("提示", message, MessageBoxImage.Information);

    public static void Success(string message) =>
        Show("成功", message, MessageBoxImage.Information);

    public static void Error(string message) =>
        Show("错误", message, MessageBoxImage.Warning);

    private static void Show(string title, string message, MessageBoxImage icon)
    {
        var app = Application.Current;
        if (app?.Dispatcher.CheckAccess() == false)
        {
            app.Dispatcher.Invoke(() => MessageBox.Show(message, title, MessageBoxButton.OK, icon));
            return;
        }
        MessageBox.Show(message, title, MessageBoxButton.OK, icon);
    }
}
