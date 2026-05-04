# 上传拒绝提示处理 - Codex 完成记录

更新时间：2026-05-04 10:34 +08:00

## 结论

Codex 已按知识库和上传链路复核后完成客户端处理。后端 P0-06 要求“客户端 UI 处理上传拒绝提示”的方向正确，但 `请登录` 不应作为普通上传错误固定显示在某个页面；它应按登录态失效处理。

本次只修改 Flutter 客户端上传错误处理，不修改后端接口、服务端配置、上传保存逻辑或资源域名。

## 知识库判断

依据本地知识库：

- `项目记忆.md`：涉及服务端/API 的任务必须先从客户端视角分析并整理契约。
- `docs/链路-资源上传与文件预览.md`：上传链路覆盖 `/upload`、`/chat/img`、`/chat/file`、`/chat/audio`、`/chat/video`、`/user/updateAvatar`。
- `docs/客户端二开任务检查清单.md`：上传/媒体改动必须检查上传失败可提示或重试。

判断结果：

- 文件类型、文件名、大小限制属于当前上传动作的业务失败，客户端应在当前页面 Toast。
- 未登录/登录过期属于登录态问题，客户端应走全局踢出登录/重新登录流程，不应只 Toast 一句“请登录”。

## 已改客户端文件

- `flutter/app_common/lib/base/http/utils/upload_error_utils.dart`
- `flutter/app_common/lib/base/http/utils/upload_utils.dart`
- `flutter/app_common/lib/base/http/utils/oa_upload_utils.dart`

## 当前客户端行为

| 服务端返回 | 客户端行为 |
|---|---|
| `code=1001/1002/1003/1010` | 由既有 `TioRespInterceptor` 触发全局登录失效流程，上传工具不额外 Toast |
| `msg=请登录/请先登录/未登录` 且无稳定 code | 客户端兜底触发 `KickOutEvent` |
| `文件类型不允许:*` | 当前页面 Toast：`该文件类型不支持上传：*` |
| `文件名非法` | 当前页面 Toast：`文件名不合法，请重命名后再试` |
| `文件超过大小限制(...)` | 当前页面 Toast，保留大小限制并转换中文括号 |
| 其他失败 `msg` | 当前页面 Toast 原始 `msg` |
| 空失败 `msg` | 当前页面 Toast：`上传失败，请稍后重试` |

覆盖入口：聊天图片/视频/语音/文件、用户头像、朋友圈发布、朋友圈封面、OA/通用上传。

## 验证

- 已格式化 3 个改动 Dart 文件。
- 定向命令：`flutter analyze --no-pub upload_error_utils.dart upload_utils.dart oa_upload_utils.dart`
- 结果：无新增类型错误。
- 剩余提示：`upload_utils.dart` 中既有 `showLoadingDialog` deprecated info，非本次新增问题。

## 后端待对齐

当前 handoff 给到前端的是中文 `msg`，不是稳定错误码。客户端已做兜底，但这不是长期可靠契约。

建议后端后续补充稳定字段，例如：

- `UPLOAD_DENY_ANON`
- `UPLOAD_DENY_EXT`
- `UPLOAD_DENY_PATH`
- `UPLOAD_DENY_SIZE`

或使用数字 `code`，并写入 `docs/api-contract-log.md`。前端后续应优先按稳定 code 判断，中文 `msg` 只作为展示文案。
