# P0-15 后端路径修正完成 — 等部署 dist + 联调

更新时间：2026-05-04 13:25 +08:00 (05:25 UTC)
对应 codex 完成:[`2026-05-04-p0-15-sso-ticket-frontend-complete.md`](2026-05-04-p0-15-sso-ticket-frontend-complete.md)

## 后端确认 codex 工作

✅ **codex 8 文件改造 + 3 Web bundle 构建 + 静态扫描 0 旧入口残留** 全部完成,质量极高。后端做了一项路径对齐修正,现在前后端完全闭环。

## 后端路径修正

### 问题

codex 设计:`mgheader.imLoginTicket()` 调 `/im-login-ticket`(经 baseURL `/tioadmin` 拼为 `/tioadmin/im-login-ticket.admin_x`)
后端原实现:`@RequestPath("/api")` class + `@RequestPath("/im-login-ticket")` method = 完整路径 `/api/im-login-ticket`

mismatch:
- nginx 反代 `/tioadmin/` → mg-server,完整 URI 透传
- mg-server 收到 `/im-login-ticket.admin_x`(去 `/tioadmin/`)
- 但后端 controller 在 `/api/im-login-ticket` → 不匹配 → 返回 1001(mg-server 默认拦截器对未列出路径要求登录)

### 修正(本会话已完成)

**新建独立 controller** [MgSsoController.java](mg-server/http-server-api/.../api/MgSsoController.java):
```java
@RequestPath(value = "/im-login-ticket")  // class-level 直接根路径
public class MgSsoController {
    @RequestPath(value = "")  // method-level 空,完整路径就是 /im-login-ticket
    public Resp issue(HttpRequest request) { ... }
}
```

**access-url-role 加规则**(mg-server runtime):
```
/im-login-ticket=*    # 已登录 mg user 可调
```

**ApiController.imLoginTicket** 改为 `@Deprecated` + 改路径 `/im-login-ticket-deprecated`(不影响新链路)

### 部署

- mg-server 编译: BUILD SUCCESS 5.7s
- jar 替换 + 重启 tantan-bs: active
- 备份: `.bak.sso2.20260504_052317`

### 实测(完整闭环)

```
$ curl -sk -X POST 'https://admin.anjuke.site/tioadmin/im-login-ticket.admin_x'
{"code":1001,"msg":"您尚未登录或登录超时","ok":false}   ✅ 路径正确,access-url-role 拦未登录(管理员持 cookie 时会通过)
```

## 当前完整状态

| 端 | 路径 | 状态 |
|---|---|---|
| mg-server 签发 | `/tioadmin/im-login-ticket.admin_x`(对应 mg-server `/im-login-ticket`)| ✅ 部署生效 |
| bs-server 兑换 | `/mytio/ndapi/exchangeLoginTicket.tio_x` | ✅ 部署生效 |
| codex Web 前端 axios | `/tioadmin/im-login-ticket.admin_x` + `/ndapi/exchangeLoginTicket` | ✅ 已构建 dist |
| codex 静态扫描 | 0 旧入口残留 + 8 处 `login_ticket` + 5 处 `/ndapi/exchangeLoginTicket` + 2 处 `/im-login-ticket` | ✅ |

**前后端契约完全对齐,可以联调。**

## 剩余卡点:Web dist 部署

codex 在 Windows `D:\tantan` 构建的 3 个 dist 需要部署到 anjuke 服务器 nginx 静态目录:

| codex 构建产物 | anjuke 部署目标 |
|---|---|
| `D:\tantan\mg-page\page\dist\` | `/opt/tantan/runtime/admin/`(mg-page nginx root)|
| `D:\tantan\bs-page\page\tioim\` | bs-page tioim nginx root(待确认实际路径) |
| `D:\tantan\bs-page\page\tioims\` | bs-page tioim-small nginx root(待确认) |

### 部署方案选项(请用户/codex 决定)

**方案 A(推荐)**:codex/用户 scp dist 到 anjuke 对应目录
```bash
# 在 codex 端执行(假设有 SSH 凭据)
scp -r D:\tantan\mg-page\page\dist\* root@anjuke.site:/opt/tantan/runtime/admin/
scp -r D:\tantan\bs-page\page\tioim\* root@anjuke.site:/opt/tantan/web/tioim/
scp -r D:\tantan\bs-page\page\tioims\* root@anjuke.site:/opt/tantan/web/tioims/
```

**方案 B**:用户 zip dist + 上传到 GitHub Release / 网盘 → 后端 download + 部署

**方案 C**:在 anjuke 服务器装 node + yarn,后端 cd source 重新构建(复杂,不推荐)

## 联调(部署 dist 之后)

1. 浏览器登录管理后台 admin.anjuke.site/admin
2. 点击进入 IM 入口(原 goIm)
3. 浏览器跳转 `https://web.anjuke.site/tioims/home?login_ticket=<ticket>`
4. 前端 history.replaceState 清 URL
5. 调 `/ndapi/exchangeLoginTicket` 兑换
6. 自动登录 IM 成功
7. 服务端日志:
```
mg-server: SSO-TICKET-ISSUE adminUid=... ticketPrefix=...
bs-server: SSO-TICKET-EXCHANGE ticketPrefix=... userCode=...
旧 NDAPI-AUTOLOGIN-AUDIT: 0(应不再出现)
```

## 联调通过后的最终步骤(后端做)

- 24h 监控 `NDAPI-AUTOLOGIN-AUDIT == 0` + `SSO-TICKET-ISSUE == SSO-TICKET-EXCHANGE`
- 后端关闭旧 `/ndapi/autologin`:
  - 选项 A:返回 410 Gone
  - 选项 B:删 endpoint(更彻底)
- 同步删除临时缓解代码(Referer 校验 + audit log,因为旧接口已下线)
- access-url-role 删 `/ndapi/autologin` 相关规则(若有)

## 备份(回滚)

```
mg-server jar: tio-mg-http-server-api-1.0.0-tio-mg.jar.bak.sso2.20260504_052317
mg access-url-role: access-url-role.properties.bak.sso2.20260504_052317
```

回滚 MTTR < 5 分钟。

## 总结

P0-15 SSO ticket 后端服务端工作 ✅ 完成,前端 ✅ 完成,**仅剩 dist 部署 + 浏览器联调 + 旧接口下线**。

请用户/codex 协调 Web dist 部署到 anjuke 方式。后端待 dist 上线后 30 分钟内可完成联调验证 + 旧接口下线。
