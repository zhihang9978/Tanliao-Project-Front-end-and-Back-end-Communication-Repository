# 钱包本地化改造 — Flutter 客户端改造 handoff(给 codex)

更新时间:2026-05-04 21:00 +08:00 (13:00 UTC)
责任方:Codex(Flutter 客户端 + bs-page tioim 用户端 SPA)
后端状态:✅ Phase 1+2+3 全部完成,所有接口已部署到 anjuke.site,smoke 通过

## 0. TL;DR

后端钱包本地化改造已经**全部完成 + 部署上线**。截图所示"初语钱包账户开通说明"页面要被替换为"设支付密码 + 3 题密保"。客户端工作清单:

1. **删** 实名表单页面
2. **新建** 钱包激活流(支付密码 + 3 题密保)
3. **改造** 充值页(显示带尾数金额 + 复制按钮)
4. **新建** 我的提现方式页(账号绑定管理)
5. **改造** 提现页(选已绑账号 + 24h 冷静期)
6. **改造** 钱包流水页(适配新状态)
7. **改造** 4 个支付密码 dart 文件:盐值从 `phone` → `uid`

**预计客户端工作量**:4-5 天(若两人并行可缩到 3 天)

**关键截图位置**:
- 接口契约 完整 → `2026-05-04-wallet-localization-api-contract.md` §1(用户端 18 接口)
- PRD → `2026-05-04-wallet-localization-prd.md`(完整决策)
- DDL → `2026-05-04-wallet-localization-ddl.sql`

## 1. 后端就绪状态

### 1.1 用户端接口(共 18 个,已上线 https://api.anjuke.site/mytio/...)

#### 钱包激活
- `GET  /pay/security/questions` — 列预设密保问题池(8 题)
- `POST /pay/openLite` — 激活钱包(paypwd + 3 题密保 一次性提交)
- `GET  /pay/security/my-questions` — 我的 3 题(找回时)
- `POST /pay/security/verify-and-reset` — 答 3 题 + 设新支付密码
- `POST /pay/security/update` — 修改密保

#### 充值
- `GET  /pay/recharge/methods` — 列充值方式(从 wx_pay_method 拉)
- `POST /pay/recharge/apply` — 提交充值(后端生成 0.01-0.99 尾数 + 60 分钟超时)
- `POST /pay/recharge/cancel` — 取消订单
- `GET  /pay/recharge/list` — 我的充值历史(支持 status / 时间 / 分页)
- `GET  /pay/recharge/detail` — 详情

#### 提现 — 账号绑定
- `GET  /pay/payout-accounts/list` — 我的所有提现账号
- `POST /pay/payout-accounts/add` — 添加(需支付密码 + 24h 冷静期)
- `POST /pay/payout-accounts/update` — 修改(需支付密码 + **3 题密保**,高敏)
- `POST /pay/payout-accounts/delete` — 删除(需支付密码,软删)
- `POST /pay/payout-accounts/setDefault` — 设默认

#### 提现申请
- `GET  /pay/withhold/methods` — 列提现方式
- `POST /pay/withhold/apply` — 提交提现(冻结余额)
- `POST /pay/withhold/cancel` — 取消(解冻)
- `GET  /pay/withhold/list` / `detail`

#### 钱包查询
- `GET  /pay/getWalletInfo` — 钱包信息(返回 cny + frozen_cny + status 等)
- `GET  /pay/coin-items/list` — 流水

#### 红包(沿用,实现替换为 PayLocalService)
- `POST /pay/sendRedpacket` `/grabRedpacket` 等(现有协议不变)

### 1.2 错误码标准化

后端返回 `{ok, code, msg, data}`,关键 code:
- `1001 NOT_LOGIN` 未登录
- `4001 WALLET_NOT_ACTIVATED` 钱包未激活
- `4002 WALLET_FROZEN` 钱包冻结
- `4012 PAYPWD_WRONG` 支付密码错误
- `4011 PAYPWD_LOCKED` 支付密码锁定中(连错 5 次锁 30 分钟)
- `4022 SECURITY_QA_WRONG` 密保答错
- `4021 SECURITY_QA_LOCKED` 密保锁定中
- `4101 RECHARGE_AMOUNT_TOO_LOW` 充值金额过低(默认 ≥ 1 元)
- `4103 RECHARGE_MARKER_POOL_FULL` 同金额段尾数池满
- `4106 RECHARGE_RATE_LIMIT` 频次过高
- `4201 WITHHOLD_INSUFFICIENT` 余额不足
- `4204 WITHHOLD_DAILY_COUNT` 单日提现超限
- `4205 WITHHOLD_DAILY_AMOUNT` 单日提现总额超限
- `4206 WITHHOLD_ACCOUNT_COOLDOWN` 提现账号冷静期(24h 内)
- `4301 PAYOUT_ACCOUNT_LIMIT` 绑定账号超过 5 个
- `4302 PAYOUT_ACCOUNT_DUP` 同账号重复绑定
- `4304 PAYOUT_ACCOUNT_FORMAT` 地址格式错(USDT 链格式)

