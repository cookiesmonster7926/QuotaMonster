# QuotaMonster — 保留下來的那一份

> **這份文件取代 `IMPLEMENTATION_PLAN.md`（已改名為 `docs/build-log.md`）。** 那份是**施工**用的，按 Stage 排；
> 這份按**主題**排，因為讀者是從問題到達的（「為什麼圖示不能用黃色？」
> 「為什麼不信 session 的 status 欄位？」），不是從 Stage 到達的。
>
> 原始的施工紀錄保留在 `docs/build-log.md`。⚠️ **那份裡面有已知是錯的敘述**
> （本文第三節逐條列出），所以它只能當歷史看，不能當現況引用。
>
> ### 這份文件怎麼產生的
> 2026-09-19，五個 agent 各自負責一個子系統，從 1653 行的計畫書萃取
> 「不可違反的規矩 / 寫下來的拒絕 / 被推翻的 / 量測數字」，
> 再由第六個 agent **逐條對照當時的原始碼**查證。
> 查證過程中抓出三處**程式碼裡已經不成立的註解**（一處是真的 bug），都已修掉。
>
> 每一條規矩都附**證據**與**這個 repo 為它付過什麼代價**。
> 代價那一欄不是裝飾 —— 它是下一個人判斷「這條可不可以繞過」的唯一依據。

---

## 這是什麼

macOS 選單列 app（Swift 6 / AppKit / SwiftPM），看 Claude Code 的額度與 session。
**零 token、零行程、零網路** —— 全部是讀既有的檔案。

- `Sources/QuotaMonsterCore/` —— 純邏輯，沒有 AppKit、沒有 `Date()`、沒有計時器。
  **所有決策都在這裡**，因為只有這裡有測試 target。
- `Sources/QuotaMonsterApp/` —— AppKit / SwiftUI。**只有路由與繪圖，不可以有決策。**

## 怎麼建、怎麼跑、怎麼驗

```bash
bash scripts/test.sh              # 不可以直接 swift test，理由見規矩 27
rm -rf .build && swift build -c release   # 增量建置的 Build complete 是假象
bash scripts/make_app.sh          # 組 .app 並裝到 ~/Applications
```

---

## 一、不可違反的規矩

每一條都在 2026-09-19 對照過當時的原始碼。


> ⚠️ **編號是按「發現的先後」給的，分節是按「主題」分的**，所以同一個子節裡的
> 編號不連號，而且子節之間的區間會重疊（資料層 6–38、Agent 13–37…）。
> 想確認總數請數條目，不要看「最後一條是幾號」。
>
> 〔2026-09-22 這一段是補的〕在那之前，31–39 全部被插在「顯示」子節裡，
> 造成兩次編號倒退 —— 一個 subagent 在數規矩時抓到的。

### 貫穿全專案

**1. 「不存在」不等於「那個狀態不成立」，而且要分兩層：看到它、但它不在那個狀態 → 正面證據，當場處理；整個沒看到它 → 不是證據，要寬限期或切斷。**

- **為什麼**：這是全 repo 出現最多次、也付過最多次代價的一條，四個落點都查證仍成立：T1 `observeWaiting`（看到但不在等→當場清；整個沒看到→連續 2 拍且 ≥30 秒才過期）、T2 `observeBatches`（同一套常數）、`TurnReadout` 三態（finished / unfinished / inconclusive）、`Presence.idleSeconds` 的 nil 不是 0。〔實測，一支探針〕T1 少了寬限期時，漏看一拍之後同一個 episode 在 t+9 再喊一次、t+305 又多一次重推。
- **證據**：NotificationEngine.swift:335-341(present 集合)、405-415、511-522、58-59(absenceGrace=30 / absenceTicks=2)；TurnCompletionReader.swift:3-16、100-101；Presence.swift:26-30；docs/build-log.md:1030-1032、1582-1590
- **付過的代價**：同一個錯在這個 repo 犯過至少三次：T2 有寬限而 T1 沒有（註解原本寫「最壞情況是下一次等待被當成新事件，而它本來就是新事件」，被探針證明是錯的，整段已改寫）；T2 的 runStatus 讀不到一度被當成「正面確認它不是 killed」；`WaitingContextReader.read` 把三件事塌縮成一個 nil，被自己的原始碼點名為反面教材。

**2. 任何門檻／常數只能定義在一處，第二份字面量一律做成別名或引用。今天的五個落點：`QuotaTier.forRemaining`、`Presence.idleThreshold`（`ScreenPresence.idleThreshold` 只是別名）、快取路徑 `StatusLineCacheReader.relativeCacheDirectory`（shell wrapper 對帳）、`FinishCaption.lifetime = FinishGlow.goneSeconds`、`RowMetrics.header = SessionRow.headerHeight`。**

- **為什麼**：兩份字面量只要有一次只改了一邊，兩邊就會在某個邊界上漂開，而那種不一致沒有人會馬上發現。快取路徑那一份最惡毒：兩邊寫得不一樣不會有任何錯誤訊息 —— wrapper 照常寫檔、app 照常讀到空目錄，表現出來正好就是「tee 裝了但額度還是過期」。⚠️ `ScreenPresence.idleThreshold` 這條別名**沒有測試守著**，用 `#expect(Presence.idleThreshold == 300)` 去釘是一則說謊的測試（別名改成另一個字面量 300 照樣會過）。
- **證據**：GlyphState.swift:17-25；Presence.swift:32-37；ScreenPresence.swift:20-30；StatusLineCacheReader.swift:23-31；StatusLineCachePathTests.swift:30-39；SessionFinish.swift:27-29；PanelView.swift:339-342
- **付過的代價**：有 —— 「用 `contains` 比對路徑常數」是 mutation testing 指出的五個洞之一（`.../statusline2` 仍然會通過），現在測試比的是完全相同。T3 原本要用 70%／90% 兩個自己的門檻，被這條規矩擋下來改成「顏色變了的那一刻」。

**3. 缺資料一律回 nil / 畫「—」，絕對不要回 0%、0 秒或 `Date()`。`nil` 在這個 repo 一律是「不知道」，不是零。**

- **為什麼**：0% 和「不知道」在視覺上必須不同，否則 app 會在你額度爆掉時顯示一條空的安全長條。而且窗口缺席是常態：Claude Code 自己會在 `resets_at` 一過就把整個窗口從 payload 拿掉〔文件「drops a window once its resets_at time passes」＋二進位 `MSn`〕。同一條在別處的落點：`runDuration` 的 0 會被畫成「跑了 0m 00s」，看起來像一個量到的數字；`ranFor` 算不出來就整格不畫，〔實測〕命中率只有 84.1%（111/132），約六分之一的完成沒有秒數；「硬編一個 `Date()` 進去就是憑空造一個量測」。
- **證據**：UsageSourceSelector.swift:38-39；StatusLineCacheReader.swift:92-101；ClaudeJSONUsageReader.swift:111-115；PanelView.swift:167-173、197-201；WorkflowRunState.swift:19-21；SessionFinish.swift:10-15；FinishSignal.swift:54-56；TurnCompletionReader.swift:116-118；docs/build-log.md:206、447、583、797、863

**4. App 層不可以有任何決策 —— 「該不該發」全部在 Core。`QuotaMonsterApp` 沒有測試 target，放進去的判斷就永遠不會有測試。今天的三個落點：`NotificationEngine`（出不出聲）、`WorkflowTally`（workflow 下場分類）、`OutlookCaption`（展望的所有字串）。**

- **為什麼**：一個新功能最容易造成的傷害不是算錯，是**安靜地改掉使用者已經每天在看的那一行** —— 放在 Core，「拒絕時與今天一模一樣」就是一個 `#expect`，不是一句承諾。`Package.swift` 今天只有一個 testTarget（`QuotaMonsterCoreTests`），所以這條是結構事實不是偏好。
- **證據**：Package.swift:13-17；NotificationPresenter.swift:5-8；WorkflowTally.swift:9-10；OutlookCaption.swift:5-9；docs/build-log.md:1097、1211-1213
- **付過的代價**：有 —— presenter 裡曾經有一個 `if batch.outcome == .completed`，它和在場判斷、預算一起被搬進 Core 才釘得住。

**5. 註解與文件裡「實測」「代理量測」「推論」「文件說」是四件不同的事，不可以混用；把品味寫成機制論也是一種說謊。**

- **為什麼**：混用會慢慢侵蝕掉整份註解的可信度，而那正是它唯一的價值。這個 repo 兩次在 commit 訊息／待辦裡把推論寫成已證實，兩次都要撤回。示範：`FinishGlow` 三段離散的理由只能寫「mockup 是使用者選的那一份」—— 連續濃度在機制上完全做得到（600 秒裡重畫十幾次），把品味寫成機制論就是在註解裡把偏好偽裝成量測。
- **證據**：FinishSignal.swift:3-11；SignalPalette.swift:10-12、36-38；TurnCompletionReader.swift:93-95；CompletionTracker.swift:35-37；docs/build-log.md:1228-1233、1466-1477、1540
- **付過的代價**：有 —— 「⚠️ 留一條錯的待辦在計畫書裡，和留一段說謊的註解是同一件事」（docs/build-log.md:1540）。


### 資料層：額度、session、快取

**6. 存活判定必須是「pid 存在 而且 核心記的行程啟動時間與 `startedAt` 相差在 300 秒內」；`kill(pid,0)` 回 `EPERM` 視為存活；死掉的 session 一律排除，註冊表裡寫什麼都不算數。**

- **為什麼**：crash 的 session 會留下一個永遠寫著 `busy` 的檔案，而 pid 會被系統回收再利用 —— 只驗 pid 會讓一個不相干的新行程「復活」那個死掉的 session。時間戳也救不了：`status` 只在狀態轉換時寫入，**沒有 heartbeat**，〔實測〕本機有 session 已宣稱 busy 41 分鐘。出貨版另有兩處守衛：`sysctl` 的 nlen 用 `u_int(mib.count)` 而不是寫死的 4，而且多驗 `info.kp_proc.p_pid == pid` 才接受那個啟動時間。
- **證據**：ProcessLiveness.swift:4-21、23-28、31-39；SessionState.swift:51-62；docs/build-log.md:150、272-276、311

**7. 目錄掃描器永不丟錯：壞檔跳過、0 bytes 跳過、截斷跳過、目錄不存在回空陣列。這條不適用於單一具名檔案的 reader —— `ClaudeJSONUsageReader.read` 用的是 `try` 不是 `try?`，今天仍然如此，不要照抄它。**

- **為什麼**：讀到 0 bytes 是正常現象（〔實測〕0.1 秒間隔快照就會捕捉到寫入中的空檔）；statusline 快取則是因為 Claude Code 會 abort 執行中的腳本，被 SIGKILL 打斷時目錄裡就是會有寫到一半的東西〔文件 ＋ 二進位 `#k()`〕。
- **證據**：SessionRegistryReader.swift:5-11、16-25、37-47；StatusLineCacheReader.swift:9-12、54-67；ClaudeJSONUsageReader.swift:29-31(對照組)；docs/build-log.md:149、257、776-778

**8. 兩個額度來源之間不做欄位層級的合併 —— 整筆快照只能有一個來源，缺的窗口不從另一邊回填；`resets_at` 的格式必須由呼叫端明講（`.iso8601(String)` vs `.epochSeconds(TimeInterval)`），不猜。**

- **為什麼**：兩邊的 five_hour 可能屬於**不同的窗口**（一個已重置、一個沒有），拼進同一列會產生一組互相矛盾、但看起來完全正常的數字。少一個數字（顯示「—」）是誠實的，湊一個不是。格式那半條：混用不會報錯，只會產生差了幾十年的倒數〔文件明寫 ＋ 二進位四處互證：`Math.round(h)`、`resets_at*1000`、`MSn` 的一年上限過濾〕，統一必須發生在 parser 邊界。
- **證據**：UsageSourceSelector.swift:23-32、40-58；ResetTimestamp.swift:3-16、27-36；StatusLineCacheReader.swift:16-20、108-117；docs/build-log.md:229、485、580、799-803

**9. statusline wrapper：先把 payload 收進記憶體，再盡力寫快取（失敗全吞），最後 `printf '%s' "$payload" | "$INNER"` 並以 `${PIPESTATUS[1]}` 當離開碼。刻意沒有 `set -euo pipefail`；快取一律 tmp + `rename(2)`；`umask 077` 設在 `mkdir` 之前、交棒前還原；交棒前 `trap - TERM INT HUP EXIT`，訊號 trap 要真的 exit（143/130/129）。**

- **為什麼**：官方文件明寫：離開碼非 0 或輸出為空，使用者的狀態列會整條變空白。所以快取的每一步都可以失敗，狀態列不可以。`set -e` 會讓任何一個無關緊要的失敗（例如快取目錄不可寫）在內層跑起來之前就終止腳本。原子寫入是**必要條件**不是防禦性寫法 —— 文件逐字「Claude Code cancels the in-flight script」＋二進位 `#k(){this.#a?.abort();…}`，直接寫檔會讓讀取端看到寫一半的 JSON。
- **證據**：quotamonster-tee.sh:15-34、46-48、52-58、60-66、82-84、95-99；docs/build-log.md:676-681、589、592
- **付過的代價**：有，四次：(1) 早期版本先 `cat > "$tmp"` 再把該檔餵給內層，快取目錄不可寫時整條狀態列以 rc=1、零輸出消失（CRITICAL，實測重現過），結構整個重寫；(2) trap 只做 rm 不 exit，被中止後行程回頭繼續等 stdin 永遠掛著（code review 抓到，實測會卡住）；(3) umask 設在 mkdir 之後，呼叫端 umask 0222 時建出 0555 的永久不可寫目錄（code review 抓到）；(4) SIGKILL 攔不到，實測會留下 `.tmp.*` 孤兒，因此必須額外寫 `StatusLineCachePruner`。

**10. `Int(Double)` 在這個 repo 是明文血訓 —— 超出 `Int.max` 或 NaN 會直接 trap 掉整個行程，而這些數字全部來自磁碟上的 JSON。三個落點都要照做：百分比夾在 `maxPercent = 1000` 以內、episode 鍵用 `String(t.timeIntervalSince1970)` 不用 `Int(...)`、`durationMs` 用 `NSNumber?.doubleValue` 不用 `as? Int`。**

- **為什麼**：〔實測〕沒有夾限時整個測試行程以 signal 5 死掉（`1e20` 是完全合法的 JSON 數字）；episode 鍵實測 `1e18` 就打得死。`.intValue / 1000` 另外還是整數除法，會把 345160 悄悄變成 345。上界留到 1000 而不是硬夾 100，是因為 `spend_limit` 超用後可以超過 100。
- **證據**：StatusLineCacheReader.swift:42-48、104-106；NotificationEngine.swift:152-158；WorkflowRunState.swift:49-58；docs/build-log.md:503
- **付過的代價**：有 —— 百分比夾限是 code review 的 MEDIUM 發現；在修掉之前，一筆絕對值荒謬的 payload 就能讓整個 app 當掉。

**11. `StatusLineCachePruner` 是整個 Core 唯一會刪檔的東西：只認 `.tmp.*` 與非 dotfile 的 `*.json` 兩種檔名，只刪一般檔案，且由 `DataStore` 每分鐘至多呼叫一次（不是每 3 秒）。`retention(for:)` 回 nil 的意思是「連碰都不要碰」，不是「立刻刪」。**

- **為什麼**：寧可留著垃圾，也不要刪掉正在寫的檔案 —— `.tmp.*` 的 300 秒寬限相對 statusline script〔實測〕20 ms 量級的執行時間有四個數量級餘裕。`removeItem` 是遞迴的，一個叫 `adir.json` 的**目錄**會連同裡面的東西一起消失〔原文未標，是 API 語意推論〕。目錄放在 QuotaMonster 自己的 Application Support 底下而不是 `~/.claude/`，所以它動手時不會碰到別人的東西。
- **證據**：StatusLineCachePruner.swift:4-23、38-52；DataStore.swift:114-116、207-210；docs/build-log.md:488、823-830

**12. 產生 fixture 一律去識別化，且任何含 `sk-ant-` 的內容一律拒絕寫出（找到就以非零碼結束）。**

- **為什麼**：研究階段有 agent 執行 `security find-generic-password -g`，把 OAuth token 寫進了本機 transcript —— fixture 腳本必須主動防這件事〔實測／已發生的事故〕。
- **證據**：scripts/capture_fixtures.py:2-12
- **付過的代價**：有 —— 這條規則就是為一次已經發生的外洩補的。


**31. 「檔案什麼時候寫的」不等於「這組數字什麼時候量的」。statusline payload 裡
有 7 天窗口卻沒有 5 小時窗口時，那筆讀數的年紀**沒有可計算的上界**，必須降成
`.expired`；「窗口過期」這件事全 repo 只有 `WindowExpiry` 一份定義，兩個 reader 共用；
`.expired` 的快照不產生歷史取樣點。**

- **為什麼**：〔實測 2026-09-21，讀 Claude Code 2.1.277 二進位〕payload 的
  `rate_limits` 不是每次渲染去問來的，是從行程記憶體的 `Eu.rawUtilization` 重發，
  而那個欄位**只有 API 回應才更新**（`function k2(){return xPr(Eu.rawUtilization)}`）。
  渲染由 UI 事件觸發，可以完全不帶新的回應 —— 所以檔案可以很新、數字可以很舊。
  `u0t` 是逐窗口判斷的（`e.resets_at>r`），五小時窗口最多活五小時，它一旦消失
  就證明 `rawUtilization` 至少從某個五小時窗口結束前就沒更新過。
- **代價**：〔實測〕`usage-history.jsonl` 在 09-21 19:30:51 寫下 `{"5h":null,"7d":0}`，
  **三秒後**寫下 `{"5h":20,"7d":13}`。同一個未重置的七天窗口不可能三秒內從 0 變成 13。
- **第二份定義的代價**：`ClaudeJSONUsageReader.window` 以前不檢查 `resets_at` 過期，
  `StatusLineCacheReader.window` 會檢查。〔實測〕`~/.claude.json` 的 `fetchedAtMs`
  從 09-17 23:43 凍住四天，那個來源一直吐同一組 `30/19` —— 而歷史檔 09-20 15:25
  那**唯一一筆**取樣點逐字等於那個凍住的檔案。四天的歷史裡有一天是假的。
- ⚠️ 刻意**重用** `.expired` 而不是新增一個 Freshness case：全 Sources 有 22 處在問
  `== .expired`（不上色、不預測、不發通知、降調），新增 case 會讓那 22 處**靜靜地**
  把它當成可信 —— 那正是這個 bug 本來的樣子。完整 switch 只有 2 處，保護不了那 22 處。
- ✅ **〔已量到 2026-09-22〕**「閒置後的第一次渲染會帶出舊數字」不再是推論：
  `trace-usage.log` 621 次渲染裡，閒置 1.5 小時後回來的前 **4 次渲染、83 秒**
  都在報 1.5 小時前的舊值，然後 7d 在**一秒內**從 19 跳到 28。詳見第五節 A2。
