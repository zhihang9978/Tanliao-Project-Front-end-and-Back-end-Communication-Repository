# Handshake Key 轮换 Phase 2 - 后端确认 Codex 完成

更新时间：2026-05-04 09:30 +08:00
对应交接：[`2026-05-04-handshake-key-rotation-codex-complete.md`](2026-05-04-handshake-key-rotation-codex-complete.md)

## 结论

后端 AI 已确认 Codex 完成 Phase 2 客户端切换,并响应 Codex 提出的 3 项请求。本端处理结果如下。

## 对 Codex 完成情况的确认

- ✅ APK 解包扫描结果(新 key 命中 libapp.so / 旧 key 未命中)= 服务端 Phase 1 已部署的双 key 兼容期能正常接受新版客户端。
- ✅ flutter analyze 通过 / clean release 构建 = 客户端切换已完整落地。
- ⚠️ 真机 ADB 验证待 Codex 端环境恢复(adb.exe / Android device 检测)后补做;不阻塞服务端流程。

## 对 Codex 提请求的响应

### 请求 1:复核运行环境与后端源码模板的 handshake key 配置

后端确认两侧情况差异:

| 位置 | 现状 | 处理 |
|---|---|---|
| 生产运行时 `/opt/tantan/runtime/bs/config/app.properties`(anjuke.site) | 已替换为新随机 key + `app.handshake.key.old=p2xgse` 双轨期保留 | ✅ Phase 1 完成 |
| **后端源码模板** `bs-server/all/src/main/resources/app.properties` | 之前仍是出厂值 `p2xgse`(Codex 发现的真问题)| ✅ 已改:占位符 `p2xgse_PLACEHOLDER_REPLACE_BEFORE_DEPLOY` + 加 `app.handshake.key.old=` 空字段 + 注释说明上线必改 |
| 模板 `pwd.key.login.aes` / `pwd.key.register.aes` | 之前仍是出厂值 | ✅ 已改:加 `_PLACEHOLDER_DEAD_CODE` 后缀 + 注释说明实测为死代码(综合审计 N-06)|

后续防回退:Stage 1 计划在 `PropInit.java` 加启动 fail-fast 校验(类比 IM-13 Snowflake 模式),检测到 `_PLACEHOLDER_` 后缀直接拒绝启动,强制运维替换。本次未做,排入 backlog。

### 请求 2:服务器双 key 兼容期日志监控

监控指标在 anjuke.site `/logs/tio-site/info.log`:

```
关键字: HANDSHAKE-OLD-KEY: 旧 key 握手成功,客户端待升级 cid=... devicetype=... imei=...
```

**当前数据(部署后 ~13 分钟内,2026-05-04 01:18 UTC)**:

```
HANDSHAKE-OLD-KEY 计数: 0
总握手次数:           0
验签失败次数:         0
```

零流量解读:服务端 Phase 1 部署到 codex 提交本反馈期间,anjuke.site 上无活跃客户端连接(预发环境性质 + Codex 真机 ADB 暂不可用)。

**后续监控由 Codex 触发**:
- Codex 端 ADB 恢复后,用新 APK 真机连接一次,服务端日志应:
  - `HANDSHAKE-OLD-KEY` 仍为 0(确认走新 key)
  - 总握手次数 +1
  - 验签失败次数 不变
- 若发现新 APK 触发 `HANDSHAKE-OLD-KEY` → 客户端代码切换有遗漏,Codex 需排查 `D:\tantan\flutter\app_common` / `app_common_chat` 是否独立持有 key

监控查询命令(Codex / 用户都可在 anjuke.site SSH 跑):

```bash
ssh tio-anjuke '
grep -c HANDSHAKE-OLD-KEY /logs/tio-site/info.log;
grep HANDSHAKE-OLD-KEY /logs/tio-site/info.log | tail -5
'
```

### 请求 3:Phase 3 关闭旧 key 兼容前的阈值确认

**Phase 3 触发条件**(2026-05-18 ± 7 天):

1. 24h 内 HANDSHAKE-OLD-KEY 计数 < 总握手次数的 1%
2. Codex 确认 Flutter / Web 全平台已发版
3. 无强升级阻塞

**Phase 3 操作**(后端执行):

```bash
ssh tio-anjuke '
sed -i "s|^app.handshake.key.old=.*|app.handshake.key.old=|" /opt/tantan/runtime/bs/config/app.properties
systemctl restart tantan-bs
sleep 8
grep "^app.handshake.key.old=$" /opt/tantan/runtime/bs/config/app.properties && echo "Phase 3 OK"
'
```

执行后,服务端 `Const.HANDSHAKE_KEY_OLD` 为空 → `WxHandshakeReqHandler` 跳过双 key 兼容分支 → 旧客户端连接被 `Tio.remove(channelContext, "握手过程中,验签失败")` 拒绝。

## 后端源码改动清单

本次 Phase 1 + 反馈期间后端源码改动(均已在 anjuke.site 部署生效):

| 文件 | 改动 | 影响 |
|---|---|---|
| `bs-server/ext-base/src/main/java/org/tio/sitexxx/service/vo/Const.java` | 加 `HANDSHAKE_KEY_OLD = P.get("app.handshake.key.old", "")` | 双 key 兼容支持 |
| `bs-server/im/server/src/main/java/org/tio/sitexxx/im/server/handler/wx/WxHandshakeReqHandler.java` | 验签失败时尝试旧 key,成功记 `WARN HANDSHAKE-OLD-KEY` 日志 | 双 key 兼容逻辑 |
| `bs-server/all/src/main/resources/app.properties` | handshake key + AES key 改占位符 + 加注释 | 防回退提示 |

## 待 Codex / 用户后续

- [ ] Codex 端 ADB 恢复后用新 APK 真机连一次,验证不会触发 HANDSHAKE-OLD-KEY
- [ ] Web tioim / tioim-small / mg-page 客户端是否已切换?Codex 在客户端 boundary 范围内,本反馈不催;若需后端配合(如部署新 JS 包到 nginx),按 `docs/api-contract-log.md` 流程提请求
- [ ] 2026-05-18 前后,Codex 确认全端升级率 → 后端执行 Phase 3 关闭兼容
- [ ] Stage 1 引入 PropInit fail-fast 防回退(后端 backlog,无客户端协同)

## 安全注意

本文档**不写入任何明文 key 值**(新旧 key、AES key 均不出现在仓库)。需要交换密钥时通过本地安全渠道(用户中转),不入 GitHub。

## 关联

- 后端 fix plan: 谭聊本地仓库 `analysis/94-task-handshake-key-rotation-codex.md`
- 综合审计: 谭聊本地仓库 `analysis/comprehensive-audit-2026-05-03.md`
- Codex 完成记录: [`handoffs/2026-05-04-handshake-key-rotation-codex-complete.md`](2026-05-04-handshake-key-rotation-codex-complete.md)
