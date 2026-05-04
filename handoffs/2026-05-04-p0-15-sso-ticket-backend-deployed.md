# P0-15 SSO ticket 服务端已上线 — 等 codex 改前端

更新时间：2026-05-04 12:55 +08:00 (04:55 UTC)
对应方案:[`2026-05-04-p0-15-mitigation-deployed-and-plan.md`](2026-05-04-p0-15-mitigation-deployed-and-plan.md)

## 结论

**P0-15 SSO ticket 完整服务端实施已部署 anjuke.site**(用户原话"安全不能拖延",未拖到下批次,本会话立即完成)。两端接口已可调,基本测试全部通过。**等 codex 改前端 5 个文件 + 重新构建 Web 部署 + 联调通过 → 下线旧 `/ndapi/autologin`**。

## 1. 已上线接口

### A. mg-server 签发(浏览器侧调用)

```
POST /api/im-login-ticket.admin_x
Cookie: tio_mg_session=<管理端 session>(浏览器同域自动带)
Body(可选 form 或 JSON): { "audience": "tioim-web" | "tioim-small" }   # 缺省 tioim-web

成功响应 200:
{
  "code": 0, "ok": true,
  "data": { "ticket": "<32B hex>", "expiresIn": 60 }
}

失败响应:
1001 mg session 未登录 / 已失效(实际由 access-url-role 拦截器返回 "您尚未登录或登录超时")
1003 mg user 状态异常
1004 audience 不在白名单
```

**实测验证**:
```
$ curl -X POST 'http://admin.anjuke.site/api/im-login-ticket.admin_x'  (无 cookie)
{"code":1001,"msg":"您尚未登录或登录超时","ok":false}   ✅
```

### B. bs-server 兑换(Web 端调用,无需登录态)

```
POST /mytio/ndapi/exchangeLoginTicket.tio_x
Content-Type: application/x-www-form-urlencoded 或 application/json
Body: ticket=<32B hex>   或   { "ticket": "..." }

成功响应 200(同时 Set-Cookie 创建 BS 用户端 session):
Resp.ok()(沿用 StdSynUser.autoLogin 现有完整 BS session 创建逻辑)
Set-Cookie: tio_session=<BS session>; Domain=.anjuke.site; Path=/; HttpOnly; Secure; SameSite=Lax

失败响应:
1010 ticket 为空
1011 ticket 不存在 / 已使用 / 已过期(60s TTL + one-shot)
```

**实测验证**:
```
$ curl -X POST 'http://api.anjuke.site/mytio/ndapi/exchangeLoginTicket.tio_x'   (空 ticket)
{"code":1010,"msg":"ticket 为空","ok":false}   ✅

$ curl -X POST '...' -d 'ticket=fakefakefakefakefakefakefake0000'
{"code":1011,"msg":"ticket 无效或已过期","ok":false}   ✅
log: SSO-TICKET-MISS: ticketPrefix=fakefake ip=127.0.0.1 ua=null

$ curl -X POST '...' -H 'Content-Type: application/json' -d '{"ticket":"fakefakefakefakefakefakefake0001"}'
{"code":1011,"msg":"ticket 无效或已过期","ok":false}   ✅(JSON 也支持,响应 codex §5)
```

## 2. 关键设计实现细节(响应 codex 5 条复核)

| codex 复核 | 后端实现 |
|---|---|
| **§1 不接受前端传 targetUid** | mg-server 用 `WebUtils.currUser(request)` 从 cookie 拿当前 mg admin → 直接用其 mg user.id 作为 unioncode → bs-server 通过 `tiono` 字段在 user 表查 IM 用户 |
| **§2 Set-Cookie 名用 BS 实际配置** | 兑换接口完全复用 `StdSynUser.autoLogin`,内部用 `httpSession.update(httpConfig)` 由 t-io 框架按 `Const.Http.SESSION_COOKIE_NAME` 自动写 cookie |
| **§3 兑换接口允许未登录访问** | access-url-role 加 `/ndapi/exchangeLoginTicket=`(已部署) |
| **§4 前端清 URL** | 由前端保证(本接口无要求) |
| **§5 form + JSON 双格式** | `request.getParam("ticket")` 优先 form,空则解析 body 为 JSON |

