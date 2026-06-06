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

---

# 侧边栏菜单手风琴 + 点击一级自动加载第一个二级(2026-06-06)
## 背景

侧边栏目前点击一级菜单只是切换自身展开/收起,可同时展开多个一级菜单;点击一级菜单也不会
自动进入任何二级页面,需要用户再点二级才能跳转。用户希望:
1. 点击一级菜单展开时,自动收起其它已展开的一级菜单(手风琴)
2. 一级菜单从未展开变为展开时,自动加载第一个可见的二级菜单

## 范围

- 只动 `oci-server/src/main/resources/static/js/system/sidebar.js`
- 只动 `expandMenu()` 入口(用户主动点击展开时才触发)
- **不动** `expandMenusWithActiveChildren()`(页面首次加载基于 active child 的展开,保持原行为)
- **不动** `collapseMenu()` / `toggleMenu()`(收起场景无新行为)
- 不动 HTML / CSS / 后端

## 步骤

- [x] 1. `expandMenu` 开头加手风琴:遍历所有 `.nav-parent`,对非当前且已展开的调用 `collapseMenu`
- [x] 2. `expandMenu` 结尾新增"找第一个可见有效二级菜单链接并 `.click()`"
- [x] 3. 新增辅助函数 `findFirstVisibleChildLink`,用 `offsetParent !== null` 过滤被
     `cloud-menu` 隐藏的项,跳过 `#` / `javascript:` 链接
- [x] 4. `node --check` 通过
- [ ] 5. 提交并 push 到 `claude/pensive-edison-mpksh`
- [ ] 6. 用户在本地浏览器实测交互(本环境无浏览器)

## 关键决策

- **触发方式选 `.click()` 而非手动 `iframe.src = href`**:子菜单的 `<a target="biz-frame">` 由浏览器原生处理 iframe 加载,`.click()` 同时会触发现有的"active 高亮切换"事件监听(`sidebar.js:99-110`),无需重复实现高亮逻辑
- **手风琴只影响用户主动点击场景**:`expandMenusWithActiveChildren()` 不走 `expandMenu`,
  直接操作 DOM —— 这是页面初始状态恢复(根据 URL 命中哪个 active child),
  与"用户主动切换"语义不同,保持隔离
- **`offsetParent === null` 跳过隐藏项**:针对 `.cloud-menu[data-cloud-types]` 按云供应商
  动态 `display:none` 的场景,确保不会"加载用户当前云类型下根本看不到的页面"
- **不引入手风琴的负面后果**:用户已在某二级页面时点击该一级,行为是"收起",
  原本就走 `collapseMenu`,不会触发新的"自动加载第一个二级",符合直觉
- **切换一级 = 切换页面上下文**:用户已确认:点击新一级菜单会切走当前 iframe 工作上下文,
  这是接受的代价

## Review

### 改动文件(1 个)

| 文件 | 增 / 减 | 内容 |
|------|--------|------|
| `oci-server/src/main/resources/static/js/system/sidebar.js` | +23 / -0 | `expandMenu` 加手风琴 + 自动加载第一个二级;新增 `findFirstVisibleChildLink` |

### 未验证项

- 浏览器实测(无环境无法跑),需要用户在本地确认:
  1. 点击一级菜单(从未展开)→ 其它一级收起,当前展开,iframe 跳到第一个二级
  2. 点击一级菜单(已展开)→ 仅收起当前,不切 iframe
  3. 页面刷新后,URL 对应的二级菜单仍被自动 active 高亮,父菜单自动展开
  4. 切换云供应商后,隐藏的二级菜单不会被作为"第一个可见"误触发

---

# 开机详情菜单新增"开机日志"抽屉(2026-06-06)

## 背景

OCI 开机管理 → 预开列表 → 点击"..."→"开机详情"打开模态框,该模态框内表格的"操作"列
下拉菜单当前有 4 项(开机停止/开机启动/配置修改/记录删除)。用户希望加第 5 项**"开机日志"**,
点击后从屏幕右侧滑出抽屉,实时展示**当前这条 BootInstance 任务**相关的日志。

## 调研发现(影响方案的关键事实)

- `task.getBootId()` 是 `String`,值等于 `BootInstance.id.toString()` —— 前端可以用它做匹配键
- 现有 SSE 流 `/system/streamLogs?isBootLog=true` 是全局的,**不区分** taskId
- `CreateInstanceTaskV2` 里 5/6 处日志都带了 `TaskId: {bootId}`(格式驼峰带空格)
- **`OracleCloudService:924` 的"开机成功完整详情"(含 IP/密码/登录信息)没带 taskId** ——
  纯前端方案下这条最关键的日志会被漏掉,**已与用户确认接受这个代价**