- ⚠️〔推論，未實測〕天生沒有五小時窗口的帳號會被這條規則永久降級。沒見過這種帳號。

**33. `~/.claude.json` 的 `cachedUsageUtilization` 不可以再被當成額度來源。
statusline tee 是**唯一**的來源，所以任何「沒有讀數」的畫面都必須說得出
「去裝 tee」以及確切的指令。**

- **為什麼**：〔實測 2026-09-21，單一機器〕那個檔案還在被 Claude Code 持續重寫
  （mtime 是當下），但 `fetchedAtMs` **凍在 3.9 天前**。把 tee 的快取目錄移開
  實跑 `--dump`，兩個窗口都變成「沒有讀數」。repo 舊文件寫「實測可以整整 16 小時
  不更新」—— 那個數字已經樂觀得不成比例。
- **代價**：規矩 31 讓 `ClaudeJSONUsageReader` 開始擋過期窗口之後，那個來源回 nil
  → `pick()` 回 nil → `usage` 是 nil → 面板原本那句「沒裝 statusline tee」
  **整個消失**，只剩「無讀數」三個字。老使用者沒差（有 tee），
  新使用者第一眼看到的就是它。文案與「該不該出現」都搬進 `UsageSourceCaption`（Core）。
- ⚠️ 同一條規矩的另一半：**tee 有在寫就不准說「沒裝」**。叫一個已經裝好的人
  再裝一次是最糟的謊 —— 他會去重裝一個沒壞的東西，然後開始懷疑其餘每一句話。
  這一條有測試逐一走過 freshness × source 的組合釘住。

**34. 「沒有 statusLine」與「statusLine 形狀看不懂」是兩件事。前者可以從零建立，
後者一律拒絕。**

- **為什麼**：規矩「看不懂的設定一律拒絕，不猜」擋的是「看不懂既有的設定卻硬要包」。
  **沒有東西可以保留，就沒有東西會被猜壞。** 而規矩 33 讓「裝不了 tee」等於
  「這個 app 沒有額度功能」，所以把沒有自訂狀態列的使用者擋在門外的代價太高。
- **從零建立的做法**：在 JSON 最前面**插入**一段（`insert_status_line`），
  不用 `json.dumps` 重寫整個檔 —— 那會把使用者的縮排、鍵的順序、尾端換行全換掉。
- ⚠️ **`--uninstall` 要把整段拿掉，不是把 command 還原成空字串。**
  「原本沒有」與「原本是空的」是兩件事；後者會留下一個 command 是 `""` 的
  statusLine，Claude Code 拿空命令去跑，狀態列整條變空白。
  記號是 `quotamonster-tee.original` 裡的空字串。

**35. 註冊表的 `name` 只有在 `nameSource != "derived"` 時才是使用者看過的名字。
`derived` 是 Claude Code 從 cwd 湊的佔位名，顯示它等於顯示一個使用者不認得的字串。**

- **實測 2026-09-22**（四個同時存在的 session）：

  | session | registry `name` | `nameSource` | transcript 的 `aiTitle` |
  |---|---|---|---|
  | a28a5af5 | `usage-ff` | derived | `修t2` |
  | eb209917 | `rl-b5` | derived | `Q-learning 環境 setup` |
  | d8258fe6 | `Q-learning 環境 setup` | **auto** | 同左 |
  | 2d765b86（VS Code 外掛）| `rl-1b` | derived | `0922作業` |

- **怎麼撈**：transcript 裡的 `{"type":"ai-title","aiTitle":"…"}`，取尾端**最後**一筆。
  尾端大小沿用 `WaitingContextReader.tailBytes`（64KB）—— 不發明新門檻。
  〔實測〕最後一筆離檔尾 176 / 2,529 / 15,666 bytes（n=3），餘裕充足。
- ⚠️ **只在 `derived` 時才去讀。** `auto` 代表那個名字有來歷，蓋掉它是把已知的事實
  換成猜測；`nameSource` 是 nil（未知）時同理。讀 transcript 是 I/O，
  有測試**數呼叫次數**釘住「用不到就一次都不准發生」。
- ⚠️ 每 60 秒才重撈一次（`SessionTitle.refreshInterval`）。面板每 3 秒刷新，
  而標題幾乎不動 —— 每次都讀 64KB 是為了一個不變的字串每秒讀幾十 KB。
- ⚠️ **這不是 VS Code 專屬的修補。** 起點是「外掛的 session 顯示成 rl-1b」，
  但四個 session 有三個是 `derived`，終端機的也一樣。

**36. VS Code 外掛的 session 不會產生 statusline payload，所以它對額度數字沒有任何貢獻。**

- 〔實測 2026-09-22〕session `2d765b86` 已經活了 2 小時、正在工作，
  tee 快取裡**一個 payload 都沒有**；同時間終端機的 session 每次渲染都有。
  外掛有自己的一套 UI（模型選擇器、計時器），不呼叫 `statusLine` 命令。
- **後果**：`context_window.used_percentage` 只存在於 payload 裡，磁碟上沒有第二處 ——
  所以外掛的 session 永遠沒有 ctx 壓力細條。而配合規矩 33
  （`~/.claude.json` 已經不再更新），**只用外掛的使用者完全拿不到額度數字**。
- ⚠️ 這一條**修不了**（我們無法讓外掛去跑 statusline），只能寫在文件裡。

**38. 「那一天沒有用量」與「那一天我們沒在看」必須分得開，而且心跳要寫在
**另一個檔案**。**

- **為什麼分得開很重要**：`usage-history.jsonl` 是事件驅動的，
  「某一天一行都沒有」是雙關 —— 可能沒用，也可能 app 沒開。
  每日長條圖把後者畫成 0%，就是把「我沒在看」講成「你沒有用」。
- **為什麼是另一個檔案**：這一步（Stage 7 步驟 10）當初被擱置的理由是
  「它會改變『檔案裡沒有那一行』的意思，而那是**不可逆的語意變更**」。
  那個反對是對的。寫進 `watch-log.jsonl` 之後 `usage-history.jsonl` 的語意
  一個字都沒動，要反悔只要刪掉那個檔 —— **不可逆的那一半被移除了**。
- 心跳 300 秒一次（288 行／天 × 30 天 ≈ 190KB；日界歸屬誤差上限 = 一天的 0.35%）。
  開機標記另計：心跳的空隙**推不出**「重開了」還是「機器睡著了」，
  睡醒不會有 boot。

### Agent 樹與 workflow

**13. T2「整批排空」的正面證據是 run 狀態檔（`<sessionId>/workflows/<wf_id>.json` 存在且 status ∈ {completed,failed,killed}），不是 journal 的 `finishedCount == total`。數字比對降為第二道防線，且 `total` 與 `peakFinished` 都取看過的最大值（單調不減）。**

- **為什麼**：〔實測 n=32〕32/32 的 mtime == birthtime、birthtime 從不早於最後一次 journal 寫入（中位 +0.0s、最大 +344s、0 個為負），執行中的 workflow 在磁碟上根本還沒有這個檔 —— 所以「檔案在且 status 終結」＝「整個 workflow script 回來了」。反過來，`total` 只數目前目錄裡存在的 meta 檔，多階段交界（上一階段收尾、下一階段還沒 spawn）當場滿足舊條件：〔實測〕32 個 workflow 有 25 個真的出現過那個窗口，8 個 ≥3 秒也就是必定被 3 秒輪詢取樣到。取最大值是因為 meta 檔沒過新鮮度閘或目錄讀一半會讓「5 隻完成 2 隻」在縮到 2 隻那一拍變成「2/2 全部完成」。
- **證據**：NotificationEngine.swift:452-459(max)、463-484(terminated)、481-486；WorkflowRunState.swift:24-30；docs/build-log.md:1441-1458、1016-1021
- **付過的代價**：有 —— 這是 T2 四個洞（錯的時刻響、對的時刻閉嘴、沒有在場判斷、沒有預算）的修法核心。`notified` 是全檔沒有任何 `notified = false` 的單向閂鎖，所以誤報一次之後整條 pipeline 真正跑完那一刻一聲都不會有；改用終結狀態後這個洞與誤報一起在結構上消失（一個 run 只會終結一次）。

**14. `latestPhase` 來自 journal.jsonl 的行序（最後一個 `started` 行的 phase），不是從 `metas` 挑一隻；而且它是「最新的那個邊緣」，不是「現在正在跑哪一階段」，nil ＝ journal 沒說。journal 的 `spawns` 是有序陣列，不可以換成 Set 或 Dictionary。**

- **為什麼**：〔實測〕`started` 行**沒有任何時間戳**（key 組合固定是 type/key/agentId/label/phase），而檔案是 append-only —— 行序是那個檔案裡唯一的時間資訊。`metas` 是按 agentId 排序的，而 agentId 是隨機 hex，取 `metas.first` 等於擲骰子：〔實測 2026-09-19〕這台機器 36 個 workflow 有 15 個因此報錯階段，而那個字串就畫在面板上。叫「最新的邊緣」是因為 workflow 的 `pipeline()` 沒有 barrier，多個階段真的會同時在跑，一個單數字串必然丟掉其中一個。階段要**領先**存活閘：`isFresh` 看的 `agent-<id>.jsonl` 比 `.meta.json` 晚落地〔實測 n=343，全部晚，中位 0.092s、最大 0.431s〕。
- **證據**：WorkflowJournalReader.swift:23-33、35-45；AgentTreeBuilder.swift:106-112；AgentTree.swift:41-47；WorkflowPhaseTests.swift:105-132；消費者 SessionRow.swift:205、Dump.swift:189
- **付過的代價**：有 —— 錯的階段已經畫在使用者眼前一段時間（「三項裡唯一使用者今天就看得到的」）。`FinishSignal.swift:46` 現在直接寫著「不是字典序、不是第一個。`latestPhase` 那一課的學費已經付過了」。

**15. `runDuration` 是 run 自己量的時間（磁碟上的 `durationMs` ÷1000），不是「這個 group 被觀察了多久」。分界線釘死：`status` 讀不到 → 完全不發（它是排空的正面證據）；`duration` 讀不到 → 照發，那一格 nil（它只是附屬資訊）。**

- **為什麼**：「app 觀察了多久」那個數字一文不值。〔實測 n=34〕`durationMs` 等於 `timestamp − startTime`、殘差全部在 20ms 內，對照「最早 meta birthtime → 最後一次寫入」差值中位 +0.0s、範圍 −0.1s…+1.7s、0 個離群值，所以它在秒級是誠實的。兩個欄位在同一個檔案裡但角色不同 —— 一個是觸發條件，一個是顯示內容。
- **證據**：WorkflowRunState.swift:13-22、56-58；AgentTree.swift:56-62；NotificationEvent.swift:161-167；NotificationEngine.swift:481-497；docs/build-log.md:1493-1497
- **付過的代價**：有 —— `BatchAlert.duration` 原本就是從「app 第一次看到這個 workflow」起算，2026-09-19 才修掉；`BatchState.firstSeen` 因此沒有讀者，整個拿掉。

**16. T2 出不出聲的裁決順序固定：outcome → 在場 → 預算，預算最後才扣，而且整個裁決放在去重之後；`killed` 的 run 完全不發；T2 絕不聚合，只能 per `workflowId`。**

- **為什麼**：順序就是它的意思：先看這一則本來該不該出聲，再看有沒有人聽得到。被 outcome 擋的、被在場擋的、被去重窗吃掉的、被靜音整批丟掉的，一格都不進帳 —— 否則〔實測〕23:00–08:00 那 54% 的排空會吃掉隔天早上的第一聲。`killed` 那條：中止會把每一隻 agent 折成 `.finished`，純看數字時「你自己停掉的」與「真的跑完了」長得一模一樣。不聚合那條：用全 session 加總（`DataStore.runningAgents`）會在「workflow 排空、但還有 10 隻一般 agent 在跑」時說「整批完成」。
- **證據**：NotificationEngine.swift:290-323、445、487-490；NotificationEvent.swift:118-143；docs/build-log.md:1027-1029、1035-1036、1435-1439
- **付過的代價**：有 —— `runStatus` 這個欄位有自己的 retrospective（2026-09-18_quotamonster_aborted-workflow-phantom-agents.md）：真實資料驗證時抓到一個被 TaskStop 停掉的 run 顯示成「5 隻執行中」。另外修的順序不能顛倒（先修觸發點、再裝在場閘）—— 加了在場閘之後會響的那幾聲**剛好都是你在座位上**的時候，降低音量的同時提高了每一聲的殺傷力。


**37. 一般 Agent subagent 的「在跑」是**推定**的，必須有自己的狀態、
自己的誤差數字，而且畫面上分得出來。**

- **為什麼只能推定**：〔實測 2026-09-22〕workflow subagent 有 `journal.jsonl`
  （`started` / `result` / `failed` / `launched`），狀態是**讀到的**；
  一般 Agent subagent 只有 `.meta.json`，欄位是 `agentType` / `description` /
  `toolUseId` / `spawnDepth` / `requestShape` —— **一個狀態欄位都沒有**。
  唯一還在動的是它的 transcript（實測一隻在跑的 agent 五秒內 286KB → 306KB）。
- **窗口 120 秒是量出來的**：〔實測，32 個 agent transcript／4,687 個相鄰寫入間隔〕
  中位數 0.4s、p90 4.5s、p99 57.6s；>60s 佔 0.96%、**>120s 佔 0.45%**、>180s 佔 0.24%。
  也就是約 **0.45%** 的觀測時刻會把「還在想」誤判成「停了」。
- ⚠️ **兩個方向的錯不對稱**：少報（還在想卻說停了）可接受；
  謊報（被殺掉卻說還在跑，最長一個窗口）是付出去的代價。
  這個 repo 原本選「寧可少報，不要謊報」，2026-09-22 使用者拍板換成
  「代理量測 + 誤差已知」—— 條件是誤差量得出來、畫面上分得出來。
- ⚠️ 所以它是**獨立的 `AgentRunState.likelyRunning`**，不與 journal 讀到的
  `.running` 合併。面板那顆點降到 `opacity(0.45)`，`--dump` 印「（推定在跑）」，
  而「N 隻在跑」後面接「其中 M 隻是由 transcript 活動推定的」。
- ⚠️ **推不出來時留在 `unknown`，絕不猜 `finished`。** 「沒有在寫字」不是
  「做完了」的證據（規矩：不存在 ≠ 那個狀態不成立）。有測試逐一釘住
  「一般 agent 永遠不可以被標成 finished 或 running」。
- 〔查過〕`NotificationEngine` 不消費 `runState`，所以 T2 的行為完全沒有變。

### 通知層 T1／T2／T3

**17. 交給 osascript 的參數陣列裡，使用者控制的字串前面一定要有 `--`；標題永遠是常數 "QuotaMonster"，絕不讓使用者字串進到標題。任何要進 `Process.arguments` 的字串在讀進來那一層就 strip NUL 並截 200 字。**

- **為什麼**：⚠️ **這一條原本的歸因是錯的，2026-09-19 修正。** 原文寫「專案名就是 cwd 的最後一段」，但〔讀碼確認〕`NotificationPresenter` 把專案名送進 **subtitle（item 3）**，而 `--` 保護的是 **body（item 1）** —— 專案名永遠到不了那一格。item 1 真正的來源是 `WaitingContextReader` 從 transcript 尾端撈出來的 headline（`AskUserQuestion` 的問題文字、工具的 `description`）。**那是比目錄名更糟的威脅模型**：目錄名需要本機檔案系統控制權，transcript 文字只要一個被 prompt injection 的 agent、或一個惡意 MCP server 的工具描述就寫得進去。⚠️ 這個誤植本身就是攻擊面 —— 下一個人照舊註解去追「專案名 → RCE」，會發現專案名落在別的保護機制底下，於是判定註解過期而把 `--` 刪掉。〔實測〕`-eproperty p:(do shell script "…")` 是一個合法的 APFS 目錄名，兩種形式（無斜線的目錄名、含斜線的絕對路徑）都能觸發。走 `on run argv` 不足以擋 —— osascript 自己的 getopt 會把它當成另一個 `-e` 片段，而 property 的初始值在載入時就求值。已在本機建出該目錄、讀回 basename、餵進去並取得執行；加 `--` 之後同一個 payload 與另外五個敵意名稱全部無效。NUL 那半條：〔實測〕帶 NUL 的參數讓 `Process` 丟出 Swift do/catch 接不到的 ObjC 例外，app 當場死，而 `JSONSerialization` 會把 `~/.claude` 底下 JSON 裡的 `\u0000` 老實解成 NUL scalar 交出來。
- **證據**：OSAScriptNotifier.swift:10-16、26-36、53-59；WaitingContextReaderTests.swift:151-160；docs/build-log.md:926-927
- **⚠️ item 3 是被另一個機制保護的，不是被 `--`**：〔實測〕subtitle 位置放同一個 payload，**就算拿掉 `--` 也不會執行** —— osascript 走 BSD getopt（遇第一個非選項就停掃），而 item 2 的常數標題 `QuotaMonster` 正好是那個非選項。反證：把 item 2 換成 `-i`，item 3 的 property 就 fired。**所以「標題永遠是常數」是承載安全性的**，不只是署名問題。⚠️ 但它擋 item 3 靠的兩層（停掃／污染編譯）都是**偶然**的；`--` 才是設計出來的那一道。
- **⚠️ 非零離開碼不代表 payload 沒執行**：〔實測〕注入成功時 osascript 反而回 1（argv 被吃掉一格，之後報 `Can't get item 3 of …`）—— 一次成功的 RCE 藏在一則錯誤訊息底下。驗證那條防線只能看副作用，不能看離開碼。
- **付過的代價**：有 —— 一份 retrospective（2026-09-18_quotamonster_silent-failures-in-the-alert-path.md 第 1 條），且是在本機真的取得執行之後才定案的。⚠️ 但計畫書要求的「餵真 payload 並斷言檔案沒被建出來」那則測試**至今不存在**（見 overturned）。

**18. 浮窗裡的 SwiftUI 內容一定要包在覆寫 `acceptsFirstMouse` 的 `NSHostingView` subclass 裡；NSPanel 的設定順序與四個預設值不可動（先 `isFloatingPanel` 再 `level = .statusBar`、`hidesOnDeactivate = false`、`collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`、用 `orderFrontRegardless()`、frame 夾在 `visibleFrame` 裡）。**

