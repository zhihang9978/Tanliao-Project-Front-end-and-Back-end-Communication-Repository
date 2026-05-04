# 钱包本地化改造 PRD(完整)

更新时间：2026-05-04 17:00 +08:00 (09:00 UTC)
责任方：后端 AI 主导,客户端 codex 协同
状态：✅ 需求盘问完成(/grill-me 17 题),待启动 Phase 1
变更性质：**单向门**(删除 5upay-sdk-core,无法回滚到新生支付通道)

## 0. 文档导航

- 本文 = PRD 主文档(决策汇总 + Phase 计划 + 测试 / 监控)
- 接口契约 → `2026-05-04-wallet-localization-api-contract.md`
- 数据库 DDL → `2026-05-04-wallet-localization-ddl.sql`

---

## 1. 项目背景

谭聊原作者钱包模块对接**新生支付**(5upay-sdk-core),要求用户实名认证(身份证 / 姓名 / 手机)开户。截图所示"初语钱包账户开通说明"页是该流程的产物。

采购方(毛家富 / anjuke.site)定位为**站内积分性质**的钱包,不需要实名,不需要第三方支付通道。改造为**全本地化**:

- 钱包激活 = 设支付密码 + 3 题密保
- 充值 = 用户向后台收款码转账(尾数识别),管理员手动到账
- 提现 = 用户绑定收款账号,管理员手动打款
- 完全删除 5upay-sdk-core 私有 jar 与所有相关代码

## 2. 改造目标

1. **替换截图所示开通页**:从实名表单 → 设支付密码 + 3 题密保
2. **支持充值 + 提现**:都不走第三方,后台手动审核到账
3. **后台可配置充值/提现方式**:支付宝 / 微信 / 银行卡 / USDT / 自定义
4. **完全本地化**:删除 5upay-sdk-core,绕过新生支付,纯本地实现
5. **实时通知管理员**:新待审订单触发声音 + Notification + Badge

## 3. 协作分工

| 范围 | 责任方 |
|---|---|
| **客户端**(Flutter)| Codex |
| **管理后台 mg-page + mg-server** | 后端(我)|
| **服务器 nginx / properties / DB / systemd** | 后端 |
| **bs-server 用户端 API + 业务逻辑** | 后端 |
| **service-pay 模块本地化重写** | 后端 |
| **数据库 DDL + 数据迁移** | 后端 |

## 4. 完整决策清单(/grill-me 17 题汇总)

### 4.1 钱包激活

| 决策 | 值 |
|---|---|
| 钱包绑定 | uid(不绑手机号)|
| 支付密码格式 | 6 位纯数字 |
| 摘要算法 | MD5("${" + uid + "}" + pwd) — 客户端先做,后端再二次 MD5 |
| 错误锁定 | 5 次错锁 30 分钟 |
| 密保问题 | 3 题(从预设问题池选)|
| 校验严格度 | 3/3 全对才放行 |
| 激活时机 | 强制:不设密保不能激活钱包 |
| 找回路径 | 答 3 题密保 → 设新支付密码;客服可代重置(写 mg_op_log)|

### 4.2 钱包账户状态机

| status | 语义 | 后果 |
|---|---|---|
| 1 ACTIVE | 激活成功 | 收发红包/充值/提现全开 |
| 2 FROZEN | 管理员强制冻结 | 全部禁用,余额可见不可动 |
| 3 CLOSED | 已注销 | 全部禁用(Stage 0 不做用户主动注销)|

| 决策 | 值 |
|---|---|
| 冻结操作 | 超管 + 财务管理员 |
| 用户主动注销 | Stage 0 不做 |
| 余额上限 | 100 万元(分= 100,000,000),后台可配 |
| 余额单位 | 分(BIGINT)|
| 余额负数防护 | 三层(SQL 乐观锁 + Redisson + CHECK 约束)|

### 4.3 充值流程

| 决策 | 值 |
|---|---|
| 订单超时 | **60 分钟** |
| 尾数算法 | 0.01-0.99 随机,**同金额段(整数部分相同)未占用** |
| 用户提示 | "请向收款码转账 ¥100.07(精确金额识别)"+ 复制按钮 |
| 同金额段并发上限 | 99 笔(0.01-0.99)|
| 单笔最低 | 1 元 |
| 用户取消 | 允许立即取消 + 立即回收尾数 |
| 金额错配 | 严格相等;不匹配 → 进无主资金池 |
| 重复转账 | 进无主资金池,管理员手动处理 |
| 合并转账 | 进无主资金池(客户端文案明确禁止)|
| 充值最高 | 由 wx_pay_method.max_amount 控制(每方式独立)|

