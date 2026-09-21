import Testing
import Foundation
@testable import QuotaMonsterCore

/// 「檔案很新」不等於「數字很新」。
///
/// ### 這組測試是為了一筆真實寫進磁碟的假資料而存在
/// 〔實測 2026-09-21〕`usage-history.jsonl` 在 19:30:51 寫下
/// `{"5h":null,"7d":0}`，**三秒後** 19:30:54 寫下 `{"5h":20,"7d":13}`。
/// 同一個七天窗口（09-19 14:00 → 09-26 14:00，距重置 53.5 小時）不可能三秒內
/// 從 0 變成 13，所以 19:30:51 那一筆不是當下的讀數。
///
/// ### 成因（實測，讀 Claude Code 2.1.277 的二進位）
/// statusline payload 的 `rate_limits` **不是每次渲染去問來的**，是從行程記憶體裡的
/// `rawUtilization` 重發的，而那個欄位只有 **API 回應**才會更新：
/// ```
/// function k2(){return xPr(Eu.rawUtilization)}
/// function xPr(e){...for(let[s]of Vw){let g=e[s];if(g!==void 0&&u0t(g,n))r[s]=g}...}
/// function u0t(e,n){let r=n/1000;return IZ(e)&&e.resets_at>r&&e.resets_at<r+31536000}
/// ```
/// 所以：**渲染由 UI 事件觸發，可以完全不帶新的 API 回應**，而我們用檔案 mtime
/// （＝渲染時刻）當那組數字的年紀。`UsageSourceSelector` 原本的註解
/// 「會讓額度數字變大的活動，本身就是會觸發重新寫入的活動」在這個方向上不成立。
///
/// ### 可以偵測的訊號
/// `u0t` 是**逐窗口**判斷的：五小時窗口的 `resets_at` 一過，那個 key 就整個消失，
/// 而七天窗口還沒到期所以留著舊數字。五小時窗口最多活五小時 ——
/// 所以「**有 7d、沒有 5h**」證明那個 `rawUtilization` 至少從某個五小時窗口結束前
/// 就沒有更新過。那不是一組可以宣稱為 live 的數字。
///
/// ⚠️〔推論，未實測〕如果有帳號**天生沒有五小時窗口**，這條規則會讓它永遠降級。
/// 我沒有看過這種帳號，也沒有辦法在這台機器上造出來。
@Suite("過期的讀數")
struct StaleReadingTests {

    let now = Fixture.now

    func payload(five: Int?, seven: Int?, writtenSecondsAgo: TimeInterval = 1)
    -> StatusLinePayload {
        StatusLinePayload(
            sessionId: "s1",
            capturedAt: now.addingTimeInterval(-writtenSecondsAgo),
            fiveHour: five.map { UsageWindow(percent: $0, resetsAt: now.addingTimeInterval(7200)) },
            sevenDay: seven.map { UsageWindow(percent: $0, resetsAt: now.addingTimeInterval(400_000)) })
    }

    // ── 訊號：有 7d 沒有 5h ────────────────────────────────────────