- **為什麼**：〔實測〕`NSHostingView.acceptsFirstMouse` 預設 false，非前景浮窗（背景 app 的浮窗就是這種）裡的按鈕會吃掉第一次點擊 —— 點了沒反應、再點一次才有，沒有錯誤也沒有 log。`isFloatingPanel = true` 會把 level 覆寫成 `.floating`(3)，所以一定要在 level 之前設；`hidesOnDeactivate` 預設 true，對 accessory app 而言「非前景」是常態，窗會當場消失；預設 collectionBehavior 把視窗綁在建立它的 Space，使用者在全螢幕 app 裡時它從來不出現，一樣沒有錯誤也沒有 callback；`.statusBar` 是 25、選單列 24，不夾在 visibleFrame 裡會畫到選單列上面；`makeKeyAndOrderFront` 會搶走正在打字的鍵盤焦點。
- **證據**：AlertPanelController.swift:5-12、14-24、74-76、144-165；docs/build-log.md:928-929、1099-1106
- **付過的代價**：有 —— 同一份 retrospective 的第 3、4 條。

**19. 去重鍵一定是穩定字串，絕對不可以用 `hashValue`；一次等待事件的身分是 `(sessionId, statusUpdatedAt)`，不是「看到它從非等待變成等待」；第一次觀測到的等待不發，而且沒有見證過它進入等待的 session 連 T+300 的重推都不排（`announced` 閘）。**

- **為什麼**：Swift 的 `Hasher` 每個行程重新設種子，存到磁碟的 hash 下次啟動就對不上，去重會**安靜地**停止運作。episode 用 `statusUpdatedAt` 而不是轉換：三秒輪詢常常整拍錯過中間那段 busy（回答完一個問題、Claude 馬上又要求批准工具，`waiting → busy → waiting` 可能發生在同一拍之內），靠轉換判斷會讓實際使用上最常見的那一種等待完全不發通知〔原文未標，看起來是推論〕。`announced` 閘讓「啟動時對著三個 session 同時尖叫」在結構上不可能發生，而開發期間 `make_app.sh` 會不斷重啟 app；沒有它的話「不發」只是延後五分鐘，而且冒出來的那一扇會被當成重推、連聲音都沒有。
- **證據**：NotificationEvent.swift:13-34；NotificationEngine.swift:144-159、377-391、367-369；docs/build-log.md:969-971、983-995
- **付過的代價**：有 —— 這條規則取代了「把已通知過的等待存到磁碟」那個方案，後者一度實作過，後來整個拿掉。

**20. `mutedUntil` 一定要存磁碟；60 秒去重窗、4 秒合併窗、`SoundBudget`、以及「已經通知過哪些等待」一律不存。判準是三問：是不是使用者直接下的指令、是不是抑制方向、時間跨度有沒有長過 app 的一次執行。**

- **為什麼**：`mutedUntil` 不是觀測值，是使用者直接下的指令，而它自己講明的跨度（「靜音到明早」約 12 小時）遠長於一次執行 —— 丟掉它 = 在使用者明確要求安靜的時段裡出聲。反過來，存下來的**抑制**是危險的那個方向：一個「已經跟你講過 X 了」在長時間停機後可能吞掉一個真正的新事件。
- **證據**：NotifyState.swift:1-31；SoundBudget.swift:11-15；DataStore.swift:129-133、169-171；docs/build-log.md:1059-1071
- **付過的代價**：有 —— `UsageHistory` 已經為「上一筆放在記憶體裡」付過代價：〔實測〕app 重啟三次加兩支診斷指令，就寫出四行一模一樣的紀錄。通知層的版本大聲得多：重啟時三個 session 在等，就是三個浮窗加三聲。


**41. 同名的 session 要接上唯一鍵。「兩列一模一樣」在使用者眼裡是壞掉，不是資料。**

- **不是邊緣案例**：〔實測 2026-09-22〕**5 個存活 session 裡有 4 個落在同名配對中
  （80%）** —— fork／resume 同一段對話會沿用同一個 `aiTitle`，那是常態。
- 註冊表的 `name`（`usage-ff` / `usage-c9` / `rl-b5`）本來就唯一，接上去就分得開。
- ⚠️ **唯一鍵本身就是顯示名時不要接**，否則會變成「A · A」。實測會發生：
  `nameSource == "auto"` 的 session，它的 registry name 就是顯示名，
  而旁邊那個的 `aiTitle` 剛好是同一個字串。
- ⚠️ 判準必須**一次算完整批** ——「同名」是整批的性質，一個一個算看不出來。
  而且 `--dump` 要與面板用同一套（規矩 28）。
- 這是 2026-09-22 引入 `aiTitle`（規矩 35）時造成的回歸。當時我說「得先量清楚
  同名多常見」就沒動 —— 結論是：**那種時候該去量，不是該延後。**

**42. 我們寫進使用者磁碟的每一個檔案都要有上限，而且清理者要與寫入者是同一個。**

- **漏掉的那一個**：`usage-history.jsonl` 與 `watch-log.jsonl` 都有 30 天保留，
  但 `trace-usage.log` **一個位元組都不會被清掉**（實測約 150KB／天）。
  加它的時候沒想到 —— 而它是唯一一個由 **bash** 寫的。
- ⚠️ **清理不可以交給 app**：那個檔案是 wrapper 在 append，而 app 的 prune 走
  tmp + rename 換檔 —— 會把正在寫的那一行丟掉，而且兩個寫入者搶同一個檔。
  所以由 wrapper 自己在寫之前看一眼大小（`stat` 每次渲染一次，成本可忽略），
  超過 1MB 就只留後半。
- ⚠️ **「沒超過上限時不要動它」需要用 inode 測，不能比對內容**：
  `tail -c 512K` 對一個小檔不會損壞任何東西，所以「一律砍」這個突變在內容比對上
  照樣過（實測紅 0 則）。差別在有沒有**重寫**。與安裝腳本那則同一招。

### 完成訊號

**21. 「又動起來了」的唯一可信證據是 transcript 的 mtime 前進，不是 `LiveSession.isWorking`。`FinishCaption.prune` 的簽章刻意不接受 `[LiveSession]`。**

- **為什麼**：註冊表的 status 是黏著的 ——〔實測〕回合結束後七分鐘一直回報 shell、另一個 session 講完 29 分鐘仍報 busy，而 `isWorking` 在 `.busy`/`.shell` 就是 true。拿它當證據，標記會在產生後的第一拍就被清掉：丁香紫一次都不會亮，而且**所有單元測試都會綠**（測試餵的是手捏的 LiveSession）。
- **證據**：SessionFinish.swift:56-71；DataStore.swift:250-256；docs/build-log.md:1283-1291、1249
- **付過的代價**：無 —— 顯示規格原本就是這樣寫的，被計畫書自己標成「差點犯的那個致命錯」，沒有出貨。

**22. 沉澱窗不是偵測。安靜只決定「何時去看」，決定「完成沒」的是 transcript 尾端那一則的 `stop_reason`；沉澱窗 90 秒不可往下砍；宣告完成前必須確認那一則 end_turn 之後沒有任何真人訊息。**

- **為什麼**：〔實測〕13,733 個回合進行中的間隔裡有 105 個（0.76%）超過 90 秒（長 Bash 66.7%、模型想很久 20.0%、使用者在打字 11.4%），但那些時點往回看到的**全部是 tool_use**，誤報 0 次 —— 這個分工讓「跑 40 分鐘的 Bash」在架構上就不可能誤觸發，只多付一次 37µs 讀取。90 秒不可砍：〔實測 n=153〕兩行式 end_turn（thinking 然後 text）的間隔中位 12.2 秒、最大 51.8 秒，窗縮到 45 秒就會在 thinking 那一行到期而使用者眼前還沒有任何文字；〔實測，現場直接觀測〕一個跑到一半的 session 最長安靜 83.9 秒。「之後不可有真人訊息」：〔實測〕479 個以真人訊息為起點的間隔裡有 6 個（1.25%）超過 90 秒（最長 623 秒），沒有這一段那 6 次會在使用者剛按下 Enter 時宣告「講完了」—— 它同時免費吃掉 Esc 中斷那道閘。
- **證據**：CompletionTracker.swift:11-18、24-31；TurnCompletionReader.swift:103-114；docs/build-log.md:1254-1273
- **付過的代價**：無（但計畫書 1376 行那句「沉澱窗本身就是偵測」至今沒改，見 overturned）

**23. 「真人訊息」全 repo 只有一份定義：`type == "user" && isMeta != true && content 裡沒有 tool_result`，而且 `content` 的字串與 list 兩種形狀都要收。**

- **為什麼**：〔實測 2026-09-19〕字串型裡有 93 則 `isMeta=true`（skill caveat／圖片占位／slash command 展開／agent 間訊息），而貼截圖的真人訊息一定是 list。「字串＝真人、list＝harness」這個直覺**兩個方向都錯**：照它寫會吞掉約四分之一的真人輸入，又會把 93 則 harness 訊息當成真人。
- **證據**：TurnCompletionReader.swift:123-154；docs/build-log.md:1269-1273
- **付過的代價**：無。⚠️ 但兩處母數對不上（見 overturned），引用時只引「兩種形狀都要收」這個判準，不要引那組數字。


### 顯示：選單列與面板

**24. 黃／琥珀在這個 app 裡只代表「要你輸入」。額度色階（`QuotaPalette`）不得使用任何黃色，只有藍 → 綠 → 紅；沒有可信讀數就不上色（`quotaTier` 回 nil，圖示走單色）。唯一被授權的例外是面板的 ctx 壓力細條（70% 黃／90% 紅），因為它抄的是使用者自己狀態列腳本的色階。**

- **為什麼**：整個 app 裡唯一有時限的訊號就是警示；把它的顏色拿去表示額度多寡會把那個訊號稀釋掉（使用者 2026-09-18 明確指定）。不上色那半條：綠色代表「還很寬裕」，對一個你自己都知道不可信的數字塗綠色是說謊 —— 這同時保留了第三種視覺狀態「單色＝這個數字不可信」。收合那一行的失敗用紅（借「壞消息」的既有語彙）、狀態不明用 secondary，一律不可以用琥珀／黃。
- **證據**：GlyphState.swift:3-8、87-92；QuotaPalette.swift:12-27；GlyphRenderer.swift:22-26；SessionRow.swift:180-199；docs/build-log.md:1612-1617
- **付過的代價**：無（使用者指定，不是事後補的）。⚠️ 但 `GlyphRenderer.swift:28-33` 至今留著一段說 `tight` 是黃色的過時註解，見 overturned。

**25. 「琥珀（有人在等你）」與「丁香紫（剛完成）」同時出現，要在型別上不可表示 —— 做成 `GlyphState.creatureGlow` 這個 computed property，不在管線某處降級。丟掉不是排隊：警示結束後不補眨眼。染了丁香紫就不可以走 template rendering；退色版是混向墨色，不是降不透明度。**

- **為什麼**：靠每個呼叫端記得判一次，兩份判斷遲早會在某個邊界上漂開。AppKit 的 template 只看 alpha channel，會把顏色整個丟掉 —— 丁香紫會**安靜地**變成墨色，所以 `usesTemplateRendering` 有第三個條件。alpha 0.45 已經被 `freshness == .expired` 佔走了，再用一次會變成兩套衰減疊在同一個通道上，沒有人讀得出來；而完成是有時限的那一個，所以它壓過過期降調。
- **證據**：GlyphState.swift:102-112、122-137；SignalPalette.swift:32-41；GlyphRenderer.swift:69、184-194；FinishSignal.swift:14-16；docs/build-log.md:1330-1337
- **付過的代價**：無（template 陷阱在寫的時候就被辨識出來並寫成 `exit(1)` 的自我斷言）

**26. `GlyphRenderer` 與 `StatusItemController.dimmed` 裡不得出現任何仿射變換 API（NSAffineTransform / Foundation.AffineTransform / CGAffineTransform 都算）；驗收一定要跑 `rm -rf .build && swift build -c release`。**

- **為什麼**：Swift 6.3.3 / CommandLineTools 在 `-O` 下，只要有一個函式對路徑套用仿射變換，swift-frontend 就會在 SILCombine 階段 segfault（signal 10/11）；debug 建置完全正常。有效的做法是根本不用 transform，依姿態直接算出最終座標。今天 grep 全 Sources 只剩註解裡那一行提到 transform 的名字。
- **證據**：GlyphRenderer.swift:198-206；StatusItemController.swift:202-204；docs/build-log.md:451-452、1124-1126；~/.claude/retrospectives/2026-09-18_quotamonster_silcombine-crash.md
- **付過的代價**：有 —— 三種 transform 型別全試全炸；`@inline(never)` 的「看起來過了」是增量建置快取的假象，清掉 `.build` 後照炸；把 switch 移進 Core 也炸。retrospective 的結論是「這次浪費最多時間的就是相信了一次增量建置的成功」。代價是 5° 前傾改用冠部水平位移近似。

**27. 面板高度是同步估算出來的，不用 `GeometryReader` 量；展開 popover 之前一定要自己算尺寸並指派給 `popover.contentSize`，並夾在 `screen.visibleFrame.height - 24` 以內。**

- **為什麼**：量的那條路（preference + onPreferenceChange）要等下一輪 runloop 才有值，而 `StatusItemController` 在展開那一瞬間就要拿 `fittingSize` 去設 contentSize —— 第一次展開會拿到還沒算好的高度，面板縮一半。不指派 contentSize 的話 `NSPopover` 會一直用 320×320 的預設值，SwiftUI 不會改（〔實測〕等 1.5 秒仍是 320×320），後果有兩個而且都看得見：面板被壓扁（內容只剩 345pt）、面板往上長進選單列（頂緣 y=953 對選單列底緣 y=923，重疊 30pt；修正後回到 y=928）。
- **證據**：PanelView.swift:326-334、349-382；StatusItemController.swift:246-266；~/.claude/retrospectives/2026-09-18_quotamonster_nspopover-sizing.md；docs/build-log.md:445-449、1609-1610
- **付過的代價**：有 —— 使用者回報面板上緣蓋到選單列。可能原因至少四個而且都合理，所以先寫了 `--probe-popover` 把數字印出來才動手（用猜的會修錯地方）。


**39. 每日長條圖的一天切在 `resetsAt` 的鐘點，不是午夜；而且「不知道」不可以
畫成 0%。**

- **為什麼不是午夜**（使用者 2026-09-22 拍板）：七根恰好把窗口切成七等份，
  換來一個自我驗證的性質 —— **七根相加恰好等於面板的 7 天已用**〔實測 30% = 30%〕。
  ⚠️ 這個性質只在**七根都說得出數字**時成立；有 unknown 時本來就對不上，
  所以 `--dump` 那句「不等就是有 bug」要加條件，否則它會叫人去追不存在的 bug。
- **為什麼可以差分**：〔實測 2026-09-22〕`7d` 在同一個窗口內單調遞增。
  我一度量到它下降並判定「不能差分」—— 那次量測在修好「舊數字被當成新讀數」
  之前，而且 `7d` 與 `5h` **同時**下降，那是帶著舊值的 payload 的指紋。
  ⚠️ 修復後 0 次下降，但**只有 9 個相鄰配對**。單調是**前提不是保證**，
  所以真的下降時回 `.unknown`，不畫一根負的。
- **為什麼稀疏取樣剛好夠**：`shouldRecord` 只在數字變了才寫，而數字只在你用
  Claude Code 時才變 —— 每個台階都抓到了。稀疏不是缺陷，是這個訊號的形狀。
  ⚠️ 由此推論：**沒有取樣點 = 沒有變過 = 仍然是 0**，不是「不知道」。
  「有沒有在看」完全交給心跳那一關，`value(at:)` 不該再猜一次
  （這一條是突變驗證抓到的：原本回 nil 並判 unknown，改成 `?? 0` 一則測試都沒紅）。
- ⚠️ **只有「邊界」需要被看著。** 某天中間短暫沒開不影響那天的總量（那段用量
  會出現在回來後的第一個讀數裡）；錯的是**跨日界**沒開 —— 那會把用量記到隔壁那天。

**40. 面板印給使用者照做的任何指令，必須在**那個使用者手上**真的存在。**

- **代價是實測的**：〔code review 2026-09-22〕空狀態提示寫死
  「`bash scripts/install_statusline_tee.sh --apply`」—— 那是 repo 相對路徑，
  而**下載 DMG 的人沒有 repo**（`.app/Contents/Resources/` 當時只有 `AppIcon.icns`）。
  那是新使用者**唯一**會看到的指引，而它不可執行。
- ⚠️ 前一天我才修好「面板在空狀態時什麼都不說」這個洞。修的是**有沒有說話**，
  沒有檢查**說的話做不做得到** —— 兩者是不同的問題，而後者更容易被當成已經解決。
- **修法**：`make_app.sh` 把使用者真的會跑的那兩支腳本打進
  `Contents/Resources/scripts/`（目錄結構要保留，安裝腳本用 `$(dirname $0)/..` 找 ROOT），
  由 App 層解析絕對路徑餵給 Core。**Core 不可以自己編那個字串** —— 它不知道 bundle 是什麼。
- ⚠️ **只打包使用者會跑的那兩支。** 第一版用 `*.sh` 全複製，`make_app.sh`、
  `make_dmg.sh` 與三支測試腳本都進了使用者的 .app —— 沒有理由的表面積，
  而且會讓人以為那些是給他用的。

**43. 同一個事實在兩個地方必須用同一套語彙 —— 選單列的兩條弧各自上色，與面板的三條進度條一致。**

- **為什麼**：〔使用者回報 2026-09-22〕選單列上 5 小時燒到一半（綠）、7 天還剩
  三分之二（藍）的時候，**兩條弧都是綠的**。原因是上色只問 `GlyphState.quotaTier`，
  而它取的是兩個窗口裡比較緊的那一個。那個取法對「整體現在多緊」是對的，
  對「這條弧代表的窗口多緊」是錯的 —— 一個值被拿去回答兩個問題。
  結果是**選單列看起來像 7 天也快沒了**，而面板同一時刻畫的是綠 + 藍。
- **修法**：`fiveHourTier` / `sevenDayTier` 各自判，`quotaTier` 留著只回答
  `usesTemplateRendering` 那個是非題（兩條弧的 nil 條件相同，所以等價）。
- ⚠️ **Core 的測試擋不住這個 bug。** 兩個 tier 算對了，繪製端照樣可以只拿其中一個
  去畫兩條弧。抓得到的只有 App 層的像素測試：渲染一個兩條弧落在不同分級的狀態，
  量兩條中線上有顏色的像素的平均色相，斷言相差超過 60°。
  〔突變驗證〕把 `tints.seven` 改回 `tints.five`，兩條色相差 0.006° → 紅。
- ⚠️ 配對的第二則同樣重要：**兩條落在同一級時顏色必須一樣**（差 < 2°）——
  否則「永遠給不同顏色」的假修法會讓第一則過關。
- **證據**：GlyphState.swift（`fiveHourTier` 檔頭）、GlyphRenderer.swift:`drawGauges`、
  Tests/QuotaMonsterAppTests/GlyphRendererTests.swift（`eachArcCarriesItsOwnColour`）、
  RenderStates 的 `21-arcs-differ` / `22-arcs-differ-flip`

**44. 讀設定要發生在 `DataStore.init`，不可以發生在 `start()`。**