- `buildOpenBootException` 内部多条 log.warn 也都不带 taskId —— 异常归因日志也会漏

## 方案

**方案 A(纯前端过滤,接受漏数据)**:
- 复用现有 `/system/streamLogs?isBootLog=true` SSE
- 前端用正则 `/[Tt]ask[Ii]d\s*[:：]\s*{bootId}(?![0-9])/` 过滤每行
- 抽屉只展示实时流(不主动拉历史)
- 不动任何后端 Java 代码
- 不动现有"OCI 开机日志(全局)"页面

## 范围

只改这 6 个文件:

| 文件 | 改动类型 |
|------|--------|
| `i18n/messages.properties` | + `openBoot.log=Boot Log` |
| `i18n/messages_zh_CN.properties` | + `openBoot.log=开机日志` |
| `i18n/messages_zh_TW.properties` | + `openBoot.log=開機日誌` |
| `templates/full_machine_list.ftl` | 引入新 CSS、`</body>` 前加抽屉 HTML、i18n 注入区加 `openBoot_log` |
| `static/js/system/full_machine_list.js` | 详情菜单(行 373-388)插一项"开机日志"、新增 `openBootLogDrawer/closeBootLogDrawer/connectBootLogSSE/disconnectBootLogSSE/appendBootLogLine` |
| `static/css/app/boot_log_drawer.css`(新建) | 抽屉遮罩 + 滑入动画 + 终端样式 |

不动:任何 Java 文件、现有 `open_boot_log.ftl` / `open_boot_log.js` / `sys_log.css`、
后端 `LogController` / `LogServiceImpl` / `OciLogBuilder` / `CreateInstanceTaskV2` / `OracleCloudService`。

## 步骤

- [x] 1. 3 个 properties 文件加 `openBoot.log` key(中/英/繁)
- [x] 2. `full_machine_list.ftl`:头部引 `boot_log_drawer.css`,i18n script 块加 `openBoot_log`,
     `</body>` 前加抽屉 HTML(标题/状态/自动滚动/关闭/日志容器/空态)
- [x] 3. 新建 `boot_log_drawer.css`:遮罩、抽屉容器、滑入动画、终端配色、状态点、空态文字
- [x] 4. `full_machine_list.js`:
     - 菜单加项放在"启动开机"后(`fa-file-alt` 图标)
     - 新增函数:`openBootLogDrawer / closeBootLogDrawer / connectBootLogSSE /
       disconnectBootLogSSE / setBootLogStatus / appendBootLogLine`
- [x] 5. `node --check` 通过 + FTL 标签平衡(`<#if>:0 <#list>:0`)
- [ ] 6. 提交 push
- [ ] 7. 用户浏览器实测

## 关键决策

1. **菜单走 i18n,抽屉内部小文案硬编码中文**:菜单项必须与同行其它项风格一致(都走 i18n);
   抽屉内"自动滚动"/"已连接"/"暂无日志" 等少量文字硬编码,避免 i18n 文件膨胀,保持"简单点"
2. **z-index 高于 modal-overlay**:抽屉叠在详情弹窗之上,关闭抽屉返回详情弹窗,关闭详情弹窗返回列表
3. **关抽屉时断 SSE**:避免泄漏长连接
4. **正则同时认 `TaskId`/`taskId`/中英文冒号/有无空格**,末尾 `(?![0-9])` 防 `123` 匹配 `1234`
5. **每打开一次抽屉清空一次内容**:避免上次任务日志残留

## 已知限制(与用户达成共识)

- `OracleCloudService:924` 的开机成功完整详情(含 Public IP / Private IP / Root 密码)
  **不会出现在抽屉里**(后端那条日志没带 taskId)
- `buildOpenBootException` 各异常分支的归因日志同样**不会出现**

如果后续要补这块,需要走方案 A'(改后端 6-7 处日志补 taskId 占位符)。

## Review

### 改动文件(共 6 个,1 新建)

| 文件 | 增 / 减 | 内容 |
|------|--------|------|
| `i18n/messages.properties` | +1 / -0 | `openBoot.log=Log` |
| `i18n/messages_zh_CN.properties` | +1 / -0 | `openBoot.log=开机日志` |
| `i18n/messages_zh_TW.properties` | +1 / -0 | `openBoot.log=開機日誌` |
| `templates/full_machine_list.ftl` | +35 / -0 | 引入 CSS、i18n key、抽屉 HTML(33 行) |
| `static/js/system/full_machine_list.js` | +109 / -0 | 菜单项 3 行 + 抽屉控制函数 106 行 |
| `static/css/app/boot_log_drawer.css` 🆕 | 新建 | 滑入动画 + 终端配色 + 状态点动画 |

