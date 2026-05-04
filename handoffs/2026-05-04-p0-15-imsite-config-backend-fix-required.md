# P0-15 IM 入口跳转 404：后端配置修复请求

时间：2026-05-04 14:45 +08:00
提交方：Codex
归属判断：后端 / 运行配置

## 现象

用户点击管理后台顶栏 `IM` 后，浏览器跳转到了：

```text
https://api.anjuke.site/tioims/home?login_ticket=<redacted>
```

页面返回 404。

正确目标应该是：

```text
https://web.anjuke.site/tioims/home?login_ticket=<ticket>
```

## 前端代码定位

当前管理后台 IM 入口代码在：

```text
D:\tantan\mg-page\page\src\_admin\components\Header.vue
```

关键逻辑：

```js
let imsite = this.sysparams.imsite
let res = await mgheader.imLoginTicket({audience:'tioim-small'})
if(res && res.ok && res.data && res.data.ticket){
  let baseUrl = imsite.replace(/\/$/,'')
  window.location.href = baseUrl + '/tioims/home?login_ticket=' + encodeURIComponent(res.data.ticket)
}
```

`sysparams` 来源：

```text
GET /tioadmin/sys/params.admin_x
```

在 `D:\tantan\mg-page\page\src\main.js` 中加载后写入 store：

```js
let sysparams=await sysParams();
store.commit('setSysParams', sysparams.data);
```

因此前端不会自行把 `web.anjuke.site` 改成 `api.anjuke.site`，当前 404 的直接原因是运行配置里的 `imsite` 值错误。

## 后端需要处理

请后端将管理后台系统参数里的 IM 站点地址修正为：

```text
imsite = https://web.anjuke.site
```

同时建议检查以下位置是否存在同类错误配置：

- `/tioadmin/sys/params.admin_x` 返回的 `imsite`
- 数据库/配置中心里的 `imsite` 参数
- 管理后台“参数配置”里与 IM/Web 站点相关的配置项
- 任何把 `imsite` 误设置成 `https://api.anjuke.site` 的初始化 SQL 或默认配置

## Codex 当前动作

Codex 已确认这不是前端静态文件缺失，也不是 IM 按钮启用问题。

Codex 一度准备在前端增加兜底归一化，但用户指出后端问题必须由后端处理。该前端兜底改动已撤回，本地源码恢复为原来的配置驱动逻辑，未继续部署新的前端兜底包。

## 验证方式

后端修复配置后，用真实管理员重新登录或刷新管理后台，再点击顶栏 `IM`：

1. 浏览器应该跳到 `https://web.anjuke.site/tioims/home?login_ticket=<ticket>`。
2. 不应该再跳到 `https://api.anjuke.site/tioims/home?...`。
3. `web.anjuke.site/tioims/home` 应返回 Web IM 静态页面。
4. 后端继续验证 `SSO-TICKET-ISSUE` / `SSO-TICKET-EXCHANGE` 闭环。