## 3. ticket 存储设计

```
Redis key: sso_ticket:<32B hex>
value(JSON):
{
  "adminUid": <Integer>,           # 发起的 mg admin user.id
  "userCode": "<mg user.id 字符串>",  # bs-server 通过 user.tiono = userCode 找 IM 用户
  "userName": "<loginname>",
  "regCellPhone": "<phone>",
  "isValid": "T",
  "audience": "tioim-web" | "tioim-small",
  "issueTime": <millis>,
  "issueIp": "..."
}
TTL: 60 秒(Redisson `bucket.set(json, 60, TimeUnit.SECONDS)`)
ONE-SHOT: 用 Redisson `bucket.getAndDelete()` 原子读取+删除,防 race
```

## 4. 监控关键字

```bash
ssh tio-anjuke '
echo "签发数:"
journalctl -u tantan-mg --since "24 hours ago" --no-pager | grep -c "SSO-TICKET-ISSUE"
echo "兑换成功数:"
journalctl -u tantan-bs --since "24 hours ago" --no-pager | grep -c "SSO-TICKET-EXCHANGE"
echo "兑换 miss(过期 / 假 ticket / 重复):"
journalctl -u tantan-bs --since "24 hours ago" --no-pager | grep -c "SSO-TICKET-MISS"
echo "签发拒绝(无 mg session):"
journalctl -u tantan-mg --since "24 hours ago" --no-pager | grep -c "SSO-TICKET-DENY"

# 旧接口监控(下线前应趋零)
echo "旧 /ndapi/autologin 调用:"
journalctl -u tantan-bs --since "24 hours ago" --no-pager | grep -c "NDAPI-AUTOLOGIN-AUDIT"
'
```

## 5. 给 codex 的待办(本批次)

请按此顺序改前端:

### 5.1 mg-page 改 跳转 URL(管理后台发起)

**`mg-page/page/src/_admin/components/Header.vue`**(或 App.vue 中实际跳转 IM 的位置)

旧:
```js
const bs_tio_session = getCookie('tio_mg_session');
location.href = imsite + '/tioims/home?bs_tio_session=' + bs_tio_session;
```

新:
```js
// 调 mg-server 新接口签发 ticket(同域自动带 mg cookie)
const resp = await axios.post('/api/im-login-ticket.admin_x', { audience: 'tioim-small' });
if (resp.data.ok) {
  location.href = imsite + '/tioims/home?login_ticket=' + resp.data.data.ticket;
} else {
  // 处理 1001/1003/1004 错误
  alert(resp.data.msg);
}
```

### 5.2 bs-page tioim-src + tioim-small-src 改首屏(Web 端兑换)

**`bs-page/page/tioim-src/src/main.js`** + **`bs-page/page/tioim-small-src/src/main.js`**

旧:
```js
const bs_tio_session = getQueryParam('bs_tio_session');
if (bs_tio_session) {
  changeURLArgs([['bs_tio_session', '']]);
  ajax.post('/ndapi/autologin', { data: { sessionid: bs_tio_session }, ... });
}
```

新:
```js
const login_ticket = getQueryParam('login_ticket');
if (login_ticket) {
  // 立即清 URL(响应 codex §4 防止泄露)
  history.replaceState(null, '', window.location.pathname);
  // 兑换 BS session
  const resp = await user.exchangeLoginTicket({ ticket: login_ticket });
  if (resp.ok) {
    location.reload();   // 重新走正常流程,带 cookie 调 /user/curr
  } else {
    // 处理 1010/1011 错误,跳登录页
    layer.alert(resp.msg);
  }
}
```

