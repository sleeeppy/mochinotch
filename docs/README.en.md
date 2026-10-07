<p align="center">
  <a href="../README.md">한국어</a> · <b>English</b> · <a href="README.ja.md">日本語</a> · <a href="README.zh.md">中文</a>
</p>

<p align="center">
  <img src="images/icon.png" width="128" alt="Mochinotch icon">
</p>

<h3 align="center">Mochinotch</h3>

<p align="center">
  A soft Dynamic Island for the MacBook notch.<br>
  Charging, notifications, and finished AI work show up right on the notch.
</p>

---

### Notifications stack beside the notch

When an app such as Messages, Slack, or KakaoTalk notifies you, its icon pops out on the right of the notch with a badge, like the Dock.
Each new app adds another slot.

<p align="center">
  <img src="images/notice.gif" width="500" alt="An icon and badge appear to the right of the notch when a notification arrives">
</p>
<br/>

### Plugging in the charger

A bolt and the battery percent appear on either side of the notch, then fold away.

<p align="center">
  <img src="images/charge.gif" width="500" alt="Charging at 82% appears on the notch when the charger is plugged in">
</p>
<br/>

### When AI work finishes

When an AI agent (Claude Code, Cursor, Codex, Kiro) finishes, the notch spreads sideways to tell you. <br/>
A light travels once around the edge, and the screen edge glows softly in that app’s color.

<p align="center">
  <img src="images/complete.gif" width="720" alt="The screen edge glows when work finishes">
</p>

<br/>

### When an agent is waiting for an answer

When Claude or Codex shows an approval or a question, an orange **Confirm** opens on the notch. It stays open until you answer, and the screen edge does not glow.

<p align="center">
  <img src="images/confirm.gif" width="720" alt="An orange confirmation opens on the notch when Cursor asks a question, and expanding it shows the question">
</p>

<br/>

### Hover to open the list

Notifications, finished work, and charging history stack newest first. Press an item to jump to that app.

<p align="center">
  <img src="images/expand.gif" width="560" alt="The list expands when the pointer hovers the notch">
</p>

<br/>

### Keep a file on the notch for a moment

Drag a file toward the notch and it drops down to make a place to drop. Drop it on **Keep** on the right and the bottom of the photo peeks out under the notch. You can swap the two sides in Settings. <br/>

<p align="center">
  <img src="images/shelf.gif" width="720" alt="Two photos dropped on Keep peek out under the notch, fan open on hover, and one is dragged into a window">
</p>

<br/>

### Drop a file on the notch for AirDrop

Drop it on **AirDrop** on the left and the notch folds, then the AirDrop window opens so you can pick a device.

<p align="center">
  <img src="images/airdrop.gif" width="720" alt="Dragging a photo to the notch opens a drop zone, and dropping it on AirDrop on the left folds the notch">
</p>

</br>

### Update inside the app

When a new version is out, **New update** appears in this list. Press that row to download, replace the app in place, and relaunch. **v0.3.5 or later** updates from inside the app.

<p align="center">
  <img src="images/update.gif" width="720" alt="Pressing New update in the list shows the download and install, then the notch folds">
</p>

<br/>

---

### Settings

Press the gear and no separate window appears. The notch grows a little and settings show inside it.

<p align="center">
  <img src="images/settings.png" width="500" alt="Settings open inside the notch">
</p>

- **Open at login**: starts automatically when the Mac turns on.
- **Intro**: choose `Mochi` or `Stretch` for the greeting at launch. After you pick one, move the pointer off the notch and it plays once.
- **Screen-edge glow**: when off, only the notch edge glows at the end of AI work. The screen stays as it is.
- **Permissions · AI**: opens the first-time permission screen again. It shows how many items are still off.
- **Guide**: next to the version at the bottom. Opens this page.
- **Keep on the left**: when on, Keep is on the left and AirDrop is on the right. Off is the other way around.
- **Language**: Korean, Japanese, English, or Chinese. The words on the notch change immediately.

---

### Permissions

The first time you launch, the notch opens **First-time permissions** after the greeting. It stays open while you move through System Settings.

<p align="center">
  <img src="images/setup.png" width="500" alt="First-time permissions inside the notch, with three permissions and the AI agent connection all on">
</p>

