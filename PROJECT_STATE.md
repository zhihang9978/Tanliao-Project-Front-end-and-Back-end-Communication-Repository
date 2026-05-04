# 项目状态看板

更新时间：2026-05-04 09:50 +08:00

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
- 最新 APK：`D:\tantan\交付\谭聊-android-release-20260504-handshake-key.apk`
- 真机验证：已在 `FIN-AL60a` Android 12/API 31 上安装并启动，包更新时间 `2026-05-04 09:30:44`。
- IM 连接验证：真机应用 UID `10210` 已建立 ESTABLISHED TCP 连接到 `154.36.161.73:9326`。

## 已知协作事项

| 事项 | 归属 | 状态 | 说明 |
| --- | --- | --- | --- |
| Handshake key 轮换 Phase 1 | 后端 AI | ✅ 完成 | `handoffs/2026-05-04-handshake-key-rotation-backend-confirmed.md` |
| Handshake key 轮换 Phase 2 | Codex + 后端 AI | ✅ 真机验证闭环 | `handoffs/2026-05-04-handshake-key-rotation-device-verified.md` |
| Handshake key 轮换 Phase 3 | 后端 AI | ✅ **已立即执行**(应用户要求,跳过 14 天观察期):删除 `app.handshake.key.old`,旧 `p2xgse` 完全失效 | `handoffs/2026-05-04-handshake-key-rotation-phase3-completed.md` |
| 客户端性能优化审计 | Codex | 已初审 | 详见 `docs/performance-audit.md` |
| 接口契约记录 | 双方 | 待持续维护 | 所有 API 变更写入 `docs/api-contract-log.md` |
| 服务器敏感信息 | 后端 AI/用户 | 不入库 | 只保存在本地安全位置，不提交 GitHub |

## 待确认

- ✅ 后端 AI 使用双 key 兼容期日志确认该真机连接按新 key 完成握手，且不产生 `HANDSHAKE-OLD-KEY` 记录。**已确认 2026-05-04 01:45 UTC**
- ✅ 后端 AI 复核运行配置和后端源码模板中旧 handshake key 是否已全部处理。**已确认**
- ✅ Phase 3 已立即执行(2026-05-04 01:50 UTC),旧 key 完全失效。**应用户要求"旧密钥应失效删除,不然安全措施无效"**
- ⚠️ Web tioim / tioim-small / mg-page 客户端若仍用旧 key 会**立即握手失败**;请 Codex 立即检查并发版
- ⚠️ iOS 客户端若启用同上
- ⏳ 每次客户端 APK 交付后是否在本仓库记录版本、构建命令和测试结论。
