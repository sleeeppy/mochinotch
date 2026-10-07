<p align="center">
  <a href="../README.md">한국어</a> · <a href="README.en.md">English</a> · <a href="README.ja.md">日本語</a> · <b>中文</b>
</p>

<p align="center">
  <img src="images/icon.png" width="128" alt="Mochinotch 图标">
</p>

<h3 align="center">Mochinotch</h3>

<p align="center">
  把 MacBook 的刘海变成柔软的灵动岛。<br>
  充电、通知和 AI 任务完成，都直接显示在刘海上。
</p>

---

### 通知堆在刘海旁边

消息、Slack、KakaoTalk 等应用来通知时，应用图标会从刘海右边弹出来，并像 Dock 一样带上角标。
再来一个应用的通知，就再多一格。

<p align="center">
  <img src="images/notice.gif" width="500" alt="通知到来时，刘海右边出现图标和角标">
</p>
<br/>

### 插上充电器

闪电和电池百分比出现在刘海两侧，然后收起来。

<p align="center">
  <img src="images/charge.gif" width="500" alt="插上充电器时，刘海显示正在充电 82%">
</p>
<br/>

### AI 任务结束时

AI 代理（Claude Code、Cursor、Codex、Kiro）做完任务后，刘海会向两侧展开来告诉你。<br/>
光沿着边缘走一圈，屏幕边缘也会轻轻染上那个应用的颜色。

<p align="center">
  <img src="images/complete.gif" width="720" alt="任务结束时屏幕边缘发光">
</p>

<br/>

### 代理在等你回答时

Claude 或 Codex 弹出批准窗口或问题卡片时，刘海上会打开橙色的**确认**。在你作答之前它一直展开，屏幕边缘不会发光。

<p align="center">
  <img src="images/confirm.gif" width="720" alt="Cursor 提问时刘海打开橙色确认，展开后能看到问题">
</p>

<br/>

### 鼠标移上去，列表会展开

到目前为止的通知、任务完成和充电记录按时间从新到旧堆在一起。点某一项就会跳到那个应用。

<p align="center">
  <img src="images/expand.gif" width="560" alt="鼠标移到刘海上时列表展开">
</p>

<br/>

### 把文件暂时放在刘海

把文件拖向刘海，刘海会往下展开一块放置区。放到右边的**暂存**上，照片下沿会从刘海下面露出来。左右可以在设置里对调。<br/>

<p align="center">
  <img src="images/shelf.gif" width="720" alt="两张照片放到暂存后从刘海下露出，鼠标移上去会散开，再把一张拖进窗口">
</p>

<br/>

### 把文件放到刘海上即可 AirDrop

放到左边的 **AirDrop** 上，刘海会先收起，然后打开 AirDrop 窗口，让你选择设备。

<p align="center">
  <img src="images/airdrop.gif" width="720" alt="把照片拖向刘海会打开放置区，放到左边的 AirDrop 后刘海收起">
</p>

</br>

### 在应用里更新

有新版本时，这个列表里会出现**新版本**。点那一行，就会就地接收、替换并重新打开。**v0.3.5 及以上**可以在应用内更新。

<p align="center">
  <img src="images/update.gif" width="720" alt="点列表里的新版本后能看到下载和安装，然后刘海收起">
</p>

<br/>

---

### 设置

点齿轮不会另开窗口。刘海会再大一点，设置就出现在里面。

<p align="center">
  <img src="images/settings.png" width="500" alt="在刘海里面打开的设置">
</p>

- **登录时打开**：打开 Mac 后自动启动。
- **开场**：启动时的招呼可以在 `麻糬` 和 `拉长` 之间选。选完后把鼠标移开刘海，会马上播放一次。
- **屏幕边缘光效**：关掉后，AI 任务结束时只有刘海边缘发光，屏幕保持原样。
- **权限 · AI 连接**：重新打开第一次启动时的权限设置，并显示还有几项没打开。
- **使用方法**：在最下面版本号旁边。点开会打开这一页。
- **暂存放在左边**：打开后暂存在左、AirDrop 在右。关掉则相反。
- **语言**：在韩语、日语、英语、中文里选择。刘海上的文字会马上切换。

---

### 权限

第一次打开时，招呼结束后刘海会展开**初始权限设置**。你在系统设置之间来回时，它不会收起。

<p align="center">
  <img src="images/setup.png" width="500" alt="刘海里展开的初始权限设置，三项权限和 AI 代理连接都已打开">
</p>