### 4.4 用户感知 / 通知

| 决策 | 值 |
|---|---|
| 通知通道 | IM 系统消息(WxSysMsgNtf=788)+ JPush 离线推送 |
| 拒绝原因必填 | ≥ 5 字 |
| 重新申请 | 直接下新订单,老订单保留 |
| SLA 软提醒 | 30 分钟未处理 → badge 橙色 |
| SLA 硬提醒 | 120 分钟未处理 → badge 红色 + Polling 推送 |
| SLA 用户提醒 | 24 小时未处理 → 推 IM 消息"审核中" |
| SLA 报警 | 72 小时未处理 → 转"待客服核查" |
| 处理管理员 ID | 仅内部 mg_op_log,不暴露用户 |

### 4.5 提现 — 账号绑定

| 决策 | 值 |
|---|---|
| 类型 | 5 类:alipay / wechat / bank / usdt / custom |
| USDT 链 | TRC20 / ERC20 / BEP20 / Polygon |
| USDT 必填 | chain_type + 收款地址(account 字段)|
| 单用户绑定上限 | 5 个 |
| 添加账号 | 需支付密码 |
| 修改账号 | 需支付密码 + 3 题密保 |
| 删除账号 | 需支付密码 |
| 24h 冷静期 | 新账号 / 修改后 24 小时不可提现到此账号 |
| 同账号去重 | (uid, method_type, account) 联合唯一 |
| 默认账号 | 首个自动设为默认,可手动改 |

### 4.6 提现申请

| 决策 | 值 |
|---|---|
| 余额冻结 | 加 `wx_wallet_coin.frozen_cny` 字段 |
| 提交瞬间 | frozen_cny += 申请额(可用余额 = cny - frozen_cny)|
| 通过时 | cny -= 申请额, frozen_cny -= 申请额, withdrawcny += 实际到账 |
| 拒绝时 | frozen_cny -= 申请额(只解冻,余额不动)|
| 单次最低 | 10 元(可后台调,wx_pay_method.min_amount)|
| 单次最高 | 10,000 元(同上)|
| 单日笔数 | 5 次(可后台调,conf 表)|
| 单日总额 | 50,000 元(可后台调)|
| 多笔并发待审 | 允许,frozen_cny 实时校验 |
| 取消窗口 | 仅 audit_status=1 待审可取消 |
| 处理中锁 | audit_status=2,30 分钟无操作自动释放 |
| 打款凭证 | 可选(管理员决定是否上传)|
| 到账时间承诺 | 不做硬承诺,文案"通常 24 小时内"|

### 4.7 红包(已有功能本地化)

| 决策 | 值 |
|---|---|
| 接口策略 | 沿用现有 /pay/sendRedpacket 等 26 个接口,实现替换 |
| 钱包未激活 | 拒绝收红包(必须先激活)|
| 钱包冻结 | 发收都禁用 |
| P2P 转账 | Stage 0 不新增,沿用现有红包机制 |
| 24h 未抢退回 | 沿用谭聊原作者逻辑(只换底层余额操作)|
| 红包金额限额 | 沿用现有 conf(WX_REDPACKET_MIN/MAX)|

### 4.8 管理后台 RBAC

**新增 38 项权限点**(详见 DDL 附录),分两大类:**财务管理** + **支付配置**。

**4 个角色**:

| 角色 | 充值审 | 提现审 | 无主资金 | 钱包查 | 加扣余额 | 冻结/解冻 | 代重置密码 | 配置 |
|---|---|---|---|---|---|---|---|---|
| 1 超管 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| 10 财务 | ✅ | ✅ | ✅ | ✅ | ✅(**不限额**)| ❌ | ❌ | ❌ |
| 11 客服 | ❌ | ❌ | ✅ | ✅(只读)| ❌ | ❌ | ✅ | ❌ |
| 12 运营 | ❌ | ❌ | ❌ | ✅(只读)| ❌ | ❌ | ❌ | ❌ |

