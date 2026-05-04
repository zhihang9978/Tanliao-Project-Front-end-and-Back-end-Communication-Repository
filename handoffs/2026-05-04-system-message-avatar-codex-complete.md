# Codex 完成记录：系统消息头像空白修复

更新时间：2026-05-04 16:15 +08:00

## 结论

- 问题归属：客户端问题。
- 后端处理：不需要后端改接口、不需要后端改数据、不需要后端部署。
- 影响范围：Flutter 客户端系统消息历史消息渲染；系统消息列表与系统消息详情页头像兜底显示。

## 问题现象

用户进入 Android 客户端“系统消息”详情页后，左侧头像显示为空的灰色占位块；系统消息卡片内容可以正常显示。

## 根因

`SessionMsgUtils.getMsg_bySystemHistoryMsg()` 在系统消息没有引用消息时，把头像设置为裸文件名 `session_sys_chat_avatar.png`。

该头像最终进入 `WtImage(AssetImage)` 渲染链路，Flutter package asset 需要完整包内资源路径；裸文件名在打包后的 APK 中无法定位资源，导致图片加载失败并显示占位色块。

另外，如果系统消息带引用消息但后端返回的 `avatar` 为空，旧逻辑也没有兜底本地系统头像。

## 客户端改动

- `D:\tantan\flutter\app_common\lib\base\model\utils\session_msg_utils.dart`
  - 使用 `Assets.imageSessionSysChatAvatar.acPkgPref` 作为本地系统消息头像兜底。
  - 当 `quote != null` 但 `data.avatar` 为空时，也兜底本地系统头像。
- `D:\tantan\flutter\app_common\assets\image\session_sys_chat_avatar.png`
  - 替换为“初语”系统消息头像。
- `D:\tantan\flutter\app_common\assets\image\session_sys_chat_cover.png`
  - 替换为“初语”系统消息封面/兜底图。

## 构建产物

- APK：`D:\tantan\交付\初语-android-release-20260504-system-avatar.apk`
- APK 大小：`99472363` 字节
- SHA256：`7B5EE46D236D4327D83842560EC0BB7A4F34244CF92904A87F05DCD7E3FA6A50`
- Android 包名：`site.anjuke.tanchat`
- 版本：`10.0.0+241101012`
- 可见应用名：`初语`

## 验证结果

- `flutter analyze --no-pub --no-fatal-infos ..\app_common\lib\base\model\utils\session_msg_utils.dart` 通过。
- `flutter build apk --release --no-pub` 通过。
- APK 内容确认包含：
  - `assets/flutter_assets/packages/app_common/assets/image/session_sys_chat_avatar.png`
  - `assets/flutter_assets/packages/app_common/assets/image/session_sys_chat_cover.png`
- ADB 安装到真机 `FIN_AL60a` 成功，安装结果 `Success`。
- 安装后包更新时间：`2026-05-04 16:04:47`。
- 启动 `site.anjuke.tanchat/com.tiocloud.fchat.MainActivity` 后前台 Activity 正常。
- 最近 logcat 未发现 `FATAL EXCEPTION`。
- 真机截图确认：系统消息列表和系统消息详情页头像均显示“初语”图标，不再显示空白占位块。

## 给后端 AI

本次没有接口契约变化，也没有服务器端配置依赖。后端只需知悉：客户端对系统消息头像为空的场景已经做本地兜底，后续服务端 `avatar` 字段可以继续为空；若服务端未来下发系统消息头像 URL，客户端仍会优先显示非空 URL。