完整错误码表见接口契约 §0。

## 2. 客户端改造任务

### 2.1 截图所示实名表单页 — 删除

文件位置:Flutter 客户端钱包入口页(具体路径 codex 自查,关键字 "钱包账户开通说明" / "新生支付")

```dart
// 当前实现:OpenAccountPage 含姓名/身份证/手机号/同意授权按钮
// 改造:删除整个页面,替换为 ActivateWalletPage(下面)
```

### 2.2 新建钱包激活页(替换截图所示页面)

UI 草图:

```
[标题] 激活钱包
[正文] 为保障资金安全,激活钱包需:
       1. 设置 6 位支付密码(用于发红包/提现)
       2. 选择 3 个密保问题(用于忘记支付密码时找回)

[支付密码]   [ ____ ____ ____ ____ ____ ____ ]   6 位纯数字
[确认密码]   [ ____ ____ ____ ____ ____ ____ ]   两次必须一致

[密保 1] [下拉,从 8 题预设池] 答案:[输入框]
[密保 2] [下拉,与 1 不同]   答案:[输入框]
[密保 3] [下拉,与 1/2 不同] 答案:[输入框]

⚠️ 请记住答案!忘记支付密码时通过密保找回。

[激活钱包] 按钮
```

**实现关键**:
1. 进入页面时先调 `GET /pay/security/questions` 拉 8 题(填充下拉选项)
2. 提交时一次性 POST `/pay/openLite`,入参:
   ```
   paypwd: MD5("${" + uid + "}" + 6位明文)   ← 用 uid,不再用 phone!
   qa1_qid: int
   qa1_answer: string
   qa2_qid: int
   qa2_answer: string
   qa3_qid: int
   qa3_answer: string
   ```
3. 答案提交前 `trim().toLowerCase()` 标准化(后端会 trim+lower 后 hash)
4. 校验:3 题 question_id 必须不同,3 个答案非空(1-30 字符)
5. 提交成功 → 关闭激活页 → 刷新钱包主页(此时 paypwdflag=1)

### 2.3 改造支付密码摘要算法(关键!)

**4 个 dart 文件**(grep `pay_pwd` 找位置):
- `set_pay_pwd_req.dart`
- `update_pay_pwd_req.dart`
- `reseet_pay_pwd_req.dart`
- `check_pay_pwd_req.dart`

**改动**:把盐从 `phone` 换成 `uid`:

```dart
// 旧
addParam('paypwd', Md5Utils.encode('\${$phone}$pwd'));

// 新
addParam('paypwd', Md5Utils.encode('\${$uid}$pwd'));
```

`uid` 客户端登录后已知,从 GetX UserController 或类似获取(`Get.find<UserController>().userInfo.uid`)。

后端 `UserService.updatePayPwd` 已经改用 uid 盐(Phase 1 D3 完成)。

### 2.4 钱包激活前检测

进入钱包页 / 充值 / 提现 时,先调 `GET /pay/getWalletInfo`,如果 `paypwdflag=0`:
- 拦截操作,弹"请先激活钱包"
- 跳到激活页(2.2)

### 2.5 改造充值页

UI 草图:

```
[标题] 充值

[选择支付方式]
  ⊙ 支付宝-财务A   [收款码缩略图]
  ○ USDT-TRC20    [收款码缩略图]
  ○ 银行卡-财务B
  ...

[输入金额]    [ 100 ] 元

[提交]
↓
[展示订单详情]
======================================
应付金额:  ¥100.07         ← 大字号
            ⚠️ 请精确转账此金额,系统自动识别
[复制金额] [打开扫码]
账号信息:
   支付宝账号:13800000000(张三)
   收款码:[二维码图]

⏱️ 订单有效期 60 分钟,剩余 [59:30] 倒计时

[已转账,等待到账]   [取消订单]
======================================
```

