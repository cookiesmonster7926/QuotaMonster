> # ⚠️ 這是歷史紀錄，不是現況
>
> **現況看 `docs/quotamonster.md`。** 這一份是 Stage 0–8 的施工紀錄，按 Stage 排。
> 它保留下來的理由只有一個：裡面有大量「當時量到什麼、為什麼不那樣做」的原始證據。
>
> ⚠️ **裡面有已知是錯的敘述** —— `docs/quotamonster.md` 的第三節逐條列出了
> 29 處「原文這樣寫、後來被資料推翻」。引用這份文件裡的任何一句之前，
> 先去那一節確認它沒有被推翻。
>
> 最後一行原本寫著「完成所有 Stage 後刪除此文件」。沒有刪，因為刪掉會連證據一起丟掉。

# 實作計劃：QuotaMonster

> 參考設計文件：`docs/plans/2026-09-18-quotamonster-design.md`

**目標：** macOS menu bar app，一眼看到 Claude Code 的 5h/7d 額度、即時 agent 數量與階層、以及誰在等你回覆。
**架構：** 純檔案資料層（旁聽 `~/.claude`，零 token、零行程）→ 純函式 Core library（可完整單元測試）→ AppKit menu bar 殼層。
**技術棧：** Swift 6.3 / SwiftPM / AppKit（`NSStatusItem`）/ Core Graphics / SwiftUI（僅下拉面板內部）/ FSEvents

**硬性限制：** 不呼叫 Claude API、不 spawn claude 行程、V1 不動 `~/.claude/settings.json`。

**關於程式碼細節：** 本文件對「一寫就錯」的關鍵函式給完整實作（存活判定、兩套連結法、原子寫入），對例行的 model/reader 給簽章與測試案例。不把整個 app 的原始碼複製進計劃書。

---

## Stage 0：Spike — 通知權限與工具鏈

> **已執行完畢（2026-09-18）。結果見 `docs/plans/2026-09-18-stage0-result.md`。**
>
> - ✅ Task 0.1 minos 14.0，`platforms: [.macOS(.v14)]` 生效
> - ✅ Task 0.2 bundle 組裝 + Apple Development 簽章 + 安裝，`scripts/make_app.sh` 可一鍵重跑
> - ❌ **Task 0.3 通知授權失敗**。四個變體（`~/Applications` vs `/Applications`、
>   regular vs accessory、全新 bundle ID、isActive true/false）全部無法取得授權，
>   `ncprefs` 登錄數始終為 0 —— 系統從未把 app 登錄進通知中心。
>   安裝位置假設**不成立**，已排除。剩下唯一站得住的假設是 Gatekeeper / 公證
>   （`spctl -a` 回報 rejected）。**Stage 5 必須改設計，待使用者在付費公證與備援方案之間決定。**
> - ✅ Task 0.4 60pt status item 正常上架（`window.origin.y = 923.0`）
>
> Stage 1 不受影響，可直接開始。


**目標：** 在寫任何功能前，證明這個 app 形狀在這台機器上真的能跑、真的能發通知。
**成功標準：** 一支 .app 從 `~/Applications` 啟動、拿到 `granted == true`、成功送出一則通知；且 60pt 的 status item 沒有被推到螢幕外。
**測試策略：** 手動驗收（這是 spike，不是產品程式碼）
**狀態：** 未開始

> ⚠️ **這個 Stage 不可跳過。** 驗證階段在 `/private/tmp` 下無論用 ad-hoc 或 Apple Development 憑證簽章，`UNUserNotificationCenter` 一律回 `"Notifications are not allowed for this application"`。已排除簽章、activation policy、quarantine、TCC 殘留。唯一沒測到的變因是安裝位置。若 `~/Applications` 也失敗，整個提醒功能要換機制，Stage 5 要重新設計。

### Task 0.1：SwiftPM scaffold 與 deployment target
**檔案：**
- 建立：`Package.swift`
- 建立：`Sources/QuotaMonsterCore/Placeholder.swift`
- 建立：`Sources/QuotaMonsterApp/main.swift`
- 建立：`Tests/QuotaMonsterCoreTests/PlaceholderTests.swift`

**步驟 1：** 建立 `Package.swift`，**必須**明寫 platforms：

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaMonster",
    platforms: [.macOS(.v14)],          // ← 少了這行會編出 minos 28.0
    targets: [
        .target(name: "QuotaMonsterCore"),
        .executableTarget(name: "QuotaMonsterApp", dependencies: ["QuotaMonsterCore"]),
        .testTarget(name: "QuotaMonsterCoreTests", dependencies: ["QuotaMonsterCore"]),
    ]
)
```

**步驟 2：** 建置並**驗證 minos**：
```bash
swift build -c release
otool -l .build/release/QuotaMonsterApp | grep -A3 LC_BUILD_VERSION | grep minos
```
預期：`minos 14.0`。若看到 `minos 28.0`，platforms 沒生效 —— 停下來修，否則 Stage 0.2 打包出來的 .app 會被 LaunchServices 以 `-10825` 拒絕，而且當成 CLI 跑又完全正常，會騙過你。

**步驟 3：** Commit
```bash
git add Package.swift Sources Tests && git commit -m "chore(quotamonster): scaffold SwiftPM package with macOS 14 target"
```

### Task 0.2：.app bundle 組裝腳本
**檔案：**
- 建立：`scripts/make_app.sh`
- 建立：`Resources/Info.plist`

**步驟 1：** `Resources/Info.plist` 關鍵欄位：

| Key | Value | 為什麼 |
|---|---|---|
| `CFBundleIdentifier` | `com.cookiesmonster.QuotaMonster` | 通知授權綁在 bundle id 上；**之後不要改** |
| `LSUIElement` | `true` | 不出現在 Dock、不出現在 Cmd-Tab |
| `LSMinimumSystemVersion` | `14.0` | 與 Package.swift 一致 |
| `CFBundleName` / `CFBundleExecutable` | `QuotaMonster` | |
| `CFBundleShortVersionString` | `0.1.0` | |

**步驟 2：** `scripts/make_app.sh` 做四件事：`swift build -c release` → 組出 `QuotaMonster.app/Contents/{MacOS,Resources}` → `codesign --force --deep --sign - QuotaMonster.app`（ad-hoc）→ `rsync` 到 `~/Applications/`。

**步驟 3：** 跑起來驗證
```bash
bash scripts/make_app.sh
open ~/Applications/QuotaMonster.app
```
預期：行程起得來（`pgrep QuotaMonster` 有輸出）。若回 `-10825`，回 Task 0.1 檢查 minos。

**步驟 4：** Commit

### Task 0.3：🔴 通知權限 probe（最高風險項）
**檔案：**
- 修改：`Sources/QuotaMonsterApp/main.swift`

**步驟 1：** 寫一支只做四件事的 probe：設 `NSApp.setActivationPolicy(.accessory)` → `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])` → 印出 `granted` 與 `error` → 送一則 `UNNotificationRequest`。

**步驟 2：** 從 `~/Applications` 執行
```bash
bash scripts/make_app.sh && open ~/Applications/QuotaMonster.app
log stream --predicate 'process == "QuotaMonster"' --style compact &
```

**步驟 3：** 判讀結果

| 觀察到 | 意義 | 下一步 |
|---|---|---|
| 系統權限對話框跳出、`granted=true`、橫幅出現 | ✅ 假設成立 | 繼續 Stage 1，Stage 5 照設計走 |
| `UNErrorDomain Code=1` | ❌ 安裝位置不是變因 | **停止**，改測 `/Applications`；仍失敗則 Stage 5 改用 `NSPanel` + `AVAudioPlayer` 備援，並回報 |

**步驟 4：** 把結果（成功或失敗）寫進 `docs/plans/2026-09-18-quotamonster-design.md` 的「待解問題」，並 commit。

### Task 0.4：menu bar 寬度 probe
**檔案：**
- 修改：`Sources/QuotaMonsterApp/main.swift`

**步驟 1：** 建一個 `NSStatusItem`，指派一張 60×22pt 的純色 `NSImage`，然後印出：
```swift
let b = statusItem.button!
print("frame=\(b.frame) windowY=\(b.window?.frame.origin.y ?? -999)")
```

**步驟 2：** 預期 `windowY >= 0`。若為負（實測 256pt 會落到 y=-33），表示被靜默推到螢幕外 —— glyph 必須更窄。

> 這個檢查要保留進產品程式碼：app 啟動後若偵測到 `windowY < 0`，要明確告訴使用者「圖示被 menu bar 空間擠掉了」，否則會被當成 crash 回報。

**步驟 3：** Commit

---

## Stage 1：資料層 — 額度與 session

> **已完成（2026-09-18）。44 個測試 / 5 個套件全綠，且已對真實資料驗證。**
>
> 每個模組都走完整的紅綠燈：先寫測試 → 親眼確認失敗訊息是「功能不存在」→ 最小實作 → 通過。
>
> | 模組 | 測試 | 釘住的關鍵行為 |
> |---|---|---|
> | `ResetTimestamp` | 9 | ISO-8601 與 epoch 秒解出同一個 Date；epoch 絕不被當毫秒；過期回 nil 不回負數 |
> | `ClaudeJSONUsageReader` | 10 | 5/60 分鐘門檻沿用 Claude Code 自己的 azo/izo；帳號不符回 nil；**缺少的窗口是 nil 不是 0** |
> | `SessionRegistryReader` | 9 | 四種 status；0 bytes 與截斷 JSON 跳過不丟錯；同 sessionId 保留最新 |
> | `ProcessLiveness` | 7 | pid 存在 **且** 啟動時間對得上；EPERM 視為存活 |
> | `SessionState` | 9 | `.waiting` = 人類被擋住；死行程一律排除；阻塞的排最前 |
>
> **真實資料驗證**（`swift run QuotaMonsterApp --dump`）：正確判定 14 小時舊的快取為 expired、
> 正確指出 5 小時窗口的重置時間已過、4 筆 session 全數存活、`perModel` 因真實資料為 null 而正確留空。
>
> **工具鏈注意事項：** 跑測試要用 `bash scripts/test.sh`，不能直接 `swift test`。
> 原因見該腳本內的註解（swift-testing 的 framework 與 interop dylib 需要手動補 rpath）。


**目標：** 一個純函式 library，餵它 `~/.claude` 的檔案，吐出正確的額度快照與 session 清單。
**成功標準：** `swift test` 全綠；對真實 fixture 能重建出與 `claude -p /usage` 一致的數字。
**測試策略：** Unit test 為主。所有 reader 都吃「路徑」而非硬寫 `~`，測試餵 fixture 目錄。
**狀態：** 未開始

### Task 1.1：測試 fixtures（含去識別化）
**檔案：**
- 建立：`Tests/Fixtures/claude_json/{fresh,stale,expired,missing_windows,unknown_keys}.json`
- 建立：`Tests/Fixtures/sessions/{busy,idle,waiting_input,waiting_permission,zero_bytes,truncated,old_version}.json`
- 建立：`scripts/capture_fixtures.sh`

**步驟 1：** 寫 `scripts/capture_fixtures.sh`，從真實檔案產生 fixture 時**強制去識別化**：`accountUuid` / `sessionId` 換成固定假 UUID、`cwd` 換成 `/tmp/fixture-project`、任何 `sk-ant-` 字串一律拒絕寫出（找到就 exit 1）。

> ⚠️ 這條規則是有來由的：研究階段有 agent 執行 `security find-generic-password -g`，把 OAuth token 寫進了本機 transcript。fixture 腳本要主動防這件事。

**步驟 2：** 手工補齊自然遇不到的邊界案例：0 bytes、截斷的 JSON、缺 `waitingFor`、2.1.272 版少欄位、`accountUuid` 不符。

**步驟 3：** Commit

### Task 1.2：`UsageSnapshot` 與 `ClaudeJSONUsageReader`
**檔案：**
- 建立：`Sources/QuotaMonsterCore/Usage/UsageSnapshot.swift`
- 建立：`Sources/QuotaMonsterCore/Usage/ClaudeJSONUsageReader.swift`
- 測試：`Tests/QuotaMonsterCoreTests/ClaudeJSONUsageReaderTests.swift`

**步驟 1：先寫失敗的測試**

```swift
@Test func fresh_reading_is_live() throws {
    let s = try ClaudeJSONUsageReader().read(fixture("claude_json/fresh.json"), now: fixedNow)
    #expect(s.fiveHour?.percent == 28)
    #expect(s.sevenDay?.percent == 18)
    #expect(s.freshness == .live)             // age <= 5 min
}