- **Allow** on each row opens a macOS prompt or the matching list in **System Settings → Privacy & Security**. Turned-on items become a green check on their own.
- If Mochinotch is missing from **Full Disk Access**, press + and add `Mochinotch` from `Applications`.
- **Screen Recording** applies only after the app relaunches. Press **Relaunch** at the bottom of the permission screen.
- **Connect** under **Connect AI agents** installs the hooks in one step. Details are below.
- **Later** closes it and it will not open by itself again. You can reopen it anytime from Settings → **Permissions · AI**.

<br/>

| Permission | What it’s for | Without it |
|---|---|---|
| **Full Disk Access** | Reads Notification Center history and shows notifications on the notch | Other apps’ notifications don’t appear. Charging and finished AI work still do |
| **Accessibility** | Reads a banner as soon as it appears, and marks it read when you open the chat or the Dock badge clears | Notifications arrive a little later, and read ones stay on the notch longer |
| **Screen Recording** | Draws the screen-edge glow when work finishes | Only that glow is missing. The notch-edge light still plays |

<br/>

> [!TIP]
> Nothing is recorded or sent. Screen Recording is used only for the few seconds the glow is drawn.

---

### FAQ

<details>
<summary><b>Other apps’ notifications don’t show on the notch</b></summary>
<br>

Check that Mochinotch is on in **Full Disk Access**, then quit and reopen the app. Only notifications that arrive while the app is running are shown. If that app’s notifications are off in **System Settings → Notifications**, they won’t reach the notch either.

</details>

<details>
<summary><b>Nothing happens when AI work finishes</b></summary>
<br>

