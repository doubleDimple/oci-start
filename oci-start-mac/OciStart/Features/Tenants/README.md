# 租户管理（全原生）

## 架构

```
AppKit 壳 → NSHostingController → TenantsView
  ├── 列表 / 搜索 / 分页 / 窗内操作菜单
  ├── 业务弹层（用户/流量/审计/邮箱/社媒/配额/引导卷/安全规则/MySQL…）
  └── 租户详情整页 TenantDetailView（对齐 Web /tenants/regionList）
```

## 操作栏 → 原生对应

| 菜单 | 实现 |
|------|------|
| 创建开机 | 原生表单 + `querySystemImages` + `boot/save` |
| 更新信息 | SSE 原生 |
| **租户详情** | **整页** `TenantDetailView` ← Web `tenant_region_list.ftl` |
| 区域订阅 | summary / 已订阅 / 未订阅勾选 / subscribe |
| 用户管理 | 三 Tab + 密码策略 |
| 流量预警 | 原生读写 |
| 流量查询 | `monitor/api/instances/traffic` |
| 审计日志 | 原生 |
| 费用 | `/cost/query` |
| 导出 / 邮箱 / 社媒 / 配额 / 引导卷 / 同步 / 删除 | 原生 |
| AI | 模型列表 + `/ws/aiChat` WebSocket 对话 |

## 租户详情页（Web 对照）

| Web | Mac |
|-----|-----|
| `GET /tenants/regionList?tenantId=` | 列表内导航 `detailParent` → `TenantDetailView` |
| 表格：名称/自定义名/开机任务/区域/主区域/同步/创建时间/操作 | 同列布局 |
| 同步 / 创建开机 / 磁盘 / 安全规则 / 数据库 / AI | 行菜单 + 已有弹层 |
| 实例列表 / 抢机任务 | 提示（侧栏页待原生化） |

**不再**通过 `WebEmbed` 嵌套 Web 页面。
