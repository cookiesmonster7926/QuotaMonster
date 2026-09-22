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
    /// 每天都有**看得到**的心跳 → 每個邊界都被看著。
    /// ⚠️ `sawLiveReading` 必須明寫 —— 預設是 false（醒著但看不到），
    /// 而「醒著」不等於「看得到」（見 `WatchLog.Mark.sawLiveReading`）。
    func watchedThroughout(_ days: Int) -> [WatchLog.Mark] {
        stride(from: 0.0, through: Double(days) * 86400, by: WatchLog.interval)
            .map { WatchLog.Mark(at: start.addingTimeInterval($0), kind: .heartbeat,
                                 sawLiveReading: true) }
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
        let marks = [WatchLog.Mark(at: start.addingTimeInterval(3600), kind: .heartbeat, sawLiveReading: true),
                     WatchLog.Mark(at: start.addingTimeInterval(2 * 86400 + 3600), kind: .heartbeat, sawLiveReading: true)]
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
            marks.append(.init(at: start.addingTimeInterval(86400 + h * 3600), kind: .heartbeat,
                               sawLiveReading: true))
        }
        let s = [sample(day: 0, hour: 20, 8), sample(day: 1, hour: 10, 20)]
        let b = bars(s, marks, nowDay: 3)
        if case .unverified = b[1].state {} else {
            Issue.record("預期 unverified，實得 \(b[1].state)")
        }
    }

    @Test("今天那一根只需要起點被看著 —— 終點是「現在」，我們正在跑")
    func todayOnlyNeedsItsStartCovered() {
        let marks = [WatchLog.Mark(at: start.addingTimeInterval(2 * 86400), kind: .heartbeat,
                                   sawLiveReading: true)]
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

/// 帳號是共用的 —— 別人／別的裝置也會燒額度。
///
/// 〔實測 2026-09-22〕18.8 小時裡有 16.1 小時（**85%**）這台機器沒有渲染狀態列，
/// 而 QuotaMonster 是醒著的。`7d` 是帳號層級的，所以那段時間別人燒掉的量
/// **確實會被算進去** —— 我們只是看不到它是**哪一天**燒的。
@Suite("每日用量 — 共用帳號")
struct DailyUsageSharedAccountTests {
    let reset = Date(timeIntervalSince1970: 1_790_402_400)
    var start: Date { reset.addingTimeInterval(-7 * 86400) }

    func mark(_ day: Double, _ hour: Double, live: Bool) -> WatchLog.Mark {
        WatchLog.Mark(at: start.addingTimeInterval(day * 86400 + hour * 3600),
                      kind: .heartbeat, sawLiveReading: live)
    }
    func sample(_ day: Double, _ hour: Double, _ v: Int) -> UsageSample {
        UsageSample(at: start.addingTimeInterval(day * 86400 + hour * 3600),
                    fiveHour: nil, sevenDay: v)
    }

    @Test("⚠️ app 醒著但整天看不到 → unknown，**不是 0%**")
    func awakeButBlindIsUnknown() {
        // ⚠️ 這一則第一版寫錯了，錯法本身值得記下來：
        // 我讓第 0 天與第 2 天都有**活**心跳、只有第 1 天瞎掉，然後期待 unknown。
        // 但那個情境是自相矛盾的 —— **如果日界兩端都有活讀數，中間瞎掉不重要**：
        // 兩端觀測到的值沒變，就代表那天真的沒有消耗（`7d` 在窗口內單調）。
        // 真正的失敗形狀是「**瞎掉的那一段跨過了日界**」。
        //
        // 情境：這台機器在第 0 天晚上之後就沒再渲染，第 2 天才回來。
        // 期間別人／別的裝置燒了 20%，而我們分不出那是第 1 天還是第 2 天燒的。
        var marks = [WatchLog.Mark]()
        for h in stride(from: 0.0, through: 22.0, by: 1.0) { marks.append(mark(0, h, live: true)) }
        // 整段瞎掉（醒著但沒有活讀數），橫跨第 0/1 與第 1/2 兩條日界
        for h in stride(from: 23.0, through: 24.0 + 26.0, by: 1.0) {
            marks.append(mark(0, h, live: false))
        }
        for h in stride(from: 3.0, through: 24.0, by: 1.0) { marks.append(mark(2, h, live: true)) }
        let s = [sample(0, 20, 8), sample(2, 4, 28)]
        let b = DailyUsage.bars(samples: s, marks: marks, resetsAt: reset,
                                now: start.addingTimeInterval(3 * 86400))
        #expect(b[1].state == .unknown,
                "整天都沒有活讀數 → 說不出那天燒了多少，畫成 0% 等於把別人燒的量藏起來")
    }

    @Test("⚠️ 日界兩端都有活讀數時，中間瞎掉**不影響**那天的總量")
    func blindMiddleDoesNotMatter() {
        // 兩端都觀測到，而且值一樣 → 那天真的是 0%。這不是僥倖，是 7d 單調的後果。
        var marks = [WatchLog.Mark]()
        marks.append(mark(1, 0, live: true))
        for h in stride(from: 1.0, through: 23.0, by: 1.0) { marks.append(mark(1, h, live: false)) }
        marks.append(mark(2, 0, live: true))
        let b = DailyUsage.bars(samples: [sample(0, 20, 8)], marks: marks, resetsAt: reset,
                                now: start.addingTimeInterval(2.5 * 86400))
        #expect(b[1].state == .measured(percent: 0))
    }

    @Test("看得到的那幾天照常量得出來")
    func daysWeCouldSeeAreStillMeasured() {
        var marks = [WatchLog.Mark]()
        for d in 0...3 {
            for h in stride(from: 0.0, through: 24.0, by: 1.0) {
                marks.append(mark(Double(d), h, live: true))
            }
        }
        let s = [sample(0, 20, 8), sample(1, 20, 20)]
        let b = DailyUsage.bars(samples: s, marks: marks, resetsAt: reset,
                                now: start.addingTimeInterval(2.5 * 86400))
        #expect(b[0].state == .measured(percent: 8))
        #expect(b[1].state == .measured(percent: 12))
    }

    @Test("開機標記不算觀測 —— 只有 boot 的那一天仍然是 unknown")
    func bootAloneIsNotObservation() {
        let marks = [WatchLog.Mark(at: start.addingTimeInterval(86400 + 3600), kind: .boot)]
        let b = DailyUsage.bars(samples: [sample(0, 20, 8)], marks: marks, resetsAt: reset,
                                now: start.addingTimeInterval(3 * 86400))
        #expect(b[1].state == .unknown)
    }
}