- Make sure Mochinotch is running. Signals are dropped quietly when it isn’t.
- In Settings → **Permissions · AI**, check that **Connect AI agents** has a green check. Claude Code and Codex in the terminal apply from the next session after you connect.
- The `curl` in [Send one yourself](#send-one-yourself) shows whether the app or the hook is the problem.
- Hook runs are logged in `~/Library/Logs/Mochinotch/hooks.log`.

</details>

<details>
<summary><b>The screen-edge glow doesn’t play</b></summary>
<br>

**Screen Recording** is required. In Settings → **Permissions · AI**, press **Allow** for **Screen Recording**, turn it on in System Settings, then press **Relaunch**. Screen Recording applies only after a relaunch. If the glow is too much, turn off **Screen-edge glow** in Settings.

</details>

<details>
<summary><b>Does it work on a Mac without a notch, or on an external display?</b></summary>
<br>

Yes. It shows as a black pill at the top center instead of a notch. If a display with a notch is connected, that display is used first.

</details>

<details>
<summary><b>Notifications stopped after a macOS update</b></summary>
<br>

Notifications are read from Notification Center’s private database. If Apple changes the format, it can stop working after an update. Check [Releases](https://github.com/sleeeppy/mochinotch/releases) when a new version is out.

</details>

<details>
<summary><b>Where does my data go?</b></summary>
<br>

Nowhere. It doesn’t connect to the internet, and events are received only at `127.0.0.1` on your Mac.

The notch list lives in memory and disappears when you quit. Troubleshooting logs stay in `~/Library/Logs/Mochinotch/`. Notifications are logged only as app and title, never the body. You can delete that folder anytime.

</details>

<details>
<summary><b>I want to remove it completely</b></summary>
<br>

1. Press **Quit** in Settings and move `/Applications/Mochinotch.app` to the Trash.
2. If you installed hooks, delete the lines containing `mochinotch-notify` from the settings files in the table below, or restore the `.mochinotch.bak` copies.
3. Delete `~/.local/bin/mochinotch-notify`, `~/.kiro/hooks/mochinotch.json`, and `~/Library/Logs/Mochinotch/`.

</details>

---

### Install

**Requires:** macOS 14 Sonoma or later

It fits best on a MacBook with a notch. On a Mac without one, or on an external display, it shows as a small pill at the top center.
<br/>
1. Download the latest `Mochinotch.dmg` from [Releases](https://github.com/sleeeppy/mochinotch/releases/latest).
2. Open it and drag `Mochinotch.app` into **Applications**.
3. Open the app.

A new version is announced on the notch, and **Update** appears at the bottom of Settings. On **v0.3.5 or later**, pressing it downloads the new version, replaces the app, and relaunches. Permissions and AI connections stay. v0.3.4 and earlier: install from here once, then later versions update inside the app.

<br/>

> [!NOTE]
> The app is not notarized, so the first launch may warn about an unidentified developer.
>
> - Go to **System Settings → Privacy & Security** and press **Open Anyway** for `Mochinotch` at the bottom.
> - Or run this once in Terminal.
>
>   ```bash
>   xattr -dr com.apple.quarantine /Applications/Mochinotch.app
>   ```

<br/>

When the app opens, the notch greets you once, then opens **First-time permissions**. <br/>
No icon appears in the Dock or the menu bar. Everything happens on the notch.

---

### How to use it

| I want to | How |
|---|---|
| See history | Hover the notch |
| Jump to that app | Press the item in the expanded list |
| Clear history | **Clear** at the top right of the list |
| Open settings | The gear at the top left of the list |
| Quit | **Quit** at the bottom of Settings |

- Notification icons on the right tuck back into the notch after you expand the list once.
- An AI icon on the left disappears when you bring that app (Claude, Cursor, Codex, Kiro) forward.
- The list lasts only while the app is running, up to the latest 30 items.

---

### Connect AI agents (Claude Code · Cursor · Codex · Kiro)

Each tool needs a hook once so it can tell the notch that work finished. No AI API is called and no conversation is sent. Only a “finished” signal goes to `127.0.0.1:47321` on your Mac.

### Connect with one button

In first-time permissions, or Settings → **Permissions · AI**, press **Connect** under **Connect AI agents**. No terminal and no extra install such as Python.

1. Hooks are written only into settings files for tools found on this Mac. The original file is copied to `.mochinotch.bak` first, and a file that is already connected is left alone.
2. Cursor, Claude, and Codex relaunch themselves when they’re open, so the hook applies right away. If an app asks about unsaved work, it is not forced to quit. You’re asked to relaunch it yourself. Kiro rereads its hook folder and does not relaunch.
3. Claude Code and Codex in the terminal apply from the next session you open.

| Tool | File | What it reports |
|---|---|---|
| Claude Code | `~/.claude/settings.json` | Finished, failed, approval, question card |
| Cursor | `~/.cursor/hooks.json` | Finished, failed, stopped. Question cards arrive as Cursor notifications |
| Codex | `~/.codex/config.toml`, `~/.codex/hooks.json` | Finished, approval (an existing `notify` still runs) |
| Kiro | `~/.kiro/hooks/mochinotch.json` | Finished. Kiro doesn’t send a hook for a waiting-for-input screen yet |

The hook calls `~/.local/bin/mochinotch-notify`, and that file calls the app. If you move or update the app, the next launch rewrites only this file, so the connection stays.

To connect from Terminal, and then relaunch any tool that’s already open:

```bash
/Applications/Mochinotch.app/Contents/MacOS/Mochinotch --install-hooks
```

### Send one yourself

With the app running, this shows on the notch immediately. Scripts and other tools can use the same call.

```bash
curl -s -X POST http://127.0.0.1:47321/event \
  -H 'Content-Type: application/json' \
  -d '{"tool":"claude","detail":"README done","kind":"completed"}'
```

| Field | Value |
|---|---|
| `tool` | `claude`, `cursor`, `codex`. Anything else is a generic task |
| `kind` | `completed`, `failed`, `needsInput`, `cancelled` |
| `title`, `detail` | Title and detail in the list (optional) |
| `bundleID` | App to open when the item is pressed (for example `com.apple.Terminal`) |

A URL works too.

```text
mochinotch://event?tool=cursor&kind=completed&detail=build%20done
```

---

### Build it yourself

Xcode 15 or later.

```bash
brew install xcodegen
xcodegen generate
open Mochinotch.xcodeproj
```

In Xcode, set signing to **Sign to Run Locally** and Run. From Terminal, `./scripts/run-dev.sh` builds, quits the running app, and launches the new one. A development build changes its signature on every rebuild, so you may have to turn permissions back on.

| Path | Role |
|---|---|
| `Mochinotch/` | App source |
| `Mochinotch/Hooks/` | Hook relay (`--hook`) and settings merge (`--install-hooks`) |
| `scripts/install-hooks.sh` | Runs `--install-hooks` with the built app |
| `hooks/` | Example settings per tool |
| `docs/` | Plans and README images |
