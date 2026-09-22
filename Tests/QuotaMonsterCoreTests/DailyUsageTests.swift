import Testing
import Foundation
@testable import QuotaMonsterCore

/// 7 天窗口裡每一天用掉多少 —— 面板那排長條。
///
/// ### 為什麼可以用差分算（而我一度認為不行）
/// 〔實測 2026-09-22〕`7d` 在**同一個窗口內是單調遞增**的。
/// 我先前量到它會下降（09-19 03:15 `58` → 03:47 `56`）並據此判定它是滾動窗口、
/// 不能差分 —— **那個量測是在修好「舊數字被當成新讀數」之前做的**。
/// 那一次 `7d` 與 `5h` **同時**下降，那是「一個帶著舊值的 payload」的指紋。
/// 修復後 0 次下降（⚠️ 只有 9 個相鄰配對，樣本小，所以下面有一則測試
/// 專門守「真的下降時要說不知道，不要畫一根負的」）。
///
/// ### 為什麼事件驅動的稀疏取樣**剛好夠**
/// `shouldRecord` 只在數字變了才寫，而數字只在你用 Claude Code 時才變 ——
/// 所以每一個台階都被抓到了，「某時刻的值」永遠能用「最後一個不晚於它的
/// 取樣點」還原。稀疏不是缺陷，是這個訊號本來的形狀。
///
/// ### ⚠️ 一天切在 14:00 不是午夜
/// 邊界是 `resetsAt − 7 天` 算出來的（這個帳號是週六 14:00，**沒有寫死星期幾**）。
/// 換來一個自我驗證的性質：**七根相加恰好等於面板的 7 天已用**，
/// 對不上就是有 bug。〔實測 2026-09-22〕30% = 30%，差 0。
@Suite("每日用量")
struct DailyUsageTests {

    let reset = Date(timeIntervalSince1970: 1_790_402_400)   // 09-26 14:00
    var start: Date { reset.addingTimeInterval(-7 * 86400) } // 09-19 14:00

    func sample(day: Double, hour: Double, _ v: Int?) -> UsageSample {
        UsageSample(at: start.addingTimeInterval(day * 86400 + hour * 3600),
                    fiveHour: nil, sevenDay: v)
    }
    /// 每天都有心跳 → 每個邊界都被看著
    func watchedThroughout(_ days: Int) -> [WatchLog.Mark] {
        stride(from: 0.0, through: Double(days) * 86400, by: WatchLog.interval)
            .map { WatchLog.Mark(at: start.addingTimeInterval($0), kind: .heartbeat) }
    }

    func bars(_ samples: [UsageSample], _ marks: [WatchLog.Mark], nowDay: Double)
    -> [DailyUsageBar] {
        DailyUsage.bars(samples: samples, marks: marks, resetsAt: reset,
                        now: start.addingTimeInterval(nowDay * 86400))
    }

    // ── 基本形狀 ───────────────────────────────────────────────

    @Test("永遠七根")
    func alwaysSeven() {
        #expect(bars([], [], nowDay: 3).count == 7)
        #expect(DailyUsage.days == 7)
    }

    @Test("還沒到的日子是 notYet，不是 0% —— 「還沒發生」不是「沒有用」")
    func futureDaysAreNotYet() {
        let b = bars([sample(day: 0, hour: 1, 5)], watchedThroughout(7), nowDay: 2.5)
        #expect(b[3].state == .notYet)
        #expect(b[6].state == .notYet)
    }

    // ── 差分 ───────────────────────────────────────────────────

    @Test("窗口起點的基準是 0 —— 不是「重置前最後一個讀數」")
    func windowStartBaselineIsZero() {
        // 重置前那個 75 屬於**上一個**窗口，不可以當這個窗口第一天的起點。
        let s = [UsageSample(at: start.addingTimeInterval(-600), fiveHour: nil, sevenDay: 75),
                 sample(day: 0, hour: 20, 8)]
        let b = bars(s, watchedThroughout(7), nowDay: 3)
        #expect(b[0].state == .measured(percent: 8))
    }

    @Test("每天的用量是該日兩端的差")
    func dailyDelta() {
        let s = [sample(day: 0, hour: 20, 8),
                 sample(day: 1, hour: 20, 20),
                 sample(day: 2, hour: 20, 23)]
        let b = bars(s, watchedThroughout(7), nowDay: 3)
        #expect(b[0].state == .measured(percent: 8))
        #expect(b[1].state == .measured(percent: 12))
        #expect(b[2].state == .measured(percent: 3))
    }

    @Test("⚠️ 七根相加等於最後一個讀數 —— 這是這個設計的自我檢查")
    func barsSumToTheLatestReading() {
        let s = [sample(day: 0, hour: 20, 8), sample(day: 1, hour: 20, 20),
                 sample(day: 2, hour: 20, 23), sample(day: 3, hour: 20, 41)]
        let b = bars(s, watchedThroughout(7), nowDay: 4)
        let total = b.reduce(0) { acc, bar in
            if case .measured(let p) = bar.state { return acc + p }
            if case .unverified(let p) = bar.state { return acc + p }
            return acc
        }
        #expect(total == 41, "對不上就代表差分或邊界算錯了")
    }

    @Test("沒有用量的那一天是 0%，而且**是量到的 0**（因為我們有在看）")
    func aQuietWatchedDayIsAMeasuredZero() {
        let s = [sample(day: 0, hour: 20, 8), sample(day: 2, hour: 20, 8)]
        let b = bars(s, watchedThroughout(7), nowDay: 3)
        #expect(b[1].state == .measured(percent: 0))
    }

