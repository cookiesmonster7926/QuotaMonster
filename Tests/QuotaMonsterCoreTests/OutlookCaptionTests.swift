import Testing
import Foundation
@testable import QuotaMonsterCore

/// 面板註腳的字串。
///
/// **為什麼字串放在 Core：** `QuotaMonsterApp` 沒有測試（它碰 AppKit），
/// 而這個功能的風險幾乎全在字串上 —— 一個新功能最容易造成的傷害，
/// 是安靜地改掉使用者已經每天在看的那一行。放在 Core 就變成
/// 一個 `#expect` 的回歸測試，而不是一句承諾。
@Suite("OutlookCaption")
struct OutlookCaptionTests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)

    func projection(percent: Int, elapsedFraction: Double) -> UsageProjection? {
        UsageProjection.fiveHour(
            percent: percent,
            resetsAt: t0.addingTimeInterval(UsagePace.fiveHour * (1 - elapsedFraction)),
            measuredAt: t0)
    }

    /// 沒有歷史的展望 —— 有數字、沒有箭頭。
    func outlook(percent: Int, elapsedFraction: Double,
                 burn: BurnOutcome = .refused(.noSamples)) -> UsageOutlook? {
        projection(percent: percent, elapsedFraction: elapsedFraction)
            .map { UsageOutlook(projection: $0, burn: burn) }
    }

    /// 造一個指定速率的 burn，用來單獨測箭頭與升級。
    func burn(_ perHour: Double, lower: Double? = nil) -> BurnOutcome {
        .estimate(BurnEstimate(percentPerHour: perHour,
                               lowerPercentPerHour: lower ?? perHour * 0.9,
                               upperPercentPerHour: perHour * 1.1,
                               sampleCount: 8, pairCount: 12, span: 1800, latestAt: t0))
    }

    // ── 最重要的一組：拒絕時不准動到既有的字 ──────────────────────

    @Test("投射拒絕時，註腳與今天顯示的一模一樣 —— 一個位元組都不差")
    func refusalLeavesTodaysCaptionUntouched() {
        #expect(OutlookCaption.fiveHour(resetText: "剩 2h 14m", outlook: nil)
                == "剩 2h 14m")
        #expect(OutlookCaption.fiveHour(resetText: "已重置", outlook: nil) == "已重置")
        #expect(OutlookCaption.fiveHour(resetText: " ", outlook: nil) == " ")
    }

    @Test("窗口才剛重置（門檻擋下來）也是如此")
    func justAfterAResetIsTodaysCaption() {
        // 每次 5 小時重置後的前 45 分鐘都會走這條路，一天大約五次。
        // 那是門檻在做它該做的事，不是壞掉。
        #expect(OutlookCaption.fiveHour(resetText: "剩 4h 30m",
                                        outlook: outlook(percent: 6,
                                                         elapsedFraction: 0.05))
                == "剩 4h 30m")
    }

    // ── 有話可說的時候 ─────────────────────────────────────────

    @Test("重置會先到 —— 說出重置那一刻的投射值")
    func resetsFirstShowsTheProjectedPercent() {
        #expect(OutlookCaption.fiveHour(resetText: "剩 1h 44m",
                                        outlook: outlook(percent: 32,
                                                         elapsedFraction: 0.65))
                == "剩 1h 44m · 估 49%")
    }

    @Test("只有均速說會超過 → 說一個數字，不拉警報")
    func theAverageAloneOnlyShowsANumber() {
        // 均速會被窗口前段的一場衝刺帶偏。沒有最近速率佐證時，
        // 這一格要說一句比警報弱、又比沉默強的話。
        #expect(OutlookCaption.fiveHour(resetText: "剩 3h 45m",
                                        outlook: outlook(percent: 40, elapsedFraction: 0.25))
                == "剩 3h 45m · 估 >100%")
    }

    @Test("均速與最近速率都說會 → 才說「會觸頂」")
    func bothAgreeingRaisesTheAlarm() {
        let o = outlook(percent: 40, elapsedFraction: 0.25, burn: burn(40, lower: 35))
        #expect(o?.exceedsConfirmed == true)
        #expect(OutlookCaption.fiveHour(resetText: "剩 3h 45m", outlook: o)
                == "剩 3h 45m · 估 會觸頂")
    }

    // ── 箭頭 ───────────────────────────────────────────────────

    @Test("最近比均速快 → 箭頭朝上")
    func fasterGetsAnUpArrow() {
        // 均速 32/(5*0.65) ≈ 9.85 pp/h，最近 20 → 快一倍。
        #expect(OutlookCaption.fiveHour(resetText: "剩 1h 44m",
                                        outlook: outlook(percent: 32, elapsedFraction: 0.65,
                                                         burn: burn(20)))
                == "剩 1h 44m · 估 49% ↑")
    }

    @Test("最近比均速慢 → 箭頭朝下")
    func slowerGetsADownArrow() {
        #expect(OutlookCaption.fiveHour(resetText: "剩 1h 44m",
                                        outlook: outlook(percent: 32, elapsedFraction: 0.65,
                                                         burn: burn(2)))
                == "剩 1h 44m · 估 49% ↓")
    }

    @Test("差不多就不畫箭頭 —— 它的缺席不主張任何事")
    func steadyDrawsNothing() {
        // 「差不多」與「不知道」在畫面上刻意合流：箭頭是純附加的，
        // 所以看不到箭頭時，使用者不會被誤導成「所以是持平」。
        #expect(OutlookCaption.fiveHour(resetText: "剩 1h 44m",
                                        outlook: outlook(percent: 32, elapsedFraction: 0.65,
                                                         burn: burn(9.85)))
                == "剩 1h 44m · 估 49%")
    }

    @Test("拉警報的那一格不再加箭頭 —— 那已經是最強的說法了")
    func theAlarmDoesNotAlsoCarryAnArrow() {
        #expect(OutlookCaption.fiveHour(
            resetText: "剩 3h 45m",
            outlook: outlook(percent: 40, elapsedFraction: 0.25, burn: burn(40, lower: 35)))
                == "剩 3h 45m · 估 會觸頂")
    }

    @Test("已經觸頂 —— 剩下的唯一有用資訊是什麼時候恢復")
    func exhaustedSaysWhenItComesBack() {
        #expect(OutlookCaption.fiveHour(resetText: "剩 41m",
                                        outlook: outlook(percent: 100,
                                                         elapsedFraction: 0.86))
                == "已觸頂 · 41m 後恢復")
    }

    @Test("已觸頂但倒數講不出來時，不要硬湊一句話")
    func exhaustedWithoutACountdownFallsBack() {
        #expect(OutlookCaption.fiveHour(resetText: "已重置",
                                        outlook: outlook(percent: 100,
                                                         elapsedFraction: 0.86))
                == "已觸頂")
    }

    // ── 第二欄：預設就是今天那一行 ──────────────────────────────

    @Test("7 天欄預設完全不變 —— 日均留著")
    func sevenDayKeepsTodaysString() {
        #expect(OutlookCaption.sevenDay(resetText: "週六 下午1:59", dailyAverage: 8.78,
                                        outlook: nil)
                == "週六 下午1:59 · 日均 8.8%")
    }

    @Test("連日均都算不出來時，只剩重置時間")
    func sevenDayWithoutAnAverage() {
        #expect(OutlookCaption.sevenDay(resetText: "週六 下午1:59", dailyAverage: nil,
                                        outlook: nil)
                == "週六 下午1:59")
    }

    @Test("只有真的會用完才替換掉日均 —— 而且是替換不是附加")
    func sevenDayEscalatesOnlyWhenItWillRunOut() {
        // 第二欄今天已經是 109.9pt、縮到 0.90 了，只能用換的不能用加的。
        let o = UsageOutlook.sevenDay(
            UsageWindow(percent: 60,
                        resetsAt: t0.addingTimeInterval(UsagePace.sevenDay * 0.5)),
            freshness: .live, measuredAt: t0)
        #expect(o?.projection.outcome == .exceedsWindow)
        #expect(OutlookCaption.sevenDay(resetText: "週六 下午1:59", dailyAverage: 8.78,
                                        outlook: o)
                == "週六 下午1:59 · 會用完")
    }

    @Test("7 天投射說得出話但不會用完時，仍然顯示日均 —— 不引入第三種字")
    func sevenDayWithAHealthyProjectionStillShowsTheAverage() {
        let o = UsageOutlook.sevenDay(
            UsageWindow(percent: 30,
                        resetsAt: t0.addingTimeInterval(UsagePace.sevenDay * 0.5)),
            freshness: .live, measuredAt: t0)
        #expect(o?.projection.outcome != .exceedsWindow)
        #expect(OutlookCaption.sevenDay(resetText: "週六 下午1:59", dailyAverage: 8.78,
                                        outlook: o)
                == "週六 下午1:59 · 日均 8.8%")
    }

    // ── tooltip：放得下完整那句話的地方 ─────────────────────────

    @Test("tooltip 說出分母，不只說結論")
    func theTooltipShowsTheDenominator() {
        let text = OutlookCaption.evidence(outlook(percent: 32, elapsedFraction: 0.65,
                                                   burn: burn(20)))
        #expect(text.contains("已經走了"))
        #expect(text.contains("32%"))
        #expect(text.contains("均速"))
        #expect(text.contains("最近"))
    }

    @Test("說不出最近節奏時，tooltip 要**講出來**，不是安靜地省略")
    func theTooltipNamesTheRefusal() {
        let text = OutlookCaption.evidence(outlook(percent: 32, elapsedFraction: 0.65))
        #expect(text.contains("歷史"))
        #expect(!text.contains("最近的節奏比"))
    }

    @Test("完全沒有展望時 tooltip 是空的 —— 不要憑空造一句話")
    func noOutlookMeansNoTooltip() {
        #expect(OutlookCaption.evidence(nil) == "")
    }
}
