# 头像上传大图等待和大小限制 - Codex 完成记录

更新时间：2026-05-04 10:46 +08:00

## 结论

用户反馈：相册选择头像后长时间显示 loading，最后提示大小限制。

Codex 按知识库和源码链路判断后确认：主要归属客户端体验问题。后端头像 5MB 限制是合理安全策略，不应通过放宽限制作为主修复；客户端此前直接上传相册原图，没有头像级压缩和本地大小预检，导致大图完整上传到服务端后才失败。

## 责任边界

- 客户端负责：头像上传前压缩、体积预检、当前页面提示和 loading 体验。
- 后端负责：保留安全限制、返回稳定错误码、尽量提前拒绝超大请求。
- 本次不修改后端接口、不要求后端放宽头像限制。

## 已改客户端文件

- `flutter/app_common/lib/base/utils/compress_utils.dart`
- `flutter/app_common/lib/base/http/utils/upload_utils.dart`

## 行为变化

- 头像上传前使用头像专用压缩参数：`720x720`、`quality=80`。
- 压缩后本地检查是否超过 `5MB`。
- 超过时立即复用上传错误处理显示大小限制提示，不再上传到后端等待失败。
- 非头像图片上传保持原有默认压缩参数：`1920x1920`、`quality=70`。

## APK

- APK：`D:\tantan\交付\谭聊-android-release-20260504-avatar-compress.apk`
- 大小：`97464943` 字节
- SHA256：`53C2D6F4A1EA41F2B1181AB4298D335FC6408ECB84DE48EB7DE562C3C859572B`

## 验证

- `dart format`：通过。
- 定向 `flutter analyze --no-pub`：无新增类型错误，仅既有 deprecated info。
- `flutter build apk --release --no-pub`：通过。
- ADB 安装：`Success`。
- 真机：`FIN-AL60a`，序列号 `3YH9K24B29002144`。
- 包名：`site.anjuke.tanchat`。
- versionName：`10.0.0`。
- versionCode：`241101012`。
- lastUpdateTime：`2026-05-04 10:46:15`。
- 启动后进程：`7857`，前台 Activity：`site.anjuke.tanchat/com.tiocloud.fchat.MainActivity`。
- logcat：无 `FATAL EXCEPTION`，无 `E/AndroidRuntime`，无应用 ANR。

## 后端建议

后端当前不需要放宽头像大小限制。建议后续继续完善：

- 对头像上传返回稳定 `UPLOAD_DENY_SIZE` 或数字 `code`，不要只依赖中文 `msg`。
- 如果框架支持，在读取完整 multipart 前基于 `Content-Length` 或上传配置尽早拒绝超大请求，进一步减少服务端资源消耗。
