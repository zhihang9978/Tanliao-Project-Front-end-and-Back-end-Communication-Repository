# P0-15 后续:前端 Console 报错修复 + 收尾(交给 codex)

更新时间：2026-05-04 15:00 +08:00 (07:00 UTC)
责任方：Codex(前端)
来源:用户决策"web 端归 codex 维护"

## 1. 背景:P0-15 联调主链路已通

后端处理完 4 个连环阻塞后(imsite 配置 / SPA fallback / mytio API 反代 / admin IM 数据初始化),用户实测 IM 入口已能完整跑通:

```
mg admin 点 IM
→ 跳 web.anjuke.site/tioims/home?login_ticket=<32B>      ✅
→ SPA 加载 200                                            ✅
→ /mytio/config/viewmodel.tio_x 200                       ✅
→ /mytio/ndapi/exchangeLoginTicket.tio_x → ok=true        ✅
→ Set-Cookie bs_tio_session                               ✅
→ /mytio/user/curr.tio_x 200(返回 admin@anjuke)          ✅
→ IM 主界面渲染                                            ✅
```

监控指标(2026-05-04 06:50 UTC):
- `SSO-TICKET-ISSUE`: 3
- `SSO-TICKET-EXCHANGE`: 3(100% 成功)
- `NDAPI-AUTOLOGIN-AUDIT`: 0(旧接口无人调,可下线)

## 2. 用户报告的剩余前端问题

### 2.1 IM 主界面加载后 Console 大量 TypeError ⚠️ 高优先级

用户截图描述"全是报错",从 reproduce 步骤看:

**reproduce**:
1. 浏览器进 `https://admin.anjuke.site/admin`,以 admin/<管理员密码> 登录
2. 顶栏点击 IM 入口
3. 跳转到 `https://web.anjuke.site/tioims/home?login_ticket=...`
4. URL 被前端清掉,变成 `https://web.anjuke.site/tioims/home`
5. IM 界面加载,**打开 DevTools Console**

**症状**:Console 红色错误一片,大致涉及:
- `Cannot read properties of undefined (reading 'chatmode')`
- `Cannot read properties of undefined (reading 'groupid')`
- 类似 `setCurrChat` / `getAllGroupList` 等访问 undefined 字段的 NPE

**疑似根因**(需 codex 验证):
- admin@anjuke 是新建的纯净 IM 账号(无好友、无群、无聊天历史)
- 前端组件假设至少有一个会话/好友/群,空数组进来直接 `.[0].chatmode` 等访问报 NPE
- 即原作者前端代码**缺空判断**

**给 codex 的处理思路**:
1. 用 admin/<密码> 登录 admin → 点 IM → 进 web.anjuke.site/tioims/home
2. F12 看 Console 完整 stack,定位首个 NPE 报错的 .vue 文件 + 行号
3. 加空判断:常见模式
   ```javascript
   // 不安全
   const chatmode = this.chatList[0].chatmode

   // 安全
   const chatmode = this.chatList?.[0]?.chatmode ?? 'p2p'
   ```
4. 涉及组件(根据用户截图描述,不一定全):
   - chatList / messageList 渲染前的空判断
   - currChat 初始化(可能要 fallback 到 null 而不是 undefined)
   - getAllGroupList 返回空数组的处理
5. 重新构建 + 部署到 `/opt/tantan/runtime/web/tioims/`(同之前模式)
6. 用 admin 账号 reproduce 验证 Console 干净

**注意**:这是**真用户首次使用**才会触发的 bug — 平时演示账号都有数据,这类 NPE 易被掩盖。修了也要保证有数据的账号不回归。

### 2.2 res.anjuke.site/img/tio.jpg 404(中优先级)

nginx access.log 显示:
```
GET /img/tio.jpg HTTP/2.0  404 185
referer: https://web.anjuke.site/
UA: Edge 147 (Windows)
```

referer 是 web.anjuke.site/(根路径,可能是默认 H5 页或 IM 首屏某处)

**确认事项**:
- 这个 `/img/tio.jpg` 路径是 codex 在哪里引用的?
- 是 logo / 占位图 / 默认头像?
- 应该改成现有素材路径,还是把图片放到 `/opt/tantan/runtime/web/img/tio.jpg`?

**建议**:codex 全局 grep `tio.jpg` 找出引用位置,要么改路径,要么补图。

### 2.3 性能优化阶段 1 遗留 debug print(低优先级)

