# mg-page bug 修复完成:系统消息缩略图上传 JSON.parse 错误(后端处理)

更新时间：2026-05-04 16:20 +08:00 (08:20 UTC)
责任方：后端 AI(已自行处理,不涉及 codex)
状态：✅ 已部署上线,等用户验证

## 1. 现象

用户反馈:管理后台 → IM → 系统消息(SysNotice)→ 选择缩略图文件 → **UI 无任何反应**(图还是默认占位)。

## 2. 根因

文件:`mg-page/page/src/_admin/views/im/SysNotice.vue`,方法 `uploadImg`(行 509-536)

```javascript
upload(fd).then(res=>{
    if(res.ok){
      try {
        console.log(res)
        console.log(JSON.parse(res.data))     // ← BUG
       let {url} =  JSON.parse(res.data)       // ← BUG
       _this.dialog.form.img=resUrl(url);
       _this.img=url
      } catch (error) {                         // ← 空 catch 静默吞错
        
      }
    }else{
        msgTips(res);
    }
})
```

- axios 已经把 `response.data` JSON 反序列化成对象 → `res.data` 是 `Img` 对象,不是字符串
- `JSON.parse(对象)` → `JSON.parse("[object Object]")` → SyntaxError
- 抛进**空 catch** → 静默失败 → `dialog.form.img` 没赋值 → UI 不更新

后端 `mg-server/.../UploadController.java:50-69` 行为正常(返回 `Resp.ok(img)`),无需改动。

同项目其他 vue(AppManage / CaseManage / RecruitCompany)以及同文件 `quillUploadImg`(548 行)都是直接 `res.data.url`,只有 `uploadImg` 这一处错。**原作者代码 bug**。

## 3. 修复

### 改动 1 — `SysNotice.vue:519-535` 简化为

```javascript
upload(fd).then(res=>{
    if(res.ok){
        _this.dialog.form.img = resUrl(res.data.url);
        _this.img = res.data.url;
    }else{
        msgTips(res);
    }
})
```

### 改动 2 — `Header.vue:27-29` 同步 codex 之前的 IM 按钮启用(防止 build 后回退)

```html
<span class="operitem recent-col" @click="goIm">
    IM
</span>
```

## 4. 构建 + 部署(全在服务器执行,不涉及客户端 codex)

服务器 node 18.19.1 + npm 9.2.0:

```bash
cd /opt/tantan/source/mg-page/page
npm install                         # 873 包
npm run build                       # ~30s,vue-cli-service build
# DONE  Build complete.
```

新 bundle:`app.49fcc79b.js`(621122B / 198 文件 / dist 总 8479707B)
旧 bundle(codex 部署):`app.9a2b497e.js`(621589B / 198 文件 / 8273604B)

## 5. 部署原子切换

```bash
TS=20260504_081607
cp -r /opt/tantan/source/mg-page/page/dist /opt/tantan/runtime/admin.new
mv /opt/tantan/runtime/admin       /opt/tantan/runtime/admin.bak.rotated.$TS
mv /opt/tantan/runtime/admin.new   /opt/tantan/runtime/admin
```

## 6. 备份

```
/opt/tantan/runtime/admin.bak.before-sysnotice-fix.20260504_081252  (codex 部署版完整副本)
/opt/tantan/runtime/admin.bak.rotated.20260504_081607               (原 admin/ 重命名,等价 codex 部署版)
/opt/tantan/source/mg-page/page/src/_admin/views/im/SysNotice.vue.bak.20260504_081252
/opt/tantan/source/mg-page/page/src/_admin/components/Header.vue.bak.20260504_081252
```

## 7. 验证(已通过)

```
HTTP smoke:
  /admin/index.html              200, 2590B
  /static/js/app.49fcc79b.js     200, 621122B  ← 新 bundle
  /static/css/app.8d791f62.css   200, 1985148B
  POST /tioadmin/upload.admin_x  → {"code":1001,"msg":"您尚未登录或登录超时","ok":false}  ✅(端点在线)

bundle 内容校验:
  grep 'goIm'                       app.49fcc79b.js  → 1 hit  ✅(IM 按钮含)
  grep 'JSON.parse(res.data)'       静态 JS 全无 hit  ✅(错误模式清零)
  grep 'sysmsg/filetype'            app.49fcc79b.js + chunk-0d7697de.c3da8894.js → SysNotice 编入
```

## 8. 待用户测试

请用户:
1. 浏览器硬刷 admin 后台(Ctrl+Shift+R)
2. 进入 IM → 系统消息 → 新建/编辑
3. 点击缩略图选择文件
4. **期望**:上传完图片立即显示缩略图(不再静默失败)
5. 保存后从列表打开,缩略图正常显示
6. (副带验证)顶栏 IM 按钮仍可点击 → 正常进 IM(IM 按钮启用未回退)

## 9. 协作分工备忘(本次教训)

- ❌ 不该把 mg-page bug 推给 codex(`2026-05-04-mg-page-sysnotice-thumbnail-bug.md` 已撤销 → WITHDRAWN)
- ✅ codex 只管**客户端**(Flutter / bs-page 用户端 SPA)
- ✅ 管理后台(mg-page + mg-server)、服务器、bs-server 都归后端
- 服务器有完整 mg-page 源码 + node + npm,后端能完全独立构建 + 部署

## 10. 回滚预案(若用户验证发现回归)

```bash
ssh root@anjuke.site '
TS=$(date +%Y%m%d_%H%M%S)
mv /opt/tantan/runtime/admin /opt/tantan/runtime/admin.failed.$TS
cp -r /opt/tantan/runtime/admin.bak.rotated.20260504_081607 /opt/tantan/runtime/admin
'
```

无需 nginx reload,nginx 直接 serve 静态文件。

## 关联

- 撤销 handoff: `2026-05-04-mg-page-sysnotice-thumbnail-bug-WITHDRAWN.md`
- codex 客户端待办(不涉及本 bug): `2026-05-04-p0-15-frontend-followup-codex.md`
