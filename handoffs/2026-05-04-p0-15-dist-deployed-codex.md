# P0-15 Codex 前端 dist 已部署到 anjuke 并完成完整性校验

更新时间：2026-05-04 13:56 +08:00 (05:56 UTC)
执行方：Codex
范围：只使用本地 `D:\tantan` 构建产物；服务器端只处理后端已确认的三套前端静态目录。

## 1. 部署结果

已部署到后端确认目录：

| 前端产物 | 服务器目录 | 状态 |
|---|---|---|
| `D:\tantan\mg-page\page\dist\*` | `/opt/tantan/runtime/admin/` | ✅ 已部署并校验 |
| `D:\tantan\bs-page\page\tioim\*` | `/opt/tantan/runtime/web/tioim/` | ✅ 已重新构建、部署并校验 |
| `D:\tantan\bs-page\page\tioims\*` | `/opt/tantan/runtime/web/tioims/` | ✅ 已重新构建、部署并校验 |

说明：第一次上传后，远端静态扫描发现 `tioim/tioims` bundle 内仍残留 `bs_tio_session` 字符串。Codex 已按 P0-15 SSO ticket 契约移除两套 Web 源码里的旧 `bs_tio_session` URL 参数兼容逻辑，仅保留 `login_ticket`，重新构建并二次部署。

## 2. 实际线上 bundle 与 MD5

| 目录 | 文件数 | 字节数 | app bundle | MD5 |
|---|---:|---:|---|---|
| `/opt/tantan/runtime/admin/` | 198 | 8273523 | `app.60aa3ae0.js` | `0a8755f3e85015a2494e55771dc7bb54` |
| `/opt/tantan/runtime/web/tioim/` | 200 | 7144869 | `app.230056cf.js` | `bbdcefc3fb3cc6caf489f53db15f07e3` |
| `/opt/tantan/runtime/web/tioims/` | 199 | 6824770 | `app.21928bf4.js` | `94bade678f54f122b93452ef9287657f` |

注意：`tioim/tioims` 的 app bundle 文件名已从上一轮文档中的 `app.535c8638.js` / `app.8f7e94a9.js` 变更为上表新文件名，原因是移除了 `bs_tio_session` 残留并重新构建。

## 3. 完整性校验

校验方式：

- 本地构建产物生成 MD5 manifest。
- 上传到 `.new` 临时目录。
- 服务器端 `md5sum -c --quiet` 校验全部文件。
- 校验通过后原子切换目录。
- 最终目录再次校验文件数、总字节数和 app bundle MD5。

结果：✅ 全部通过。

## 4. 旧入口静态扫描

服务器扫描命令范围：

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

## 5. HTTP 静态资源可访问性

服务器侧 HEAD 验证：

| URL | 结果 |
|---|---|
| `https://admin.anjuke.site/static/js/app.60aa3ae0.js` | HTTP 200 |
| `https://web.anjuke.site/tioim/static/js/app.230056cf.js` | HTTP 200 |
| `https://web.anjuke.site/tioims/static/js/app.21928bf4.js` | HTTP 200 |

## 6. 后端接手事项

Codex 前端部署与完整性校验已完成。请后端继续：

1. 浏览器端到端联调 P0-15 SSO ticket 流程。
2. 如 `web.anjuke.site/tioims/home` 仍命中 bs view cache，请清 view cache 或重启 `tantan-bs`。
3. 确认 `SSO-TICKET-ISSUE` / `SSO-TICKET-EXCHANGE` 日志闭环。
4. 监控旧 `/ndapi/autologin` 调用为 0 后，下线旧接口并移除临时 Referer/audit 缓解层。

## 7. Codex 本地源码变更

本轮为满足旧入口 0 命中，额外修改：

- `D:\tantan\bs-page\page\tioim-src\src\main.js`
- `D:\tantan\bs-page\page\tioim-small-src\src\main.js`

变更内容：删除 `bs_tio_session` 查询参数读取和 URL 清理兼容逻辑，只处理新的 `login_ticket`。
