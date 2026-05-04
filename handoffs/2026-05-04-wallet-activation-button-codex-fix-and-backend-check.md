# 钱包激活按钮无反馈：Codex 修复与后端待排查

时间：2026-05-04 23:35

## 结论

用户反馈安卓客户端“激活钱包”页填完资料后点击按钮无反应。Codex 已完成客户端第一层修复：按钮现在能触发提交，有 loading、有失败反馈、有超时和错误码兜底。

修复后真机复测，客户端点击已进入提交链路，但 `POST /pay/openLite` 仍返回失败。前端提交字段与本仓库既有契约一致，因此剩余问题需要后端继续排查接口业务错误和响应体。

## Codex 已改客户端

### 1. `OpenWalletPage` 提交链路

文件：

- `D:\tantan\flutter\app_common_chat\lib\feature\wallet\open_wallet_page.dart`

改动：

- 激活按钮改为显式 `ElevatedButton`。
- 点击前 `FocusScope.unfocus()` 收起键盘。
- 提交中显示 `LoadingDialog.show(context, text: '正在激活钱包...')`。
- 请求完成后恢复按钮状态。
- 失败统一走 `WalletErrorUtils.messageForCode(resp.code, resp.msg)`。
- 空响应/异常不再静默。

### 2. `/pay/openLite` 请求

文件：

- `D:\tantan\flutter\app_common\lib\base\http\request\pay_open_lite_req.dart`

改动：

- `sendTimeout = 15s`
- `receiveTimeout = 15s`
- `errorReturnJsonCache = false`

原因：钱包激活是强业务状态变更 POST，不能在失败时读取陈旧 JsonCache。

### 3. 钱包错误提示

文件：

- `D:\tantan\flutter\app_common\lib\base\utils\wallet_error_utils.dart`

改动：

- 新增 `4023 SECURITY_QA_NOT_SET` 映射：“请选择 3 个不重复的密保问题”。
- 未知错误码显示：“请求失败（错误码 xxx），请稍后再试”。

## 真机复测记录

设备：

- `3YH9K24B29002144`

APK：

- `D:\tantan\交付\初语-android-release-20260504-wallet-activation-fix.apk`
- 大小：`99570667`
- SHA256：`2C373D6949013CDEB8C65D8947BBB8E034B78E56D3BE44A5EADCA9ACDB0BD8F4`
- 安装结果：`Success`
- 安装后包信息：`versionName=10.0.0`, `versionCode=241101012`, `lastUpdateTime=2026-05-04 23:33:38`

验证：

- `flutter analyze --no-pub --no-fatal-infos` 定向检查通过。
- `flutter build apk --release --no-pub` 通过。
- 启动后 `MainActivity` 正常前台，无 `FATAL EXCEPTION` / `AndroidRuntime` / ANR。
- 从“我的 > 钱包”可进入激活页。
- 填写 6 位支付密码、确认密码、3 个密保问题和答案后，点击按钮已触发提交，不再是无反馈。

## 后端待排查

客户端提交契约与本仓库 `2026-05-04-wallet-localization-api-contract.md` 一致：

```text
POST /pay/openLite
paypwd
qa1_qid
qa1_answer
qa2_qid
qa2_answer
qa3_qid
qa3_answer
```

真机复测使用了 3 个不同的密保问题，仍返回失败。请后端确认：

1. `/pay/openLite` 失败响应是否稳定返回 `code` 和 `msg`。
2. 如果返回 `4023 SECURITY_QA_NOT_SET`，请核对服务端实际收到的 `qa1_qid/qa2_qid/qa3_qid` 是否为空、重复或字段名未绑定。
3. 如果当前响应是 `{ok:false}` 且没有 `code/msg`，请补齐错误码和中文提示，否则客户端只能显示兜底失败。
4. 成功后请确认 `GET /pay/getWalletInfo` 是否立即返回 `paypwdflag=1`。

## 职责边界

Codex 本轮只修改 Flutter 客户端，没有修改后端、数据库、nginx、systemd 或服务器数据。剩余 `/pay/openLite` 服务端失败原因交给后端 AI 排查。
