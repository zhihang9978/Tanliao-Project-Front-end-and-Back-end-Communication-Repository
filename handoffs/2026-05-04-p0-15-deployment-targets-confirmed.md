# P0-15 部署目标 + 完整性校验流程(回应 codex 文档/部署诉求)

更新时间：2026-05-04 13:35 +08:00 (05:35 UTC)
对应 codex 反馈:文档需补 SSO 契约 + 确认服务器静态目录 + dist 上传完整性校验

## 1. ✅ 文档已补 — `docs/api-contract-log.md` 加 SSO ticket 正式契约

包含:
- §1 签发接口(URL / Cookie / Content-Type / 请求 / 响应 / 错误码 / 日志关键字)
- §2 兑换接口(同上)
- §3 ticket 数据结构(Redis key/value/TTL/one-shot)
- §4 完整业务流程(7 步,含浏览器视角)
- §5 兼容性(临时缓解层 / 旧接口下线计划)
- §6 临时缓解层(NDAPI-AUTOLOGIN-AUDIT + Referer 校验)
- §7 验收方式(实测命令 + 静态扫描结果 + 端到端待办)

## 2. ✅ 服务器静态目录确认(给 codex 准确上传位置)

经实测 anjuke.site nginx 配置 + 文件系统:

| codex 构建产物 | anjuke 部署目标 | 验证 |
|---|---|---|
| `D:\tantan\mg-page\page\dist\*` | **`/opt/tantan/runtime/admin/`** | nginx admin.anjuke.site server 块 `root /opt/tantan/runtime/admin;` |
| `D:\tantan\bs-page\page\tioim\*` | **`/opt/tantan/runtime/web/tioim/`** | bs-server `app-env.properties` `http.view.page=/opt/tantan/runtime/web` + `web.anjuke.site` proxy_pass 10160 |
| `D:\tantan\bs-page\page\tioims\*` | **`/opt/tantan/runtime/web/tioims/`** | 同上 |

**注意细节**:
- 三套目标都已存在(无需 mkdir,直接覆盖即可)
- mg-page 部署后**自动生效**(nginx serve 静态文件,无需重启 nginx 也无需重启服务)
- tioim/tioims 部署后**自动生效**(bs-server 内嵌 t-io HTTP 直接 serve `/opt/tantan/runtime/web/`,无需重启 bs-server)
- 但 bs-server **可能有 view 缓存**(看到 response 头 `tio_view_from_cache: 1`)→ 部署后**先清 view 缓存**,详见 §4

## 3. 上传方案选项(请用户/codex 决定)

### 方案 A — codex 直连 anjuke scp(推荐,最快)

需要 codex 端有 anjuke ssh 凭据(用户提供)。

```powershell
# 在 codex 端 PowerShell 或 WSL
scp -r D:\tantan\mg-page\page\dist\* root@anjuke.site:/opt/tantan/runtime/admin.new/
scp -r D:\tantan\bs-page\page\tioim\* root@anjuke.site:/opt/tantan/runtime/web/tioim.new/
scp -r D:\tantan\bs-page\page\tioims\* root@anjuke.site:/opt/tantan/runtime/web/tioims.new/

# 服务器侧后端切换(原子替换)
ssh root@anjuke.site '
  cd /opt/tantan/runtime
  mv admin admin.bak.$(date +%Y%m%d_%H%M%S) && mv admin.new admin
  cd web
  mv tioim tioim.bak.$(date +%Y%m%d_%H%M%S) && mv tioim.new tioim
  mv tioims tioims.bak.$(date +%Y%m%d_%H%M%S) && mv tioims.new tioims
'
```

### 方案 B — 用户中转(zip + scp / 网盘)

```powershell
# codex 端打包
powershell Compress-Archive D:\tantan\mg-page\page\dist mg-dist-20260504.zip
powershell Compress-Archive D:\tantan\bs-page\page\tioim tioim-20260504.zip
powershell Compress-Archive D:\tantan\bs-page\page\tioims tioims-20260504.zip
# → 用户传到 anjuke,后端解压 + 替换
```

### 方案 C — comm-repo Release(适合产物有版本管理需求时)

不推荐:dist 文件大(~MB 级),git 不适合存放二进制。

## 4. 部署后完整性校验 SOP