之前 codex 性能优化时留了 console.log debug 输出。上线前应清理:

```bash
grep -RIn "console.log\|debugger\|TODO" D:\tantan\bs-page\page\tioim-src\src\
```

清理掉所有调试打印(保留必要的 console.error / console.warn)。

### 2.4 mg-page 同样检查(顺便)

mg-page 也是 codex 维护的,同样处理:
- 全局 grep console.log / debugger
- 检查 admin 后台是否有 NPE

## 3. 协作模式确认

用户决定的分工:

| 责任 | 谁负责 |
|---|---|
| **bs-page / mg-page 源码** | codex(D:\tantan 本地) |
| **前端编译 + dist 部署** | codex(继续之前模式) |
| **服务器 nginx / properties / DB / 后端服务** | 后端(我) |
| **handoff 通信** | 双方都用 comm-repo |

**重要约束**:
- codex 改源码后**直接部署 dist 到 /opt/tantan/runtime/web/{tioim,tioims} 或 /opt/tantan/runtime/admin**(同之前模式)
- 部署前**通知后端**,后端可以提前确认服务状态、备份目录
- **不要改服务器上的 nginx/properties/DB**(那是后端的领域)
- 部署完做完整性校验(md5 + 文件数 + 关键 bundle 名)

## 4. 服务器辅助信息(给 codex 部署时用)

```
SSH:    ssh root@anjuke.site (codex 应已有访问)
runtime:
  /opt/tantan/runtime/web/tioims/    ← bs-page tioims SPA(本次修复入口)
  /opt/tantan/runtime/web/tioim/     ← bs-page tioim SPA(老 H5)
  /opt/tantan/runtime/admin/         ← mg-page 管理后台
  /opt/tantan/runtime/web/img/       ← static 图片资源(若放 tio.jpg 在这)

bundle 当前 hash(部署前比对):
  admin    /static/js/app.9a2b497e.js  (codex 上次部署)
  tioims   /static/js/app.21928bf4.js  (基线,codex 未改 tioims)
  tioim    /static/js/app.230056cf.js  (基线,codex 未改 tioim)
```

## 5. 测试账号信息

```
admin@anjuke IM 账号(本次修复创建)
  user.id      = 100002
  user.tiono   = '1'(关联 mg admin 的 unioncode)
  user.loginname = 'admin@anjuke'
  user.phone   = '19900000001'(测试号)
  user.phonebindflag = 1(已绑定,免弹窗)
  user.realnameflag  = 1(已实名,免弹窗)
  user.status  = 1(正常)
```

**关于 admin@anjuke 应不应该走 C 端实名制**:
当前是把 admin@anjuke 当 C 端正常账号处理(走全部实名校验)。如果 codex 觉得 admin SSO 进的 IM 应当**绕过实名/绑手机**(B 端运营场景),需要前端加 admin 标识判断,跳过那两步引导;或后端给 admin 用户加特殊 status 让前端识别。

**建议**:先不改这个,等用户反馈是否需要 admin 免绑手机。

## 6. 后端这边并行进行的事

不影响 codex,通报一下:

- [ ] 监控 `SSO-TICKET-EXCHANGE` 24h 确认稳定(目前 3 次 100%)
- [ ] 24h 后 `/ndapi/autologin` 改 410 Gone(代码修改 + 重新部署 bs-server)
- [ ] 删除 P0-15 临时缓解层代码(audit log + Referer 校验,仅过渡用)
- [ ] 后端 properties 全文 grep `https://` 查剩余错配域名(类似 im.server 的问题)

## 7. 完成后请回 handoff

codex 修完前端后,回一份 handoff:

`handoffs/2026-05-04-p0-15-frontend-bugs-fixed-codex.md`

内容包含:
- 修了哪些 .vue 文件(具体行号 + 改动)
- 新 bundle hash
- 部署完整性校验结果
- 用 admin@anjuke 账号 reproduce Console 是否清白

后端验收后,P0-15 整体可以宣告闭环。

## 关联

- mytio API 反代修复: `handoffs/2026-05-04-p0-15-mytio-api-proxy-fixed.md`
- SPA fallback 修复: `handoffs/2026-05-04-p0-15-spa-fallback-fixed.md`
- imsite 配置修复: `handoffs/2026-05-04-p0-15-imsite-config-fixed.md`
- codex IM 入口启用: `handoffs/2026-05-04-p0-15-im-entry-enabled-codex.md`
