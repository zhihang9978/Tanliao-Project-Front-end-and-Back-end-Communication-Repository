# 接口契约与变更记录

所有前后端联动变更都记录在这里。

## 记录格式

```md
## YYYY-MM-DD - 变更标题

- 提出方：Codex / 后端 AI / 用户
- 归属：客户端 / 后端 / 双方
- 接口：METHOD /path
- 变更内容：
- 请求示例：
- 响应示例：
- 兼容性：是否兼容旧客户端
- 客户端动作：
- 后端动作：
- 验收方式：
```

## 2026-05-04 - P0-15 SSO ticket 替代旧 sessionid URL 流转(正式契约)

- 提出方：codex 紧急升级 + 后端 AI 实施
- 归属：双方
- 关联 handoff:
  - `handoffs/2026-05-04-p0-15-sso-ticket-backend-deployed.md`
  - `handoffs/2026-05-04-p0-15-sso-ticket-frontend-complete.md`
  - `handoffs/2026-05-04-p0-15-sso-ticket-backend-path-aligned.md`
- 背景:旧 `/ndapi/autologin` 把长期 mg sessionid 放在跳转 URL,违反 OWASP A05;改为 60s 一次性 ticket。

### 1. 签发接口(管理后台 → mg-server)

- METHOD: `POST`
- URL(浏览器侧):`https://admin.anjuke.site/tioadmin/im-login-ticket.admin_x`
- nginx 反代后 mg-server 实际路径:`/im-login-ticket`(class-level `@RequestPath("/im-login-ticket")`)
- Cookie:必须带 `tio_mg_session`(浏览器同域自动)
- Content-Type:`application/x-www-form-urlencoded` 或 `application/json` 都支持
- 请求 Body(可选):
  ```json
  { "audience": "tioim-web" | "tioim-small" }   // 缺省 tioim-web
  ```
- 成功响应 200:
  ```json
  {
    "code": 0, "ok": true,
    "data": { "ticket": "<32B hex,例如 8b97c2f3...>", "expiresIn": 60 }
  }
  ```
- 错误码:
  | code | msg | 含义 |
  |---|---|---|
  | 1001 | 您尚未登录或登录超时 | 无 mg session 或失效(实际由 access-url-role 拦截器返回) |
  | 1003 | 账号状态异常 | mg user.status != NORMAL |
  | 1004 | audience 不在白名单 | 仅接受 tioim-web / tioim-small |
- 服务端日志关键字:`SSO-TICKET-ISSUE` / `SSO-TICKET-DENY-NOLOGIN` / `SSO-TICKET-DENY-STATUS`

### 2. 兑换接口(Web SPA → bs-server)

- METHOD: `POST`
- URL(浏览器侧):`https://api.anjuke.site/mytio/ndapi/exchangeLoginTicket.tio_x`
- bs-server 实际路径:`/ndapi/exchangeLoginTicket`(`NdApiController` `@RequestPath("/ndapi")` class + `@RequestPath("/exchangeLoginTicket")` method)
- Cookie:**无需登录态**(此接口本身就是建立登录态的入口,access-url-role 配 `=` 公开)
- Content-Type:`application/x-www-form-urlencoded`(`ticket=<hex>`)或 `application/json`(`{"ticket":"<hex>"}`)双支持
- 成功响应 200(同时 Set-Cookie 创建 BS session):
  ```
  Set-Cookie: tio_session=<新 BS session>; Domain=.anjuke.site; Path=/; HttpOnly; Secure; SameSite=Lax
  Body: { "code": 0, "ok": true }(沿用 StdSynUser.autoLogin 现有 Resp.ok())
  ```
- 错误码:
  | code | msg | 含义 |
  |---|---|---|
  | 1010 | ticket 为空 | 请求未带 ticket |
  | 1011 | ticket 无效或已过期 | Redis miss(60s TTL 过 / 已被 one-shot 删 / 假 ticket) |
- 服务端日志关键字:`SSO-TICKET-EXCHANGE`(成功)/ `SSO-TICKET-MISS`(miss)

### 3. ticket 数据结构(Redis,后端实现细节,客户端不依赖)

- key:`sso_ticket:<32B hex>`
- value(JSON):
  ```json
  {
    "adminUid": <Integer>,
    "userCode": "<mg user.id 字符串>",
    "userName": "<mg loginname>",
    "regCellPhone": "<phone>",
    "isValid": "T",
    "audience": "tioim-web" | "tioim-small",
    "issueTime": <millis>,
    "issueIp": "..."
  }
  ```
- TTL:60 秒
- ONE-SHOT:Redisson `bucket.getAndDelete()` 原子读取+删除

### 4. 完整业务流程

