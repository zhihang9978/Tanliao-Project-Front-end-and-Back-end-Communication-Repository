# 2026-05-04 Codex 钱包本地化复审修复

后端同学：用户要求复审后判断问题归属并继续修复。Codex 侧确认本次 3 个 finding 均为客户端问题，不需要后端改接口。本次只修改 Flutter 客户端和本地文档，未修改后端、服务器、数据库、nginx 或 systemd。

## 修复内容

1. 提现可用余额

- 文件：`flutter/app_common_chat/lib/feature/wallet/withdraw/withdraw_page.dart`
- 问题：提现页使用 `cny` 作为可提现余额，冻结金额会被计入可提现额度。
- 修复：初始化余额和“全部提现”均改为 `available_cny ?? cny`。

2. 红包支付钱包状态门禁

- 文件：`flutter/app_common_chat/lib/feature/wallet/send_red_paper/srp_packet_dialog.dart`
- 问题：钱包信息未加载时 `_canUseWallet()` 返回 true，用户快速输入 6 位支付密码可能绕过客户端激活/冻结校验。
- 修复：新增 `walletInfoLoaded`、`walletInfoLoadFailed` 状态；钱包信息未加载、加载失败或为空时禁止密码输入和提交。

3. 旧兼容选择弹窗

- 文件：`flutter/app_common_chat/lib/feature/wallet/add_bank_card/choose_bank_card_dialog.dart`
- 问题：旧兼容桩不再显示 Dialog，但仍直接触发 `onClickPacket`，未来误接旧调用方时可能让旧回调 `Navigator.pop` 弹掉当前页面。
- 修复：兼容桩只提示“当前版本仅支持钱包余额支付”，不再触发旧回调。

## 验证

- `dart format` 已执行。
- 定向 `flutter analyze --no-pub --no-fatal-infos` 无 error/warning，仅项目既有 `AppI18n.of` deprecated info。
- `flutter build apk --release --no-pub` 在 `D:\tantan\flutter\tanchat-fromdev` 构建成功。
- 旧接口可达性扫描：业务 UI 不再调用旧接口，只剩未引用旧 request 类定义。

## APK

- 路径：`D:\tantan\交付\初语-android-release-20260504-wallet-localization.apk`
- 大小：`99570667` 字节
- SHA256：`324B325BE8B9F8D48612DE2721647EBAAB31287A83E595B5692FF429882D73FF`

## ADB

`adb devices` 当前无在线设备，本轮无法安装真机。设备接入后需要安装上述 APK 做钱包激活、充值、提现账户、提现、流水和红包支付联调。
