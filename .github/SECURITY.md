# 安全性與隱私

你要裝的是一個**沒有沙盒、沒有經過 Apple 公證**的選單列 app，而且它會去讀
`~/.claude/` 底下的東西。下面把「它讀什麼、寫什麼、送不送東西出去」逐條寫出來，
每一條都給你可以自己跑一次的查證方式。

這份文件沿用整個 repo 的用詞規矩（`docs/quotamonster.md` 規矩 5）：

| 標記 | 意思 |
|---|---|
| 〔讀碼〕 | 對照原始碼、或對整個 repo grep 得到的 |
| 〔實測〕 | 在一台機器上真的跑過、看到輸出 |
| 〔推論〕 | 沒有量過，是推出來的 |

本文標〔實測〕的環境：macOS 27.0（build 26A428）、arm64、2026-09-21。
**其他版本／其他機器上會不會一樣，我沒有量過** —— 所以那些地方請當成〔推論〕讀。

---

## 一分鐘版本

- **送出去的東西：沒有。** 整個 `Sources/` 與 `scripts/` 裡沒有任何一個網路 API
  （`URLSession` / `URLRequest` / `Network` / socket / curl / wget 全部 0 筆命中）〔讀碼〕。
  沒有遙測、沒有崩潰回報、沒有自動更新，也沒有任何地方會去讀你的 API key。
- **讀：** `~/.claude.json`、`~/.claude/sessions/`、`~/.claude/projects/` 的一部分
  （transcript 只讀檔尾），加上它自己的 Application Support 目錄。
- **寫：** 只寫 `~/Library/Application Support/QuotaMonster/` 底下。
- **唯一會動到 `~/.claude/` 的東西**是 statusline tee 的安裝腳本，它只改
  `settings.json` 裡的 `statusLine.command` 一個字串，動手前留時間戳備份，
  而且要你自己加 `--apply` 才會執行 → 第 5 節。
- 它**過不了 Gatekeeper** → 第 7 節。

---

## 1. 它讀哪些東西

| 路徑 | 讀出來做什麼 | 讀法 |
|---|---|---|
| `~/.claude.json` | `cachedUsageUtilization`：5 小時／7 天額度百分比、重置時間、分模型窗口 | 只讀，從不寫 |
| `~/.claude/sessions/<pid>.json` | session 註冊表：pid、sessionId、`cwd`、啟動時間、狀態，以及（有的話）session 名稱與 Claude Code 版本 | 只讀 |
| `~/.claude/projects/<slug>/<sessionId>.jsonl` | transcript。判斷「這一輪講完了沒有」與「它在等你批准哪個工具」 | **只讀檔尾 64KB**，極少數情況擴到 256KB；從不整檔讀 |
| `~/.claude/projects/<slug>/<sessionId>/subagents/*.json`、`workflows/*.json`、`journal.jsonl` | subagent 樹與 workflow 狀態 | 只讀 |
| `~/Library/Application Support/QuotaMonster/**` | 它自己的快取、偏好、額度歷史 | 讀寫，見第 2 節 |
| `~/Library/Sounds`、`/System/Library/Sounds` | **只列檔名**，給偏好設定的音效下拉選單用 | 只列目錄，不開檔 |
| 行程表（`kill(pid, 0)`、`sysctl KERN_PROC`） | 註冊表裡那個 pid 還活著嗎；擁有這個 session 的終端機是哪個 app | 不送訊號、不讀別人的記憶體 |
| `CGSessionCopyCurrentDictionary`、IOKit HID 閒置時間 | 螢幕鎖了沒、螢幕睡了沒、你離開鍵盤多久 —— 決定要不要開浮窗／要不要出聲 | 這三個訊號都**不需要任何授權**，也拿不到你按了什麼 |

**沒有讀的東西**（明確講出來，因為這些是你會擔心的）〔讀碼〕：

- **不讀 `~/.claude/settings.json`。** app 從來不開這個檔；只有 tee 的安裝腳本會，
  而那是你自己跑的（第 5 節）。
- 不讀鑰匙圈、不讀剪貼簿、不讀其他 app 的視窗內容。
- 不裝任何 Claude Code hook（`docs/quotamonster.md` 寫下來的拒絕第 8 條）。
- 不做帳號檢查，不解析你的 API key／OAuth token；那些欄位對它沒有用途。

### 關於 transcript：它到底看了你多少內容

這是這個 app 唯一會碰到「對話內容」的地方，所以講細一點〔讀碼〕：

1. **只從檔尾往回讀固定 byte 數**（64KB；視窗裡一則 assistant 都沒有時才擴到 256KB），
   不是 `Data(contentsOf:)`。
2. **只在兩個時刻讀**：要開等待浮窗的那一刻、以及完成偵測的沉澱窗到期時。
   不是每三秒。
