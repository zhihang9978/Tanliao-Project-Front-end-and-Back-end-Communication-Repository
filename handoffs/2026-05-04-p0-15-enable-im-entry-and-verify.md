# P0-15 联调阻塞点:IM 入口按钮 UI 未启用,需要 Codex 处理

更新时间：2026-05-04 14:30 +08:00 (06:30 UTC)
责任方：Codex(前端)
优先级：高(P0-15 联调最后一步)

## 当前状态

✅ 后端服务端就绪(签发 + 兑换接口部署)
✅ Codex 客户端 dist 已部署 anjuke 服务器
✅ 后端 view cache 已清,新 bundle 200 可达
✅ P0-10 cookie 加固首次实证生效(Set-Cookie Secure+HttpOnly+SameSite)
⏳ **唯一卡点:管理员在 admin 后台看不到 IM 入口按钮**

## 用户实测发现

用户已成功登录 admin.anjuke.site/admin(看到用户列表页),**点击了管理后台所有界面**,但:

- 后端监控 `SSO-TICKET-ISSUE` 仍 = 0
- 即:**没有任何路径触发 `goIm()` 调用 `imLoginTicket` 签发**

原因:`mg-page/page/src/_admin/components/Header.vue` 中 IM 按钮 HTML 是**被注释**的(原作者历史遗留):

```html
<!-- <span :class="['operitem recent-col',dropdown.type=='recent'&&dropdown.show?'active':'']" @click="goIm">
    im
</span> -->
```

Codex 上一轮把 `goIm()` 函数改成调 `imLoginTicket` 了,但**按钮 UI 没有启用**,管理员在 UI 上点不到。

## 请 Codex 做的事(2 个任务)

### 任务 A:启用 IM 入口按钮(必做)

`mg-page/page/src/_admin/components/Header.vue` 反注释 IM 按钮:

```html
<!-- 改前(注释掉) -->
<!-- <span :class="['operitem recent-col',dropdown.type=='recent'&&dropdown.show?'active':'']" @click="goIm">
    im
</span> -->

<!-- 改后(启用) -->
<span :class="['operitem recent-col',dropdown.type=='recent'&&dropdown.show?'active':'']" @click="goIm">
    IM
</span>
```

或者如果有更合适的 UI 位置(比如 dropdown 菜单 / 顶栏图标),Codex 视实际 UX 决定。重点是**管理员能看到并点击**。

然后:
1. 重新构建 `mg-page/page/dist`
2. 部署到 `/opt/tantan/runtime/admin/`(沿用之前的 scp + atomic mv 流程)
3. 服务器侧无需重启 nginx(静态文件直接生效,新 bundle hash 自动失效旧缓存)

### 任务 B:浏览器端到端联调验证

部署 IM 按钮后:

1. 清浏览器 cookies(域 anjuke.site)+ cache
2. 登录 https://admin.anjuke.site/admin
3. F12 打开 DevTools,切到 Network
4. 点击新启用的 **IM 入口按钮**
5. 应观察到 4 个网络请求依次发生:
   ```
   ① POST /tioadmin/im-login-ticket.admin_x
      Status: 200
      Response: {"code":0,"ok":true,"data":{"ticket":"<32B hex>","expiresIn":60}}

   ② 浏览器跳转 https://web.anjuke.site/tioims/home?login_ticket=<ticket>
      → 立即 history.replaceState 清 URL(URL bar 应变成干净的 /tioims/home)

   ③ POST /mytio/ndapi/exchangeLoginTicket.tio_x
      Body: ticket=<hex>
      Status: 200
      Response Headers 含: Set-Cookie: tio_session=...; Domain=.anjuke.site; Secure; HttpOnly; SameSite=Lax

   ④ GET /mytio/user/curr.tio_x
      Status: 200
      Response: {当前 IM 登录用户信息}
   ```
6. tioims 界面正常显示当前管理员的 IM 视图 = ✅ 联调成功

## 临时验证方式(可选,Codex 可先跑确认服务端逻辑)

如果想**先确认服务端 SSO 链路工作正常**(不依赖 UI 按钮),Codex 在 admin 后台 Console 跑:

```javascript
fetch('/tioadmin/im-login-ticket.admin_x', {
  method: 'POST',
  headers: {'Content-Type': 'application/json'},
  body: JSON.stringify({audience: 'tioim-small'}),
  credentials: 'include'
}).then(r => r.json()).then(d => {
  console.log('SSO ticket 签发:', d);
  if (d.ok) {
    setTimeout(() => location.href = 'https://web.anjuke.site/tioims/home?login_ticket=' + d.data.ticket, 1500);
  }
});
```

**期望结果**:
- Console 打印 `{code:0, ok:true, data:{ticket:"...", expiresIn:60}}`
- 1.5 秒后跳转 → tioims 自动登录 IM 界面

跑成功后说明**服务端链路 100% 正常**,只剩 UI 按钮问题。

## 后端待跟进

Codex 完成上述两项后:

1. 后端立即看监控:`SSO-TICKET-ISSUE = SSO-TICKET-EXCHANGE` 数(预期 ≥ 1)
2. 24h 监控旧 `NDAPI-AUTOLOGIN-AUDIT == 0`
3. 后端下线旧 `/ndapi/autologin`(改返 410 Gone)+ 删临时缓解代码

## 备份(Codex 部署前)

Codex 上传 mg-page dist 时建议保留旧版本备份:

```bash
ssh root@anjuke.site '
cd /opt/tantan/runtime
mv admin admin.bak.before-im-entry.$(date +%Y%m%d_%H%M%S)
mkdir admin
'
# 然后 scp 新 dist 到 admin/
```

或沿用之前的 `.new + atomic mv` 流程。

## 总结

P0-15 安全闭环服务端 + 客户端代码层面**已全部完成**。最后只差**一个按钮 UI 启用**,这是产品可用性问题(管理员需要能在 UI 看到 IM 入口)+ 联调验证。

Codex 完成后,后端在 30 分钟内可关闭整个 P0-15 安全工单。
