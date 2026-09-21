# QuotaMonster — 設計文件

> 日期：2026-09-18 · 狀態：待實作 · 對應計劃：`IMPLEMENTATION_PLAN.md`

## 一句話

一個 macOS menu bar app，讓你不用切視窗就知道：**額度還剩多少、幾隻 agent 在跑、誰在等你**。

## 為什麼要自己寫

掃過 22 個相關開源專案，分成三個幾乎不重疊的陣營：

| 陣營 | 代表 | 有什麼 | 缺什麼 |
|---|---|---|---|
| 只做額度 | ccusage 18.6k★、ccstatusline 12.9k★、CCSeva、ClaudeBar | 5h/7d 數字、燒量分析 | 沒有 session 清單、沒有 agent 階層 |
| 只做 session 狀態 | herdr 39k★、claude-status-bar 686★ | 誰在忙、誰卡住 | 沒有額度數字 |
| 只做 subagent 階層 | agent-mission-control、agentwatch | 完整樹狀圖 | 全是 web dashboard / TUI，**沒有一個在 menu bar** |

最接近的是 `vinzdg/codenotch`（1,868★, Swift, MIT）——做到額度 + session，但 session 是平面清單，**完全沒有 subagent 階層**。

**三者的交集沒有人做過。** 這是這個專案存在的理由。

---

## 硬性限制（使用者定的）

1. **零 token 成本。** 不得為了取得用量而呼叫 Claude API。
2. **不 spawn claude 行程。** 連 0 token 的 `claude -p /usage` 也不在背景跑。
3. **不裝 hook。** V1 不動 `~/.claude/settings.json`。

這三條把資料層釘死在「旁聽已存在的檔案」。以下所有設計都在這個框內。

---

## 資料層：四個來源，全部零成本

### S1 — `~/.claude.json` › `cachedUsageUtilization`（額度主來源）

未公開欄位，從 v2.1.274 二進位檔逆向出規則：

```
utilization.five_hour        = { utilization: 28, resets_at: "2026-09-17T19:40:00+00:00", ... }
utilization.seven_day        = { utilization: 18, ... }
utilization.seven_day_opus   / seven_day_sonnet / seven_day_oauth_apps
utilization.limits[]         = [{ kind, percent, resets_at, scope, severity, is_active }]
fetchedAtMs                  = <epoch ms>
accountUuid                  = <uuid>
```

**寫入規則（binary 內 `_0r`）**：任何 claude 行程取得用量後寫入，但有**硬性 5 分鐘節流**。
**讀取規則（binary 內 `u6n`）**：Claude Code 自己把 `age > 3600000ms` 的視為過期並回傳 null，且 `accountUuid` 不符就清空。

→ **我們沿用同一套規則**：≤5 分鐘視為新鮮，>60 分鐘標示為過期並灰化。不自己發明門檻。

⚠️ zod schema 只保證 `five_hour / seven_day / seven_day_oauth_apps / seven_day_opus / seven_day_sonnet / cinder_cove / extra_usage / limits`，其餘欄位（`tangelo`、`nimbus_quill`、`amber_gauge`…）靠 `.passthrough()` 存活，**不可依賴**。

### S2 — statusLine payload tee（額度即時來源，可選 L1）

Claude Code 每次刷新狀態列時，會餵一包 JSON 到 `statusLine.command` 的 stdin。官方文件確認包含：

```
rate_limits.five_hour.used_percentage   # 0-100
rate_limits.five_hour.resets_at         # Unix epoch 秒（注意：與 S1 的 ISO-8601 不同！）
rate_limits.seven_day.used_percentage
rate_limits.seven_day.resets_at
context_window.used_percentage          # 每 session 的 context 壓力
cost.total_cost_usd / total_lines_added / total_lines_removed
model.display_name / agent.name / workspace.current_dir / worktree.branch
```

做法：wrapper script 先把 stdin 原子寫入（tmp + rename）到快取，再原封不動餵給使用者現有的 `statusline.sh`。

**觸發時機**（官方文件）：session 開始/resume、新 assistant 訊息、`/compact` 完成、permission mode 變更、vim 切換、command 變更、`refreshInterval`、`resets_at` 到期、快取 `expires_at` 到期。debounce 300ms，新事件會**取消**執行中的 script → **wrapper 必須原子寫入**，否則會留下截斷的 JSON。