- **為什麼**：〔實測 2026-09-22〕四個 `DataStore` 建立點裡有**三個**不走 `start()`
  —— `RenderPanel`、`RenderPreferences`、`ProbePopover` 都只呼叫 `refresh()`，
  而讀偏好檔在 `start()` 裡。於是這三支診斷**從來沒有反映過任何偏好**。
- **後果不是「少一個功能」，是驗證整個變成安慰劑。** 最糟的是 `--render-prefs`：
  它的全部工作就是畫偏好視窗給人看，而它畫的一直是預設值 ——
  它甚至在 stdout 印「⚠️ 這張圖用的是**目前實際的偏好檔**，不是合成資料」。
  那同時踩到規矩 28：診斷**主張**了一件假的事。
  〔驗證〕把偏好檔設成 `chartStyle: cumulative` + `morningHour: 10` 再渲染，
  修好前畫出「每日長條 / 08:00」，修好後畫出「累計曲線 / 10:00」。
- ⚠️ **修法不是在那三個地方各補一行** —— 那只是把同一個洞留給第四個建立點。
  讀檔移進 `init`（`init(home:)`，測試傳假家目錄），
  「建得出 `DataStore` 就一定有偏好」才是結構上的事。`start()` 仍然再讀一次，
  因為 init 到 start 之間有可能被另一個行程改過。
  〔突變驗證〕拿掉 init 裡那一行 → `chartStyle` 回 `.daily`，紅。
- 規矩 28 講的是「畫的東西要跟註解說的一樣」，這一條講的是
  「**輸入**要跟真實情況一樣」。兩者都會讓診斷變成安慰劑。
- ⚠️ 診斷可以**覆寫**設定，但不可以**改掉**設定檔：`--chart daily|cumulative`
  走 `setPreferences(_:persist: false)`，而且把實際採用的樣式寫到 stderr。

**45. 單調性的前提壞掉時要**標出來**，不是夾成單調，也不是照畫。**

- **為什麼**：7d 是這個窗口的累計值，同一個窗口內不可能變小。所以一個比先前最高值
  還低的讀數，與那個最高值**其中之一是錯的，而我們不知道是哪一個**。
  照畫 → 畫出一條定義上不可能的下降累計線；夾成單調 → 把壞資料悄悄改成好資料，
  而且從此看不出來。兩種都是在說謊，方向不同而已。
- ⚠️ 判準是「比**先前最高**低」不是「比前一點低」。〔實測 2026-09-22 本機歷史檔，
  窗口內 66 筆〕09-20 15:25 是 19，09-21 19:30 掉到 0，接著 13、14…… 到 20:40 才回到 19 ——
  中間那串每一個都與那個 19 衝突，只比前一點的話它們全部會被當成正常的上升。
- ⚠️ 圖例寫「**淡色段**」不寫「虛線」：均速那條斜線本身就是虛線，寫「虛線＝讀數互相矛盾」
  會直接指到它身上。第一版就是這樣寫的，渲染出來才看見畫面上同時有兩條虛線。
- **證據**：DailyUsage.swift（`CumulativePoint.contradictsEarlier`、`cumulativeLegend`）、
  CumulativeChart.swift:`segments`、DailyUsageTests.swift（`CumulativeTests` 後六則）

**46. 本機編得過不代表 CI 編得過 —— 而且差異是靜默的，只會在 CI 第一次跑才爆。**

- **為什麼**：開發機的 `xcode-select` 指向 CommandLineTools（Swift 6.3.3），
  CI 的 macos runner 用完整 Xcode（Swift 6.2.3）。**沒有任何本機指令看得到這個差**。
- **付過的代價，兩次，都是型別推論**：
  1. `StatusLineCachePrunerTests` 把 `Int` 當 `TimeInterval` 用，6.3.3 過、6.2.3 不過。
  2. 〔2026-09-22〕`cos(a)` / `sin(a)` 對一個 `CGFloat` 是**歧義**的 ——
     arm64 上 `CGFloat == Double`，於是 CoreGraphics 的 `cos(CGFloat)` 與
     `_math` 的 `cos(Double)` 兩個多載一樣好。本機過、CI 紅。
- **怎麼避開**：算術一律先 `Double(...)` 轉明確；能不用三角函式就不用
  （那一則測試改成「先平均 RGB 再換算一次色相」，**前提是一條弧只有一個顏色**，
  而那個前提在這裡本來就成立）。
- ⚠️ **加 CI 的價值有一半在這裡**，不是在「跑一次測試」——
  本機的 632 則全綠，CI 連編都編不過。

**47. 增量讀檔的身分是 `(inode, offset)`，不是路徑；而且「沒有新東西」與「讀不到」不可以塌縮。**

- **為什麼**：transcript 在 compact / fork / `--resume` 時會被**整個重寫**。它可能變短（size 測得到），
  也可能**大小一樣而內容整個換掉**（寫新檔再 rename 上去）—— 後者 size 與 mtime **都測不出來**，
  只有 inode 測得到。認錯了就是從一個錯的位移往下讀，交出半行垃圾。
  這是 `~/CLAUDE.md`「mtime 是什麼時候寫的，不是內容什麼時候量的」在增量讀取上的落點。
- ⚠️ **半行要留著，不可以丟也不可以重讀。** 既有的 `WaitingContextReader.tail` 從尾端抓 64KB 並
  **丟掉第一個換行之前的東西**（它切在半行上）—— 從記住的 offset 往前讀時第一個 byte **就是**行首，
  照抄那個行為會每讀一次就靜靜吃掉一筆記錄。反過來，讓 offset 停在行首、半行留在檔案裡下次重讀，
  會讓那半行**被讀兩次**（「bb」+「bb\n」變成「bbbbbb」）。正解：bytes 一旦拿走就算進 offset，
  未完成的那截另外暫存。〔兩個方向都是測試抓到的〕
- ⚠️ `FileHandle.readToEnd()` 在**已經在檔尾**時回 `nil`，不是回空的 `Data`。
  把那個 nil 當成讀取失敗，「檔案沒長」與「空檔案」兩種**正常情況**都會變成「讀不到」——
  也就是把正面證據講成「我們沒看到」。
- ⚠️ **這組數字被修正過一次，而修正的原因本身就是一條教訓。**
  第一版報的是 1004 → 71.8 毫秒（14 倍）。〔code review 2026-09-22〕`--bench-refresh`
  當時**沒有排乾 autorelease pool**，每拍 RSS 長約 5MB —— 也就是那支量尺自己在漏。
  補上 `autoreleasepool` 之後，**把同一支量尺移植回改造前的版本**重新量，
  得到 740 → 62.8 毫秒（11.8 倍）。
  ⚠️ **量尺漏水的時候，前後兩個數字會一起變形，而比值看起來仍然很漂亮** ——
  這種錯不會讓結論反過來，只會讓每一個數字都不能引用。
- **代價是量到的**：改造前 `--bench-refresh`（已修正的那一版）量到 `DataStore.refresh()` 穩態中位 **740 毫秒**
  （一拍的預算是 3000），因為 `AgentTreeBuilder.toolUseIds` 每 3 秒把整份母 transcript
  `String(contentsOf:)` 讀進來再逐行處理。改成增量之後：**62.8 毫秒**，第一拍（補課）399 毫秒。
- **成本拆在哪裡**〔實測 2026-09-22，最大的兩份 transcript〕：讀檔 21.6 / 11.0 ms、
  **切行（`String.split`）278.5 / 222.8 ms（68–78%）**、JSON 解析 57.0 / 94.0 ms。
  ⚠️ **最貴的是切行，不是 JSON** —— 多 MB 的 Swift `String` 做 `split` 要走 Unicode 字素邊界
  （改用 `Data` 切只要 72.5 / 51.8 ms）。
- ⚠️ **這一條原本寫「I/O 只有 0.014 秒，97% 是 JSON 解析」，那個歸因是錯的**，
  而且它是一個「沒有自己驗過、卻寫成〔實測〕」的數字（code review 2026-09-22 實測推翻）。
  結論方向沒變（要省的是**逐行的工作**，不是 bytes），但理由換了。
  ⚠️ 一個**看起來很精確**的數字最不會被人再去驗 —— 那正是規矩 5 最貴的違反方式。

**48. 讀到的終端狀態勝過活動代理量測，而且兩者不可以互相推導。**

- **為什麼**：一般 Agent subagent 現在有兩種證據：`AgentActivity` 的「transcript 最近還在被寫」
  （**代理量測**，規矩 37）與母 transcript 裡讀到的 `<status>`（**量測**）。
  優先序固定：讀到下場 → `.finished` 並帶 `AgentNode.outcome`；讀不到才退回推定；
  推不出來維持 `.unknown`。形狀與 workflow 那邊完全一樣（`terminated ? .finished : journal…`）。
- ⚠️ **`outcome == nil` 是「沒讀到」，不是「順利結束」。** `AgentTally` 把它算進「狀態不明」
  而不是「已完成」—— 第二節拒絕 2 講的就是這件事。實測 18.5% 的背景 agent 從來沒有終端記錄，
  所以那一格不是理論上的。
- ⚠️ **同一段文字在兩個畫面上只能有一份實作。** 〔code review 2026-09-23〕簡易版面
  自己寫了第二份倒數措辭，兩份在**三個方向同時漂開**：字彙（「已重置」vs「重置時間已過」）、
  **契約**（`OutlookCaption.fiveHour` 的檔頭把 `resetText` 的集合寫死，而它的 `.exhausted`
  分支 `guard resetText.hasPrefix("剩 ")` 就建在那個集合上 —— 餵集合外的字串進去，
  「N 後恢復」會**安靜地消失**）、**時鐘**（`Date()` vs `store.lastRefresh`，同一個倒數差一分鐘）。
  收進 `ResetCaption`（Core，有測試）之後，原本那份改法會讓 13 則測試變紅。
  ⚠️ 附帶抓到一個真的 bug：`mins > 0` 把「還剩 30 秒」講成「重置時間已過」，
  而 `WindowExpiry.accepts` 保證窗口還活著 —— 於是窗口最後 60 秒會印出
  「重置時間已過 · 估 79%」，同一句話的兩半互相否定。
- ⚠️ **搬走一個約定的時候，要把讓它誠實的那個出口一起搬。** 同一次 review：
  簡易頁把 `OutlookCaption` 的箭頭搬過去了，卻把 `.help(evidence)` 留在完整面板。
  而 `arrow` 刻意讓「持平」與「資料不夠」都畫成空字串，`evidence` 就是它的付款方式
  （`OutlookCaption` 自己的檔頭寫著「說不出最近節奏時要**講出來**，不是安靜地省略」）——
  少搬那一行，`BurnRefusal` 的八種具名拒絕在那一頁全部到不了畫面。成本 0pt。
- ⚠️ **收合那一行的用詞與顏色必須與 `WorkflowTally` 完全一樣**（已完成 / 失敗 / 已停止 / 狀態不明，
  失敗紅、不明 secondary、其餘 tertiary）。同一件事兩套語彙，這個 repo 已經為它付過一次代價（規矩 43）。

**49. 放大的選單列標記一定要包一層 `NSImage` 重畫，不可以 `Image(nsImage:).resizable()`。**

- **為什麼（邊緣）**：〔實測 2026-09-22〕`ImageRenderer(scale: 2)`、132pt 目標，沿中線掃描：
  `.resizable()` 有 **24 個過渡像素**（邊緣糊掉），包裝重畫是 **0 個**。
- ⚠️ **為什麼（顏色，這個更嚴重）**：來源若 `isTemplate == true`，SwiftUI 會用
  `foregroundStyle` 把**兩條弧的顏色整個吃掉**（實測紅／藍變成一片單色）。
  而 `GlyphState.usesTemplateRendering` 在「**沒有讀數／過期**」時正好是 true ——
  **這個陷阱剛好落在最需要誠實的那一格**。包裝之後 `isTemplate == false`，顏色原封不動。
- **作法**：`NSImage(size: N, flipped: false) { r in source.draw(in: r); return true }`。
  出貨的那顆 renderer 畫進一個大畫布，**不是第二份畫法** ——
  這個 repo 為「手工重畫一份」付過兩次代價（mockup 的 line cap 與單色 bug）。
- ⚠️ **也不可以改用 `IconRenderer`。** 它畫的是 app 圖示：`innerLitFraction` 寫死、
  永遠畫一隻 agent、用自己的 hex 三元組而不是 `QuotaPalette`，檔頭自己寫著
  「不是某個當下的讀數」。拿它當主角＝在使用者找真讀數的地方畫一個很像真的假讀數。
  它證明的只有一件事：這套幾何從 22pt 放到 1024px 是乾淨的。

**50. popover 開著的時候改版面，下一跳才可以指派 `contentSize`。**

- **量到的**〔實測 2026-09-22，`--probe-panel-switch`，n≥2、兩個方向〕：

  | | fittingSize | contentSize | window |
  |---|---|---|---|
  | 穩定（完整） | 595 | 595 | 621 |
  | 同一個 tick | 595（**舊值**） | 595 | 621 |
  | `main.async` 一跳之後 | **300（新值）** | 595 | **326（也跟上了）** |
  | 100ms / 1.5s 之後 | 300 | 595 | 326 |

- **一跳就夠。** 不要用計時器賭，也**不要在 Core 複製一份高度計算** ——
  那會變成規矩 2 的第二份字面量，而且它會與真正的版面無聲地漂開。
- ⚠️ **`window` 那一欄自己就跟上了**，所以視覺上不補指派也是對的。
  補是為了讓 `contentSize` 這個屬性不要過期 —— `panelSize()` 的螢幕高度夾限（規矩 27）會去讀它。
- ⚠️ 這一條之所以有答案，是因為**在寫程式之前先量**：當時 `PanelStyle` 還不存在，
  診斷就先用一個 `@State` 在既有的兩個 view 之間切來量同一個機制。
  「先實作再撞上」會讓這個問題在半路變成一個計時器的猜謎。

**51. 網路呼叫只能在一個檔案裡，而且那件事是對使用者的承諾，不是實作細節。**

- **為什麼**：0.3.0 以前這個 app 一個網路 API 都沒有，而 `README.md` 與
  `.github/SECURITY.md` 把那件事**寫給使用者看**，還附上讓他自己跑的 `grep`
  並宣告預期是 0 筆。加第一個網路呼叫**改變了這個 app 是什麼**，
  所以它與文件必須在**同一個 commit** 裡改完。
- **執行方式**：所有網路 API 只出現在 `ReleaseChecker.swift`。
  文件請讀者跑的那個 grep 現在宣告「應該只命中這一個檔案」，
  命中第二個就是一個回報的理由。
  ⚠️ 連**註解**裡都不可以寫出 `URLSession` 這個字 —— 寫了就會讓那個 grep
  多命中一個檔案，而那句「只命中一個」會變成假的。
  〔2026-09-23 實際發生過：`PreferencesView` 的一句註解就讓 grep 指錯檔案。〕
- **可關掉是承諾的一部分**：`Preferences.checksForUpdates` 關掉之後
  `ReleaseChecker` 一次都不會被呼叫。SECURITY.md 那句話在 0.3.0 之後
  只能以「關得掉」的形式繼續成立。
- ⚠️ **不在 `refresh()` 裡。** 那個迴圈 3 秒一拍、穩態 62.8 毫秒（規矩 47），
  而〔實測 2026-09-23〕一次真實的 GitHub 請求是 **381 毫秒** ——
  放進去等於把一個本機檔案掃描的迴圈變成一個會被網路拖住的迴圈。
- ⚠️ **診斷指令不可以連網。** `currentVersion` 從 bundle 讀，純 CLI 沒有 bundle
  就回 nil，整條檢查不跑 —— 一個診斷工具不該因為被跑了一次就送出請求。
  例外是 `--probe-update`，那是使用者主動下的指令，而它會把這件事印出來。

**52. 「問不到」與「已經是最新的」是兩件事，而且沉默會被讀成後者。**

- **為什麼**：這是兩層規矩（`~/CLAUDE.md`）在更新檢查上的落點。
  一個永遠連不上的使用者，如果面板一直不說話，他會以為自己是最新的 ——
  而他可能已經落後好幾版。
- **三態，每個「不知道」都有名字**：`available` / `upToDate` /
  `unknown(notCheckedYet | offline | rateLimited | unreadable |
  unparseableTag | draftOrPrerelease)`。
  ⚠️ **草稿與預覽版是「不知道」不是「最新的」** —— 它只代表這一次問到的東西
  不能拿來判斷。
- **沉默的規則**：已經是最新的 → 不說（沒有新聞不是新聞）；
  一次失敗 → 不說（不值得打擾）；**超過三天沒有成功問到 → 必須說**，
  而且那句話裡不可以出現「最新」兩個字。
- ⚠️ **`lastSuccess` 要落地，`lastAttempt` 不落地。** 方向相反：前者是**揭露**
  （存了才說得出「已經三天問不到」），後者是**抑制**（存了會少問，規矩 20）。
  丟掉 `lastAttempt` 的代價只是每次開 app 多問一次，而〔實測〕GitHub 未認證
  是 60 次/小時，那不是問題。
- ⚠️ **版本比較不可以用字串。** `"0.10.0" < "0.9.0"` 在字典序上是**真**的，
  於是 0.10.0 出來之後所有 0.9.x 的人會被告知「你已經是最新的」——
  而那是一個沒有人會回報的安靜錯誤。〔突變驗證〕改成字串比較 → 2 則紅。

### 工具鏈與診斷

**28. 診斷指令不可以說謊：註解說它畫了什麼就必須真的畫（用 `exit(1)` 的自我斷言釘住，不是用註解）；配色一律用 `--dark` 檢查；`--render` 必須寫 1x / 2x / 8x，判配色要看 2x；合成資料要在輸出裡講明它是合成的；trace 類直接寫 fd 1 不用 `print`；「只在有變化時印」的變化鍵不可含任何秒數。**

- **為什麼**：一份**說謊的**診斷比沒有診斷更糟，因為它會讓你以為已經看過了。自我斷言要挑抓得到的那一個：`RenderStates` 的 template 陷阱**不可以用像素斷言**抓 —— 離屏 `draw(in:)` 會照實畫出丁香紫，有 bug 的版本一樣會過，唯一抓得到的是 `isTemplate` 本身。`print` 在 stdout 不是 TTY 時是區塊緩衝（4KB），導到檔案再 tail 會看到空檔案然後以為追蹤器沒在跑。
- **證據**：RenderStates.swift:54-66、68-75、112；RenderPanel.swift:15-36、51-53；TraceAlerts.swift:14-21；TraceFinishes.swift:19-22、82-85；Dump.swift:4-8；docs/build-log.md:1119-1120、1588-1593、1620-1622
- **付過的代價**：有，三次：`--render-alert` 宣稱畫了「兩個在等」卻沒有，於是 n=2 的版面從來沒被眼睛看過 —— 而它剛好是唯一一個把第二個 session 整個藏起來的版面；用淺色渲染判斷配色看走眼兩次；`--render` 一直只寫 1x 與 8x，使用者每天真正看到的 2x 從來沒被渲染過（2026-09-19 才補上，commit c151ace）。

