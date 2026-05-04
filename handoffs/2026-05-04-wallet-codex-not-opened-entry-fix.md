# 2026-05-04 Codex 我的页钱包未开户跳转修复

后端同学：用户反馈从“我的”页面点击钱包时，客户端只提示“用户未开户”，没有进入钱包激活流程。Codex 侧已确认并修复。

## 归因

- 后端对全新未激活钱包返回“用户未开户”是合理业务状态。
- 问题在前端：`WalletPage.open()` 把 `/pay/getWalletInfo` 的未开户失败当普通错误 toast 后 return，没有进入 `OpenWalletPage`。
- 本次不需要后端改接口。

## 修复

- 新增 `WalletErrorUtils.isNotActivatedResponse()`，兼容：
  - `code=4001`
  - msg 包含 `未开户`、`未开通`、`未激活`、`not activated`、`not opened`
- `WalletPage.open()`：未开户时提示“请先激活钱包”并打开 `OpenWalletPage`。
- 钱包页内部 `_ensureWalletActivated()` 同步修复。
- `RechargePage._ensureWalletActivated()` 同步修复。
- 红包支付弹窗钱包状态加载失败分支同步修复，避免显示原始“用户未开户”。

## 验证

- `dart format` 已执行。
- 定向 `flutter analyze --no-pub --no-fatal-infos` 无 error/warning，仅项目既有 deprecated info。
- `flutter build apk --release --no-pub` 在 `D:\tantan\flutter\tanchat-fromdev` 构建成功。
- APK 已安装到设备 `3YH9K24B29002144` 成功。
- 包更新时间：`2026-05-04 23:12:28`。
- 启动后前台 Activity：`site.anjuke.tanchat/com.tiocloud.fchat.MainActivity`。
- PID：`19580`。
- logcat 未见 `FATAL EXCEPTION`、`AndroidRuntime` 或 ANR。

## APK

- 路径：`D:\tantan\交付\初语-android-release-20260504-wallet-localization.apk`
- 大小：`99570667` 字节
- SHA256：`B0068552DF08DADDF7DE22B0FAC3D0372F8A63ABC0ECBAD8CB0A20E14843AD0E`

## 预期行为

现在从“我的 > 钱包”进入时，如果 `/pay/getWalletInfo` 返回未开户，客户端应进入钱包激活流程，而不是停留在“用户未开户”toast。
