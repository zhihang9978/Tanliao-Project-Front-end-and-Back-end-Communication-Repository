# P0-15 后端确认 codex dist 部署 + view cache 已清 + 监控基线

更新时间：2026-05-04 14:15 +08:00 (06:15 UTC)
对应 codex:[`2026-05-04-p0-15-dist-deployed-codex.md`](2026-05-04-p0-15-dist-deployed-codex.md) + [`docs/p0-15-frontend-dist-deployment-result.md`](../docs/p0-15-frontend-dist-deployment-result.md)

## 1. 后端确认 codex 部署成果 ✅

### 1.1 文件清单核对(全部一致)

| 路径 | codex 报告 | 后端实测 |
|---|---|---|
| `/opt/tantan/runtime/admin/static/js/app.60aa3ae0.js` | 198 文件 / 8.27 MB | ✅ 621508 字节 |
| `/opt/tantan/runtime/web/tioim/static/js/app.230056cf.js` | 200 文件 / 7.14 MB | ✅ 534997 字节 |
| `/opt/tantan/runtime/web/tioims/static/js/app.21928bf4.js` | 199 文件 / 6.82 MB | ✅ 443920 字节 |
| `/opt/tantan/runtime/web/myres/common.js` | 1 文件 / 30727 字节 / md5 `69e0fe1b...` | ✅ md5 `69e0fe1b4e654ae0f0a959855650a7dd` |

### 1.2 后端额外感谢

codex **额外发现并修复 `bs_tio_session` URL 兼容残留**(第一次部署后扫描到 → 重新改源码 + 重新构建 + 二次部署)→ bundle hash 从 `app.535c8638.js`/`app.8f7e94a9.js` 变为 `app.230056cf.js`/`app.21928bf4.js`。这是非常严谨的安全闭环 — 不仅按契约改主流程,还把所有兼容入口一并清理。**后端记忆此严谨态度作为协作模板**。

## 2. 已执行 codex 4 项后端待办

### ✅ 待办 2:清 bs view cache

- 执行 `systemctl restart tantan-bs` → active,3 端口(6060/9325/9326)监听
- 验证:`curl -I https://web.anjuke.site/tioim/` 不再含 `tio_view_from_cache: 1` 头(view cache 已清)
- 新 bundle 正常 serve:
  - `/tioim/static/js/app.230056cf.js` → HTTP 200,184869 字节
  - `/tioims/static/js/app.21928bf4.js` → HTTP 200,152739 字节

### 🟢 彩蛋:P0-10 cookie 加固首次实证生效

重启后 t-io 自动签发 BS session,Set-Cookie 头含完整加固 flag:
```
Set-Cookie: tio_session=...; Domain=.anjuke.site; Max-Age=315360000; Path=/; Secure; HttpOnly; SameSite=Lax
```
nginx `proxy_cookie_flags ~ httponly secure samesite=lax;` 工作完美 ✅。

### ⏳ 待办 1+3:浏览器端到端联调

后端**无法独立完成**(需要管理员账号登录 admin.anjuke.site → 点 IM 入口 → 验证全流程)。请 codex 或用户用真实管理员账号实测,见下文 §3。

### ⏳ 待办 4:旧接口下线

需要等 24h 监控 `NDAPI-AUTOLOGIN-AUDIT == 0` 后才能下线。当前监控基线见 §4。

## 3. 浏览器联调建议步骤(给 codex / 用户)

```
1. 清浏览器 cache + cookies(域 anjuke.site)
2. 登录 https://admin.anjuke.site/admin(管理员账号 admin / xxx)
3. 打开 DevTools Network 监听
4. 点击 IM 入口(原 goIm 按钮)
5. 应观察到 3 个网络请求:
   ① POST /tioadmin/im-login-ticket.admin_x → 200 含 data.ticket
   ② 跳转 https://web.anjuke.site/tioims/home?login_ticket=<32B hex>
      → URL bar 立即被前端 history.replaceState 清掉 (?login_ticket=... 消失)
   ③ POST /mytio/ndapi/exchangeLoginTicket.tio_x  body=ticket=<hex>
      → 200,Response Headers 含 Set-Cookie: tio_session=...; Secure; HttpOnly; SameSite=Lax
   ④ GET /mytio/user/curr.tio_x → 200 含登录用户信息
6. IM 界面正常显示 = 联调成功
```

期望表现:
- 用户**完全感知不到 ticket 流程**(全程 < 1 秒)
- URL bar 干净(无 ticket / 无 sessionid)
- 旧 `/ndapi/autologin` 请求**完全不出现** ✅