**29. `Package.swift` 必須明寫 `platforms: [.macOS(.v14)]`，而 `make_app.sh` 裡那道 minos 檢查不可移除。**

- **為什麼**：預設 swiftc 在這台機器上編出 minos 28.0（高於執行中的 macOS 27.0）。包成 .app 後 LaunchServices 直接以 -10825 拒絕啟動，但當成純 CLI binary 跑又完全正常 —— 會騙過天真的 smoke test。〔實測〕
- **證據**：Package.swift:6-9；make_app.sh:19-28；docs/build-log.md:53、62-67、96

**30. 跑測試一律 `bash scripts/test.sh`，不可以直接 `swift test`；不用 Xcode / xcodebuild，也不為了跑測試去動全域的 `xcode-select`。**

- **為什麼**：這台機器的 `xcode-select` 指向 CommandLineTools（不是 Xcode），SwiftPM 在這個組態下不會自動補 swift-testing 的 framework 搜尋路徑與 runtime rpath，而且需要**兩條**路徑不是一條：`Library/Developer/Frameworks`（Testing.framework）與 `Library/Developer/usr/lib`（lib_TestingInterop.dylib）。第二條特別容易漏，因為它的錯誤訊息要等第一條補好才出現。`sudo xcode-select -s` 會影響整台機器上所有其他專案。
- **證據**：scripts/test.sh:1-17；scripts/make_app.sh:2-6；~/.claude/retrospectives/2026-09-18_quotamonster_swift-testing-rpath.md
- **付過的代價**：有 —— 三個階段、三種不同的錯誤訊息才找到（no such module → Testing.framework 找不到 → lib_TestingInterop.dylib 找不到）。


---

**32. shell 腳本裡 `$VAR` 後面若直接接非 ASCII 字元，一律寫成 `${VAR}`。**

- **為什麼**：〔實測〕macOS 內建的 `/bin/bash` 是 3.2.57，配 `LANG=*.UTF-8` 時會把
  全形標點的第一個 byte 併進變數名：`bash -c 'set -u; V=1; echo "是 $V，但"'`
  → `V\xef: unbound variable`。這個 repo 的 shell 腳本**全部是中文註解與中文輸出**，
  所以這不是理論風險。`${V}` 版本正常。
- **怎麼檢查**：非註解行 grep `\$[A-Za-z_][A-Za-z0-9_]*[^\x00-\x7f{]`。

## 二、寫下來的拒絕

**這些不是待辦，是決定。** 每一條都最容易被下一個人「順手加回來」——
加回來之前請先讀它的理由，並確認那個理由今天不成立了。


**1. T2 對 `killed` 的 run 完全不出聲；run 狀態檔沒寫出來（app crash、未來版本改格式）就永遠不發；一般 Agent 扇出不發 T2。**

- **為什麼（前兩條，未變）**：`killed` 是你自己按的 TaskStop，你知道它為什麼停。沒有正面證據就不宣告完成 —— 「寧可少報，不謊報」。

- ⚠️ **第三條的理由 2026-09-22 被換掉了，結論沒變。** 原本寫的是「一般 subagent 每個節點都是 `.unknown`（背景啟動的 agent 根本不回報完成）」——**那個理由今天不成立**：完成的正面證據一直在母 transcript 裡（第三節第 29 條），而且 2026-09-22 下午**已經讀進來了**（`TranscriptWatcher`，面板的收合那一行現在說「已完成 N · 失敗 M」）。

  結論仍然成立，是因為**另外三件量到的事**：

  1. **沒有可用的扇出單位。** 規矩 16 說 T2 絕不聚合，workflow 的單位是 `workflowId`；一般 agent 沒有等價的容器。〔實測 2026-09-22，37 份 transcript / 37 筆 spawn〕`sourceToolAssistantUUID`、`parentUuid`、擁有那個 tool_use 的 assistant 記錄 uuid、2 秒時間桶 —— **四個候選鍵給出同一個直方圖 `{1: 37}`，一個批次都沒有**。根因也量到了：背景 Agent 立刻回 `async_launched`，所以扇出的成員是在**連續好幾個 assistant 回合**裡開出去的（相隔 2.6–25.2 秒），每一隻自己一則記錄。全機器**沒有任何一則 assistant 記錄含有 ≥2 個 Agent tool_use**。
  2. **唯一分得出批次的鍵會直接違反規矩 16。** `promptId`（人類那一回合的 id）給出 `{1:17, 2:5, 3:2, 4:1}`，但它〔實測〕**跨 transcript 不唯一** —— `e168fb68` 同時是某個母 session 的 3 隻扇出與某個孫 agent 的 4 隻扇出的鍵，只用它當鍵就是把兩個無關的單位聚合在一起，正是規矩 16 點名的那件事。它還會在 `--resume` / fork 時**靜靜地消失**（同一個 uuid 在原檔有 promptId、在分叉檔是 `None`），而且它的語意是「這一個人類回合」不是「這一次扇出」——實測把相隔 86.6 秒與 828.2 秒的兩次委派併成同一批。
  3. **批次不保證會關。** 〔實測〕27 隻背景 agent 裡有 **5 隻（18.5%）從來沒有終端記錄**，其中兩隻是設計上就不會結束的伺服器。所以「等到全部都終結」需要一個逾時 —— 而那是一個**沒有量過**的門檻（規矩 2）。
  4. **它幾乎不會觸發。** 全機器**有史以來只有 6 個真正的扇出批次**，其中 3 個還藏在 subagent 自己的 transcript 裡（從頂層 session 看不到）。三週的重度使用會響幾次。

- **所以**：讀到的下場**只拿來顯示**（面板收合那一行、`--dump`），不拿來發聲。顯示錯了看得見，發聲錯了是一聲謊報。
- **證據**：AgentTally.swift、AgentOutcome.swift、TranscriptWatcher.swift；NotificationEngine.swift:487-490；WorkflowTally.swift:16-18；本節第三段的四項量測

**2. 「狀態不明」的 workflow 不併進「已完成」。**

- **為什麼**：沒有狀態檔＝不知道下場，併進去等於在面板上宣告一件我們不知道的事。〔實測 n=39〕磁碟上四種下場都真的出現過（completed 34 / failed 3 / killed 1 / 沒有狀態檔 1），沒有一個分類是虛構的。
- **證據**：WorkflowTally.swift:19-24、41-45；docs/build-log.md:1513-1524

**3. 不自建安靜時段排程器。靜音只有單鍵循環三段：關 → 1 小時 → 到明早八點 → 關。`SoundBudget` 刻意也不是第二個排程器（沒有日曆邊界、沒有時段、沒有「到明早」，只數最近一小時）。**

- **為什麼**：macOS Focus 已經做了那件事，而第二個排程器正是「明明開了勿擾卻在半夜三點響」的成因 —— 兩個排程器一定會在某個邊界上意見不同，而使用者只會記得是我們吵到他。而且 Focus 狀態〔實測〕讀不到（`~/Library/DoNotDisturb/DB/Assertions.json` 受 TCC 保護、沒有公開 API），所以手動靜音是使用者唯一的防線 —— 那也正是 `mutedUntil` 必須存磁碟的理由。
- **證據**：MutePolicy.swift:3-10、16-40；SoundBudget.swift:17-20；PanelView.swift:438-443；docs/build-log.md:1053-1057、1556-1558

**4. 「跳過去」刻意只做到把擁有它的 app 叫到前面，不做「跳到那個分頁」。**

- **為什麼**：要指定分頁需要 Accessibility + Screen Recording 兩個授權（〔實測〕`AXIsProcessTrusted() == false`、AX 回 `kAXErrorAPIDisabled (-25211)`；螢幕上 20 個視窗，`kCGWindowName` 拿得到 **0 個**），而〔實測〕三個真實 session 有**兩個根本沒有 tty** —— 三個授權提示換一個在三分之二場合仍然無效的功能。改成在面板上顯示 session 自己的名字（`usage-c9`），讓使用者知道找哪個分頁。這是**寫下來的拒絕，不是待辦**。
- **證據**：OwningApplicationResolver.swift:5-15；docs/build-log.md:930、1552-1556

**5. 完成訊號不出聲（mockup 寫的 `Purr` 音效不做）；「未讀」的第二個鐘不做（勾一直等到你打開面板、顯示「58 分前完成」）。**

- **為什麼**：使用者拍板的是「餘光＋勾」。要出聲就得先過 T2 剛裝好的在場閘與 `SoundBudget`，而 T2 那一節自己立過規矩「主動訊號要先 shadow 量過再開」。第二個鐘要一份 seen 集合、一個 popover 開啟的掛勾、一條 24 小時上限，而且它是整個 mockup 裡唯一會說一小時謊的東西。今天 grep 全 Sources 沒有任何 Purr 或 seen 集合，拒絕仍然成立。
- **證據**：docs/build-log.md:1308-1319；grep -i purr Sources/ → 0

**6. 不用 `Codable`，一律 `JSONSerialization` + `as? [String: Any]`；`AgentMeta` 的 schema 沒有官方契約 —— 未知的 key 必須無害、缺少的 key 必須容忍；未知的 session `status` 值寧可整筆跳過，不要猜。**

- **為什麼**：payload schema 會長，未知的新鍵不可造成解析失敗。〔實測〕187 個真實 agent meta 檔共有 **5 種 key 組合**，所以只有 agentType / description / spawnDepth 是必要欄位，`agentId` 一律從檔名推（檔案內容裡沒有這個欄位）。session 那邊：同一台機器上可能同時跑著不同版本的 Claude Code，欄位集合會不一樣（fixture 特地備了 2.1.272 少欄位的案例）。`NotifyState` 雖然是 Codable，但也用 keyed container 逐欄取，好讓那個已經拿掉的 `lastNotified` 不會讓新版讀不回來。
- **證據**：AgentMeta.swift:3-6、43-54；SessionRegistryReader.swift:64-71；ClaudeSession.swift:27-30；NotifyState.swift:74-86；docs/build-log.md:256、362-367、779

**7. 快取檔不另外包一層 metadata，就是 payload 原文，一個 byte 不改；擷取時間改用檔案 mtime（payload 裡沒有任何時間戳），但必須夾在 `now` 以內。**

- **為什麼**：`diff` 得出來、`jq` 讀得動，出事時使用者自己就能看懂。夾 `now` 是因為 mtime 可能在未來（時鐘往回跳、或檔案從別的機器同步過來），不夾住的話它的年齡是負的，會被判成永遠「剛更新」，而且永遠贏過另一個來源。〔程式碼註解，計畫書只寫到「capturedAt 取 mtime」〕
- **證據**：StatusLinePayload.swift:20-21；StatusLineCacheReader.swift:69-73；docs/build-log.md:601、608-609

**8. 不對 statusline 來源做帳號檢查，也不拿 `hook_event_name` 當「這是 statusline payload」的判斷依據；statusline 這條路不裝 hook。**

- **為什麼**：payload 裡沒有任何帳號識別（二進位裡 `accountEpoch` 有被追蹤，但從不序列化）—— `expectedAccount` 這條防線對這個來源不存在，原文的用字是「不要假裝有」。`hook_event_name` 根本不存在（二進位 `rg -ac 'hook_event_name:"Status"'` → 0），那是 hook payload 才有的欄位。而 `statusLine` 是 settings.json 自己的 key、不是 hook（只是同受 `disableAllHooks` 開關管轄），所以不違反這個專案「不裝 hook」的硬性限制。
- **證據**：StatusLinePayload.swift:12-13；ClaudeJSONUsageReader.swift:25-39(對照)；docs/build-log.md:585-586、594

**9. `spendLimit` 刻意不算進「這筆 payload 能不能當額度來源」（`hasAnyWindow`）；讀分模型額度時刻意不檢查新鮮度。**

- **為什麼**：`UsageSnapshot` 只帶 five_hour 與 seven_day，所以一筆只有 spend_limit 的 payload 若勝出，換算出來的快照三個數字全是「—」，那比顯示一個 16 小時前的舊數字更糟；`spendLimit` 仍然解析並保留在型別上，只是還沒有人消費它〔程式碼註解，計畫書未寫〕。分模型那條：過期的分模型數字仍然比沒有好，但代價是呼叫端一定要把 `fetchedAt` 一起呈現出來 —— 面板那一欄因此要標自己的年齡，它與另外兩欄不同來源。
- **證據**：StatusLinePayload.swift:57-65；ClaudeJSONUsageReader.swift:69-71；PanelView.swift:184-188、214-226；docs/build-log.md:1606-1609

**10. 安裝腳本對看不懂的設定一律拒絕，不猜；預設只印 diff，要 `--apply` 才動手，而且安裝前先把 diff 拿給使用者看（使用者定的規則，不是建議）。只改 `statusLine.command` 一個字串，其餘 byte 完全不動。**

- **為什麼**：沒有 statusLine、`type` 不是 "command"、command 不是字串、command 不是可執行檔、JSON 壞掉、或檔案裡找到多處相同字面量 —— 全部 die，不動任何 byte。可逐 byte 還原是這個 Stage 的招牌承諾之一：備份走 `settings.json.bak-<timestamp>`，原本的命令字串原樣存進 `quotamonster-tee.original`。
- **證據**：scripts/install_statusline_tee.sh:7、15-19、104-115、130-143、169-173、191-217；docs/build-log.md:486、705-718

**11. `SoundBudget.remaining(at:)` 刻意不是 `mutating`，而且就地算、不回傳 `stamps.count`；`consumeIfPossible` 刻意不拆成 `hasRoom` + `consume`；`Audibility` 刻意不進 `dedupKey`；`Presence` 的三個參數、`NotificationInput.presence`、`BatchAlert.audibility` 三處刻意不給預設值。**

- **為什麼**：問一下剩多少不可以改變任何東西 —— 一個會改狀態的存取子，會讓「印一行診斷」本身變成一次行為改變；回傳 count 的版本會在沒有事件的那段時間一直說「剩 0」，而說謊的診斷比沒有診斷更糟。拆開 consume 就給了下一個人一個只檢查不扣、或先扣再判的縫。去重鍵回答「這是哪一件事」，不是「這一件事多大聲」，而且待發區裡的事件必須維持 `.undecided`（`NotificationEvent` 是 `Equatable`，三處 `pending.contains(where:)` 靠它擋重複入列）。不給預設值買到的是：漏接線時是一個**編譯錯誤**，不是一個安靜的行為選擇／靜音的預設（呼叫點實測只有七個）。
- **證據**：SoundBudget.swift:52-73；NotificationEvent.swift:123-131、171-179；Presence.swift:39-42；NotificationEngine.swift:13-17

**12. `WaitingAlert` 刻意不是 `[WaitingSession]`，而是 primary + others；兩個同時在等的 session 不合併，≥3 才合成一則摘要。**

- **為什麼**：空的等待警示是一個沒有意義的東西，而 UI 那邊要讀 `sessions[0]` —— 用陣列表示就等於把一個會 crash 的狀態留在型別裡，然後靠每個呼叫端記得不要造出它；拆開之後那個狀態在結構上不存在。兩個各自完整比一則摘要有用，代價是 presenter 必須自己累積窗口內容（引擎送兩則，各自 `show()` 會讓第二則蓋掉第一則，等最久的那個就永遠看不到）。
- **證據**：NotificationEvent.swift:70-95;NotificationEngine.swift:51-52；NotificationPresenter.swift:19-25

**13. `Presence` 刻意不回答「使用者看得到浮窗嗎」—— 兩個問題不合併成同一個型別，而且 nil 要倒向相反的方向：`canSeeAPanel` 讀不到 → 當成人在（開窗、不發 osascript）；`worthSounding` 讀不到 → 當成人不在（不出聲）。**

- **為什麼**：同一條原則（猜錯要選不會多打擾的那一邊）在兩個問題上得到相反的結論，因為出聲多猜一次的代價就是多響一聲。把兩個問題塞進同一個型別，等於留一個邀請下一個人「順手統一」的接縫，而統一的那一刻就會有一邊的 nil 倒錯方向。`(hidIdleSeconds ?? 0)` 會把「IOHIDSystem 沒回話」變成「人剛剛才動過」。
- **證據**：Presence.swift:9-22、52-61；ScreenPresence.swift:32-40、69-75

**14. 音效刻意不用設計文件寫的 `AVAudioPlayer`，也不用 `AudioServicesPlaySystemSound`，改用 `NSSound(named:)`；預設音效刻意不用 `Glass`，用 `Submarine`，而且存成可改字串不寫死。**

- **為什麼**：AppKit 會快取 named 實例：(一) 不必自己持有 strong reference —— `AVAudioPlayer` 少了那一步，區域變數一釋放聲音就當場斷掉；(二) 播放中再呼叫 `play()` 直接回 false，重疊自己就擋掉了。`AudioServices` 最差：還是要 file URL，沒有 `isPlaying`，也沒有音量。而且不需要往 repo 加任何音效檔，`Package.swift` 與 `make_app.sh` 都不動。`Glass` 是 macOS 的預設警示音，跟其他每一個 app 的嗶聲分不出來，正好毀掉 T1 唯一的目的（「回到**那個**終端機」）；存成字串是因為 `NSSound(named:)` 也會找 `~/Library/Sounds`。
- **證據**：AlertSound.swift:3-25；docs/build-log.md:917-918、942-946

**15. `UsageOutlook.sevenDay` 的簽章上刻意拿不到 `samples`（歷史樣本），所以 7 天欄永遠沒有箭頭；`steady`（速率差不多）不給任何符號，與「不知道」在畫面上刻意合流；5 小時欄永遠不印時鐘時間。**

- **為什麼**：7 天窗口唯一誠實的估計法就是它自己的均速，因為那個分母裡已經包含了你睡覺的時間 —— 把最近速率乘以七天，正是這個專案禁止的那種「很有自信的錯」，而讓它連拿都拿不到，比寫一行註解叫人不要那樣做有效。箭頭是純附加的，所以它的**缺席**不主張任何事；如果 `steady` 有自己的符號，使用者就會把「不知道」讀成「持平」。印時鐘等於宣告一個精確到分鐘的預言，而 5 小時窗口的資料撐不起那個精度。
- **證據**：UsageOutlook.swift:10-13、82-94；OutlookCaption.swift:22-46、62-71；docs/build-log.md:1168-1175、1191-1197

**16. 不加獨立的「詳細額度卡」；每日長條圖先不畫；選單列圖示設計的「四塊移植」不做 —— Parallax 幾何維持原狀。**

- **為什麼**：前兩項是使用者決定：維持現在的面板高度；長條圖等 `usage-history.jsonl` 累積兩天後再決定要不要畫、畫在哪（記錄器已經在跑，所以是「延後」不是「放棄」）。第三項是使用者指示「維持原狀」，而且它最容易被下一個人順手加回來 —— 它在「其他缺口」清單裡，但括號寫著「凍結中」。今天 grep 全 Sources 沒有任何長條圖，`GlyphGeometry` 也仍是 Parallax。
- **證據**：docs/build-log.md:1611、1626-1627、1639；GlyphGeometry.swift:3-17

