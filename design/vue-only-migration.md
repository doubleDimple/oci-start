# Vue 页面与 FreeMarker 移除

桌面、移动端及登录页面统一使用 `oci-start-web`。服务端的 74 个 FTL 模板、模板渲染方法、FreeMarker starter/配置和 133 个旧页面专属静态资源已移除。通知文本模板、业务数据、后端国际化消息和数据库迁移机制不属于这次删除范围。

## 页面和接口兼容

- `/login`、`/m/login` 提供同一响应式 Vue 登录页，保持移动 iOS 外观及桌面点阵地图。登录、首次注册、找回密码、消息验证码、MFA、GitHub/Google 登录沿用原接口。
- `/api/auth/bootstrap` 是公开、禁止缓存的初始化接口，只返回站点名、功能开关、公开 site key 和 RSA 公钥。私钥留在会话中，刷新或并发打开页面复用同一密钥对。Vue 加密失败时不会提交明文密码。
- `/perform_login` 的 JSON 请求在失败时明确返回非 2xx；成功返回原 `success/redirectUrl`。普通表单和现有客户端保留兼容方式。Turnstile 验证失败不再把 Vue 请求重定向成 HTML；服务不可用时保持失败状态。
- 登录页显示与后台验证统一使用 `VerifyService.isMessageEnabled()`，消息渠道开关包含原验证码服务支持的飞书。
- `VueSpaFilter` 只接管已列出的 GET/HEAD 页面，原 `/m` 别名、`/main`、`/index`、`/about/author` 和业务网址继续可用。API、下载、WebSocket、写入操作仍交给原处理器。页面不再回退到旧模板；缺少 Vue 入口时明确返回 503。
- IP 封禁：接口返回 JSON 403，浏览器页面跳到公开 `/forbidden`；不会回显异常细节。公开页面跳过已登录页面的会话轮询。
- Vite 开发代理将 `/login` 和 `/m/login` 交给 Vue；`/api/**`、OAuth 回调、登录提交及非 GET/HEAD 请求保持转发到后端。

## 构建和部署

从仓库根目录构建完整发行包：

```sh
mvn -Pweb -pl oci-server -am clean package
```

`web` profile 通过显式 reactor 依赖保证前端先完成类型检查和构建，服务端随后复制静态资源并打包；并行 Maven 构建也保持此顺序。前端模块的 POM 仅用于构建顺序，不进入应用运行依赖。

本机已安装 pnpm 时，也可以分步构建：

```sh
pnpm --dir oci-start-web run build
mvn -pl oci-server -am clean package
```

最终文件仍为 `oci-server/target/oci-start-release.jar`。Vue 静态文件随 JAR 发布，继续使用服务端原端口，生产环境无需 Node 服务或 Vite 端口。`prepare-package` 会逐项检查入口 HTML 引用的 JS/CSS（包含预加载文件），缺少入口或资源时拒绝打包；JAR 配置同时排除增量构建中可能残留的旧模板资源。

Vite 只清理其生成的 `static/assets`。共享图片、后端区域国旗、三个本地 xterm 运行脚本和安装脚本保留。入口 `index.html` 禁止缓存，页面引用带内容哈希的 JS/CSS。

首次升级必须同时部署包含新初始化接口的后端和相应 Vue 构建。IDE 直接启动 Java 不会自动运行 pnpm；可运行 `start-dev.sh` 联合开发，或先构建 Vue 再启动 Java。

项目内 macOS/Windows 客户端也改为读取初始化接口，打包脚本同步启用 `-Pweb`。连接旧服务端时，初始化接口返回 404 可回退原 HTML；旧鉴权器对未知接口返回 401 时，只有确认为含 RSA 公钥的旧登录页才启用兼容路径。网络失败、503 或新 Vue HTML 不会触发明文降级。使用原生客户端时应同步更新客户端，旧二进制仍可能依赖模板中的登录配置。

## 验证边界

认证与路由使用隔离服务/会话测试；浏览器验收中的账号、验证码、OAuth、重置结果及 Turnstile 响应均为模拟值，不操作真实用户或云资源。真实第三方授权和挑战服务仍需在配置完成的部署环境中验证。

- JDK 17 下后端全套 140 项测试通过，涵盖路由、会话、RSA、验证码组合、封禁继承及错误响应。
- 前端 27 项测试通过，涵盖认证请求、超时/取消、公开页面会话守卫和移动列表导航。
- 生产构建的 20 个浏览器场景覆盖 320/390px、桌面地图、双语主题、登录/注册/找回密码、模拟 OAuth 和 Turnstile。
- 打包检查的 7 个隔离样例验证了缺失入口、样式及预加载文件均无法通过。
