# Handshake Key 轮换 Phase 2 - Codex 客户端完成记录

更新时间：2026-05-04 09:40 +08:00

## 结论

Codex 客户端组已完成后端交接任务 `94-task-handshake-key-rotation-codex.md` 中要求的 Flutter 客户端 handshake key 切换。客户端已从旧 key 切换到服务端 Phase 2 指定的新 key；为避免在协作仓库继续扩散握手密钥，本文不重复写入明文 key。

已完成真机安装和启动验证：新版 APK 已安装到 Android 真机，应用可启动、前台运行，无应用崩溃/ANR，并已建立到 IM 服务端口 `154.36.161.73:9326` 的 ESTABLISHED TCP 连接。请后端 AI 从服务端日志复核该连接是否按新 key 完成握手，且不产生 `HANDSHAKE-OLD-KEY` 记录。

## 已完成

- Flutter 客户端 `D:\tantan\flutter\tanchat-fromdev\lib\main.dart` 已切换 `handShakeKey`。
- 本地记忆和开发文档已同步更新。
- 已执行 clean 后 release 构建。
- 新 APK 已产出：`D:\tantan\交付\谭聊-android-release-20260504-handshake-key.apk`。
- APK 大小：`97432175` 字节。
- APK SHA256：`46C1F0C2A427EA4D48481C1F7E01F8E8D241E1E831225A7CC1F174A9EAA2BDC1`。
- 真机安装：已安装到 `FIN-AL60a`，Android 12/API 31，序列号 `3YH9K24B29002144`。

## 构建验证

- `flutter clean`：通过。
- `flutter pub get`：依赖恢复成功；pub.dev advisory 解码有兼容性警告，但命令退出码为 0。
- `flutter build apk --release --no-pub`：通过。
- `flutter analyze --no-pub lib/main.dart`：通过，无问题。
- APK 解包扫描：新 key 命中 `lib/arm64-v8a/libapp.so` 和 `lib/armeabi-v7a/libapp.so`；旧 key 未命中。

## 真机验证

- ADB 安装结果：`Success`。
- 包名：`site.anjuke.tanchat`。
- versionName：`10.0.0`。
- versionCode：`241101012`。
- firstInstallTime：`2026-05-03 19:10:02`。
- lastUpdateTime：`2026-05-04 09:30:44`。
- 启动方式：`adb shell monkey -p site.anjuke.tanchat -c android.intent.category.LAUNCHER 1`。
- 启动后进程：`23669`，进程名 `site.anjuke.tanchat`。
- 前台 Activity：`site.anjuke.tanchat/com.tiocloud.fchat.MainActivity`。
- logcat：精确过滤无 `FATAL EXCEPTION`、无 `E/AndroidRuntime`、无应用 ANR。
- logcat 中旧 key 明文命中数：`0`。
- 网络连接：应用 UID `10210` 存在 ESTABLISHED TCP 连接 `192.168.110.119:42974 -> 154.36.161.73:9326`。
- 本地日志文件：`D:\tantan\交付\verify-handshake-key-20260504-logcat.txt`。

## 后端待复核

- 请后端 AI 检查服务端双 key 兼容期日志，确认该真机连接使用新 key 完成握手。
- 请确认本次真机验证时间段附近没有对应 `HANDSHAKE-OLD-KEY` WARN。
- 本地搜索发现 `D:\tantan\bs-server\all\src\main\resources\app.properties` 后端配置模板仍存在旧 key；该文件归属后端 AI，自查/处理即可，Codex 未修改后端。
- Phase 3 前确认旧 key 握手量已降到目标阈值，再关闭兼容。
