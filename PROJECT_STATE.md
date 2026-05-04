# 项目状态看板

更新时间：2026-05-04 10:34 +08:00

## 当前基线

- 项目源码以本地 `D:\tantan` 为准。
- 客户端是 Flutter 跨平台客户端，包含 Android/iOS 原生壳。
- Codex 当前负责客户端/前端；后端 AI 负责服务器端。
- 开发环境短信验证码固定为 `123456`，用于客户端注册测试。

## 域名

- 主域名：`anjuke.site`
- API：`https://api.anjuke.site`
- 资源：`https://res.anjuke.site/`
- TURN：`turn:anjuke.site:3478`

## 客户端状态

- Android applicationId：`site.anjuke.tanchat`
- 当前客户端版本号：`10.0.0+241101012`
- 客户端 API 基础地址：`https://api.anjuke.site`
- 客户端 app context：`/mytio`
- IM handshake key：已按服务端 Phase 2 交接任务切换到新 key；协作仓库不重复公开明文 key。
- 最新 APK：`D:\tantan\交付\谭聊-android-release-20260504-performance-stage123.apk`
- 最新 APK SHA256：`E8F242B412411350EB62DEAEE49C4A5F16D564D3528FF813783AA8079CDB0B8A`
- 真机验证：已在 `FIN-AL60a` Android 12/API 31 上安装并启动，包更新时间 `2026-05-04 10:00:30`。
- IM 连接验证：真机应用 UID `10210` 已建立 ESTABLISHED TCP 连接到 `154.36.161.73:9326`。

## 已知协作事项

| 事项 | 归属 | 状态 | 说明 |
| --- | --- | --- | --- |
| 客户端性能优化阶段 1-3 | Codex | 已完成首轮，真机已验证 | `handoffs/2026-05-04-client-performance-stage123-codex-complete.md` |
| 上传拒绝提示前端处理 | Codex | ✅ 已完成，未登录走登录失效流程，类型/路径/大小走当前页面 Toast | `handoffs/2026-05-04-upload-deny-ui-codex-complete.md` |
| Handshake key 轮换 Phase 1 | 后端 AI | ✅ 完成(2026-05-04 01:05 UTC) | `handoffs/2026-05-04-handshake-key-rotation-backend-confirmed.md` |
| Handshake key 轮换 Phase 2 | Codex + 后端 AI | ✅ 真机验证闭环(09:30:44 之后 0 次 OLD-KEY) | `handoffs/2026-05-04-handshake-key-rotation-device-verified.md` |
| Handshake key 轮换 Phase 3 | 后端 AI | ✅ **已立即执行**(2026-05-04 01:50 UTC,应用户要求跳过 14 天观察期):删除 `app.handshake.key.old`,旧 `p2xgse` 完全失效 | `handoffs/2026-05-04-handshake-key-rotation-phase3-completed.md` |
| **后端批量 P0-06/10/11 + P1-14** | 后端 AI | ✅ 完成 + 部署 + 验证(2026-05-04 02:05 UTC) | `handoffs/2026-05-04-batch-p0-06-10-11-p1-14-completed.md` |
| 客户端性能优化审计 | Codex | 已初审，已落地首轮优化 | `docs/performance-audit.md` |
| 接口契约记录 | 双方 | 待持续维护 | 所有 API 变更写入 `docs/api-contract-log.md` |
| 服务器敏感信息 | 后端 AI/用户 | 不入库 | 只保存在本地安全位置，不提交 GitHub |

## 待确认

- ✅ 后端 AI 使用双 key 兼容期日志确认该真机连接按新 key 完成握手,**已确认 2026-05-04 01:45 UTC** 0 次 HANDSHAKE-OLD-KEY 在 09:30:44 后
- ✅ 后端 AI 复核运行配置和后端源码模板中旧 handshake key,**已处理 2026-05-04**(模板加占位符 `_PLACEHOLDER_REPLACE_BEFORE_DEPLOY` 防回退)
- ✅ Phase 3 已立即执行(2026-05-04 01:50 UTC),旧 key 完全失效
- ✅ Codex 已处理 P0-06 上传拒绝提示：未登录/登录过期走全局登录失效流程，文件类型/文件名/大小限制走当前页面 Toast
- ⚠️ Codex 注意:Web tioim / tioim-small / mg-page / iOS 若仍用旧 `p2xgse` 会立即握手失败,请同步检查
- ⚠️ Codex 注意:浏览器 devtools 看 Web tioim 的 sessionId cookie 是否含 `HttpOnly; Secure; SameSite=Lax`(P0-10 nginx 已加)
- ⚠️ 后端待对齐:上传拒绝当前主要靠中文 `msg`，长期应补稳定 `code/errCode`，例如 `UPLOAD_DENY_ANON/EXT/PATH/SIZE`
- ⏳ 如果后端后续调整消息同步 payload、历史消息分页、资源缩略图策略,需要继续通过本仓库对齐
