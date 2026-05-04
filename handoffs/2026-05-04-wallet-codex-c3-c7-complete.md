# 2026-05-04 Codex 钱包本地化客户端 C3-C7 完成

后端同学：Codex 侧已完成本轮钱包本地化客户端 C3-C7 收口。本次只修改 Flutter 客户端和本地文档，未修改后端、服务器、数据库、nginx 或 systemd。

## 完成范围

- C3 充值本地化：客户端使用 `GET /pay/recharge/methods`、`POST /pay/recharge/apply`、`POST /pay/recharge/cancel`。
- C4-C5 提现账户：客户端使用 `/pay/payout-accounts` 系列接口完成列表、新增、编辑、删除、设默认；编辑提交 3 个密保答案。
- C6 钱包首页和流水：钱包首页展示 `cny`、`available_cny`、`frozen_cny`、`status`；流水使用 `GET /pay/coin-items/list`。
- C7 提现：提现页使用 `GET /pay/withhold/methods`、`GET /pay/payout-accounts`、`POST /pay/withhold/apply`；支付密码仍使用 uid 盐摘要。
- 红包联动：发红包支付弹窗只保留本地钱包余额支付，并校验钱包激活、冻结、支付密码状态。

## 旧接口断链

客户端可达 UI 已不再调用以下旧接口：

- `/pay/bankcardlist`
- `/pay/recharge`
- `/pay/rechargeQuery`
- `/pay/withhold`
- `/pay/withholdQuery`

处理方式：

- `RechargeResultPage` 已从总路由表移除。
- 旧 `RechargeDialog`、`RechargeResultPage`、`ChooseBankCardDialog`、`SRPBankCardDialog` 改为兼容桩，不再触发旧接口。
- 源码中仍保留未引用的旧 request 类定义，后续可以单独清理死代码；当前业务 UI 扫描只剩 request 类定义本身。

## 生成模型

- `pay_get_wallet_info_entity.g.dart` 已同步当前钱包字段。
- `pay_get_wallet_items_entity.g.dart` 已同步当前流水字段。
- 新钱包接口 request 仍优先使用手写 `fromJson`，不依赖全局 `JsonConvert` 注册。

## APK

- 路径：`D:\tantan\交付\初语-android-release-20260504-wallet-localization.apk`
- 大小：`99570667` 字节
- SHA256：`1894F48F2060E2BEE4ACECAD3803353B936DD56225A0DC17A318BFE0D04B1DE0`

## 验证

- `dart format` 已执行。
- 定向 `flutter analyze --no-pub --no-fatal-infos` 无 error/warning；剩余为项目既有 `AppI18n.of` deprecated info。
- `flutter build apk --release --no-pub` 在 `D:\tantan\flutter\tanchat-fromdev` 构建成功。
- `adb devices` 当前无在线设备，因此本轮未安装真机。设备接入后需要安装上面的 APK 做钱包激活、充值、提现账户、提现、流水和红包支付联调。

## 后端联调关注点

- `/pay/recharge/apply` 返回的精确打款金额、二维码、收款账号、过期时间需与客户端展示字段保持稳定。
- `/pay/payout-accounts/update` 当前客户端提交 `qa1_answer/qa2_answer/qa3_answer`，并兼容提交 `old_qa1_answer/old_qa2_answer/old_qa3_answer`。
- `/pay/getWalletInfo` 需稳定返回 `paypwdflag`、`status`、`cny`、`available_cny`、`frozen_cny`。
- 后端若确认旧 request 类也需要从客户端源码删除，请单独开死代码清理任务；本轮已保证可达 UI 不再调用旧接口。
