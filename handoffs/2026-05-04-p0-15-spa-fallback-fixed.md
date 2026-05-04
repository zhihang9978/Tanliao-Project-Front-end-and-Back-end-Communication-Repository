# P0-15 联调阻塞 2:Vue Router history mode 路径 404 — nginx fallback 已加

更新时间：2026-05-04 14:45 +08:00 (06:45 UTC)
责任方：后端 AI

## 第二个根因(im.server 修完后又遇到)

`im.server` 修完(api → web)后,用户再次点击 IM 按钮,跳转到正确域名:
```
https://web.anjuke.site/tioims/home?login_ticket=ad4129e30c59c493827fc6fa75b10327
```

**但浏览器显示 404**:
```
404
Failed to load resource: /favicon.ico (404)
Failed to load resource: /tioims/home?login_ticket=ad4129...:1 (404)
```

## 根因

`/tioims/home` 是 Vue Router **history mode** 路径,**不是真实静态文件**。bs-server view 接到请求后找不到对应文件 → 返回 404。

正确做法:**SPA 应 fallback 到 `/tioims/index.html`** 让 Vue Router 内部接管路由。

```
$ ls /opt/tantan/runtime/web/tioims/
favicon.ico   index.html   static/   ← 没有 home / login 文件,这些是 SPA 路由
```

## 修复(已部署)

修改 `/etc/nginx/sites-available/tantan.conf` 的 `web.anjuke.site` server 块,在 `location /` 之前插入 3 个静态目录的 location:

```nginx
# P0-15 fix(2026-05-04): SPA Vue Router history mode fallback
location /tioim/ {
    root /opt/tantan/runtime/web;
    try_files $uri $uri/ /tioim/index.html;
}
location /tioims/ {
    root /opt/tantan/runtime/web;
    try_files $uri $uri/ /tioims/index.html;
}
location /myres/ {
    root /opt/tantan/runtime/web;
    try_files $uri =404;
}
```

效果:
- `/tioims/home` → 找不到 home 文件 → fallback `/tioims/index.html` → 200(Vue Router 接管路由)
- `/tioims/static/js/app.*.js` → 找到静态文件 → 200(直接 serve)
- `/tioim/home` → fallback 到 `/tioim/index.html` → 200
- `/myres/common.js` → 静态文件 200,无 fallback(legacy 文件,无 SPA 路由)

## 实测验证

```
/tioims/home:                           200 ✅
/tioims/login:                          200 ✅
/tioim/home:                            200 ✅
/tioims/static/js/app.21928bf4.js:      200 ✅
/tioim/static/js/app.230056cf.js:       200 ✅
/tioims/home?login_ticket=fake123:      200 ✅(URL 含 query 也正常)
```

`nginx -t` + `nginx -s reload` 通过,无回归。

## 副作用与额外好处

**性能**:tioim/tioims/myres 静态文件现在 nginx 直接 serve(原来反代到 bs-server view)→ 更高效。
**bs-server 减负**:不需要处理 SPA 静态请求。

唯一注意:这要求 `/opt/tantan/runtime/web/tioims/index.html` 等文件**必须**存在。当前已部署,没问题。后续如有新 SPA 入口也要在 nginx 同样配置。

## 备份

```
/etc/nginx/sites-available/tantan.conf.bak.spa-fallback.20260504_064029
```

回滚:
```bash
ssh root@anjuke.site '
cp /etc/nginx/sites-available/tantan.conf.bak.spa-fallback.20260504_064029 /etc/nginx/sites-available/tantan.conf
nginx -s reload
'
```

## 给用户的下一步

**请用户**:
1. 刷新 admin 后台(Ctrl+Shift+R 硬刷)
2. 点击右上角 **IM** 按钮
3. 期望:
   - 跳转 `https://web.anjuke.site/tioims/home?login_ticket=<32B hex>`
   - **页面正常加载**(不再 404)
   - URL bar 立即被前端 `history.replaceState` 清掉(变成干净的 `/tioims/home`)
   - 自动调用 `/mytio/ndapi/exchangeLoginTicket.tio_x` 兑换
   - IM 界面显示当前管理员的 IM 视图

## 后端待跟进

跑完联调后 监控:
- `SSO-TICKET-ISSUE` ↑(签发)
- `SSO-TICKET-EXCHANGE` ↑(兑换)— 应等于 ISSUE
- `NDAPI-AUTOLOGIN-AUDIT` 仍 0

`SSO-TICKET-EXCHANGE` 增加到 ≥ 1 即代表 P0-15 完整闭环验证通过 → 24h 后下线旧 `/ndapi/autologin`。

## P0-15 联调阻塞总结(给学习参考)

| # | 阻塞 | 根因 | 修复 |
|---|---|---|---|
| 1 | UI 没 IM 按钮 | Header.vue HTML 注释 | codex 反注释 + 重新构建部署 |
| 2 | 跳到错误域 404 | mg-server `im.server=https://api.anjuke.site` | 后端改为 `https://web.anjuke.site` + 重启 |
| 3 | SPA 路径 404 | nginx 无 try_files fallback | 后端加 location /tioims/ try_files |

每一个都是 30 秒到 5 分钟的修复,但发现需要服务端配合 + 实际浏览器测试。**这反映了"代码对 + 配置对 + nginx 对"三者必须同时正确**。

## 关联

- imsite 错配修复: `handoffs/2026-05-04-p0-15-imsite-config-fixed.md`
- codex IM 入口启用: `handoffs/2026-05-04-p0-15-im-entry-enabled-codex.md`