    // ── 有沒有在看 ─────────────────────────────────────────────

    @Test("⚠️ 完全沒有心跳的那一天是 unknown，不是 0% —— 這是整張圖最重要的一條")
    func anUnwatchedDayIsUnknownNotZero() {
        // 只在第 0 天與第 2 天有心跳，第 1 天整天沒開 app。
        let marks = [WatchLog.Mark(at: start.addingTimeInterval(3600), kind: .heartbeat),
                     WatchLog.Mark(at: start.addingTimeInterval(2 * 86400 + 3600), kind: .heartbeat)]
        let s = [sample(day: 0, hour: 1, 8), sample(day: 2, hour: 1, 30)]
        let b = bars(s, marks, nowDay: 3)
        #expect(b[1].state == .unknown,
                "app 沒開的那天畫成 0%，等於把「我沒在看」講成「你沒有用」")
    }

    @Test("只有一端沒被看著 → unverified：數字給得出來，但歸屬可能落在隔壁那天")
    func halfWatchedDayIsUnverified() {
        // 第 1 天有心跳，但它的**結尾**（＝第 2 天的開頭）附近沒有。
        var marks = [WatchLog.Mark]()
        for h in stride(from: 0.0, to: 20.0, by: 1.0) {
            marks.append(.init(at: start.addingTimeInterval(86400 + h * 3600), kind: .heartbeat))
        }
        let s = [sample(day: 0, hour: 20, 8), sample(day: 1, hour: 10, 20)]
        let b = bars(s, marks, nowDay: 3)
        if case .unverified = b[1].state {} else {
            Issue.record("預期 unverified，實得 \(b[1].state)")
        }
    }

    @Test("今天那一根只需要起點被看著 —— 終點是「現在」，我們正在跑")
    func todayOnlyNeedsItsStartCovered() {
        let marks = [WatchLog.Mark(at: start.addingTimeInterval(2 * 86400), kind: .heartbeat)]
        let s = [sample(day: 1, hour: 20, 20), sample(day: 2, hour: 5, 26)]
        let b = bars(s, marks, nowDay: 2.5)
        #expect(b[2].state == .measured(percent: 6))
    }

    // ── 不可以說謊 ─────────────────────────────────────────────

    @Test("⚠️ 真的下降時說不知道，不畫一根負的")
    func aDecreaseBecomesUnknown() {
        let s = [sample(day: 0, hour: 20, 30), sample(day: 1, hour: 20, 25)]
        let b = bars(s, watchedThroughout(7), nowDay: 3)
        #expect(b[1].state == .unknown,
                "單調是前提，不是保證。前提壞了要說不知道，不是硬算一個數字")
    }

    @Test("有在看、卻一個取樣點都沒有 → 那是量到的 0，不是不知道")
    func watchedButNoSamplesIsAMeasuredZero() {
        // `shouldRecord` 只在數字變了才寫，所以「沒有取樣點」＝「沒有變過」＝仍然是 0。
        // ⚠️ 這一則是突變驗證逼出來的：原本我在這裡回 unknown，
        // 那是把「值是多少」與「我們有沒有在看」混成同一個問題。
        let b = bars([], watchedThroughout(7), nowDay: 3)
        #expect(b[0].state == .measured(percent: 0))
        #expect(b[2].state == .measured(percent: 0))
        #expect(b[3].state == .notYet)
    }

    @Test("沒在看、也沒有取樣點 → 這才是不知道")
    func unwatchedAndNoSamplesIsUnknown() {
        let b = bars([], [], nowDay: 3)
        #expect(b[0].state == .unknown)
        #expect(b[2].state == .unknown)
    }

    @Test("⚠️ 某一天中間的取樣點不會讓起點的基準漂掉 —— 起點取的是該時刻的值")
    func baselineIsTheValueAtTheBoundaryNotTheFirstSampleOfTheDay() {
        // 第 0 天結束時是 8；第 1 天只有一筆 20。第 1 天的用量是 20−8＝12，不是 20。
        let s = [sample(day: 0, hour: 20, 8), sample(day: 1, hour: 10, 20)]
        let b = bars(s, watchedThroughout(7), nowDay: 3)
        #expect(b[1].state == .measured(percent: 12))
    }

    @Test("窗口之後的取樣點不算進來")
    func samplesAfterTheWindowAreIgnored() {
        let s = [sample(day: 0, hour: 20, 8),
                 UsageSample(at: reset.addingTimeInterval(600), fiveHour: nil, sevenDay: 99)]
        let b = bars(s, watchedThroughout(7), nowDay: 6.9)
        #expect(b[6].state == .measured(percent: 0))
    }
}

/// 均速線。
@Suite("每日用量 — 均速線")
struct DailyUsagePaceTests {
    @Test("100% 平均分給七天")
    func evenPace() {
        #expect(abs(DailyUsage.evenPacePercent - 100.0 / 7.0) < 0.0001)
        // 約 14.3%／天。高於它就是在超支。
        #expect(DailyUsage.evenPacePercent > 14.2)
        #expect(DailyUsage.evenPacePercent < 14.3)
    }
    @Test("它跟著 days 走，不是寫死的 14.3")
    func derivedFromDays() {
        #expect(DailyUsage.evenPacePercent * Double(DailyUsage.days) == 100)
    }
}
