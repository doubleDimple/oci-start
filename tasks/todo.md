# 代理类型下拉框样式统一(2026-06-06)

## 背景

VPN 代理列表页(`vpn_proxy.ftl`)的"代理类型 / 可用状态"下拉、通知管理页(`notification_settings.ftl`)
Telegram 代理面板的"代理类型"下拉,目前仍是浏览器原生 `<select>`,与项目其它页面已经使用的
`CustomSelect`(`/js/common/custom-select.js`)风格不一致。

原需求还包括为以上下拉新增 HY2 / VLESS 代理类型,经评估(JDK 8 项目、`telegrambots` 仅支持
HTTP/HTTPS/SOCKS5、Java 生态无成熟 HY2/VLESS 客户端),本期**放弃** HY2 / VLESS 支持,
仅完成下拉框样式统一。

## 范围

- 只改截图涉及的两个页面,全站其它已用 custom-select 的页面**不动**
- VPN 代理列表模态框的"代理类型"和"可用状态"两个 select **都改**(同表单风格统一)

## 步骤

- [x] 1. 修改 `vpn_proxy.ftl`:`<head>` 引入 `custom-select.css`,`<body>` 底部引入 `custom-select.js`;
     `proxyType` / `availableStatus` 两个 `<select>` 加 `data-custom-select` + `data-placeholder`
- [x] 2. 修改 `vpn_proxy.js`:`openAddModal`(`form.reset()` 后)、`openEditModal`(赋值后)统一通过
     新增的 `refreshProxyModalSelects()` 调用 `CustomSelect.refresh()`
- [x] 3. 修改 `notification_settings.ftl`:Telegram 代理 `proxyType` `<select>` 加 `data-custom-select`
- [x] 4. JS `node --check` 通过、FTL 标签平衡(`<#if>`/`<#list>`/`<#assign>` 计数为 0)通过
- [ ] 5. 提交并 push 到 `claude/pensive-edison-mpksh`
- [ ] 6. 用户在本地浏览器实测三个下拉的样式与交互(本环境无浏览器,无法代为完成)

## 不做的事

- 不引入 HY2 / VLESS 协议支持(协议层无法在 JDK 8 + Java 生态下实现)
- 不重构 `vpn_proxy.js` 既有逻辑,只补 refresh 调用
- 不动全站其它页面的 select
- 不动 i18n / 后端 controller / entity

## Review

### 改动文件(共 3 个)

| 文件 | 增 / 减 | 内容 |
|------|--------|------|
| `oci-server/src/main/resources/templates/vpn_proxy.ftl` | +6 / -2 | 引入 custom-select 资源;两个 `<select>` 加 `data-custom-select`,代理类型再加 `data-placeholder` |
| `oci-server/src/main/resources/static/js/system/vpn_proxy.js` | +8 / -0 | 新增 `refreshProxyModalSelects()`,在 `openAddModal` / `openEditModal` 末尾调用 |
| `oci-server/src/main/resources/templates/notification_settings.ftl` | +1 / -1 | Telegram 代理类型 `<select>` 加 `data-custom-select`(资源已在该模板加载) |

### 关键决策

1. **`refreshProxyModalSelects()` 单独抽出**:`openAddModal` 与 `openEditModal` 都要刷新同一组 select,
   抽函数避免重复;函数内部用 `typeof CustomSelect === 'undefined'` 做兜底,即使资源加载失败也不抛错。
2. **`custom-select.js` 引入位置在 `vpn_proxy.js` 之前**:`vpn_proxy.js` 中直接引用了 `CustomSelect`,
   按"被依赖项先加载"的惯例放在前面,清晰。运行期顺序其实无关紧要(两者都是同步 script,
   全局 `CustomSelect` 在用户点击按钮前必然已就绪)。
3. **不引入 HY2 / VLESS**:已在前期讨论中放弃,不在本任务范围。

### 未验证项

- **浏览器端实际渲染**:本会话环境无浏览器,无法启动前端实测。请在本地启动 `oci-server` 后,
  访问 "我的工具 → VPN 代理列表"(打开新增/编辑模态框)与 "我的工具 → 通知管理"(Telegram 代理面板),
  确认三个下拉框样式与统一样式一致、点开/选择/键盘交互均正常。
- **Maven 编译**:本环境只有 JDK 21,而项目 Lombok 1.18.24 不兼容 JDK 21,无法跑 `mvn compile`。
  但本次改动**仅静态资源**(`.ftl` / `.js` / `.css`),不会影响 Java 字节码,无编译风险。

### 不动的边界

- 全站其它已用 custom-select 的页面未碰
- 后端 Controller / Service / Entity / DTO 全部未碰
- i18n 资源未碰
- `vpn_proxy.js` 既有逻辑未重构

