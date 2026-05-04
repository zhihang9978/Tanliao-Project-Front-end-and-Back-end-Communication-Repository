# 客户端性能审计记录

更新时间：2026-05-04

## 当前结论

客户端性能瓶颈主要不在 Flutter 跨平台本身，而在 IM 热路径实现：高频日志、本地数据库索引不足、逐条 DB 写入、消息/会话列表全量刷新、Socket 包解析与同步处理堆积、媒体处理成本高。

## 高优先级优化

### 1. Release 高频日志治理

- 客户端 release 环境不应输出大量 debug 日志。
- Socket 收发包日志应默认关闭或采样。
- 本地日志文件写入应只保留 warning/error 和必要异常。

### 2. 本地数据库索引与批处理

建议客户端本地 DB 增加查询索引，并将逐条 insert/update 改为 transaction + batch。

重点表：

- 私聊消息表：按 `cmpid / uid / touid / id / contenttype` 查询。
- 群聊消息表：按 `cmpid / groupid / id / contenttype` 查询。
- 会话表：按 `cmpid / chatmode / bizid / chatuptime` 查询和排序。

### 3. 会话列表刷新节流

- 高频消息不要每条都全量 sort + notify。
- 建议 16-100ms 聚合一次事件，维护 Map 结构减少线性扫描。

### 4. 消息列表渲染优化

- 避免长列表 `shrinkWrap`。
- 为消息 item 增加稳定 key。
- 批量插入消息后一次刷新。
- build 阶段不要修改 model。

### 5. Socket 与同步链路

- JSON/gzip 解码、DB 转换、大 payload 处理应避免阻塞 UI。
- 需要增加队列长度、包处理耗时、DB 写入耗时等指标。

## 需要后端 AI 对齐

- 消息同步 payload 大小、分页、游标和 ACK 语义。
- 历史消息分页大小和返回字段。
- 群聊高并发推送策略。
- 资源服务缩略图策略，避免客户端列表加载原图。
- TURN/coturn 并发容量和超时策略。

## 建议执行顺序

1. 先做客户端 release 日志开关和 Socket 日志治理。
2. 再做 DB 索引、version migration、DAO 批处理。
3. 再做会话/消息列表刷新节流和局部刷新。
4. 最后做媒体、WebRTC、性能埋点和跨端验证。