@Test func reading_between_5_and_60_minutes_is_aging() throws { ... #expect(s.freshness == .aging(minutes: 23)) }
@Test func reading_past_60_minutes_is_expired() throws { ... #expect(s.freshness == .expired) }   // 沿用 Claude Code 自己的 izo=3600000
@Test func account_mismatch_yields_nil() throws { ... #expect(s.fiveHour == nil) }
@Test func unknown_extra_windows_do_not_break_parsing() throws { ... }   // tangelo / nimbus_quill 等 passthrough 欄位
@Test func missing_window_is_nil_not_zero() throws { ... #expect(s.sevenDay == nil) }
```

**步驟 2：** `swift test --filter ClaudeJSONUsageReader` → 預期 FAIL（型別不存在）

**步驟 3：** 實作。`Freshness` 三態必須是列舉而非布林 —— UI 要區分「新鮮 / 有點舊（顯示年齡）/ 過期（灰化）」。

> **絕對不要**在缺資料時回傳 0%。0% 和「不知道」在視覺上必須不同，否則 app 會在你額度爆掉時顯示一條空的安全長條。

**步驟 4：** `swift test` → PASS

**步驟 5：** Commit：`feat(core): read plan usage from ~/.claude.json with Claude Code's own freshness rules`

### Task 1.3：`resets_at` 雙格式統一
**檔案：**
- 建立：`Sources/QuotaMonsterCore/Usage/ResetTimestamp.swift`
- 測試：`Tests/QuotaMonsterCoreTests/ResetTimestampTests.swift`

**步驟 1：先寫測試** —— 同一個時刻的兩種表示必須解出相同 `Date`：

```swift
@Test func iso8601_and_epoch_seconds_agree() throws {
    let a = try ResetTimestamp.parse(.string("2026-09-17T19:40:00.176235+00:00"))
    let b = try ResetTimestamp.parse(.number(1789674000))
    #expect(abs(a.timeIntervalSince(b)) < 1)
}
@Test func epoch_is_never_interpreted_as_milliseconds() throws { ... }
@Test func countdown_uses_local_timezone() throws { ... }   // 使用者在 UTC+8
```

> 這條測試存在的理由：`~/.claude.json` 給 **ISO-8601 字串**，statusLine payload 給 **Unix epoch 秒**。混用會產生差了幾十年的倒數，而且不會報錯。

**步驟 2–4：** FAIL → 實作 → PASS
**步驟 5：** Commit

### Task 1.4：`SessionRegistryReader`
**檔案：**
- 建立：`Sources/QuotaMonsterCore/Sessions/ClaudeSession.swift`
- 建立：`Sources/QuotaMonsterCore/Sessions/SessionRegistryReader.swift`
- 測試：`Tests/QuotaMonsterCoreTests/SessionRegistryReaderTests.swift`

**步驟 1：先寫測試**

```swift
@Test func parses_all_four_status_values() throws { ... }   // busy / shell / idle / waiting
@Test func waiting_carries_waitingFor() throws {
    let s = try read("sessions/waiting_input.json")
    #expect(s.status == .waiting(.inputNeeded))
}
@Test func permission_prompt_is_distinct_from_input_needed() throws { ... }
@Test func zero_byte_file_is_skipped_not_thrown() throws { #expect(reader.read(dir).count == 3) }
@Test func truncated_json_is_skipped_not_thrown() throws { ... }
@Test func missing_optional_fields_parse_fine() throws { ... }   // 2.1.272 少欄位
@Test func duplicate_sessionId_keeps_newest_startedAt() throws { ... }
```

**步驟 3：實作要點**
- 除 `pid / sessionId / cwd / startedAt / status` 外，**所有欄位都是 Optional**。
- 整個解析包在 try/catch 裡；**讀到 0 bytes 是正常現象**（實測 0.1 秒間隔快照會捕捉到寫入中的空檔），不是錯誤。
- 依 `sessionId` 去重，保留 `startedAt` 最新者（crash 後 resume 會同時存在兩筆）。

**步驟 5：** Commit

### Task 1.5：`ProcessLiveness` — pid 重用安全的存活判定
**檔案：**
- 建立：`Sources/QuotaMonsterCore/Sessions/ProcessLiveness.swift`
- 測試：`Tests/QuotaMonsterCoreTests/ProcessLivenessTests.swift`

**步驟 1：先寫測試**

```swift
@Test func own_pid_is_alive() { #expect(ProcessLiveness.isAlive(pid: getpid(), startedAt: ownStart) == true) }
@Test func impossible_pid_is_dead() { #expect(ProcessLiveness.isAlive(pid: 999_999, startedAt: Date()) == false) }
@Test func recycled_pid_with_mismatched_start_time_is_dead() {
    // 同一個 pid，但宣稱的 startedAt 比真實行程啟動時間早一小時 → 必須判定為死
    #expect(ProcessLiveness.isAlive(pid: getpid(), startedAt: ownStart.addingTimeInterval(-3600)) == false)
}
@Test func start_time_within_tolerance_is_alive() { ... }   // 容差 300 秒
```

**步驟 3：完整實作**（這是「一寫就錯」的部分，給完整程式碼）

```swift
import Darwin
import Foundation

public enum ProcessLiveness {
    /// pid 重用容差。session 檔的 startedAt 與行程真實啟動時間可能差幾秒。
    public static let reuseTolerance: TimeInterval = 300

    public static func isAlive(pid: Int32, startedAt: Date) -> Bool {
        guard pidExists(pid) else { return false }
        guard let real = processStartTime(pid) else { return false }
        return abs(real.timeIntervalSince(startedAt)) < reuseTolerance
    }

    private static func pidExists(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM      // 存在但不屬於我們 → 仍算活著
    }

    private static func processStartTime(_ pid: Int32) -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let tv = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }
}
```

> **為什麼不能只看 pid：** crash 的 session 會留下一個永遠寫著 `busy` 的檔案，而 pid 會被系統回收再利用。只驗 pid 會讓一個不相干的新行程「復活」那個死掉的 session。實測本機有 session 已宣稱 busy 41 分鐘 —— 時間戳完全不能用來判斷存活，因為 `status` 只在狀態轉換時寫入，**沒有 heartbeat**。

**步驟 5：** Commit

### Task 1.6：`SessionState` 衍生
**檔案：**
- 建立：`Sources/QuotaMonsterCore/Sessions/SessionState.swift`
- 測試：`Tests/QuotaMonsterCoreTests/SessionStateTests.swift`

**步驟 1：測試**

```swift
@Test func waiting_maps_to_needsHuman() { #expect(state(for: waitingInput).needsHuman == true) }
@Test func busy_never_maps_to_needsHuman() { #expect(state(for: busy).needsHuman == false) }
@Test func dead_process_is_excluded_regardless_of_status() { ... }
```

> **這條規則有 binary 證據撐腰**：狀態機 `{running:"busy", requires_action:"waiting", idle:"idle"}`，而被 subagent 卡住走的是 `delegatedActive` → `busy` 分支。所以 `waiting` 在設計上就等於「人類被擋住」，可以直接當通知觸發條件，不需要 hook。

**步驟 5：** Commit

---

## Stage 2：Agent 樹重建

> **已完成（2026-09-18）。78 個測試 / 10 個套件全綠，且已對真實資料驗證。**
>
> | 模組 | 測試 | 釘住的關鍵行為 |
> |---|---|---|
> | `AgentMeta` | 7 | 只要求 agentType/description/spawnDepth（實測 5 種 key 組合）；agentId 來自檔名；未知 key 無害 |
> | `WorkflowJournalReader` | 7 | running = started −(result ∪ **failed**)；壞行跳過 |
> | `SessionDirectoryResolver` | 5 | 靠兄弟 transcript 判別同名目錄 |
> | `AgentTreeBuilder` | 11 | **兩套連結法**：toolUseId/parentAgentId vs 目錄路徑；比 session 舊的排除 |
> | `AgentTreeBuilder`（中止） | 4 | 終結的 run 裡沒有 agent 在跑，journal 說什麼都不算 |
>
> **真實資料驗證抓到一個 bug 並已修掉：** 被 `TaskStop` 中止的 workflow 顯示成「5 隻執行中」，
> 因為中止的 run 永遠不會寫 result/failed。權威訊號是 `<sessionId>/workflows/<wf_id>.json`
> 的 `status`（實測終結值只有 completed / failed / killed）。
> 詳見 `~/.claude/retrospectives/2026-09-18_quotamonster_aborted-workflow-phantom-agents.md`。
>
> **已知且刻意保留的缺口：** 一般 Agent subagent 的完成狀態是 `.unknown`。
> 它沒有 journal，完成與否要從母 transcript 的 `toolUseResult` 推，
> 而背景啟動的 agent 根本不回報完成（實測 23 筆中 13 筆是 `async_launched`）。
> `runningAgentCount` 只計入**確定**在跑的 —— 寧可少報，不謊報。


**目標：** 從檔案重建出「session → agent → subagent」的完整樹，死掉的不出現。
**成功標準：** 對真實 fixture 重建出深度 3 的樹；已完成與已失敗的 agent 不被標為執行中。
**測試策略：** Unit test，餵一整棵真實（去識別化）的目錄結構。
**狀態：** 未開始

### Task 2.1：`AgentMeta` 讀取
**檔案：**
- 建立：`Sources/QuotaMonsterCore/Agents/AgentMeta.swift`
- 測試：`Tests/QuotaMonsterCoreTests/AgentMetaTests.swift`

欄位：`agentType`、`description`、`workflowPhase?`、`spawnDepth`、`requestShape`、`toolUseId?`、`parentAgentId?`。全部 Optional except 必要者；schema 無官方契約，要容忍新欄位。

### Task 2.2：session 目錄解析
**檔案：**
- 建立：`Sources/QuotaMonsterCore/Agents/SessionDirectoryResolver.swift`

**步驟 1：測試**
```swift
@Test func resolves_session_dir_by_sibling_transcript() throws { ... }
@Test func disambiguates_when_same_sessionId_exists_under_two_project_slugs() throws { ... }
```
> 實測 11 個 session 目錄中有 1 個同時存在於兩個 project slug 底下。判別依據是**同層是否有 `<sessionId>.jsonl` 這個兄弟檔**。

### Task 2.3：workflow journal 讀取
**檔案：**
- 建立：`Sources/QuotaMonsterCore/Agents/WorkflowJournalReader.swift`

**步驟 1：測試**
```swift
@Test func running_equals_started_minus_result_and_failed() throws {
    // journal 有 'failed' 事件類型；漏掉它會讓失敗的 agent 永遠掛在樹上
    #expect(reader.running(journal).contains("a8a79b948d33593bc") == false)
}
```

### Task 2.4：樹建構 — 兩套連結法
**檔案：**
- 建立：`Sources/QuotaMonsterCore/Agents/AgentTreeBuilder.swift`
- 測試：`Tests/QuotaMonsterCoreTests/AgentTreeBuilderTests.swift`

**步驟 1：測試**
```swift
@Test func plain_agents_link_by_toolUseId() throws { ... }
@Test func depth_two_and_three_link_by_parentAgentId() throws { ... }
@Test func workflow_agents_link_by_directory_path() throws { ... }
@Test func sourceToolAssistantUUID_is_never_used_as_parent_edge() throws { ... }
```

> ⚠️ **這裡有一個經驗證推翻的假設。** 研究階段一度採用 `sourceToolAssistantUUID` 當 parent 指標。實測它是**檔案內**指標：72/72 解析於 subagent 自己的 transcript，在母 transcript 內 0 筆。照它寫會得到空樹。
>
> 正確做法是**兩套並存**：
> - 一般 Agent subagent → `meta.json.toolUseId` 配對母 transcript 的 `tool_use.id`；深度 ≥2 用 `parentAgentId`
> - **workflow subagent → 沒有任何 parent 欄位**，只能靠目錄路徑 `<sessionId>/subagents/workflows/<wf_id>/`
>
> 本機佔比：workflow agent 60 / 91。**多數情況走的是沒有 parent 欄位的那條路。**

### Task 2.5：三重存活閘整合
**檔案：**
- 建立：`Sources/QuotaMonsterCore/Agents/AgentLiveness.swift`

**步驟 1：測試**
```swift
@Test func agent_older_than_session_startedAt_is_excluded() throws { ... }   // resume 累積陷阱
@Test func failed_workflow_agent_is_not_live() throws { ... }
@Test func does_not_fall_back_to_mtime_threshold_alone() throws { ... }
```
> 不可單用 mtime 門檻判死活：實測那個 failed 的 agent 在失敗後僅 153 秒就被觀察到，用「冷卻超過 N 秒視為死」會誤判。

**步驟 5：** Commit：`feat(core): rebuild live agent tree with dual linkage and triple liveness gate`

---

## Stage 3 + 4：選單列圖示與下拉面板

> **已完成（2026-09-18）。105 個測試 / 12 個套件全綠，app 已安裝並執行中。**
>
> **採用方案：Parallax**（round 6 最高分，63/80），未套用那四塊建議移植 —— 使用者指示「維持原狀」。
> 已知取捨：兩個徑向 counter 低於 1x 下限，非 Retina 螢幕上兩條弧會糊在一起。
> 使用者用的是 MacBook Air（2x），實際影響很小。幾何是純函式，要換成 `beads` 只需改一個檔。
>
> | 模組 | 測試 | 內容 |
> |---|---|---|
> | `GlyphGeometry` | 20 | 半徑預算、弧掃掠、50% 標記、agent 單位角度、阻塞分段、生物姿態 —— 規格的每個數字都釘死 |
> | `GlyphState` | 7 | 已用 → 剩餘的換算；nil ≠ 0；只有警示狀態用顏色 |
> | `GlyphRenderer` | — | Core Graphics 繪製，15 個狀態可用 `--render` 輸出 PNG 人眼檢查 |
> | `DataStore` | — | 3 秒輪詢，全部是既有檔案的 stat + 小解析 |
> | `StatusItemController` | — | 固定 22pt，**絕不用 `.variableLength`**；啟動後檢查是否被擠出螢幕 |
> | `PanelView` / `SessionRow` | — | 釘住 + 捲動：表頭、額度三欄、阻塞卡永遠可見，只有 session 清單捲動 |
>
> **面板設計取自定案的「釘住+捲動」殼**：表頭帶 SESSIONS/AGENTS/BLOCKED roll-up、
> 額度三欄大數字（沒讀數顯示「—」而不是 0）、阻塞卡帶琥珀軌並**說出後果**
> （「N 個 agent 跟著停住」）、session 列用 row 型別而非縮排表示層級、
> 扇出先給 pip 形狀再給名字。
>
> **編譯器地雷（不可移除的規避）：** `GlyphRenderer` 裡不得出現任何仿射變換 API。
> 見 `~/.claude/retrospectives/2026-09-18_quotamonster_silcombine-crash.md`。
>
> **呼吸動畫已完成（2026-09-18）。** 122 個測試 / 14 個套件全綠。
>
> | 模組 | 測試 | 內容 |
> |---|---|---|
> | `Breath` | 6 | 12 格取樣、首尾無縫、起訖都是全亮、對稱、動作預算 4×6=24 秒 |
> | `BreathController` | 11 | 重新觸發規則：增加時 / T+60 / T+300，硬上限 4 次；解除才重置；reduce-motion 與低電量永不動 |
> | `BreathAnimator` | — | 12 張預渲染 + 單一 12Hz timer（tolerance 0.02、`.common` 模式）；結束時 **invalidate 並釋放 frame 陣列**，不是暫停 |
>
> 關鍵結構性保證：**動畫的終點值就是物件的靜止值**。frame 0 是全亮，而收工只在回到
> frame 0 時發生，所以物件不可能停在一個還在喊的狀態。離開不做轉場 ——
> 對離開做動畫會訓練眼睛去看一個已經不需要看的東西。
>
> 螢幕睡眠與 session 鎖定會立即停止。呼吸的視窗之外，**這個 app 沒有任何重複性計時器**。
>
> ⚠️ 尚未觀察到實機觸發（目前沒有 session 在等你）。純邏輯有 17 個測試、
> 12 格已用 `--render` 視覺確認，但活的計時器路徑要等下一次權限請求才會跑到。

## Stage 6：statusline tee —— 讓額度數字真的活著

> **已完成（2026-09-18）。169 個 Swift 測試 / 18 個套件，另加 99 項 shell 層測試，全綠。**
> tee 已安裝並實機驗證，面板的 5h/7d 現在是秒級即時。
>
> 完成後跑了一輪六面向的對抗式 code review（含 mutation testing）：29 個發現、
> 27 個經第二個 agent 獨立複驗，21 confirmed / 6 refuted。**21 個全部修掉**，
> 其中兩個是這個 Stage 的招牌承諾本身被打破：
>
> | 模組 | 測試 | 釘住的關鍵行為 |
> |---|---|---|
> | `quotamonster-tee.sh` | 40（shell） | 對 11 種 payload，stdout / stderr / 離開碼與直接跑使用者腳本**逐 byte 相同**；快取是原文；0600；路徑穿越擋掉；umask 還原；不 fork bomb |
> | `install_statusline_tee.sh` | 30（shell） | 只改 statusLine.command 一個字串；備份；逐 byte 還原；四種看不懂的設定一律拒絕 |
> | `StatusLineCacheReader` | 19 | epoch 秒 vs ISO-8601；浮點百分比四捨五入不截斷；缺席 ≠ 0%；已重置的窗口回 nil；0 bytes 與截斷跳過；mtime 當擷取時間 |
> | `UsageSourceSelector` | 11 | 挑新的那個來源；**不做欄位層級合併**；兩邊都沒有回 nil；缺的窗口不回填 |
> | `StatusLineCachePruner` | 7 | 只刪自己寫的兩種檔名；5 分鐘內的 `.tmp.*` 不刪；外來檔案再舊也不碰 |
> | `StatusLineCachePath` | 2 | shell 與 Swift 的快取路徑常數對帳 —— 不一致不會報錯，只會表現成「tee 裝了但還是過期」 |
>
> **實機驗證（`--dump`，安裝後 3 秒）：**
> ```
> 來源 A  ~/.claude.json   1004 分鐘前   5 小時 已用 30%，重置時間已過
> 來源 B  statusline tee      3 秒前     5 小時 10%   7 天 42%   context 34% of 1M
> 採用    statusline tee，live
> ```
> 兩個數字與使用者狀態列上的 `5h:10% 7d:42%` 相同。安裝前後用真實 payload
> 再對過一次 stdout/stderr/離開碼，全部逐 byte 相同（413 bytes）。
>
> | 嚴重度 | 問題 | 修法 |
> |---|---|---|
> | CRITICAL | 快取目錄不可寫（磁碟滿／權限跑掉）時 wrapper 以 rc=1、零輸出收工 —— 使用者的狀態列整條消失 | 結構改成**先把 payload 讀進記憶體**，再盡力寫快取，最後一定把完整 payload 交給內層 |
> | HIGH | `settings.json` 是 symlink 時 `os.replace` 會把連結換成普通檔，dotfiles 倉庫那份被孤立 | 所有讀寫走 `realpath` |
> | HIGH | tee 明明一秒前才寫過檔，面板卻說「沒裝 statusline tee」 | `DataStore` 多記 payload 數，面板才分得出「沒裝」與「裝了但還沒帶到額度」 |
> | MEDIUM | `Int(Double)` 超出範圍會 trap，而 `1e20` 是合法 JSON → 整個 app 當掉 | 非有限值與負數回 nil，正值夾在 1000 以內 |
> | MEDIUM | CRLF 的 settings.json 被 text mode 靜默轉成 LF，「逐 byte 相同的備份」名不副實 | 讀寫都加 `newline=""` |
> | MEDIUM | 選中 statusline 來源時面板說「此方案無此視窗」，等於告訴使用者他沒有 Opus 額度 | 說出真正的原因：這個來源不提供分模型視窗 |
>
> mutation testing 另外指出五個「把實作改壞、測試照樣全綠」的洞，全部補上：
> 安裝腳本的可執行檔檢查、路徑穿越的套套邏輯斷言、reader 的 dotfile 判斷、
> 跨語言路徑常數用 `contains` 比對、以及 shell 測試自己在第一個失敗就中止
> （`set -e` + `pipefail` 遇到 `diff | head`），後面九個案例根本沒跑到。
>
> **寫測試時抓到、不寫測試就會漏掉的兩個 bug：**
> 1. `exec 3< "$tmp" 2>/dev/null` —— 沒帶命令的 `exec` 會把重導向**永久套用到整個 shell**，
>    等於把內層腳本的 stderr 永遠丟進 `/dev/null`。第一次跑 golden 測試就抓到。
> 2. bash 3.2 會把緊接在變數後的全形標點 bytes 當成變數名的一部分
>    （`"...（rc=$rc）"` → `rc\xef: unbound variable`），讓測試中途中斷卻回報離開碼 0。
>    現在測試有 `REACHED_END` 防假綠燈，且全面改用 `${VAR}`。
>
> 兩者與其他 shell 包裝的通則見
> `~/.claude/retrospectives/2026-09-18_quotamonster_shell-wrapper-traps.md`。
>
> **實測到的環境事實（推翻或補充了原本的假設）：**
> - `rate_limits.*.used_percentage` 在真實 payload 裡是**整數**（9、42），
>   但二進位的 `wQe` 會吐出一位小數，所以仍然必須用 `doubleValue` 讀。
> - payload **沒有** `hook_event_name`（那是 hook payload 才有的），也**沒有任何帳號識別**。
> - 已經在跑的其他 session 不會馬上開始寫快取 —— 額度是帳號層級的所以不影響數字，
>   但那些 session 的 context 壓力要等它們自己重新渲染狀態列。
>
> **安裝與還原：**
> ```bash
> bash scripts/install_statusline_tee.sh              # 只看 diff
> bash scripts/install_statusline_tee.sh --apply      # 安裝
> bash scripts/install_statusline_tee.sh --uninstall --apply   # 逐 byte 還原
> ```
> 備份在 `~/.claude/settings.json.bak-20260918-162322`，
> 原本的命令字串原樣存在 `~/.claude/quotamonster-tee.original`。


> **為什麼這不是加分項（2026-09-18 實測證據）**
>
> 動工當下 `~/.claude.json` 的 `cachedUsageUtilization` 已經 **975.7 分鐘（16.3 小時）** 沒更新，
> 寫著 `five_hour 30% / seven_day 19%`；同一時刻使用者的狀態列顯示 `5h:5% 7d:41%`。
> 而且那筆 five_hour 的 `resets_at` 是 `2026-09-17T19:40Z` —— **那個窗口 20 小時前就重置了**。
> 快取描述的不是一個舊的數字，是一個**已經不存在的窗口**。
>
> 純檔案路線在日常使用下不是「晚 5 分鐘」，是「整天顯示已過期」。tee 是唯一的解，
> 也是唯一拿得到 `context_window.used_percentage`（每個 session 的 context 壓力）的途徑。

**目標：** 在使用者現有的 `~/.claude/statusline.sh` 外面包一層 wrapper，把 Claude Code 餵進來的
statusLine JSON 原子寫入快取後，**一個 byte 不差**地交給原本的腳本；Core 端讀這份快取，
讓面板的 5h/7d 變成秒級即時，並多出每個 session 的 context 壓力。

**架構：** shell wrapper（零解析、零判斷、失敗一律退回純轉送）→ 每個 session 一個快取檔
→ `StatusLineCacheReader`（純函式目錄掃描）→ `UsageSourceSelector`（兩個來源挑新的）
→ `DataStore` 單一 slot → 既有 UI 不必改型別。

**成功標準：**
1. `bash scripts/test_statusline_tee.sh` 全綠 —— wrapper 對 11 種 payload 的 stdout / stderr / 離開碼
   與直接執行使用者腳本**逐 byte 相同**
2. `bash scripts/test.sh` 全綠，且新模組的紅燈都親眼看過
3. 安裝後 `swift run QuotaMonsterApp --dump` 顯示的 5h/7d 與使用者狀態列**同一個數字**
4. 使用者的三行狀態列在安裝前後肉眼與 byte 層級都沒有變化

**測試策略：** shell 層走 golden byte-equivalence（對照組 = 直接跑原腳本）；
Swift 層走 unit test 餵 fixture 目錄；最後對**真實 payload** 驗一次（規則見 `~/CLAUDE.md`：
fixture 只涵蓋想得到的情況）。

**狀態：** 未開始

---

### 契約：先釘住，再寫程式

payload schema 與呼叫語意來自兩個獨立來源，且互相對過帳：
`code.claude.com/docs/en/statusline`（官方文件，14/14 條經第二個 agent 重抓驗證）
與 v2.1.276 二進位檔（`U$o` payload builder，`BUILD_TIME 2026-09-18T00:40:43Z`）。

| 事實 | 出處 | 對實作的約束 |
|---|---|---|
| `rate_limits.*.resets_at` 是 **Unix epoch 秒（整數）** | 文件明寫 + 二進位四處互證（`Math.round(h)`、`resets_at*1000`、`MSn` 一年上限過濾） | 必須走 `ResetTimestamp.parse(.epochSeconds:)`。用 `.iso8601` 會得到差幾十年的倒數而且不報錯 |
| `rate_limits.*.used_percentage` 是 **浮點，一位小數** | 二進位 `wQe(t){return Math.round(t*1000)/10}` | 用 `doubleValue` 讀再四捨五入。用 `intValue` 會把 30.6 截成 30 |
| `context_window.used_percentage` 是 **整數**，可能 null | 二進位 `yVt`：`Math.round(r/n*100)` 夾在 0–100 | 與上一列型別不同，不可共用解析路徑。要更細的解析度就自己用 `total_input_tokens / context_window_size` 算 |
| **窗口的 `resets_at` 一過，Claude Code 直接把整個窗口從 payload 拿掉** | 文件「drops a window once its `resets_at` time passes」+ 二進位 `MSn` | **缺席 ≠ 0%。** 缺席時要回 nil 讓 UI 顯示「—」，不可以顯示一條空的安全長條 |
| 只有 `five_hour` / `seven_day` / `spend_limit` 三個窗口 | 二進位 `U$o` 的 rate_limits 字面量 | 這個來源拿不到 `seven_day_opus` / `seven_day_sonnet`（它們只存在於 `/usage` API schema 與 UI 標籤表） |
| **payload 裡沒有任何帳號識別** | 二進位：`accountEpoch` 存在但不序列化 | `expectedAccount` 這條防線對這個來源不存在。不要假裝有 |
| **沒有 `hook_event_name`** | 二進位 `rg -ac 'hook_event_name:"Status"'` → 0 | 不可拿它當「這是 statusline payload」的判斷依據 |
| `session_id` 一定在，且就叫 `session_id` | 二進位 `Sl()` 第一個鍵 | 這是每個 session 的唯一鍵，快取檔名就用它 |
| stdin 是**單行** JSON + `\n`，寫完就關 | 二進位：`JSON.stringify` 無 replacer 無 indent | 仍然要 `cat` 讀到 EOF（文件所有範例都這樣，且單行不是契約的一部分） |
| **新事件觸發時，執行中的 script 會被 abort** | 文件逐字「Claude Code cancels the in-flight script」+ 二進位 `#k(){this.#a?.abort();…}` | 原子寫入（tmp + rename）是**必要條件**，不是防禦性寫法 |
| 300 ms debounce；改 `command` 會跳過 debounce 立刻跑 | 文件 + 二進位 `F$o=300` | 安裝後第一次渲染是即時的，不必等事件 |
| **離開碼非 0 或輸出為空 → 狀態列整條變空白** | 文件 Troubleshooting | 快取寫入的任何失敗都**不可以**讓 wrapper 失敗。錯誤一律吞掉，離開碼與 stdout 完全交給內層腳本 |
| 多行輸出、ANSI 色碼都是官方支援 | 文件 §Display multiple lines | 使用者的三行狀態列在契約之內，不會被截成一行 |
| 子行程環境有 `CLAUDE_PROJECT_DIR` / `COLUMNS` / `LINES`，cwd = session 的 project cwd | 二進位 `wce(h,"StatusLine",…)` | wrapper 不可改動這些；`exec` 交棒可以原樣繼承 |
| `statusLine` 是自己的 settings key，**不是 hook** | settings-reference；只是同受 `disableAllHooks` 開關管轄 | 不違反「不裝 hook」的硬性限制 |
| 未驗證：abort 用的是哪個訊號、有沒有 timeout | 兩個 agent 都標 UNCONFIRMED | 所以 SIGKILL 情境也要能安全收尾（實測會留下 `.tmp.*` 孤兒 → 需要 GC） |

### 快取位置與格式

```
~/Library/Application Support/QuotaMonster/statusline/
    <session_id>.json     ← payload 原文，一個 byte 不改；擷取時間 = 檔案 mtime
    _unkeyed.json         ← 萬一未來 session_id 改名，額度資料仍然進得來
    .tmp.<pid>            ← 寫入中；被 SIGKILL 時的孤兒，由 GC 清掉
```

- 放 Application Support 而不是 `~/.claude/` 底下：那是 Claude Code 的目錄，它自己有 `.last-cleanup`。
  我們的資料放我們自己的地方。路徑有空白，wrapper 的每個變數都加引號，golden 測試含一個空白路徑案例。
- **不另外包一層 metadata。** 快取檔就是 payload 原文，`diff` 得出來、`jq` 讀得動，
  出事時使用者自己就能看懂。擷取時間用 mtime —— payload 裡沒有時間戳。
- 檔名只接受 `[0-9a-fA-F-]{36}`。實測餵進 `"session_id": "../../../../etc/passwd…"` 會落到
  `_unkeyed.json`，沒有逃出目錄。

### Task 6.1：wrapper 腳本與 golden byte-equivalence 測試

**檔案：**
- 建立：`scripts/quotamonster-tee.sh`（repo 是 source of truth，安裝腳本複製過去）
- 建立：`scripts/test_statusline_tee.sh`

**步驟 1：先寫測試。** `test_statusline_tee.sh` 對每個案例跑兩次 —— 直接跑使用者腳本（對照組）
與經過 wrapper —— 然後比對 **stdout、stderr、離開碼**三者。案例：

| 案例 | 釘住的行為 |
|---|---|
| `normal` | 一般 payload，三行輸出完全相同 |
| `empty` | 空 stdin（內層會以非 0 收尾）—— 離開碼也要一致 |
| `not-json` / `truncated` | 內層的 `fallback_prompt` 路徑不可被 wrapper 改變 |
| `no-session-id` / `bad-session-id` | 落到 `_unkeyed.json`，輸出不受影響 |
| `traversal` | `"session_id": "../../../../etc/passwd…"` 不可寫出目錄外 |
| `unicode` | CJK 路徑 |
| `pretty` | 多行 JSON（單行不是契約） |
| `huge` | 200 KB payload |
| `minimal` | 沒有 `rate_limits` / `context_window` |
| `spaced-cache-dir` | 快取路徑含空白 |

**步驟 2：** `bash scripts/test_statusline_tee.sh` → 預期 FAIL（`scripts/quotamonster-tee.sh` 不存在）

**步驟 3：實作。** 順序是刻意的 —— **先寫快取再跑內層**，因為 abort 隨時會來，
而寫入只花 ~1 ms，跑內層要 14 ms。

```bash
#!/usr/bin/env bash
INNER="${QM_STATUSLINE_INNER:-$HOME/.claude/statusline.sh}"
DIR="${QM_STATUSLINE_CACHE_DIR:-$HOME/Library/Application Support/QuotaMonster/statusline}"

# INNER 指到自己會變 fork bomb。-ef 是 bash 內建，不 fork。
if [ "$INNER" -ef "$0" ] 2>/dev/null; then
  cat >/dev/null 2>&1
  printf 'QuotaMonster tee: QM_STATUSLINE_INNER points at the wrapper itself'
  exit 0
fi

# 這之前 stdin 一個 byte 都還沒動，所以失敗可以純轉送。
[ -d "$DIR" ] || mkdir -p "$DIR" 2>/dev/null || exec "$INNER"

tmp="$DIR/.tmp.$$"
trap 'rm -f "$tmp" 2>/dev/null' EXIT INT TERM HUP

old_umask=$(umask); umask 077          # 快取只有自己讀得到
cat > "$tmp" 2>/dev/null
umask "$old_umask"                     # 內層腳本的建檔權限不可被我們改變

# 先抓住 inode，再改名。之後就算別人蓋過同一個路徑，內層拿到的還是這一份。
exec 3< "$tmp" 2>/dev/null || exec "$INNER" < "$tmp"

sid=""
IFS= read -r -d '' head < "$tmp" || true     # 內建，不 fork
if [[ $head =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([0-9a-fA-F-]{36})\" ]]; then
  sid="${BASH_REMATCH[1]}"
fi
[ -n "$sid" ] || sid="_unkeyed"
mv -f "$tmp" "$DIR/$sid.json" 2>/dev/null    # 原子改名；失敗也無所謂，fd 3 還在

exec "$INNER" <&3 3<&-
```

> ⚠️ **這支腳本的每一個錯誤都被吞掉，是刻意的。** 文件明寫：離開碼非 0 或輸出為空，
> 使用者的狀態列會整條變空白。快取寫不進去是小事，狀態列消失是大事。
>
> ⚠️ **`umask` 一定要還原。** 不還原的話內層腳本建立 `/tmp/claude-statusline-git-cache`
> 的權限會從 644 變成 600 —— 我們承諾的是「行為完全不變」。
>
> ⚠️ **不要改成 `read -d '' payload` 省掉 `cat` 那個 fork。** 實測只快 1.5 ms，
> 但 bash 變數放不下 NUL，遇到含 NUL 的 stdin 會把使用者的狀態列餵成截斷資料。
>
> 環境限制：這台機器的 `/bin/bash` 是 **3.2.57**。`read -N` 是 4.1 才有的，不能用；
> `read -r -d ''`、`[[ =~ ]]` + `BASH_REMATCH`、`{36}` 量詞在 3.2 都可用（已實測）。

**步驟 4：** `bash scripts/test_statusline_tee.sh` → 預期 PASS（12/12 逐 byte 相同）

**步驟 5：** 另外手測兩個殺行程情境（寫進腳本註解，不進自動化測試 —— 需要 fifo 與時序）：

| 情境 | 預期 | 實測 |
|---|---|---|
| 讀 stdin 時收到 SIGTERM | trap 清掉 tmp，快取保留上一筆完整值 | ✅ 快取仍是合法 JSON |
| 讀 stdin 時收到 SIGKILL（不可攔截） | 快取檔不受影響，留下一個 `.tmp.*` 孤兒 | ✅ 所以需要 Task 6.6 的 GC |
| 8 個寫入者 × 25 次渲染 × 3 個 session，讀取端持續解析 | 零截斷 | ✅ 194,179 次解析、0 次讀到半個檔 |

**步驟 6：** Commit `feat(tee): add statusline wrapper with atomic cache write`

### Task 6.2：安裝腳本 —— 備份、diff、可解除

**檔案：**
- 建立：`scripts/install_statusline_tee.sh`（`--uninstall` / `--dry-run`）

**步驟 1：** 腳本要做的事，順序不可變：
1. 讀 `~/.claude/settings.json`，確認 `statusLine.command` 目前指向什麼
2. **已經指向 wrapper → 只更新 wrapper，不碰 settings**（可重複執行）
3. 備份 `~/.claude/settings.json` → `settings.json.bak-<timestamp>`
4. 複製 `scripts/quotamonster-tee.sh` → `~/.claude/quotamonster-tee.sh`（chmod 755）
5. 把原本的 command 寫進 wrapper 的 `QM_STATUSLINE_INNER` 預設值 ——
   **不要寫死 `statusline.sh`**，使用者之後改指別的腳本時 tee 仍然對得上
6. 用 `python3 json.load/dump` 改寫 settings.json，**只動 `statusLine.command` 一個字串**，
   其餘鍵與縮排原樣輸出
7. 印出 unified diff 與備份路徑

**步驟 2：** `--uninstall` 把 command 改回備份裡的值並刪掉 wrapper。

**步驟 3：** ⚠️ **安裝前先把 diff 拿給使用者看。** 這是使用者定的規則，不是建議。

**步驟 4：** Commit `feat(tee): add reversible installer for the statusline wrapper`

### Task 6.3：真實 payload 擷取與 fixture

**檔案：**
- 修改：`scripts/capture_fixtures.py`
- 建立：`Tests/QuotaMonsterCoreTests/Fixtures/statusline/*.json`

**步驟 1：** 安裝完成後，真實 payload 會在幾秒內出現在快取目錄。**先看它**，
再決定 fixture 長什麼樣 —— 這是 `~/CLAUDE.md` 的規則：fixture 只涵蓋想得到的情況。

**步驟 2：** 擴充 `capture_fixtures.py` 產生 statusline fixture，沿用既有的
`NOW_MS = 1789660000000`、`FAKE_SESSION`、`sk-ant-` 拒寫規則。要產生的案例：

| fixture | 釘住的行為 |
|---|---|
| `live.json` | 完整 payload，rate_limits 與 context_window 都在 |
| `no_rate_limits.json` | 整個 `rate_limits` 缺席（首次 API 回應之前） |
| `window_dropped.json` | 只有 `seven_day`，`five_hour` 已被 Claude Code 丟棄 |
| `null_context.json` | `used_percentage` 與 `current_usage` 都是 null（`/compact` 之後） |
| `reset_passed.json` | `resets_at` 已經過去（我們自己要再擋一次） |
| `fractional.json` | `used_percentage: 30.6` —— 不可被截成 30 |
| `spend_limit.json` | gateway 才有的第三個窗口 |
| `unknown_keys.json` | 未來版本新增的鍵不可造成解析失敗 |
| `truncated.json` / `zero_bytes.json` | 目錄掃描要跳過，不可丟錯 |

**步驟 3：** Commit

### Task 6.4：`StatusLinePayload` 與 `StatusLineCacheReader`

**檔案：**
- 建立：`Sources/QuotaMonsterCore/Usage/StatusLinePayload.swift`
- 建立：`Sources/QuotaMonsterCore/Usage/StatusLineCacheReader.swift`
- 測試：`Tests/QuotaMonsterCoreTests/StatusLineCacheReaderTests.swift`

**步驟 1：先寫失敗的測試**

```swift
@Test("epoch 秒的 resets_at 解得出正確時間 —— 不是毫秒，也不是 ISO-8601")
@Test("used_percentage 是浮點，30.6 要進位成 31 而不是截成 30")
@Test("context 的 used_percentage 是整數，可能是 null")
@Test("整個 rate_limits 缺席時，兩個窗口都是 nil，不可以是 0")
@Test("Claude Code 已經丟掉的窗口，我們不可以無中生有")
@Test("resets_at 已經過去的窗口回 nil —— 那是一個不存在的窗口的數字")
@Test("讀到 0 bytes 要跳過，不可丟錯")
@Test("截斷的 JSON 要跳過，不可丟錯")
@Test("以點開頭的檔案要略過 —— .tmp.* 是寫入中的孤兒")
@Test("檔名不是 UUID 的檔案要略過")
@Test("目錄不存在時回空陣列，不丟錯")
@Test("擷取時間來自檔案 mtime —— payload 裡沒有時間戳")
@Test("未知的新鍵不可造成解析失敗")
```

**步驟 2：** `bash scripts/test.sh --filter StatusLineCacheReader` → 預期 FAIL（型別不存在）

**步驟 3：實作要點**
- 這是**目錄掃描器**，照 `SessionRegistryReader` 的規矩：**永不丟錯**，壞檔跳過，目錄不存在回 `[]`。
  （⚠️ 不要照 `ClaudeJSONUsageReader` —— 實測它 line 31 用的是 `try` 不是 `try?`，
  格式壞掉會把錯誤丟出來。那是單一具名檔案的規矩，不適用於掃描器。）
- `JSONSerialization` + `as? [String: Any]`，不用 `Codable`（房規，且 payload schema 會長）
- `resets_at` 走 `ResetTimestamp.parse(.epochSeconds:)` —— 這是它第一個 production 呼叫端
- `capturedAt` 取檔案 mtime

**步驟 4：** PASS
**步驟 5：** Commit `feat(core): read live usage and context pressure from the statusline cache`

### Task 6.5：`UsageSourceSelector` —— 兩個來源挑一個

**檔案：**
- 建立：`Sources/QuotaMonsterCore/Usage/UsageSourceSelector.swift`
- 測試：`Tests/QuotaMonsterCoreTests/UsageSourceSelectorTests.swift`

**步驟 1：測試**

```swift
@Test("statusline 較新時勝出")
@Test("statusline 不存在時退回 ~/.claude.json")
@Test("兩個都沒有時回 nil —— 不可以回一個全 0 的快照")
@Test("statusline 較舊時（例如整天沒開 session）退回 ~/.claude.json")
@Test("statusline 只有 seven_day 時，five_hour 不從另一個來源硬湊")
```

> 最後一條是刻意的：兩個來源的 five_hour 可能屬於**不同的窗口**（一個已重置、一個沒有）。
> 把它們拼在同一列會產生一組互相矛盾、但看起來很正常的數字。整筆快照只能有一個來源。

**步驟 2–4：** FAIL → 實作 → PASS

**新鮮度：** 沿用 `ClaudeJSONUsageReader` 的 300 秒 / 3600 秒門檻，不發明第四種狀態。
理由：statusline 是**事件驅動**的 —— 會讓數字變大的活動，本身就是會觸發重新寫入的活動。
所以「舊」在這個來源等於「你沒在用」，而不是「數字不準」。真正會讓它不準的只有窗口重置，
那個已經在 Task 6.4 擋掉了。

**步驟 5：** Commit

### Task 6.6：`StatusLineCachePruner` —— 清掉孤兒

**檔案：**
- 建立：`Sources/QuotaMonsterCore/Usage/StatusLineCachePruner.swift`
- 測試：`Tests/QuotaMonsterCoreTests/StatusLineCachePrunerTests.swift`

**步驟 1：測試**

```swift
@Test("超過 5 分鐘的 .tmp.* 孤兒要刪掉 —— SIGKILL 會留下它們")
@Test("5 分鐘內的 .tmp.* 不可刪 —— 那可能是正在寫的")
@Test("超過 24 小時的 session 快取要刪掉")
@Test("目錄不存在時什麼都不做，不丟錯")
@Test("不是我們的檔案不碰")
```

**步驟 3：** 由 `DataStore` 呼叫，但**不是每 3 秒一次** —— 每分鐘至多一次。

**步驟 5：** Commit

### Task 6.7：`DataStore` 接線與真實資料驗證

**檔案：**
- 修改：`Sources/QuotaMonsterApp/App/DataStore.swift`
- 修改：`Sources/QuotaMonsterApp/Dump.swift`

**步驟 1：** `DataStore.swift:51` 那一行從單一來源變成挑選：

```swift
let fromJSON = try? usageReader.read(home/".claude.json", now: now, expectedAccount: nil)
let payloads = statusLineReader.read(directory: Self.statusLineCacheDirectory, now: now)
usage = UsageSourceSelector.pick(claudeJSON: fromJSON, statusLine: payloads, now: now)
contextPressure = Dictionary(...)   // sessionId → SessionContextPressure
```

下游完全不必改：`GlyphState`、`PanelView`、`StatusItemController` 讀的都是 `UsageSnapshot`。

**步驟 2：** `--dump` 加一段 statusline 來源的輸出：讀到幾個 payload、各自多舊、挑了哪一個來源。

**步驟 3：** 跑 `swift run QuotaMonsterApp --dump`，**用眼睛對** —— 顯示的 5h/7d
必須與同一時刻使用者狀態列上的數字相同。這一步不可省略。

**步驟 5：** Commit

### Task 6.8：面板 —— 額度變即時、多出 context 壓力

**檔案：**
- 修改：`Sources/QuotaMonsterApp/Panel/PanelView.swift`
- 修改：`Sources/QuotaMonsterApp/Panel/SessionRow.swift`

**步驟 1：** 額度三欄不必改版面 —— 資料換了來源，`freshnessText` 自然就不再說「已過期」。

**步驟 2：** session 列加一條 context 壓力細條：
- 沒有讀數顯示 `—`，不是 0%（房規，`PanelView.swift:95` 已有前例）
- 只有主 session 有 statusline payload；subagent 列不顯示
- 顏色門檻沿用使用者狀態列自己的那一組（70% 黃、90% 紅），視覺上才是同一個系統

**步驟 3：** ⚠️ **選單列圖示完全不動。** 設計凍結在 Parallax，使用者指示維持原狀。

**步驟 5：** Commit

### Task 6.9：重跑全部、更新文件

**步驟 1：** `bash scripts/test.sh` 全綠 + `bash scripts/test_statusline_tee.sh` 全綠
**步驟 2：** `bash scripts/make_app.sh` 重新安裝，確認選單列圖示與面板都正常
**步驟 3：** 把 Stage 6 的實測結果寫回本文件（照 Stage 1–4 的格式：模組 / 測試數 / 釘住的行為）
**步驟 4：** Commit

---

## Stage 5：通知層 —— 讓「有人在等你」真的傳達得到

> **已完成（2026-09-18 晚）。296 個測試 / 31 個套件全綠，乾淨 release 建置通過，
> app 已重新安裝並執行中。多角色 review 宣稱 23 項，對抗式查證後剩 2 項屬實，
> 兩項都已修掉。**
>
> | 模組 | 測試 | 內容 |
> |---|---|---|
> | `NotificationEngine` | 48 | T1／T2／T3、去重、合併、靜音。全部無計時器 |
> | `WaitingContextReader` | 10 | transcript 尾端撈待批准的 tool_use。只讀 64KB |
> | `NotifyState` + `MutePolicy` | 15 | 跨重啟的靜音與已通知標記；「明早」的四個邊界 |
> | `OwningApplicationResolver` | 8 | ppid 走訪。Ghostty 要 6 跳，maxHops 給 24 |
> | `WorkflowGroup.runStatus` | 1 | 分辨「全部完成」與「被你停掉」 |
> | App 層 | — | 無測試，所以**沒有任何決策**：只有路由與繪圖 |
>
> **浮窗實機證據（`--demo-alert`）：** `isVisible true` · `level 25` ·
> frame 完全落在 `visibleFrame` 內 · `NSApp.isActive false`（沒搶前景）·
> `keyWindow nil`（沒搶鍵盤焦點）。單一等待 320 × 141pt。
>
> **整條鏈路實機驗證（2026-09-19，`--trace-alerts` + 使用者目視確認）：**
> ```
> [02:10:23] usage-c9  busy → waiting(input needed)
> [02:10:30] ⚡️ T1 有人在等你 · usage · 看得到浮窗嗎 true（閒置 0s）
> ```
> 轉換到發出 **7 秒** = 3 秒輪詢 + 4 秒合併視窗，與設計一致。
>
> **診斷：** `--render-alert <file> --dark`（五種情況一張圖）、
> `--demo-alert`（真的把 NSPanel 叫出來 15 秒，量它到底落在哪）。
>
> 原生 `UNUserNotificationCenter` 不可用（Stage 0 四個變體全失敗），走備援三通道。
> **使用者已拍板的四個決定：**
> - **T1 浮窗走 `Question` 方向** —— 最大的一行是那個 session 真正問出口的句子，
>   不是「usage 正在等待輸入」這種轉述。320×123pt。四份 mockup 在 `alert-mockups/`。
> - **T2 完成 = 選單列圖示瞬時訊號 + 音效**
> - **音效 = `Submarine`**（存成可改字串，`~/Library/Sounds` 的自備音效也吃得到）
> - **osascript 只在你看不到浮窗時才發** —— 螢幕鎖定／螢幕睡眠／session 非前景／
>   閒置 >5 分鐘。看得到浮窗時不重複打擾；真正離開螢幕時事件仍然留得下痕跡。

### 動工前實測釘死的六件事（全部有證據，不要重測也不要繞過）

| # | 事實 | 後果 |
|---|---|---|
| 1 | `osascript` 的 argv 裡**少了 `--` 就是遠端執行**。`-eproperty p:(do shell script "…")` 是合法目錄名，會被 osascript 自己的 getopt 當成另一個 `-e` 片段，而 property 初始值在載入時求值。已實測建出該目錄並取得執行 | 參數陣列裡使用者字串前面**一定**要有 `--`。測試要餵那個字串並斷言檔案沒被建出來 —— 只試 `foo" & (…) & "` 的測試在有漏洞的版本上也會過 |
| 2 | `Process.arguments` 含 NUL byte 會丟 **Swift 接不到的 ObjC 例外**，`do/catch` 救不了，app 當場死。`JSONSerialization` 會從 `~/.claude` 的 JSON 給出帶 NUL 的 String | 進參數陣列前一律 strip NUL + 截長度 |
| 3 | `NSHostingView.acceptsFirstMouse` 預設 **false** | 非前景浮窗裡的 SwiftUI 按鈕會吃掉第一次點擊 —— 使用者點了沒反應，再點一次。必須 subclass 覆寫。這是整個 Stage 5 最容易變成「這東西壞了，刪掉」的一行 |
| 4 | `NSPanel` 預設 `hidesOnDeactivate = true`，且預設 `collectionBehavior` 綁在建立它的 Space | 背景 app 的浮窗會**當場消失**，或在全螢幕 app 裡**從來不出現**（沒有錯誤、沒有 callback）。`isFloatingPanel` 會覆寫 `level`，所以順序是先 `isFloatingPanel` 再 `level` |
| 5 | `AXIsProcessTrusted() == false`、視窗標題受 Screen Recording 管制、三個真實 session 有兩個根本沒有 tty | 「跳過去」**只能做到把擁有它的 app 叫到前面**，做不到指定分頁。ppid 走訪要走 6 跳才到 Ghostty，`maxHops` 給 24 |
| 6 | Focus／勿擾狀態**讀不到**（`~/Library/DoNotDisturb/DB/Assertions.json` 受 TCC 保護，也沒有公開 API） | 設計文件寫的「靠 interruption level 讓系統仲裁」在備援路線上是**過時的**。手動靜音是唯一的防線，所以它必須存到磁碟 |

### 與設計文件的兩處刻意偏離（連同理由）

1. **T3 額度門檻不用 70%／90%，改用 `QuotaTier` 的降級（剩 50%、剩 20%）。**
   `GlyphState.swift` 已經寫死一條規則：「⚠️ 門檻只能定義在 `QuotaTier.forRemaining`」。
   再引進第二組門檻，就會出現「圖示已經變紅、但通知說你還在 70% 那一格」這種
   不一致，而且不會有人馬上發現。改成「顏色變了的那一刻」發一次瞬時訊號 ——
   訊號與顏色講的是同一件事。
2. **音效用 `NSSound(named:)`，不是設計文件寫的 `AVAudioPlayer`。**
   AppKit 會快取 named 實例：不必自己持有 strong reference（`AVAudioPlayer` 少了
   這步，區域變數一釋放聲音就斷）、播放中再呼叫 `play()` 直接回 false。
   不需要往 repo 加任何音效檔，`Package.swift` 與 `make_app.sh` 都不動。

---

### Task 5.1：`WorkflowGroup` 帶上 run 狀態

**檔案：** 改 `Sources/QuotaMonsterCore/Agents/AgentTree.swift`、
`Sources/QuotaMonsterCore/Agents/AgentTreeBuilder.swift`；
測試 `Tests/QuotaMonsterCoreTests/AgentTreeBuilderTests.swift`

`AgentTreeBuilder` 已經算出 `terminated`，但把 status 丟掉了。被 TaskStop 停掉的 run
會讓**每一隻** agent 變成 `.finished`，於是 `finishedCount == total` —— 不帶 status
的話，T2 會對一個你自己停掉的 run 說「7 個 agent 全部完成」。這個 repo 已經為這個
欄位寫過一次 retrospective（`2026-09-18_quotamonster_aborted-workflow-phantom-agents.md`）。

**測試：** run 狀態是 `killed` 時 `group.runStatus == "killed"`；檔案不存在時是 nil。

### Task 5.2：`NotificationEvent` —— 通知的資料形狀

**建立：** `Sources/QuotaMonsterCore/Notify/NotificationEvent.swift`

三個 case，全部 `Equatable, Sendable`，**沒有任何 AppKit 相依**。
`waiting` 帶 `[WaitingSession]`（一次一個或合併多個）、`coalesced`、`isRepeat`；
`batchDrained` 帶 workflowId／phase／total／duration／outcome；
`quotaTier` 帶新舊分級。每個 event 帶一個**穩定字串**的 `dedupKey`。

⚠️ **去重鍵絕對不可以用 `hashValue`。** Swift 的 `Hasher` 每個行程重新設種子，
存到磁碟的 hash 下次啟動就對不上，去重會**安靜地**停止運作。

### Task 5.3：`NotificationEngine` —— T1，一個等待事件只喊一次

**建立：** `Sources/QuotaMonsterCore/Notify/NotificationEngine.swift`
**測試：** `Tests/QuotaMonsterCoreTests/NotificationEngineTests.swift`

形狀完全照抄 `BreathController`（純 struct、時間用參數注入、`defer` 記上一輪、
硬上限在所有觸發分支之前、解除就整組重置），兩處刻意不同：
- **回傳 `[NotificationEvent]` 而不是 `Bool`** —— session A 的 T1 與 workflow B 的 T2
  可以在同一拍發生，`BreathController` 一次只回得了一件事。
- **狀態是 keyed map 而不是純量**，因為去重是 per session／per workflowId。

**一個等待事件（episode）的身分是 `(sessionId, statusUpdatedAt)`，不是「看到轉換」。**
理由：三秒輪詢常常會整拍錯過中間那段 busy —— 你回答完一個問題，Claude 馬上又要求
批准工具，`waiting → busy → waiting` 可能發生在同一拍之內。靠「看到離開 waiting」
來判斷新事件，會讓實際使用上**最常見**的那一種等待完全不發通知。
`statusUpdatedAt` 就是那個判別器，而且它已經在 `ClaudeSession` 裡了。
沒有 `statusUpdatedAt` 的舊版本才退回「看到轉換」。

**第一次觀測到的等待不發通知。** app 剛啟動時就已經在等的 session，我們沒有見證
它進入等待，不算一次我們見證的事件。少掉的只有那一次打斷 —— 圖示本來就已經是
琥珀色而且在呼吸，資訊一點都沒少。這條規則讓「啟動時對著三個 session 同時尖叫」
在結構上不可能發生，而開發期間 `make_app.sh` 會不斷重啟這個 app。

**測試清單：**
- 第一次觀測到的等待不發
- 見證進入等待 → 發一次
- 持續等待 → 不再發
- 恰好在 T+300 再推一次，之後永遠安靜
- `statusUpdatedAt` 變了（沒看到中間的 busy）→ 算新事件
- 沒有 `statusUpdatedAt` 的舊版本 → 退回轉換判定，不 crash
- 離開等待 → 整組重置，下一次拿回完整預算
- **同一個 `now` 連呼叫兩次只會發一次**（`refresh()` 有六個呼叫點，開面板時會在
  幾毫秒內被呼叫兩次）

### Task 5.4：去重與合併

**同檔，另一個 `@Suite`。**

- 相同 `dedupKey` 60 秒內抑制
- 合併視窗 4 秒：同類事件 ≥3 則合成一則摘要（一個視窗、一個計數，不是三個視窗）
- ⚠️ 合併視窗代表**單一 T1 也會延後 4 秒**。可以接受，理由要寫在程式碼裡：
  選單列圖示在**同一拍**就已經變琥珀並開始呼吸（`BreathController` 吃的是同一份
  資料），瞬時訊號早就發出去了；4 秒的窗口只用在比較重的那個打斷上。

### Task 5.5：T2 —— 扇出整批排空

**同檔，第三個 `@Suite`。**

**「排空」只能用正面證據定義：** `total > 0 && finishedCount == total`，
**不是** `runningCount == 0`。`.unknown` 不計入 `finishedCount`，所以讀不到 journal
的情況永遠滿足不了這個條件。這就是 `runningAgentCount` 那條「寧可少報，不謊報」
套用在事件上。

**另外三條硬規則：**
- **必須先看過同一個 `workflowId` 還沒完成的樣子**（`everObservedIncomplete`）。
  否則「app 啟動前就已經跑完的那批」會在啟動時發一則。
- **絕不聚合。** T2 只能 per `workflowId`。`DataStore.runningAgents` 是全 session
  加總，用它會在「workflow 排空、但還有 10 隻一般 agent 在跑」時說「整批完成」。
- **不存在不等於排空。** key 消失的那一拍不可以刪掉狀態；留著 `lastSeen`，
  要連續 2 次觀測不到**且**超過 30 秒才過期。這是 Stage 5 唯一一處必須比
  `BreathController` 更保守的地方（它是 `blockedCount == 0` 就當場重置）。
- `peakFinished` 單調不減 —— journal 暫時讀不到不可以讓進度倒退。

**`runStatus` 的用法：** `killed` → **完全不發**（是你自己停的，你知道）；
`failed` → 發，但措辭是失敗不是完成；其餘 → 「全部完成」。

**並且明確測出來：** 一般 Agent 扇出永遠不會發 T2 —— 它的每個節點都是 `.unknown`，
沒有正面證據。這是 Stage 2 的已知缺口，不是這裡的 bug。

### Task 5.6：T3 —— 額度分級降級

**同檔，第四個 `@Suite`。**

`QuotaTier` 變差時（comfortable→tight、tight→critical）發一次瞬時訊號，不出聲、
不浮窗。變好不發。**讀數過期或沒有讀數時什麼都不發** —— 對一個你自己都知道
不可信的數字發通知，比不發更糟。

### Task 5.7：靜音

**建立：** `Sources/QuotaMonsterCore/Notify/MutePolicy.swift`

`mutedUntil` 抑制**全部**三級。「靜音 1 小時」與「靜音到明早」（下一個 08:00）。
**不自建安靜時段排程器** —— macOS Focus 已經做了，第二個排程器正是「明明開了
勿擾卻在半夜三點響」的成因。

被靜音的事件是**丟掉**，不是排隊：狀態照樣往前走，所以解除靜音不會一次爆出一串。

### Task 5.8：`NotifyState` —— 跨重啟活下來的那一小塊

**建立：** `Sources/QuotaMonsterCore/Notify/NotifyState.swift`
**路徑：** `Library/Application Support/QuotaMonster/notify-state.json`

只存兩樣：`mutedUntil`、每個 session 最後通知過的 episode 鍵與時間。
60 秒去重窗與 4 秒合併窗**不存**（都比任何一次重啟短，存了沒用還要每 3 秒寫檔）。

寫檔慣例整份抄 `UsageHistory`：`.atomic` 整檔重寫、錯誤全吞回 `Bool`、
壞檔回 nil 不丟錯、`start()` 時從磁碟讀回記憶體。寫檔時順手丟掉超過 24 小時的
session 條目，**這樣就不必動到 pruner** —— `StatusLineCachePrunerTests` 明講
「pruner 是整個 Core 唯一會刪檔的東西」，那句話要繼續成立。

### Task 5.9：`WaitingContextReader` —— 那個 session 到底在問什麼

**建立：** `Sources/QuotaMonsterCore/Notify/WaitingContextReader.swift`

Question 方向的那一行英雄字要有來源。session 註冊表只有「在問你問題／等你批准
工具」兩種分類，沒有內文；內文在 transcript 尾端最後一則 assistant 訊息的
`tool_use` 裡（已實測：`AskUserQuestion` 的 `questions`、Bash 的 `description`
與 `command` 都在）。

⚠️ **絕不在 UI 路徑上整檔解析。** 活躍 transcript 實測 480KB–878KB。
只在**要浮窗的那一刻**讀一次尾端（seek 到結尾往回抓固定 byte 數），
不是每 3 秒。讀不到就退回分類文字，不是空白。

### Task 5.10：`OwningApplicationResolver` —— 跳過去要跳到哪

**建立：** `Sources/QuotaMonsterCore/Sessions/OwningApplicationResolver.swift`

pid 往上走 ppid，回傳第一個「是個 GUI app」的 pid。兩個相依（取 parent、判斷是不是
app）都用注入的 closure，測試餵假的行程樹。`maxHops = 24` —— 真實的 Ghostty 鏈走了
**6 跳**，給 4 會安靜地失敗。production 的 `parentOf` 走 `sysctl(KERN_PROC_PID)`，
跟 `ProcessLiveness.processStartTime` 共用同一次呼叫，**不要生 `ps`**。

**在按下去的當下才解析，不要在建面板時就算好。** 擁有者是從活的行程樹推出來的，
快取起來會過期，然後把一個被回收的 pid 叫到前面。

### Task 5.11 ~ 5.15：App 層（沒有測試，所以不可以有任何決策）

- `Alert/FirstMouseHostingView.swift` —— 覆寫 `acceptsFirstMouse` 回 true
- `Alert/AlertPanelController.swift` —— NSPanel，設定順序是載重的（先
  `isFloatingPanel` 再 `level`）、`hidesOnDeactivate = false`、
  `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`、
  `orderFrontRegardless()` 而不是 `makeKeyAndOrderFront`。位置夾在 `visibleFrame`
  裡（同時解決瀏海與「level 25 蓋住選單列」兩件事）。滑鼠在上面時取消收起計時器。
  **session 一離開等待就立刻拆掉** —— 對著一個你已經回答過的問題繼續喊，
  就是那個刪 app 的瞬間。
- `Alert/AlertView.swift` —— Question 方向的 SwiftUI
- `Alert/AlertSound.swift` —— `NSSound(named:)` + 啟動時預熱（冷啟動第一聲要 97ms，
  之後 8ms）
- `Alert/OSAScriptNotifier.swift` —— `--` + strip NUL + 絕不 `waitUntilExit()` +
  10 秒看門狗
- `Alert/ScreenPresence.swift` —— 鎖定／螢幕睡眠／閒置的免授權探測
- `Alert/NotificationPresenter.swift` —— 決定走哪個通道
- 改 `App/DataStore.swift`：在 `trees = built` 之後、`lastRefresh = now` 之前驅動
  引擎，外面包一個 `deliversNotifications` 旗標（與既有的 `recordsHistory` 同理 ——
  `--dump` 與 `--render-panel` 也會建 DataStore 並呼叫 `refresh()`，不擋的話
  跑一次診斷就會浮出一排視窗）
- 改 `Panel/PanelView.swift`：footer 加靜音
- `Panel/RenderAlert.swift` —— `--render-alert <file> --dark` 診斷。
  ⚠️ **配色一定要用深色版本檢查**，這個專案已經在淺色渲染上看走眼兩次

### Task 5.16：驗收

- `bash scripts/test.sh` 全綠
- **`rm -rf .build && swift build -c release`** —— 增量建置的 `Build complete`
  是假象，retrospective 有紀錄
- `--render-alert` 深色目視
- 裝起來實機等一次真的等待事件

---

## Stage 7：燒量速率與觸頂預測

> **步驟 0–9 已完成（2026-09-19）。358 個測試 / 35 個套件全綠，乾淨 release
> 建置通過，app 已重新安裝並執行中。步驟 10（heartbeat）與 11（7 天最近速率）
> 依決策暫緩 —— 見下方。**
>
> | 模組 | 測試 | 內容 |
> |---|---|---|
> | `UsageProjection` | 13 | 窗口均速與重置時投射。**不需要歷史**，第一次啟動就正確 |
> | `UsageBurn` | 14 | 分段 Theil–Sen。期望值全部對著真實位元組算出來 |
> | `UsageOutlook` | 10 | Core 與 App 唯一的縫。升級規則在這裡 |
> | `OutlookCaption` | 18 | 所有字串。「拒絕時與今天一模一樣」是 `#expect` 不是承諾 |
> | `MutePolicy.next` | 3 | 順帶修掉一個按不到的靜音選單 |
> | `UsageHistory.prune` | 3 | 順帶修掉每分鐘重寫整個檔案 |
>
> **實機輸出（`--dump`）：** 7 天已過 93%、均速 0.33 %/小時 → 重置時約 55%；
> 5 小時在重置後 45 分鐘內拒絕，而且說得出理由。
>
> **面板高度 444 → 442pt**（靜音鍵從 Menu 換成循環鍵時省下的），
> 新功能本身是 0pt。
>
> 一句話：**數字來自窗口自己**（`percent / elapsed`，不需要歷史，第一次啟動就正確），
> **歷史只當形容詞**（最近的節奏比均速快還是慢），永遠不可以取代那個數字，
> 也永遠不可以在沒有那個數字的時候單獨出現。

### 動工前實測釘死的五件事

| # | 事實 | 後果 |
|---|---|---|
| 1 | **5 小時序列是鋸齒。** 實測 `32 → null → 1`（18:00 / 18:44 / 19:45）、`7 → null → 0` | 跨重置點做斜率會得到巨大**負值**。分段必須靠 `windowStart` 在**結構上**擋掉，不是靠偵測重置 |
| 2 | **窗口內不單調。** 實測 17:46–17:47 的 `27, 26, 27, 26, 27` —— 兩個來源在邊界上差 1 個百分點 | 相鄰點差分在正常運作下就會產生負燒量。最小配對間隔 180 秒是那個 45 秒振盪簇的四倍，**這一個常數就是全部的抗噪能力** |
| 3 | **null 出現在序列中間**（26 筆裡 2 筆） | null 是洞，不是 0，也不是重置訊號 —— `StatusLineCacheReader` 會丟掉過期窗口而 `~/.claude.json` 會留著，而 JSONL 沒有記來源，所以 null 無法還原成任何一種 |
| 4 | **空隙有歧義。** `shouldRecord` 只在數字變動時才寫，所以 3.5 小時的空隙代表「沒變」**或**「app 沒開」，檔案裡分不出來 | 把空隙當零燒量＝把關機時間算成你很省。超過 1200 秒就切斷，不橋接（實測活動期內最大間隔 817 秒、活動期之間最小 2646 秒，1200 落在這道空帶正中央） |
| 5 | **百分比是整數**，`rate_limits` 沒有絕對 token 數 | 7 天窗口一小時走 0.3–0.6 個點，**1.5–3 小時才跳一格**。短於三小時的「最近速率」量到的是量化誤差 |

### 三個定案（評審建議，已採納）

1. **5 小時欄永遠不印時鐘時間。** 只有「估 49%」，越過 100% 時升級成「會觸頂」。
   設計一原本要印時鐘，而它的門檻 `0.05` 是從 `UsagePace` 抄來的 —— 那個常數是為
   **7 天**窗口挑的（5% = 8.4 小時），放到 5 小時窗口上只有 **15 分鐘**。
   把實測最快的那一段（22.52 pp/h，17:46:49–18:00:37）放在剛重置的窗口起點，
   t+15m 就會投射出 120% 並印出一個時鐘時間 —— 而實測那兩個窗口最後分別停在
   32% 與 ≤7%，那段突發只持續了 14 分鐘。**門檻改成 0.15（45 分鐘）**，
   在實測資料上一毛錢都不花。
2. **「日均 8.8%」留著**，只在 7 天投射真的越過 100%（且窗口已過 30%）時
   才替換成「會用完」。直接換成「屆時 82%」會讓每個 7 天窗口的前 2.1 天
   失去一個現在就能用的數字。
3. **heartbeat 先不做。** 程式碼很便宜，但它會改變「檔案裡沒有那一行」的意思，
   而那是不可逆的語意變更。等投射與箭頭實際跑一陣子再決定。

### 兩欄的寬度預算是相反的（實測 `NSFont.systemFont(ofSize: 9)`，每欄 99pt）

- **第一欄**今天是 `剩 1h 44m` = 44.1pt，**還有 55pt 空位** → 可以用「加」的
- **第二欄**今天是 `週六 下午1:59 · 日均 8.8%` = 109.9pt，**已經縮到 0.90** → 只能用「換」的

所以箭頭只出現在第一欄。`週六 下午1:59 · 日均 8.8% ↑` 是 119.8pt（縮到 0.83），不行。

**高度成本 0pt** —— 全部落在既有的 caption 行裡，不加新列、不加卡片。

### 兩個窗口需要不同的估計法

7 天窗口**唯一誠實的估計法就是它自己的均速**，因為那個分母裡已經包含了你睡覺的時間。
把最近速率乘以七天，正是這個專案禁止的那種「很有自信的錯」。
5 小時窗口兩個都要：均速給數字，最近速率給形容詞。

---

### 建置順序（每一步結束都可以 commit）

| 步 | 內容 | 出貨了嗎 |
|---|---|---|
| **0** | `UsageHistory.pruneInterval = 3600`，DataStore 把歷史清理與 statusline 清理拆開 —— 現在歷史檔每 60 秒被整檔解析重寫一次 | 純效能，今天就對 |
| **1** | 抽出 `UsagePace.elapsed` 共用守衛，`dailyAverage` 的 5 個測試不准動 | 純重構 |
| **2** | `UsageProjection` —— **最重要的一步**。11 個測試，前三個編碼上面那個 kill | Core |
| **3** | 接上第一欄。**功能在這裡就活了，而且完全不需要歷史** | ✅ 出貨 |
| **4** | `UsageBurn.recentRun` —— 分段、丟 null、切空隙。先把真實的 28 行存成 fixture | Core |
| **5** | `UsageBurn.theilSen` —— 最小配對間隔。控制組測試要證明 OLS 在同一組點上是負的 | Core |
| **6** | 組出 `BurnOutcome`，每個具名拒絕一個測試 | Core |
| **7** | `UsageOutlook` —— Core 與 App 之間唯一的縫。升級規則在這裡 | Core |
| **8** | `OutlookCaption` —— **所有字串放 Core**，因為 App 測不到而字串就是風險所在 | Core |
| **9** | 接上箭頭與 tooltip | ✅ 出貨 |
| — | `--dump` 多一段展望 | ✅ 出貨（面板上「沒有箭頭」與「沒有投射」看起來都是一片安靜，只有這裡說得出為什麼） |
| 10 | heartbeat + bootMarker | ⏸ 等使用者點頭 |
| 11 | 7 天的最近速率與「會用完」升級 | ⏸ 等兩天資料 |

### 使用者會注意到、而且應該先講的一件事

**每次 5 小時窗口重置後的前 45 分鐘，第一欄顯示的東西跟今天一模一樣。**
一天大約五次。那是門檻在做它該做的事，不是壞掉。

### 做的時候才發現的三件事

1. **`UsagePace` 的 0.05 門檻搬不過來，而且是最危險的一種搬不過來。**
   詳見上面的定案一。這是整個 Stage 最重要的一個常數。
2. **靜音的 SwiftUI `Menu` 要換掉，但理由的分量要分清楚。**
   **已證實：** 它在離屏渲染下畫成一個紅色禁止符號，於是 `--render-panel`
   對那個角落說不出真話 —— 而那是這個專案唯一的視覺檢查手段。
   **未證實：** `.transient` 的 popover 很可能在 Menu 開視窗的那一下自己關掉
   （文件支持，但我沒有實機驗證）。換成單鍵循環之後兩個都不必再問。
   ⚠️ 這一條當初在 commit 訊息裡被寫成已證實，那是誇大了。
3. **7 天欄的拒絕理由需要自己的 case。** 一開始沿用「歷史還是空的」，
   但那是一句小謊 —— 它會讓人以為再等一陣子就會有箭頭，而 7 天窗口
   在簽章上就拿不到歷史，那永遠不會發生。

### 升級規則（這條是把兩個設計接起來的關鍵）

`.exceedsWindow` 只有在**均速說會**、**而且最近速率存在**、**而且它的 Q1 也超過**
的時候才會渲染成「會觸頂」那三個字。任何一個單獨都不准產生那個警示字串。

---

## Stage 8：完成訊號（已實作）

> **✅ 2026-09-19 完成。** 469 測試 / 47 套件全綠，乾淨 release 建置通過，
> app 已重裝重啟。四個 commit：尾端判讀 → 狀態機與衰退 → GlyphState → 接線與顯示。
>
> **⚠️ 動工後被實測推翻或修正的六件事，全部記在下面的「實作時才知道的」一節。**
> 其中兩件會讓功能完全失效（拿 `isWorking` 當「又動起來了」、沿用 `locate()`），
> 一件是計畫書自己寫錯的觸發規則。

### 實作時才知道的（每一條都改了設計）

1. **「沉澱窗本身就是偵測」這句話會誤導實作。** 安靜只決定**何時去看**，
   決定**完成沒**的是尾端那一則的 `stop_reason`。這個分工是整個方案的救命符：
   〔實測〕13,733 個回合進行中的間隔裡有 105 個超過 90 秒（長 Bash 66.7%、
   模型想很久 20.0%、使用者在打字 11.4%），但那些時點往回看到的全部是 `tool_use`
   —— **誤報 0 次**。一個跑 40 分鐘的 Bash 在架構上就不可能誤觸發。
2. **原本寫的「且內容是 text 不是 tool_use」是冗餘的**（`stop_reason` 本身就分開了
   兩者）。⚠️ 但它的危害被高估過：在 90 秒窗下拿掉它額外漏掉的只有
   「回合真的停在 thinking-only 那一行」，〔實測〕全庫 **1/153**。
   真正的問題是它把正確性偷偷綁死在沉澱窗長度上 —— 兩行式 end_turn 的間隔
   〔實測 n=153〕中位 12.2 秒、**最大 51.8 秒**，窗一縮到 45 秒就開始漏。
   **所以「拿掉 content 檢查」與「沉澱窗 ≥ 60 秒」是綁在一起的兩個決定。**
3. **真正會誤報的機制計畫書沒寫到：你剛按下 Enter、模型還沒吐第一行。**
   〔實測〕479 個以真人訊息為起點的間隔裡有 6 個（1.25%）超過 90 秒（最長 623 秒），
   那些時點的尾端是**上一輪的** end_turn。修法免費且在同一次讀取裡：
   **要求那則 end_turn 之後沒有任何真人訊息**。這同時吃掉 Esc 那道閘。
4. **「真人訊息」的判準兩個方向都會錯。** 正確的是
   `type=="user" && isMeta != true && content 裡沒有 tool_result`，
   而且**字串與 list 兩種形狀都要收**。〔實測〕字串型 382 則裡有 **93 則
   `isMeta=true`**（skill caveat／圖片占位／slash command 展開／agent 間訊息），
   而**貼截圖的真人訊息 105 則全部是 list**。
5. **計畫書的 `ranFor` 算法做不到。** 原文要求從 64KB 尾端回推到該輪第一則真人訊息，
   但〔實測 n=337〕回合起點到 end_turn 的 byte 距離中位數 **114,059 B**，
   整個回合塞得進 64KB 的只有 **37.4%**。改成在「安靜→又動起來」那一刻讀一次，
   〔實測〕命中率 **84.1%** —— 所以約六分之一的完成**不會有秒數**，面板整格不畫。
6. **`SessionDirectoryResolver.locate()` 不能拿來找 transcript。** 它硬性要求
   `<sessionId>/` 目錄存在，而〔實測〕40 個 transcript 只有 **15 個**有。
   活著的 session 剛好都有（都跑過 Task），所以這個洞在真機上看不出來，
   但下一個新開的終端機第一次跑到回合結束時會整個消失。

### ⚠️ 差點犯的那個致命錯

顯示規格原本要拿 `LiveSession.isWorking` 當「又動起來了」的證據 ——
而**這一節自己量過 `status` 是黏著的**（下面那張表）。回合結束那一刻 session
幾乎一定還是 busy／shell，標記會在產生後的第一拍就被清掉：
**丁香紫一次都不會亮，而且所有單元測試都會綠**（測試餵的是手捏的 LiveSession）。
唯一可信的證據是 **transcript 的 mtime 前進**，所以
`FinishCaption.prune` 的簽章刻意**不接受 `[LiveSession]`**。

### 音量：計畫書的 1.6 則／天複驗不出來

把整條偵測鏈在全語料上**模擬跑過**〔實測，模擬〕：
門檻 180s → **8.12 則／活躍日、最忙一天 26 次**；600s → 5.17／19；1800s → 3.00／11。
**使用者 2026-09-19 選 600 秒**（`FinishGlow.minimumInterestingRun`），
理由是它與 `goneSeconds` 同一個數 ——「亮的時間不超過跑的時間」講得出口。

⚠️ **「九道閘」與「92.6% 吞掉」不可以再出現在任何文件或註解裡。**
三道複驗得出來的：跑不到 3 分鐘〔實測〕**五成到七成，取決於回合起點怎麼定義**
（四個獨立量測得到 57.9 / 58.5 / 65.5 / 72.2%）、90 秒內又打字了〔實測〕24.4%
（而且**沉澱窗本身就是這道閘**，不需要另外寫）、Esc 中斷〔實測〕**1/335 = 0.3%**
（計畫書寫 2%；全庫只有 7 個中斷標記，其中 6 個落在 tool_use 上 ——
那裡根本沒有完成訊號可擋，這道閘在那裡是空轉的）。
另外兩道（人不在、那個 app 在最前面）**transcript 裡沒有任何欄位可以重建**，
既不能證實也不能證偽。

### 刻意沒做的兩件（mockup 有，計畫書沒帶過來）

- **`Purr` 音效。** `glyph-signal.html` 寫「同時響一聲 Purr」，但使用者拍板的是
  「餘光＋勾」。要出聲就得先過 T2 剛裝好的在場閘與 `SoundBudget`，
  而 T2 那一節自己立過規矩「主動訊號要先 shadow 量過再開」。
- **「未讀」那第二個鐘**（勾一直等到你打開面板、「58 分前完成」）。
  它要一份 seen 集合、一個 popover 開啟的掛勾、一條 24 小時上限，
  而且它是整個 mockup 裡唯一會說一小時謊的東西。

---

> **狀態：使用者已選定顯示方式；觸發條件在設計後被實測推翻，已改。**

### 顯示（使用者 2026-09-19 選的，兩個疊起來）

> **✅ 丁香紫已在 2x 下由使用者看過並拍板留下（2026-09-19）。**
> ⚠️ 過程中發現 `--render` 一直只寫 1x 與 8x，而這台機器是 Retina ——
> 選單列把 22pt 畫成 **44 個裝置像素（2x）**，也就是說**使用者每天真正看到的
> 那個尺寸從來沒有被渲染過**。mockup 寫「必須在 1x 下看」沒錯（那是最壞情況，
> 外接非 Retina 螢幕），但只看 1x 等於在一個他每天不會遇到的條件下判配色 ——
> 與這個 repo 犯過兩次的「用淺色渲染判斷」是同一類錯。`--render` 現在寫三種倍率。

同一件事的兩種放大倍率：

- **選單列 = 餘光（`finished-mockups/glyph-signal.html`）。** 生物核心染上丁香紫
  `#E08CFF`（色相 284°，色相環上唯一沒有鄰居的空地；距琥珀 112°、距最近的額度藍 67°），
  眨一次眼，滿色 180 秒 → 退色到 600 秒 → 乾淨消失。
  **像素不與琥珀重疊**（琥珀在 r=7.25 外圈，丁香在 r≤2.15 核心），節奏相反
  （眨一次 vs 重複呼吸），而且有人被擋住時完成訊號整批丟掉 —— 結構上不可能同時出現。
- **面板 = 細節（`finished-mockups/quiet-panel.html`）。** 那一列的 header 行換三個欄位
  （圓點→勾、`IDLE`→`剛完成`、存活時間→`跑了 12m 04s`），加一條坐在卡片上緣、
  10 分鐘內排空的鮮度線。高度成本 0pt。

⚠️ **一處刻意偏離 mockup（使用者 2026-09-19 已同意）：
`quiet-panel` 用的完成綠 `#30D158` 不用，改用丁香紫。**
兩個理由：(1) 它與 `SessionRow.contextColour` 在 ctx<70% 時的綠是**同一個色值**，
完成那一列會有兩條綠疊在一起（mockup 作者自己畫的時候撞到並記下來了）；
(2) 選單列說「完成＝丁香紫」、面板說「完成＝綠」就是兩套語彙，
而這個 repo 已經為這件事立過規矩（`QuotaPalette` 存在的唯一理由）。
**面板的勾與鮮度線一律用丁香紫**，與選單列同一份定義。

### ⚠️ 觸發條件：`busy → idle` 是錯的，實測推翻

設計階段假設「session 進入 `idle` ＝ 這一輪做完了」。**那是錯的。**

`ProcessLiveness.swift` 早就寫下過一半的答案：「session 檔沒有 heartbeat ——
`status` 只在狀態轉換時寫入，實測有 session 已宣稱 busy 41 分鐘」。
2026-09-19 的實測把另一半補完了：

| session | 註冊表 `status` | transcript 尾端 | 真實情況 |
|---|---|---|---|
| usage-c9 | `busy` | `tool_use` | 正在跑 ✓ |
| f1-e3 | **`busy`** ❌ | `text` · `stop_reason=end_turn` | 29 分鐘前就講完了 |
| f1-73 | `idle` | `text` · `stop_reason=end_turn` | 13 小時前講完 ✓ |

`status` 是**黏著的**：它停在最後一次活動。實測我自己的回合結束後七分鐘，
session 一直回報 `shell`（因為回合最後一個動作是 `git commit`），從來沒有進 `idle`。
而 `idle` 出現時也不是「剛做完」——`f1-73` 的 `statusUpdatedAt` 是 13 小時前。

**改用 transcript 尾端，那才是直接證據：**

- 「這一輪講完了」＝ 最後一則 assistant 訊息 `stop_reason == "end_turn"`
  且內容是 text 不是 `tool_use`
- 「還在跑」＝ `stop_reason == "tool_use"`
- **`ranFor`** 從 transcript 時間戳算（該輪第一則使用者訊息 → 最後一則 assistant），
  比黏著的 `statusUpdatedAt` 準得多

**成本控制（照設計文件的既有規則）：** 只用 `stat()` 取 mtime，
**沉澱窗本身就是偵測** —— 某個 transcript 連續 90 秒沒有被寫入，才做**一次**
64KB 的尾端讀取確認 `end_turn`。三個 session 一天大概讀幾十次，不是每三秒。
`WaitingContextReader` 已經解掉尾端讀取的每一個難處（64KB 視窗、被截斷的半行、
NUL），直接沿用。

### 九道閘與音量（規則組算的，全文見 workflow 輸出）

典型 **1.6 則／天**、最忙 3.7 則／天，92.6% 的完成刻意吞掉。
擋掉最多的三道都是實測的：跑不到 3 分鐘（66%）、90 秒內你又打字了（25%）、
你按了 Esc 中斷（2%）。另外兩道（人不在、那個 app 在最前面）是**估計**，
若它們無效，上限是 12.5 則／天 —— 所以主動訊號要先 shadow 量過再開。

### 動工前要先修的既有 bug：T2 有四個洞，不是兩個

> **✅ 2026-09-19 四個全部修完。** 390 測試 / 38 套件全綠（+28），
> `rm -rf .build` 後的乾淨 release 建置通過，app 已重裝並重啟。
> 四個 commit：文件 → 觸發點 → 在場閘 → 預算。
> 實機驗證：`--trace-alerts` 當下印出
> `在場 鎖定 true 螢幕睡 true 閒置 485s · 值得出聲嗎 false · 看得到浮窗嗎 false`
> —— 正是計畫書抓到的那一格，現在它不會出聲了。
>
> 底下保留原始的診斷紀錄，因為每一個數字都是新閘的常數的理由。
> **還沒修的三項列在本節最後。**

> **2026-09-19 量測，三份獨立腳本 + 一次對抗式讀碼。**
> 原文只寫了「沒有在場判斷、沒有預算」。實際去量之後，前面還有兩個更嚴重的，
> 而且**順序不能顛倒**（理由見最後一段）。

#### ① 它在錯的時刻響

`WorkflowGroup.total` 是 `agents.count`（`AgentTree.swift:51`），而 agents 只數
**目前目錄裡存在的 meta 檔**（`AgentTreeBuilder.swift:88-92`）。多階段 pipeline 在
階段交界時，上一階段全部 `.finished`、下一階段還沒 spawn —— `finishedCount == total`
當場成立，`everObservedIncomplete` 也早就是 true，於是宣告「整批排空」。

〔實測，逐行 parse 磁碟上全部 32 個 journal〕**29 個是多階段，25 個真的出現過
這個窗口。** 例：`wf_51f2a365-6e8` 在 Research 7/7 全完成時 Verify 尚未 started。
〔代理量：已完成那批的 `agent-<id>.jsonl` 最大 mtime → 下一階段第一個
`agent-<id>.meta.json` 的 birthtime〕窗口中位數 2.2 秒、最大 7.3 秒，**8 個 ≥3 秒**
也就是必定被 3 秒輪詢取樣到。〔推論〕<3 秒的窗口是機率問題；我沒有實際觀測到
app 在某個階段交界發出 T2。

#### ② 然後在對的時刻閉嘴

`notified`（`NotificationEngine.swift:400`）是**單向閂鎖** —— 全檔沒有任何
`notified = false`。下一階段到來時 `st.total` 會取 max 長大、`complete` 變回 false、
`everObservedIncomplete` 重新被設起來，**只有 `notified` 沒有跟著重新武裝**。
所以誤報之後，整條 pipeline 真正跑完的那一刻一聲都不會有。
〔讀碼確定，條件分支只有一條〕

既有測試只測了 total **縮水**（`shrinkingGroupIsNotDrained`），沒有任何一個測試
讓 total 在發過之後**變大**。

#### ③ 沒有在場判斷

`NotificationPresenter.swift:59` 只有一個 `outcome == .completed` 的閘就
`AlertSound.play()`。〔實測，一次〕`02:28:23 T2 · 看得到浮窗嗎 false（鎖定 true
螢幕睡 true 閒置 866s）` —— 對著一台鎖上、螢幕睡著的機器播音效。

#### ④ 沒有預算

〔實測，mtime 代理換算〕無閘的音量上限是 **18.7 聲／天**（26 聲 / 33.4 小時），
最忙那一天 20 聲 —— 比上面那張表替完成訊號算出的 1.6 則／天高一個數量級。
54%（14/26）的排空發生在 23:00–08:00。

### 修法：用 run 狀態檔當正面證據

`<sessionId>/workflows/<wf_id>.json` 這個檔案**只在 run 終結時寫一次**：
〔實測，n=32〕32/32 的 `mtime == birthtime`，且 birthtime **從來不早於**最後一次
journal 寫入（中位 +0.0s、最大 +344s、0 個為負）；而 2026-09-19 這一輪自己跑的
workflow 在執行中檔案不存在、結束後才出現〔實測，直接觀測〕。
實測所有檔案的 status 只有三種，全部是終結值：completed 28 / failed 3 / killed 1。

所以**「檔案存在且 status 是終結值」就是「整個 workflow script 回來了」的正面證據**
—— 正是 Task 5.5 要求的那種證據，而 `runStatus` 早就一路帶到 `WorkflowGroup` 了
（Task 5.1 為了分辨 killed 才拉進來的），只是沒有人拿它當觸發條件。

改用它之後，①②與「狀態過期後重發」三件事**一起消失**：階段交界時檔案還不存在，
所以誤報在結構上不可能；而一個 run 只會終結一次，過期回來時 `complete` 立刻成立、
`everObservedIncomplete` 湊不齊，也不會補發。

代價講在前面：run 狀態檔沒寫出來（app crash、未來版本改格式）就**永遠不發** ——
這是刻意選的方向，與 `runningAgentCount` 那條「寧可少報，不謊報」同一條原則。

### ⚠️ 順序不能顛倒

**先裝在場閘、後修觸發點會讓事情更糟。** 過去那些誤報多半響在空椅子前，沒有人被騙；
加了在場閘之後，會響的那幾聲**剛好都是你在座位上**的時候 —— 你聽到「跑完了」、
走去泡咖啡，但 pipeline 才做完第一階段。**降低音量的同時提高了每一聲的殺傷力。**

### 順手修掉的一句推論

原文寫「T2 會在 session 真正結束前 **5–60 秒**就對同一件事響一次」。那是推論，
而且方向相反。〔代理量：母 transcript 排空之後第一則 `stop_reason == "end_turn"`
當「這一輪講完了」；Stage 8 的完成訊號尚未實作，所以這是重建不是量測〕
兩支獨立腳本各算一次得到中位數 **250 秒（n=28）與 233.5 秒（n=25）**；
25 則裡只有 **1 則（4%）**落在 5–60 秒，**30 秒內 0 則**。

所以 T2 與 Stage 8 的完成訊號不是同一件事響兩次，語意也不同：
**T2 是「扇出結果回來了」，完成訊號才是「這一輪講完了」。**
〔實測〕77%（20/26）的排空發生在 session 上一個 end_turn 之後 —— 扇出在背景跑、
主 session 已經閒著。真要對兩者去重，視窗是**分鐘級**（10 分鐘），不是秒級，
而那是 Stage 8 自己的設計決定。

⚠️ 這個代理在 orchestrator 排空後又做了別的事時會嚴重高估（看到 6030s / 17316s /
21968s 三個離群值，另有 1 則之後根本沒有 end_turn），所以中位數比平均數可信得多。

### 三項裡的前兩項已經修掉（2026-09-19 稍晚）

> **✅ `latestPhase` 與 `runDuration` 完成。** 413 測試 / 40 套件全綠（+23），
> 乾淨 release 建置通過，app 已重裝重啟。兩個 commit：階段 → 時長。
>
> - **階段**改用 journal.jsonl 的行序（append-only，行序＝spawn 序，
>   而 started 行**沒有任何時間戳**，所以行序是那個檔案裡唯一的時間資訊）。
>   欄位改名 `phase` → `latestPhase`，因為它取的是**最新的那個邊緣**，
>   而不是「現在正在跑哪一階段」—— pipeline 沒有 barrier，多個階段真的會同時在跑。
>   實機對照：`wf_266aeea2-d48` 舊報 `Measure`、新報 `Design`（它確實是 Measure→Design）。
> - **時長**改用 run 狀態檔自己的 `durationMs`，欄位改名 `duration` → `runDuration`
>   並改成 optional。分界是：**`status` 讀不到 → 完全不發**（它是排空的正面證據）；
>   **`duration` 讀不到 → 照發，那一格 nil**（它只是附屬資訊）。
>   `BatchState.firstSeen` 因此沒有讀者，整個拿掉。
>
> **還剩第 3 項，另外新發現一項（第 4 項）。**

### 這一輪**沒有**修的（對抗式讀碼找到，但不在 T2 這條路上）

原本三項都改「事件的內容」或「面板上的字」，不改「聲音出不出」。混進同一個 diff 的話，
一個變紅的測試就沒辦法告訴你是哪一道閘壞了。

1. ~~**`WorkflowGroup.phase` 取的是 agentId 字典序最小那隻的 phase**~~ —— **已修**
   （`AgentTreeBuilder.swift:106`，而 `metas` 在 91 行是按 agentId 排序的）。
   agentId 是隨機 hex，字典序與 spawn 順序無關。〔實測〕掃磁碟上 29 個多階段
   workflow，比對「min(agentId) 那隻的 phase」與「min(meta birthtime) 那隻的 phase」：
   **14 個一致、15 個不一致**。這不是潛在問題 —— `SessionRow.swift:117` 現在就把它
   畫在面板上，`Dump.swift:189` 也印它，`BatchAlert.phase` 也帶著它。
   **這是三項裡唯一使用者今天就看得到的。**
2. ~~**`BatchAlert.duration` 是從「app 第一次看到這個 workflow」起算**~~ —— **已修**
3. ~~**`outcome == .failed` 的 T2 只剩「圖示閃一下」一條通道，而那條通道會安靜地消失。**~~
   —— **已修（2026-09-19），兩層都修了。**
   (a) `pulse()` 回傳「真的播了嗎」，presenter 在「沒出聲**而且**圖示也被吞掉」
   時留一行 log；(b) **面板那一行現在分得出失敗了**（`WorkflowTally`，Core，有測試）。
   原本「另有 N 個 workflow 已完成」把失敗的也算進去 —— 而它是這台機器上
   **當下就在發生**的事：接上去之後 `usage-c9` 那一列立刻變成
   「另有 3 個 workflow 已完成 · **2 個失敗**」。面板本來就在對著真實資料說謊。
   四種下場都是磁碟上真的出現過的〔實測 n=39〕：completed 34 / failed 3 /
   killed 1 / 沒有狀態檔 1，所以沒有一個分類是虛構的。
   ⚠️ **「狀態不明」不可以併進「已完成」** —— 那是「不存在 ≠ 那個狀態不成立」。

4. ~~**同一則 `BatchAlert` 裡 `total` 不是權威來源**~~ —— **這一條是錯的，我撤回它。**
   〔實測 n=38，2026-09-19〕`agentCount` 與目錄裡的 meta 檔數只有 **4 個**不一致
   （不是先前寫的 31/34），而且四次都是 **`agentCount` 偏小**：
   `wf_7d1cbb2d-dba` 報 9，實際 29 隻；四個裡三個是 `failed` 的 run。
   反過來，**meta 檔數與 journal 的 `started` 數 38/38 完全一致**。
   所以 `total` 才是準的那個，`agentCount` 是不可信的那個 —— 方向與原文相反。

   「app 重啟接手會少報」也不成立，而且是 T2 改用終結狀態當觸發條件時
   **順手關掉**的：T2 現在要求 run 狀態檔存在，而〔實測 n=32〕那個檔案的
   birthtime **從不早於**最後一次 journal 寫入 —— 所以 T2 發的那一刻 journal
   已經完整，所有 started 過的 agent 都有 meta 檔，`total` 就是全額。
   實機對照：`--dump` 對 `wf_7d1cbb2d-dba` 顯示 `29/29`。

   ⚠️ **留一條錯的待辦在計畫書裡，和留一段說謊的註解是同一件事。**

順帶一個被新規則**順手關掉**的洞：`runStatus` 那一拍讀不到（檔案正在被覆寫、
JSON 半行）時被當成「正面確認不是 killed」。現在讀不到 → `terminated` 為 false
→ 根本不會宣告排空，所以那條路自己不見了。同理，「狀態過期後回來重發一次」
也不再可能（回來時已經是終結狀態，`everObservedIncomplete` 湊不齊）。

---

## 尚未完成

### Stage 5 的已知邊界（做完了，但這些是它做不到的）
- **一般 Agent 扇出永遠不會發 T2。** `AgentTreeBuilder` 把每一隻一般 subagent
  都寫成 `.unknown`，沒有正面證據就不宣告完成。這是 Stage 2 的已知缺口，
  不是通知層的 bug。實測這台機器 251 隻 subagent 裡有 31 隻是這一類。
- **「跳過去」只到 app 層級，到不了分頁。** 要分頁需要 Accessibility +
  Screen Recording 兩個授權，而三個真實 session 有兩個根本沒有 tty ——
  三個授權提示換一個在三分之二場合仍然無效的功能。這是**寫下來的拒絕**，
  不是待辦。面板上顯示 session 自己的名字（`usage-c9`）讓使用者知道找哪個分頁。
- **Focus／勿擾讀不到**（`Assertions.json` 受 TCC 保護），所以手動靜音是唯一
  的防線。設計文件裡「靠 interruption level 讓系統仲裁」在備援路線上是過時的。
- **osascript 的署名永遠是「指令碼編輯器」**，而且**偵測不到**使用者有沒有在
  系統設定裡把它關掉。自建 applet 實測回 `-10814`，一則都送不出。
- **合併視窗讓單一 T1 延後最多 4 秒。** 可以接受：選單列圖示在同一拍就已經
  變琥珀並開始呼吸，瞬時訊號早就發出去了。
- 浮窗沒有測試覆蓋（它碰 AppKit）。`--demo-alert` 是那條路徑唯一的驗證方式。

### 使用者第一次實際用到時抓到的那一格

**症狀：** 從來沒看過那扇窗。**原因不是壞掉，是開給沒有人看。**

診斷是靠三個訊號的**組合**分出來的，單看任何一個都分不出來：
圖示有變琥珀（資料層正常）、有聽到音效（引擎與 presenter 都跑了）、
通知中心有一則「指令碼編輯器」（osascript 發了 —— 而它**只在
`ScreenPresence` 判定看不到浮窗時才發**，所以當下閒置超過五分鐘）。
加上 app 的 log 裡沒有「警示浮窗沒有出現」，結論就唯一了：
窗開了十秒，對著一張空椅子，然後自己消失。

**修法：** 存起來，人一碰鍵盤就補上（`WaitingAlert.retaining`）。
補上的那一扇 `isRepeat` 一律是 false —— 它是使用者第一次看到它。

**留下的工具：** `--trace-alerts`。通知沒出現時畫面上什麼線索都沒有，
而「引擎沒發」「被合併視窗吃掉」「走了另一條通道」三者長得一模一樣。
`--demo-alert` 證明得了浮窗畫得出來，證明不了有事件走到它。

### review 留下的兩條通則（比那兩個 bug 本身重要）

1. **「不存在」不是資訊，而這件事要在每一層各做一次。** T2 一開始就有寬限期，
   T1 沒有 —— 因為當時的理由是「最壞情況是下一次等待被當成新事件，而它本來
   就是新事件」。那是錯的：episode 的身分來自 `statusUpdatedAt`，不是來自
   有沒有被看到。而且修的時候還要再分一層：**「看到它不在等了」是正面證據，
   當場清；「整個沒看到它」不是，要寬限。** 混在一起會兩邊各錯一種。
2. **診斷指令的註解說它畫了什麼，就必須真的畫。** `--render-alert` 宣稱畫了
   「兩個在等」卻沒有，於是 n=2 的版面從來沒被眼睛看過 —— 而它剛好就是唯一
   一個把第二個 session 整個藏起來的版面。一份**說謊的**診斷比沒有診斷更糟，
   因為它會讓你以為已經看過了。

### V2 — 使用者點名要的三個加值功能
- ~~**每個 session 的 context 壓力**~~ — **Stage 6 已完成**。session 列有 ctx 細條，
  門檻與使用者自己的狀態列腳本一致（70% 黃、90% 紅）。
- **燒量速率與觸頂預測** — **時間序列已經開始累積**（2026-09-18）：
  `~/Library/Application Support/QuotaMonster/usage-history.jsonl`，一行一個點，
  數字沒變就不寫，保留 30 天。`UsageHistory` 有 16 個測試。
  已經做出來的：**每日均量**（`UsagePace`，唯一不需要歷史就算得出來的速率指標，
  顯示在 7 天那一欄的註腳）。
  還沒做的：每日長條圖（要約兩天資料才有意義）、觸頂預測。
- **卡住 / 閒置 agent 偵測** — 資料層已經有足夠資訊，缺的是門檻與 UI

### 面板現況（2026-09-18 下午，依使用者回饋調整過）
- 額度三欄：5 小時（倒數）／ 7 天全模型（絕對重置時間 + 日均）／ 7 天分模型（標年齡）
- 分模型來自 `~/.claude.json` 的 `utilization.limits` 陣列，**不是** `seven_day_opus`
  那種鍵（實測全是 null）。它與另外兩欄不同來源，所以一定要標出自己的年齡。
- session 清單高度跟著 session 多寡走，至少同時顯示三個，超過才捲動。
  高度是**同步估算**的而不是量的（量的要等下一輪 runloop，第一次展開會縮一半）。
- 使用者選擇**不加**獨立的詳細額度卡，維持現在的高度。
- **選單列圖示顏色政策已改**（2026-09-18 下午）：平常就依剩餘額度上色 ——
  **剩 >50% 藍、20–50% 綠、<20% 紅**，取兩個窗口較緊者；沒有讀數或讀數過期
  一律不上色（單色＝這個數字不可信）。警示狀態靠形狀與呼吸區分，不靠顏色。
  ⚠️ **黃色保留給「要我輸入」（警示）**，額度色階不得使用 —— 使用者明確指定。
  幾何仍然凍結，改的只有顏色。可讀性三條：生物不染色、色階與暗軌透明度都要
  依深色／淺色列分兩組。
- **面板的三條進度條與圖示共用同一套色階**（`QuotaPalette`），但每一欄依自己的
  剩餘量取色。門檻只定義在 `QuotaTier.forRemaining`。
- 診斷：`--render <dir> --dark`（圖示）、`--render-panel <file> --dark`（面板）。
  **配色一定要用深色版本檢查** —— 使用者的選單列與面板都是深色的，
  用淺色渲染判斷已經看走眼兩次。
- **footer 多了靜音**（2026-09-18 晚）：一小時 / 到明早八點。靜音中會顯示
  解除時間，點一下解除。狀態存在 `notify-state.json`，跨重啟活著 ——
  「到明早」約 12 小時，遠長於這個 app 的一次執行。
- 每日長條圖：使用者決定**先不畫**，等 `usage-history.jsonl` 累積兩天後再決定
  要不要畫、畫在哪。記錄器已經在跑。

### 其他缺口
- **已經在跑的 session 不會立刻開始寫 tee 快取**。實測安裝後 8 分鐘，
  另外兩個 session 仍然沒有 payload。額度是帳號層級的，所以數字不受影響
  （任何一個 session 寫就夠），但那些 session 的 context 壓力要等它們自己
  重新渲染狀態列，或重開。可考慮的緩解：`statusLine.refreshInterval`
  （官方設定，最小 1 秒）能讓閒置的 session 也定期重跑 —— 但那會改變
  使用者狀態列的更新節奏，要先問過。
- 開機自動啟動（`SMAppService`，Stage 0 已驗證可用且不受安裝位置限制）
- 偏好設定介面（目前所有門檻都寫死）
- FSEvents 監看取代 3 秒輪詢
- 選單列圖示設計的四塊移植（凍結中，使用者指示維持原狀）
- 一般 Agent subagent 的完成狀態仍是 `.unknown`（見 Stage 2 的已知缺口）

## 附錄：Stage 5 路線決策紀錄

> **（2026-09-18）走備援，不購買 Developer ID。**
> 原生 `UNUserNotificationCenter` 經 Stage 0 實測不可用。T1（有人在等你）改以
> **選單列圖示警示狀態 + app 自有 NSPanel 浮窗 + AVAudioPlayer 音效**實作；
> osascript 僅作為可選的附加通道。能力邊界對照表見
> `docs/plans/2026-09-18-quotamonster-design.md` 的「通知政策」一節。

Stage 4（下拉面板）、Stage 5（通知層）、Stage 6（statusline tee）的細節待 Stage 0 的通知 probe 結果確定後定案 —— probe 的結果會決定 Stage 5 是走 `UNUserNotificationCenter` 還是備援機制。

---
完成所有 Stage 後刪除此文件。