**高敏操作保护**:
- 加扣余额:二次确认 + 强制理由 ≥ 50 字 + 写 mg_op_log + Polling 推所有超管
- 冻结钱包:必填理由 + 推 IM 消息给被冻用户
- 代重置支付密码:输入用户 phone 核身 + 操作日志 + 推用户 IM

### 4.9 5upay 完整删除

详见 [§5.4 删除清单](#54-5upay-删除清单)。

### 4.10 部署与配置

| 决策 | 值 |
|---|---|
| 模式开关 | `pay.local.mode=true`(properties)|
| 双层配置 | properties(开关/模式)+ conf 表(业务参数,后台可改)|
| 灰度策略 | **直接全量切**(开发期无老用户)|
| 回滚 | **单向门**(5upay 已删,不可回滚)|

### 4.11 实时推送(管理员通知)

| 决策 | 值 |
|---|---|
| 实现方案 | **短 Polling 3 秒**(最简,0 风险)|
| 服务端队列 | 内存事件队列,管理员 uid 粒度,1000 条上限 |
| 前端 | EventSource-style polling + 浏览器声音 + Notification + favicon 红点 |
| 偏好开关 | localStorage,默认开 |
| 事件类型 | recharge_pending / withdraw_pending / pending_count(每 60 秒心跳) |

### 4.12 防刷 / 幂等

| 决策 | 值 |
|---|---|
| 同 uid 同金额段并发 | 3 笔上限 |
| 同 uid 全局并发待审 | 10 笔上限 |
| 同 uid 提交频次 | 2 次 / 30 秒(Redis 计数)|
| 同 IP 提交频次 | 30 次 / 分钟 |
| 5 秒去重 | Redis SETNX(同 uid + 同方式 + 同金额)|

### 4.13 测试 / 监控

**测试 3 档**:
- L0 冒烟 12 项(每次部署必跑,5-10 分钟)
- L1 集成 15 项(Phase 4 前必跑,30-60 分钟)
- L2 端到端 5 次(上线前)

**监控 11 项**(写入 88-monitoring-metrics.md):
- 待审充值/提现订单数 > 50 → P3
- 充值订单超时率 > 30% → P3
- 提现 SLA > 24h → P2
- 无主资金累计 > 10 → P3
- **钱包余额负数 > 0 → P0**
- 支付密码连续错次/h > 100 → P2
- 锁定中用户数 > 10 → P3
- **单日扣减总额 > 100 万 → P0**
- 单日加余额 > 50 万 → P1
- frozen_cny / cny > 30% → P2
- paypwd_lock_until 锁定数 > 10 → P3

### 4.14 资源 / 序列号

| 决策 | 值 |
|---|---|
| 资源存储 | 沿用 /upload(本地 /opt/tantan/upload/)|
| 收款码图限制 | 5MB |
| 凭证图限制 | 5MB |
| 客户端缓存 | 60 秒(支付方式列表)|
| 订单号 | Snowflake + 前缀(R 充值 / W 提现 / T 流水 / U 无主资金)|
| 流水查询时间 | 默认最近 30 天,翻页可看历史 |
| 客服联络 | 沿用现有 IM 私聊,不做工单 |

### 4.15 USDT 特殊字段

`wx_pay_method` 加列:`chain_type VARCHAR(20)`(仅 method_type=usdt 时必填)

链类型:TRC20 / ERC20 / BEP20 / Polygon
收款地址:用通用 account 字段
前端校验:
- TRC20: T 开头 + 34 字符
- ERC20 / BEP20 / Polygon: 0x 开头 + 42 字符

### 4.16 并发安全(三层防御)

**第 1 层 — 乐观锁 SQL**(主防线):
```sql
UPDATE wx_wallet_coin
SET cny = cny - ?, frozen_cny = frozen_cny + ?
WHERE uid = ? AND (cny - frozen_cny) >= ?
```

**第 2 层 — Redisson 分布式锁**(辅防线,UX):
```java
RLock lock = redisson.getLock("wallet:lock:" + uid);
if (!lock.tryLock(2, 5, SECONDS)) throw "操作过于频繁";
```

**第 3 层 — MySQL 8 CHECK 约束**(终极兜底):
```sql
CHECK (cny >= 0), CHECK (frozen_cny >= 0), CHECK (frozen_cny <= cny)
```

**所有钱包余额操作走统一 WalletService 模板**,严禁绕过。

### 4.17 接口契约 / 客户端兼容

| 决策 | 值 |
|---|---|
| Resp 结构 | 沿用现有 `{ok, code, msg, data}` |
| 时间格式 | yyyy-MM-dd HH:mm:ss(字符串)|
| 金额格式 | 后端 BIGINT 分,响应也是分,前端展示除 100 |
| 字段命名 | camelCase |
| 错误码 | 4xxx 段(详见接口契约附录)|
| 用户端接口数 | 18 个 |
| 后台接口数 | 25 个 |
| 老 APK | 强制升级机制(`app.minimum.version`)|
| i18n | Stage 0 不做 |
| 版本号 | 不做 v1/v2,沿用现有路径 |

---

## 5. 数据库改动总览

### 5.1 新建 5 表

详见 DDL 附录:
- `wx_pay_method` — 充值/提现方式配置
- `wx_user_payout_account` — 提现账号绑定
- `wx_wallet_security_qa` — 密保问答(每用户 3 行)
- `wx_security_question` — 密保问题预设池(8 题初始化)
- `wx_unmatched_payment` — 无主资金池

### 5.2 ALTER 5 表

```sql
ALTER TABLE wx_wallet_coin
  ADD COLUMN frozen_cny BIGINT DEFAULT 0 COMMENT '冻结金额(分)' AFTER cny,
  ADD CONSTRAINT chk_cny_nonneg CHECK (cny >= 0),
  ADD CONSTRAINT chk_frozen_nonneg CHECK (frozen_cny >= 0),
  ADD CONSTRAINT chk_frozen_lte_cny CHECK (frozen_cny <= cny);

ALTER TABLE wx_user_recharge_item
  ADD COLUMN method_id INT,
  ADD COLUMN marker_amount DECIMAL(12,2) COMMENT '实际应付(带尾数)',
  ADD COLUMN serial_no VARCHAR(32) UNIQUE,
  ADD COLUMN audit_status TINYINT DEFAULT 1 COMMENT '1待审 2处理中 3通过 4拒绝 5取消 6超时',
  ADD COLUMN audit_uid INT,
  ADD COLUMN audit_remark VARCHAR(500),
  ADD COLUMN audit_lock_time DATETIME,
  ADD COLUMN audit_time DATETIME,
  ADD COLUMN expire_time DATETIME;

ALTER TABLE wx_user_withhold_item
  ADD COLUMN method_id INT,
  ADD COLUMN account_id INT,
  ADD COLUMN account_snapshot TEXT COMMENT '下单时账号快照',
  ADD COLUMN serial_no VARCHAR(32) UNIQUE,
  ADD COLUMN audit_status TINYINT DEFAULT 1,
  ADD COLUMN audit_uid INT,
  ADD COLUMN audit_remark VARCHAR(500),
  ADD COLUMN audit_lock_time DATETIME,
  ADD COLUMN audit_time DATETIME,
  ADD COLUMN payout_evidence VARCHAR(255) COMMENT '可选打款凭证';

ALTER TABLE mg_op_log
  ADD COLUMN target_uid INT,
  ADD COLUMN amount BIGINT,
  ADD COLUMN extra_json TEXT;

ALTER TABLE wx_user
  ADD COLUMN paypwd_lock_until DATETIME COMMENT '支付密码锁定到何时';
```

### 5.3 TRUNCATE 12 表(开发期清空)

```sql
TRUNCATE wx_wallet;
TRUNCATE wx_wallet_info;
TRUNCATE wx_wallet_coin;
TRUNCATE wx_wallet_coin_item;
TRUNCATE wx_user_recharge_item;
TRUNCATE wx_wallet_recharge_item;
TRUNCATE wx_user_withhold_item;
TRUNCATE wx_wallet_withhold_items;
TRUNCATE wx_wallet_back_red_packet_items;
TRUNCATE wx_wallet_send_red_packet;
TRUNCATE wx_wallet_grab_red_item;
TRUNCATE wx_wallet_red_packet_random;
```

### 5.4 INSERT 初始化数据

详见 DDL 附录:
- 8 个预设密保问题
- 38 个权限点(mg_auth)
- 4 个新角色(mg_role)
- 角色绑权限(mg_role_auth)
- 5 个 conf 配置项(WX_WALLET_BALANCE_CAP_CNY 等)

### 5.4 5upay 删除清单

**JAR 文件**:
- `init-lib/lib/5upay-sdk-java/` 整目录(含 macOS `._*` 元数据)→ rm -rf

**安装脚本**:
- `init-lib/install.sh:63` 行(`mvn install:install-file ... 5upay-sdk-core-1.0.0.jar`)→ 删

**Maven 依赖**(2 处易漏):
- `bs-server/service-pay/pom.xml` 中 `<artifactId>5upay-sdk-core</artifactId>` 整 dependency 块 → 删
- `bs-server/service/pom.xml` 中同上 → 删

**Java 代码**(共 ~25 文件):
- `bs-server/service-pay/.../impl/pay5u/` 整目录 → rm -rf(含 Pay5UConst / Pay5uApi / Pay5uCallBackApi / 17 个 *5UResp.java)
- `bs-server/service-pay/.../service/impl/Pay5uService.java` → 删
- `bs-server/service-pay/.../service/WalletQueueApi.java` → 改写(去 5upay 引用,保队列壳)
- `bs-server/service-pay/.../init/PayInit.java` → 重写为 PayLocalServiceInit
- `bs-server/http-server-api/.../controller/pay/PayCallbackController.java` → 整文件大概率删

**配置项**(properties 中 5upay.* / pay5u.*):
- `bs-server/all/src/main/resources/app.properties` → grep + 删
- `bs-server/all/src/main/resources/app-env.properties` → grep + 删

**新增**:`PayLocalServiceImpl.java` 实现 `BasePayService` 接口。

---

## 6. Phase 实施计划

### Phase 1 — 后端基础(2-3 天,我后端单干)

**D1**:
- 数据库 DDL 脚本上 anjuke.site 开发库
- TRUNCATE 12 表
- INSERT 初始化数据

**D2**:
- 删除 5upay-sdk-core 完整清理(jar / install.sh / pom / 代码 / 配置)
- 编写 PayLocalServiceImpl + WalletService(并发安全模板)
- 改写 PayInit / 删除 PayCallbackController
- mvn clean install 验证编译通过

**D3**:
- bs-server 接口:
  - `/pay/openLite` 激活钱包
  - `/pay/security/*` 密保 5 接口
  - `/user/setpaypwd` 增强(uid 盐 + 顺手激活)
- 单元自测 + L0 冒烟 1-3 项
- 推 PRD + 接口契约 + DDL 到 comm-repo

### Phase 2 — 充值/提现接口(2-3 天,我 + codex 并行)

**我后端**:
- `/pay/recharge/methods` `/apply` `/cancel` `/list` `/detail`
- `/pay/withhold/methods` `/apply` `/cancel` `/list` `/detail`
- `/pay/payout-accounts/*` 5 接口
- `/pay/coin-items/list` 流水
- 红包接口本地化对接 WalletService
- mg-server B1-B4(MgPayMethod / MgRechargeAudit / MgWithholdAudit / MgWallet)

**codex 客户端**(handoff 后启动):
- C1-C2 钱包激活流(替换截图所示页面 → 设密码 + 3 题密保)
- 支付密码摘要改用 uid 盐(4 个 dart 文件)

### Phase 3 — 后台 UI + 客户端(2-3 天,并行)

**我后端**:
- mg-page 4 个页面:支付方式 / 充值审 / 提现审 / 用户钱包
- Polling 3 秒推送 + 浏览器声音 + Notification + favicon 红点
- 监控 11 项接入(SQL + webhook)
- mg-page 顶栏 badge

**codex 客户端**:
- C3 充值页(显示尾数 + 复制按钮)
- C4 我的提现方式页(添加/编辑/删除/默认)
- C5 提现页(选账号 + 输金额)
- C6 钱包流水页

### Phase 4 — 联调 + 上线(1 天)

- L0 冒烟 12 项(联调)
- L1 集成 15 项(主测)
- L2 端到端 5 次
- 上线 Go/No-Go 标准检查
- 部署 jar + 切换 properties + 重启 bs-server / mg-server
- 监控告警上线
- 用户验收

**总工期 8-10 天**(并行后)。

---

## 7. 测试计划

详见 [§4.13](#413-测试--监控)。

### 7.1 L0 冒烟(部署后立即跑)

12 项核心流程,5-10 分钟跑完。任一失败 = 回滚。

### 7.2 L1 集成

15 项并发/边界,30-60 分钟。

### 7.3 L2 端到端

完整真实场景 × 5 次稳定通过。

### 7.4 安全测试

- 盗号尝试改提现账号 → 必须密保拦截
- 暴力支付密码 5 次 → 锁定 30 分钟
- 后台手动加余额 → mg_op_log + 推超管
- 接口越权测试

### 7.5 Go/No-Go 标准

**全部 ✅ 才上线**:
- L0 12 项 100% 通过
- L1 15 项 100% 通过
- L2 5 次稳定通过
- 安全 4 项通过
- 监控 11 指标接入完整
- 数据库备份 OK
- 回滚预案演练过

---

## 8. 监控

详见 [§4.13](#413-测试--监控) 11 项指标。

**Stage 0 实现方式**:SQL 定时任务(谭聊已有 quartz)+ webhook 推钉钉/飞书。

详见 [analysis/88-monitoring-metrics.md](../../analysis/88-monitoring-metrics.md) Stage 0 框架。

---

## 9. 上线 SOP

走 [analysis/81-build-deploy-runbook.md](../../analysis/81-build-deploy-runbook.md) §五 jar 替换 11 步标准流程:

1. 本地 mvn clean install + L0 自测通过
2. ssh anjuke.site:`mysqldump tio_site_main > backup_before_wallet_v2_$(date +%Y%m%d).sql`
3. 执行数据库 DDL 脚本
4. systemctl stop tantan-bs tantan-mg
5. scp jar 到 /opt/tantan/runtime/{bs,mg}/lib/
6. 替换 properties(`pay.local.mode=true` 等)
7. systemctl start tantan-bs tantan-mg
8. 端口监听检查
9. HTTP smoke(全部新接口 200)
10. L1 集成测试
11. 监控告警接入

**回滚**:**单向门,无回滚**(5upay 已删)。如严重问题,只能 hotfix。

---

## 10. 风险与缓解

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| 5upay 删除导致 Maven 编译挂(漏删 import) | 中 | 高(Phase 1 卡)| 严格按 §5.4 清单逐条删,mvn clean install 立即报错可定位 |
| 余额并发 bug 导致负数 | 低 | P0 | 三层防御 + L1 第 1-5 项专测 + 监控 P0 告警 |
| 充值尾数池耗尽(99 笔满) | 极低 | 用户体验 | 监控告警 + 60 分钟超时回收快 |
| 老 APK 用户调老接口 | 中(开发期已发版)| 中 | 强制升级 + 老接口 410 Gone + 友好错误 |
| 管理员审核响应慢导致用户投诉 | 中 | 中 | SLA 30/120/24/72h 多级提醒 + Polling 实时通知 |
| 盗号者改提现账号 | 低 | 高 | 修改账号需密保 + 24h 冷静期 |
| Polling 3 秒导致 mg-server 高 QPS | 低 | 低 | 实测 10 管理员 = 3.3 QPS,微小 |

---

## 11. 关联文档

- 接口契约 → `2026-05-04-wallet-localization-api-contract.md`
- 数据库 DDL → `2026-05-04-wallet-localization-ddl.sql`
- 协作分工 → `2026-05-04-p0-15-frontend-followup-codex.md`
- 知识库引用:[02-deployment.md](../../analysis/02-deployment.md) / [14-bs-server-pay.md](../../analysis/14-bs-server-pay.md) / [60-protocol-contracts.md](../../analysis/60-protocol-contracts.md) / [85-dependency-graph.md](../../analysis/85-dependency-graph.md) / [86-data-migration-guide.md](../../analysis/86-data-migration-guide.md) / [87-ops-runbook.md](../../analysis/87-ops-runbook.md) / [88-monitoring-metrics.md](../../analysis/88-monitoring-metrics.md)

## 12. 变更日志

| 时间 | 变更 |
|---|---|
| 2026-05-04 17:00 | 初版,/grill-me 17 题盘问完成 |