/// 累計曲線 —— 同一份資料的另一種看法（使用者 2026-09-22 選擇兩種都做、可在設定切換）。
///
/// ### 為什麼這個視圖沒有歸屬問題
/// 長條圖要回答「**哪一天**燒的」，所以日界附近看不到就會出錯。
/// 累計曲線只回答「到這一刻為止燒了多少」——**那個問題不需要分天**，
/// 所以共用帳號、別的裝置、觀測空窗都不影響它的正確性。
/// 它唯一的損失是「空窗那一段的形狀」：兩個觀測點之間我們畫的是直線，
/// 而真實可能是階梯。總量與端點都是對的。
@Suite("累計曲線")
struct CumulativeTests {
    let reset = Date(timeIntervalSince1970: 1_790_402_400)
    var start: Date { reset.addingTimeInterval(-7 * 86400) }
    func sample(_ day: Double, _ hour: Double, _ v: Int?) -> UsageSample {
        UsageSample(at: start.addingTimeInterval(day * 86400 + hour * 3600),
                    fiveHour: nil, sevenDay: v)
    }

    @Test("第一個點一定是窗口起點的 0% —— 那是定義，不是資料")
    func startsAtZero() {
        let pts = DailyUsage.cumulative(samples: [sample(1, 0, 12)], resetsAt: reset,
                                        now: start.addingTimeInterval(2 * 86400))
        #expect(pts.first?.at == start)
        #expect(pts.first?.percent == 0)
    }

    @Test("最後一個點是「現在」，帶著當下的值 —— 曲線要畫到現在，不是畫到最後一次取樣")
    func endsAtNow() {
        let now = start.addingTimeInterval(2 * 86400)
        let pts = DailyUsage.cumulative(samples: [sample(1, 0, 12)], resetsAt: reset, now: now)
        #expect(pts.last?.at == now)
        #expect(pts.last?.percent == 12)
    }

    @Test("中間就是每一個取樣點，照時間排好")
    func keepsEverySample() {
        let pts = DailyUsage.cumulative(samples: [sample(2, 0, 20), sample(1, 0, 12)],
                                        resetsAt: reset, now: start.addingTimeInterval(3 * 86400))
        #expect(pts.map(\.percent) == [0, 12, 20, 20])
        #expect(pts.map(\.at) == pts.map(\.at).sorted())
    }

    @Test("窗口外的取樣點不算進來")
    func ignoresSamplesOutsideTheWindow() {
        let before = UsageSample(at: start.addingTimeInterval(-600), fiveHour: nil, sevenDay: 75)
        let pts = DailyUsage.cumulative(samples: [before, sample(1, 0, 12)], resetsAt: reset,
                                        now: start.addingTimeInterval(2 * 86400))
        #expect(pts.map(\.percent) == [0, 12, 12])
    }

    @Test("沒有讀數的取樣點跳過 —— nil 不是 0")
    func skipsNilReadings() {
        let pts = DailyUsage.cumulative(samples: [sample(1, 0, nil), sample(1, 1, 12)],
                                        resetsAt: reset, now: start.addingTimeInterval(2 * 86400))
        #expect(pts.map(\.percent) == [0, 12, 12])
    }

