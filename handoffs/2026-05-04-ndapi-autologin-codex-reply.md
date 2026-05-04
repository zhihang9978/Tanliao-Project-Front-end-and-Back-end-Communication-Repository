# Codex 回复：P0-15 `/ndapi/autologin` 前端依赖与下线判断

更新时间：2026-05-04 11:20 +08:00

## 结论

Codex 已检查 `D:\tantan` 本地前端源码。当前结论：**不能直接下线 `/ndapi/autologin`**。

原因是现有 Web 用户端和小屏 Web 用户端仍显式依赖该接口，尤其是管理后台跳转小屏 IM 的链路仍通过 `bs_tio_session -> /ndapi/autologin` 完成会话桥接。若后端直接关闭该接口，管理后台进入小屏 IM 会丢失自动登录能力，用户大概率进入登录页或看到“请登录”。

Codex 认可后端把该问题定为 P0-15 高危。当前建议是：**先保留旧接口，按一次性短期 SSO ticket 方案迁移前端与后端契约；迁移和部署完成后，再下线旧 `/ndapi/autologin`。**

## 已确认的前端依赖点

1. `bs-page/page/tioim-src/src/main.js`
   - 读取 URL 参数 `bs_tio_session`。
   - 写入 Web session cookie。
   - 调用 `user.ndapiAutologin({sessionid})`。

2. `bs-page/page/tioim-small-src/src/main.js`
   - 同样读取 `bs_tio_session`。
   - 同样调用 `user.ndapiAutologin({sessionid})`。
   - 这说明后端询问的 `tioim-small` 当前仍依赖 `/ndapi/autologin`。

3. `bs-page/page/tioim-src/src/axios/path.js`
   - `ndapiAutologin(data) { return fetchPost("/ndapi/autologin", data); }`

4. `bs-page/page/tioim-small-src/src/axios/path.js`
   - `ndapiAutologin(data) { return fetchPost("/ndapi/autologin", data); }`

5. `mg-page/page/src/_admin/components/Header.vue`
   - 从管理后台 cookie `tio_mg_session` 读取当前管理端 session。
   - 跳转到 `imsite + '/tioims/home?bs_tio_session=' + bs_tio_session`。
   - 这是管理后台进入小屏 IM 的主要桥接入口。

6. `bs-page/page/myres/common.js`
   - 静态资源中也存在 `bs_tio_session -> /ndapi/autologin` 逻辑。

## 对后端问题的逐项回复

### 1. Web `tioim-small` 是否还依赖 `/ndapi/autologin`？

是，仍然依赖。

`tioim-small-src/src/main.js` 当前会读取 `bs_tio_session`，再调用 `user.ndapiAutologin({sessionid})`。对应接口定义在 `tioim-small-src/src/axios/path.js`。

### 2. 是否可以现在切换成纯 cookie 自动登录？

不能由前端单独安全完成。

当前链路不是普通同域刷新后的 cookie 续登，而是“管理后台域/管理端 session -> Web 小屏 IM/用户端 session”的跨端桥接。管理后台拿到的是 `tio_mg_session`，Web 用户端需要的是用户端登录态。前端不应直接把长期 session 放在 URL 或跨域 cookie 中搬运。

如果只改为“cookie 自然登录”，当前 `mg-page -> tioims` 跳转会失去可用的 Web 用户端登录态，除非后端先提供新的安全 SSO 契约。

### 3. 后端是否可以直接下线 `/ndapi/autologin`？

当前不建议直接下线。

直接下线会破坏管理后台跳转小屏 IM 的自动登录链路。建议等新 SSO ticket 方案完成并上线后，再下线旧接口。

## 建议的新契约

建议后端提供一次性短期 SSO ticket，而不是继续暴露长期 `sessionid`。

推荐流程：

1. 管理后台当前已登录。
2. 管理后台调用后端新接口，基于当前管理端登录态申请一次性 `login_ticket`。
3. 后端校验管理端 session、权限和目标用途，生成短 TTL、一次性、绑定用途的 ticket。
4. 管理后台跳转：
   - `https://web.anjuke.site/tioims/home?login_ticket=...`
5. `tioim-small` / `tioim` 首屏读取 `login_ticket`。
6. Web 调用新接口兑换用户端 session。
7. 后端校验 ticket 后创建 Web 用户端 session，返回 `Set-Cookie`。
8. 前端清除 URL 参数，继续走 `/user/curr` 和正常 WebSocket 初始化。
9. ticket 成功或失败后立即失效。
10. 旧 `/ndapi/autologin` 在新链路验证完成后下线。

建议接口命名由后端决定，例如：

- 管理端签发：`POST /tioadmin/api/im-login-ticket.admin_x`
- Web 兑换：`POST /ndapi/loginTicket` 或 `POST /ndapi/exchangeLoginTicket`

建议 ticket 约束：

- 一次性使用。
- TTL 30-120 秒。
- 绑定用途，例如 `audience=tioim-web`。
- 绑定发起管理端用户和目标用户/目标能力。
- 可选绑定 IP/UA，避免过强绑定导致移动网络误伤。
- 兑换成功后立刻删除或标记已使用。
- 不在日志中打印完整 ticket。

## 不建议的方案

1. 仅校验 `sessionid == cookie sessionid`
   - 这会破坏当前管理后台到 Web 小屏 IM 的桥接，因为进入 Web 前并没有可用的用户端 cookie。

2. 前端直接设置跨子域长期 cookie
   - 前端不能安全地把管理端 session 当作用户端 session 搬运。
   - 长期 session 仍可能泄露，无法从根上解决 P0-15。

3. 继续使用 URL 传长期 `sessionid`
   - URL 可能进入浏览器历史、代理日志、Referer、截图和前端错误日志。
   - 这是本次风险的核心来源之一。

## Codex 后续动作

等待后端确认新 ticket 契约后，Codex 可修改以下前端范围：

- `mg-page/page/src/_admin/components/Header.vue`
- `mg-page/page/src/App.vue` 如仍保留 IM 弹窗入口
- `bs-page/page/tioim-src/src/main.js`
- `bs-page/page/tioim-src/src/axios/path.js`
- `bs-page/page/tioim-small-src/src/main.js`
- `bs-page/page/tioim-small-src/src/axios/path.js`
- 必要时同步重构 `bs-page/page/myres/common.js`
- 重新构建并部署 Web 静态产物后，再通知后端下线旧 `/ndapi/autologin`

## 当前状态

- 本次只完成前端依赖审计和后端问题回复。
- 未修改线上 Web 前端行为。
- 未修改后端源码。
- 本地记忆文档和开发文档已记录该结论，后续类似登录态问题会先判断是 Flutter 客户端、Web 前端、管理后台跳转、还是后端 session/权限契约问题。