### 关键决策

1. **正则 `[Tt]ask[Ii]d\s*[:：]\s*{bootId}(?![0-9])`**:大小写不敏感,中/英文冒号兼容,
   末尾 `(?![0-9])` 防止 `123` 误匹配 `1234`
2. **z-index 2000**(`.modal-overlay` 是 1050):抽屉叠在详情弹窗之上
3. **每次打开抽屉清空 DOM + 计数**:防止上一条任务的日志残留
4. **最多保留 1000 行**:与 `open_boot_log.js` 一致,避免内存膨胀
5. **关抽屉时 `close()` SSE**:防止泄漏长连接
6. **使用 `data-state` 切换状态点颜色**(灰/黄/绿/红):比类切换更紧凑

### 静态校验

- `node --check full_machine_list.js` → PASS
- FTL `<#if>` / `<#list>` 标签平衡 → 0 / 0

### 已知限制(用户已确认接受)

- 后端 `OracleCloudService:924` 的"开机成功完整详情"(含 IP / Root 密码)未带 taskId →
  **不会出现在抽屉里**
- `buildOpenBootException` 各异常分支日志未带 taskId → **不会出现**
- `CreateInstanceTaskV2:305`(网络连接暂时不可达)未带 taskId → **不会出现**
- 抽屉**不加载历史**,只展示打开后的实时流(若 SSE 连上时该任务正好没在抢机,可能长时间空白)

### 未验证项

- **浏览器实测**:本环境无浏览器,无法启动 oci-server。需要用户验证:
  1. 进入 OCI 开机管理 → 打开"开机详情" → 操作栏菜单出现"开机日志"
  2. 点击 → 抽屉从右侧滑入,顶部显示 `#bootId`,状态点变绿(已连接)
  3. 抢机正在运行时,匹配 `TaskId: {当前 id}` 的行实时出现在抽屉里
  4. 关闭抽屉 → 滑出 + SSE 断开(可在 DevTools Network 看到 EventSource 关闭)
  5. 多次开关无残留日志、无重复连接
  6. 详情弹窗与抽屉的 z-index 关系正确
- **Maven 编译**:本环境无法跑(JDK 21 与 Lombok 1.18.24 不兼容,与本次改动无关)
  本次仅静态资源 + properties,不会影响 Java 字节码

---

# 开机日志抽屉升级 A':后端日志统一加 TaskId 前缀(2026-06-06)

## 背景

A 方案上线后实测发现:抢机失败重试日志(用户最高频反馈,如
`用户:[东京]的区域:[ap-tokyo-1]的架构:[ARM]未完成开机,...将在:[60]秒后重试`)进不了抽屉,
因为 `OciLogBuilder.buildOpenBootException` 体内 12 处 log 均未带 taskId。这是结构性问题,
所有异常分支日志全部漏。

## 方案

后端给所有相关日志统一加 `[TaskId={bootId}] ` 前缀(`bootId` 即 `BootInstance.id`);
前端正则放宽,同时认 `TaskId: 123`(旧)与 `TaskId=123`(新)。

## 范围

| 文件 | 改动 |
|------|------|
| `OciLogBuilder.java` | `buildOpenBootException` 体内 12 处有内容的 `log.info/warn`(空字符串和纯分隔符不改) |
| `OracleCloudService.java:924` | 那条"开机成功完整详情"前面拼 `[TaskId=...]` |
| `CreateInstanceTaskV2.java:305` | "网络连接暂时不可达"日志加 `[TaskId={}]` |
| `static/js/system/full_machine_list.js` | 抽屉正则改为 `/[Tt]ask[Ii]d\s*[=:：]\s*{id}(?![0-9])/` |

不动 Entity / Repository / Controller / 其它业务逻辑。

## 步骤

- [x] 1. `OciLogBuilder.java`:12 处 `log.info/warn` 加 `[TaskId={}]` 前缀和 `user.getBootId()` 参数
- [x] 2. `OracleCloudService.java:914-923`:**每行**前面拼 `taskTag`(因 Logback `%msg%n` 原样
     输出 `\n`,Tailer 按行读 → 多行被分割成多个 SSE 消息,只加首行 TaskId 会让其它行漏过)
