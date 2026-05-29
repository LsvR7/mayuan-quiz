# 马原背题

这是一个纯前端的马克思主义基本原理刷题网页，题库来自 `原理2024-2025-2年题库更新` 目录下的 Word 文件。

## 本地预览

可以直接双击打开 `index.html`。如果浏览器限制本地文件访问，建议在当前目录启动一个静态服务：

```powershell
node -e "const http=require('http'),fs=require('fs'),path=require('path');const root=process.cwd();const types={'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8'};http.createServer((req,res)=>{let file=decodeURIComponent(new URL(req.url,'http://localhost').pathname);if(file==='/')file='/index.html';const full=path.join(root,file);fs.readFile(full,(err,data)=>{if(err){res.writeHead(404);res.end('Not found');return}res.writeHead(200,{'Content-Type':types[path.extname(full)]||'application/octet-stream'});res.end(data)})}).listen(8765,'127.0.0.1')"
```

然后在电脑浏览器打开：

```text
http://127.0.0.1:8765/
```

## 手机使用

发布到 GitHub Pages 后，用手机浏览器打开固定网址即可答题，也可以把网址加入浏览器收藏。

答题进度、错题本、筛选条件都保存在当前手机浏览器的本地存储中。换手机、换浏览器、清除网站数据或清除浏览器缓存后，这些记录可能会丢失。

## 发布到 GitHub Pages

1. 在当前目录初始化 Git 仓库并提交文件。
2. 在 GitHub 创建一个公开仓库，建议仓库名为 `mayuan-quiz`。
3. 将本地仓库推送到 GitHub 的 `main` 分支。
4. 打开仓库的 `Settings` -> `Pages`。
5. 将 Source 设为 `Deploy from a branch`。
6. 将 Branch 设为 `main`，Folder 设为 `/root`，保存。
7. 等待 Pages 构建完成后，访问类似下面的固定网址：

```text
https://<你的GitHub用户名>.github.io/mayuan-quiz/
```

## 功能

- 背题模式：直接显示题目、选项和正确答案。
- 做题模式：单选题和判断题点击选项后直接判断对错；多选题选完后点击提交，并保存作答记录。
- 错题重练：答错自动加入错题组，连续答对 2 次后移出错题组。
- 章节和题型筛选：支持按章节、单选、多选、判断题筛选。
- 进度保存：当前位置、筛选条件、作答历史和错题记录保存在当前浏览器本地。

## 更新题库

替换或修改 Word 文件后，在当前目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\extract_questions.ps1
```

脚本会重新生成 `questions.js`，并把抽取统计写入 `extraction-report.json`。
