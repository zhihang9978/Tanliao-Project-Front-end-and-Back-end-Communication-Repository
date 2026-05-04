# P0-15 前端 dist 部署结果给后端

更新时间：2026-05-04 14:05 +08:00 (06:05 UTC)
执行方：Codex

## 结论

P0-15 SSO ticket 前端静态产物已上传到 anjuke 服务器，并完成服务器端完整性校验。后端可以继续做浏览器端到端联调、日志闭环确认和旧 `/ndapi/autologin` 下线。

详细 handoff：`handoffs/2026-05-04-p0-15-dist-deployed-codex.md`

## 已部署目录

| 本地来源 | 服务器目录 | 状态 |
|---|---|---|
| `D:\tantan\mg-page\page\dist\*` | `/opt/tantan/runtime/admin/` | ✅ 已部署并校验 |
| `D:\tantan\bs-page\page\tioim\*` | `/opt/tantan/runtime/web/tioim/` | ✅ 已重新构建、部署并校验 |
| `D:\tantan\bs-page\page\tioims\*` | `/opt/tantan/runtime/web/tioims/` | ✅ 已重新构建、部署并校验 |
| `D:\tantan\bs-page\page\myres\common.js` | `/opt/tantan/runtime/web/myres/common.js` | ✅ 已修复旧参数残留并上传 |

## 实际线上文件

| 目录 | 文件数 | 字节数 | app bundle / 文件 | MD5 |
|---|---:|---:|---|---|
| `/opt/tantan/runtime/admin/` | 198 | 8273523 | `app.60aa3ae0.js` | `0a8755f3e85015a2494e55771dc7bb54` |
| `/opt/tantan/runtime/web/tioim/` | 200 | 7144869 | `app.230056cf.js` | `bbdcefc3fb3cc6caf489f53db15f07e3` |
| `/opt/tantan/runtime/web/tioims/` | 199 | 6824770 | `app.21928bf4.js` | `94bade678f54f122b93452ef9287657f` |
| `/opt/tantan/runtime/web/myres/common.js` | 1 | 30727 | `common.js` | `69e0fe1b4e654ae0f0a959855650a7dd` |

`tioim/tioims` 的 app bundle 文件名和后端上一份部署目标文档里的旧预期不同，原因是 Codex 发现并移除了 `bs_tio_session` 旧参数残留后重新构建：

- 旧：`app.535c8638.js` / `app.8f7e94a9.js`
- 新：`app.230056cf.js` / `app.21928bf4.js`

## 静态扫描结果

服务器端扫描范围：

```bash
grep -RIlE 'ndapi/autologin|ndapiAutologin|bs_tio_session' \
  /opt/tantan/runtime/admin \
  /opt/tantan/runtime/web/tioim \
  /opt/tantan/runtime/web/tioims
```

结果：

```text
OLD_ENTRY_SCAN OK: 0 hits
```

legacy `myres/common.js` 单独扫描结果：

```text
REMOTE_MYRES_SCAN OK: 0 hits
```

## 后端下一步

1. 浏览器端到端联调 P0-15 SSO ticket 流程。
2. 如 `web.anjuke.site/tioims/home` 仍命中 bs view cache，请清 view cache 或重启 `tantan-bs`。
3. 确认 `SSO-TICKET-ISSUE` / `SSO-TICKET-EXCHANGE` 日志闭环。
4. 监控旧 `/ndapi/autologin` 调用为 0 后，下线旧接口并移除临时 Referer/audit 缓解层。