- 每一项点**允许**，会打开 macOS 提示，或 **系统设置 → 隐私与安全性** 里对应的列表。打开的项目会自动变成绿色对勾。
- 如果 **完全磁盘访问权限** 列表里没有 Mochinotch，点下面的 +，从“应用程序”里添加 `Mochinotch`。
- **屏幕录制**要重新打开应用后才生效。点初始权限设置下面的**重新打开**即可。
- **连接 AI 代理**里的**连接**会一次性写入 hook。详见下面的 AI 代理连接。
- 点**以后**会关闭，并且不会再自动出现。随时可以从设置 → **权限 · AI 连接**重新打开。

<br/>

| 权限 | 用来做什么 | 没有它时 |
|---|---|---|
| **完全磁盘访问权限** | 读取通知中心记录，把通知显示在刘海 | 其他应用的通知不会出现。充电和 AI 任务完成仍然正常 |
| **辅助功能** | 横幅一出现就读取；打开聊天或 Dock 角标消失时标为已读 | 通知会稍晚出现，已读通知会在刘海上停留更久 |
| **屏幕录制** | 任务结束时绘制屏幕边缘光效 | 只少这个光效，刘海边缘的光仍然会亮 |

<br/>

> [!TIP]
> 不会录制或发送画面。屏幕录制权限只在光效那几秒里，用来照亮并画出光。

---

### 常见问题

<details>
<summary><b>其他应用的通知不出现在刘海</b></summary>
<br>

确认 **完全磁盘访问权限** 里的 Mochinotch 已打开，然后退出应用再打开。只有应用打开之后到来的通知才会显示。如果那个应用自己的通知在 **系统设置 → 通知** 里是关的，刘海也不会收到。

</details>

<details>
<summary><b>AI 任务结束了却没有任何反应</b></summary>
<br>

