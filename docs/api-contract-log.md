# 接口契约与变更记录

所有前后端联动变更都记录在这里。

## 记录格式

```md
## YYYY-MM-DD - 变更标题

- 提出方：Codex / 后端 AI / 用户
- 归属：客户端 / 后端 / 双方
- 接口：METHOD /path
- 变更内容：
- 请求示例：
- 响应示例：
- 兼容性：是否兼容旧客户端
- 客户端动作：
- 后端动作：
- 验收方式：
```

## 2026-05-04 - 上传拒绝提示处理

- 提出方：后端 AI + Codex 复核
- 归属：双方
- 接口：
  - `POST /mytio/upload`
  - `POST /mytio/chat/img`
  - `POST /mytio/chat/file`
  - `POST /mytio/chat/audio`
  - `POST /mytio/chat/video`
  - `POST /mytio/user/updateAvatar`
- 变更内容：后端 P0-06 已增加上传登录鉴权、扩展名白名单、路径穿越拦截和大小限制；客户端已统一处理上传拒绝提示。
- 当前响应示例：
  - `{"msg":"请登录","ok":false}`
  - `{"msg":"文件类型不允许:exe","ok":false}`
  - `{"msg":"文件名非法","ok":false}`
  - `{"msg":"文件超过大小限制(50MB)","ok":false}`
- 客户端动作：
  - 登录态错误码 `1001/1002/1003/1010`：走全局登录失效流程。
  - 无稳定 code 但 `msg=请登录/请先登录/未登录`：客户端兜底触发 `KickOutEvent`。
  - 文件类型、文件名、大小限制：当前上传页面 Toast 友好提示。
- 后端动作：
  - 已完成 P0-06 服务端限制。
  - 待补充稳定 `code/errCode`，建议至少覆盖 `UPLOAD_DENY_ANON`、`UPLOAD_DENY_EXT`、`UPLOAD_DENY_PATH`、`UPLOAD_DENY_SIZE`，避免客户端长期依赖中文 `msg` 判断逻辑。
- 兼容性：旧客户端仍会显示服务端 `msg` 或通用失败；新客户端对登录态和 4 类上传拒绝有更明确处理。
- 验收方式：
  - 登录态失效后上传应进入重新登录流程。
  - 上传 `.exe` 等禁用类型应显示“该文件类型不支持上传：exe”。
  - 非法文件名应显示“文件名不合法，请重命名后再试”。
  - 超过大小限制应显示大小限制提示。

## 2026-05-04 - 初始接口基线

- 提出方：Codex
- 归属：双方
- API 域名：`https://api.anjuke.site`
- app context：`/mytio`
- 资源域名：`https://res.anjuke.site/`
- 开发验证码：`123456`
- 说明：当前仅记录基线，不包含敏感密钥和服务器登录信息。

## 待补充

- 登录接口、注册接口、短信验证码接口。
- IM 同步接口、历史消息接口。
- 音视频信令接口、TURN 配置下发接口。
