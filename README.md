# 谭聊项目 - 前后端 AI 沟通仓库

这个仓库用于 Codex（客户端/前端 AI）与后端 AI 之间记录协作边界、接口约定、联调问题、决策记录和交接状态。

## 使用原则

- 只提交协作信息、接口契约、问题定位、复现步骤、非敏感配置说明。
- 禁止提交服务器密码、SSH 密钥、数据库密码、第三方 AppSecret、Token、证书私钥。
- 客户端问题先由 Codex 分析定位；涉及 API、服务器、数据库、Nginx、Redis、MySQL、systemd、TURN 服务时，记录到本仓库并交给后端 AI 对齐。
- 后端变更应说明接口路径、请求参数、响应字段、兼容性、部署时间和回滚方式。
- 客户端变更应说明影响页面、包名、版本号、APK 路径、构建方式和测试结论。

## 当前项目基线

- 主域名：`anjuke.site`
- API 域名：`https://api.anjuke.site`
- 资源域名：`https://res.anjuke.site/`
- Flutter 客户端：`D:\tantan\flutter\tanchat-fromdev`
- Flutter 公共包：`D:\tantan\flutter\app_common`
- IM 公共包：`D:\tantan\flutter\app_common_chat`
- Android applicationId：`site.anjuke.tanchat`
- 当前客户端版本来源：以本地 `D:\tantan` 源码为准。

## 目录说明

- `AGENTS.md`：前后端 AI 协作规则。
- `PROJECT_STATE.md`：当前状态看板。
- `docs/client-backend-boundary.md`：客户端/后端职责边界。
- `docs/api-contract-log.md`：接口约定与变更记录。
- `docs/handoff-template.md`：交接模板。
- `docs/decision-log.md`：决策记录。
- `docs/performance-audit.md`：客户端性能审计记录。

## 工作流

1. 先判断问题属于客户端、后端，还是两边联动。
2. 客户端可独立处理的问题由 Codex 修改客户端源码。
3. 需要后端配合的问题，先在本仓库记录接口/行为约定，再由后端 AI 实施。
4. 联调完成后更新 `PROJECT_STATE.md` 和相关记录文档。