    @Test("只有 7d 沒有 5h 的 payload 不可以是 live —— 就算檔案是一秒前寫的")
    func sevenDayWithoutFiveHourIsNotLive() throws {
        let p = payload(five: nil, seven: 13)
        let picked = try #require(UsageSourceSelector.pick(claudeJSON: nil, statusLine: [p], now: now))
        #expect(picked.snapshot.freshness == .expired,
                "檔案 mtime 是渲染時刻，不是那組數字的取得時刻")
    }

    @Test("兩個窗口都在時，freshness 照舊由檔案年齡決定（不可退步）")
    func bothWindowsKeepsNormalFreshness() throws {
        let p = payload(five: 20, seven: 13)
        let picked = try #require(UsageSourceSelector.pick(claudeJSON: nil, statusLine: [p], now: now))
        #expect(picked.snapshot.freshness == .live)
    }

    @Test("只有 5h 沒有 7d 不是那個訊號 —— 不可以跟著降級")
    func fiveHourWithoutSevenDayIsFine() throws {
        // 五小時窗口還在，代表 rawUtilization 在這個窗口內被更新過。
        // 七天窗口缺席是別的原因（例如方案沒有那個窗口），不構成「舊」的證據。
        let p = payload(five: 20, seven: nil)
        let picked = try #require(UsageSourceSelector.pick(claudeJSON: nil, statusLine: [p], now: now))
        #expect(picked.snapshot.freshness == .live)
    }

    @Test("真實重現：19:30:51 那一筆進不了歷史檔")
    func theRealRegression() throws {
        let stale = payload(five: nil, seven: 0)
        let picked = try #require(UsageSourceSelector.pick(claudeJSON: nil, statusLine: [stale], now: now))
        #expect(UsageSample(picked.snapshot, at: now) == nil,
                "過期的快照不可以變成一個取樣點")
    }

    // ── 兩個 reader 對「過期」必須是同一個定義（規矩 2）────────────

    @Test("~/.claude.json 也要丟掉已經重置的窗口 —— 以前只有 statusline 擋")
    func claudeJSONDropsResetWindows() {
        // 〔實測〕這台機器的 ~/.claude.json 的 fetchedAtMs 從 2026-09-17 23:43 凍住四天，
        // 兩個窗口的 resets_at 都早就過了，它卻一直吐同一組 30/19 ——
        // usage-history.jsonl 的 09-20 15:25 那一筆就是它寫進去的。
        let past = ISO8601DateFormatter().string(from: now.addingTimeInterval(-3600))
        let dict: [String: Any] = ["utilization": 19, "resets_at": past]
        #expect(ClaudeJSONUsageReader.window(from: dict, now: now) == nil)
    }

    @Test("兩個 reader 餵同一組重置時間，判得完全一樣")
    func bothReadersAgreeOnExpiry() {
        let iso = ISO8601DateFormatter()
        for offset in [-86400.0, -3600, -1, 0, 1, 3600, 86400, 31_536_001] {
            let at = now.addingTimeInterval(offset)
            let fromJSON = ClaudeJSONUsageReader.window(
                from: ["utilization": 42, "resets_at": iso.string(from: at)], now: now)
            let fromStatusLine = StatusLineCacheReader.window(
                from: ["used_percentage": 42, "resets_at": at.timeIntervalSince1970], now: now)
            #expect((fromJSON == nil) == (fromStatusLine == nil),
                    "重置時間 \(offset) 秒的窗口，兩個 reader 判得不一樣")
        }
    }

    @Test("沒有重置時間的窗口兩邊都留著 —— 無從判斷過期，不等於過期")
    func missingResetKeepsWindow() {
        #expect(ClaudeJSONUsageReader.window(from: ["utilization": 42], now: now) != nil)
        #expect(StatusLineCacheReader.window(from: ["used_percentage": 42], now: now) != nil)
    }

    // ── 過期的快照不進歷史檔 ───────────────────────────────────────

    @Test("過期的快照不產生取樣點 —— 歷史檔只收得起可信的數字")
    func expiredSnapshotMakesNoSample() {
        let expired = UsageSnapshot(
            fiveHour: UsageWindow(percent: 30, resetsAt: nil),
            sevenDay: UsageWindow(percent: 19, resetsAt: nil),
            perModel: [:], freshness: .expired, fetchedAt: now.addingTimeInterval(-300_000))
        #expect(UsageSample(expired, at: now) == nil)
    }

    @Test("aging 仍然收 —— 它只是有點舊，不是不可信")
    func agingStillRecorded() {
        let aging = UsageSnapshot(
            fiveHour: UsageWindow(percent: 30, resetsAt: nil),
            sevenDay: UsageWindow(percent: 19, resetsAt: nil),
            perModel: [:], freshness: .aging(minutes: 23), fetchedAt: now.addingTimeInterval(-1380))
        #expect(UsageSample(aging, at: now) != nil)
    }
}
