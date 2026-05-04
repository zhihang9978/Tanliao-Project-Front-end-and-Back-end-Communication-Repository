# 客户端性能优化阶段 1-3 - Codex 完成记录

更新时间：2026-05-04 10:05 +08:00

## 结论

Codex 已完成客户端性能优化首轮落地，覆盖用户指定的三阶段方向。所有改动均在 Flutter/客户端范围内完成，未修改后端协议、数据库服务端结构或服务端部署配置。

## 第一阶段：低风险高收益

- Release 默认关闭 debug/info 高频日志，只保留 warning/error/fatal。
- Socket 收发包体日志增加客户端开关，release 默认关闭。
- 会话同步事件采用 50ms 短窗口聚合，减少消息突发时整页频繁刷新。
- 会话同步从嵌套线性扫描改为 `Map<id,index>` 合并，update 未命中时自动插入。
- 聊天列表和消息列表增加稳定 key，减少 Flutter 列表复用抖动。
- `ChatItemWidget` build 阶段不再修改会话 model。

## 第二阶段：本地 DB

- 用户本地 SQLCipher DB version 从 `1` 升级到 `2`。
- Provider 新增 `createIndexSqlList`，DB 创建和升级时自动创建索引。
- 新增热路径索引：
  - `SynChatChatlist(chatLinkId)`
  - `OaChat(cmpid, chatuptime)`
  - `OaChat(chatmode, cmpid, bizid)`
  - `OaChat(cmpid, uid)`
  - `OaPrivatemsg(cmpid, uid, touid, id)`
  - `OaPrivatemsg(cmpid, touid, uid, id)`
  - `OaPrivatemsg(cmpid, uid, touid, contenttype, id)`
  - `OaPrivatemsg(uid, cmpid)`
  - `OaGroupmsg(cmpid, groupid, id)`
  - `OaGroupmsg(cmpid, groupid, contenttype, id)`
  - `OaGroupmsg(uid, cmpid)`
  - `OaGroupmsg(uid, cmpid, groupid)`
- `ChatDao` 批量 insert/replace/update/delete 改用 batch。
- `OaChatDao`、`OaPrivatemsgDao`、`OaGroupmsgDao` 的全量替换和消息批量同步写入路径改用 batch。

## 第三阶段：媒体和大并发体验

- `WtImage` 对网络图和文件图按控件尺寸加 `ResizeImage` 解码提示，降低头像/缩略图内存解码成本。
- 图片上传前压缩限制最大边长 `1920x1920`，避免超大原图直接进入上传链路。
- 图片/视频压缩增加可控耗时埋点，默认只在 debug 打开。
- WebRTC 本轮未改协议；维持既有连接超时、失败回调和资源释放逻辑。

## APK

- APK：`D:\tantan\交付\谭聊-android-release-20260504-performance-stage123.apk`
- 大小：`97448559` 字节
- SHA256：`E8F242B412411350EB62DEAEE49C4A5F16D564D3528FF813783AA8079CDB0B8A`

## 验证

- `flutter build apk --release --no-pub`：通过。
- 定向 `flutter analyze`：无类型错误；剩余为项目既有 info 级提示。
- ADB 安装：`Success`。
- 真机：`FIN-AL60a`，Android 12/API 31，序列号 `3YH9K24B29002144`。
- 包名：`site.anjuke.tanchat`。
- versionName：`10.0.0`。
- versionCode：`241101012`。
- lastUpdateTime：`2026-05-04 10:00:30`。
- 启动后进程：`28142`，前台 Activity：`site.anjuke.tanchat/com.tiocloud.fchat.MainActivity`。
- logcat：无 `FATAL EXCEPTION`，无 `E/AndroidRuntime`，无应用 ANR。
- IM 连接：应用 UID `10210` 建立 ESTABLISHED TCP 连接 `192.168.110.119:36888 -> 154.36.161.73:9326`。

## 后端需要知道

- 本轮没有后端接口字段、路径、状态码、鉴权、IM 协议或服务端表结构变更。
- 客户端 release 默认不再写 debug/info 级别日志，Socket 包体日志默认关闭；后续线上定位需要临时打开客户端开关或依赖服务端日志。
- 客户端本地 SQLCipher 用户库 schema version 升级到 `2`，旧客户端本地库首次打开会执行索引迁移。
- 如果后端调整消息同步 payload 大小、历史消息分页或资源缩略图策略，需要继续通过本仓库对齐契约。