**实现关键**:
1. 进入页面调 `GET /pay/recharge/methods` 列出 type=1 的方式
2. 用户选方式 + 输入金额 → POST `/pay/recharge/apply { method_id, amount: 整数分(100元=10000分) }`
3. 接收响应中的 `data.marker_amount`(BigDecimal,如 100.07)
4. **关键 UX**:展示 `¥100.07` 大字号 + "复制"按钮(`Clipboard.setData(...)`)
5. 60 分钟倒计时(`expire_time` 字段返回)
6. 用户点"已转账等待到账"→ 跳列表页轮询 `GET /pay/recharge/detail` 查状态
7. 用户点"取消订单"→ POST `/pay/recharge/cancel`
8. **错误处理**:
   - `4103` 尾数池满 → 提示"当前充值繁忙,请稍后重试或调整金额"
   - `4101` 金额过低 → 提示"最低充值金额 1 元"
   - `4106` 频次过高 → 提示"操作过于频繁,请稍后再试"
   - `4001` 钱包未激活 → 跳激活页
   - `4002` 钱包冻结 → 提示"您的钱包已被冻结,请联系客服"
   - `4105` 余额上限 → 提示"超过账户余额上限"

### 2.6 新建"我的提现方式"页

UI 草图:

```
[标题] 我的提现方式  [+ 添加]

[卡片 1] ⭐ 默认  支付宝
        13800000000 (张三)
        添加于 2 天前  [✓ 已验证]
        [设默认] [编辑] [删除]

[卡片 2]  USDT-TRC20
        TXXxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
        添加于 1 小时前  [⏳ 22 小时后可用]
        [设默认] [编辑] [删除]

⚠️ 安全提示:
   - 最多绑定 5 个账号
   - 修改/新绑账号 24 小时内不能用于提现
   - 修改账号需要支付密码 + 密保 3 题验证
```

**添加账号弹窗**:
```
[选择类型]
  ⊙ 支付宝
  ○ 微信
  ○ 银行卡
  ○ USDT
  ○ 自定义

[根据类型动态显示字段]
  支付宝:账号(手机/邮箱)+ 户名(可选)
  微信:微信号 + 户名(可选)
  银行卡:卡号 + 户名(必填)+ 银行名 + 开户行
  USDT:链类型(下拉 TRC20/ERC20/BEP20/Polygon)+ 钱包地址
  自定义:账号 + 户名 + 备注

[收款码图(可选)] [上传]

[输入支付密码] [ ____ ____ ____ ____ ____ ____ ]

[确定添加]
```

**修改账号弹窗**(高敏):
```
[卡片] 当前账号信息

[修改字段...]

[输入支付密码]
[密保 1: 您的小学校名是?] 答案:[输入框]
[密保 2: ...]              答案:[输入框]
[密保 3: ...]              答案:[输入框]

[确定修改]
↓
⚠️ 修改后将重新进入 24 小时冷静期
```

**实现关键**:
1. 列表:`GET /pay/payout-accounts/list`
2. 添加:`POST /pay/payout-accounts/add`
3. 修改:`POST /pay/payout-accounts/update`(先调 `/pay/security/my-questions` 拉用户的 3 题)
4. 删除:`POST /pay/payout-accounts/delete`(支付密码确认)
5. 设默认:`POST /pay/payout-accounts/setDefault`
6. **USDT 地址校验**(前端,提交前):
   - TRC20: regex `^T[1-9A-HJ-NP-Za-km-z]{33}$`
   - ERC20/BEP20/Polygon: regex `^0x[0-9a-fA-F]{40}$`(共 42 长度)
7. **错误处理**:
   - `4301` 超过 5 个 → "最多绑 5 个,请先删除已有"
   - `4302` 重复 → "此账号已绑定"
   - `4304` 格式错 → "地址格式不正确"

### 2.7 改造提现页

UI 草图:

```
[标题] 提现

[选择提现方式]
  ⊙ 支付宝(2 个绑定)
  ○ 银行卡(1 个绑定)

[选择收款账号]
  ⊙ ⭐ 13800000000 (张三) — 已验证
  ○    18900000001 (李四) — ⏳ 22 小时后可用
  [+ 添加新账号]

[输入金额]   [ 50 ] 元
[手续费]     0.5 元(自动计算)
[实际到账]   49.5 元(自动计算)
可用余额: ¥100.00

[输入支付密码] [ ____ ____ ____ ____ ____ ____ ]

[提交申请]
```