---

## 三、被推翻過的（推翻本身就是知識）

⚠️ **下面每一條在 `docs/build-log.md` 裡都還留著原文。**
它們被列在這裡，是因為「曾經這樣想、後來被資料推翻」比結論本身更值得保留 ——
下一個人很可能會走上同一條路。


**1. 原文說**：（被列為現行規矩）「呼吸動畫是整個 app 裡唯一會動的東西」「呼吸的視窗之外，這個 app 沒有任何重複性計時器」。

**實際上**：**兩句今天都不成立，而且其中一句還寫在出貨的原始碼註解裡。** 除了呼吸之外，至少還有三個重複性計時器：`DataStore.start()` 的 3 秒輪詢（永遠在跑）、`StatusItemController.play()` 的 12Hz pulse 計時器（T2／T3 的瞬時訊號與完成訊號的眨眼，Stage 5 與 Stage 8 加的）、`AlertPanelController.startTicking()` 的 1Hz（浮窗上往上數的秒數）。真正還成立、而且才是重點的那條是：**動畫計時器用完即 `invalidate()` 並釋放整個 frame 陣列，不是暫停；動畫的終點值就是物件的靜止值**，而且 pulse 有四道讓路條件（減少動態／低耗電／警示中／還在播）。照原句去「清理」會刪掉三個在用的計時器。

*證據：BreathAnimator.swift:6-8（仍寫著舊句）vs DataStore.swift:138-143、StatusItemController.swift:158-179、AlertPanelController.swift:221-234；比較克制的版本在 StatusItemController.swift:137-138（「在動的那幾秒之外」）*

**2. 原文說**：（被列為現行規矩，出現在兩個主題）「找 transcript 一律走 `SessionDirectoryResolver.transcript()`，不可以用 `locate()`」——寫成無例外。

**實際上**：**T1 警示路徑今天仍然用 `locate()`。**`NotificationPresenter.transcript(for:)` 是 `resolver.locate(...)?.transcript`。修的只有 Stage 8 的完成偵測路徑（`DataStore.swift:242`）。後果是真的：`locate()` 硬性要求 `<sessionId>/` 目錄存在，而〔實測〕40 個 transcript 只有 15 個有 —— 沒開過 subagent 的 session 在浮窗上永遠拿不到「到底在問什麼」那一行，會安靜地退回分類文字。計畫書 1249 行自己把「沿用 locate()」列為「會讓功能完全失效」的兩件事之一。文件必須寫成「完成偵測已改，警示路徑仍是 locate()，那是一個已知的降級」，不可以寫成無例外的規矩。

*證據：NotificationPresenter.swift:189-192 vs DataStore.swift:240-245；SessionDirectoryResolver.swift:42-57；docs/build-log.md:1249、1280-1282*

**3. 原文說**：（程式碼註解）「⚠️ `tight` 的黃刻意比 `alert` 的琥珀更黃（綠成分高很多），但兩者色相仍然相鄰。」

**實際上**：**過時的註解，今天不成立，而且還在出貨的原始碼裡。** 現行 `QuotaPalette.tight` 是**綠色**（淺底 0.13/0.60/0.32、深底 0.30/0.84/0.48），而且同一個檔案上方八行就寫著「額度色階不得使用任何黃色」。這是 2026-09-18 下午改色階前的殘留 —— 同一段 doc comment 裡「額度分級的顏色。」還出現了兩次，是合併沒清乾淨的痕跡。

*證據：GlyphRenderer.swift:28-33（過時，兩行重複的 doc）vs GlyphRenderer.swift:22-26 與 QuotaPalette.swift:12-27*

**4. 原文說**：計畫書 Stage 3+4 的模組表：`GlyphState`「**只有警示狀態用顏色**」。

**實際上**：2026-09-18 下午改掉了：平常就依剩餘額度上色（>50% 藍、20–50% 綠、<20% 紅，取兩窗口較緊者），沒有讀數或讀數過期才不上色；警示改成靠**形狀與呼吸**區分，不靠顏色。凍結的只剩幾何。⚠️ 計畫書裡那一行舊表格從來沒有被改掉，照抄會抄到錯的。

*證據：docs/build-log.md:440（舊，仍在）vs 1612-1617（新）；程式碼已是新版：GlyphState.swift:87-92*

**5. 原文說**：計畫書 Stage 8 設計段：「**沉澱窗本身就是偵測** —— 某個 transcript 連續 90 秒沒有被寫入，才做一次 64KB 的尾端讀取確認 end_turn。」

**實際上**：安靜只決定「何時去看」，決定「完成沒」的是尾端那一則的 `stop_reason`。這個分工是整個方案的救命符 —— 一個跑 40 分鐘的 Bash 在架構上就不可能誤觸發。⚠️ 那句原文至今仍留在計畫書 1376 行。

*證據：docs/build-log.md:1376（仍在）vs 1254-1259 與 CompletionTracker.swift:11-18*

**6. 原文說**：計畫書：「九道閘、典型 1.6 則／天、最忙 3.7 則／天、92.6% 的完成刻意吞掉；三道最有效的閘是跑不到 3 分鐘（66%）、90 秒內又打字（25%）、Esc 中斷（2%）。」

**實際上**：複驗不出來，而且**計畫書自己在 1299 行下令「九道閘」與「92.6% 吞掉」不可以再出現在任何文件或註解裡** —— 但被禁的那段原文至今仍完整留在 1381-1386 行，兩處直接牴觸。三道複驗得出來但數字不同：跑不到 3 分鐘〔實測〕五成到七成（四個獨立量測 57.9 / 58.5 / 65.5 / 72.2%）；90 秒內又打字〔實測〕24.4%（而且沉澱窗本身就是這道閘）；Esc 中斷〔實測〕1/335 = 0.3%（全庫只有 7 個中斷標記，其中 6 個落在 tool_use 上，那裡根本沒有完成訊號可擋）。另外兩道（人不在、那個 app 在最前面）transcript 裡沒有任何欄位可以重建，既不能證實也不能證偽。

*證據：禁令 docs/build-log.md:1292-1306；仍留著的原文 docs/build-log.md:1381-1386；程式碼側的正確提醒 FinishSignal.swift:29-31*

**7. 原文說**：T2 的排空觸發條件是 journal 的 `finishedCount == total`（正面證據＝數字對上）；而且一個 workflowId 發過一次就夠了，`notified` 設起來就不用管。

**實際上**：那個定義會在**錯的時刻**宣告：`total` 只數目前目錄裡存在的 meta 檔，多階段 pipeline 的階段交界當場滿足它 ——〔實測〕32 個 workflow 有 25 個真的出現過那個窗口、8 個 ≥3 秒。而 `notified` 是**單向閂鎖**（全檔沒有任何 `notified = false`），下一階段到來時 total／complete／everObservedIncomplete 都會重新武裝，只有它不會 —— 所以誤報一次之後，整條 pipeline 真正跑完那一刻一聲都沒有。現行觸發改成 run 狀態檔終結，兩個洞一起在結構上消失（一個 run 只會終結一次）。既有測試只測了 total 縮水（`shrinkingGroupIsNotDrained`），沒有一個讓 total 在發過之後變大。

*證據：docs/build-log.md:1016-1021、1408-1429（原文）vs 1441-1458；NotificationEngine.swift:129、463-486*

**8. 原文說**：`WorkflowGroup.phase` ＝ agentId 字典序最小那隻 agent 的 phase，而且它是「現在正在跑哪一階段」。

**實際上**：agentId 是隨機 hex，字典序與 spawn 順序無關 —— 等於擲骰子，而那個字串直接畫在面板上。〔實測〕掃磁碟上的 workflow，「min(agentId) 那隻」與「min(meta birthtime) 那隻」36 個裡 15 個不一致（以 29 個多階段計是 14 一致 / 15 不一致）。2026-09-19 改用 journal.jsonl 的行序，欄位改名 `phase` → `latestPhase`，並明說它是「最新的那個邊緣」。實機對照：`wf_266aeea2-d48` 舊報 Measure、新報 Design。

*證據：docs/build-log.md:1483-1510；WorkflowJournalReader.swift:35-45；AgentTreeBuilder.swift:106-112；WorkflowPhaseTests.swift:105-120*

**9. 原文說**：`BatchAlert.duration` ＝ 這批跑了多久（實作是從「app 第一次看到這個 workflow」起算）。

**實際上**：那量的是「我們看了多久」，不是「它跑了多久」。2026-09-19 改用 run 狀態檔自己的 `durationMs`（÷1000 成秒），欄位改名 `runDuration` 並改成 optional；`BatchState.firstSeen` 因此沒有讀者，整個拿掉。`AgentTree.swift:56-62` 的註解就是為了擋下一個人再讀成「這個 group 存在多久」。

*證據：docs/build-log.md:1493-1497、1511；NotificationEvent.swift:161-167；AgentTree.swift:56-62*

**10. 原文說**：「T2 會在 session 真正結束前 5–60 秒就對同一件事響一次」，所以 Stage 8 的完成訊號要跟它做秒級去重。

**實際上**：那是**推論，而且方向相反**。〔代理量測／重建，不是量測：母 transcript 排空後第一則 `stop_reason == "end_turn"` 當「這一輪講完了」〕兩支獨立腳本各算一次得到中位 **250 秒（n=28）與 233.5 秒（n=25）**；25 則裡只有 1 則（4%）落在 5–60 秒、30 秒內 0 則。而且 77%（20/26）的排空發生在主 session 已經閒著之後。兩者語意也不同：T2 是「扇出結果回來了」，完成訊號才是「這一輪講完了」。真要去重，視窗是分鐘級（10 分鐘）。⚠️ 這個代理在 orchestrator 排空後又做了別的事時會嚴重高估（三個離群值 6030s / 17316s / 21968s），所以中位數比平均數可信得多。

*證據：docs/build-log.md:1466-1482*

**11. 原文說**：待辦：「同一則 `BatchAlert` 裡 `total` 不是權威來源，run 自報的 `agentCount` 才是」；以及「app 重啟接手會少報 total」。

**實際上**：**兩條都被作者自己撤回，方向相反。**〔實測 n=38〕`agentCount` 與目錄裡的 meta 檔數只有 **4 個**不一致（不是先前寫的 31/34），而且四次都是 `agentCount` **偏小**（`wf_7d1cbb2d-dba` 報 9、實際 29 隻）；meta 檔數與 journal 的 `started` 數 **38/38 完全一致** —— 所以 `total` 才是準的那個。「重啟少報」也不成立，而且是 T2 改用終結狀態當觸發時順手關掉的（該檔 birthtime 從不早於最後一次 journal 寫入）。⚠️「留一條錯的待辦在計畫書裡，和留一段說謊的註解是同一件事。」

*證據：docs/build-log.md:1525-1543；commit 4547102*

**12. 原文說**：5 小時窗口的「已過多少才准投射」沿用 `UsagePace.minimumElapsedFraction = 0.05`。

**實際上**：實測推翻，改成 **0.15（45 分鐘）**。0.05 是為 **7 天**窗口挑的（5% = 8.4 小時），放到 5 小時窗口上只剩 15 分鐘 —— 把〔實測〕最快的那一段 22.52 pp/h 放在剛重置的窗口起點，t+15m 就會投射出 120% 並印出一個時鐘時間，而那兩個窗口最後分別停在 32% 與 ≤7%、突發只持續 14 分鐘。0.15 在實測資料上一毛錢都不花（26 個點只擋掉 19:45 那兩個 elapsed≈0 的）。計畫書自己標注：「這是整個 Stage 最重要的一個常數」。

*證據：docs/build-log.md:1168-1175、1223-1225；UsageProjection.swift:50-64*

**13. 原文說**：「⚠️ 生物**不染色**」是一條無例外的規矩（它本身是實測寫下來的）。

**實際上**：Stage 8 為了完成訊號把它彎了一角：生物核心會染丁香紫。規矩的現行範圍縮小成「**額度色階**不染生物」，完成訊號是唯一的例外。⚠️ 而且 `SignalPalette.swift:19-23` 自己標明：mockup 的反論（用一個沒有人用過的顏色，效果相反）是**推理，不是量測**，所以上線前必須跑 `--render --dark` 並在 1x 下看 —— 1x 的生物只有約 4 個裝置像素寬。

*證據：GlyphRenderer.swift:59-62 vs :184-194；SignalPalette.swift:19-23*

**14. 原文說**：wrapper 的「完整實作」是：先 `cat > "$tmp"` 把 stdin 寫進檔案，`exec 3< "$tmp"` 抓住 inode，最後 `exec "$INNER" <&3 3<&-` 交棒；`trap 'rm -f "$tmp"' EXIT INT TERM HUP`（只清檔案，不 exit）；`old_umask=$(umask); umask 077` 寫在 `mkdir -p` **之後**；而且「不要改成 `read -d ''` 省掉 `cat` 那個 fork」。

**實際上**：**整個結構被換掉，四條都反了。** 現在是 `IFS= read -r -d '' payload` 收進記憶體 → 盡力寫快取（失敗全吞）→ `printf '%s' "$payload" | "$INNER"`，離開碼取 `${PIPESTATUS[1]}`；訊號 trap 必須真的 exit（143/130/129），EXIT 才只 cleanup，交棒前 `trap - TERM INT HUP EXIT`；umask 必須在 mkdir **之前**設。連「不要用 read -d ''」那條禁令自己都被推翻了 —— statusLine payload 來自 `JSON.stringify`，不可能含裸 NUL。「用 exec 交棒」這個機制今天不存在（環境變數照樣繼承）。照計畫書那幾句去改寫腳本會退回被推翻的舊結構。

*證據：docs/build-log.md:640-684、593、656（舊）vs quotamonster-tee.sh:26-34、46-48、52-58、60-66、95-99；推翻理由記在 docs/build-log.md:500-501*

**15. 原文說**：研究階段用 `sourceToolAssistantUUID` 當 parent 指標，把 subagent 接回母 transcript。

**實際上**：它是**檔案內**指標，不是跨檔案的 parent edge（實測 72/72 解析於 subagent 自己的 transcript、母 transcript 0 筆）—— 照它寫會得到一棵空樹。正解是兩套連結法並存：一般 agent 用 `toolUseId` / `parentAgentId`，workflow agent 沒有任何 parent 欄位、只能靠目錄路徑分組（所以 workflow group 是平的一組，不是樹）。

*證據：docs/build-log.md:403-411；AgentTreeBuilder.swift:5-14*

**16. 原文說**：Stage 1 的分模型 7 天額度來自 `utilization` 裡 `seven_day_` 前綴的鍵（`UsageSnapshot.perModel` 就是這樣掃的）。

**實際上**：〔實測〕那些鍵在這個帳號上全是 null，真正有值的是 `utilization.limits` 陣列，而且只有帶得出 `scope.model.display_name` 的那一筆才算分模型（三筆：kind=session 30%、weekly_all 19%、weekly_scoped 1% / display_name="Fable"）。面板今天讀的是 `readScoped` 回傳的 `ScopedUsage`；`perModel` 那條路徑還在程式碼裡，但在這個帳號上永遠是空的。

*證據：docs/build-log.md:1606-1608；ClaudeJSONUsageReader.swift:45-48（舊路徑仍在）vs 59-102（現行）*

**17. 原文說**：計畫書要求「osascript 的 `--` 那條規矩，測試要餵那個字串並斷言檔案沒被建出來 —— 只試引號逸出的測試在有漏洞的版本上也會過」。

**實際上**：**這樣的測試不存在。**`--` 本身在程式碼裡，但 `Package.swift` 只有 `QuotaMonsterCoreTests` 一個 test target，而 `OSAScriptNotifier` 住在沒有測試的 `QuotaMonsterApp` 裡；grep 整個 `Tests/` 與 `scripts/` 都找不到 `eproperty` 或 `do shell script` 的 payload。今天唯一與這條路徑有關的測試是 Core 這一層的 NUL strip。這不是被推翻的規矩，是一條**沒有被兌現的驗收要求** —— 而它自己寫明了「假的綠燈」的風險，所以要當成未結的洞留在文件裡。

*證據：docs/build-log.md:926（要求）；Package.swift:13-17（只有一個 test target）；OSAScriptNotifier.swift:32；grep -rn 'eproperty|do shell script' Tests/ scripts/ → 0*

**18. 原文說**：`NotifyState` 存兩樣：`mutedUntil`、每個 session 最後通知過的 episode 鍵與時間；寫檔時順手丟掉超過 24 小時的條目。以及 osascript 只在「螢幕鎖定／螢幕睡眠／**session 非前景**／閒置 >5 分鐘」時才發。

**實際上**：`NotifyState` 今天**只有 `mutedUntil` 一個欄位**；第二樣一度存了，後來發現它是死的（防止重啟尖叫的是引擎的「第一次觀測不發」規則），連帶「丟掉 24 小時前的條目」也不存在了。「session 非前景」**從來沒有實作** —— `ScreenPresence.canSeeAPanel` 只有三個訊號（`!isLocked && !screensAsleep && !isIdle`），全 repo 唯一出現 `frontmostApplication` 的地方是 `SessionActivator.swift:33` 的**反面**提醒（不要拿它去驗證）。

*證據：docs/build-log.md:919-921、1059-1071（原文）vs NotifyState.swift:24-31、ScreenPresence.swift:38-40；grep frontmostApplication Sources/ → 只命中 SessionActivator.swift:33*

**19. 原文說**：（commit 訊息裡寫過）換掉靜音 `Menu` 的兩個理由都已證實；以及計畫書「面板現況」寫 footer 的靜音是「一小時 / 到明早八點」兩個選項。

**實際上**：只有一個證實：`Menu` 在離屏渲染下畫成紅色禁止符號，所以 `--render-panel` 對那個角落說不出真話。另一個「`.transient` popover 會在 Menu 開視窗那一下自己關掉」**未證實**（文件支持，沒有實機驗證）—— 計畫書明寫「⚠️ 這一條當初在 commit 訊息裡被寫成已證實，那是誇大了」。而 UI 今天是**單鍵循環**（關 → 1 小時 → 到明早 → 關），沒有第二個視窗，現在是哪一段一直寫在旁邊；計畫書 1623-1625 的舊描述沒改。

*證據：docs/build-log.md:1225-1231 vs 1623-1625（舊，仍在）；MutePolicy.swift:18-28；PanelView.swift:444-466*

**20. 原文說**：計畫書附錄：「T1 以『選單列圖示警示狀態 + app 自有 NSPanel 浮窗 + **AVAudioPlayer** 音效』實作」；以及「Stage 4／5／6 的細節待 Stage 0 的通知 probe 結果確定後定案」。

