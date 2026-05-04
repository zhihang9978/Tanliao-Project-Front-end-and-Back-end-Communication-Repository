# P0-15 联调失败根因 + 后端配置修复(imsite 错配)

更新时间：2026-05-04 14:40 +08:00 (06:40 UTC)
责任方：后端 AI

## 联调失败现象

用户点击 admin 后台 IM 按钮后:
- mg-server 监控:`SSO-TICKET-ISSUE = 2`(签发成功 2 次)
- bs-server 监控:`SSO-TICKET-EXCHANGE = 0`(0 次兑换)
- 用户实际 URL:`https://api.anjuke.site/tioims/home?login_ticket=da1d8e120290196d2551eb132afbacfd` → **404**

## 根因

mg-server 配置 `im.server` 错指向 API 域而非前端 SPA 域:

```
# /opt/tantan/runtime/mg/config/app-env.properties
im.server=https://api.anjuke.site    # ❌ 错:这是 REST API 域
```

**结果**:
- `Const.IM_SERVER = "https://api.anjuke.site"`
- `SysController.sysparams` 返回给 mg-page 的 `imsite = "https://api.anjuke.site"`
- mg-page Header.vue `goIm()`:`location.href = imsite + "/tioims/home?login_ticket=..."` = `https://api.anjuke.site/tioims/home?login_ticket=...`
- nginx `api.anjuke.site` 反代到 bs-server **6060(REST API)**,没有 tioims 静态文件 → **404**

正确 SPA 部署位置在 `https://web.anjuke.site`(nginx 反代到 bs-server view 10160 + 文件 `/opt/tantan/runtime/web/tioims/`)。

## 域名分工

| 域名 | nginx 反代 | 用途 |
|---|---|---|
| `api.anjuke.site` | bs-server 6060 | REST API(/mytio/*)+ 兑换接口 `/mytio/ndapi/exchangeLoginTicket.tio_x` |
| `web.anjuke.site` | bs-server 10160(view) | **前端 SPA(tioim/tioims)静态文件 + Vue Router** |
| `admin.anjuke.site` | nginx static + bs/mg-server | 管理后台 SPA + `/tioadmin/*` 反代到 mg-server 6061 |

## 修复

```bash
ssh root@anjuke.site '
TS=$(date +%Y%m%d_%H%M%S)
PROP=/opt/tantan/runtime/mg/config/app-env.properties
cp $PROP $PROP.bak.imsite.$TS
sed -i "s|^im\.server=.*|im.server=https://web.anjuke.site|" $PROP
systemctl restart tantan-mg
'
```

执行结果:
- 改前:`im.server=https://api.anjuke.site` ❌
- 改后:`im.server=https://web.anjuke.site` ✅
- tantan-mg 重启:active,2 端口监听(6061/10161),0 异常
- 备份:`app-env.properties.bak.imsite.20260504_063659`

## 给 codex 的下一步

**用户需要**(本会话内):
1. 刷新 admin 后台(因为 mg-server 重启了,sysparams 会重新拉取)
2. 重新点击 IM 入口按钮
3. 期望跳转到 `https://web.anjuke.site/tioims/home?login_ticket=...`
4. URL bar 立即被前端 history.replaceState 清掉
5. 自动兑换 ticket → IM 登录成功

**Codex 不需要改代码**,只需要等用户做联调。

## 同时记录:这是配置错误,不是代码错误

- mg-page bundle 默认值已经是 `https://web.anjuke.site`(fallback)— codex 代码正确
- 但运行时 sysparams API 返回的 `imsite` 覆盖了默认值 → 用了错误域名
- 修复点在**后端 properties**,不在前端代码

## 这反映出 N-07 类似问题

类似的"出厂配置错指向 anjuke 但子域名错配"已经记录过(turnserver.url),本次又遇到 `im.server`。**Stage 0 收官前应做完整 properties 出厂值审查**:

- 看每个 `*.properties` 中 `https://` / `http://` URL 是否都指向正确域
- 已知错配:
  - `im.server`(已修)
  - `turnserver.url`(已修 N-07)
  - `mg.menu.sysn.site`(看到是 `https://admin.anjuke.site` ✅ 正确)

后续:跑一遍 properties 全 grep `https://` 看是否还有错配。

## 备份 + 回滚

```bash
# 紧急回滚(不太可能需要)
ssh root@anjuke.site '
cp /opt/tantan/runtime/mg/config/app-env.properties.bak.imsite.20260504_063659 /opt/tantan/runtime/mg/config/app-env.properties
systemctl restart tantan-mg
'
```

## 关联

- codex IM 入口启用: `handoffs/2026-05-04-p0-15-im-entry-enabled-codex.md`
- 后端联调阻塞 handoff: `handoffs/2026-05-04-p0-15-enable-im-entry-and-verify.md`
- 后端 dist 部署确认: `handoffs/2026-05-04-p0-15-backend-post-deploy-verified.md`