```
1. 管理员浏览器登录 admin.anjuke.site(持 tio_mg_session)
2. 点击 IM 入口 → mg-page Header.vue.goIm() 调 mgheader.imLoginTicket({ audience: 'tioim-small' })
   → POST /tioadmin/im-login-ticket.admin_x
   → mg-server 校验 cookie + 生成 ticket + 存 Redis + 返回
3. mg-page 收 ticket → location.href = imsite + '/tioims/home?login_ticket=<ticket>'
4. 浏览器跳转到 web.anjuke.site/tioims/home?login_ticket=...
5. tioim-small/main.js 首屏:
   a. 读取 URL 中的 login_ticket
   b. 立即 history.replaceState 清 URL(防止 ticket 进历史/Referer)
   c. 调 user.exchangeLoginTicket({ ticket })
   d. 兑换成功 → location.reload()(走正常 /user/curr)
   e. 兑换失败 → 跳登录页
6. bs-server /ndapi/exchangeLoginTicket:
   a. 解析 ticket(form 或 JSON)
   b. Redis getAndDelete(原子 one-shot)
   c. miss → 返回 1011
   d. 命中 → 解析 ticketData → 转 OutUserVo → 复用 StdSynUser.autoLogin 创建 BS session + Set-Cookie
```

### 5. 兼容性

- 旧 `/ndapi/autologin?sessionid=...`:**保留兼容期(临时缓解 Referer 校验已上线)**,新前端不再调用,旧前端调用仍可用
- 联调通过 + 24h 监控旧接口 0 调用后,后端关闭旧 `/ndapi/autologin`(改返 410 Gone 或删 endpoint)
- bs-server 侧 `access-url-role.properties` 加规则:`/ndapi/exchangeLoginTicket=`(允许未登录访问,本身是登录入口)
- mg-server 侧 `access-url-role.properties` 加规则:`/im-login-ticket=*`(已登录 mg user 即可)

### 6. 临时缓解层(未来下线)

`/mytio/ndapi/autologin.tio_x` 已加(2026-05-04 04:29 UTC):
- 审计日志 `NDAPI-AUTOLOGIN-AUDIT: ip=... referer=... origin=... ua=... sidPrefix=...`
- Referer 白名单:非 anjuke.site 子域直接返回 `{"msg":"invalid referer","ok":false}`
- 空 Referer 仍允许(兼容浏览器隐私模式 / 客户端无 Referer)

旧接口下线后,这段临时缓解代码将一并删除。

### 7. 验收方式

- 后端实测:
  - `POST /tioadmin/im-login-ticket.admin_x`(无 cookie)→ 1001 ✅
  - `POST /mytio/ndapi/exchangeLoginTicket.tio_x`(空 ticket)→ 1010 ✅
  - 同上 form/JSON 假 ticket → 1011 + log SSO-TICKET-MISS ✅
- codex 静态扫描:
  - 旧入口 0 残留 ✅
  - 新入口 login_ticket × 8 / exchangeLoginTicket × 5 / im-login-ticket × 2 ✅
- 端到端联调:**等 dist 部署到 anjuke nginx 后浏览器实测**(剩余卡点)

## 2026-05-04 - 上传拒绝提示处理

- 提出方：后端 AI + Codex 复核
- 归属：双方
- 接口：
  - `POST /mytio/upload`
  - `POST /mytio/chat/img`
  - `POST /mytio/chat/file`
  - `POST /mytio/chat/audio`
  - `POST /mytio/chat/video`
  - `POST /mytio/user/updateAvatar`
- 变更内容：后端 P0-06 已增加上传登录鉴权、扩展名白名单、路径穿越拦截和大小限制；客户端已统一处理上传拒绝提示。
- 当前响应示例：
  - `{"msg":"请登录","ok":false}`
  - `{"msg":"文件类型不允许:exe","ok":false}`
  - `{"msg":"文件名非法","ok":false}`
  - `{"msg":"文件超过大小限制(50MB)","ok":false}`
- 客户端动作：
  - 登录态错误码 `1001/1002/1003/1010`：走全局登录失效流程。
  - 无稳定 code 但 `msg=请登录/请先登录/未登录`：客户端兜底触发 `KickOutEvent`。
  - 文件类型、文件名、大小限制：当前上传页面 Toast 友好提示。
- 后端动作：
  - 已完成 P0-06 服务端限制。
  - 待补充稳定 `code/errCode`，建议至少覆盖 `UPLOAD_DENY_ANON`、`UPLOAD_DENY_EXT`、`UPLOAD_DENY_PATH`、`UPLOAD_DENY_SIZE`，避免客户端长期依赖中文 `msg` 判断逻辑。
- 兼容性：旧客户端仍会显示服务端 `msg` 或通用失败；新客户端对登录态和 4 类上传拒绝有更明确处理。
- 验收方式：
  - 登录态失效后上传应进入重新登录流程。
  - 上传 `.exe` 等禁用类型应显示“该文件类型不支持上传：exe”。
  - 非法文件名应显示“文件名不合法，请重命名后再试”。
  - 超过大小限制应显示大小限制提示。

## 2026-05-04 - 初始接口基线

- 提出方：Codex
- 归属：双方
- API 域名：`https://api.anjuke.site`
- app context：`/mytio`
- 资源域名：`https://res.anjuke.site/`
- 开发验证码：`123456`
- 说明：当前仅记录基线，不包含敏感密钥和服务器登录信息。

## 待补充

- 登录接口、注册接口、短信验证码接口。
- IM 同步接口、历史消息接口。
- 音视频信令接口、TURN 配置下发接口。