3. 讀出來之後只取三種東西：最後一則的 `stop_reason`、最後一則真人訊息的時間、
   以及待批准工具的名稱與一行說明。
4. 這一行說明有兩個去處：**畫在你自己螢幕上的浮窗**，以及（**只在你看不到浮窗時**）
   本機通知的內文，截斷到 200 字。**除此之外不落地、不寫進任何檔案。**

---

## 2. 它寫哪些東西

全部在 `~/Library/Application Support/QuotaMonster/` 底下，一個 byte 都不寫到
`~/.claude/`〔讀碼〕。

| 檔案 | 內容 | 誰寫的 |
|---|---|---|
| `statusline/<session_id>.json` | Claude Code 餵給狀態列的那份 payload **原文**，一個 byte 不改 | statusline tee 這支 shell script（第 5 節） |
| `preferences.json` | 你在偏好設定裡選的東西（音效名稱、門檻、開關） | app |
| `notify-state.json` | 只有 `mutedUntil`（靜音到什麼時候） | app |
| `usage-history.jsonl` | 額度時間序列，一行就是 `{時間, 5h%, 7d%}`，**沒有任何文字內容** | app |
| `trace-usage.log` | 選用的量測記錄。**預設完全不寫** —— 只有你自己 `touch trace-usage.on` 才會開始記 | statusline tee |

⚠️ **`statusline/<session_id>.json` 是這些檔案裡最敏感的一個**，因為它是 payload 原文。
〔實測 2026-09-21〕這台機器上那份 payload 的欄位包含：`session_id`、`transcript_path`、
`cwd`、`session_name`、`model`、`workspace.project_dir`、`cost.*`、`context_window.*`、
`rate_limits.*` —— 也就是**你的專案路徑會在裡面**，但**對話內容不在裡面**。
〔實測 2026-09-21〕那個檔案的權限是 `-rw-------`（0600）—— wrapper 在 `mkdir`
之前設 `umask 077`。⚠️ 但同一次實測裡，**`statusline/` 這個目錄本身是 0755**，
所以同機器的其他使用者列得出檔名（＝session id），讀不到內容。
〔推論，沒有查證〕那多半是因為這個目錄建立於「umask 設在 mkdir 之後」那個
bug 修好之前，早一步用寬權限建出來了；新建的目錄應該是 0700，我沒有在乾淨的
機器上驗過。要自己收緊：`chmod 700 ~/Library/Application\ Support/QuotaMonster/statusline`。

不喜歡這件事的話：不要裝 tee。額度數字會退回 `~/.claude.json` 那個來源
（比較舊，但一樣能用），其他功能不受影響。

### 診斷指令會寫檔嗎

會，但只寫到**你自己在命令列上指定的那個路徑**：`--render` / `--render-panel` /
`--render-alert` / `--render-prefs` 會把 PNG 寫到你給的目錄或檔名〔讀碼〕。

⚠️ 誠實補一條：`Sources/QuotaMonsterApp/main.swift` 裡還留著一段 Stage 0 探針的
程式碼，它會寫 `~/Library/Logs/QMProbe-*.log`。〔讀碼：對 `Sources/` grep `Probe()`
沒有任何命中〕現行的啟動路徑不會走到它，所以那個檔案不會被建出來 ——
但程式碼還在檔案裡，你 grep 的時候會看到它，所以先說。

---

## 3. 它刪哪些東西

整個 Core 只有一個地方會刪檔：`StatusLineCachePruner`，而且〔讀碼〕：

- 只在**它自己的** `~/Library/Application Support/QuotaMonster/statusline/` 裡動手，
  永遠不會走進 `~/.claude/`。
- 只認兩種檔名：`.tmp.*`（寫了一半的孤兒，300 秒寬限）與非 dotfile 的 `*.json`。
- **只刪一般檔案** —— 一個叫 `adir.json` 的**目錄**不會被碰（`removeItem` 是遞迴的）。
- 每分鐘至多跑一次。

`--uninstall` **不會**清這個目錄，因為刪使用者的東西要你自己決定；要清就自己 `rm -rf` 它。

---

## 4. 它送出哪些東西

**沒有網路連線。** 查證方式（你自己跑一次，應該 0 筆命中）：

```bash
git grep -nE 'URLSession|URLRequest|NSURLConnection|import Network|NWConnection|socket\(' -- Sources scripts
```

唯一離開 app 行程的資料是**本機通知**：`/usr/bin/osascript` 的
`display notification`，三個欄位（內文、標題、副標題），送進你自己機器的通知中心。
兩件相關的事：

- 通知的署名會顯示成**「指令碼編輯器」**，不是 QuotaMonster —— 那個身分是
  StandardAdditions 指派給所有 `osascript` 腳本的，這個版本改不掉。
  所以你在通知中心看到「指令碼編輯器」的橫幅時，那就是它。