- [x] 3. `CreateInstanceTaskV2.java:305`:`buildOpenNoThrow("[TaskId={}] 网络...", taskId, ...)`
- [x] 4. `full_machine_list.js`:正则字符类加 `=`(`[=:：]`)
- [x] 5. JS `node --check` PASS;Java 逐行人工核对占位符与参数数量,全部对齐
     (含 `e` 作为 Throwable 不消耗占位符的 SLF4J 行为)
- [ ] 6. 提交 push
- [ ] 7. 用户浏览器实测

## 风险与缓解

- **SLF4J 占位符数量不匹配会抛异常** → 改完后用 grep 检查所有改动行的 `{}` 数与逗号分隔参数数对齐
- **影响现有"OCI 开机日志(全局)"页面显示** → 全局页面只是多出 `[TaskId=xxx]` 前缀,无害
- **`log.warn(..., e)` 最后一个 Throwable 的处理** → SLF4J 自动检测最后参数为 Throwable 时不消耗占位符,继续保留 e 作为 stack trace

## Review

### 改动文件(4 个)

| 文件 | 增 / 减 | 说明 |
|------|--------|------|
| `OciLogBuilder.java` | +12 / -12 | 12 处 log 加 `[TaskId={}]` 前缀和 `user.getBootId()` |
| `OracleCloudService.java` | +9 / -8 | 新增 `taskTag` 局部变量,8 行 append 各加一次 |
| `CreateInstanceTaskV2.java` | +1 / -1 | 网络异常日志加 `[TaskId={}]` |
| `full_machine_list.js` | +1 / -1 | 正则 `[:：]` → `[=:：]` 兼容 `=` 分隔符 |

### 占位符核对(逐行人工)

| 行 | format `{}` 数 | 非 Throwable args 数 | 状态 |
|----|---|---|---|
| OciLogBuilder:52 | 2 | 2(`e` 是 Throwable,不消耗) | ✅ |
| OciLogBuilder:63 | 3 | 3 | ✅ |
| OciLogBuilder:70 | 5 | 5 | ✅ |
| OciLogBuilder:72 | 7 | 7 | ✅ |
| OciLogBuilder:77/82 | 3 | 3 | ✅ |
| OciLogBuilder:88/92/97 | 2 | 2 | ✅ |
| OciLogBuilder:101/105 | 2 | 2 | ✅ |
| OciLogBuilder:107 | 4 | 4 | ✅ |
| CreateInstanceTaskV2:305 | 2 | 2 | ✅ |
| OracleCloudService:923 | 0(纯拼字符串)| - | ✅ |

### 关键决策

1. **多行日志的每行都加 TaskId 前缀**:`OracleCloudService:924` 那条 `\n` 分隔的"开机成功
   详情",在文件里是多行;Tailer 按行读 → 每行单独成为 SSE 消息。如果只在首行加 TaskId,
   后续 IP/密码行还是会被过滤掉。每行加前缀虽显累赘,但是唯一保证完整可见的做法。
2. **不重构 `buildOpenBootException` 方法签名**:把"加 TaskId"做成 `OciLogBuilder` 内部职责,
   而不是修改方法签名要求所有调用方传 taskId,改动范围最小
3. **正则字符类只加 `=`,不动其它**:`[Tt]ask[Ii]d\s*[=:：]\s*X(?![0-9])` 同时兼容旧的
   `TaskId: 123` 和新的 `TaskId=123`,不会破坏现有日志识别

### 已知副作用(可接受)

- 现有"OCI 开机日志(全局)"页面所有相关日志行会多出 `[TaskId=xxx]` 前缀
  → 更清晰,不是问题
- `buildOpenBootException` 那 4 处 `<====================>` 纯分隔符日志**未加** TaskId
  (本身无信息量,加了反而怪)→ 抽屉里不会显示,但分隔符本来就不重要

### 未验证项

- **浏览器实测**:本环境无 JDK 8 / 无浏览器,无法启动 oci-server。需要用户验证:
  1. 重启 oci-server 后,抢机失败重试日志(用户截图那条)能进入对应任务的抽屉
  2. 开机成功的完整登录信息(IP/Public IP/Private IP/region/Root 密码)每行进入抽屉
  3. 各类异常分支(容量不足/配额超限/API 无权限/抢机频率太快/未知错误等)也能进入抽屉
  4. 现有"OCI 开机日志(全局)"页面正常展示(只是多了前缀)
- **Maven 编译**:本环境 JDK 21 + Lombok 1.18.24 不兼容,无法跑。但本次 Java 改动仅
  字符串字面量与方法调用,语法/类型无歧义,编译风险极低

