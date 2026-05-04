# Handshake Key 轮换 - 真机验证服务端日志关联确认

更新时间：2026-05-04 09:45 +08:00 (01:45 UTC)
对应 Codex 真机验证：[`2026-05-04-handshake-key-rotation-codex-complete.md`](2026-05-04-handshake-key-rotation-codex-complete.md) §"真机验证"

## 结论

**Phase 2 客户端切换完全生效**。Codex 真机 `FIN-AL60a` (imei `e9c0a57052260503`) 在新 APK 安装后(`lastUpdateTime: 2026-05-04 09:30:44`)的所有握手包均走新 key,**未触发任何 `HANDSHAKE-OLD-KEY` 兼容路径**。双 key 兼容期对老 APK 仍兜底有效。

## 服务端日志证据

### 1. HANDSHAKE-OLD-KEY 时间序列

服务端 journalctl(实际 logback active log 写入 `/logs/tio-site/all.log`,root appender 走 stdout/journalctl):

| 时间(UTC) | 时间(北京) | 设备 | 说明 |
|---|---|---|---|
| 01:05:47 | 09:05:47 | imei `e9c0a57052260503`,cid `official`,devicetype 2 (Android) | 服务端 Phase 1 部署后 4 秒,旧 APK 重连 → 走 OLD KEY 兼容,握手成功 |
| 01:23:04 | 09:23:04 | 同上 | 旧 APK 又一次重连(可能客户端心跳/断线重连)|
| **01:30:44** | **09:30:44** | — | **Codex 安装新 APK(关键时间点)** |
| 01:30:44 ~ 01:45:00 | 09:30:44 ~ 09:45:00 | — | **0 次 HANDSHAKE-OLD-KEY,0 次验签失败** |

### 2. 当前 9326 连接快照(01:45 UTC)

```
ss -tnp state established sport = :9326
[::ffff:154.36.161.73]:9326  ← [::ffff:150.228.149.223]:10557
[::ffff:154.36.161.73]:9326  ← [::ffff:129.224.203.25]:1170
```

2 个 ESTABLISHED 连接持续中(NAT 后内网 IP `192.168.110.119` 出口公网 IP 即上述其一)。**两条连接均无对应的 HANDSHAKE-OLD-KEY 日志,意味着握手用的是新 key**。

### 3. 总体监控

| 指标 | 值 | 含义 |
|---|---|---|
| HANDSHAKE-OLD-KEY 计数(全) | 2 | 都来自旧 APK,新 APK 安装前 |
| HANDSHAKE-OLD-KEY 计数(09:30:44 之后) | **0** | 新 APK 走新 key ✅ |
| 握手验签失败计数 | 0 | 无客户端被拒 |
| 9326 ESTABLISHED 连接数 | 2 | 真机连接活跃 |
| 9325 ESTABLISHED 连接数 | 0 | 当前无 IM TCP 直连 |

## 对 Codex 的反馈

### 已复核 ✅

> "请后端 AI 检查服务端双 key 兼容期日志，确认该真机连接使用新 key 完成握手"

**确认**:Codex 真机的 imei `e9c0a57052260503` 在 09:30:44 安装新 APK **之前** 触发过 2 次 OLD-KEY(旧 APK 行为),**之后 0 次**。等同于:新 APK 在该真机上正常用新 key 完成握手。

### 已复核 ✅

> "请确认本次真机验证时间段附近没有对应 HANDSHAKE-OLD-KEY WARN"

**确认**:09:30:44 之后服务端日志干净,无 WARN。

### 已修复 ✅

> "本地搜索发现 D:\tantan\bs-server\all\src\main\resources\app.properties 后端配置模板仍存在旧 key"

**已处理**(在前一份反馈 [`backend-confirmed`](2026-05-04-handshake-key-rotation-backend-confirmed.md) 中):

- 模板 `app.handshake.key=p2xgse_PLACEHOLDER_REPLACE_BEFORE_DEPLOY`(占位符防回退)
- 模板加 `app.handshake.key.old=` 空字段
- pwd.key.aes 同步加 `_DEAD_CODE` 后缀(综合审计 N-06 验证为死代码)
- Stage 1 backlog: PropInit fail-fast 检测占位符拒绝启动

## Phase 3 触发评估

按 [`94-task-handshake-key-rotation-codex.md`](原后端 fix plan 在客户端组本地) 设定:
- 升级率 > 99%
- 旧 key 计数 24h < 1% 总握手量
- Codex 确认全端发版

**当前 anjuke.site 状态**:
- 唯一已知触发 OLD KEY 的客户端(imei `e9c0a57052260503`)已自行升级到新 APK
- 9326 当前 2 个 ESTABLISHED 全部走新 key(无 WARN)
- **如果 anjuke.site 是单测试设备/小规模预发,Phase 3 可立即触发**;若有更多用户群体,保持 14 天观察期更稳

**建议方案**:
- 选项 A(谨慎):2026-05-18 ± 7 天后,确认所有 Web tioim / 历史 APK 全部升级,再 Phase 3
- 选项 B(快速):若用户确认 anjuke.site 当前无活跃旧版本用户,可在 24h 后(2026-05-05)直接 Phase 3

由用户决定走 A 还是 B。后端默认按 A 等待。

## 待 Codex / 用户后续

- [ ] Web tioim / tioim-small / mg-page 是否已切换?(本次只验证了 Flutter Android)
- [ ] iOS 客户端发版?(若启用 iOS,需同步轮换)
- [ ] 用户决定 Phase 3 时间窗口(选项 A vs B)
- [ ] Codex 把本反馈链入 PROJECT_STATE 状态表"已闭环"

## 监控查询命令(供后续日常使用)

更正:active log 是 `/logs/tio-site/all.log` **不是** `/logs/tio-site/info.log`(后者 0 字节空文件,logback 配置 root appender 写到 all.log)。

```bash
# anjuke.site 上跑
ssh tio-anjuke '
echo "=== 24h 内 OLD-KEY 触发次数 ==="
journalctl -u tantan-bs --since "24 hours ago" --no-pager | grep -c "HANDSHAKE-OLD-KEY"
echo "=== 24h 内验签失败次数 ==="
journalctl -u tantan-bs --since "24 hours ago" --no-pager | grep -c "握手过程中.*验签失败"
echo "=== 当前 9326 ESTABLISHED 数 ==="
ss -tnp state established sport = :9326 | tail -n +2 | wc -l
'
```

## 关联

- Codex 真机验证: [`handoffs/2026-05-04-handshake-key-rotation-codex-complete.md`](2026-05-04-handshake-key-rotation-codex-complete.md)
- 后端 Phase 1 + 模板修复: [`handoffs/2026-05-04-handshake-key-rotation-backend-confirmed.md`](2026-05-04-handshake-key-rotation-backend-confirmed.md)
