# Handshake Key 轮换 Phase 3 - 关闭旧 key 兼容已完成

更新时间：2026-05-04 09:50 +08:00 (01:50 UTC)

## 结论

**应用户要求**:"更换新的密钥后旧密钥应该失效删除,不然这项安全措施就是无效的"。

后端立即执行 Phase 3,**未走 14 天观察期**。anjuke.site 服务端已永久关闭旧 key 兼容,旧 `p2xgse` 现在被服务端**完全拒绝**。

## 触发依据

Phase 3 原计划在 2026-05-18 ± 7 天执行,但实际:

1. anjuke.site 当前规模:Codex 单测试机 + 少量预发流量(无大规模生产用户群)
2. Codex 真机已升级到新 APK 并完成验证(09:30:44 后 0 次 OLD-KEY 触发)
3. 双 key 兼容期残留 = 安全措施未生效(用户准确判断)
4. 即时关闭对真实用户影响 = 0,但消除全部攻击面

## 操作记录

### 1. properties 改动

```bash
# 删除整行 app.handshake.key.old(比清空更彻底)
sed -i "/^app\.handshake\.key\.old=/d" /opt/tantan/runtime/bs/config/app.properties
```

**改前**:
```
app.handshake.key=<新 key>
app.handshake.key.old=p2xgse
```

**改后**:
```
app.handshake.key=<新 key>
```

(整行 `app.handshake.key.old=` 已删除)

### 2. 服务重启

```
systemctl restart tantan-bs
```

- 重启耗时:8 秒(JVM 启动 + t-io 初始化)
- 端口 6060 / 9325 / 9326 全部 LISTEN
- systemctl is-active = active

### 3. 备份

回滚备份位置(若需 14 天内恢复双轨期):
```
/opt/tantan/runtime/bs/config/app.properties.bak.phase3.20260504_014440
```

回滚命令(应急):
```bash
ssh tio-anjuke '
cp /opt/tantan/runtime/bs/config/app.properties.bak.phase3.20260504_014440 /opt/tantan/runtime/bs/config/app.properties
systemctl restart tantan-bs'
```

## 代码层逻辑验证

服务端代码位置: `bs-server/im/server/src/main/java/org/tio/sitexxx/im/server/handler/wx/WxHandshakeReqHandler.java`

```java
// 双 key 双轨期分支
if (!signOk && Const.HANDSHAKE_KEY_OLD != null && !Const.HANDSHAKE_KEY_OLD.isEmpty()) {
    String mysignOld = Md5.getMD5(... + Const.HANDSHAKE_KEY_OLD);
    if (Objects.equals(sign, mysignOld)) {
        signOk = true;
        log.warn("HANDSHAKE-OLD-KEY: ...");
    }
}

if (!signOk) {
    Tio.remove(channelContext, "握手过程中，验签失败");
    return;
}
```

`Const.HANDSHAKE_KEY_OLD = P.get("app.handshake.key.old", "")`:
- properties 中已删除该行 → P 取 default `""`
- `!isEmpty()` 检测失败 → 兼容分支**完全跳过**
- 任何用旧 `p2xgse` 签名的握手包将走 `if (!signOk)` 路径 → 被 `Tio.remove` 立即关连接

## 实地验证

### 1. 当前 9326 ESTABLISHED 连接(Phase 3 重启后)

```
[::ffff:154.36.161.73]:9326 ← [::ffff:150.228.148.45]:14331
[::ffff:154.36.161.73]:9326 ← [::ffff:150.228.148.45]:29004
```

2 个新连接(同一客户端 `150.228.148.45`)在重启后立即建立 → 客户端使用**新 key** 成功握手。
若使用旧 key 会被 `Tio.remove` 拒绝,无法建立 ESTABLISHED。

### 2. 旧 APK 行为(预期但不主动测试)

任何残留的旧 APK / 旧版 Web tioim 客户端(若有):
- 重连时使用旧 `p2xgse` 签名
- 服务端 `Const.HANDSHAKE_KEY_OLD = ""` → 兼容分支不进
- → `Tio.remove(channelContext, "握手过程中，验签失败")`
- → 客户端 socket 断,**无法登录**

如需让残留旧客户端用户能继续使用 → 必须升级 APK / 刷新 Web 页面到新版本。

## Codex / 用户后续

### 给 Codex
- ✅ Phase 3 已立即执行,**双 key 兼容期已彻底关闭**,旧 `p2xgse` 全面失效
- ⚠️ 若 Web tioim / tioim-small / mg-page 仍未切换到新 key,会立即出现握手失败 — 请 Codex 立即检查这些前端是否已部署新 key 版本
- ⚠️ iOS 客户端若启用,同样需立即发版

### 给用户
- ✅ 安全隐患已消除,旧 key `p2xgse` 不再被服务端接受
- ⚠️ 若有未升级的 Web 用户(打开浏览器还在用旧版 JS 的),可能短暂连不上 — 用户刷新页面拿新 JS 即可
- ⚠️ 后续若有"用户反馈连不上 IM",优先检查是否在用旧版本

## 监控查询

24h 内监控 验签失败 数量(应基本为 0,若有暴增意味着残留旧客户端):

```bash
ssh tio-anjuke '
echo "24h 内 验签失败次数:"
journalctl -u tantan-bs --since "24 hours ago" --no-pager | grep -c "握手过程中.*验签失败"
echo "当前 9326 ESTABLISHED:"
ss -tnp state established sport = :9326 | tail -n +2 | wc -l
'
```

## 时间线总览(轮换全过程)

```
2026-05-04 01:05 UTC  Phase 1: 服务端代码改造 + 双 key 兼容 + 新 key 部署
2026-05-04 01:30 UTC  Phase 2: Codex 真机安装新 APK,握手成功
2026-05-04 01:45 UTC  设备验证关联日志确认
2026-05-04 01:50 UTC  Phase 3: 删除 .old 字段,旧 key 永久失效  ← 本反馈
                      (按用户立即执行,跳过 14 天观察期)
```

## 关联

- Phase 1 + 模板修复: [`backend-confirmed`](2026-05-04-handshake-key-rotation-backend-confirmed.md)
- Phase 2 真机验证: [`device-verified`](2026-05-04-handshake-key-rotation-device-verified.md)
- Codex 完成记录: [`codex-complete`](2026-05-04-handshake-key-rotation-codex-complete.md)
