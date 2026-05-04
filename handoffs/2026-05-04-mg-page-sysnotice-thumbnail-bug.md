# mg-page bug:系统消息缩略图上传无效(JSON.parse 错误)

更新时间：2026-05-04 15:30 +08:00 (07:30 UTC)
责任方：Codex(前端 mg-page)
来源:用户反馈"管理后台的系统消息发送添加不了缩略图"
优先级:中(影响管理后台运营,但不阻塞 IM 主功能)

## 1. 现象

用户操作:管理后台 → IM → 系统消息(SysNotice)→ 新建/编辑 → 选择缩略图文件
预期:上传后预览图显示
实际:**点击选择文件后 UI 无任何反应**(图还是默认占位 coverBg.png)

## 2. 根因(确认是源码 bug)

文件:`mg-page/page/src/_admin/views/im/SysNotice.vue`
方法:`uploadImg(event)`,行号 509-536

错误代码(509-536):
```javascript
uploadImg(event){
    let _this=this,
        file = event.currentTarget.files[0],
        reader = new FileReader();
    reader.readAsDataURL(file);
    reader.onload = function (e) {
        let blob=dataURLtoBlob(this.result);
        let fd=new FormData();
        fd.append("uploadFile",blob,file.name);
        fd.append("filetype",6);
        upload(fd).then(res=>{
            if(res.ok){
              try {
                console.log(res)
                console.log(JSON.parse(res.data))      // ← BUG 1
               let {url} =  JSON.parse(res.data)        // ← BUG 2
               _this.dialog.form.img=resUrl(url);
               _this.img=url
              } catch (error) {                          // ← 空 catch,静默吞错
                
              }
            }else{
                msgTips(res);
            }
        })
        event.target.value="";
    }
},
```

### 错在哪

- `fetchUpload` 内部 axios 已经把 `response.data` 反序列化成 JS 对象 → `res = {ok:true, code:0, data:{id, url, ...img 字段}, msg:""}`
- `res.data` **是对象,不是字符串**
- `JSON.parse(对象)` 触发 `String(obj)` = `"[object Object]"` → 然后 parse 报 SyntaxError
- 抛进空 catch → 静默失败 → `dialog.form.img` 没赋值 → UI 不更新

### 后端返回(确认)

`mg-server/.../UploadController.java:50-69`(`POST /tioadmin/upload.admin_x`):
```java
Img img = ImgUtils.processImg(Const.UPLOAD_DIR.CASE_IMG, uploadFile);
...
return Resp.ok(img);   // ← Img 对象,不是字符串
```

`Resp` 序列化结构:`{ok: boolean, code: int, data: <object>, msg: string}`

axios 默认拿到 application/json 响应已 parse → res.data 直接是 Img 对象。

### 同项目内的正确写法(可参考)

| 文件:行 | 写法 |
|---|---|
| `mg-page/.../views/im/AppManage.vue:328` | `let data=res.data; _this.dialog.form.fileurl=data.url;` |
| `mg-page/.../views/official/CaseManage.vue:448` | `_this.caseItemInfo.casecover=resUrl(res.data.url);` |
| `mg-page/.../views/official/RecruitCompany.vue:232` | `_this.dialog.form.cmplogo=res.data.url;` |
| `mg-page/.../views/im/SysNotice.vue:551`(同文件富文本插图) | `url=resUrl(res.data.url)` ← **同文件其他地方都是对的,就 519 错了** |

确认是原作者只在这一处写错了。

## 3. 修复方案

文件:`D:\tantan\mg-page\page\src\_admin\views\im\SysNotice.vue`
行号:509-536

替换为:

```javascript
uploadImg(event){
    let _this=this,
        file = event.currentTarget.files[0],
        reader = new FileReader();
    reader.readAsDataURL(file);
    reader.onload = function (e) {
        let blob=dataURLtoBlob(this.result);
        let fd=new FormData();
        fd.append("uploadFile",blob,file.name);
        fd.append("filetype",6);
        upload(fd).then(res=>{
            if(res.ok){
                _this.dialog.form.img = resUrl(res.data.url);
                _this.img = res.data.url;
            }else{
                msgTips(res);
            }
        })
        event.target.value="";
    }
},
```

改动要点:
1. 删 try/catch
2. 删 2 行 console.log
3. 删 `JSON.parse(res.data)`
4. 直接 `res.data.url`
5. 失败走 msgTips(原代码 else 分支已有)

## 4. 验证步骤

1. codex 在 D:\tantan\mg-page 改完后:
   ```powershell
   cd D:\tantan\mg-page\page
   vue-cli-service build
   ```
2. 部署 dist 到 `/opt/tantan/runtime/admin/`(同之前 SOP)
3. 浏览器硬刷 admin 后台
4. 进系统消息 → 新建 → 点缩略图选择文件
5. 期望:上传完图片立即显示在缩略图位置
6. 保存后从列表打开,缩略图正常显示

## 5. 关联待修(顺手)

同文件 `quillUploadImg`(537-561 行)是对的,无需改;不要改坏。

mg-page 全局 grep 是否还有类似 `JSON.parse(res.data)` 误用:
```powershell
findstr /S /N "JSON.parse(res.data)" D:\tantan\mg-page\page\src\
```

如果还有其他地方,一并修。

## 6. 给后端的反馈点

无需后端改动。后端 `/tioadmin/upload.admin_x` 行为正确(返回 Img 对象)。

后端会在 codex 部署完后,从服务器看 nginx access.log 是否有 `/tioadmin/upload.admin_x` 200,以及 img 表是否有新记录。

## 关联

- 协作分工 handoff: `handoffs/2026-05-04-p0-15-frontend-followup-codex.md`