---

# 修复"任务计数在涨但日志全无"(2026-06-06)

## 用户反馈

任务很多时,当天抢机次数(`currentAttemptCount`)在累加,但**完全没有该任务的抢机日志**。

## 根因诊断

完整调用链:

```
createInstanceData (OracleCloudService:105)
  ↓ 第一行就 inc(user) → 数据库 currentAttemptCount += 1 ← 用户看到的"今日次数"
  ↓ 后续 OCI API 调用 → BmcException(容量不足,最高频)
  ↓ catch → buildOpenBootException
      ↓ 进入"容量不足"分支(OciLogBuilder:60-71)
         if (log.isDebugEnabled()) { ... }   ← 反模式!Logback 默认 root=info
           ↳ 5 行 log.info 被吞
           ↳ 1 行 log.warn 被吞
         if (size <= 0) { log.info(...重试...) }   ← 只在最后一个 AD 才打
  ↓ 多 AD 场景下,size > 0 时函数静默返回
```

`isDebugEnabled()` 只能守卫 `log.debug(...)`,守卫 `log.info/warn` 等于**强制让 info/warn 永远不输出**。
这是经典反模式。

## 范围

只改 `OciLogBuilder.java` 容量不足分支:
- 去掉 2 个 `if (log.isDebugEnabled())` 守卫
- 顺手删 2 个 `log.info("")` 空字符串 + 2 个 `log.info("<====>")` 纯分隔符
  (用户确认走 A:保持"OCI 开机日志(全局)"页面输出干净)
- 保留 3 条有信息量的日志(容量不足提示 / 未完成开机 / 重试)

## 不做的事(深入分析后排除)

- **`createFromDbCreateComputer:291` 返回值丢失**:看似 bug,但实测 `buildOpenBootException`
  方法体内**根本不修改入参 `oracleInstanceDetail`**,引用语义下"丢返回值"与"接返回值"功能等价。
  纯代码气味,不直接对应用户报告的问题,**按精准修改原则跳过**
- **全项目其它 9 处 `isDebugEnabled() 守卫 info/warn`**:同型号反模式,但分散在
  `OracleCloudService` 和 `OciCliUtils` 的多个独立场景,需要逐一判断"作者本意 debug 还是 info"
  才能选 "去守卫" 还是 "改成 log.debug",超出本次范围

## 步骤

- [x] 1. `OciLogBuilder.java:60-71` 删 2 处 `isDebugEnabled` 守卫,删 4 行无信息量日志
- [x] 2. `git diff` 确认改动精准(-10 行 / 解放出 2 条原本被吞的 log)
- [ ] 3. 提交 push
- [ ] 4. 用户重启 oci-server 实测

## 关键决策

- **不修 Bug 3 是经过深入代码分析后的诚实结论**,不是偷懒。`buildOpenBootException`
  全方法体逐行核对,确认它不修改 `oracleInstanceDetail`(只 return 它),所以丢返回值
  在引用传递下零影响
- **删纯分隔符与空行**:它们原本就靠 `isDebugEnabled` 隐藏,一旦解放守卫,涌进全局日志
  页面会是垃圾信息。用户已确认走 A 删干净
- **保留 `log.info` 不改 `log.debug`**:这条容量不足日志对用户有价值(抢机进度可见),
  作者本意应是 info 级别,守卫的写法是 bug 而非 debug 抑制

## Review

### 改动文件(1 个)

| 文件 | 增 / 减 | 内容 |
|------|--------|------|
| `OciLogBuilder.java` | +2 / -10 | 删 2 个 `if (isDebugEnabled())` 守卫 + 4 行无信息量日志,保留 3 条有意义日志 |

### 效果

修复后,**容量不足场景的每次失败都会输出一行日志**:
```
[TaskId=N] 用户:东京当前区域容量不足 Out of host capacity 换另一个可用性区域继续执行
```

多 AD 场景下,3 个 AD 都失败后还会额外打 `未完成开机` 和 `将在 60 秒后重试`。

抽屉里能完整看到失败链路。

### 未验证项

- **浏览器+服务端实测**:本环境无法启动 oci-server,需用户重启后:
  1. 触发一次抢机失败(任意场景)
  2. 控制台/日志文件看到 `[TaskId=N] ... 当前区域容量不足 ...` 输出
  3. 对应任务的"开机日志"抽屉里看到这条
  4. "OCI 开机日志(全局)"页面没有出现成片的 `<======>` 分隔符



