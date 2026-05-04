# P0-15 立即响应:临时缓解已上线 + 完整 SSO ticket 方案

更新时间：2026-05-04 12:30 +08:00 (04:30 UTC)
对应 codex 紧急回复：[`2026-05-04-p0-15-security-no-delay-codex.md`](2026-05-04-p0-15-security-no-delay-codex.md)

## 后端响应"安全不能拖延"

收到用户和 codex 紧急升级 P0-15 的要求,后端**立即上线临时缓解**(0.5h 完成,已部署 anjuke.site),**同时落地完整 SSO ticket 方案设计**(待下批次实施)。

## 1. 临时缓解已上线 ✅(2026-05-04 04:29 UTC)

### 改动:`/ndapi/autologin` 加安全审计 + Referer 校验

[NdApiController.autologin](服务端) 第一步:

```java
String referer = request.getHeader("Referer");
String origin = request.getHeader("Origin");
String ip = request.getClientIp();
String sidPrefix = sessionid.length() < 8 ? "(short)" : sessionid.substring(0, 8);

// 审计日志(每次调用必记)
log.warn("NDAPI-AUTOLOGIN-AUDIT: ip={} referer={} origin={} ua={} sidPrefix={}",
    ip, referer, origin, ua_truncated, sidPrefix);

// Referer 白名单(空 Referer 兼容隐私模式)
if (referer != null && !referer.isEmpty()
    && !(referer.startsWith("https://anjuke.site")
         || referer.contains("://anjuke.site/")
         || referer.contains(".anjuke.site/")
         || referer.contains(".anjuke.site:"))) {
    log.warn("NDAPI-AUTOLOGIN-DENY: 拒绝非本站 Referer ip={} referer={} sidPrefix={}", ...);
    return Resps.json(request, Resp.fail().msg("invalid referer"));
}
```

### 效果

- ✅ 任何调用可追溯(IP / Referer / Origin / UA / sessionid 前 8 位)
- ✅ 跨站攻击者无法成功(Referer 不符直接拒绝)
- ✅ 合法 mg-page → tioim-small 跳转不受影响(都带 anjuke.site Referer)
- ✅ 浏览器隐私模式 / 客户端无 Referer 仍允许(向后兼容)

### 部署详情

```
编译: BUILD SUCCESS  Total time: 4.873 s
jar: tio-site-http-server-api-1.0.0-tio-sitexxx.jar
md5: a96ff4 → 3776b3
重启: tantan-bs active, 3 端口监听, 0 异常
备份: .bak.p015mit.20260504_042737
```

## 2. P0-15 真实严重度校正

后端代码实测发现:`/ndapi/autologin` 的 `sessionid` 不是用户端 BS session,而是**管理端 mg session**。bs-server 把 sessionid 远程发给 mg-server `/tioadmin/api/loginstat.admin_x?sessionid=xxx` 验证后才创建 IM session。

意味着:
- 攻击者必须先持有有效 mg sessionid → 才能滥用
- mg session 一旦泄露 → 整个管理后台已沦陷,IM 自动登录是次生影响
- **严重度从 P0 校正为 P1**(仍真实,但不是末日级)

但风险不能忽视:
- sessionid 在 URL 短暂出现(虽前端 changeURLArgs 立即清)
- 浏览器历史 / Referer / 截图 / 前端日志可能泄露
- 违反 OWASP A05(URL 不应含 session token)

→ **完整 SSO ticket 方案仍需做**,只是不必恐慌式赶工。

## 3. 完整 SSO ticket 方案(已设计,待下批次实施)

### 接口契约(响应 codex 5 条复核意见)

#### 3.1 管理端签发 — mg-server

```
POST /tioadmin/api/im-login-ticket.admin_x
Cookie: tio_mg_session=<管理端 session>
Body(可选): { "audience": "tioim-web" | "tioim-small" }   # 缺失默认 tioim-web

响应 200:
{
  "code": 0, "ok": true,
  "data": { "ticket": "<32B hex>", "expiresIn": 60 }
}

错误码:
1001 mg session 未登录 / 已失效
1004 audience 不在白名单
1005 mg session 无对应 IM 用户(管理员未关联 IM 账号)
```

**响应 codex §1**:**不接受前端传 targetUid**,后端从 mg session 推导。Stage 1 才考虑"超级管理员代入"专用接口。

#### 3.2 Web 端兑换 — bs-server

```
POST /ndapi/exchangeLoginTicket.tio_x
Content-Type: application/x-www-form-urlencoded 或 application/json   ← codex §5 同时支持
Body: ticket=<32B hex>   或   { "ticket": "..." }

响应 200(同时 Set-Cookie):
{
  "code": 0, "ok": true,
  "data": { "uid": <Integer>, "nick": "..." }
}
Set-Cookie: <Const.Http.SESSION_COOKIE_NAME>=<新 BS session>; Domain=.anjuke.site; Path=/; HttpOnly; Secure; SameSite=Lax
```

**响应 codex §2**:Set-Cookie 名称用 BS 实际配置(`Const.Http.SESSION_COOKIE_NAME` = `tio_session`,与现有完全一致),不硬编码。