⚠️ 官方文件明載：主 session 閒置時（例如協調者在等背景 subagent）事件會靜默 → 需要 `refreshInterval`（最小 1 秒）才保證刷新。

⚠️ 兩個來源的 `resets_at` **格式不同**（epoch 秒 vs ISO-8601 字串）。混用會產生差了幾十年的倒數。**必須在 parser 邊界統一成 `Date`。**

### S3 — `~/.claude/sessions/<pid>.json`（即時 session 狀態）

```
pid, sessionId, cwd, startedAt, procStart, version, kind, entrypoint,
messagingSocketPath, name, nameSource, status, statusUpdatedAt, updatedAt,
waitingFor?, bridgeSessionId?
```

從 binary 取出的權威狀態機：

```
status 列舉        = ["busy", "shell", "idle", "waiting"]
kind   列舉        = ["interactive", "bg", "daemon", "daemon-worker"]
狀態映射            = { running: "busy", requires_action: "waiting", idle: "idle" }
waitingFor 僅在 status=="waiting" 時存在，值只有兩個：
   "input needed"      ← AskUserQuestion / dialog:* 工具
   "permission prompt" ← 其餘
```

**關鍵**：被 subagent 卡住走的是 `delegatedActive` → `busy` 分支，**不是 `waiting`**。
→ `status == "waiting"` 在設計上就等於「人類被擋住」，可直接當作通知觸發條件，不需要 hook。

### S4 — `~/.claude/projects/<slug>/<sessionId>/subagents/**`（agent 階層）

```
<sessionId>.jsonl                                   ← 協調者 transcript
<sessionId>/subagents/agent-<id>.jsonl              ← 一般 Agent 工具的 subagent
<sessionId>/subagents/agent-<id>.meta.json          ← ~200 bytes，寫一次不動
<sessionId>/subagents/workflows/<wf_id>/agent-*.jsonl
<sessionId>/subagents/workflows/<wf_id>/journal.jsonl
```

`meta.json` 內容：`{ agentType, description, workflowPhase, spawnDepth, requestShape, toolUseId?, parentAgentId? }`

---

## Agent 樹重建演算法

> ⚠️ 研究階段一度採用 `sourceToolAssistantUUID` 當 parent 指標，**經驗證推翻**：該欄位是檔案內指標（72/72 解析於 subagent 自己的 transcript，母 transcript 內 0 筆）。照它寫會得到空樹。

**必須兩套連結法並存：**

| agent 種類 | 連結方式 | 本機佔比 |
|---|---|---|
| 一般 Agent 工具 subagent | `meta.json.toolUseId` ↔ 母 transcript 的 `tool_use.id`；深度 ≥2 用 `parentAgentId` | 31 / 91 |
| **workflow subagent** | **沒有任何 parent 欄位** —— 只能靠目錄路徑 `<sessionId>/subagents/workflows/<wf_id>/` | **60 / 91** |

驗證數據：深度 1 → 22/22 無 `parentAgentId`；深度 2 → 5/5 有；深度 3 → 4/4 有。

### 存活判定：三重 AND 閘（每一閘單獨都有偽陽性）

```
Gate 1  kill(pid, 0) 成功（EPERM 視為存活）
        AND  sysctl(KERN_PROC_PID).kp_proc.p_starttime ≈ startedAt（容差 300 秒）
        ← 只驗 pid 會被 pid 重用騙到，讓死掉的 session 復活

Gate 2  agent 的 .jsonl mtime 新於 session 的 startedAt
        ← subagents/ 是 append-only 歷史，跨 --resume 累積；
          少了這關會把 4 天前的死 agent 當成在跑

Gate 3  workflow agent：journal.jsonl 的 started 減去 (result ∪ failed)
        ← journal 有 'failed' 事件類型，漏掉它會讓失敗的 agent 永遠掛在樹上
          （實測 agentId a8a79b948d33593bc 就是 ['started','failed']）
```

### 已知陷阱

