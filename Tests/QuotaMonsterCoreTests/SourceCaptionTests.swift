import Testing
import Foundation
@testable import QuotaMonsterCore

/// 面板額度區塊右上角那一行：**它為什麼是這個數字，或為什麼沒有數字**。
///
/// ### 為什麼這一行值得有自己的型別與測試
/// 〔實測 2026-09-21〕`~/.claude.json` 的 `cachedUsageUtilization` 這個來源
/// **已經死了**：那個檔案還在被 Claude Code 持續重寫（mtime 是當下），
/// 但 `fetchedAtMs` 凍在 3.9 天前。也就是說 —— **沒有 statusline tee 就完全沒有額度數字**。
/// 把快取目錄移開實跑 `--dump`：兩個窗口都是「沒有讀數」。
///
/// 所以這一行是新使用者**唯一**會看到的線索。它不能只說「無讀數」。
///
/// ### ⚠️ 這裡修的是一個我自己弄出來的退步
/// 原本 `~/.claude.json` 會吐過期的舊數字，於是 `usageSource == .claudeJSON`，
/// 面板會說「沒裝 statusline tee」。2026-09-21 讓那支 reader 開始擋過期窗口之後，
/// 它回 nil → `pick()` 回 nil → `usage` 是 nil → 面板只剩「無讀數」三個字，
/// **提示整個消失了**。對老使用者沒差（有 tee），新使用者第一眼看到的就是它。
@Suite("來源註腳")
struct SourceCaptionTests {

    func snapshot(_ f: Freshness) -> UsageSnapshot {
        UsageSnapshot(fiveHour: UsageWindow(percent: 30, resetsAt: nil),
                      sevenDay: nil, perModel: [:], freshness: f,
                      fetchedAt: Fixture.now)
    }

    // ── 一個數字都沒有：唯一的線索 ────────────────────────────────
    //
    // ⚠️ 分成兩件，不是一件：角落那行註腳右對齊、10pt，塞得下的預算很小
    // （`OutlookCaption` 的檔頭整段都在講這件事）。**指令屬於空狀態提示，
    // 不屬於註腳。** 把它們合成一個字串會讓註腳在窄螢幕上被縮到看不清楚。

    @Test("完全沒有讀數而且沒有任何 tee payload → 註腳說「沒裝 tee」")
    func noReadingAtAllSaysNotInstalled() {
        let c = UsageSourceCaption.text(usage: nil, source: nil, statusLinePayloadCount: 0)
        #expect(c.contains("沒裝"), "新使用者唯一的線索不能只是「無讀數」")
    }

    @Test("完全沒有讀數而且沒有 tee → 空狀態提示要說得出確切的指令")
    func noReadingGivesAnActionableHint() {
        let h = UsageSourceCaption.setupHint(usage: nil, source: nil, statusLinePayloadCount: 0)
        let hint = try! #require(h)
        #expect(hint.contains("install_statusline_tee"))
        // ⚠️〔實測 2026-09-21〕~/.claude.json 那個來源已經不更新了
        //（檔案一直被重寫，但 fetchedAtMs 凍了 3.9 天），所以提示不可以把 tee
        // 講成「可選的加強」—— 它是額度數字的**唯一**來源。
        #expect(hint.contains("唯一"))
    }

    @Test("沒有讀數但 tee 有在寫 → 不可以叫他去裝一個已經裝好的東西")
    func noReadingButTeeIsWriting() {
        let c = UsageSourceCaption.text(usage: nil, source: nil, statusLinePayloadCount: 2)
        #expect(c.contains("還沒帶到額度"))
        #expect(UsageSourceCaption.setupHint(usage: nil, source: nil,
                                             statusLinePayloadCount: 2) == nil,
                "tee 明明在寫卻叫他重裝，是最糟的謊")
    }

    @Test("有讀數的時候永遠不出現空狀態提示")
    func noHintWhenThereIsAReading() {
        for f: Freshness in [.live, .aging(minutes: 9), .expired] {
            for src: UsageSource in [.statusLine, .claudeJSON] {
                #expect(UsageSourceCaption.setupHint(usage: snapshot(f), source: src,
                                                     statusLinePayloadCount: 1) == nil)
            }
        }
    }

    // ── 有讀數：既有行為不可退步 ──────────────────────────────────

    @Test("statusline 來源 · live → 就只說「剛更新」")
    func liveStatusLineIsTerse() {
        #expect(UsageSourceCaption.text(usage: snapshot(.live), source: .statusLine,
                                        statusLinePayloadCount: 1) == "剛更新")
    }

    @Test("statusline 來源 · aging → 說出幾分鐘前")
    func agingSaysMinutes() {
        #expect(UsageSourceCaption.text(usage: snapshot(.aging(minutes: 23)),
                                        source: .statusLine,
                                        statusLinePayloadCount: 1) == "23 分鐘前")
    }

    @Test("statusline 來源 · expired → 說出那是「沒有 session 在動」，不是壞掉")
    func expiredStatusLineExplainsWhy() {
        let c = UsageSourceCaption.text(usage: snapshot(.expired), source: .statusLine,
                                        statusLinePayloadCount: 1)
        #expect(c.contains("已過期"))
        #expect(c.contains("沒有 session 動過"))
    }

    @Test("claude.json 來源 · 沒過期 → 要標出來源（兩個來源的「舊」意思不同）")
    func claudeJSONNamesItsSource() {
        let c = UsageSourceCaption.text(usage: snapshot(.aging(minutes: 3)),
                                        source: .claudeJSON, statusLinePayloadCount: 0)
        #expect(c.contains("~/.claude.json"))
    }

    @Test("claude.json 來源 · 過期且沒有 tee → 註腳說「沒裝」，提示給指令")
    func expiredClaudeJSONStillTellsHow() {
        let c = UsageSourceCaption.text(usage: snapshot(.expired), source: .claudeJSON,
                                        statusLinePayloadCount: 0)
        #expect(c.contains("沒裝 statusline tee"))
        let h = UsageSourceCaption.setupHint(usage: snapshot(.expired), source: .claudeJSON,
                                             statusLinePayloadCount: 0)
        #expect(h != nil, "過期又沒有 tee，等於沒有活的數字 —— 這種人最需要提示")
    }

    // ── 不可以說謊 ────────────────────────────────────────────────

    @Test("任何情況下，tee 有在寫就不可以出現「沒裝 tee」")
    func neverTellsAnInstalledUserToInstall() {
        for f: Freshness in [.live, .aging(minutes: 9), .expired] {
            for src: UsageSource? in [.statusLine, .claudeJSON, nil] {
                let c = UsageSourceCaption.text(usage: snapshot(f), source: src,
                                                statusLinePayloadCount: 3)
                #expect(c.contains("沒裝") == false,
                        "freshness=\(f) source=\(String(describing: src)) 時說了「沒裝」")
            }
        }
    }
}