- 標題**永遠是常數字串** `QuotaMonster`，而且交給 `osascript` 的參數陣列裡，
  使用者可控的字串前面一定有 `--`。這不是風格問題：少了它就是可以被
  transcript 裡的一段文字觸發的 RCE（一個被 prompt injection 的 agent、
  或一個惡意 MCP server 的工具描述，都寫得進 transcript）。
  〔讀碼 2026-09-21〕`Tests/QuotaMonsterCoreTests/OSAScriptCommandTests.swift`
  會**真的餵那個 payload 跑一次 `osascript`**，然後斷言 sentinel 檔案沒有被建出來；
  旁邊還有一則控制組（同一個 payload 拿掉 `--` 就真的會執行），
  用來證明前一則有牙齒 —— 只試引號逸出的測試在有漏洞的版本上也會過。
  ⚠️ `docs/quotamonster.md` 第三節第 17 條說「這樣的測試不存在」。
  那是 2026-09-19 的快照，那一則測試在同一天稍後補上了（commit `b7d2790`）。

---

## 5. statusline tee：唯一會改到 `~/.claude/` 的東西

**如果你只想讀一段，就讀這一段。**

Claude Code 寫進 `~/.claude.json` 的額度快取不是每回合刷新
（〔repo 先前記錄的實測〕可以整整 16 小時不動；〔實測 2026-09-21〕我這次跑 `--dump`
時，那份快取是 **92 小時前**抓的，裡面 5 小時窗口的重置時間早就過去了 ——
它描述的是一個已經不存在的窗口），所以要拿到**活的**額度數字，唯一的途徑是旁聽 Claude Code 餵給狀態列腳本的 payload。
做法是在你原本的狀態列腳本外面包一層 wrapper（tee），而這需要改
`~/.claude/settings.json` 裡的 `statusLine.command`。

**這是選用的。** 不裝，app 照樣能跑，只是額度數字會比較舊。

### 它到底改了什麼

```bash
bash scripts/install_statusline_tee.sh              # 只印 diff，什麼都不改
bash scripts/install_statusline_tee.sh --apply      # 真的裝
bash scripts/install_statusline_tee.sh --uninstall --apply   # 還原
```

〔讀碼 + 51 項 shell 測試，見 `scripts/test_install_statusline_tee.sh`〕：

- **只有 `statusLine.command` 這一個字串會變**，檔案其餘 byte 完全不動
  （包含縮排、註解風格、CRLF、`\uXXXX` 跳脫寫法）。
  你的 hooks、plugin 設定、主題一個字都不會被碰到。
- 改成的樣子是：`QM_STATUSLINE_INNER="$HOME/<你原本的腳本>" "$HOME/.claude/quotamonster-tee.sh"`。
- **動手前一定留備份**：`~/.claude/settings.json.bak-<YYYYmmdd-HHMMSS>`，與原檔逐 byte 相同。
- 你原本的命令字串原樣存進 `~/.claude/quotamonster-tee.original`，
  `--uninstall` 就是拿它**逐 byte 還原**。
- **看不懂就拒絕，不猜**：沒有 `statusLine`、`type` 不是 `"command"`、
  命令不是一個可執行檔、JSON 壞掉、或那個字串在檔案裡出現不只一次 ——
  全部直接中止，不動任何 byte。
- 檔案權限會**保留原本的**（〔實測 2026-09-21〕修掉過一個 bug：原本 0600 的
  settings.json 裝完會變成 0644）。
- `settings.json` 是 symlink（stow / chezmoi / yadm）時，讀寫都走 realpath，
  不會把你的 symlink 換成普通檔。
- 它也會把 `quotamonster-tee.sh` 複製到 `~/.claude/` 底下（wrapper 本體），
  `--uninstall` 會把它與 `.original` 一起移除。

### wrapper 執行時做什麼

每次 Claude Code 渲染狀態列時：把 stdin 的 payload 完整收下來 → 盡力寫快取
（失敗全吞）→ **一個 byte 不差地**交棒給你原本的腳本，並用它的離開碼當離開碼。

- 你的狀態列輸出不會變（67 項對照測試在釘這件事：同一份 payload 直接餵內層
  vs 餵 wrapper，stdout / stderr / 離開碼三者任一不同就算失敗）。
- 快取的每一步都可以失敗，**狀態列不可以** —— 所以它刻意沒有 `set -euo pipefail`。
- 它不送任何東西出去、不改你的 payload、也不看 payload 裡的 token 或 key。

---

## 6. 權限、沙盒、TCC

- 〔實測 2026-09-21〕`codesign -d --entitlements -` 對這個 .app 印不出任何
  entitlement：**沒有 App Sandbox、沒有任何特殊權限**。
  也就是說它以你的使用者身分跑，能讀到的東西就是你自己能讀到的東西 ——
  這正是它讀得到 `~/.claude/` 的原因，也是你應該讀完這份文件再決定裝不裝的原因。
