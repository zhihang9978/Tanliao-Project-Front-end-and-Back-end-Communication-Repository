# 客户端性能审计记录

更新时间：2026-05-04 10:05 +08:00

## 当前结论

客户端性能瓶颈主要不在 Flutter 跨平台本身，而在 IM 热路径实现：高频日志、本地数据库索引不足、逐条 DB 写入、消息/会话列表全量刷新、Socket 包解析与同步处理堆积、媒体处理成本高。

2026-05-04 Codex 已完成性能优化首轮落地，详见：`handoffs/2026-05-04-client-performance-stage123-codex-complete.md`。

## 已落地优化

### 1. Release 高频日志治理

- Release 默认关闭 debug/info 级别日志写盘，只保留 warning/error/fatal。
- Socket 收发包体日志增加开关，release 默认关闭。
- 影响：减少 IM 高频收发包时的本地文件 IO、存储增长和 CPU 消耗。

### 2. 会话列表刷新节流

- `ChatSyncEvent` 采用 50ms 短窗口聚合。
- 会话局部同步使用 `Map<id,index>` 合并，减少嵌套线性扫描。
- update 未命中时自动按新增处理，避免批量 upsert 事件丢失新会话。

### 3. 列表渲染稳定性

- 聊天列表和消息列表 item 增加稳定 key。
- `ChatItemWidget` build 阶段不再修改 model。

### 4. 本地 DB 索引和批量写入

- 用户本地 SQLCipher DB version 升级到 `2`。
- 新增 provider 级索引迁移机制。
- 为 `SynChatChatlist`、`OaChat`、`OaPrivatemsg`、`OaGroupmsg` 增加热路径索引。
- `ChatDao` 批量 insert/replace/update/delete 改用 batch。
- `OaChatDao`、`OaPrivatemsgDao`、`OaGroupmsgDao` 的全量替换和消息批量同步写入路径改用 batch。

### 5. 图片和媒体基础优化

- `WtImage` 对网络图和文件图按控件尺寸提供解码 hint。
- 图片上传前压缩限制最大边长 `1920x1920`。
- 图片/视频压缩增加可控耗时埋点，默认只在 debug 打开。

## 需要后端 AI 对齐

- 本轮没有后端接口字段、路径、状态码、鉴权、IM 协议或服务端表结构变更。
- 后续如果要继续优化大并发，需要后端配合：消息同步 payload 大小、历史消息分页、群聊推送批处理、资源缩略图策略、TURN/coturn 并发容量。
- 客户端 release 默认不再写 debug/info 和 Socket 包体日志，线上排查应优先看服务端日志；如需客户端细节日志，需要临时打开客户端开关。

## 验证

- `flutter build apk --release --no-pub`：通过。
- 定向 `flutter analyze`：无类型错误；剩余为项目既有 info 级提示。
- 真机安装：`FIN-AL60a` Android 12/API 31，ADB 安装 `Success`。
- 启动验证：应用前台运行，无 `FATAL EXCEPTION`、无 `E/AndroidRuntime`、无应用 ANR。
- IM 连接：应用 UID `10210` 已建立到 `154.36.161.73:9326` 的 ESTABLISHED TCP 连接。

## 后续建议

- 第二轮优化应增加可视化性能计数：Socket 队列长度、DB 慢查询、消息同步 payload 大小、图片 decode 尺寸、首屏耗时。
- 若后端能提供缩略图 URL，客户端应优先在列表/聊天气泡中加载缩略图，点击预览时再加载原图。
- 若消息量继续增长，应进一步拆分会话列表局部刷新，而不是整页 stream 重建。
