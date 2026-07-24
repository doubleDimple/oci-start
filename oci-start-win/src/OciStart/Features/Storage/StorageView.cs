using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Microsoft.Win32;
using OciStart.Common;
using OciStart.Common.Components;
using OciStart.Core;
using OciStart.Features.Shared;

namespace OciStart.Features.Storage;

public sealed class BucketRow
{
    public string Name { get; set; } = "";
    public string Namespace { get; set; } = "";
    public string Access { get; set; } = "";
    public string Created { get; set; } = "";
}

public sealed class ObjectRow
{
    public string Name { get; set; } = "";
    public string Size { get; set; } = "";
    public string Time { get; set; } = "";
    public string Etag { get; set; } = "";
}

/// <summary>对象存储 — 对齐 Mac：租户 → Namespace → Bucket → 对象 + 写操作.</summary>
public sealed class StorageView : UserControl
{
    /// <summary>Align Mac StorageService: ≥50MB use multipart; 10MB chunks.</summary>
    private const long MultipartThreshold = 50L * 1024 * 1024;
    private const long ChunkSize = 10L * 1024 * 1024;

    private static readonly (string Title, string Value)[] AccessTypes =
    [
        ("私有", "NoPublicAccess"),
        ("公共读", "ObjectRead"),
        ("公共读(无列表)", "ObjectReadWithoutList")
    ];

    private readonly PageScaffold _scaffold = new();
    private readonly ApiClient _api = ApiClient.Shared;
    private readonly ComboBox _tenantBox = new() { MinWidth = 200, Padding = new Thickness(8, 6, 8, 6) };
    private readonly DataGrid _bucketGrid = ListPageHelper.CreateGrid();
    private readonly DataGrid _objectGrid = ListPageHelper.CreateGrid();
    private readonly TextBlock _nsText = new()
    {
        VerticalAlignment = VerticalAlignment.Center,
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        Margin = new Thickness(12, 0, 0, 0)
    };
    private readonly TextBlock _bucketHint = new()
    {
        VerticalAlignment = VerticalAlignment.Center,
        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
        Margin = new Thickness(12, 0, 0, 0),
        Text = "选中 Bucket 后加载对象"
    };

    private List<TenantRegionOption> _tenants = [];
    private string _ns = "";
    private string? _selectedBucket;

    public StorageView()
    {
        _scaffold.Title = "对象存储";
        _scaffold.Subtitle = "OCI Object Storage · Bucket / 对象";
        _scaffold.SetToolbar(
            FormFieldFactory.Secondary("刷新 Bucket", async (_, _) => await LoadBucketsAsync()),
            FormFieldFactory.Primary("创建 Bucket", async (_, _) => await CreateBucketAsync()),
            FormFieldFactory.Secondary("删除 Bucket", async (_, _) => await DeleteBucketAsync()),
            FormFieldFactory.Primary("上传", async (_, _) => await UploadObjectAsync()),
            FormFieldFactory.Secondary("下载", async (_, _) => await DownloadObjectAsync()),
            FormFieldFactory.Secondary("预览", async (_, _) => await PreviewObjectAsync()),
            FormFieldFactory.Secondary("预签名", async (_, _) => await PresignObjectAsync()),
            FormFieldFactory.Secondary("删除对象", async (_, _) => await DeleteObjectAsync()));

        _bucketGrid.Columns.Add(ListPageHelper.Col("Bucket", nameof(BucketRow.Name), star: true));
        _bucketGrid.Columns.Add(ListPageHelper.Col("Namespace", nameof(BucketRow.Namespace), 140));
        _bucketGrid.Columns.Add(ListPageHelper.Col("访问", nameof(BucketRow.Access), 120));
        _bucketGrid.Columns.Add(ListPageHelper.Col("创建", nameof(BucketRow.Created), 150));
        _bucketGrid.SelectionChanged += async (_, _) =>
        {
            if (_bucketGrid.SelectedItem is BucketRow b)
            {
                _selectedBucket = b.Name;
                if (!string.IsNullOrEmpty(b.Namespace)) _ns = b.Namespace;
                _bucketHint.Text = "对象 · " + b.Name;
                await LoadObjectsAsync();
            }
        };

        _objectGrid.Columns.Add(ListPageHelper.Col("对象名", nameof(ObjectRow.Name), star: true));
        _objectGrid.Columns.Add(ListPageHelper.Col("大小", nameof(ObjectRow.Size), 100));
        _objectGrid.Columns.Add(ListPageHelper.Col("时间", nameof(ObjectRow.Time), 150));
        _objectGrid.Columns.Add(ListPageHelper.Col("ETag", nameof(ObjectRow.Etag), 120));

        var bar = ListPageHelper.TopBar(
            new TextBlock { Text = "租户", VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 8, 0) },
            _tenantBox,
            FormFieldFactory.Primary("加载", async (_, _) => await LoadBucketsAsync()),
            _nsText,
            _bucketHint);