### 5.3 axios 加新方法

**`bs-page/page/tioim-src/src/axios/path.js`** + **`bs-page/page/tioim-small-src/src/axios/path.js`**

```js
// 加方法:
exchangeLoginTicket(data) {
  return fetchPost("/ndapi/exchangeLoginTicket", data);
}
```

### 5.4 myres/common.js 同步重构(若仍依赖)

`bs-page/page/myres/common.js` 中如有旧 `/ndapi/autologin + bs_tio_session` 逻辑,同步改成 `login_ticket + exchangeLoginTicket`。

## 6. 联调步骤(双方协作)

1. ✅ 后端服务端 已部署
2. ⏳ codex 改前端 5 文件 + 重新构建 Web 静态产物 + 部署到 nginx
3. ⏳ 浏览器实测:管理后台 admin 用户 → 跳转小屏 IM → 验证自动登录成功
4. ⏳ 监控:`SSO-TICKET-ISSUE` 数 = `SSO-TICKET-EXCHANGE` 数(无 miss)+ 旧 `NDAPI-AUTOLOGIN-AUDIT` 趋零
5. ⏳ 24h 监控通过 → 后端下线旧 `/ndapi/autologin`(改为返回 410 Gone 或直接删 endpoint)

## 7. 部署详情

```
mg-server 编译:tio-mg-http-server-api BUILD SUCCESS 2.6s
bs-server 编译:tio-site-http-server-api + tio-site-service-sdk BUILD SUCCESS 5.2s

mg-server jar:tio-mg-http-server-api-1.0.0-tio-mg.jar(md5 51bff385...)
bs-server jar:
  tio-site-http-server-api-1.0.0-tio-sitexxx.jar(md5 6e845a7d...)
  tio-site-service-sdk-1.0.0-tio-sitexxx.jar(md5 6bf7ca71...)

access-url-role 加规则:/ndapi/exchangeLoginTicket=

重启:
  systemctl restart tantan-mg → active(2 端口监听)
  systemctl restart tantan-bs → active(3 端口监听)
  启动异常: 0(过滤 framework noise)
```

## 8. 备份(回滚用)

```
/opt/tantan/runtime/mg/lib/tio-mg-http-server-api-1.0.0-tio-mg.jar.bak.sso.20260504_045215
/opt/tantan/runtime/bs/lib/tio-site-http-server-api-1.0.0-tio-sitexxx.jar.bak.sso.20260504_045215
/opt/tantan/runtime/bs/lib/tio-site-service-sdk-1.0.0-tio-sitexxx.jar.bak.sso.20260504_045215
/opt/tantan/runtime/bs/config/access-url-role.properties.bak.sso.20260504_045215
```

应急回滚 MTTR < 5 分钟。

## 9. 当前状态

| 项 | 状态 |
|---|---|
| 后端临时缓解(审计 + Referer) | ✅ 已部署(早 30 分钟) |
| 后端 SSO ticket 完整实现 | ✅ **已部署 anjuke.site 04:55 UTC** |
| 接口可达性测试 | ✅ 4 项基本测试通过 |
| 端到端真实 mg login 联调 | ⏳ 等 codex 浏览器侧做 |
| 客户端前端改造 | ⏳ codex 改 5 文件 + 重新构建 |
| 旧 `/ndapi/autologin` 下线 | ⏳ 联调通过 + 24h 监控趋零后 |

## 10. 关联

- 后端完整 fix plan: `analysis/94-fix-plan-P0-15-sso-ticket.md`
- codex 紧急回复: [`2026-05-04-p0-15-security-no-delay-codex.md`](2026-05-04-p0-15-security-no-delay-codex.md)
- 后端临时缓解: [`2026-05-04-p0-15-mitigation-deployed-and-plan.md`](2026-05-04-p0-15-mitigation-deployed-and-plan.md)
