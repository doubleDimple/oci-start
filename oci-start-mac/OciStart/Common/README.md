# Common — 可复用 UI

所有业务页共用组件放这里。规划见仓库 `tasks/macos-common-components.md`。

| 文件 | 用途 |
|------|------|
| `Models/PageState` | 分页状态 |
| `Models/SelectOption` | 下拉选项 |
| `Components/PageScaffold` | 页头+内容壳 |
| `Components/SelectMenu` | 自定义下拉（非系统 Menu，对齐 Web custom-select） |
| `Components/PaginationBar` | 通用分页（`SelectMenu` 每页条数 + `AppCompactField` 跳转，直接 `PaginationBar(state:onChange:)`） |
| `Components/FilterBar` | 筛选行 |
| `Components/SearchField` | 搜索 |
| `Components/StatusBadge` | 状态胶囊 |
| `Components/PrimaryButton` | 按钮 |
| `Components/EmptyStateView` | 空态 |
| `Components/LoadingOverlay` | 全局 LoadingHUD + 页内加载 |
| `Components/ToastCenter` | 错误 Toast（成功反馈请用 LoadingHUD） |
| `Components/AppAlert` | 确认框 |
| `Components/AppSheetChrome` | 弹层外壳（标题栏/内容/页脚）+ Tab/多行输入 |
| `Components/FormFields` | 表单行 |
| `Components/DataList` | 列表壳 |
| `Components/SectionCard` | 卡片 |
| `Extensions/View+Common` | 修饰器 |

**规则：** 业务页禁止再写第二套分页/下拉/空态。