**實際上**：實際是 `NSSound(named:)`（見 refusals），附錄那一行沒有跟著更新；Stage 5 本體的「與設計文件的兩處刻意偏離」才是現行決定。第二句也是施工殘留：Stage 0–8 全部完成，那句話讀起來像還沒開始。另外 Stage 0 的假設「授權失敗的唯一變因是安裝位置」也不成立 —— 四個變體（`~/Applications` vs `/Applications`、regular vs accessory、全新 bundle ID、isActive true/false）全部失敗，`ncprefs` 登錄數始終為 0，剩下唯一站得住的假設是 Gatekeeper／公證（`spctl -a` 回 rejected）。

*證據：docs/build-log.md:1645-1646、1650（附錄，過時）vs 942-946；AlertSound.swift:3-25；docs/build-log.md:17-27、36*

**21. 原文說**：（文件與註解裡飄著的數字）計畫書 Stage 8 標頭「469 測試 / 47 套件全綠」；Stage 3+4 模組表「15 個狀態可用 `--render`」；`NotificationPresenter` 檔頭「那邊有 62 個測試」；計畫書「字串型 382 則裡有 93 則 isMeta=true，而貼截圖的真人訊息 105 則全部是 list」。

**實際上**：四個都已經漂掉，而且其中兩個寫在出貨的原始碼註解裡。靜態計數今天是 **477 個 `@Test` / 48 個 `@Suite`**（⚠️ 這一輪唯讀，是計數不是執行結果）；`RenderStates.cases` 今天有 **20** 個；`NotificationEngineTests` 今天有 **71** 個 `@Test` / 6 個 `@Suite`，不是 62；而 `TurnCompletionReader` 的註解寫的是另一組母數（「非 tool_result 的 user 行 395 則：字串 290（其中 93 則 isMeta=true）、list(text) 144、list(image,text) 33」），與計畫書的 382 對不上，而且它自己三個分項相加 = 467 ≠ 它寫的 395。共同的 93 兩邊一致，**判準本身（兩種形狀都要收）不受影響**，但那兩段文字不可能同時為真。⚠️ 我沒有重新量語料，只核對了兩段文字與它們自己的算術。**結論：文件不要抄任何測試數與語料母數。**

*證據：docs/build-log.md:1245、441、1277-1279 vs `grep -c '@Test'` 合計 477 / `@Suite` 48、RenderStates.swift:17-42、NotificationPresenter.swift:7、TurnCompletionReader.swift:129-135*

**22. 原文說**：面板在選中 statusline 來源、沒有分模型資料時顯示「此方案無此視窗」（修法被描述成：改成說出真正原因「這個來源不提供分模型視窗」）。

**實際上**：bug 確實修了，但**修法與被引述的新字串不一樣**。今天的實際字串是二選一：`store.scoped == nil ? "讀不到 ~/.claude.json" : "此方案無分模型視窗"` —— 也就是「此方案無…」那句話還在，只是改成只有在**真的讀到** `~/.claude.json` 而它沒有分模型項目時才說。引述計畫書 505 行的措辭會在文件裡留下一個對不上程式碼的引號。

*證據：docs/build-log.md:505 vs PanelView.swift:214-220*

**23. 原文說**：計畫書 Stage 3+4 收尾：「⚠️ 尚未觀察到實機觸發（目前沒有 session 在等你）…活的計時器路徑要等下一次權限請求才會跑到。」以及三重存活閘會有自己的檔案 `Sources/QuotaMonsterCore/Agents/AgentLiveness.swift`。

**實際上**：第一句後來真的跑到了 ——「使用者第一次實際用到時抓到的那一格」那一節裡，診斷的三個訊號之一就是「圖示**有**變琥珀」，警示狀態在實機上確實渲染出來了；那一節抓到的 bug 是浮窗開給沒有人看，不是圖示沒亮。計畫書沒有回頭修那一行。第二句：`AgentLiveness.swift` 這個檔案不存在，三道閘分散在 `AgentTreeBuilder.isFresh`、`WorkflowJournal.running`、`WorkflowRunState.isTerminal` —— 規矩成立，落點不同。

*證據：docs/build-log.md:468-469（舊，仍在）vs 1564-1576；docs/build-log.md:413-416 vs `ls Sources/QuotaMonsterCore/Agents/`（只有 AgentMeta / AgentTree / AgentTreeBuilder / SessionDirectoryResolver / WorkflowJournalReader / WorkflowRunState / WorkflowTally）*

**24. 原文說**：（方法問題，不是單一條目）萃取結果普遍用 `file.swift:行號` 當證據錨點。

**實際上**：抽查下來行號普遍有 1–15 行的漂移（例如「NotificationEngine.swift:465-477」指的那段 max 其實在 452-459；「SessionDirectoryResolver.swift:67-83」的撞號排序其實在 78-80；「Breath.swift:96-113」其實在 80-108；「T2 絕不聚合」在兩個主題各給了 438-443 與 459-463，而狀態鍵在 445）。規矩本身都成立，但一份要**長期保留**的文件如果錨在行號上，一個 commit 就會開始說謊 —— 而說謊的註解正是這個 repo 花最多篇幅在防的東西。建議改錨在型別＋成員名（`NotificationEngine.observeBatches`、`FinishCaption.prune`），行號只當輔助。

*證據：逐條比對 Sources/ 現況；示例見 NotificationEngine.swift:452-459、SessionDirectoryResolver.swift:78-80、Breath.swift:80-108*
---

**25. 原文說**：`UsageSourceSelector.snapshot(from:)` 上方的註解：「新鮮度沿用
300/3600 秒門檻，這對 statusline 來說是**保守**的 —— 這個來源是**事件驅動**的，
會讓額度數字變大的活動，本身就是會觸發重新寫入的活動。」

**資料說**：〔實測 2026-09-21〕反了。渲染是 UI 事件驅動的，**不是 API 回應驅動的**。
Claude Code 從行程記憶體重發 `rawUtilization`，所以一次渲染可以完全不帶新數字。
一個閒置兩天的 session 被喚醒時，第一次渲染會把兩天前的數字用一個**當下的 mtime**
寫出來，而我們把它標成 `live`。代價是歷史檔裡一筆假資料，以及一整天的假資料點。

**代價**：這句註解讓「檔案年齡 ≈ 讀數年齡」看起來像已經想過的結論，
所以後面每一個讀到它的人都不會再去質疑 `capturedAt` 的語意。

**26. 原文說**：`quotamonster-tee.sh` 檔頭：「statusLine payload 來自 JSON.stringify，
不可能含有裸 NUL（會被跳脫成 \u0000），所以這個代價收得下。」

**資料說**：那個推論大概是對的，但**代價不對稱**，而且那段註解自己就含著
**一個真的 NUL byte** —— 作者想寫 `\u0000`，寫進去的是 `\0` 本人。
〔實測〕餵一份含裸 NUL 的 72 byte payload：`read` 在 NUL 處停住，內層只收到 59 byte，
而那份截斷版**經 rename 蓋掉了上一筆完整的快取**（`[ -s ]` 只檢查非空，不檢查完整）。
現在不靠推論：`read -r -d ''` 讀到 NUL 回 0、讀到 EOF 回非 0。

**27. 原文說**：`scripts/test_statusline_tee.sh`：「收到 SIGTERM 之後 3 秒內真的收工
（不是繼續等 stdin）」——讀起來像是在守那三個 trap。

**資料說**：〔實測〕把 wrapper 的三個 trap 全部刪掉，這一則**照樣通過** ——
TERM 是在 trap 安裝**之前**那個阻塞的 `read` 期間送到的，收工靠的是預設處置。
它證明的只是「不會掛住」。測試名稱已改成它真正證明的東西。

**28. 原文說**：`GlyphRenderer.drawAgentRail`：「暗軌在每個狀態都畫 ——
沒有 agent 時墨水盒才不會縮水。」

**資料說**：墨水盒**確實**會縮（〔實測 2x〕idle 從 32px 高變成 27px），
所以那句話的前半是真的。但它推出來的結論不成立：`NSImage` 是固定的 22×22，
狀態列置中的是**圖**不是墨水，所以位置不會跑。

而那條軌付出的代價是實的：〔使用者回報 + 2x 渲染對照，2026-09-22〕
它本身就讀成一條線，而點與它的對比太弱 —— **1～3 隻看起來像「一條線上有
幾塊比較亮」，0 隻則是一條沒有意義的灰線**。拿掉之後點就是點、數得出來，
4 隻以上才合併成橫槓，而那時候「一條」是有意義的。

**代價**：這段程式碼**完全沒有測試**（拿掉暗軌，551 則測試一個都沒紅）。
一個每天被看見的視覺元素，靠的是一句沒有被驗證過的註解在維持。
現在有 5 則像素測試釘住它（把暗軌加回去會紅 4 則）。

**29. 原文說**：第五節 D 段（結構性做不到）：「**一般 Agent 扇出永遠不會發 T2**
—— `AgentTreeBuilder` 把每一隻一般 subagent 都寫成 `.unknown`，沒有正面證據
就不宣告完成。」以及 `AgentRunState.unknown` 的檔頭：「背景啟動的 agent
**根本不回報完成**。」

**資料說**：〔實測 2026-09-22，33 隻一般 agent，**100% 覆蓋**〕證據一直都在
母 transcript 裡，只是沒有人去找：

| | 幾隻 | 完成訊號 |
|---|---|---|
| 背景（`isAsync: true`） | 24 | `<task-notification>` 帶 `<task-id>{agentId}</task-id>` 與 `<status>` |
| 前景 | 9 | 該次 `tool_result` 的 `toolUseResult.status == "completed"` |

`<status>` 實測有三種：`completed`（720）、`failed`（14）、`killed`（6）。

「背景啟動的 agent 根本不回報完成」的觀察本身沒錯 —— `tool_result` 當下回的是
`status: async_launched`。錯在**停在那裡**：完成是後來以另一種記錄抵達的。

**代價**：這個結論被寫進「結構性做不到」那一節，而那一節的意思是
「不要再試了」。一條寫錯的「做不到」比一個待辦更貴 —— 待辦會被撿起來，
「做不到」不會。

⚠️ 〔2026-09-22 下午**已實作**〕`TranscriptCursor`（記 `(inode, offset)`、只交出
新增的完整行）＋ `TranscriptWatcher`。收合那一行現在說「已完成 N · 失敗 M ·
已停止 K · 狀態不明 J」。

⚠️ 這一段原本寫著「**這個發現還沒有被實作**……`AgentTally` 這一版仍然只用
`AgentActivity` 的活動代理，所以收合那一行說『已結束』不說『已完成』」——
而同一個 commit 的其他四處都說做完了〔code review 2026-09-22 抓到〕。
⚠️ 它還寫「它可以到 13MB」，實測是 **22.4MB（活著的最大 16.1MB）**，低估約 70%。
而且那支整份重讀的代價不只是「讀不到下場」：它一直每 3 秒跑一次，
佔掉 `refresh()` 一拍 740 毫秒中的絕大部分（第三節第 32 條）。

**30. 原文說**：第三節第 29 條（那條推翻「一般 Agent 沒有正面證據」的）自己寫的表格：
「背景（`isAsync: true`）24 隻 → `<task-notification>` 帶 `<task-id>{agentId}` 與 `<status>`；
前景 9 隻 → `toolUseResult.status == "completed"`」。

**資料說**：〔重新實測 2026-09-22，37 份 transcript、34,204 筆記錄〕方向對，但**兩個決定實作怎麼寫的細節是錯的**：

1. **接得起來的鍵不是 tool-use-id，是 `toolUseResult.agentId`。**
   用 agentId 對 `<task-id>`：**25/25**。用 tool-use-id：**5/25** ——
   `<tool-use-id>` 只出現在 72 個通知區塊裡的 57 個，而且**重複通知時會消失**。
2. **通知主要不是 `type:"user"` 記錄。** 25/25 隻 agent 的最早落地形式是
   `type:"queue-operation"` / `operation:"enqueue"`（一個**沒有 `message` 外層**、
   `content` 直接是字串的記錄）。只看 user 記錄的 reader 看得到 **6/25**。
   第三種載體 `type:"attachment"`（`attachment.prompt`）帶 11 隻，但**沒有一隻**是
   前兩種看不到的 —— enqueue 單獨就是 25/25。

還量到三個會讓資料說謊的邊界，原文沒有提：

- `operation:"remove"` 是 enqueue 的**逐字複本**（338 vs 417 筆）。兩個都算＝雙重計數。
- **同一隻 agent 會重複通知 `completed`** —— 一隻通知了 **17 次**，另一隻的第二次
  `<result>` 開頭是「Correction to my previous report」。所以是**最後一筆贏**，
  而且要算「不同的 agentId」不是「通知筆數」。通知本身就寫著：
  「A task-notification fires each time this agent stops with no live background children of its own.」
- **沒有 `<status>` 的區塊不是「下場不明」，是「不是完成」。** 11 筆沒有 status 的裡面
  9 筆是 `Monitor event:` 帶 `<event>`（例如「Episode 1500 | Score 3」）。把它當 unknown
  會讓一個**活著的** monitor 在面板上變成一隻卡住的 agent —— 正是規矩 1 那個兩層分界。

**代價**：原文那兩個細節任何一個照著寫，得到的都是一個「看起來會動、覆蓋率卻只有 20–24%」的 reader，
而且不會有任何錯誤訊息。⚠️ 原文還有一個數字對不上：表格說 33 隻 agent，`<status>` 三種值合計卻是 740
（720/14/6）—— 那顯然是全庫記錄數不是這 33 隻的分佈。引用時不要把兩組數字當成同一個母數。

**31. 原文說**：`AgentTreeBuilder` 檔頭：「不要用 `sourceToolAssistantUUID` 當 parent 指標。
實測它是**檔案內**指標（72/72 解析於 subagent 自己的 transcript，母 transcript 內 0 筆），
照它寫會得到一棵空樹。」

**資料說**：〔實測 2026-09-22〕**那句話沒有錯，但它的範圍被寫得太寬了。**
兩個不同的記錄族群被講成同一件事：

| 族群 | 數量 | 在自己的檔案裡解析得到 | 在母 transcript 裡解析得到 |
|---|---|---|---|
| subagent transcript 裡帶這個欄位的記錄 | 18,092 | 18,092 | **0 / 18,094** |
| 母 transcript 裡的 **spawn** 記錄 | 37 | **37 / 37** | 同左（就是同一個檔案） |

也就是說它**永遠是檔案內指標**；原始量測只取樣了 subagent 那一側，於是「母 transcript 內 0 筆」
對那些記錄為真、對 spawn 記錄為假。檔頭那句操作建議（拿它當 parent 指標會得到空樹）仍然正確。

**代價**：這一條差點讓「用它當扇出批次鍵」在還沒量之前就被放棄。真正讓那個方案出局的是
**另一件事**（它是 per-tool-call 的鍵，直方圖 `{1: 37}`，一個批次都沒有）—— 見第二節拒絕 1。
⚠️ 一條**範圍寫太寬的實測**與一條寫錯的實測一樣貴：它會讓下一個人停止提問。

**32. 原文說**：`DataStore` 的 `refreshInterval` 註解：「慢輪詢。FSEvents 監看是 V2 的事；
先用固定間隔把功能跑通。**全部是 stat + 小檔案解析，成本可以忽略。**」

**資料說**：〔實測 2026-09-22，`--bench-refresh`〕`refresh()` 的穩態中位是 **740 毫秒**，
而一拍的預算是 3000 毫秒 —— **三分之一的時間在 main actor 上重新解析看過的行**。
「小檔案」那三個字是這句話唯一錯的地方：`AgentTreeBuilder.toolUseIds` 讀的是母 transcript，
這台機器上最大的 22.4MB、還活著的最大 16.1MB（`AgentTally` 的註解與這份文件當時三處都寫「13MB」，
已經低估約 70%）。改成增量讀取之後是 **62.8 毫秒**。

**代價**：這句註解讓「這個迴圈很便宜」變成一個**沒有人再去驗的前提**，
而它正好是後面每一個「順手加一點在 refresh 裡」的依據。
⚠️ 一個沒有量過的「成本可以忽略」，與把推論寫成量測是同一件事（規矩 5）。

**33. 原文說**：`FinishGlow.menuBar` 的註解：「⚠️ `ranFor == nil` 不亮。
〔實測〕約六分之一的完成算不出秒數」，以及第五節 A 段把「完成訊號要不要出聲」
列成「等更多資料」。

**資料說**：〔實測 2026-09-22，`--trace-finishes` 跑滿 53 分鐘 / 957 拍 / 4–5 個 session〕
產生了 **7 個完成標記，選單列一次都沒亮**。而且七個的原因**完全一樣**：

```
[15:30:17] ✓ 完成  修t2    跑了多久算不出來
[15:31:24] ✓ 完成  rl-1b   跑了多久算不出來
…（7/7 全部如此）
```

**卡住的不是那個 600 秒門檻，是上游算不出 `ranFor`。**
「六分之一」（84.1%，111/132）與今天的 7/7 不衝突 —— 它們量的是不同的母體：
`ranFor` 要上溯到這一輪的**第一則真人訊息**，而〔實測〕只有 **37.4%** 的回合塞得進
64KB 的尾端窗口（中位要往回搆 114,059 bytes）。**回合越長越搆不到**，
而這幾個 session 的回合都很長（219 次「又動了」對 7 次沉澱）。

**代價**：第五節把「這個訊號該不該出聲」掛在「等更多資料」上等了好幾天，
而真正該問的問題是**它為什麼幾乎不亮**。等一個永遠不會來的樣本，
與沒有在等，看起來一模一樣。
⚠️ 這也是規矩 28 的一個新形狀：`--trace-finishes` 當時只印「選單列 none」，
而 none 有**三個**不同的原因（沒有標記／算不出 `ranFor`／跑得不夠久）——
一支分不出原因的診斷，會讓人把「量到了」與「看得懂」混為一談。
現在它把最新那個標記的 `ranFor` 一起印出來。

**修法已經有機器了**〔推論，尚未實作〕：`TranscriptCursor` 是**往前**掃的，
掃過去的時候順手記下最後一則真人訊息的位置，回合起點就不必往回搆。

## 四、診斷指令對照

**哪一支回答哪一個問題**是關鍵，因為它們看起來都像「印一些東西出來」。

