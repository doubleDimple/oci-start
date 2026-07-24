# OCI-Start Windows — 按 Mac 左侧菜单实现

菜单顺序与 **`oci-start-mac` NavigationCatalog / sidebar.ftl** 一致。

进度清单：`tasks/windows-menu-progress.md`

## 运行（Windows）

```powershell
cd oci-start-win
dotnet restore OciStart.sln
dotnet build OciStart.sln -c Debug
dotnet run --project src/OciStart
```

联调建议：先起后端，登录选远程 `http://127.0.0.1:9856`。

## 侧栏覆盖

| 分组 | 覆盖 |
|------|------|
| 服务管理 | 监控→区域→租户→实例→邮件→存储→开机→AI→延迟→开机日志（多云占位同 Mac） |
| 代理管理 | 密钥 / CF / EdgeOne |
| VPS | 监控看板 |
| 系统管理 | 质量 / 日志 / 安全 / 代理 |
| 我的工具 | AI 对话 / 通知 / 备忘 / 迁移 / MFA |
| 开发者 | Token |

原则：原生 WPF；禁止业务整页套 FTL；设置页对齐质量管理卡片标准。

### 实例控制台

- 使用 **WebView2 仅嵌入 noVNC RFB 画布**（对齐 Mac WKWebView），不是业务整页。
- 本机需安装 [WebView2 Evergreen Runtime](https://developer.microsoft.com/microsoft-edge/webview2/)。
- 画布脚本从 jsDelivr 拉 `@novnc/novnc@1.4.0`，联调时需能访问外网 CDN。
