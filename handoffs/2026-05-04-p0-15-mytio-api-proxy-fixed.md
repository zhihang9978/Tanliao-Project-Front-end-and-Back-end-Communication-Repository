# P0-15 联调阻塞 3:web.anjuke.site 缺 /mytio/ API 反代,已修

更新时间：2026-05-04 14:50 +08:00 (06:50 UTC)
责任方：后端 AI

## 第三个根因(SPA 加载后又遇到)

修完 SPA fallback 后,`/tioims/home` 200 正常加载,但浏览器 Console 报错:

```
Failed to load resource: /mytio/config/viewmodel.tio_x → 404
Uncaught TypeError: Cannot read properties of null (reading 'tioim_title')
```

## 根因

bs-page tioims SPA 启动时调 `/mytio/config/viewmodel.tio_x` 拿配置(含 `tioim_title` 等)。

axios baseURL 默认 = 当前域(web.anjuke.site,**相对路径**),但:
- `web.anjuke.site/mytio/*` → nginx 反代到 bs-server **view 10160**(只服务静态/模板,**没有 API**)
- `api.anjuke.site/mytio/*` → nginx 反代到 bs-server **6060(API)**(✅ 这里有)

SPA 在 web 域用相对路径调 API → 走错后端 → 404。

## 修复

`/etc/nginx/sites-available/tantan.conf` 的 `web.anjuke.site` server 块,在 `location /` 之前(SPA fallback 之后)加 API 反代:

```nginx
# P0-15 fix(2026-05-04): /mytio/ API 反代到 bs-server 6060
location /mytio/ {
    proxy_pass http://127.0.0.1:6060;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto https;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 300s;
}
```

## 实测验证

```
/mytio/config/viewmodel.tio_x:           200 ✅(SPA 启动配置)
/mytio/user/curr.tio_x:                   200 ✅(用户信息)
/mytio/ndapi/exchangeLoginTicket.tio_x:   {"code":1010,"msg":"ticket 为空","ok":false} ✅(SSO 兑换)
/tioims/home:                             200 ✅(SPA 路径仍 fallback 正常)
/tioims/static/js/app.21928bf4.js:        200 ✅(静态文件仍正常)
```

`nginx -t` + `nginx -s reload` 通过,无回归。

## 备份

```
/etc/nginx/sites-available/tantan.conf.bak.mytio-api.20260504_064556
```

## 现在 web.anjuke.site nginx 完整 location 路由表

```
/                          → bs-server view 10160(默认,模板 / 旧路径)
/preview/                  → fileview 8012
/tioim/                    → 静态文件 + SPA fallback /tioim/index.html
/tioims/                   → 静态文件 + SPA fallback /tioims/index.html
/myres/                    → 静态文件
/mytio/                    → bs-server API 6060(SPA 内部 API 调用)← 本次新增
```

## P0-15 联调阻塞总览(到目前为止)

| # | 阻塞 | 根因 | 修复 |
|---|---|---|---|
| 1 | UI 无 IM 按钮 | Header.vue HTML 注释 | codex 反注释 + 重新构建 ✅ |
| 2 | 跳到错误域 404 | mg-server `im.server=api.anjuke.site` | 后端改 `web.anjuke.site` ✅ |
| 3 | SPA 路径 404 | nginx 无 try_files fallback | 后端加 `location /tioims/ try_files` ✅ |
| 4 | viewmodel API 404 | web.anjuke.site 缺 /mytio/ 反代 | 后端加 `location /mytio/ → 6060` ✅ |

每个都是几分钟修复,但需要实际浏览器测试才暴露。这是典型的**前后端分离 + SPA history mode + 多域名分工**项目部署常见的连环坑。

## 给用户的下一步

请刷新 admin 后台 + 点 IM 按钮再次测试。本次应该 **完整跑通**:

1. 点 IM → 跳 `web.anjuke.site/tioims/home?login_ticket=...`(2 修复)
2. SPA 加载 200(3 修复)
3. viewmodel 200(本次 4 修复)
4. URL 清掉 → 兑换 ticket → Set-Cookie → IM 登录成功

如果还有问题,Console 截图发我,继续排查。

## 关联

- imsite 修复: `handoffs/2026-05-04-p0-15-imsite-config-fixed.md`
- SPA fallback 修复: `handoffs/2026-05-04-p0-15-spa-fallback-fixed.md`
