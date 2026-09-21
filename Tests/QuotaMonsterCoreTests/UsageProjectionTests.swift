import Testing
import Foundation
@testable import QuotaMonsterCore

/// 「照這個速度，這個窗口會怎麼收場？」
///
/// **這個型別不碰歷史。** 窗口的起點就是 `resetsAt − 窗口長度`，所以單一讀數
/// 就足夠算出均速與重置時的投射值 —— 第一次啟動、歷史檔還是空的，它就正確。
///
/// ⚠️ **它刻意不提供時鐘觸頂時間。** 理由是實測的：這台機器上最快的一段是
/// 22.52 pp/h（17:46:49–18:00:37 那 7 個點），而它只持續了 14 分鐘 ——
/// 下一個觀測是 44 分鐘後的一個 null。要把 5 小時窗口用完需要 20 pp/h 撐滿五小時，
/// 資料裡沒有任何證據支持任何速率會持續那麼久。而時鐘時間正是使用者會拿去排行程的東西。
@Suite("UsageProjection")
struct UsageProjectionTests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    /// 造一個「窗口已經過了 fraction、目前用了 percent」的讀數。
    func reading(percent: Int, elapsedFraction: Double,
                 window: TimeInterval) -> (Int, Date, Date) {
        let elapsed = window * elapsedFraction
        let measuredAt = t0
        let resetsAt = measuredAt.addingTimeInterval(window - elapsed)
        return (percent, resetsAt, measuredAt)
    }

    // ── 主線 ───────────────────────────────────────────────────

    @Test("真實資料點：5 小時窗口走了 3h15m、用掉 32% → 均速 9.83，重置時投射 49%")
    func realFiveHourPoint() throws {
        // 這是 09-18 18:00:37 那一筆。窗口在 19:45 左右重置，所以當下已過 3h15m。
        let elapsed: TimeInterval = 3 * 3600 + 15 * 60
        let p = try #require(UsageProjection.fiveHour(
            percent: 32,
            resetsAt: t0.addingTimeInterval(UsagePace.fiveHour - elapsed),
            measuredAt: t0))
        #expect(abs(p.burnPerHour - 9.846) < 0.01)
        #expect(p.outcome == .resetsFirst(projectedPercent: 49))
    }

    // ── 門檻：整個設計裡最容易寫錯的一個常數 ────────────────────

    @Test("剛重置 15 分鐘就拒絕 —— 0.05 是 7 天窗口的門檻，不可以搬過來")
    func fifteenMinutesIntoAFiveHourWindowRefuses() {
        // UsagePace.minimumElapsedFraction = 0.05 是為 **7 天**窗口挑的：
        // 5% 的七天是 8.4 小時。同一個數字放到 5 小時窗口上只有 15 分鐘。
        //
        // 把實測最快的那一段（22.52 pp/h）放在剛重置的窗口起點，15 分鐘後
        // 已用 6%，投射到重置時是 120% —— 於是它會宣告「會觸頂」。
        // 而實測那兩個窗口最後分別停在 32% 與 ≤7%，那段突發只持續了 14 分鐘。
        let (pct, reset, measured) = reading(percent: 6, elapsedFraction: 0.05,
                                             window: UsagePace.fiveHour)
        #expect(UsageProjection.fiveHour(percent: pct, resetsAt: reset,
                                         measuredAt: measured) == nil)
    }

    @Test("同一段突發在 45 分鐘時就算數了，而且說的是「會觸頂」不是幾點")
    func thatSameBurstSpeaksAtFortyFiveMinutes() throws {
        let (pct, reset, measured) = reading(percent: 17, elapsedFraction: 0.15,
                                             window: UsagePace.fiveHour)
        let p = try #require(UsageProjection.fiveHour(percent: pct, resetsAt: reset,
                                                      measuredAt: measured))
        #expect(p.outcome == .exceedsWindow)
    }

    @Test("5 小時的門檻是 45 分鐘，7 天的是 2.1 天 —— 兩個窗口不共用一個數字")
    func eachWindowHasItsOwnGate() {
        #expect(UsageProjection.fiveHourMinimumElapsed == 0.15)
        #expect(UsageProjection.sevenDayMinimumElapsed == 0.30)
        #expect(UsagePace.fiveHour * UsageProjection.fiveHourMinimumElapsed == 45 * 60)
    }

    // ── 邊界 ───────────────────────────────────────────────────

    @Test("剛好投射到 99 是「重置先到」，剛好 100 是「會觸頂」")
    func theBoundaryBetweenTheTwoOutcomes() throws {
        let half = UsagePace.fiveHour / 2
        let a = try #require(UsageProjection.fiveHour(
            percent: 49, resetsAt: t0.addingTimeInterval(half), measuredAt: t0))
        #expect(a.outcome == .resetsFirst(projectedPercent: 98))

        let b = try #require(UsageProjection.fiveHour(
            percent: 50, resetsAt: t0.addingTimeInterval(half), measuredAt: t0))
        #expect(b.outcome == .exceedsWindow)
    }

    @Test("用了 0% 是「重置時 0%」，不是 nil —— 0 是一個讀數")
    func zeroUsageIsAProjectionNotARefusal() throws {
        let p = try #require(UsageProjection.fiveHour(
            percent: 0, resetsAt: t0.addingTimeInterval(UsagePace.fiveHour / 2),
            measuredAt: t0))
        #expect(p.outcome == .resetsFirst(projectedPercent: 0))
        #expect(p.burnPerHour == 0)
    }

    @Test("已經 100% 就是已觸頂，沒有東西好預測")
    func exhaustedIsItsOwnOutcome() throws {
        let p = try #require(UsageProjection.fiveHour(
            percent: 100, resetsAt: t0.addingTimeInterval(UsagePace.fiveHour / 2),
            measuredAt: t0))
        #expect(p.outcome == .exhausted)
    }

    @Test("重置時間已經過了就拒絕")
    func pastResetRefuses() {
        #expect(UsageProjection.fiveHour(percent: 30, resetsAt: t0.addingTimeInterval(-60),
                                         measuredAt: t0) == nil)
    }

    @Test("重置時間比一整個窗口還遠就拒絕 —— 那是時間戳混到了不同單位")
    func absurdResetRefuses() {
        // ISO-8601 與 epoch 混用會產生這種值。它在畫面上看起來完全像真的。
        #expect(UsageProjection.fiveHour(
            percent: 30, resetsAt: t0.addingTimeInterval(UsagePace.fiveHour + 60),
            measuredAt: t0) == nil)
    }

    @Test("兩個 wrapper 把窗口長度與門檻綁死 —— 外面不能自己湊一對")
    func wrappersBindLengthAndGateTogether() throws {
        // 同樣「走了 20%」，5 小時說得出話（20% > 15%），7 天說不出（20% < 30%）。
        // 把 7 天的長度配上 5 小時的門檻，正是印出「日均 340%」的方式，
        // 所以 measure 是 internal，外面只拿得到這兩個綁好的 wrapper。
        let fiveReset = t0.addingTimeInterval(UsagePace.fiveHour * 0.8)
        let five = try #require(UsageProjection.fiveHour(percent: 30, resetsAt: fiveReset,
                                                         measuredAt: t0))
        #expect(five.windowLength == UsagePace.fiveHour)
        #expect(abs(five.elapsedFraction - 0.2) < 1e-9)

        let sevenReset = t0.addingTimeInterval(UsagePace.sevenDay * 0.8)
        #expect(UsageProjection.sevenDay(percent: 30, resetsAt: sevenReset,
                                         measuredAt: t0) == nil)
    }

    // ── 舊讀數 ─────────────────────────────────────────────────

    @Test("讀數是半小時前抓的，燒量仍然完全正確 —— 分子分母同一個瞬間")
    func anAgingReadingStillYieldsTheExactRate() throws {
        // measuredAt 用 snapshot.fetchedAt 而不是 Date()。
        // 用 Date() 的話，分母（已過時間）會一直長，分子（percent）卻停在
        // 半小時前那個值 —— 燒量會被安靜地低估，而且愈舊低估愈多。
        let reset = t0.addingTimeInterval(UsagePace.fiveHour / 2)
        let fresh = try #require(UsageProjection.fiveHour(percent: 30, resetsAt: reset,
                                                          measuredAt: t0))
        // 同一筆讀數，半小時後才被算到：resetsAt 與 percent 都沒變。
        let stale = try #require(UsageProjection.fiveHour(percent: 30, resetsAt: reset,
                                                          measuredAt: t0))
        #expect(fresh.burnPerHour == stale.burnPerHour)
        #expect(fresh.outcome == stale.outcome)
    }

    // ── 兩個指標不准漂開 ────────────────────────────────────────

    @Test("burnPerDay 與 UsagePace.dailyAverage 是同一個東西")
    func burnPerDayReconcilesWithDailyAverage() throws {
        // 面板上第二欄顯示的是 dailyAverage，第一欄的投射走 burnPerHour。
        // 兩個各算一次就會在某個邊界上漂開，而且沒有人會馬上發現。
        let reset = t0.addingTimeInterval(UsagePace.sevenDay * 0.4)
        let p = try #require(UsageProjection.sevenDay(percent: 50, resetsAt: reset,
                                                      measuredAt: t0))
        let pace = try #require(UsagePace.dailyAverage(percent: 50, resetsAt: reset,
                                                       windowLength: UsagePace.sevenDay,
                                                       now: t0))
        #expect(abs(p.burnPerDay - pace) < 1e-9)
    }

    @Test("窗口起點是算出來的，不是猜的")
    func windowStartIsDerived() throws {
        let reset = t0.addingTimeInterval(3600)
        let p = try #require(UsageProjection.fiveHour(percent: 30, resetsAt: reset,
                                                      measuredAt: t0))
        #expect(p.windowStart == reset.addingTimeInterval(-UsagePace.fiveHour))
        #expect(abs(p.elapsed - (UsagePace.fiveHour - 3600)) < 1e-9)
    }
}