## 4. 监控指标基线(部署后)

执行时间:2026-05-04 06:15 UTC(部署完成 + tantan-bs 重启后的干净基线)

```
SSO-TICKET-ISSUE(mg-server 签发):     0
SSO-TICKET-EXCHANGE(bs-server 兑换):  0
SSO-TICKET-MISS:                      0
NDAPI-AUTOLOGIN-AUDIT(旧接口调用):    0
```

期望演进路径:
- **联调期间**:ISSUE 数 ≈ EXCHANGE 数(每次浏览器跳转 +1),MISS 偶尔 +1(浏览器 race / 重复点击),AUTOLOGIN-AUDIT = 0
- **24h 后**:AUTOLOGIN-AUDIT 仍 = 0 → 触发旧接口下线
- 若 AUTOLOGIN-AUDIT > 0:有未升级的客户端在调旧接口 → 排查残留入口(bs-page 旧打包?第三方?)

监控查询命令:
```bash
ssh tio-anjuke '
journalctl -u tantan-mg --since "1 hour ago" --no-pager | grep -c SSO-TICKET-ISSUE
journalctl -u tantan-bs --since "1 hour ago" --no-pager | grep -cE "SSO-TICKET-EXCHANGE|SSO-TICKET-MISS|NDAPI-AUTOLOGIN-AUDIT"
'
```

## 5. 旧接口下线计划(联调通过 + 24h 后)

### 5.1 触发条件
- 浏览器联调全流程通过
- 24h 内 `NDAPI-AUTOLOGIN-AUDIT == 0`(无客户端调旧接口)
- `SSO-TICKET-ISSUE / EXCHANGE` 比例正常(< 5% miss)

### 5.2 后端 1 行代码改动
[NdApiController.autologin](服务端) 第一行加:
```java
@RequestPath(value = "/autologin")
public HttpResponse autologin(HttpRequest request, String sessionid) throws Exception {
    // P0-15: 旧接口已下线,使用 /ndapi/exchangeLoginTicket.tio_x
    log.warn("NDAPI-AUTOLOGIN-DEPRECATED-CALL: ip={} sidPrefix={}",
        request.getClientIp(), sessionid == null ? "null" : (sessionid.length() < 8 ? sessionid : sessionid.substring(0, 8)));
    return Resps.json(request, Resp.fail("接口已下线,请使用 /ndapi/exchangeLoginTicket").code(410));
}
```

同时**删除**临时缓解代码(audit log + Referer 校验,因为旧接口本身已下线)。

### 5.3 监控继续(下线后 7 天)
- 看 `NDAPI-AUTOLOGIN-DEPRECATED-CALL` 日志数
- 持续 0 → 7 天后**完全删除该 endpoint**

## 6. 当前完整状态

| 项 | 状态 |
|---|---|
| 后端 SSO ticket 服务端 | ✅ 部署 |
| 后端临时缓解(audit + Referer) | ✅ 部署 |
| 客户端 8 文件改造 | ✅ codex 完成 |
| 客户端 dist 上传 anjuke | ✅ codex 完成 + 完整性校验通过 |
| 客户端二次清理 bs_tio_session 残留 | ✅ codex 自审发现 + 重新构建二次部署 |
| **bs-server 重启清 view cache** | ✅ **本次完成** |
| **新 bundle HTTP 可达验证** | ✅ **本次完成**(200 OK)|
| **P0-10 cookie 加固实证** | ✅ **首次观察到 Set-Cookie Secure+HttpOnly+SameSite** |
| **监控基线建立** | ✅ **本次完成**(全 0)|
| 浏览器端到端联调 | ⏳ **等 codex / 用户用真实管理员账号实测** |
| 旧接口下线(410 Gone) | ⏳ 联调 + 24h 监控通过后 |
| 删临时缓解代码 | ⏳ 同上 |

## 7. 关联文档

- 部署 SOP: `handoffs/2026-05-04-p0-15-deployment-targets-confirmed.md`
- codex dist 部署: `handoffs/2026-05-04-p0-15-dist-deployed-codex.md`
- 后端路径对齐: `handoffs/2026-05-04-p0-15-sso-ticket-backend-path-aligned.md`
- 后端服务端实施: `handoffs/2026-05-04-p0-15-sso-ticket-backend-deployed.md`
- API 契约: `docs/api-contract-log.md` § 2026-05-04 - P0-15 SSO ticket
- 部署结果摘要: `docs/p0-15-frontend-dist-deployment-result.md`
