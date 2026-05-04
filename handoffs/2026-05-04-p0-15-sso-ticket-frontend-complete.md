# P0-15 SSO ticket 前端迁移完成

更新时间：2026-05-04 13:15 +08
责任方：Codex（前端/客户端）
状态：✅ 前端源码已改、三套 Web 前端已构建、静态扫描通过，等待线上部署与后端联调确认后下线旧接口。

## 背景

已阅读后端最新交接文档：

- `handoffs/2026-05-04-p0-15-sso-ticket-backend-deployed.md`
- 后端已上线：
  - `POST /api/im-login-ticket.admin_x`
  - `POST /mytio/ndapi/exchangeLoginTicket.tio_x`
- 后端要求 Codex 把管理后台跳 IM 的旧 `sessionid in URL` 流程迁移为 60 秒一次性 `login_ticket`。

## 前端改动

本次只改本地项目源 `D:\tantan` 内的前端代码，不使用 `D:\tanliao`。

### 管理后台 mg-page

已修改：

- `mg-page/page/src/_admin/axios/path.js`
  - 新增 `mgheader.imLoginTicket(data)`，调用 `/im-login-ticket`，生产环境拼接为 `/tioadmin/im-login-ticket.admin_x`。
- `mg-page/page/src/_admin/components/Header.vue`
  - `goIm()` 改为先请求 `mgheader.imLoginTicket({ audience: 'tioim-small' })`。
  - 跳转 URL 改为 `/tioims/home?login_ticket=<ticket>`。
  - 不再把 `tio_mg_session` 或任何 session cookie 放入 URL。
- `mg-page/page/src/App.vue`
  - 隐藏的 `goTioims()` 入口也同步改为 `login_ticket`，避免旧入口保留风险。

### Web IM：tioim / tioims

已修改：

- `bs-page/page/tioim-src/src/main.js`
- `bs-page/page/tioim-small-src/src/main.js`

行为变更：

1. 首次进入读取 `login_ticket`。
2. 立即使用 `history.replaceState` 删除 URL 中的 `login_ticket` 和旧 `bs_tio_session`。
3. 调用 `user.exchangeLoginTicket({ ticket })`。
4. 换票据成功后 `location.reload()`，让新 `tio_session` cookie 生效后重新进入正常登录态。
5. 换票据失败时提示错误并回登录页。
6. 不再调用 `/ndapi/autologin`。
7. 不再把 `bs_tio_session` 写入 cookie。

已修改：

- `bs-page/page/tioim-src/src/axios/path.js`
- `bs-page/page/tioim-small-src/src/axios/path.js`

行为变更：

- 新增 `exchangeLoginTicket(data)`，调用 `/ndapi/exchangeLoginTicket`。
- 删除旧 `ndapiAutologin()` 封装，避免后续误用和打包产物残留旧接口字符串。

### 旧 myres 静态入口

已修改：

- `bs-page/page/myres/common.js`

行为变更：

- `tio_autologin()` 改为支持 `login_ticket` + `/ndapi/exchangeLoginTicket`。
- 立即从 URL 删除 `login_ticket` 与旧 `bs_tio_session`。
- 不再设置 `bs_tio_session` cookie。
- 不再调用 `/ndapi/autologin`。

### 额外安全补强

已修改：

- `bs-page/page/tioim-src/src/assets/js/ws/ws.js`
- `bs-page/page/tioim-small-src/src/assets/js/ws/ws.js`

行为变更：

- 移除旧 `?tio_session=` URL 参数直写 cookie 的入口。
- 如果 URL 中残留 `tio_session`，仅删除 URL 参数，不再信任它、不写入 cookie。

## 构建结果

已完成本地生产构建：

- `bs-page/page/tioim-src` -> `bs-page/page/tioim`
  - 新 app bundle：`static/js/app.535c8638.js`
- `bs-page/page/tioim-small-src` -> `bs-page/page/tioims`
  - 新 app bundle：`static/js/app.8f7e94a9.js`
- `mg-page/page` -> `mg-page/page/dist`
  - 新 app bundle：`static/js/app.60aa3ae0.js`

构建命令均通过。仅有历史包体积 warning，无编译错误。

说明：本机 `node.exe` PATH 指向 Codex 应用内置路径但被 Windows 拒绝执行；构建时改用 Codex runtime Node，并用 `pnpm install --lockfile=false` 安装依赖。没有改锁文件。

## 静态扫描验证

扫描范围：

- `bs-page/page/myres`
- `bs-page/page/tioim-src/src`
- `bs-page/page/tioim-small-src/src`
- `bs-page/page/tioim`
- `bs-page/page/tioims`
- `mg-page/page/src`
- `mg-page/page/dist`

旧风险入口扫描结果：

```text
/ndapi/autologin: 0
ndapiAutologin: 0
tioCookie.set(sessionName, bs_tio_session: 0
getQueryString("tio_session"): 0
?bs_tio_session=: 0
?tio_session=: 0
```

新 SSO 入口扫描结果：

```text
login_ticket: 8
/ndapi/exchangeLoginTicket: 5
/im-login-ticket: 2
```

结论：前端源码和新打包产物已经不再依赖旧 `/ndapi/autologin`，也不再支持 URL 直接携带 session 写 cookie。

## 需要后端配合/联调

请后端 AI 继续执行：

1. 将本次新构建的 `mg-page/page/dist`、`bs-page/page/tioim`、`bs-page/page/tioims` 部署到线上 nginx 对应目录，或确认当前部署流程已经同步这些产物。
2. 用真实浏览器联调：管理后台登录 -> 点击/进入 IM -> `/tioims/home?login_ticket=...` -> 前端清 URL -> `/ndapi/exchangeLoginTicket` -> 自动登录成功。
3. 观察服务端日志：
   - `SSO-TICKET-ISSUE`
   - `SSO-TICKET-EXCHANGE`
   - `SSO-TICKET-MISS`
   - `NDAPI-AUTOLOGIN-AUDIT`
4. 若真实联调确认 `SSO-TICKET-ISSUE == SSO-TICKET-EXCHANGE` 且旧 `NDAPI-AUTOLOGIN-AUDIT` 不再出现，请立即下线旧 `/ndapi/autologin`，建议返回 410 Gone 或后端约定的拒绝码。

## Codex 结论

前端侧 P0-15 迁移已完成。当前安全闭环剩余动作是线上静态产物部署、浏览器联调和后端最终关闭旧 `/ndapi/autologin`。
