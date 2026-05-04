# Codex 紧急回复：P0-15 安全问题不能延后

更新时间：2026-05-04 12:00 +08:00

## 用户最新决策

用户明确要求：**关于安全问题绝对不能拖延。**

因此 Codex 不接受把 P0-15 `/ndapi/autologin` sessionid 越权风险长期放入 Stage 1 backlog 的排期方式。该问题应从“已知 + 有方案 + 等执行”调整为：

> P0 安全缺陷，必须立即进入当前修复队列。

## 风险判断

`/ndapi/autologin` 当前允许通过传入 `sessionid` 完成自动登录。Codex 已确认现有 Web/管理后台链路依赖它，但这不改变其安全等级。

不能直接关旧接口，是因为会破坏管理后台跳转小屏 IM；但也不能因为有业务依赖就继续无限期保留长期 sessionid URL 流转。

正确处理方式是：**立即做兼容迁移，而不是延期。**

## 建议立即执行顺序

### Step 1：后端立即实现 SSO ticket 接口

请后端优先实现已 ack 的 ticket 方案，不等 DAU 或 Stage 1：

- 管理端签发：`POST /tioadmin/api/im-login-ticket.admin_x`
- Web 兑换：`POST /ndapi/exchangeLoginTicket.tio_x`
- Redis ticket：TTL 60 秒，一次性使用，兑换后立即删除
- 日志只记录 ticket 前 8 位，不记录完整 ticket
- 旧 `/ndapi/autologin` 暂时保留兼容，但应加调用审计日志和风险计数

### Step 2：后端通知 Codex 改前端

后端完成服务端接口并部署测试环境后，请在本仓库写 handoff，包含：

- 最终接口路径
- 请求 Content-Type：form / JSON / 是否两者都支持
- cookie 名称是否固定为 `tio_session`，还是使用当前 BS `session_cookie_name`
- 管理端签发接口是否需要 `targetUid`
- `audience` 取值和校验规则
- 错误码和响应样例
- 是否保留 `.tio_x` 后缀
- 是否已经加入 access-url-role 白名单

Codex 收到后改：

- `mg-page/page/src/_admin/components/Header.vue`
- `mg-page/page/src/App.vue` 如仍保留 IM 弹窗入口
- `bs-page/page/tioim-src/src/main.js`
- `bs-page/page/tioim-src/src/axios/path.js`
- `bs-page/page/tioim-small-src/src/main.js`
- `bs-page/page/tioim-small-src/src/axios/path.js`
- 必要时同步 `bs-page/page/myres/common.js`

### Step 3：联调通过后立即关闭旧接口

联调通过后，旧 `/ndapi/autologin` 应至少做到：

1. 默认拒绝公网调用；或
2. 仅保留短暂兼容窗口；或
3. 直接下线并删除前端旧入口。

不能长期保留“URL 传长期 sessionid 自动登录”的行为。

## Codex 对后端接口草案的复核意见

后端提出的 SSO ticket 方案方向正确，但有几个细节需要调整或确认：

### 1. `targetUid` 不应由普通前端任意决定

当前管理后台跳小屏 IM 的现有链路只传 `tio_mg_session`，不是明确传某个目标用户。

建议：

- 普通“进入自己的 IM”场景：后端从 `tio_mg_session` 推导当前管理用户对应的 IM 用户，不要求前端传 `targetUid`。
- “超级管理员代入某用户”场景：可以传 `targetUid`，但后端必须强校验角色 99/100、目标用户状态和审计日志。

否则前端传 `targetUid` 本身会变成新的越权入口。

### 2. `Set-Cookie` 名称必须和 BS 实际 session 配置一致

后端草案写：

`Set-Cookie: tio_session=<新 session>; Domain=.anjuke.site; Path=/; HttpOnly; Secure; SameSite=Lax`

请确认实际 Web 用户端配置中的 `session_cookie_name` 是否就是 `tio_session`。前端 Web 代码会从 `/view/conf` 返回的 `session_cookie_name` 读取 cookie 名称。如果环境实际名称不同，硬编码 `tio_session` 会导致 `/user/curr` 仍然未登录。

建议后端使用 BS 当前配置的 session cookie 名称生成 `Set-Cookie`。

### 3. Web 兑换接口应允许无登录访问，但必须强校验 ticket

`POST /ndapi/exchangeLoginTicket.tio_x` 在调用时还没有用户端 cookie，因此 access-url-role 应允许未登录访问。

但安全必须依赖：

- ticket 随机性
- TTL
- 一次性
- audience
- 发行端身份
- 兑换后删除
- 审计日志

### 4. ticket 可以在 URL 中短暂出现，但前端必须立刻清理

前端收到 `login_ticket` 后会：

1. 立即调用兑换接口；
2. 成功或失败后立刻用 `history.replaceState` / 现有 `changeURLArgs` 清除 URL 参数；
3. 不写入 localStorage/sessionStorage；
4. 不打印完整 ticket 日志。

### 5. 建议兑换接口支持 JSON 和 form 两种请求

现有 Web axios 封装可能更容易走 form 或普通对象。为降低联调风险，建议后端同时支持：

- `application/x-www-form-urlencoded`: `ticket=...`
- `application/json`: `{ "ticket": "..." }`

## 在 ticket 完成前的临时缓解

如果后端今天不能一次完成 ticket 方案，也应立刻做临时缓解：

- 对 `/ndapi/autologin` 加安全审计日志：来源 IP、UA、Referer/Origin、sessionid 前 8 位、是否成功、映射 uid。
- 对 `/ndapi/autologin` 加速率限制。
- 拒绝空 Referer/Origin 或明显非本站来源的浏览器请求；这不是完整安全边界，但可以降低误用和泄露后的直接利用面。
- 统计所有成功调用，若来源不是 `admin.anjuke.site` / `web.anjuke.site` 相关链路，立即告警。
- 尽快压缩旧接口兼容窗口。

## 前端当前状态

Codex 已完成依赖审计，确认旧接口不能裸关；但用户已经明确安全不能拖延，所以当前推荐变为：

- 后端立刻做 ticket 服务端；
- Codex 等后端 handoff 后立即改 Web 前端；
- 联调通过后旧 `/ndapi/autologin` 下线。

本次 handoff 是对后端排期决策的纠偏，不涉及服务器密钥和真实用户数据。
