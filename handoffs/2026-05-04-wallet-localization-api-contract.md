# 钱包本地化改造 — 接口契约 v1

更新时间：2026-05-04 17:30 +08:00 (09:30 UTC)
对应 PRD：`2026-05-04-wallet-localization-prd.md`
适用读者：客户端 codex(用户端 18 接口)+ 后端我自己实现参考(后台 25 接口)

## 0. 通用规范

### 请求

| 维度 | 值 |
|---|---|
| 路径前缀(用户端)| `/mytio/...`(实际,经 nginx 转 bs-server)|
| 路径前缀(后台)| `/tioadmin/...`(实际,经 nginx 转 mg-server)|
| 后缀 | `.tio_x`(用户)/ `.admin_x`(后台)|
| 方法 | 全部 POST 或 GET 见下表 |
| 鉴权 | Cookie `tio_session`(用户)/ Cookie `tio_mg_session`(后台)|
| 请求格式 | application/x-www-form-urlencoded(POST 用 fetchPost)|

### 响应

```json
{
  "ok": true,
  "code": 0,
  "msg": "",
  "data": { ... }
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| ok | bool | 业务是否成功 |
| code | int | 0 成功,4xxx 业务错误,1xxx 鉴权错误 |
| msg | string | 错误消息(中文,直接展示)|
| data | object/array/null | 业务数据 |

### 字段规范

- 时间:`yyyy-MM-dd HH:mm:ss` 字符串(沿用现有)
- 金额:**后端 BIGINT 分**,响应字段也是分。前端展示时除 100。
- 字段命名:camelCase(后端 Java 自动序列化)
- 空值:用 null 不用空字符串
- 序列号:`R231104783521`(R 充值 / W 提现 / T 流水 / U 无主资金)+ Snowflake 后 12 位

### 错误码表

```java
public class WalletErrorCode {
    public static final int OK = 0;

    // 通用鉴权
    public static final int NOT_LOGIN = 1001;
    public static final int NO_PERMISSION = 1004;

    // 钱包激活
    public static final int WALLET_NOT_ACTIVATED = 4001;
    public static final int WALLET_FROZEN = 4002;
    public static final int WALLET_CLOSED = 4003;
    public static final int PAYPWD_LOCKED = 4011;
    public static final int PAYPWD_WRONG = 4012;
    public static final int PAYPWD_FORMAT = 4013;
    public static final int SECURITY_QA_LOCKED = 4021;
    public static final int SECURITY_QA_WRONG = 4022;
    public static final int SECURITY_QA_NOT_SET = 4023;

    // 充值
    public static final int RECHARGE_AMOUNT_TOO_LOW = 4101;
    public static final int RECHARGE_AMOUNT_TOO_HIGH = 4102;
    public static final int RECHARGE_MARKER_POOL_FULL = 4103;
    public static final int RECHARGE_DUP_PENDING = 4104;
    public static final int RECHARGE_BALANCE_CAP = 4105;
    public static final int RECHARGE_RATE_LIMIT = 4106;
    public static final int RECHARGE_ORDER_NOT_FOUND = 4107;
    public static final int RECHARGE_ORDER_EXPIRED = 4108;
    public static final int RECHARGE_ORDER_FINAL_STATE = 4109;

    // 提现
    public static final int WITHHOLD_INSUFFICIENT = 4201;
    public static final int WITHHOLD_AMOUNT_TOO_LOW = 4202;
    public static final int WITHHOLD_AMOUNT_TOO_HIGH = 4203;
    public static final int WITHHOLD_DAILY_COUNT = 4204;
    public static final int WITHHOLD_DAILY_AMOUNT = 4205;
    public static final int WITHHOLD_ACCOUNT_COOLDOWN = 4206;
    public static final int WITHHOLD_ACCOUNT_INVALID = 4207;
    public static final int WITHHOLD_ORDER_NOT_FOUND = 4208;
    public static final int WITHHOLD_ORDER_FINAL_STATE = 4209;

