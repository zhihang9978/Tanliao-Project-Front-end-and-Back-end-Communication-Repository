# P0-15 前端 dist 部署结果给后端

更新时间：2026-05-04 14:25 +08:00 (06:25 UTC)
执行方：Codex

## 结论

P0-15 SSO ticket 前端静态产物已上传到 anjuke 服务器并完成服务器端完整性校验。后续追加完成：管理后台 IM 入口按钮已启用并部署，真实管理员现在可以从 admin 顶栏点击 `IM` 触发 SSO ticket 流程。

详细 handoff：

- `handoffs/2026-05-04-p0-15-dist-deployed-codex.md`
- `handoffs/2026-05-04-p0-15-im-entry-enabled-codex.md`

## 已部署目录

| 本地来源 | 服务器目录 | 状态 |
|---|---|---|
| `D:\tantan\mg-page\page\dist\*` | `/opt/tantan/runtime/admin/` | 已重新构建、启用 IM 入口、部署并校验 |
| `D:\tantan\bs-page\page\tioim\*` | `/opt/tantan/runtime/web/tioim/` | 已重新构建、部署并校验 |
| `D:\tantan\bs-page\page\tioims\*` | `/opt/tantan/runtime/web/tioims/` | 已重新构建、部署并校验 |
| `D:\tantan\bs-page\page\myres\common.js` | `/opt/tantan/runtime/web/myres/common.js` | 已修复旧参数残留并上传 |

## 实际线上文件

| 目录 | 文件数 | 字节数 | app bundle / 文件 | MD5 |
|---|---:|---:|---|---|
| `/opt/tantan/runtime/admin/` | 198 | 8273604 | `app.9a2b497e.js` | `a3a2132c511862bf8d6ba08b7f258ebd` |
| `/opt/tantan/runtime/web/tioim/` | 200 | 7144869 | `app.230056cf.js` | `bbdcefc3fb3cc6caf489f53db15f07e3` |
| `/opt/tantan/runtime/web/tioims/` | 199 | 6824770 | `app.21928bf4.js` | `94bade678f54f122b93452ef9287657f` |
| `/opt/tantan/runtime/web/myres/common.js` | 1 | 30727 | `common.js` | `69e0fe1b4e654ae0f0a959855650a7dd` |

Admin bundle changed:

- old: `app.60aa3ae0.js`
- new: `app.9a2b497e.js`
- reason: enabled visible IM entry button in `mg-page/page/src/_admin/components/Header.vue`.

`tioim/tioims` bundle names changed earlier due to removal of `bs_tio_session`:

- old: `app.535c8638.js` / `app.8f7e94a9.js`
- new: `app.230056cf.js` / `app.21928bf4.js`

## 静态扫描结果

Server-side active static scan:

```bash
grep -RIlE 'ndapi/autologin|ndapiAutologin|bs_tio_session' \
  /opt/tantan/runtime/admin \
  /opt/tantan/runtime/web/tioim \
  /opt/tantan/runtime/web/tioims
```

Result:

```text
OLD_ENTRY_SCAN OK: 0 hits
ADMIN_OLD_ENTRY_SCAN OK: 0 hits
```

Admin SSO bundle scan:

```text
/opt/tantan/runtime/admin/static/js/app.9a2b497e.js
```

contains:

```text
im-login-ticket
login_ticket
```

legacy `myres/common.js` scan:

```text
REMOTE_MYRES_SCAN OK: 0 hits
```

## 后端下一步

1. 使用真实管理员登录 `https://admin.anjuke.site/admin`。
2. 点击顶栏 `IM` 按钮。
3. 验证：`POST /tioadmin/im-login-ticket.admin_x` 返回 `code=0` 和 `data.ticket`。
4. 验证跳转到 `https://web.anjuke.site/tioims/home?login_ticket=<ticket>` 后，前端立即清理 URL 中的 `login_ticket`。
5. 验证 `POST /mytio/ndapi/exchangeLoginTicket.tio_x` 返回 200 并 Set-Cookie。
6. 验证 `GET /mytio/user/curr.tio_x` 返回当前 IM 用户。
7. 后端监控：`SSO-TICKET-ISSUE >= 1`，`SSO-TICKET-EXCHANGE >= 1`，`NDAPI-AUTOLOGIN-AUDIT == 0`。
8. 联调成功并确认 24h 旧接口 0 调用后，下线旧 `/ndapi/autologin`。