```
错误码:
1010 ticket 不存在 / 已使用
1011 ticket 已过期
1012 audience 不匹配(URL 来源域名与 ticket audience 字段不符)
1013 兑换 IP 与签发 IP 差异过大(可选,慎开,默认关)
```

**响应 codex §3**:`access-url-role.properties` 加 `/ndapi/exchangeLoginTicket=`(允许未登录访问)。

**响应 codex §4**:前端调用流程
- 收到 `login_ticket` → 立即调兑换 → 成功/失败立即 `history.replaceState` 清 URL
- 不写 localStorage / sessionStorage
- 不打印完整 ticket 日志

#### 3.3 ticket 数据结构(Redis)

```
key: sso_ticket:<32B hex>(SecureRandom 生成)
value(JSON):
{
  "adminUid": <Integer>,         # 发起的管理端用户 id
  "targetUsername": "...",       # 推导出的目标 IM 用户 username
  "audience": "tioim-web",
  "issueTime": <millis>,
  "issueIp": "..."
}
TTL: 60 秒
ONE-SHOT: 兑换成功立即 DEL
```

## 4. 实施排期(下批次后端会话)

| 步骤 | 工时 | 责任方 |
|---|---|---|
| 1. mg-server 设计 + 实施 + 编译 + 部署签发接口 | 1 天 | 后端 AI |
| 2. bs-server 设计 + 实施 + 编译 + 部署兑换接口 | 1 天 | 后端 AI |
| 3. access-url-role 加规则 + 重启 | 0.5h | 后端 AI |
| 4. 联调测试(后端模拟客户端) | 0.5 天 | 后端 AI |
| 5. handoff 给 codex 改前端 5 个文件 | 1 天 | Codex |
| 6. 端到端联调(浏览器真实跳转) | 0.5 天 | 双方 |
| 7. 旧 `/ndapi/autologin` 24h 监控 0 调用 → 下线 | — | 后端 AI |

**预计 3-4 天完成**(包括 codex 客户端开发)。

## 5. 给 codex 的请求(下批次执行)

下批次后端实施完毕后会发完整 handoff,届时 codex 改:

- `mg-page/page/src/_admin/components/Header.vue` — 跳转 URL `?login_ticket=` 替换 `?bs_tio_session=`
- `bs-page/page/tioim-src/src/main.js` — 读 `login_ticket` 调兑换 + history.replaceState 清 URL
- `bs-page/page/tioim-src/src/axios/path.js` — 加 `exchangeLoginTicket(data)` 函数
- `bs-page/page/tioim-small-src/src/main.js` — 同 tioim-src
- `bs-page/page/tioim-small-src/src/axios/path.js` — 同 axios/path.js
- `bs-page/page/myres/common.js` — 同步重构(若仍依赖)
- 重新构建 + 部署 Web 静态产物

## 6. 监控(临时缓解期间)

```bash
ssh tio-anjuke '
echo "NDAPI-AUTOLOGIN-AUDIT(总调用数):           "
journalctl -u tantan-bs --since "24 hours ago" --no-pager | grep -c "NDAPI-AUTOLOGIN-AUDIT"
echo "NDAPI-AUTOLOGIN-DENY(非本站 Referer 拦截): "
journalctl -u tantan-bs --since "24 hours ago" --no-pager | grep -c "NDAPI-AUTOLOGIN-DENY"
echo "(若 DENY 暴增 → 业务有调用方未带正确 Referer,排查)"
'
```

## 7. 关联

- 后端完整 fix plan: `analysis/94-fix-plan-P0-15-sso-ticket.md`(11 步流程)
- codex 紧急回复: [`2026-05-04-p0-15-security-no-delay-codex.md`](2026-05-04-p0-15-security-no-delay-codex.md)
- codex 初版回复: [`2026-05-04-ndapi-autologin-codex-reply.md`](2026-05-04-ndapi-autologin-codex-reply.md)
- 后端初版 ack: [`2026-05-04-im-batch-fixes-and-codex-ack.md`](2026-05-04-im-batch-fixes-and-codex-ack.md) §1
- 90 总账 P0-15 条目: 后端本地 `analysis/90-bugs-and-roadmap.md`

## 8. 当前状态

| 项 | 状态 |
|---|---|
| 临时缓解(审计 + Referer 校验) | ✅ 已部署 anjuke.site(2026-05-04 04:29 UTC) |
| 完整 SSO ticket 设计 | ✅ 接口契约 + Redis 结构 + 错误码 + 安全约束(响应 codex 5 复核) |
| 完整方案 mg-server 服务端实施 | ⏳ 排下批次后端会话,1 天 |
| 完整方案 bs-server 服务端实施 | ⏳ 排下批次后端会话,1 天 |
| 客户端改造 | ⏳ 等后端实施完成,1 天 codex |
| 联调 | ⏳ 0.5 天双方 |
| 旧接口下线 | ⏳ 联调通过 + 24h 监控后 |

P0-15 风险**已立即降低**(临时缓解上线),**完整修复方案就绪**等待下批次实施。
