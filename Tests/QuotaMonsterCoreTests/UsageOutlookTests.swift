import Testing
import Foundation
@testable import QuotaMonsterCore

/// Core 與 App 之間唯一的縫。
///
/// 所有的拒絕都在這裡結束 —— `PanelView` 拿到的要嘛是一個可以直接畫的
/// `UsageOutlook`，要嘛是 `nil`，中間沒有算術。
@Suite("UsageOutlook")
struct UsageOutlookTests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)

    func window(_ percent: Int, elapsedFraction: Double,
                length: TimeInterval = UsagePace.fiveHour) -> UsageWindow {
        UsageWindow(percent: percent,
                    resetsAt: t0.addingTimeInterval(length * (1 - elapsedFraction)))
    }

    // ── 什麼時候整個不說話 ──────────────────────────────────────

    @Test("讀數過期就回 nil —— 就算每個數字都算得出來")
    func expiredReadingsProduceNothing() {
        // 與 GlyphState.quotaTier 同一條規則：過期時回 nil 而不是一個
        // 讓人放心的顏色。對一個你自己都知道不可信的數字做預測更糟。
        #expect(UsageOutlook.fiveHour(window(32, elapsedFraction: 0.65),
                                      freshness: .expired, measuredAt: t0,
                                      samples: []) == nil)
    }

    @Test("沒有窗口、或窗口沒有重置時間，都回 nil")
    func missingInputsProduceNothing() {
        #expect(UsageOutlook.fiveHour(nil, freshness: .live, measuredAt: t0,
                                      samples: []) == nil)
        #expect(UsageOutlook.fiveHour(UsageWindow(percent: 32, resetsAt: nil),
                                      freshness: .live, measuredAt: t0,
                                      samples: []) == nil)
    }

    @Test("投射說不出話時整個回 nil —— 沒有投射就沒有東西好修飾")
    func noProjectionMeansNoOutlook() {
        // 箭頭是形容詞。形容詞不能單獨出現。
        #expect(UsageOutlook.fiveHour(window(6, elapsedFraction: 0.05),
                                      freshness: .live, measuredAt: t0,
                                      samples: []) == nil)
    }

    @Test("有點舊但還沒過期的讀數照常說話，而且數字與全新時完全相同")
    func anAgingReadingStillSpeaks() throws {
        let fresh = try #require(UsageOutlook.fiveHour(window(32, elapsedFraction: 0.65),
                                                       freshness: .live, measuredAt: t0,
                                                       samples: []))
        let aging = try #require(UsageOutlook.fiveHour(window(32, elapsedFraction: 0.65),
                                                       freshness: .aging(minutes: 30),
                                                       measuredAt: t0, samples: []))
        #expect(fresh.projection.burnPerHour == aging.projection.burnPerHour)
    }

    // ── 箭頭 ───────────────────────────────────────────────────

    @Test("歷史不夠就沒有箭頭 —— 但投射照常")
    func noHistoryMeansNoArrowButStillANumber() throws {
        let o = try #require(UsageOutlook.fiveHour(window(32, elapsedFraction: 0.65),
                                                   freshness: .live, measuredAt: t0,
                                                   samples: []))
        #expect(o.trend == nil)
        #expect(o.burn == .refused(.noSamples))
    }

    @Test("fixture +25950：最近 10.74、均速 1.66 → 箭頭朝上")
    func theFasterCase() throws {
        // 那個窗口的均速被裡面 3.4 小時的閒置壓到 1.66 pp/h，
        // 但當下其實在以 10.74 燒。這就是箭頭存在的理由。
        let o = try #require(try outlookAtFixturePoint(
            now: 25_950, windowStart: 10_800, percent: 7))
        #expect(o.trend == .faster)
        #expect(abs(o.projection.burnPerHour - 1.6634) < 0.001)
    }

    @Test("fixture +4530：最近 8.81、均速 7.37 → 在死區內，沒有箭頭")
    func theSteadyCase() throws {
        // 差距 19.7%，還在 25% 的死區裡面。「差不多」不該畫一個箭頭 ——
        // 箭頭是純附加的，它的**缺席**不主張任何事。
        let o = try #require(try outlookAtFixturePoint(
            now: 4_530, windowStart: -7_200, percent: 24))
        #expect(o.trend == .steady)
        #expect(abs(o.projection.burnPerHour - 7.3657) < 0.001)
    }

    @Test("跨過那段 3.4 小時的空隙時沒有箭頭 —— 不是「變慢了」")
    func theGapProducesNoArrowNotASlowOne() throws {
        // 有一種天真的做法是拿「最新的點」與「更早的錨點」相減。
        // 那在這個空隙上會把箭頭指向**錯的方向**：+12003 到 +24410 之間
        // 什麼都沒發生（可能是沒開 app），錨點法會說「慢下來了」。
        // 切斷之後剩下的點不夠，於是沒有箭頭 —— 沒有箭頭是對的答案。
        let o = try #require(try outlookAtFixturePoint(
            now: 24_410, windowStart: 10_800, percent: 2))
        #expect(o.trend == nil)
    }

    // ── 升級：兩個都說會，才准說「會觸頂」 ───────────────────────

    @Test("只有均速說會觸頂 → 顯示數字，不顯示那三個字")
    func theAverageAloneMayNotRaiseTheAlarm() throws {
        let o = try #require(UsageOutlook.fiveHour(window(40, elapsedFraction: 0.25),
                                                   freshness: .live, measuredAt: t0,
                                                   samples: []))
        #expect(o.projection.outcome == .exceedsWindow)
        #expect(o.exceedsConfirmed == false)
    }

    @Test("均速與最近速率都說會觸頂 → 才准說「會觸頂」")
    func bothMustAgree() throws {
        // 最近速率用它的**第一四分位數**去檢查，不是中位數 ——
        // 要拉警報就用保守的那一端。
        let fast = (0..<10).map { i in
            UsageSample(at: t0.addingTimeInterval(Double(i) * 300 - 3000),
                        fiveHour: 10 + i * 4, sevenDay: nil)
        }
        let o = try #require(UsageOutlook.fiveHour(window(46, elapsedFraction: 0.25),
                                                   freshness: .live, measuredAt: t0,
                                                   samples: fast))
        #expect(o.projection.outcome == .exceedsWindow)
        #expect(o.exceedsConfirmed == true)
    }

    // ── 7 天那一欄刻意吃不到歷史 ────────────────────────────────

    @Test("7 天的展望不吃 samples —— 那個分母裡已經有你睡覺的時間了")
    func theSevenDayOutlookTakesNoHistory() throws {
        // 把最近速率乘以七天，正是這個專案禁止的那種很有自信的錯。
        // 簽章上就沒有 samples，所以這件事在型別上做不到。
        let o = try #require(UsageOutlook.sevenDay(
            window(50, elapsedFraction: 0.5, length: UsagePace.sevenDay),
            freshness: .live, measuredAt: t0))
        #expect(o.trend == nil)
        // 說成「歷史還是空的」是一句小謊 —— 它會讓人以為再等一陣子就會有箭頭。
        #expect(o.burn == .refused(.notUsedForThisWindow))
    }

    // ── helper ────────────────────────────────────────────────

    /// `now` 與 `windowStart` 都是 `Fixtures/usage/history-8h.jsonl`
    /// 的合成時間基準 `1_800_000_000` 的**偏移量**（秒）。
    /// 那份 fixture 是合成的，絕對 epoch 不代表任何真實時刻 ——
    /// 詳見 `UsageBurnTests` 開頭的來源說明。
    func outlookAtFixturePoint(now: Int, windowStart: Int,
                               percent: Int) throws -> UsageOutlook? {
        let base = 1_800_000_000
        let url = try Fixture.url("usage/history-8h.jsonl")
        let at = Date(timeIntervalSince1970: TimeInterval(base + now))
        let samples = UsageHistory().read(url, now: at)
        let start = Date(timeIntervalSince1970: TimeInterval(base + windowStart))
        return UsageOutlook.fiveHour(
            UsageWindow(percent: percent, resetsAt: start.addingTimeInterval(UsagePace.fiveHour)),
            freshness: .live, measuredAt: at, samples: samples)
    }
}