- 确认 Mochinotch 正在运行。没开的时候，信号会被悄悄丢掉。
- 在设置 → **权限 · AI 连接** 里，确认 **连接 AI 代理** 有绿色对勾。终端里的 Claude Code 和 Codex 要从连接之后新开的会话才生效。
- 用下面 [自己发一条](#自己发一条) 的 `curl`，可以看出是应用还是 hook 的问题。
- hook 的运行记录在 `~/Library/Logs/Mochinotch/hooks.log`。

</details>

<details>
<summary><b>屏幕边缘光效不出现</b></summary>
<br>

需要 **屏幕录制** 权限。在设置 → **权限 · AI 连接** 里点 **屏幕录制** 的 **允许**，在系统设置里打开后，再点 **重新打开**。屏幕录制要重新打开应用才生效。如果觉得光效太抢眼，可以在设置里关掉 **屏幕边缘光效**。

</details>

<details>
<summary><b>没有刘海的 Mac 或外接显示器也能用吗？</b></summary>
<br>

可以。它会变成屏幕顶部中央的黑色胶囊，而不是刘海。如果连接了有刘海的屏幕，会优先用那一块屏幕。

</details>

<details>
<summary><b>更新 macOS 之后通知不来了</b></summary>
<br>

通知是从 macOS 通知中心的私有数据库读出来的。如果 Apple 改了格式，更新之后可能会失效。有新版本时请查看 [Releases](https://github.com/sleeeppy/mochinotch/releases)。

</details>

<details>
<summary><b>个人信息会去哪里？</b></summary>
<br>

不会出去。不连接互联网，事件只在这台 Mac 的 `127.0.0.1` 上接收。

刘海列表只存在内存里，退出应用就消失。排查问题的记录留在 `~/Library/Logs/Mochinotch/`，通知只记下应用和标题，不记正文。这个文件夹随时可以删。

</details>

<details>
<summary><b>想彻底删除</b></summary>
<br>

1. 在设置里点 **退出**，把 `/Applications/Mochinotch.app` 丢进废纸篓。
2. 如果装过 hook，从下面表格里的设置文件中删掉包含 `mochinotch-notify` 的行，或用 `.mochinotch.bak` 还原。
3. 删除 `~/.local/bin/mochinotch-notify`、`~/.kiro/hooks/mochinotch.json` 和 `~/Library/Logs/Mochinotch/`。

</details>

---

### 安装

**要求：** macOS 14 Sonoma 或更高

在有刘海的 MacBook 上最合适。没有刘海的 Mac 或外接显示器上，会显示在屏幕顶部中央，像一颗小胶囊。
<br/>
1. 从 [Releases](https://github.com/sleeeppy/mochinotch/releases/latest) 下载最新的 `Mochinotch.dmg`。
2. 打开后，把 `Mochinotch.app` 拖进 **Applications** 文件夹。
3. 打开应用。

有新版本时刘海会告诉你，设置最下面会出现 **更新**。**v0.3.5 及以上**点一下就会就地接收、替换并重新打开。已经打开的权限和 AI 连接会保留。v0.3.4 及更早需要先从这里安装一次，之后就能在应用里更新。

<br/>

> [!NOTE]
> 应用没有经过 Apple 公证，第一次打开时可能会提示“无法验证开发者”。
>
> - 打开 **系统设置 → 隐私与安全性**，点最下面 `Mochinotch` 的 **仍要打开**。
> - 或者在终端里执行一次。
>
>   ```bash
>   xattr -dr com.apple.quarantine /Applications/Mochinotch.app
>   ```

<br/>

应用打开后，刘海会先打一次招呼，接着展开 **初始权限设置**。<br/>
Dock 和菜单栏都不会出现图标。所有操作都在刘海上。

---

### 使用方法

| 想做的事 | 方法 |
|---|---|
| 看记录 | 把鼠标移到刘海上 |
| 跳到那个应用 | 在展开的列表里点那一项 |
| 清空记录 | 展开列表右上角的 **清除** |
| 打开设置 | 展开列表左上角的齿轮 |
| 退出应用 | 设置最下面的 **退出** |

- 右边的通知图标在列表展开过一次后，会收回刘海里。
- 左边的 AI 任务图标，在你把那个应用（Claude、Cursor、Codex、Kiro）调到前面时会消失。
- 列表只在应用开着的时候积累，最多保留最近 30 条。

---

### 连接 AI 代理（Claude Code · Cursor · Codex · Kiro）

要让 AI 工具把“任务结束了”发给刘海，每个工具都要装一次 hook。不会调用 AI API，也不会发送对话内容。信号只发到这台 Mac 里的 `127.0.0.1:47321`。

### 一个按钮完成连接

在初始权限设置，或设置 → **权限 · AI 连接** 里，点 **连接 AI 代理** 的 **连接**。不需要终端，也不需要另外安装 Python。

1. 只会往这台 Mac 上找到的工具的设置文件里写入 hook。修改前会把原文件复制成 `.mochinotch.bak`，已经连接过的文件不会再动。
2. 正在运行的 Cursor、Claude、Codex 会自动重新打开，马上生效。如果因为有未保存的工作而询问是否退出，不会强行关掉，而是请你自己重新打开。Kiro 会自己重新读取 hook 文件夹，所以不会重新打开。
3. 终端里的 Claude Code 和 Codex 从新开的会话开始生效。

| 工具 | 文件 | 会通知的事 |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | 任务完成、失败、批准窗口、问题卡片 |
| Cursor | `~/.cursor/hooks.json` | 任务完成、失败、停止。问题卡片通过 Cursor 通知接收 |
| Codex | `~/.codex/config.toml`、`~/.codex/hooks.json` | 任务完成、批准窗口（原来的 `notify` 仍会执行） |
| Kiro | `~/.kiro/hooks/mochinotch.json` | 任务完成。等待输入的画面，Kiro 还不会发送 hook |

hook 会调用 `~/.local/bin/mochinotch-notify`，再由这个文件通知应用。即使移动或更新了应用，下次打开时也只会把这个文件改到新位置，连接不会断。

要从终端连接，可以这样运行。已经打开的工具请自己重新打开。

```bash
/Applications/Mochinotch.app/Contents/MacOS/Mochinotch --install-hooks
```

### 自己发一条

应用开着的时候，从终端发出去会马上出现在刘海。自己的脚本或其他工具也可以这样用。

```bash
curl -s -X POST http://127.0.0.1:47321/event \
  -H 'Content-Type: application/json' \
  -d '{"tool":"claude","detail":"README 整理完了","kind":"completed"}'
```

| 字段 | 值 |
|---|---|
| `tool` | `claude`、`cursor`、`codex`，其他值算作普通任务 |
| `kind` | `completed`、`failed`、`needsInput`、`cancelled` |
| `title`、`detail` | 列表里显示的标题和说明（可省略） |
| `bundleID` | 点那一项时要打开的应用（例如 `com.apple.Terminal`） |

也可以用 URL 发送。

```text
mochinotch://event?tool=cursor&kind=completed&detail=build%20done
```

---

### 自己构建

需要 Xcode 15 或更高。

```bash
brew install xcodegen
xcodegen generate
open Mochinotch.xcodeproj
```

在 Xcode 里把签名设为 **Sign to Run Locally** 再 Run。终端里用 `./scripts/run-dev.sh` 就能构建、关掉正在运行的应用并重新打开。开发版每次重新构建签名都会变，权限可能需要重新打开。

| 路径 | 作用 |
|---|---|
| `Mochinotch/` | 应用源码 |
| `Mochinotch/Hooks/` | hook 转发（`--hook`）和设置合并（`--install-hooks`） |
| `scripts/install-hooks.sh` | 用构建出的应用运行 `--install-hooks` |
| `hooks/` | 各工具的设置示例 |
| `docs/` | 开发计划和 README 图片 |