- 不要求輔助使用（Accessibility）、不要求螢幕錄製、不要求完全磁碟取用權限。
- 通知走 `osascript`，所以**不會**跳 QuotaMonster 自己的通知授權對話框。
- 「開機自動啟動」走 `SMAppService.mainApp`：註冊的是**這個 .app 本身**，
  app 不安裝任何 helper bundle、也不自己寫 LaunchAgent plist（註冊交給系統做）。
  你可以用 `--probe-login` 看它現在的真實狀態；不加 `--register` / `--unregister`
  它就只看不動手。

---

## 7. 簽章與公證：這個版本過不了 Gatekeeper，而且短期內不會改

講白：這個專案只有**免費 Apple ID 的 Apple Development 憑證**，**沒有 Developer ID**。
公證（notarization）需要 Developer ID，所以：

**這個 .app 與任何由它做出來的 DMG，都不可能通過公證。**

〔實測 2026-09-21〕`spctl -a -vvv` 對裝好的 .app 回的就是 `rejected`。

你有兩條路：

1. **自己 build**（建議）。〔實測 2026-09-21〕這個 repo 裡沒有任何預先編好的
   執行檔（`git ls-files` 只有原始碼、文件與幾張證據 PNG），
   所以你跑的就是你剛剛看過的原始碼。
   `bash scripts/make_app.sh` **預設走 ad-hoc 簽章**；要用自己的
   Apple Development 憑證就設環境變數
   （`CODESIGN_IDENTITY="…" bash scripts/make_app.sh`，
   名稱用 `security find-identity -v -p codesigning` 查）。
   ⚠️ 兩種都過不了公證 —— 差別在 ad-hoc 沒有穩定的簽章身分，
   〔推論，這份文件沒有量過〕重建之後通知授權可能要重新給一次。
2. 用 release 的 DMG、或別人給你的 .app：第一次打開要用**右鍵 → 打開**，或到
   系統設定 → 隱私權與安全性 → 「仍要打開」。
   ⚠️ 這個動作對任何 app 都是同一個動作，所以**只對你自己 build 或你真的信任來源的東西做**。

---

## 8. 自己查證的指令

```bash
# 它碰哪些路徑
git grep -n 'claude\|Application Support' -- Sources scripts

# 有沒有網路（應該 0 筆）
git grep -nE 'URLSession|URLRequest|import Network|NWConnection|socket\(' -- Sources scripts

# 有沒有碰鑰匙圈（應該 0 筆）
git grep -niE 'keychain|SecItem' -- Sources scripts

# 把 find-generic-password 也加進去，就只會命中 capture_fixtures.py 裡
# 那段「不准這樣做」的註解 —— 那條規矩是為一次已經發生的外洩補的
git grep -niE 'keychain|SecItem|find-generic-password' -- Sources scripts

# 它會啟動哪些外部行程（應該只有 /usr/bin/osascript）
git grep -n 'executableURL\|launchPath' -- Sources

# 它寫／刪哪些檔
git grep -n 'write(to\|createFile\|removeItem\|replaceItem' -- Sources

# 資料層真的看到了什麼（這支會印出你自己的路徑與 session，貼出來前先看一眼）
~/Applications/QuotaMonster.app/Contents/MacOS/QuotaMonsterApp --dump
```

---

## 9. 回報安全問題

**請不要開公開 issue。**

用 GitHub 的私密回報：這個 repo 的 **Security → Report a vulnerability**
（Private vulnerability reporting）。那條路只有維護者看得到。

請盡量附上：

- 受影響的版本與 macOS 版本。版本號目前只寫在 bundle 裡（app 本身沒有「關於」視窗）：
  `plutil -extract CFBundleShortVersionString raw ~/Applications/QuotaMonster.app/Contents/Info.plist`
  〔實測 2026-09-21 回 `0.1.0`〕
- 重現步驟。如果需要一份會觸發問題的 transcript 或 payload，
  **請先把裡面的內容換掉**再貼（`scripts/capture_fixtures.py` 有現成的去識別化流程，
  而且它看到 `sk-ant-` 開頭的字串會直接拒絕寫出）
- 你認為的影響範圍

回報後會發生什麼：這是一個人維護的業餘專案，**沒有 SLA**。
會盡快確認收到並告訴你判斷結果；修好之後會在 release notes 裡註明，
你不想被提到的話說一聲。

⚠️ 反過來也請你注意：**不要在 issue、PR 或討論裡貼未經處理的 `--dump` 輸出**。
那份輸出裡有你的家目錄路徑、專案名、session 名稱，以及 subagent 的任務描述。