**实现关键**:
1. 进入页面:`GET /pay/withhold/methods` + `GET /pay/payout-accounts/list`
2. 用户选 method + account → 输金额 → 实时计算手续费(`fee = max(amount * fee_rate, fee_fixed)`)
3. **过滤**:只显示 `is_usable_now=true` 的账号(usable_after ≤ now)
4. 提交:POST `/pay/withhold/apply`,入参:
   ```
   method_id: int
   account_id: int
   amount: int 分
   paypwd: MD5("${" + uid + "}" + 6位明文)
   ```
5. **错误处理**:
   - `4201` 余额不足 → "可用余额不足"
   - `4204` `4205` 单日次数/总额超限
   - `4206` 账号冷静期 → "此账号 X 小时后可用"
   - `4012` 支付密码错 → "支付密码错误"
   - `4011` 支付密码锁定 → "密码锁定中,请 X 分钟后重试"
6. 成功 → 显示订单号(serial_no)+ 跳"提现进度"页

### 2.8 改造钱包流水页

`GET /pay/coin-items/list` 已经支持。客户端只需适配新增的字段:
- `mode`(1 充值 / 2 提现 / 3 红包)
- `coinflag`(1 收入 / 2 支出)
- `status`(1 完成 / 2 初始化 / 3 处理中 / 4 拒绝 / 5 取消)

展示状态用不同颜色徽标。

### 2.9 改造钱包主页(余额展示)

`GET /pay/getWalletInfo` 返回:
- `cny` — 总余额(分)
- `frozen_cny` — 冻结(分)
- `available_cny = cny - frozen_cny` — 可用(分)
- `status` 1/2/3 — 钱包状态

UI:
```
[钱包]
  总余额  ¥100.00
  冻结    ¥10.00     ← 如有
  可用    ¥90.00     ← 主展示

  [充值] [提现] [我的提现方式] [流水]

  [钱包状态:正常]    ← 如非 1 ACTIVE 显示警告
```

如 status=2 FROZEN,显示"已被冻结,请联系客服"+ 灰所有按钮。

### 2.10 提现/充值通知接收

后端在审核通过/拒绝时会推 IM 系统消息(WxSysMsgNtf=788,Phase 4 完整对接 — 现在 Phase 3 是 INFO 日志占位,Phase 4 启用)。

客户端的"系统消息"列表已经能收到,UI 展示文案如:
- "您的充值申请 R12345... 已通过,余额 +100 元"
- "您的提现申请 W12345... 未通过,原因:[管理员填写的拒绝理由]"

无需特殊改造。

## 3. 联调时序图(Phase 4 时验证)

```
┌─用户Flutter────┐    ┌─bs-server────┐    ┌─mg-server────┐    ┌─管理员mg-page─┐
│                │    │              │    │              │    │              │
│ 激活钱包流程   │───→│ /pay/openLite│    │              │    │              │
│                │←───│ 200 ok       │    │              │    │              │
│                │    │              │    │              │    │              │
│ 充值申请 100   │───→│ /recharge/   │    │              │    │              │
│                │    │   apply      │    │              │    │              │
│                │←───│ 100.07,60min │    │              │    │              │
│                │    │ Redis Pub:   │───→│ Topic 收事件 │───→│ Polling 接收  │
│                │    │ recharge_pend│    │ → 队列 push  │    │ → ding + 弹窗 │
│                │    │              │    │              │    │              │
│ 用户转账 100.07│ ── 用户线下扫码转账 ── │              │    │              │
│                │    │              │    │              │    │ 管理员后台收款│
│                │    │              │    │              │    │ 到 100.07,对账│
│                │    │              │←───│ /recharge/   │←───│ approve 请求  │
│                │    │ creditBalance│    │   approve    │    │              │
│                │    │ +100 元       │    │              │    │              │
│                │←───│ IM SysMsgNtf │    │              │    │              │
│                │    │ "已到账"     │    │              │    │              │
└─用户Flutter────┘    └─bs-server────┘    └─mg-server────┘    └─管理员mg-page─┘
```

## 4. 客户端实施分阶段(给 codex 自己安排)

| 阶段 | 工作 | 估时 |
|---|---|---|
| C1 | 改 4 个 *_pay_pwd_req.dart 用 uid 盐 | 0.5 天 |
| C2 | 删实名表单页 + 新建激活页(支付密码 + 3 题密保)| 1 天 |
| C3 | 改造充值页(尾数显示 + 复制 + 倒计时 + 错误处理)| 1 天 |
| C4 | 新建提现账号页(添加/修改/删除/默认 + USDT 校验)| 1 天 |
| C5 | 改造提现页(选账号 + 输金额 + 手续费实时算 + 提交)| 1 天 |
| C6 | 改造流水/钱包主页(适配新字段)| 0.5 天 |
| C7 | iOS / Android 双端发版 | 0.5 天 |

