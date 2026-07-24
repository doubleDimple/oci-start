using System.Windows.Controls;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;

namespace OciStart.Features.AiModels;

public sealed class AiConfigRow
{
    public string Id { get; set; } = "";
    public string Tenant { get; set; } = "";
    public string Model { get; set; } = "";
    public string Provider { get; set; } = "";
    public string Enabled { get; set; } = "";
}

public sealed class AiModelsView : UserControl
{
    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly DataGrid _grid = ListPageHelper.CreateGrid();
    private readonly ComboBox _tenantBox = new() { MinWidth = 200, Padding = new System.Windows.Thickness(8, 6, 8, 6) };
    private readonly ComboBox _modelBox = new() { MinWidth = 220, Padding = new System.Windows.Thickness(8, 6, 8, 6) };
    private List<(string id, string name)> _tenants = [];
    private List<(string id, string name, string provider)> _models = [];

    public AiModelsView()
    {
        _scaffold.Title = "OCI AI 管理";
        _scaffold.Subtitle = "Telegram AI 模型配置";
        _scaffold.SetToolbar(FormFieldFactory.Secondary("刷新配置", async (_, _) => await LoadConfigsAsync()));

        _grid.Columns.Add(ListPageHelper.Col("租户", nameof(AiConfigRow.Tenant), 120));
        _grid.Columns.Add(ListPageHelper.Col("模型", nameof(AiConfigRow.Model), star: true));
        _grid.Columns.Add(ListPageHelper.Col("Provider", nameof(AiConfigRow.Provider), 100));
        _grid.Columns.Add(ListPageHelper.Col("启用", nameof(AiConfigRow.Enabled), 60));

        var bar = ListPageHelper.TopBar(
            _tenantBox,
            FormFieldFactory.Secondary("加载模型", async (_, _) => await LoadModelsAsync()),
            _modelBox,
            FormFieldFactory.Primary("添加", async (_, _) => await AddAsync()),
            FormFieldFactory.Secondary("删除选中", async (_, _) => await DeleteSelectedAsync()));
        Content = ListPageHelper.Wrap(_scaffold, bar, _grid);
        Loaded += async (_, _) =>
        {
            await LoadTenantsAsync();
            await LoadConfigsAsync();
        };
    }

    private async Task LoadTenantsAsync()
    {
        try
        {
            var raw = await _api.GetJsonAsync("/system/ai/tenants").ConfigureAwait(true);
            var (rows, _, _, _) = JsonPage.Parse(raw);
            _tenants = rows.Select(m => (
                JsonPage.Pick(m, "id", "tenantId"),
                JsonPage.Pick(m, "name", "userName", "defName", "label")
            )).Where(t => !string.IsNullOrEmpty(t.Item1)).ToList();
            _tenantBox.ItemsSource = _tenants.Select(t => string.IsNullOrEmpty(t.name) ? t.id : t.name).ToList();
            if (_tenantBox.Items.Count > 0) _tenantBox.SelectedIndex = 0;
        }
        catch { /* optional */ }
    }

    private async Task LoadModelsAsync()
    {
        if (_tenantBox.SelectedIndex < 0 || _tenantBox.SelectedIndex >= _tenants.Count)
        {
            ToastService.Info("请选择租户");
            return;
        }
        try
        {
            var tid = _tenants[_tenantBox.SelectedIndex].id;
            var raw = await _api.GetJsonAsync("/system/ai/modelsByTenant", new Dictionary<string, string>
            {
                ["tenantId"] = tid
            }).ConfigureAwait(true);
            var (rows, _, _, _) = JsonPage.Parse(raw, ["content", "list", "data", "models"]);
            _models = rows.Select(m => (
                JsonPage.Pick(m, "id", "modelId"),
                JsonPage.Pick(m, "name", "modelName"),
                JsonPage.Pick(m, "provider")
            )).Where(x => !string.IsNullOrEmpty(x.Item1)).ToList();
            _modelBox.ItemsSource = _models.Select(m => m.name).ToList();
            if (_modelBox.Items.Count > 0) _modelBox.SelectedIndex = 0;
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task LoadConfigsAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var raw = await _api.GetJsonAsync("/system/telegramAiConfigs").ConfigureAwait(true);
            var (rows, _, _, _) = JsonPage.Parse(raw);
            _grid.ItemsSource = rows.Select(m => new AiConfigRow
            {
                Id = JsonPage.Pick(m, "id"),
                Tenant = JsonPage.Pick(m, "tenantId", "userName", "tenantName"),
                Model = JsonPage.Pick(m, "modelName", "model", "name"),
                Provider = JsonPage.Pick(m, "provider"),
                Enabled = JsonPage.Pick(m, "enabled")
            }).ToList();
        });

    private async Task AddAsync()
    {
        if (_tenantBox.SelectedIndex < 0 || _modelBox.SelectedIndex < 0 ||
            _modelBox.SelectedIndex >= _models.Count)
        {
            ToastService.Info("请选择租户与模型");
            return;
        }
        try
        {
            var tid = _tenants[_tenantBox.SelectedIndex].id;
            var model = _models[_modelBox.SelectedIndex];
            var raw = await _api.PostJsonAsync("/system/updateTelegramAiConfig", new
            {
                tenantId = tid,
                modelId = model.id,
                modelName = model.name,
                provider = string.IsNullOrEmpty(model.provider) ? "OCI" : model.provider,
                enabled = true,
                cloudType = 1
            }).ConfigureAwait(true);
            ApiClient.EnsureApiOk(raw, "添加失败");
            ToastService.Success("已添加");
            await LoadConfigsAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }

    private async Task DeleteSelectedAsync()
    {
        if (_grid.SelectedItem is not AiConfigRow row || string.IsNullOrEmpty(row.Id))
        {
            ToastService.Info("请先选择配置");
            return;
        }
        try
        {
            try
            {
                await _api.DeleteJsonAsync($"/system/deleteTelegramAiConfig/{row.Id}").ConfigureAwait(true);
            }
            catch
            {
                var raw = await _api.PostJsonAsync($"/system/deleteTelegramAiConfig/{row.Id}", new { })
                    .ConfigureAwait(true);
                ApiClient.EnsureApiOk(raw, "删除失败");
            }
            ToastService.Success("已删除");
            await LoadConfigsAsync();
        }
        catch (Exception ex) { ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message); }
    }
}