- **session 檔沒有 heartbeat**：`status` 只在轉換時寫入。實測有 session 已宣稱 busy 41 分鐘。**不可用時間戳判斷存活**，只能靠 Gate 1。
- **讀到 0 bytes**：0.1 秒間隔快照實測捕捉到寫入中的空檔。每次讀都要 try/catch，除 `pid/sessionId/cwd/startedAt/status` 外**所有欄位都視為可選**。
- **版本歪斜**：同一台機器上 pid 24098 跑 2.1.272、其餘跑 2.1.274，裝了 4 個版本，symlink 會在更新時改寫。parser 必須容忍版本差異。
- **同一 session 兩筆記錄**：crash 後 resume 會在舊行程收尾前註冊新 pid。依 `sessionId` 去重，保留 `startedAt` 最新的那筆。
- **背景 agent 的完成事件拿不到**：23 筆 `toolUseResult` 中 13 筆是 `async_launched`，不帶 `totalTokens` / `totalDurationMs` / `agentType`。這是不裝 hook 的已知代價，UI 要誠實顯示為「背景執行中，完成狀態未知」。

### 絕對禁止

**不得連線 `/tmp/cc-socks/*.sock`，不得讀取 `sessions/*.key`。**
那是 peer IPC 的訊息注入通道，受 `crossSessionInbound` 信任政策與核准對話框保護。一個監看型 app 去撥它，行為上與攻擊者無異。使用者要的每一件事都能從檔案取得。

---

## 更新策略：FSEvents 為主，慢輪詢保底

```
FSEvents 監看 → ~/.claude/sessions/          （目錄層級，捕捉出現/消失/狀態轉換）
              → 每個活躍 session 的 subagents/ （新 meta.json = agent 誕生；jsonl mtime = 進度）
              → 每個 workflow 的 journal.jsonl
              → ~/.claude.json                （額度刷新）
              → 快取檔（若啟用 statusline tee）

慢輪詢 5 秒  → 保底，捕捉 FSEvents 漏掉的（例如行程死掉但沒碰目錄）
```

**絕不在 UI 路徑上整檔解析 transcript。** 活躍 transcript 實測 480KB–878KB，每 20 秒每 agent 成長 5–35KB。只用 `stat()` 取 mtime/size；真的需要內容時從記住的 byte offset seek 到尾端讀。

---

## 通知政策

> ⚠️ **2026-09-18 更新：原生通知不可用，本節已改設計。**
> Stage 0 實測證實 `UNUserNotificationCenter` 在本機建置、未公證的簽章條件下拿不到授權
> （四個變體全失敗，`ncprefs` 登錄數始終為 0）。詳見 `2026-09-18-stage0-result.md`。
> 使用者決定**走備援、不購買 Developer ID**。以下分級已據此重寫。

### 分級（備援版）

| 級別 | 觸發 | 傳遞（備援版） |
|---|---|---|
| **T1 擋人** | `status=="waiting"` 且 `waitingFor` 存在 | ① 選單列圖示進入警示狀態（外圈依阻塞數等分——已設計完成，零授權需求）<br>② app 自己的 `NSPanel` 浮出視窗，靠近選單列，可點擊跳轉<br>③ `AVAudioPlayer` 短音 |
| **T2 完成** | 扇出整批排空 / 頂層 agent 完成 | 選單列圖示的瞬時訊號（衰減後消失）+ 可選音效 |
| **T3 額度** | 跨越 70% / 90% 門檻 | 僅選單列圖示，不出聲、不浮窗 |

**備援方案的能力邊界（誠實記錄）：**

| | 原生 UN | NSPanel 浮窗 | osascript |
|---|---|---|---|
| 需要授權 | 是（拿不到） | 否 | 否 |
| 進通知中心歷史 | ✔ | ✘ | ✔ |
| 鎖定畫面顯示 | ✔ | ✘ | ✔ |
| 動作按鈕（「跳過去」） | ✔ | ✔ | ✘ |
| 歸屬於本 app 的圖示與名稱 | ✔ | ✔ | ✘（顯示為「指令碼編輯器」） |
| 穿透 Focus | ✔（time-sensitive） | 自行決定 | ✘ |

**osascript 送達已由使用者實機確認（2026-09-18）** —— 橫幅確實出現。
所以它是一條真的可用的通道，只是歸屬與按鈕受限。

→ **T1 以 NSPanel 為主**（唯一同時具備動作按鈕與正確歸屬的通道），
**並同時發一則 osascript 通知**，讓事件進得了通知中心歷史與鎖定畫面——
這兩件事是 NSPanel 做不到的。兩者以同一個去重鍵節流，避免同一事件被通知兩次。
`NSUserNotification` 不是選項（macOS 11 起棄用）。

