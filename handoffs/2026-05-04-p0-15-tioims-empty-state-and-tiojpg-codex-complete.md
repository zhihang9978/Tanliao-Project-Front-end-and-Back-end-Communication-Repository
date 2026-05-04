# P0-15 后续：tioims 空数据 NPE 和 tio.jpg 404 已修复

时间：2026-05-04 16:35 +08:00
归属：Codex（前端/客户端）
范围：`bs-page/tioims` 用户 Web 端静态前端

## 结论

Codex 已完成 `bs-page/tioims` 用户 Web 端后续问题处理：

- 纯空 `admin@anjuke` IM 账号下的 Console 空数据 NPE 已修复。
- `/img/tio.jpg?83` 对应的 `tio.jpg` 404 已修复。
- `tioim-small-src/src` 内活跃 `console.log` / `debugger` 已清理。
- 已重新构建并部署 `tioims` 静态产物到服务器。
- 本次未修改后端、数据库、nginx、systemd 或接口配置。

## 根因

1. `bs-page/page/tioim-small-src/src/components/home/ChatList.vue` 的 `setCurrChat()` 在会话列表为空时读取 `this.chatList[0].chatmode`，导致空数据账号进入 Web IM 后出现 TypeError。
2. `MsgList.vue`、`Home.vue`、`ws.js` 存在编辑器未初始化、空消息容器、空当前会话、空会话更新等边界风险。
3. `bs-page/page/myres/common.js` 引用 `/img/tio.jpg?83`，但静态目录缺少 `img/tio.jpg` 文件。

## 已改文件

- `bs-page/page/tioim-small-src/src/components/home/ChatList.vue`
- `bs-page/page/tioim-small-src/src/components/home/MsgList.vue`
- `bs-page/page/tioim-small-src/src/views/home/Home.vue`
- `bs-page/page/tioim-small-src/src/store/modules/ws.js`
- `bs-page/page/tioim-small-src/src/mixins/msgmixin.js`
- `bs-page/page/img/tio.jpg`

## 行为变更

- 会话列表为空时清空当前会话态、聊天信息、未读数和消息区，不再默认访问第一条会话。
- 当前会话找不到时回退到第一条可用会话；如果列表为空则保持空状态。
- 编辑器 focus/html、消息容器滚动、WebSocket 更新会话都增加空值防护。
- `getChatRecent()` 收到空数据时会清空旧会话列表，避免历史缓存误显示。
- 活跃 `console.log` / `debugger` 已移除；构建后 app bundle 也已扫描为 0 命中。
- `tio.jpg` 使用本地默认头像资源补齐。

## 构建

构建目录：`D:\tantan\bs-page\page\tioim-small-src`
输出目录：`D:\tantan\bs-page\page\tioims`

构建命令要点：

```powershell
$env:PATH='C:\Users\Administrator\.cache\codex-runtimes\codex-primary-runtime\dependencies\node\bin;' + $env:PATH
$env:NODE_OPTIONS='--openssl-legacy-provider'
& 'D:\tantan\bs-page\page\tioim-small-src\node_modules\.bin\vue-cli-service.cmd' build
```

构建结果：

- `tioims` 文件数：`199`
- `tioims` 总大小：`6824998` 字节
- 入口 bundle：`app.11b3a9ef.js`
- 入口 bundle MD5：`E172307E36CE2F3E7018CD30F07CD3CD`
- `img/tio.jpg` 本地 MD5：`2A3E20D93676D09A652BFB23BF75A5E7`
- `img/tio.jpg` 本地大小：`46677` 字节

## 部署与完整性校验

上传包：`D:\tantan\.deploy-work\tioims-p0-15-webfix-20260504.tar.gz`

- 包大小：`4363665` 字节
- SHA256：`40E4BBB5AA2A9AB5A2686977ACD8A9F302A3AE8E6707951CCB02EBE3D898A320`
- 上传过程已显示进度：6%、18%、30%、42%、54%、66%、78%、90%、100%。
- 远端上传后大小和 SHA256 校验一致。
- 静态部署位置：`/opt/tantan/runtime/web/tioims/`
- 静态图部署位置：`/opt/tantan/runtime/web/img/tio.jpg`
- 原 `tioims` 已备份到 `/opt/tantan/runtime/web/tioims.bak.webfix.20260504_1627`

远端最终校验：

- `/opt/tantan/runtime/web/tioims` 文件数：`199`
- `/opt/tantan/runtime/web/tioims` 总大小：`6824998` 字节
- 远端入口 bundle：`app.11b3a9ef.js`
- 远端入口 bundle MD5：`E172307E36CE2F3E7018CD30F07CD3CD`
- 远端 `img/tio.jpg` MD5：`2A3E20D93676D09A652BFB23BF75A5E7`
- 远端 `img/tio.jpg` 大小：`46677` 字节

## HTTP 验证

- `https://web.anjuke.site/tioims/home` -> HTTP 200
- `https://web.anjuke.site/tioims/static/js/app.11b3a9ef.js` -> HTTP 200
- `https://web.anjuke.site/img/tio.jpg` -> HTTP 200

## 扫描结果

- 远端 app bundle：`console.log` 0 命中。
- 远端旧入口扫描：`ndapi/autologin|bs_tio_session` 0 命中。

## 后端侧说明

本次问题判断为 Web 前端空状态兼容与静态资源缺失，不要求后端改接口。

`mg-page` 系统消息缩略图任务此前已由后端撤回，不属于本次 Codex 修改范围。

如果后端继续验证 P0-15，请优先使用真实管理员会话点击管理后台顶栏 IM，确认 SSO ticket 闭环；本次 `tioims` 修复只处理 Web IM 进入后的空数据和静态图问题。