    @Test("一個取樣點都沒有時，仍然畫得出「從 0 到現在還是 0」那條平線")
    func flatLineWhenNothingHappened() {
        let now = start.addingTimeInterval(2 * 86400)
        let pts = DailyUsage.cumulative(samples: [], resetsAt: reset, now: now)
        #expect(pts.count == 2)
        #expect(pts.allSatisfy { $0.percent == 0 })
    }

    @Test("窗口還沒開始（時鐘怪怪的）不可以爆 —— 回空的")
    func beforeTheWindowIsEmpty() {
        #expect(DailyUsage.cumulative(samples: [], resetsAt: reset,
                                      now: start.addingTimeInterval(-60)).isEmpty)
    }

    // ── 讀數自相矛盾 ──────────────────────────────────────────
    //
    // 同一個窗口內 7d 不可能變小（它是這個窗口的累計）。所以「比先前看過的
    // 最高值還低」的讀數，與那個最高值**其中之一是錯的，而我們不知道是哪一個**。
    //
    // ⚠️ 這不是假設性的：〔實測 2026-09-22，本機歷史檔 66 筆窗口內取樣〕
    // 09-20 15:25 是 19，09-21 19:30 掉到 0，接著 13、14…… 到 20:40 才回到 19。
    // 畫成原始曲線就是一條**往下走的累計線** —— 那在定義上不可能。
    // 兩種偷懶的修法都不行：直接畫（宣告一件不可能的事）、
    // 夾成遞增（把壞資料悄悄改成好資料）。所以標出來。

    @Test("一路上升時沒有任何一點被標成矛盾")
    func monotonicHasNoContradictions() {
        let pts = DailyUsage.cumulative(samples: [sample(1, 0, 12), sample(2, 0, 20)],
                                        resetsAt: reset, now: start.addingTimeInterval(3 * 86400))
        #expect(pts.allSatisfy { !$0.contradictsEarlier })
    }

    @Test("掉下去的那一點要標成矛盾")
    func aDropIsMarked() {
        let pts = DailyUsage.cumulative(samples: [sample(1, 0, 19), sample(2, 0, 0)],
                                        resetsAt: reset, now: start.addingTimeInterval(3 * 86400))
        #expect(pts.map(\.contradictsEarlier) == [false, false, true, true])
    }

    @Test("回升到還沒超過先前最高之前，每一點都還是矛盾的")
    func stillContradictedWhileBelowTheEarlierPeak() {
        // ⚠️ 這一則是「只比前一點」與「比先前最高」的分水嶺：
        // 19 → 0 → 13 → 25，只比前一點的實作會說 13 沒問題 ——
        // 但 13 與那個 19 一樣不可能同時成立。
        let pts = DailyUsage.cumulative(
            samples: [sample(1, 0, 19), sample(2, 0, 0), sample(2, 1, 13), sample(2, 2, 25)],
            resetsAt: reset, now: start.addingTimeInterval(2 * 86400 + 3 * 3600))
        #expect(pts.map(\.percent) == [0, 19, 0, 13, 25, 25])
        #expect(pts.map(\.contradictsEarlier) == [false, false, true, true, false, false])
    }

    @Test("「現在」那一點跟著它繼承的那個值 —— 還在谷底就還是矛盾的")
    func theNowPointInheritsTheContradiction() {
        let now = start.addingTimeInterval(3 * 86400)
        let pts = DailyUsage.cumulative(samples: [sample(1, 0, 19), sample(2, 0, 5)],
                                        resetsAt: reset, now: now)
        #expect(pts.last?.at == now)
        #expect(pts.last?.contradictsEarlier == true)
    }

    @Test("起點那個 0% 永遠不是矛盾 —— 它是定義")
    func theSyntheticStartIsNeverContradicted() {
        let pts = DailyUsage.cumulative(samples: [sample(1, 0, 0)], resetsAt: reset,
                                        now: start.addingTimeInterval(2 * 86400))
        #expect(pts.allSatisfy { !$0.contradictsEarlier })
    }

    // ── 圖例 ──────────────────────────────────────────────────

    @Test("正常時圖例講那條斜線 —— 那是這張圖唯一能回答「會不會用完」的東西")
    func legendExplainsThePaceLine() {
        let pts = DailyUsage.cumulative(samples: [sample(1, 0, 12)], resetsAt: reset,
                                        now: start.addingTimeInterval(2 * 86400))
        #expect(DailyUsage.cumulativeLegend(pts).contains("重置"))
    }

    @Test("有矛盾時圖例改去解釋那一段 —— 看得見的怪事優先於看不見的細節")
    func legendExplainsTheContradictionInstead() {
        let pts = DailyUsage.cumulative(samples: [sample(1, 0, 19), sample(2, 0, 0)],
                                        resetsAt: reset, now: start.addingTimeInterval(3 * 86400))
        #expect(DailyUsage.cumulativeLegend(pts).contains("矛盾"))
    }
}
