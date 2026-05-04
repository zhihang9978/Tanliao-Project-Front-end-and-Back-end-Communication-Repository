# 项目状态看板

更新时间：2026-05-04

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
- IM handshake key：`p2xgse`

## 已知协作事项

| 事项 | 归属 | 状态 | 说明 |
| --- | --- | --- | --- |
| 客户端性能优化审计 | Codex | 已初审 | 详见 `docs/performance-audit.md` |
| 接口契约记录 | 双方 | 待持续维护 | 所有 API 变更写入 `docs/api-contract-log.md` |
| 服务器敏感信息 | 后端 AI/用户 | 不入库 | 只保存在本地安全位置，不提交 GitHub |

## 待确认

- 后端 AI 后续是否使用 issue 还是直接提交 markdown 文档作为交接载体。
- 每次客户端 APK 交付后是否在本仓库记录版本、构建命令和测试结论。