    // 提现账号
    public static final int PAYOUT_ACCOUNT_LIMIT = 4301;
    public static final int PAYOUT_ACCOUNT_DUP = 4302;
    public static final int PAYOUT_ACCOUNT_NOT_FOUND = 4303;
    public static final int PAYOUT_ACCOUNT_FORMAT = 4304;

    // 通用
    public static final int RATE_LIMIT = 4900;
    public static final int OPERATION_TOO_FREQUENT = 4901;
    public static final int CONCURRENT_LOCK = 4902;
    public static final int IP_RATE_LIMIT = 4903;
}
```

---

## 1. 用户端接口(共 18 + 5 已有红包) — 由 codex 实现

### 1.1 钱包激活

#### 1.1.1 `GET /pay/security/questions`

列出预设密保问题池。

**请求**:无入参

**响应**:
```json
{
  "ok": true,
  "code": 0,
  "data": [
    {"id": 1, "question": "您的小学校名是?"},
    {"id": 2, "question": "您母亲的姓名是?"},
    {"id": 3, "question": "您出生的城市是?"},
    {"id": 4, "question": "您父亲的姓名是?"},
    {"id": 5, "question": "您最难忘的老师姓名是?"},
    {"id": 6, "question": "您最喜欢的食物是?"},
    {"id": 7, "question": "您养过的第一只宠物名字是?"},
    {"id": 8, "question": "您高中校名是?"}
  ]
}
```

#### 1.1.2 `POST /pay/openLite`

激活钱包(含设支付密码 + 设 3 题密保)。

**请求**:
| 字段 | 类型 | 必填 | 说明 |
|---|---|---|---|
| paypwd | string | 是 | MD5("${" + uid + "}" + 6位明文)|
| qa1_qid | int | 是 | 第 1 题 question_id |
| qa1_answer | string | 是 | 第 1 题答案(后端 trim+lower 后哈希)|
| qa2_qid | int | 是 | 第 2 题 question_id(必须与 qa1_qid 不同)|
| qa2_answer | string | 是 | 同上 |
| qa3_qid | int | 是 | 第 3 题 question_id |
| qa3_answer | string | 是 | |

**成功响应**:
```json
{"ok": true, "code": 0, "data": {"walletid": "1024-w001", "paypwdflag": 1, "status": 1}}
```

**错误**:`PAYPWD_FORMAT 4013` / `SECURITY_QA_NOT_SET 4023`(题不齐 3 个 / 重复)

#### 1.1.3 `GET /pay/security/my-questions`

找回支付密码时,返回我已绑定的 3 题 question_id 和 question 文本(不返回答案)。

**请求**:无入参(uid 从 session 取)

**响应**:
```json
{
  "ok": true,
  "data": [
    {"order_no": 1, "qid": 1, "question": "您的小学校名是?"},
    {"order_no": 2, "qid": 5, "question": "您最难忘的老师姓名是?"},
    {"order_no": 3, "qid": 7, "question": "您养过的第一只宠物名字是?"}
  ]
}
```

#### 1.1.4 `POST /pay/security/verify-and-reset`

提交 3 答案 + 设新支付密码。

**请求**:
| 字段 | 类型 | 必填 |
|---|---|---|
| qa1_answer | string | 是 |
| qa2_answer | string | 是 |
| qa3_answer | string | 是 |
| new_paypwd | string | 是 |

**成功响应**:
```json
{"ok": true, "code": 0}
```

**错误**:`SECURITY_QA_WRONG 4022` / `SECURITY_QA_LOCKED 4021`(连错 5 次锁 30 分钟)

#### 1.1.5 `POST /pay/security/update`

修改密保(需要原支付密码 + 原 3 题密保 — 高敏)。

**请求**:
| 字段 | 类型 | 必填 |
|---|---|---|
| old_paypwd | string | 是 |
| old_qa1_answer ~ old_qa3_answer | string | 是 |
| new_qa1_qid ~ new_qa3_qid | int | 是 |
| new_qa1_answer ~ new_qa3_answer | string | 是 |

**响应**:`ok` / 错误

### 1.2 充值

#### 1.2.1 `GET /pay/recharge/methods`

列出可用充值方式。

**响应**:
```json
{
  "ok": true,
  "data": [
    {
      "id": 1,
      "name": "支付宝-财务A",
      "method_type": "alipay",
      "account": "13800000000",
      "payee_name": "张三",
      "qrcode_url": "https://res.anjuke.site/img/zfb-qr.jpg",
      "min_amount": 100,
      "max_amount": 10000000,
      "fee_rate": 0.0,
      "fee_fixed": 0,
      "remark": "营业时间 09:00-22:00",
      "sort": 10
    },
    {
      "id": 2,
      "name": "USDT-TRC20",
      "method_type": "usdt",
      "chain_type": "TRC20",
      "account": "TXXxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxX",
      "qrcode_url": "https://res.anjuke.site/img/usdt-trc20.png",
      "min_amount": 1000,
      "max_amount": null,
      "fee_rate": 0.0,
      "fee_fixed": 0,
      "remark": "USDT 1:7 折算人民币(后台调汇率)",
      "sort": 20
    }
  ]
}
```

#### 1.2.2 `POST /pay/recharge/apply`

提交充值申请。

**请求**:
| 字段 | 类型 | 必填 |
|---|---|---|
| method_id | int | 是 |
| amount | bigint | 是 | 申请金额(分),如 10000 表示 100 元 |

**成功响应**:
```json
{
  "ok": true,
  "code": 0,
  "data": {
    "id": 12345,
    "serial_no": "R231104783521",
    "method_id": 1,
    "method_name": "支付宝-财务A",
    "method_type": "alipay",
    "amount": 10000,
    "marker_amount": 100.07,
    "marker_decimal": 7,
    "qrcode_url": "https://res.anjuke.site/img/zfb-qr.jpg",
    "account": "13800000000",
    "payee_name": "张三",
    "fee": 0,
    "actual_credit": 10000,
    "audit_status": 1,
    "audit_status_label": "待审",
    "expire_time": "2026-05-04 18:30:00",
    "createtime": "2026-05-04 17:30:00"
  }
}
```

**错误**:
- `RECHARGE_AMOUNT_TOO_LOW 4101`("最低 1 元")
- `RECHARGE_MARKER_POOL_FULL 4103`("当前充值繁忙,请稍后或调整金额")
- `RECHARGE_DUP_PENDING 4104`("您已有 3 笔同金额段待审")
- `RECHARGE_BALANCE_CAP 4105`("超过余额上限 100 万")
- `RECHARGE_RATE_LIMIT 4106`("操作过于频繁")
- `WALLET_NOT_ACTIVATED 4001`

**客户端 UX**:
- 拿到 marker_amount 后,显示大字号:`¥100.07`
- 加"复制金额"按钮 → 复制到剪贴板
- 加"打开扫码"按钮(如有 qrcode_url)
- 计时器倒数(60 分钟过期)

#### 1.2.3 `POST /pay/recharge/cancel`

用户主动取消未到账订单。

**请求**:
| 字段 | 类型 | 必填 |
|---|---|---|
| order_id | bigint | 是 |

**响应**:`ok` / `RECHARGE_ORDER_FINAL_STATE 4109`("订单已不可取消")

#### 1.2.4 `GET /pay/recharge/list`

我的充值历史。

**请求**:
| 字段 | 默认 |
|---|---|
| status | "all" / "pending" / "done" / "rejected" / "expired" / "cancelled" |
| page | 1 |
| size | 20 |
| start_date | (可选)默认 30 天前 |
| end_date | (可选)默认今天 |

**响应**:
```json
{
  "ok": true,
  "data": {
    "list": [...],
    "total": 156,
    "page": 1,
    "size": 20
  }
}
```

#### 1.2.5 `GET /pay/recharge/detail`

单个订单详情。

**请求**:`order_id`

**响应**:同 1.2.2 + `audit_remark`(如已审)+ `audit_time`

### 1.3 提现 — 账号绑定

#### 1.3.1 `GET /pay/payout-accounts`

我的提现账号列表。

**响应**:
```json
{
  "ok": true,
  "data": [
    {
      "id": 1,
      "method_type": "alipay",
      "account": "13800000000",
      "payee_name": "张三",
      "is_default": 1,
      "verified": 1,
      "usable_after": "2026-05-04 18:00:00",
      "is_usable_now": true,
      "createtime": "2026-05-03 17:00:00"
    },
    {
      "id": 2,
      "method_type": "usdt",
      "chain_type": "TRC20",
      "account": "TXXxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxX",
      "is_default": 0,
      "verified": 0,
      "usable_after": "2026-05-05 18:00:00",
      "is_usable_now": false,
      "createtime": "2026-05-04 18:00:00"
    }
  ]
}
```

#### 1.3.2 `POST /pay/payout-accounts/add`

添加提现账号(需支付密码)。

**请求**:
| 字段 | 类型 | 必填 |
|---|---|---|
| paypwd | string | 是 |
| method_type | string | 是 | alipay/wechat/bank/usdt/custom |
| account | string | 是 | 账号/地址 |
| payee_name | string | 视类型 | bank 必填,其他可选 |
| chain_type | string | usdt 必填 | TRC20/ERC20/BEP20/Polygon |
| extra | string | 否 | JSON,如银行支行/币种说明 |
| qrcode_url | string | 否 | |

**响应**:
```json
{
  "ok": true,
  "data": {"id": 3, "usable_after": "2026-05-05 17:30:00"}
}
```

**错误**:`PAYOUT_ACCOUNT_LIMIT 4301`("最多 5 个")/ `PAYOUT_ACCOUNT_DUP 4302`("此账号已绑定")/ `PAYOUT_ACCOUNT_FORMAT 4304`("地址格式错误")

#### 1.3.3 `POST /pay/payout-accounts/update`

修改账号(需支付密码 + 3 题密保 — 高敏)。

**请求**:同 add + `id` + 3 题密保答案

**响应**:`ok` / `SECURITY_QA_WRONG 4022`

注意:修改后 `usable_after` 重新设为 now+24h。

#### 1.3.4 `POST /pay/payout-accounts/delete`

**请求**:`id` + `paypwd`

**响应**:`ok`

#### 1.3.5 `POST /pay/payout-accounts/setDefault`

**请求**:`id`

**响应**:`ok`

### 1.4 提现申请

#### 1.4.1 `GET /pay/withhold/methods`

类似 `/pay/recharge/methods`,但 type=2。

#### 1.4.2 `POST /pay/withhold/apply`

提交提现申请。

**请求**:
| 字段 | 类型 | 必填 |
|---|---|---|
| method_id | int | 是 |
| account_id | int | 是 | 已绑定账号 id |
| amount | bigint | 是 | 申请金额(分)|
| paypwd | string | 是 | 验证支付密码 |

**响应**:
```json
{
  "ok": true,
  "data": {
    "id": 67890,
    "serial_no": "W231104783521",
    "amount": 5000,
    "fee": 50,
    "actual_payout": 4950,
    "audit_status": 1,
    "audit_status_label": "待审",
    "createtime": "2026-05-04 17:30:00"
  }
}
```

**错误**:
- `WITHHOLD_INSUFFICIENT 4201`("可用余额不足")
- `WITHHOLD_DAILY_COUNT 4204`("超过单日 5 笔")
- `WITHHOLD_DAILY_AMOUNT 4205`("超过单日 5 万")
- `WITHHOLD_ACCOUNT_COOLDOWN 4206`("账号冷静期未结束")
- `WITHHOLD_ACCOUNT_INVALID 4207`("账号已删除")
- `PAYPWD_WRONG 4012`

#### 1.4.3 `POST /pay/withhold/cancel`

仅 audit_status=1 待审可取消。

#### 1.4.4 `GET /pay/withhold/list` / `GET /pay/withhold/detail`

类似充值。

### 1.5 钱包查询

#### 1.5.1 `GET /pay/getWalletInfo`

钱包信息(沿用现有,语义本地化适配)。

**响应**:
```json
{
  "ok": true,
  "data": {
    "uid": 1024,
    "walletid": "1024-w001",
    "status": 1,
    "status_label": "正常",
    "openflag": 1,
    "paypwdflag": 1,
    "cny": 50000,
    "frozen_cny": 5000,
    "available_cny": 45000,
    "total_recharge": 100000,
    "total_withdraw": 50000,
    "send_redpacket": 30000,
    "accept_redpacket": 30000,
    "balance_cap_cny": 100000000,
    "createtime": "2026-05-01 17:00:00"
  }
}
```

#### 1.5.2 `GET /pay/coin-items/list`

流水。

**请求**:
| 字段 | 默认 |
|---|---|
| mode | "all" / 1充值 / 2提现 / 3红包 |
| coinflag | "all" / 1收入 / 2支出 |
| page / size | 1/20 |
| start_date / end_date | 默认 30 天 |

**响应**:list of item。

### 1.6 红包(沿用现有,无需 codex 改 — 后端实现替换)

- `POST /pay/sendRedpacket`(已有)
- `POST /pay/grabRedpacket`(已有)
- `GET /pay/redInfo`(已有)
- `GET /pay/sendRedpacketlist` / `/pay/grabRedpacketlist`(已有)
- `GET /pay/redStatus`(已有)

后端把 service-pay 实现从 PayStdServiceImpl 切换到 PayLocalServiceImpl,字段不变。

---

## 2. 后台接口(共 25) — 后端我自己实现

### 2.1 支付方式管理(MgPayMethodController)

| 路径 | 方法 | 用途 |
|---|---|---|
| `/mg/paymethod/list` | GET | 列所有方式(type 筛选)|
| `/mg/paymethod/save` | POST | 增/改(id 为空则增)|
| `/mg/paymethod/delete` | POST | 删 |
| `/mg/paymethod/toggle` | POST | 启用/停用 |

**方式字段**(同 1.2.1 + 后台字段):
- 加 `cny_per_unit DECIMAL`(USDT 用,1 USDT = X 元)
- 加 `qrcode_filename`(上传后端文件名)

### 2.2 充值审核(MgRechargeAuditController)

| 路径 | 方法 | 用途 |
|---|---|---|
| `/mg/recharge/pending` | GET | 待审列表(audit_status=1)|
| `/mg/recharge/all` | GET | 全部历史(可筛选 status / uid / 时间)|
| `/mg/recharge/detail` | GET | 单详情 |
| `/mg/recharge/lock` | POST | 锁定(audit_status 1→2)|
| `/mg/recharge/unlock` | POST | 释放锁(自己锁定的可释放)|
| `/mg/recharge/match-by-amount` | GET | 按金额查待审(对账用)|
| `/mg/recharge/approve` | POST | 通过 |
| `/mg/recharge/reject` | POST | 拒绝 + 必填理由 ≥ 5 字 |

**approve 入参**:
```
order_id: 12345
actual_amount: 10007  (实收分,可能与 marker_amount 不同 — 但严格要求 = marker_amount)
remark: "已对账,微信收款 100.07"
```

### 2.3 提现审核(MgWithholdAuditController)

| 路径 | 方法 | 用途 |
|---|---|---|
| `/mg/withhold/pending` | GET | 待审列表 |
| `/mg/withhold/all` | GET | 全部历史 |
| `/mg/withhold/detail` | GET | 详情(含绑定账号快照)|
| `/mg/withhold/lock` `/unlock` | POST | 同充值 |
| `/mg/withhold/approve` | POST | 通过(可选上传打款凭证)|
| `/mg/withhold/reject` | POST | 拒绝 + 理由 |

**approve 入参**:
```
order_id: 67890
payout_evidence: (可选)上传图 url
remark: "已转账"
```

### 2.4 用户钱包(MgWalletController)

| 路径 | 方法 | 用途 | 权限 |
|---|---|---|---|
| `/mg/wallet/list` | GET | 用户钱包列表(分页 + 搜索 uid/手机/邮箱)| 所有有"查看"权限角色 |
| `/mg/wallet/detail` | GET | 单用户详情(余额/流水/状态)| 同上 |
| `/mg/wallet/credit` | POST | 手动加余额 + 必填理由 ≥ 50 字 | 超管 + 财务 |
| `/mg/wallet/debit` | POST | 手动扣余额 + 必填理由 ≥ 50 字 | 超管 + 财务 |
| `/mg/wallet/freeze` | POST | 冻结 + 必填理由 | 超管 + 财务 |
| `/mg/wallet/unfreeze` | POST | 解冻 | 超管 + 财务 |
| `/mg/wallet/reset-paypwd` | POST | 客服代重置(需输用户 phone 核身)| 超管 + 客服 |

### 2.5 无主资金(MgUnmatchedController)

| 路径 | 方法 | 用途 |
|---|---|---|
| `/mg/unmatched/list` | GET | 待处理列表 |
| `/mg/unmatched/record` | POST | 录入收到的款项(管理员看到收款码进账时录)|
| `/mg/unmatched/match-user` | POST | 匹配到指定 uid(给该用户加余额)|
| `/mg/unmatched/refund` | POST | 标记已退回原账户 |
| `/mg/unmatched/ignore` | POST | 忽略 + 必填理由(测试转账)|

### 2.6 限额配置(MgLimitsController)

| 路径 | 方法 |
|---|---|
| `/mg/limits/list` | GET |
| `/mg/limits/save` | POST |

写到 conf 表(WX_WALLET_BALANCE_CAP_CNY 等)。

### 2.7 密保问题池(MgSecurityQuestionController)

| 路径 | 方法 |
|---|---|
| `/mg/secquestion/list` | GET |
| `/mg/secquestion/save` | POST |
| `/mg/secquestion/delete` | POST |

### 2.8 实时通知(MgAuditPollController)

| 路径 | 方法 | 用途 |
|---|---|---|
| `/mg/audit/poll` | GET | 浏览器每 3 秒调,拿事件队列 + 全量计数 |
| `/mg/audit/pending-count` | GET | 仅查计数(独立请求)|

**poll 响应**:
```json
{
  "ok": true,
  "data": {
    "events": [
      {"type": "recharge_pending", "order_id": 12345, "amount": 10000, "uid": 1024, "ts": "..."},
      {"type": "withdraw_pending", "order_id": 67890, "amount": 5000, "uid": 1025, "ts": "..."}
    ],
    "recharge_pending": 3,
    "withdraw_pending": 2,
    "unmatched_pending": 1
  }
}
```

### 2.9 审计日志(MgAuditLogController — 仅超管)

| 路径 | 方法 |
|---|---|
| `/mg/auditlog/list` | GET |
| `/mg/auditlog/export` | GET | 导 Excel |

数据从 mg_op_log 查,加上 `target_uid / amount / extra_json` 字段筛选。

---

## 3. 已废弃接口(部署时改 410 Gone)

下列接口在本地化后**不可用**,改返回 HTTP 410(Gone):

- `POST /pay/open`(实名开户 — 改用 /pay/openLite)
- `POST /pay/updateOpenInfo`(更新实名信息 — 没有实名了)
- `POST /pay/recharge`(走新生通道 — 改用 /pay/recharge/apply)
- `POST /pay/rechargeconfirm`
- `POST /pay/withhold`(走新生提现 — 改用 /pay/withhold/apply)
- `POST /pay/withholdQuery`
- `GET /pay/getClientToken`
- `POST /pay/realinfo`(查实名 — 没有实名)
- `POST /pay/callback/*`(新生回调,整 Controller 删)

**实现**:在 PayController 保留接口签名,直接 return Resp.fail("此接口已废弃,请升级到最新版客户端") + HTTP 410 status。

---

## 4. 老 APK 处理

强制升级机制:
- 后台 conf 加 `app.minimum.version=10.0.1`(Phase 4 部署后的版本号)
- 客户端启动时调 `/version/check.tio_x` 拿到 minimum_version
- 若客户端 < minimum → 弹强制升级对话框,跳下载页

老 APK(没有钱包激活流):
- 用户打开钱包页 → 检测 paypwdflag=0 + 无密保 → 但老 APK 没有"激活页" → 客户端跳"请升级"
- 调 /pay/open(老接口)→ 410 + 提示升级

---

## 5. 客户端摘要算法变更(关键!)

**所有 4 个 dart 文件**:
- `set_pay_pwd_req.dart`
- `update_pay_pwd_req.dart`
- `reseet_pay_pwd_req.dart`
- `check_pay_pwd_req.dart`

把 `phone` 改成 `uid`:

```dart
// 旧
addParam('paypwd', Md5Utils.encode('\${$phone}$pwd'));

// 新
addParam('paypwd', Md5Utils.encode('\${$uid}$pwd'));
```

后端同步:`UserService.setPayPwd` 校验逻辑用 uid 计算 hash 比对。

---

## 6. 客户端关键 UX 提示

### 6.1 钱包激活页

```
[标题] 激活钱包
[正文] 设置 6 位支付密码 + 选择 3 个密保问题(用于找回支付密码)

支付密码:[ ____ ____ ____ ____ ____ ____ ]  6 位纯数字
确认密码:[ ____ ____ ____ ____ ____ ____ ]

密保问题 1: [下拉选,从 8 题预设池]    答案: [输入框]
密保问题 2: [下拉选,与 1 不同]        答案: [输入框]
密保问题 3: [下拉选,与 1/2 不同]      答案: [输入框]

⚠️ 请记住答案!忘记支付密码时通过密保找回。

[激活钱包] 按钮
```

### 6.2 充值页

```
[标题] 充值
[选择支付方式] (列出 /pay/recharge/methods)
[输入金额] [ 100 ] 元

[提交]
↓ 后端返回 marker_amount = 100.07

[显示订单]
应付金额: ¥100.07         [大字号,可复制]
                          ⚠️ 请按精确金额转账,系统将自动识别
扫码支付 / 转账信息: [收款码图]
                    支付宝账号: 13800000000(张三)
有效期: 59:30 倒计时

[已转账,等待到账] / [取消订单]
```

### 6.3 提现 — 我的提现方式页

```
[标题] 我的提现方式  [+ 添加]

[卡片 1] ⭐ 默认  支付宝  138****0000(张三)
        添加于 2 天前  [已验证]
        [设默认] [编辑] [删除]

[卡片 2]  USDT-TRC20  TXXxxxx****xxxxX
        添加于 1 小时前  [⏳ 22 小时后可用]
        [设默认] [编辑] [删除]

⚠️ 安全提示:为保障资金安全,新绑定/修改的账号 24 小时后才能用于提现
```

### 6.4 提现页

```
[标题] 提现
[选择提现方式] [下拉]
[选择收款账号] [列出我的可用账号,过 24h 的]
[输入金额] [ 50 ] 元
[手续费] 0.5 元(自动计算展示)
[实际到账] 49.5 元(自动计算)
可用余额: 100.00 元

[输入支付密码] [ ____ ____ ____ ____ ____ ____ ]

[提交申请]
```

---

## 7. 联调测试用例(L0 冒烟)

详见 PRD §7.1。

---

## 8. 变更日志

| 时间 | 变更 |
|---|---|
| 2026-05-04 17:30 | 初版,Phase 1-2 实施基线 |