| 指令 | 它能證明什麼 | 它**不能**證明什麼 |
|---|---|---|
| `--dump` | 資料層看到的真實世界（兩個額度來源怎麼挑、session、agent 樹、歷史、展望與拒絕理由） | 任何 UI 的事 |
| `--render <dir> --dark` | 選單列圖示每個狀態長什麼樣（1x / 2x / 8x） | 它在真的選單列上會不會被別的項目擠掉 |
| `--render-panel <f> --dark` | 面板畫出來長什麼樣、自然高度幾 pt | session 列（另外輸出 `panel-rows.png`）、`Menu` 之類離屏會壞的元件 |
| `--render-panel … --panel simple\|full` | 兩種版面各自長什麼樣（**只覆寫記憶體，不碰偏好檔**）。⚠️ 簡易版面沒有 session 清單，所以它**不**另外渲染 `panel-rows.png` 也不 `splice()` | 切換那一下順不順 —— 那要 `--probe-panel-switch` |
| `--probe-update [--as <版本>]` | 更新檢查那條路通不通、現在會說什麼。⚠️ **會真的連網**（使用者主動下的指令，與偏好無關）。`--as 0.0.1` 假裝自己是舊版，用來驗「有新版」那條路 | 面板那一條畫得對不對 —— 那是 `--render-panel --demo-update` |
| `--render-panel … --demo-update` / `--demo-outage` | 「有新版」與「一直問不到」兩條的版面（**合成**的，會印出來說明） | 真的檢查會不會成功 |
| `--probe-panel-switch` | popover 開著時翻版面，`fittingSize` / `contentSize` / `window` 在四個時點各是多少（規矩 50） | 使用者按不按得到那顆鍵 |
| `--render-panel … --chart daily\|cumulative` | 額度底下那兩種圖各自長什麼樣（**只覆寫記憶體，不碰偏好檔**） | 哪一種比較好用 —— 那是使用者的事 |
| `--render-panel … --demo-finish` | 完成那一列的版面，**並自己斷言列高 Δ=0pt**（不是 0 就 exit 1） | 那一列在真的有完成時會不會出現 |
| `--render-alert <f> --dark` | T1 浮窗五種情況的版面 | 它會不會真的出現在螢幕上 |
| `--demo-alert` | 浮窗**真的**開得出來（印 isVisible / level / frame / NSApp.isActive / keyWindow） | 有沒有事件走到它 |
| `--trace-alerts <秒>` | 通知引擎對著實時資料每一拍看到什麼、發了什麼、在場狀態 | 浮窗畫得對不對 |
| `--trace-finishes <秒>` | 完成偵測器每一拍看到什麼（安靜多久、尾端讀到什麼、有沒有產生標記、選單列該是什麼） | 它是**影子引擎**：獨立行程、自己剛開機，所以此刻已經完成的都會被判成「不是我們見證的」 |
| `--probe-popover` | popover 的實際尺寸與 SwiftUI 回報的差距 | — |
| `--render-prefs <f> --dark` | 偏好設定視窗的版面與深色配色（scale 2） | 它在真的視窗裡拿不拿得到鍵盤焦點 |
| `--probe-login` | 開機自動啟動的真實狀態（bundle 路徑、原始 rawValue、對應到哪一格、按下去會做什麼）。加 `--register` / `--unregister` 會**真的動手**並印出前後狀態 | 下次登入到底會不會起來 —— 那要真的登出才知道 |

**三條使用規矩：**

0. ⚠️ **AppKit 包裝的 SwiftUI 控制項在 `ImageRenderer` 底下不畫，會變成一個
   紅色禁止符號。** 這個 repo 原本只為 `Menu` 記下這件事，〔實測 2026-09-19〕
   `Stepper` 也一樣 —— 寫偏好設定介面時先避開了 `Menu` 與 `Picker`
   （後者預設樣式就是 `.menu`），還是踩到第三個，是 `--render-prefs`
   第一次跑就抓到的。`ScrollView` 則是畫成**空的**。
   所以離屏要驗收的介面只能用 `Button` 與 `Text`。
   ⚠️ 這比「整個不畫」危險：它產出一張**看起來很正常、但那個角落是假的圖**。

1. ⚠️ **這些指令畫的是「使用者的偏好」，不是「預設值」** —— 偏好在
   `DataStore.init` 讀（規矩 44）。〔2026-09-22 之前不是這樣，而 `--render-prefs`
   還印著「這張圖用的是目前實際的偏好檔」——**那句話當時是假的**。〕
   所以要看某個設定長什麼樣，就真的去改偏好檔再渲染。

1. **`--dark` 一定要加。** 使用者的選單列與面板都是深色的，這個專案已經**兩次**
   因為用淺色渲染判斷而得到相反的結論。
2. **判配色看 2x。** 這台機器是 Retina，選單列把 22pt 畫成 44 個裝置像素。
   1x 是最壞情況（外接非 Retina 螢幕）、8x 是拿來看幾何的 ——
   〔2026-09-19 發現〕`--render` 一直只寫 1x 與 8x，**使用者每天真正看到的尺寸
   從來沒有被渲染過**。
3. **trace 類的輸出直接寫 fd 1，不用 `print`。** Swift 的 `print` 在 stdout 不是 TTY
   時是 4KB 區塊緩衝，導到檔案再 tail 會看到空檔案，然後以為工具沒在跑。

---

| `--render-icon <dir>` | app icon 長什麼樣 | 寫出十個尺寸的 `.iconset`。⚠️ 十個**各自原生渲染**，不從 1024 縮。少寫一個就 `exit(1)`，不是印警告。 |
| `touch ~/Library/.../QuotaMonster/trace-usage.on` | 「一個回合的第一次渲染會不會早於第一個 API 回應」 | 開關檔，不是環境變數 —— 開關都不碰 `settings.json`。每次渲染記一行到 `trace-usage.log`。刪掉開關檔就停。 |

## 五、還沒完成的

> 「刻意不做」的那些在**第二節**，不在這裡 —— 那些是決定，不是待辦。
> 這一節只列**還沒做、但沒有拒絕過**的。

### A. 等條件

| 項目 | 卡在哪 |
|---|---|
| ~~**每日長條圖**~~ —— **已做（2026-09-22）** | 答案是「**跟著額度窗口切**」：一根長條是 14:00 到 14:00，不是午夜到午夜；而且每一根帶著信心（日界兩端有沒有被**看得見的**心跳蓋到）。另外也做了累計曲線，兩者可在偏好設定切換。下面這段是當時卡住的紀錄，留著當背景。⚠️ **卡的不是資料量，是語意。**〔實測 2026-09-22〕`usage-history.jsonl` 有 **134 點、跨 3.9 天**，早就超過當初說的「兩天」。但 (一) 取樣是**事件驅動**的（`shouldRecord` 只在數字變了才寫，而數字來自 statusline tee），逐日覆蓋 6.6h / 14.4h / **0h** / 2.2h / 3.5h，**沒有一天超過 14.4 小時**；(二) `7d` 是滾動窗口**會下降**（實測 09-19 03:15 `58` → 03:47 `56`），`5h` 每五小時歸零 —— **兩條線都不能直接差分成「今天用了多少」**。「那根長條代表什麼」這個問題還沒有答案，再等幾天不會自己解決。 |
| heartbeat + bootMarker（Stage 7 步驟 10） | 等使用者點頭 |
| 完成訊號要不要出聲 | ⚠️ **量過了，而且問題換了。**〔實測 2026-09-22，53 分鐘 / 957 拍 / 4–5 個 session〕產生 7 個標記、選單列**一次都沒亮**，7/7 的原因都是 `ranFor` 算不出來（不是 600 秒門檻）。**在它幾乎不亮之前，「該不該出聲」是問不出答案的。** 先修 `ranFor`（`TranscriptCursor` 往前掃時順手記下最後一則真人訊息，回合起點就不用往回搆），再重問這一題。全文見第三節第 33 條。 |

### A2. 已經量完、可以結案的

- ~~**「一個回合的第一次渲染是不是早於該回合第一個 API 回應」**~~ ——
  **已量到（2026-09-22）**，規矩 31 那個標著〔推論〕的環節現在是實測。
  `trace-usage.log` 621 次渲染 / 17.9 小時：
  - **95%（586/620）的渲染帶著沒有變的數字** —— 渲染是 UI 驅動的，不是 API 驅動的。
  - 決定性的一組（閒置 1.5 小時後回來）：
    ```
    13:08:27  5h=—  7d=19    ← 前一次渲染在 5584s 前
    13:08:44  5h=—  7d=19
    13:09:47  5h=—  7d=19
    13:09:49  5h=—  7d=19
    13:09:50  5h=21 7d=28    ← 1 秒後，真正的數字才進來
    ```
    **7d 在一秒內從 19 跳到 28** —— 19 是 1.5 小時前被原封不動帶出來的舊值。
    閒置後的**前 4 次渲染、83 秒**都在報舊數字。
  - ⚠️ `five_hour` 缺席有**兩個**成因，形狀一樣：閒置（上面那個）與
    **窗口重置**（09-21 22:50:01 正好是 5 小時窗口的邊界）。
    規矩 31 那個 `.expired` 降級兩個都擋得住。
  - 開關檔 `trace-usage.on` 目前**還開著**；要停就把它刪掉。

### B. 還沒做的功能

- ~~**開機自動啟動**（`SMAppService`）~~ —— **已做（2026-09-19）**。
  面板 footer 多一顆電源圈按鈕。⚠️ 兩個實測到的陷阱：
  (1) **`status == .notFound (3)` 是註冊前的正常值，不是安裝損壞** ——
  把它當錯誤顯示，使用者會以為 app 壞了；
  (2) `requiresApproval`（使用者在系統設定裡關掉）**`register()` 叫不回來**，
  只能開系統設定那一頁，所以它是獨立的一格，不可以跟 `off` 混在一起。
  〔實測〕`notFound → register → enabled`，而且註冊**撐得過 `make_app.sh` 重裝**。
  ⚠️ 這顆按鈕**在 `--render-panel` 上看不到** —— 診斷是純 CLI binary，
  不是 .app bundle，那種情況整個不畫（按了保證沒用的按鈕比沒有更糟）。
- ~~**偏好設定介面**~~ —— **已做（2026-09-19）**，四格：音效／「明早」幾點／
  ctx 黃紅／額度門檻。存在 `preferences.json`（**不是 `UserDefaults`** ——
  純 CLI binary 沒有 bundle identifier，`--dump` 會印出一個 app 根本沒在讀的
  數字，那是規矩 28）。

  **判準：這個量測是一條曲線，還是一條界線。** 曲線可以調（動它只是沿著
  量過的線移動），界線不行（動它讓量測作廢）。⚠️ **使用者親自選過不等於
  它是口味** —— `SoundBudget.capacity` 與 `Presence.idleThreshold` 都是他
  拍板的，但調壞的方向是**無聲**的，所以不給調。

  規矩 2 繼續成立的三個條件：(1) 字面量仍只活在原處，偏好是覆寫；
  (2) **磁碟上永遠不出現預設值**（沒調過的欄位在 JSON 裡不存在，
  一個沒動過設定的使用者的檔案是 `{}`），這樣新的量測改了預設他會跟著走；
  (3) ⚠️ **解析點必須由型別固定成一個** —— 前兩件成立時第三件仍然可以
  無聲地失敗。額度門檻就是那個反例：`QuotaTier.forRemaining` 有三個消費者，
  其中 `GlyphState.quotaTier` 是沒有參數的 computed property，
  給參數預設值的話它永遠拿預設，於是面板的條在 5% 轉紅、圖示還是 20% 轉紅、
  T3 在 5% 才響，**零編譯錯誤**。執行手段只有一個：**覆寫參數不給預設值**。

  ⚠️ 而且那則守著規矩 2 的測試（`thresholdsHaveASingleDefinition`）以前
  **兩邊都餵預設**，所以這個功能會把它變成一則說謊的測試。已升級成餵
  **非預設**的門檻，並驗過：把 `quotaTier` 改回吃預設，它會紅。
- **FSEvents 監看取代 3 秒輪詢**。`DataStore` 裡只有一行註解說它是 V2 的事。
- **卡住／閒置 agent 偵測**。資料層已經有足夠資訊，缺的是門檻與 UI。
- **已經在跑的 session 不會立刻開始寫 tee 快取**。〔實測〕安裝後 8 分鐘，
  另外兩個 session 仍然沒有 payload。額度是帳號層級的所以數字不受影響，
  但那些 session 的 context 壓力要等它們自己重新渲染狀態列，或重開。
  緩解方案是 `statusLine.refreshInterval`（官方設定，最小 1 秒），
  但那會改變使用者狀態列的更新節奏 —— **要先問過**。

- ~~**一般 Agent 的真實完成狀態**（`completed` / `failed` / `killed`）~~ ——
  **已做（2026-09-22）**。`TranscriptCursor`（記 `(inode, offset)`，只交出新增的完整行）
  ＋ `TranscriptWatcher`（每份 transcript 一份累積的事實）＋ `TranscriptFacts`（解析）。
  面板收合那一行現在說「已完成 N · 失敗 M · 狀態不明 K」，`--dump` 同一套語彙。
  ⚠️ 順手修掉一個沒人量過的效能洞：`refresh()` 穩態 740 → **62.8 毫秒**（規矩 47）。
  ⚠️ **T2 仍然不對一般 Agent 扇出生效** —— 理由整個換過，見第二節拒絕 1：
  不是「沒有證據」（有了），是**沒有可用的扇出單位**（四個候選鍵給出 `{1: 37}`，
  唯一分得出批次的 `promptId` 跨 transcript 不唯一、會在 resume 時消失），
  加上 18.5% 的背景 agent 從來不終結，以及全機器有史以來只有 6 個真正的扇出批次。
- **workflow 的 `journal.jsonl` 還是每拍整份重讀**，而且是在新鮮度閘**之前**
  （`AgentTreeBuilder.swift` 的 `journalReader.read()` 在 `isFresh` 過濾之前），
  所以四天前死掉的 workflow 的 journal（這台機器上最大 888KB）永遠會被重新解析。
  〔實測〕它是改造後剩下的 62.8 毫秒的主要來源。機器已經有了（`TranscriptCursor`），
  缺的是把它接上去 —— 但 journal 是 append-only 且會跨 `--resume` 累積，
  接之前要先確認它的重寫行為與 transcript 一樣。
- **已經在跑的 session 不會立刻開始寫 tee 快取**（見上）。
- ~~**一般 Agent subagent 看不出在不在跑**~~ —— **已做（2026-09-22）**，
  改用 transcript 活動的代理量測（規矩 37），窗口 120 秒。
  剩下的是 **卡住／閒置 agent 偵測**：機制已經有了（`AgentActivity`），
  缺的是「多久算卡住」那個門檻與 UI。⚠️ 那個門檻**還沒有量過**。

### C. 測試覆蓋的缺口（這一節最重要）

- ~~**`OSAScriptNotifier` 的 `--` 沒有任何測試守著**~~ —— **已補（2026-09-19）**。
  參數組裝搬進 Core 的 `OSAScriptCommand`，`OSAScriptCommandTests` 有 8 則：
  5 則結構（`--` 排在每個使用者字串之前、標題恆定、兩欄都過 clean…）＋
  2 則**行為**（真的跑 osascript：負向斷言 sentinel 沒被建出來，
  控制組把 `--` 濾掉之後斷言它**有**被建出來 —— 後者的用途不是抓 bug，
  是證明前者有牙齒）＋ 1 則守「內容不可逃逸」。
  驗證方式：把 `--` 拿掉之後 **5/8 變紅**，其中行為那一則以正確的理由紅
  （`fileExists → true`，payload 真的執行了）。
  ~~原文：~~
  程式碼是對的（`OSAScriptNotifier.swift:32`，註解寫著「少了這一行就是 RCE」），
  但計畫書自己要求過的那則測試 ——「餵那個真的 payload 並斷言檔案沒被建出來」
  ——〔grep 全 `Tests/`〕**至今不存在**。而規矩 3 自己講明：只試引號逸出的測試
  在有漏洞的版本上也會過。要寫的話得先把參數組裝搬進 Core（見下一條）。
- ~~**App 層沒有測試 target**~~ —— **已補（2026-09-19）**。
  `QuotaMonsterAppTests` 10 則。⚠️ **不必把 executable 拆成 library**：
  SwiftPM 讓 testTarget 直接相依 executableTarget（`@testable import` 摸得到
  internal），只要測試套件標 `@MainActor`。
  補的是「今天完全沒有東西守著、而且錯了不會有人發現」的那些：
  額度色階裡沒有黃色（規矩 24，先前只有註解擋著 —— 驗過把 tight 改回黃色會紅）、
  丁香紫只出現在生物核心、染了色就不走 template、警示路徑不碰生物、
  退色版是混出來的、格式有小時分支。
  ⚠️ **規矩 16 沒有因此鬆動**：決策仍然只能放 Core。這個 target 測的是
  **繪圖與色彩**這種 Core 碰不到的東西，不是拿來放決策的後門。

  ⚠️ **一則差點變成謊話的測試，留在這裡當教訓**：我原本寫「有人在等你時
  完成訊號整批丟掉 → 兩張圖逐 byte 相同」，然後去驗它 —— 把
  `GlyphState.creatureGlow` 的守門拿掉，**那一則照樣過**，因為警示走
  `drawAlert`、根本不呼叫 `drawCreature`。守住那條規矩的是 Core 那一則。
  測試改寫成它真正在證明的事（警示路徑不碰生物），並在註解裡寫明它**不是**
  `creatureGlow` 的守門。
- **`ScreenPresence.idleThreshold` 的別名沒有測試守著。**
  用 `#expect(Presence.idleThreshold == 300)` 去釘是一則**說謊的測試**
  （別名改回字面量 300 它照樣會過），唯一的執行手段就是那一行別名本身。

### D. 結構性做不到的（不是沒做）

- ~~**一般 Agent 扇出永遠不會發 T2**~~ —— ⚠️ **這一條錯了，已移出本節**
  （見第三節「被推翻」第 29 條）。〔實測 2026-09-22，100% 覆蓋〕完成的正面證據
  一直都在母 transcript 裡：背景 agent 走 `<task-notification>` 的 `<status>`、
  前景 agent 走 `tool_result` 的 `toolUseResult.status`。
  〔2026-09-22 下午**已實作**〕`TranscriptCursor` + `TranscriptWatcher`。
  ⚠️ **但 T2 對一般 Agent 扇出仍然不發**，理由整個換過 —— 不是「沒有證據」，
  是**沒有可用的扇出單位**。完整量測見第二節拒絕 1。
- **Focus／勿擾讀不到**（`Assertions.json` 受 TCC 保護，也沒有公開 API），
  所以手動靜音是唯一的防線。
- **osascript 的署名永遠是「指令碼編輯器」**，而且**偵測不到**使用者有沒有在
  系統設定裡把它關掉。自建 applet 實測回 `-10814`，一則都送不出。
- **「跳過去」只到 app 層級，到不了分頁**（見第二節的拒絕 4）。
- **VS Code 外掛的 session 對額度數字沒有任何貢獻**（規矩 36）。
  〔實測 2026-09-22〕它不呼叫 `statusLine` 命令，所以永遠沒有 payload ——
  沒有 ctx 細條，而且配合規矩 33（`~/.claude.json` 已經不再更新），
  **只用外掛的使用者完全拿不到額度數字**。我們無法讓外掛去跑 statusline。
- **macOS 14／15／16 上沒有人跑過。** binary 的 `minos` 是 14.0，
  但開發機是 macOS 27。〔推論，非實測〕Release 說明已標明。
- **Intel Mac 不支援**（`lipo -info` → `arm64`）。這是刻意的取捨。