```bash
ssh root@anjuke.site '
echo "=== mg-page 文件清单 ==="
ls -la /opt/tantan/runtime/admin/ | head -10
echo
echo "=== mg-page 预期 bundle hash ==="
ls /opt/tantan/runtime/admin/static/js/app.*.js
md5sum /opt/tantan/runtime/admin/static/js/app.*.js | head -3
# codex 提供的预期: app.60aa3ae0.js

echo
echo "=== bs-page tioim 文件清单 ==="
ls -la /opt/tantan/runtime/web/tioim/ | head -10
ls /opt/tantan/runtime/web/tioim/static/js/app.*.js
md5sum /opt/tantan/runtime/web/tioim/static/js/app.*.js | head -3
# codex 提供的预期: app.535c8638.js

echo
echo "=== bs-page tioims 文件清单 ==="
ls -la /opt/tantan/runtime/web/tioims/ | head -10
ls /opt/tantan/runtime/web/tioims/static/js/app.*.js
md5sum /opt/tantan/runtime/web/tioims/static/js/app.*.js | head -3
# codex 提供的预期: app.8f7e94a9.js

echo
echo "=== 静态扫描(应 0 旧 ndapi/autologin 残留)==="
grep -rE "ndapi/autologin|ndapiAutologin|bs_tio_session" /opt/tantan/runtime/admin/ /opt/tantan/runtime/web/tioim/ /opt/tantan/runtime/web/tioims/ 2>/dev/null | head -5
# 应输出空(0 命中)

echo
echo "=== 触发 bs-server view 缓存失效 ==="
# 看 response 头是否还 hit view cache
curl -skI "https://web.anjuke.site/tioims/home?login_ticket=test" --max-time 5 | head -10
# 若 tio_view_from_cache: 1,可重启 tantan-bs 强制清:
# systemctl restart tantan-bs
'
```

## 5. 浏览器联调步骤(部署校验通过后)

1. 清浏览器 cache + cookies 域 anjuke.site(确保用新 JS bundle)
2. 登录 admin.anjuke.site/admin(管理员)
3. 点击 IM 入口或 goTioims 入口
4. 浏览器 DevTools Network 看:
   - 第 1 个 POST: `/tioadmin/im-login-ticket.admin_x` → 200 含 `data.ticket`
   - 跳转到 `https://web.anjuke.site/tioims/home?login_ticket=<ticket>`
   - URL bar 应**立即被前端 history.replaceState 清掉** `?login_ticket=...`
   - 第 2 个 POST: `/mytio/ndapi/exchangeLoginTicket.tio_x` body `ticket=...` → 200 + Set-Cookie
   - 第 3 个 GET: `/mytio/user/curr.tio_x` → 200 含登录用户信息
5. IM 界面正常显示用户信息 = 联调成功

## 6. 联调通过后的最终步骤(后端做)

```bash
ssh root@anjuke.site '
echo "=== 24h 监控统计 ==="
echo -n "签发数(SSO-TICKET-ISSUE):     "; journalctl -u tantan-mg --since "24 hours ago" --no-pager | grep -c "SSO-TICKET-ISSUE"
echo -n "兑换成功数(SSO-TICKET-EXCHANGE): "; journalctl -u tantan-bs --since "24 hours ago" --no-pager | grep -c "SSO-TICKET-EXCHANGE"
echo -n "兑换 miss 数:                  "; journalctl -u tantan-bs --since "24 hours ago" --no-pager | grep -c "SSO-TICKET-MISS"
echo -n "旧 /ndapi/autologin 调用数:    "; journalctl -u tantan-bs --since "24 hours ago" --no-pager | grep -c "NDAPI-AUTOLOGIN-AUDIT"
'

# 期望:ISSUE 数 ≈ EXCHANGE 数(允许少量 miss 来自浏览器 race),AUTOLOGIN-AUDIT = 0
```

旧接口下线(后端 1 行代码改动):
1. 在 NdApiController.autologin 第一行直接 return 410 Gone:
   ```java
   return Resps.json(request, Resp.fail("接口已下线,请使用 /ndapi/exchangeLoginTicket").code(410));
   ```
2. 删除临时缓解的 audit + Referer 校验代码(下线了无意义)
3. 编译 + 部署 + 监控 24h 无投诉

## 7. 当前完整状态

| 项 | 状态 |
|---|---|
| 后端 mg-server 签发 | ✅ 部署 + 路径对齐 codex |
| 后端 bs-server 兑换 | ✅ 部署 + 4 项基本测试通过 |
| 后端 access-url-role 规则 | ✅ mg `/im-login-ticket=*` + bs `/ndapi/exchangeLoginTicket=` |
| 临时缓解层 | ✅ /ndapi/autologin Referer 校验 + 审计 |
| 客户端 8 文件改造 | ✅ codex 完成 + 0 旧入口残留扫描 |
| 客户端 3 套 dist 构建 | ✅ codex 完成,等部署 |
| **dist 部署到 anjuke** | ⏳ **待 codex/用户决定上传方案** |
| 部署后完整性校验 | ⏳ 部署后立即跑 §4 SOP |
| 浏览器端到端联调 | ⏳ 校验通过后 §5 SOP |
| 旧 /ndapi/autologin 下线 | ⏳ 联调 + 24h 监控通过后 §6 |
| 文档(api-contract-log.md) | ✅ 已补 SSO 完整契约(本次) |

## 8. 关联

- API 契约: `docs/api-contract-log.md` § 2026-05-04 - P0-15 SSO ticket
- 后端实施: `handoffs/2026-05-04-p0-15-sso-ticket-backend-deployed.md`
- 客户端完成: `handoffs/2026-05-04-p0-15-sso-ticket-frontend-complete.md`
- 路径对齐: `handoffs/2026-05-04-p0-15-sso-ticket-backend-path-aligned.md`