### 扇出規則（整份設計裡最重要的一條）

這個使用者一次扇出約 10 隻 subagent。**subagent 個別完成絕不通知。** 只在整批排空時發一則：

> `usage · Research 階段 7 個 agent 全部完成 · 4m 12s`

天真的 `SubagentStop` 做法會產生 10 則橫幅——那是攻擊，不是通知。

### 去重與遲滯

- 去重鍵 `(sessionId, eventClass, contentHash)`，60 秒內相同鍵抑制
- 合併視窗 4 秒：同類事件 ≥3 則合成一則摘要
- T1 每個 session 每次等待事件只發一次，5 分鐘後**恰好再推一次**，之後靜默直到狀態解除

### 安靜時段

**不自建排程器。** macOS Focus 已經做了，第二個排程器正是「明明開了勿擾卻在半夜三點響」的成因。只在 footer 提供手動「靜音 1 小時 / 靜音到明早」。

> ⚠️ **2026-09-18 晚更新：「改用 interruption level 讓系統仲裁」這句話在備援路線上是過時的。**
> interruption level 是 `UNUserNotificationCenter` 的東西，而那條路拿不到授權。
> NSPanel、`NSSound`、osascript **三條通道沒有一條是 Focus-aware**，而且這個 app
> 連讀都讀不到 Focus 狀態（`~/Library/DoNotDisturb/DB/Assertions.json` 受 TCC 保護，
> 也沒有公開 API）。所以**手動靜音是唯一的防線**，它因此必須存到磁碟
> （見 `NotifyState`）。

### Stage 5 實作時偏離本文件的兩處（連同理由）

1. **T3 的門檻不是 70%／90%，是 `QuotaTier` 的降級（剩 50%、剩 20%）。**
   `GlyphState.swift` 已經寫死「⚠️ 門檻只能定義在 `QuotaTier.forRemaining`」。
   再開第二組門檻會出現「圖示已經變紅、但通知說你還在 70% 那一格」，
   而且不會有人馬上發現。訊號與顏色要講同一件事。
2. **音效用 `NSSound(named:)`，不是 `AVAudioPlayer`。** AppKit 會快取 named 實例：
   不必自己持有 strong reference（`AVAudioPlayer` 少了那一步，區域變數一釋放
   聲音就當場斷掉），而且播放中再呼叫 `play()` 直接回 `false`。
   不需要往 repo 加任何音效檔。

---

## macOS 平台計劃

### 技術棧

**Swift + AppKit（`NSStatusItem`），非沙盒，`LSUIElement=true`，SwiftPM 建置。**

- SwiftUI 只用在下拉面板內部
- menu bar glyph 用 Core Graphics 離屏繪製成 `NSImage`，指派給 `statusItem.button.image`
- 資料層抽成獨立 library target，可用 `swift test` 完整單元測試（TDD 要求）

### 三顆已驗證的地雷

**1. 🔴 通知權限未證實 —— 必須是第一個實驗**

在 `/private/tmp` 下，無論 ad-hoc 簽章或使用者的 Apple Development 憑證，`UNUserNotificationCenter` 一律回 `UNErrorDomain Code=1 "Notifications are not allowed for this application"`。已排除：簽章、activation policy / LSUIElement、quarantine（無)、TCC 殘留（`tccutil reset` → No such bundle identifier，ncprefs 零筆）。

唯一未測變因是**安裝位置**：`lsregister` 把臨時 bundle 歸類為 `directory: Other (255)`，而這台機器上所有會發通知的第三方 app 都在 `/Applications`。

→ **Stage 0 就是這個實驗。** 複製一支 30 行 probe 到 `~/Applications`，確認系統權限對話框出現且 `granted == true`。若在那裡仍失敗，整個提醒功能要換機制，設計要大改。

備援（若證實不可用）：app 自己的 `NSPanel` 浮出、`AVAudioPlayer` 音效、`osascript display notification`（實測 exit 0 可送達，但會被歸屬到「指令碼編輯器」）。
`NSUserNotification` **不是**備援——macOS 11 起棄用。

**2. 🔴 寬度上限 216pt，超過靜默消失**

實測：216pt 的 button 落在 x=814 y=923（正常）；256pt 的 button 落到 **y=-33**（螢幕外），`isVisible` 仍回 true，**沒有錯誤、沒有 callback**。第三方區右緣固定在 x=1030（系統項目佔 1030→1470）。`NSStatusItem` 會在圖片寬度外自動加 16pt padding。

