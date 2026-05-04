# P0-15 Codex 已启用管理后台 IM 入口并部署 mg-page

更新时间：2026-05-04 14:25 +08:00 (06:25 UTC)
执行方：Codex
责任范围：前端 mg-page 管理后台 UI + 静态 dist 部署。

## 1. 结论

后端提出的阻塞点已处理：管理后台 `Header.vue` 中被注释的 IM 入口按钮已启用，`goIm()` 现有 SSO ticket 流程可由管理员在 UI 中点击触发。

已重新构建 `mg-page/page/dist` 并部署到：

```text
/opt/tantan/runtime/admin/
```

## 2. 本地源码改动

文件：

```text
D:\tantan\mg-page\page\src\_admin\components\Header.vue
```

改动：

```html
<span class="operitem recent-col" @click="goIm">
    IM
</span>
```

说明：只恢复入口按钮，不改变 `goIm()` 的 SSO ticket 逻辑。`goIm()` 仍调用：

```text
POST /tioadmin/im-login-ticket.admin_x
```

成功后跳转：

```text
https://web.anjuke.site/tioims/home?login_ticket=<ticket>
```

## 3. 构建结果

本地构建命令：

```powershell
vue-cli-service build
```

构建结果：

| 目录 | 文件数 | 字节数 | app bundle | MD5 |
|---|---:|---:|---|---|
| `D:\tantan\mg-page\page\dist` | 198 | 8273604 | `app.9a2b497e.js` | `a3a2132c511862bf8d6ba08b7f258ebd` |

构建警告：仅 webpack 体积警告，未阻断构建；和此前 mg-page 构建性质一致。

## 4. 部署与完整性校验

部署方式：

1. 上传到 `/opt/tantan/runtime/admin.new/`
2. 服务器端 `md5sum -c --quiet` 校验全部文件
3. 原子切换：`admin` 备份为 `admin.bak.before-im-entry.<timestamp>`，`admin.new` 切换为 `admin`
4. 最终目录再次校验

服务器最终结果：

```text
REMOTE_FINAL admin: files=198 bytes=8273604
a3a2132c511862bf8d6ba08b7f258ebd  /opt/tantan/runtime/admin/static/js/app.9a2b497e.js
```

`index.html` 已引用新 bundle：

```text
static/js/app.9a2b497e.js
```

HTTP 可访问性：

```text
https://admin.anjuke.site/static/js/app.9a2b497e.js -> HTTP 200
content-length: 621589
```

## 5. 静态扫描

旧入口扫描：

```bash
grep -RIlE 'ndapi/autologin|ndapiAutologin|bs_tio_session' /opt/tantan/runtime/admin
```

结果：

```text
ADMIN_OLD_ENTRY_SCAN OK: 0 hits
```

新 SSO 入口扫描：

```text
/opt/tantan/runtime/admin/static/js/app.9a2b497e.js
```

该 bundle 包含：

```text
im-login-ticket
login_ticket
```

## 6. 服务端 smoke

未带登录 Cookie 直接请求签发接口：

```bash
curl -sk -X POST 'https://admin.anjuke.site/tioadmin/im-login-ticket.admin_x'
```

返回：

```json
{"code":1001,"msg":"您尚未登录或登录超时","ok":false}
```

这符合预期：说明路径在线，且未登录访问仍被拦截。

## 7. 后端接手

Codex 已完成按钮启用、mg-page 重建、admin 静态目录部署、完整性校验和静态扫描。

请后端继续：

1. 让用户或后端使用真实管理员会话进入 `https://admin.anjuke.site/admin`。
2. 点击顶栏新增的 `IM` 入口。
3. 观察：
   - `SSO-TICKET-ISSUE` 增加
   - `SSO-TICKET-EXCHANGE` 增加
   - `NDAPI-AUTOLOGIN-AUDIT` 仍为 0
4. 浏览器确认 URL 中 `login_ticket` 被前端清理，IM 页面登录成功。
5. 联调成功 + 24h 旧接口 0 调用后，下线旧 `/ndapi/autologin`。

## 8. 当前阻塞状态

Codex 侧阻塞已解除。

剩余不是代码部署问题，而是需要真实管理员登录态做浏览器端到端验证。