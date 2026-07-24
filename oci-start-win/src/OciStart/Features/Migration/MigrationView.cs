using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.Migration;

public sealed class MigrationView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly TextBox _masterKey = FormFieldFactory.TextField(watermark: "导入时填写 Master Key");
    private readonly TextBlock _exportKey = new()
    {
        TextWrapping = TextWrapping.Wrap,
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        Margin = new Thickness(0, 8, 0, 0)
    };

    public MigrationView()
    {
        _scaffold.Title = "数据迁移";
        _scaffold.Subtitle = "加密导出 / 导入";

        var accent = Color.FromRgb(0x3B, 0x82, 0xF6);
        var exportCard = new ModuleSettingsCard("导出", "生成加密备份与 Master Key", "⇪", accent, false);
        exportCard.SetBody(
            new TextBlock
            {
                Text = "导出后请妥善保存 Master Key，丢失将无法导入。",
                TextWrapping = TextWrapping.Wrap,
                Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
            },
            _exportKey);
        exportCard.SetFooter(FormFieldFactory.Primary("导出加密包", async (_, _) => await ExportAsync()));

        var importCard = new ModuleSettingsCard("导入", "从加密包恢复数据", "⇩", accent, false);
        importCard.SetBody(FormFieldFactory.Labeled("Master Key", _masterKey));
        importCard.SetFooter(FormFieldFactory.Primary("选择文件并导入", async (_, _) => await ImportAsync()));

        var scroll = new ScrollViewer
        {
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            Padding = new Thickness(16),
            Content = new EqualHeightCardRow(exportCard, importCard)
        };
        _scaffold.SetBody(scroll);
        Content = _scaffold;
    }

    private async Task ExportAsync()
    {
        try
        {
            _scaffold.SetLoading(true);
            var (data, filename, headers) = await _api.DownloadAsync("/migration/exportEncrypted").ConfigureAwait(true);
            headers.TryGetValue("X-MASTER-KEY", out var key);
            if (string.IsNullOrEmpty(key))
                headers.TryGetValue("x-master-key", out key);
            _exportKey.Text = string.IsNullOrEmpty(key) ? "（响应未包含 Master Key 头，请查看服务端日志）" : "Master Key: " + key;

            var dlg = new SaveFileDialog
            {
                FileName = filename ?? $"oci-start_migration_{DateTimeOffset.Now.ToUnixTimeSeconds()}.enc",
                Filter = "Encrypted|*.enc|All|*.*"
            };
            if (dlg.ShowDialog() == true)
            {
                await File.WriteAllBytesAsync(dlg.FileName, data).ConfigureAwait(true);
                ToastService.Success("已导出：" + dlg.FileName);
            }
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
        finally
        {
            _scaffold.SetLoading(false);
        }
    }

    private async Task ImportAsync()
    {
        var dlg = new OpenFileDialog { Filter = "Encrypted|*.enc;*.bin|All|*.*" };
        if (dlg.ShowDialog() != true) return;
        try
        {
            _scaffold.SetLoading(true);
            var fields = new Dictionary<string, string>();
            if (!string.IsNullOrWhiteSpace(_masterKey.Text))
                fields["masterKey"] = _masterKey.Text.Trim();
            var raw = await _api.PostMultipartAsync(
                "/migration/importEncrypted",
                fields,
                "file",
                dlg.FileName).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "导入成功");
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Success(r.message);
        }
        catch (Exception ex)
        {
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
        finally
        {
            _scaffold.SetLoading(false);
        }
    }
}