216pt 是**沒有任何其他第三方 icon 時**的最佳情況，每多一個 app 就縮水。
→ glyph 設計在 22–60pt，且 app 必須偵測 `button.window.frame.origin.y < 0` 並告訴使用者，否則會被當成 crash 回報。

**3. 🔴 工具鏈兩個前置**

```bash
# (a) xcode-select 目前指向 CommandLineTools，xcodebuild 會失敗
#     ——但若走純 SwiftPM 就不需要改。保留此行僅供需要 Xcode 時使用
sudo xcode-select -s /Applications/Xcode.app

# (b) 預設 swiftc 目標是 arm64-apple-macosx28.0，高於執行中的 macOS 27.0
#     包成 .app 後 LaunchServices 直接拒絕啟動（-10825）
#     ——但當成純 CLI binary 跑又完全正常，會騙過天真的 smoke test
#     修法：Package.swift 明寫 platforms: [.macOS(.v14)]
```

### 非沙盒是強制的

核心沙盒拒絕紀錄明確：`deny(1) file-read-data ~/.claude`。更糟的是**沙盒下是靜默失敗**——`NSHomeDirectory()` 被重導到容器，`NSHomeDirectory() + "/.claude"` 不會報錯，只會回報 0 個 session。

代價：不能上 Mac App Store。要分發給別台機器需要 Developer ID + 公證；使用者目前只有 Apple Development 憑證（team PZ56996BR5），`spctl -a -t exec` 對本機簽章的 build 已回 `rejected`。自用不受影響。

### 其他已驗證事項

- `SMAppService`（登入時啟動）可用，且不受安裝位置限制。注意 `status == .notFound (3)` 是註冊前的正常值，不是安裝損壞。
- `NSStatusBar.system.thickness` 回 22.0，但 macOS 27 的 menu bar 實際高 33pt（WindowServer 的 Menubar CGWindow 是 1470×33）。**畫 22pt 內容框，但不要把 bar 高度寫死成 22。**
- 無法自動截圖驗證 glyph（終端機沒有螢幕錄製權限）。自動化檢查只能靠行程內自省（`button.image.size` / `window.frame.origin.y`），顏色要人眼看。

---

## 分期

| 階段 | 內容 | 結束條件 |
|---|---|---|
| **Stage 0** | 通知權限驗證 + 工具鏈 smoke test | probe app 在 `~/Applications` 拿到 `granted == true`，且 .app 能被 LaunchServices 啟動 |
| **Stage 1** | 資料層 library：額度模型 + session 讀取 + 存活判定 | `swift test` 全綠，對真實 fixture 重建出正確結果 |
| **Stage 2** | Agent 樹重建（兩套連結法 + 三重存活閘） | 對真實 fixture 重建出深度 3 的樹，死 agent 不出現 |
| **Stage 3** | menu bar glyph 渲染 | 十種狀態都畫得出來，寬度 ≤60pt，行程內自省通過 |
| **Stage 4** | 下拉面板（額度頭部 + agent 樹 + 事件流） | 點開能看到真實的四個 session 與其子樹 |
| **Stage 5** | 通知層（分級 + 扇出規則 + 去重） | 扇出 10 隻 agent 只收到 1 則通知 |
| **Stage 6** | statusline tee（L1，可選） | 額度變秒級即時，且使用者原本的三行狀態列**逐字不變** |
| **V2** | 燒量預測、卡住偵測、context 壓力、跳轉到卡住的 session | — |

---

## 待解問題

1. 「跳到那個 session 的終端機」做不做得到？四個 session 裡兩個跑在 VS Code 擴充（`entrypoint: claude-vscode`），視窗能提起但面板未必能聚焦；另外兩個在 Ghostty。**V2 時間盒實驗，不進 V1。**
2. `subagents/` 的目錄結構是穩定契約還是實作細節？無官方文件。**必須版本化 parser 並容忍結構變動。**
3. `status` 的第四個值 `"shell"` 從未觀察到（推測是使用者 shell-out）。先不賦予獨立視覺。
4. 「額度過期」的門檻沿用 Claude Code 自己的 60 分鐘，但 app 應在第一週量測實際刷新頻率後自我校準。
