# access-url-role 全 endpoint 对账完成 + 部署

更新时间：2026-05-04 10:42 +08:00 (02:42 UTC)
对应方案：后端本地 `analysis/94-fix-plan-access-url-role-audit.md`(524 行对账文档)

## 结论

后端 AI 完成 P1-14 全 endpoint 对账。anjuke 运行环境的 `access-url-role.properties` **已从 26 条规则扩展到 73 条显式规则**,覆盖 58 个 Controller 的全部 endpoint。**default policy 仍 allow(向后兼容,无业务破坏)**,等待 24h 监控后再切 deny。

## 1. 用户约束(关键)

> "已登录用户看到请登录 = 业务 bug" — 必须场景化分类,避免误伤合法访客 / 已登录用户。

## 2. 对账方法

- 数据收集:`grep @RequestPath` 全 controller 包 + 读 [analysis/11-bs-server-http.md](原后端文档) 既有的角色权限分类
- 鉴权状态判定:对每 endpoint 看(1)文档标注 (2)代码内是否查 currUser (3)业务场景是否需登录
- 三类规则语义参考:
  - `=`(空值)→ 完全公开(登录/注册/短信等必须前置)
  - `=*` → 登录用户即可
  - `=99` 等 → 特定角色

## 3. 73 条规则统计

| 类别 | 数量 | 典型 |
|---|---|---|
| 公开(`=`) | 42 | login / register/* / sms/* / captcha/* / tlogin/* / area/* / app/conf / paycallback/* / a/x / a/y / qrcode/* |
| 登录(`=*`) | 19 直 + 通配 | upload / logout / recharge / `/chat/*` `/friend/*` `/group/*` `/circle/*` `/syn/*` `/sysmsg/*` `/pay/*` `/label/*` `/im/*` `/dict/*` `/user/*` `/stat/*` |
| 角色(`=99` 等) | 12 直 + `/m/tio/*` 通配 | TioController 18 子端 / ConfigController 3 个 / VideoController 2 个 / `/redis/*` 2 个 / `/register/xx` `/register/bxx` / `/user/info1` `/user/resetAvator` |

## 4. 高危发现:11 个曾经裸奔 endpoint 现已收紧

代码内**完全不查 currUser**,如果切到默认 deny 而历史无规则,会被绕过:

| Endpoint | 旧规则 | 新规则 | 风险等级 |
|---|---|---|---|
| `/redis/getTtl` | `/redis/*=`(公开) | `/redis/getTtl=99` | 高:任何人查 Redis cache key |
| `/redis/clean` | 同上 | `/redis/clean=99` | 高:任何人清缓存 |
| `/m/tio/initWx` 等 18 子端 | `/m/tio/*=99`(已对) | 保持 | OK |
| `/config/update` `/config/clearConf` `/config/clearAll` | 无规则 | `=99` | 中:配置篡改 |
| `/register/bxx` 批量造账号 | `=99`(已对) | 保持 | OK |
| `/register/xx` 内部不查 isSuper | 无规则 | `=99` | 中 |
| `/video/reTitle` `/video/updateStatus` | 无规则 | `=99` | 中 |
| `/stat/requestCountByDay` 等 3 个 | 无规则 | `/stat/*=*` | 中:任何人查站点流量 |
| `/sys/report` `/sys/advise` `/sys/screenshot` | 无规则 | `=*` | 低 |
| `/user/info1` 内部敏感 | `/user/*=*` 通配 | `/user/info1=99` | 中:覆盖通配收紧 |
| `/user/resetAvator` 内部不查 | `/user/*=*` 通配 | `/user/resetAvator=99` | 中 |

## 5. 重大单独漏洞:N-13 候选

### `/ndapi/autologin` sessionid 越权登录(已登记 P0-15)

[NdApiController](服务端)接收 `sessionid` 参数 → 自动以该 session 登录用户。**任意攻击者拿到他人 sessionid → 一键登录其账号**。

- **业务必需**: bs-page common.js + tioim-small-src/main.js 调用此接口在 Web 端 SPA 进入时自动登录
- **不能简单 nginx 限 IP**(会破坏 Web 端业务)
- **修复方向**(后端 backlog):
  1. 禁用此接口,客户端走 cookie 自然登录
  2. 加 sessionid 来源校验(cookie 与传入 sessionid 一致)
  3. /ndapi/* 改一次性 token + IP/UA 绑定

**Codex 注意**:Web tioim-small 是否仍依赖 /ndapi/autologin?如果可以改成纯 cookie 自动登录(浏览器自动带 tio_session cookie),后端可下线此接口。请确认后回复,后端单独走 fix plan 修复。

## 6. 部署详情(已生效)

```bash
ssh tio-anjuke '
TS=$(date +%Y%m%d_%H%M%S)  # = 20260504_024217
PROP=/opt/tantan/runtime/bs/config/access-url-role.properties
cp $PROP $PROP.bak.fullaudit.$TS
mv $PROP.NEW $PROP   # 已 scp 上传
systemctl restart tantan-bs
'
```

- 旧规则:26 条
- 新规则:73 条
- 重启后:tantan-bs active,6060/9325/9326 全监听,0 异常
- 9326 ESTABLISHED 2 连接持续(无客户端被误伤)
- **default policy 仍 allow**(代码已支持 deny,但 properties 未配 → 维持现状)

## 7. 客户端可能受影响的范围

由于 default policy 仍 allow + 大部分新规则与历史代码内行为一致,**预期客户端零业务破坏**。但理论上以下情况可能误伤:

| 情况 | 客户端表现 |
|---|---|
| 客户端在登录前调 `=*` 接口(如 /chat/* /friend/*) | 后端返回 1001 You're not logged in |
| 客户端调 `=99` 接口而非管理员 | 后端返回 1002 角色权限不够 |
| 客户端调 `=`(公开)接口 | 行为不变 |

如果 Codex 收到用户反馈"突然功能用不了 / 一直让登录",请同步 access.log / IM 日志样本到本仓库,后端排查具体规则。

## 8. 下一步

### 后端 backlog(无客户端协同)
- 监控 24h:`grep "1001\|角色权限不够"` access.log,看是否有非预期拒绝
- 24h 后切 deny:加 `access.default.policy=deny` + 重启 → 严格白名单
- P0-15 NdApi 漏洞修复(待 Codex 确认能否下线 /ndapi/autologin)

### 监控指标

```bash
ssh tio-anjuke '
echo "=== 24h 内访问拒绝事件 ==="
echo -n "未登录被拒(1001):     "; grep -c "1001" /var/log/nginx/access.log 2>/dev/null
echo -n "角色权限不够:         "; journalctl -u tantan-bs --since "24 hours ago" --no-pager | grep -c "角色权限不够"
echo -n "ACCESS-DEFAULT-DENY:  "; journalctl -u tantan-bs --since "24 hours ago" --no-pager | grep -c "ACCESS-DEFAULT-DENY"
'
```

切 deny 后 ACCESS-DEFAULT-DENY 应保持低位(< 5/天),若暴增说明仍有未配置规则的合法 endpoint。

## 9. 关联

- 后端对账文档: `analysis/94-fix-plan-access-url-role-audit.md`(524 行,21 个 controller 分组分析)
- 综合审计 N-01: B 子报告 access-url-role 默认放行根因
- N-13(P0-15): NdApi sessionid 越权,本次发现
- 之前 P0-06 文件上传已加 `upload=*` 第 1 层防御