        var split = new Grid { Margin = new Thickness(16, 0, 16, 16) };
        split.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        split.RowDefinitions.Add(new RowDefinition { Height = new GridLength(8) });
        split.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        Grid.SetRow(_bucketGrid, 0);
        Grid.SetRow(_objectGrid, 2);
        split.Children.Add(_bucketGrid);
        split.Children.Add(_objectGrid);

        var root = new DockPanel();
        DockPanel.SetDock(bar, Dock.Top);
        root.Children.Add(bar);
        root.Children.Add(split);
        _scaffold.SetBody(root);
        Content = _scaffold;
        Loaded += async (_, _) => await LoadTenantsAsync();
    }

    private string? TenantId =>
        _tenantBox.SelectedIndex >= 0 && _tenantBox.SelectedIndex < _tenants.Count
            ? _tenants[_tenantBox.SelectedIndex].Id
            : null;

    private string EffectiveNs(BucketRow? bucket = null)
    {
        bucket ??= _bucketGrid.SelectedItem as BucketRow;
        if (bucket != null && !string.IsNullOrEmpty(bucket.Namespace)) return bucket.Namespace;
        return _ns;
    }

    private async Task LoadTenantsAsync() =>
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var raw = await _api.GetJsonAsync("/tenants/listParentTenants").ConfigureAwait(true);
            _tenants = TenantRegionOption.ParseList(raw);
            _tenantBox.ItemsSource = _tenants.Select(t => t.DisplayLabel).ToList();
            if (_tenantBox.Items.Count > 0)
            {
                _tenantBox.SelectedIndex = 0;
                await LoadBucketsAsync();
            }
        });

    private async Task LoadBucketsAsync()
    {
        var tid = TenantId;
        if (tid == null) { ToastService.Info("请选择租户"); return; }
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            _ns = "";
            try
            {
                var nsRaw = await _api.GetJsonAsync("/oci/storage/namespace",
                    new Dictionary<string, string> { ["tenantId"] = tid }).ConfigureAwait(true);
                var root = JsonUtil.Obj(nsRaw) ?? new();
                if (root.TryGetValue("data", out var d))
                {
                    if (d.ValueKind == System.Text.Json.JsonValueKind.String) _ns = d.GetString() ?? "";
                    else if (d.ValueKind == System.Text.Json.JsonValueKind.Object)
                        _ns = JsonUtil.Str(JsonUtil.ToDict(d), "namespace");
                }
                if (string.IsNullOrEmpty(_ns)) _ns = JsonUtil.Str(root, "namespace");
            }
            catch { /* optional */ }
            _nsText.Text = "Namespace: " + (string.IsNullOrEmpty(_ns) ? "—" : _ns);

            var raw = await _api.GetJsonAsync("/oci/storage/buckets", new Dictionary<string, string>
            {
                ["tenantId"] = tid,
                ["limit"] = "50"
            }).ConfigureAwait(true);
            var (rows, _, _, _) = JsonPage.Parse(raw, ["content", "list", "buckets", "items", "data"]);
            _bucketGrid.ItemsSource = rows.Select(m => new BucketRow
            {
                Name = JsonPage.Pick(m, "name", "bucketName"),
                Namespace = string.IsNullOrEmpty(JsonPage.Pick(m, "namespace", "namespaceName"))
                    ? _ns
                    : JsonPage.Pick(m, "namespace", "namespaceName"),
                Access = AccessLabel(JsonPage.Pick(m, "publicAccessType", "accessType", "access", "publicAccess")),
                Created = JsonPage.Pick(m, "timeCreated", "created", "createTime")
            }).ToList();
            _objectGrid.ItemsSource = null;
            _selectedBucket = null;
            _bucketHint.Text = "选中 Bucket 后加载对象";
        });
    }

    private async Task LoadObjectsAsync()
    {
        var tid = TenantId;
        if (tid == null || string.IsNullOrEmpty(_selectedBucket)) return;
        await ListPageHelper.SafeLoad(_scaffold, async () =>
        {
            var ns = EffectiveNs();
            var q = new Dictionary<string, string>
            {
                ["tenantId"] = tid,
                ["bucketName"] = _selectedBucket!,
                ["limit"] = "50"
            };
            if (!string.IsNullOrEmpty(ns)) q["namespace"] = ns;
            var raw = await _api.GetJsonAsync("/oci/storage/objects", q).ConfigureAwait(true);
            var (rows, _, _, _) = JsonPage.Parse(raw, ["content", "list", "objects", "items", "data"]);
            _objectGrid.ItemsSource = rows.Select(m => new ObjectRow
            {
                Name = JsonPage.Pick(m, "name", "objectName", "key"),
                Size = FormatSize(JsonPage.Pick(m, "size", "contentLength")),
                Time = JsonPage.Pick(m, "timeCreated", "timeModified", "lastModified"),
                Etag = JsonPage.Pick(m, "etag", "eTag")
            }).ToList();
        });
    }

    // ── Bucket write ───────────────────────────────────────────

    private async Task CreateBucketAsync()
    {
        var tid = TenantId;
        if (tid == null || !long.TryParse(tid, out var tenantId))
        {
            ToastService.Info("请选择租户");
            return;
        }

        var form = PromptCreateBucket();
        if (form == null) return;
        var (name, access) = form.Value;
        if (string.IsNullOrEmpty(name))
        {
            ToastService.Error("请输入存储桶名称");
            return;
        }

        try
        {
            _scaffold.SetLoading(true);
            var raw = await _api.PostJsonAsync("/oci/storage/bucket/create", new
            {
                tenantId,
                bucketName = name,
                publicAccessType = access
            }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "创建成功");
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Success(r.message);
            await LoadBucketsAsync();
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

    private async Task DeleteBucketAsync()
    {
        var tid = TenantId;
        if (tid == null || !long.TryParse(tid, out var tenantId))
        {
            ToastService.Info("请选择租户");
            return;
        }
        if (_bucketGrid.SelectedItem is not BucketRow bucket)
        {
            ToastService.Info("请先选择 Bucket");
            return;
        }
        if (MessageBox.Show($"确定删除「{bucket.Name}」？桶必须为空才能删除。", "删除存储桶",
                MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;

        try
        {
            _scaffold.SetLoading(true);
            var ns = EffectiveNs(bucket);
            var raw = await _api.PostJsonAsync("/oci/storage/bucket/delete", new
            {
                tenantId,
                @namespace = ns,
                bucketName = bucket.Name
            }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "已删除");
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Success(r.message);
            if (_selectedBucket == bucket.Name)
            {
                _selectedBucket = null;
                _objectGrid.ItemsSource = null;
            }
            await LoadBucketsAsync();
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

    // ── Object write ───────────────────────────────────────────

    private async Task UploadObjectAsync()
    {
        var tid = TenantId;
        if (tid == null || string.IsNullOrEmpty(_selectedBucket))
        {
            ToastService.Info("请先选择 Bucket");
            return;
        }
        var ns = EffectiveNs();
        if (string.IsNullOrEmpty(ns))
        {
            ToastService.Error("无法获取 Namespace，请先加载 Bucket");
            return;
        }
        if (!long.TryParse(tid, out var tenantId))
        {
            ToastService.Error("租户 ID 无效");
            return;
        }

        var dlg = new OpenFileDialog
        {
            Title = "选择要上传的文件",
            Filter = "All|*.*",
            Multiselect = true
        };
        if (dlg.ShowDialog() != true || dlg.FileNames.Length == 0) return;

        try
        {
            _scaffold.SetLoading(true);
            var ok = 0;
            foreach (var path in dlg.FileNames)
            {
                var fi = new FileInfo(path);
                var objectName = fi.Name;
                if (fi.Length >= MultipartThreshold)
                {
                    _scaffold.Subtitle = $"分片上传 {objectName} ({FormatSize(fi.Length.ToString())})…";
                    await UploadMultipartAsync(tenantId, ns, _selectedBucket!, objectName, path, fi.Length)
                        .ConfigureAwait(true);
                }
                else
                {
                    var fields = new Dictionary<string, string>
                    {
                        ["tenantId"] = tid,
                        ["namespace"] = ns,
                        ["bucketName"] = _selectedBucket!
                    };
                    var raw = await _api.PostMultipartAsync(
                        "/oci/storage/object/upload",
                        fields,
                        "file",
                        path).ConfigureAwait(true);
                    var r = ApiClient.SuccessMessage(raw, "上传成功");
                    if (!r.ok) throw ApiError.Server(r.message);
                }
                ok++;
            }
            _scaffold.Subtitle = "OCI Object Storage · Bucket / 对象";
            ToastService.Success(ok == 1 ? "上传成功" : $"已上传 {ok} 个文件");
            await LoadObjectsAsync();
        }
        catch (Exception ex)
        {
            _scaffold.Subtitle = "OCI Object Storage · Bucket / 对象";
            ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
        }
        finally
        {
            _scaffold.SetLoading(false);
        }
    }

    /// <summary>Multipart: initiate → part loop → commit (abort on failure).</summary>
    private async Task UploadMultipartAsync(
        long tenantId, string ns, string bucket, string objectName, string filePath, long totalSize)
    {
        string? uploadId = null;
        var parts = new List<object>();
        try
        {
            var initRaw = await _api.PostJsonAsync("/oci/storage/object/multipart/initiate", new
            {
                tenantId,
                @namespace = ns,
                bucketName = bucket,
                objectName,
                totalSize,
                chunkSize = ChunkSize
            }).ConfigureAwait(true);
            uploadId = ExtractUploadId(initRaw);
            if (string.IsNullOrEmpty(uploadId))
                throw ApiError.Server("初始化分片上传失败");

            await using var fs = File.OpenRead(filePath);
            var partNumber = 1;
            var buffer = new byte[ChunkSize];
            int read;
            while ((read = await fs.ReadAsync(buffer.AsMemory(0, buffer.Length)).ConfigureAwait(true)) > 0)
            {
                var tmp = Path.Combine(Path.GetTempPath(), $"oci-part-{Guid.NewGuid():N}.bin");
                try
                {
                    await File.WriteAllBytesAsync(tmp, buffer.AsMemory(0, read).ToArray()).ConfigureAwait(true);
                    var fields = new Dictionary<string, string>
                    {
                        ["tenantId"] = tenantId.ToString(),
                        ["namespace"] = ns,
                        ["bucketName"] = bucket,
                        ["objectName"] = objectName,
                        ["uploadId"] = uploadId!,
                        ["partNumber"] = partNumber.ToString()
                    };
                    var partRaw = await _api.PostMultipartAsync(
                        "/oci/storage/object/multipart/part",
                        fields,
                        "chunk",
                        tmp).ConfigureAwait(true);
                    var (partNum, etag) = ExtractPartResult(partRaw, partNumber);
                    if (string.IsNullOrEmpty(etag))
                        throw ApiError.Server($"分片 {partNumber} 上传失败");
                    parts.Add(new { partNum, etag });
                    _scaffold.Subtitle =
                        $"分片 {partNumber} · {FormatSize((partNumber * ChunkSize).ToString())}/{FormatSize(totalSize.ToString())}";
                    partNumber++;
                }
                finally
                {
                    try { File.Delete(tmp); } catch { /* ignore */ }
                }
            }

            var commitRaw = await _api.PostJsonAsync("/oci/storage/object/multipart/commit", new
            {
                tenantId,
                @namespace = ns,
                bucketName = bucket,
                objectName,
                uploadId,
                parts
            }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(commitRaw, "分片上传成功");
            if (!r.ok) throw ApiError.Server(r.message);
        }
        catch
        {
            if (!string.IsNullOrEmpty(uploadId))
            {
                try
                {
                    await _api.PostJsonAsync("/oci/storage/object/multipart/abort", new
                    {
                        tenantId,
                        @namespace = ns,
                        bucketName = bucket,
                        objectName,
                        uploadId
                    }).ConfigureAwait(true);
                }
                catch { /* best-effort abort */ }
            }
            throw;
        }
    }

    private static string ExtractUploadId(byte[] raw)
    {
        var root = JsonUtil.Obj(raw);
        if (root == null) return "";
        if (root.TryGetValue("data", out var data) && data.ValueKind == System.Text.Json.JsonValueKind.Object)
        {
            var d = JsonUtil.ToDict(data);
            var id = JsonUtil.Str(d, "uploadId");
            if (!string.IsNullOrEmpty(id)) return id;
        }
        return JsonUtil.Str(root, "uploadId");
    }

    private static (int partNum, string etag) ExtractPartResult(byte[] raw, int fallbackPart)
    {
        var root = JsonUtil.Obj(raw);
        if (root == null) return (fallbackPart, "");
        Dictionary<string, System.Text.Json.JsonElement> d = root;
        if (root.TryGetValue("data", out var data) && data.ValueKind == System.Text.Json.JsonValueKind.Object)
            d = JsonUtil.ToDict(data);
        var partNum = JsonUtil.Int(d, "partNum", fallbackPart);
        var etag = JsonUtil.Str(d, "etag");
        return (partNum, etag);
    }

    private async Task PreviewObjectAsync()
    {
        var tid = TenantId;
        if (tid == null || string.IsNullOrEmpty(_selectedBucket))
        {
            ToastService.Info("请先选择 Bucket");
            return;
        }
        if (_objectGrid.SelectedItem is not ObjectRow obj || string.IsNullOrEmpty(obj.Name))
        {
            ToastService.Info("请先选择对象");
            return;
        }
        var ns = EffectiveNs();
        if (string.IsNullOrEmpty(ns))
        {
            ToastService.Error("无法获取 Namespace");
            return;
        }

        try
        {
            _scaffold.SetLoading(true);
            var q = new Dictionary<string, string>
            {
                ["tenantId"] = tid,
                ["namespace"] = ns,
                ["bucketName"] = _selectedBucket!,
                ["objectName"] = obj.Name
            };
            var (data, _, headers) = await _api.DownloadAsync("/oci/storage/object/preview", q)
                .ConfigureAwait(true);
            var contentType = "";
            if (headers.TryGetValue("Content-Type", out var ct)) contentType = ct;
            ShowPreviewDialog(obj.Name, data, contentType);
        }
        catch (Exception ex)
        {
            // fallback: open browser URL (cookie same-origin when local)
            try
            {
                var url = _api.MakeUrl("/oci/storage/object/preview", new Dictionary<string, string>
                {
                    ["tenantId"] = tid!,
                    ["namespace"] = ns,
                    ["bucketName"] = _selectedBucket!,
                    ["objectName"] = obj.Name
                });
                Process.Start(new ProcessStartInfo(url.ToString()) { UseShellExecute = true });
                ToastService.Info("已在浏览器打开预览");
            }
            catch
            {
                ToastService.Error(ex is ApiError ae ? ae.Message : ex.Message);
            }
        }
        finally
        {
            _scaffold.SetLoading(false);
        }
    }

    private static void ShowPreviewDialog(string name, byte[] data, string contentType)
    {
        var lower = name.ToLowerInvariant();
        var isImage = contentType.StartsWith("image/", StringComparison.OrdinalIgnoreCase) ||
                      lower.EndsWith(".png") || lower.EndsWith(".jpg") || lower.EndsWith(".jpeg") ||
                      lower.EndsWith(".gif") || lower.EndsWith(".webp") || lower.EndsWith(".bmp");
        var isText = contentType.StartsWith("text/", StringComparison.OrdinalIgnoreCase) ||
                     contentType.Contains("json", StringComparison.OrdinalIgnoreCase) ||
                     contentType.Contains("xml", StringComparison.OrdinalIgnoreCase) ||
                     lower.EndsWith(".txt") || lower.EndsWith(".log") || lower.EndsWith(".md") ||
                     lower.EndsWith(".json") || lower.EndsWith(".xml") || lower.EndsWith(".csv");

        var win = new Window
        {
            Title = "预览 — " + name,
            Width = 720,
            Height = 560,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush")
        };
        if (Application.Current.MainWindow != null)
            win.Owner = Application.Current.MainWindow;

        UIElement body;
        if (isImage)
        {
            try
            {
                var img = new System.Windows.Media.Imaging.BitmapImage();
                using var ms = new MemoryStream(data);
                img.BeginInit();
                img.CacheOption = System.Windows.Media.Imaging.BitmapCacheOption.OnLoad;
                img.StreamSource = ms;
                img.EndInit();
                img.Freeze();
                body = new ScrollViewer
                {
                    Content = new Image { Source = img, Stretch = Stretch.Uniform, Margin = new Thickness(12) }
                };
            }
            catch
            {
                body = new TextBlock
                {
                    Text = "无法解码图片",
                    Margin = new Thickness(16),
                    Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
                };
            }
        }
        else if (isText)
        {
            var text = System.Text.Encoding.UTF8.GetString(data);
            if (text.Length > 200_000) text = text[..200_000] + "\n…(截断)";
            body = new TextBox
            {
                Text = text,
                IsReadOnly = true,
                TextWrapping = TextWrapping.Wrap,
                AcceptsReturn = true,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
                FontFamily = new FontFamily("Cascadia Mono, Consolas"),
                Margin = new Thickness(8),
                Style = (Style)Application.Current.FindResource("AppTextBox")
            };
        }
        else
        {
            body = new StackPanel
            {
                Margin = new Thickness(24),
                Children =
                {
                    new TextBlock
                    {
                        Text = $"类型 {contentType}\n大小 {data.Length:N0} 字节\n此类型请下载后查看。",
                        TextWrapping = TextWrapping.Wrap,
                        Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush")
                    }
                }
            };
        }

        var root = new DockPanel { Margin = new Thickness(8) };
        var close = FormFieldFactory.Secondary("关闭", (_, _) => win.Close());
        close.HorizontalAlignment = HorizontalAlignment.Right;
        close.Margin = new Thickness(0, 8, 8, 8);
        DockPanel.SetDock(close, Dock.Bottom);
        root.Children.Add(close);
        root.Children.Add(body);
        win.Content = root;
        win.ShowDialog();
    }

    private async Task DownloadObjectAsync()
    {
        var tid = TenantId;
        if (tid == null || string.IsNullOrEmpty(_selectedBucket))
        {
            ToastService.Info("请先选择 Bucket");
            return;
        }
        if (_objectGrid.SelectedItem is not ObjectRow obj || string.IsNullOrEmpty(obj.Name))
        {
            ToastService.Info("请先选择对象");
            return;
        }
        var ns = EffectiveNs();
        if (string.IsNullOrEmpty(ns))
        {
            ToastService.Error("无法获取 Namespace");
            return;
        }

        var displayName = obj.Name.Contains('/')
            ? obj.Name[(obj.Name.LastIndexOf('/') + 1)..]
            : obj.Name;
        var save = new SaveFileDialog
        {
            Title = "保存对象",
            FileName = displayName,
            Filter = "All|*.*"
        };
        if (save.ShowDialog() != true) return;

        try
        {
            _scaffold.SetLoading(true);
            var q = new Dictionary<string, string>
            {
                ["tenantId"] = tid,
                ["namespace"] = ns,
                ["bucketName"] = _selectedBucket!,
                ["objectName"] = obj.Name
            };
            var (data, filename, _) = await _api.DownloadAsync("/oci/storage/object/download", q)
                .ConfigureAwait(true);
            await File.WriteAllBytesAsync(save.FileName, data).ConfigureAwait(true);
            ToastService.Success("已下载：" + (filename ?? save.FileName));
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

    private async Task DeleteObjectAsync()
    {
        var tid = TenantId;
        if (tid == null || !long.TryParse(tid, out var tenantId) || string.IsNullOrEmpty(_selectedBucket))
        {
            ToastService.Info("请先选择 Bucket");
            return;
        }
        if (_objectGrid.SelectedItem is not ObjectRow obj || string.IsNullOrEmpty(obj.Name))
        {
            ToastService.Info("请先选择对象");
            return;
        }
        var ns = EffectiveNs();
        if (MessageBox.Show($"确定删除「{obj.Name}」？", "删除对象",
                MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes)
            return;

        try
        {
            _scaffold.SetLoading(true);
            var raw = await _api.PostJsonAsync("/oci/storage/object/delete", new
            {
                tenantId,
                @namespace = ns,
                bucketName = _selectedBucket,
                objectName = obj.Name
            }).ConfigureAwait(true);
            var r = ApiClient.SuccessMessage(raw, "已删除");
            if (!r.ok) throw ApiError.Server(r.message);
            ToastService.Success(r.message);
            await LoadObjectsAsync();
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

    private async Task PresignObjectAsync()
    {
        var tid = TenantId;
        if (tid == null || !long.TryParse(tid, out var tenantId) || string.IsNullOrEmpty(_selectedBucket))
        {
            ToastService.Info("请先选择 Bucket");
            return;
        }
        if (_objectGrid.SelectedItem is not ObjectRow obj || string.IsNullOrEmpty(obj.Name))
        {
            ToastService.Info("请先选择对象");
            return;
        }
        var ns = EffectiveNs();

        try
        {
            _scaffold.SetLoading(true);
            var raw = await _api.PostJsonAsync("/oci/storage/object/presigned", new
            {
                tenantId,
                @namespace = ns,
                bucketName = _selectedBucket,
                objectName = obj.Name,
                validitySeconds = 3600L
            }).ConfigureAwait(true);
            var url = ExtractPresignedUrl(raw);
            if (string.IsNullOrEmpty(url))
                throw ApiError.Server("生成预签名 URL 失败");

            try
            {
                Clipboard.SetText(url);
            }
            catch { /* ignore clipboard errors */ }

            ShowPresignedDialog(url);
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

    // ── Dialogs / helpers ──────────────────────────────────────

    private static (string Name, string Access)? PromptCreateBucket()
    {
        var win = new Window
        {
            Title = "创建存储桶",
            Width = 440,
            Height = 260,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.NoResize,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush")
        };
        if (Application.Current.MainWindow != null)
            win.Owner = Application.Current.MainWindow;

        var nameBox = FormFieldFactory.TextField(watermark: "my-bucket-name");
        var accessBox = new ComboBox
        {
            MinWidth = 240,
            Padding = new Thickness(8, 6, 8, 6),
            ItemsSource = AccessTypes.Select(a => a.Title).ToList(),
            SelectedIndex = 0
        };
        var ok = false;
        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(FormFieldFactory.Labeled("桶名称", nameBox));
        panel.Children.Add(FormFieldFactory.Labeled("访问类型", accessBox));
        panel.Children.Add(new TextBlock
        {
            Text = "名称需全局唯一，仅小写字母、数字、连字符。",
            FontSize = 11,
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
            Margin = new Thickness(0, 4, 0, 0)
        });
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 16, 0, 0)
        };
        buttons.Children.Add(FormFieldFactory.Secondary("取消", (_, _) => win.Close()));
        buttons.Children.Add(FormFieldFactory.Primary("创建", (_, _) => { ok = true; win.Close(); }));
        panel.Children.Add(buttons);
        win.Content = panel;
        win.ShowDialog();
        if (!ok) return null;
        var idx = Math.Clamp(accessBox.SelectedIndex, 0, AccessTypes.Length - 1);
        return (nameBox.Text?.Trim() ?? "", AccessTypes[idx].Value);
    }

    private static void ShowPresignedDialog(string url)
    {
        var win = new Window
        {
            Title = "预签名链接",
            Width = 520,
            Height = 240,
            WindowStartupLocation = WindowStartupLocation.CenterOwner,
            ResizeMode = ResizeMode.CanResize,
            Background = (Brush)Application.Current.FindResource("SidebarBgBrush")
        };
        if (Application.Current.MainWindow != null)
            win.Owner = Application.Current.MainWindow;

        var box = new TextBox
        {
            Text = url,
            IsReadOnly = true,
            TextWrapping = TextWrapping.Wrap,
            AcceptsReturn = true,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            MinHeight = 80,
            Style = (Style)Application.Current.FindResource("AppTextBox")
        };
        var panel = new StackPanel { Margin = new Thickness(16) };
        panel.Children.Add(new TextBlock
        {
            Text = "链接有效期约 1 小时。已自动复制到剪贴板。",
            TextWrapping = TextWrapping.Wrap,
            Foreground = (Brush)Application.Current.FindResource("TextSecondaryBrush"),
            Margin = new Thickness(0, 0, 0, 10)
        });
        panel.Children.Add(box);
        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 16, 0, 0)
        };
        buttons.Children.Add(FormFieldFactory.Secondary("复制", (_, _) =>
        {
            try { Clipboard.SetText(url); ToastService.Success("已复制"); }
            catch (Exception ex) { ToastService.Error(ex.Message); }
        }));
        buttons.Children.Add(FormFieldFactory.Secondary("浏览器打开", (_, _) =>
        {
            try
            {
                Process.Start(new ProcessStartInfo(url) { UseShellExecute = true });
            }
            catch (Exception ex) { ToastService.Error(ex.Message); }
        }));
        buttons.Children.Add(FormFieldFactory.Primary("关闭", (_, _) => win.Close()));
        panel.Children.Add(buttons);
        win.Content = panel;
        win.ShowDialog();
    }

    private static string ExtractPresignedUrl(byte[] raw)
    {
        var root = JsonUtil.Obj(raw) ?? new();
        // envelope data
        if (root.TryGetValue("data", out var data))
        {
            if (data.ValueKind == System.Text.Json.JsonValueKind.String)
            {
                var s = data.GetString() ?? "";
                if (!string.IsNullOrEmpty(s)) return s;
            }
            if (data.ValueKind == System.Text.Json.JsonValueKind.Object)
            {
                var d = JsonUtil.ToDict(data);
                var u = JsonUtil.Str(d, "url");
                if (string.IsNullOrEmpty(u)) u = JsonUtil.Str(d, "presignedUrl");
                if (string.IsNullOrEmpty(u)) u = JsonUtil.Str(d, "parUrl");
                if (!string.IsNullOrEmpty(u)) return u;
            }
        }
        var top = JsonUtil.Str(root, "url");
        if (string.IsNullOrEmpty(top)) top = JsonUtil.Str(root, "presignedUrl");
        return top;
    }

    private static string AccessLabel(string raw) => raw switch
    {
        "ObjectRead" => "公共读",
        "ObjectReadWithoutList" => "公共读(无列表)",
        "NoPublicAccess" or "" => "私有",
        _ => string.IsNullOrEmpty(raw) ? "私有" : raw
    };

    private static string FormatSize(string raw)
    {
        if (string.IsNullOrEmpty(raw)) return "—";
        if (!long.TryParse(raw, out var n) || n < 0) return raw;
        string[] units = ["B", "KB", "MB", "GB", "TB"];
        double v = n;
        var i = 0;
        while (v >= 1024 && i < units.Length - 1)
        {
            v /= 1024;
            i++;
        }
        return i == 0 ? $"{n} B" : $"{v:0.##} {units[i]}";
    }
}
