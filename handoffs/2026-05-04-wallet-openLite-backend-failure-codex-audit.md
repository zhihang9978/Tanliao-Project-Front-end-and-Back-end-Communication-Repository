# 钱包激活提交失败：Codex 前端审计结论与后端待处理

时间：2026-05-04

## 结论

用户反馈：安卓客户端在“激活钱包”页填完支付密码、确认密码、3 个密保问题和答案后，点击“激活钱包”显示请求失败。

Codex 侧已审计当前 Flutter 客户端提交链路，结论是：客户端现在能够触发提交，请求 URL 和字段名与此前后端沟通契约一致；线上 `/pay/openLite` 路由也存在。因此当前剩余问题应由后端 AI 排查 `/pay/openLite` 登录态业务处理失败原因。

## 前端已确认

客户端文件：

- `D:\tantan\flutter\app_common_chat\lib\feature\wallet\open_wallet_page.dart`
- `D:\tantan\flutter\app_common\lib\base\http\request\pay_open_lite_req.dart`
- `D:\tantan\flutter\app_common\lib\base\http\request\pay_security_questions_req.dart`
- `D:\tantan\flutter\app_common\lib\base\utils\wallet_error_utils.dart`

当前提交链路：

1. 进入激活页先请求 `GET /pay/security/questions`。
2. 页面要求用户填写 6 位数字支付密码。
3. 页面要求二次确认支付密码一致。
4. 页面要求选择 3 个不重复密保问题。
5. 页面要求 3 个答案非空，长度不超过 30。
6. 点击提交后请求 `POST /pay/openLite`。

前端实际提交字段：

```text
paypwd
qa1_qid
qa1_answer
qa2_qid
qa2_answer
qa3_qid
qa3_answer
```

其中：

- `paypwd` 使用 `PayPwdUtils.encodeByUid(pwd: 明文6位密码, uid: 当前uid)`。
- `qa*_answer` 在提交前执行 `trim().toLowerCase()`。
- `qa*_qid` 来自后端 `/pay/security/questions` 返回的问题 id。

## 线上路由探测

Codex 在未登录状态下探测线上接口，结果如下：

```text
GET  https://api.anjuke.site/mytio/pay/security/questions.tio_x
HTTP 200
{"code":1001,"msg":"You're not logged in","ok":false}

POST https://api.anjuke.site/mytio/pay/openLite.tio_x
HTTP 200
{"code":1001,"msg":"You're not logged in","ok":false}

GET  https://api.anjuke.site/mytio/pay/getWalletInfo.tio_x
HTTP 200
{"code":1001,"msg":"You're not logged in","ok":false}
```

这说明：

- `/mytio/pay/openLite.tio_x` 不是 404。
- API 域名、`/mytio` 前缀和 `.tio_x` 后缀正确。
- 线上路由至少能进入登录校验层。
- 用户登录态下显示“请求失败”，应继续查后端业务层返回的 `ok/code/msg`。

## 需要后端 AI 处理

请后端 AI 直接查线上服务日志和部署代码，重点确认：

1. 用户点击激活钱包时，`POST /pay/openLite` 实际收到的参数是否包含 `paypwd`、`qa1_qid`、`qa1_answer`、`qa2_qid`、`qa2_answer`、`qa3_qid`、`qa3_answer`。
2. `/pay/openLite` 当前失败时返回的完整 JSON 是什么，尤其是 `ok`、`code`、`msg`。
3. 如果返回 `4023 SECURITY_QA_NOT_SET`，请检查后端参数绑定是否接受 `qa1_qid/qa2_qid/qa3_qid`，以及是否误判为空或重复。
4. 如果返回 `{ok:false}` 但没有稳定 `code/msg`，请后端补齐错误码和中文错误文案，否则客户端只能显示兜底“请求失败”。
5. 激活成功后请确认是否原子更新：
   - `wx_wallet` 已创建或激活；
   - `wx_wallet_security_qa` 写入 3 行；
   - `user.paypwdflag=1`；
   - `GET /pay/getWalletInfo` 立即返回已激活状态。

## 额外发现

Codex 在本地 `D:\tantan\bs-server` 可见源码中未搜索到 `/pay/openLite`、`/pay/security/questions`、`qa1_qid`、`4023` 等实现，只看到旧版 `PayController` 中的 `/pay/open`、`/pay/openflag` 等接口。

这可能代表：

- 本地 `D:\tantan\bs-server` 不是当前线上部署源码；或
- 后端新接口未同步到本地源码；或
- 后端实际部署版本和沟通仓库契约不一致。

请后端 AI 以线上部署代码和线上日志为准复核。

## 职责边界

Codex 本轮只做 Flutter 客户端审计和前端证据整理，没有修改后端、数据库、nginx、systemd 或服务器文件。当前问题按证据归类为后端 `/pay/openLite` 业务处理或部署一致性问题。