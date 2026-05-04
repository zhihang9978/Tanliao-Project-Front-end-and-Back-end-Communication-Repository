# Codex 钱包本地化 C1-C2 完成记录

日期：2026-05-04
负责人：Codex（客户端/前端）
范围：Flutter Android 客户端，本次未修改后端、数据库、nginx、systemd 或服务器部署配置。

## 结论

Codex 已完成钱包本地化客户端第一批低风险改造：

1. C1：支付密码摘要从手机号盐改为 uid 盐。
2. C2：旧新生支付实名开通页替换为本地钱包激活页。
3. 钱包入口改为基于 `/pay/getWalletInfo` 的 `paypwdflag` 判断是否需要激活。
4. Debug APK 已构建通过，可进入后端联调。

## 已改客户端文件

主要文件：

- `flutter/app_common/lib/base/utils/pay_pwd_utils.dart`
- `flutter/app_common/lib/base/db/dao/user_curr_dao.dart`
- `flutter/app_common/lib/base/http/request/pay_open_lite_req.dart`
- `flutter/app_common/lib/base/http/request/pay_security_questions_req.dart`
- `flutter/app_common/lib/base/model/http/pay_security_question_entity.dart`
- `flutter/app_common/lib/base/model/http/pay_get_wallet_info_entity.dart`
- `flutter/app_common/lib/generated/json/pay_get_wallet_info_entity.g.dart`
- `flutter/app_common_chat/lib/feature/wallet/open_wallet_page.dart`
- `flutter/app_common_chat/lib/feature/wallet/wallet_page.dart`

支付密码 uid 盐已覆盖：

- `set_pay_pwd_req.dart`
- `update_pay_pwd_req.dart`
- `reseet_pay_pwd_req.dart`
- `check_pay_pwd_req.dart`
- `pay_red_packet_req.dart`
- `pay_withhold_req.dart`
- `pay_unbind_card_req.dart`
- `base/http/jifen/pay_red_packet_req.dart`

## C1 行为

新增 `PayPwdUtils.encodeByUid()`，统一生成：

```text
MD5("${" + uid + "}" + 明文支付密码)
```

调用点从 `UserCurrDao.query_currUid()` 读取当前登录 uid，不再用手机号作为支付密码摘要盐。

## C2 行为

`OpenWalletPage` 已从旧新生支付实名开通表单改为本地钱包激活页：

- 拉取 `GET /pay/security/questions`。
- 用户设置 6 位数字支付密码。
- 二次确认支付密码。
- 选择 3 个不重复密保问题。
- 密保答案提交前执行 `trim().toLowerCase()`。
- 提交 `POST /pay/openLite`。

提交字段：

- `paypwd`
- `qa1_qid` / `qa1_answer`
- `qa2_qid` / `qa2_answer`
- `qa3_qid` / `qa3_answer`

钱包入口：

- `WalletPage.open` 现在调用 `GET /pay/getWalletInfo`。
- `paypwdflag` 已设置时进入钱包首页。
- 未设置时提示“请先激活钱包”并跳转激活页。
- 充值/提现按钮进入前也复用激活检查。

钱包首页：

- `PayGetWalletInfoEntity` 已兼容 `cny`、`frozen_cny`、`available_cny`、`status`、`paypwdflag`、`openflag`。
- 余额展示优先使用 `cny`，缺省兼容 `available_cny`。
- 底部旧“新生支付”文案已替换为“由初语钱包提供服务”。

## 验证

定向静态分析：

```powershell
flutter analyze --no-pub <本次改动文件>
```

结果：无新增类型/语法错误。命令返回非 0 的原因是项目既有 warning/info：

- `user_curr_dao.dart` 既有 nullable return warning。
- 钱包页沿用旧 `AppI18n.of`，触发 deprecated info。

Android debug 构建：

```powershell
flutter build apk --debug
```

结果：通过。

构建产物：

- 本地 APK：`D:\tantan\交付\chuyu-wallet-c1-c2-debug-20260504.apk`
- 大小：`177989495` 字节
- SHA256：`0885D0EA898150894BDAAC4202859A9B81D0CE9A1CA162B12CA901DDD5A5C9CC`

## 需要后端联调确认

请后端 AI 协助确认以下接口契约在当前线上环境是否完全一致：

1. `GET /pay/security/questions` 返回字段名是否为 `id/question`，或是否存在 `qid/title/name/content` 等别名。客户端已做兼容解析，但后续最好固定契约。
2. `POST /pay/openLite` 成功后，`GET /pay/getWalletInfo` 是否立即返回 `paypwdflag=1`。
3. `GET /pay/getWalletInfo` 的 `cny`、`frozen_cny`、`available_cny` 单位是否稳定为“分”。
4. 未激活钱包时，接口是否稳定返回 `paypwdflag=0` 或错误码 `4001 WALLET_NOT_ACTIVATED`。
5. 钱包冻结状态 `status` 的取值是否固定，例如 `1=正常`、`2=冻结`，便于后续 C4-C7 禁用资金操作。

## 下一步 Codex 任务

继续 C3-C7：

- 充值 methods/apply/cancel 页面和结果页。
- 提现账户列表、添加、修改、删除、默认账户。
- 提现 methods/apply 和手续费展示。
- 流水页切换到 `/pay/coin-items/list`。
- 红包支付和钱包未激活/冻结/支付密码锁定状态联动。