**总:5-6 天**(并行可缩到 3-4 天)。

## 5. 测试环境信息

- 服务器:anjuke.site(开发环境,无生产用户)
- 测试账号:`admin@anjuke`(uid=100002,密码:admin/888888 — 出厂值)
  - 用 admin@anjuke 登录后激活钱包 → 跑全流程
- 后端日志:`journalctl -u tantan-bs -f`(我会监控)
- 数据库:`tio_site_main` 表数据可读
  - `mysql tio_site_main -e "SELECT * FROM wx_wallet WHERE uid=100002"`
  - `mysql tio_site_main -e "SELECT * FROM wx_wallet_security_qa WHERE uid=100002"`
  - `mysql tio_site_main -e "SELECT * FROM wx_user_recharge_item WHERE uid=100002"`

## 6. 测试数据准备

为了让 codex 客户端能马上测试充值流,我会**手动 INSERT 一条测试支付方式**到 `wx_pay_method`:

```sql
INSERT INTO wx_pay_method (type, method_type, name, account, payee_name, qrcode_url, status, sort, remark)
VALUES (1, 'alipay', '测试支付宝', '13800000000', '测试财务', '/img/test-qr.jpg', 1, 10, '联调测试用');

INSERT INTO wx_pay_method (type, method_type, name, account, status, sort, remark)
VALUES (2, 'alipay', '测试支付宝(提现)', '13800000000', 1, 10, '联调测试用');
```

这样 codex 调 `/pay/recharge/methods` 能拿到 1 条返回。

## 7. 协作模式约定(再次明确)

- **客户端 codex 改 D:\tantan\flutter** Flutter 源码,自行编译 APK + ipa,部署到客户端(同之前模式)
- **后端我** 不动客户端代码,只动 bs-server / mg-server / mg-page / DB
- 双方走 comm-repo handoff 通信
- 对接问题写 handoff 推 comm-repo

## 8. Phase 4 联调时间安排

codex 客户端完成 C1-C2 后(钱包激活流可用),即可开始联调:

1. codex 在客户端激活钱包 → 后端验证 wx_wallet 行 + wx_wallet_security_qa 3 行 + user.paypwdflag=1
2. codex 跑充值申请 → 我从 mg-page 后台审核通过 → 客户端余额到账
3. codex 跑提现申请 → 我从 mg-page 后台审核通过 → 客户端 IM 收消息
4. codex 跑红包(沿用现有协议)→ 我看 wx_wallet_coin 余额变化

任何一步失败,立刻在 comm-repo 写 handoff,我会立即响应。

## 9. 给后端的反馈格式(若 codex 发现问题)

发 handoff `handoffs/2026-05-04-wallet-codex-issue-{xxx}.md`,内容:
- 接口:`/pay/xxx`
- 入参:...
- 期望:...
- 实际:...
- 客户端日志:...
- 服务器响应原文:...

我会立即响应。

## 10. 关联文档(全部已就绪)

- PRD 主文档:`2026-05-04-wallet-localization-prd.md`(完整决策 17 题盘问结果)
- 接口契约 v1:`2026-05-04-wallet-localization-api-contract.md`(43 接口完整字段定义 + 错误码)
- DDL:`2026-05-04-wallet-localization-ddl.sql`(数据库 schema 完整)
- 上一份给 codex 的 handoff:`2026-05-04-p0-15-frontend-followup-codex.md`(协作分工)

---

## 11. 后端 Phase 1-3 完成里程碑(给 codex 信心)

- ✅ 数据库 5 新表 + 5 ALTER + 38 权限 + 4 角色 + 8 密保 + 6 conf 配置
- ✅ 5upay-sdk-core 完整删除(不可回滚)
- ✅ bs-server 18 用户端接口部署上线
- ✅ mg-server 26 后台接口部署上线
- ✅ mg-page 7 个新页面(Recharge / Withhold / Wallet / Unmatched / PayMethod / Limits / SecurityQuestion)+ 全局 Polling 3 秒 / Web Audio API ding 声 / Element Notification / 顶栏 badge popover
- ✅ Java 8 编译全 14 模块 BUILD SUCCESS
- ✅ tantan-bs + tantan-mg systemd active
- ✅ Smoke 全 50+ 接口路由注册无误,鉴权拦截器正常

后端这边**不再有未完成的 Phase 3 工作**,可专心等 codex 客户端 + Phase 4 联调。

加油,有问题随时问。
