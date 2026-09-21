import Foundation

/// 最近的節奏比這個窗口的均速快還是慢。
///
/// ⚠️ **這是形容詞，不是數字。** 它只能修飾 `UsageProjection`，
/// 永遠不可以取代它，也永遠不可以在沒有它的時候單獨出現。
public enum UsageTrend: Equatable, Sendable {
    case faster
    case slower
    /// 差不多。**不畫箭頭** —— 與「不知道」在畫面上刻意合流：
    /// 箭頭是純附加的，所以它的**缺席**不主張任何事。
    case steady

    /// 死區。要偏離均速這個比例以上才算數。
    ///
    /// 實測 18:00:37 那一刻最近 8.91、均速 9.85，差 9.5% —— 那是「差不多」，
    /// 不該畫箭頭。而 23:37:43 是 10.75 對 1.81，差了五倍，那是真的變快了。
    public static let deadband = 0.25

    static func from(recent: Double, average: Double) -> UsageTrend {
        guard average > 0 else { return .steady }
        let ratio = recent / average
        if ratio > 1 + deadband { return .faster }
        if ratio < 1 - deadband { return .slower }
        return .steady
    }
}

/// 一個窗口的完整展望：**數字 + 修飾它的形容詞**。
///
/// Core 與 App 之間唯一的縫。所有的拒絕都在這裡結束 ——
/// `PanelView` 拿到的要嘛是一個可以直接畫的值，要嘛是 `nil`，中間沒有算術。
public struct UsageOutlook: Equatable, Sendable {

    /// 主角。**非 optional** —— 沒有投射就沒有 `UsageOutlook`。
    public let projection: UsageProjection
    /// 最近的燒量，或它為什麼說不出話（具名，tooltip 要印）。
    public let burn: BurnOutcome

    public var trend: UsageTrend? {
        burn.value.map { UsageTrend.from(recent: $0.percentPerHour,
                                         average: projection.burnPerHour) }
    }

    /// 可以說出「會觸頂」那三個字了嗎？
    ///
    /// ⚠️ **均速與最近速率都說會，才算數。** 任何一個單獨都不准拉警報：
    /// 均速會被窗口前段的一場衝刺帶偏，最近速率會被一段十四分鐘的突發帶偏。
    /// 而且最近速率用它的**第一四分位數**檢查，不是中位數 ——
    /// 要拉警報就用保守的那一端。
    public var exceedsConfirmed: Bool {
        guard projection.outcome == .exceedsWindow, let e = burn.value,
              e.lowerPercentPerHour > 0 else { return false }
        let hoursLeftInWindow = (projection.windowLength - projection.elapsed) / 3600
        let percentLeft = Double(100 - projection.percent)
        return percentLeft / e.lowerPercentPerHour < hoursLeftInWindow
    }

    public init(projection: UsageProjection, burn: BurnOutcome) {
        self.projection = projection
        self.burn = burn
    }

    // ── 建構 ───────────────────────────────────────────────────

    /// - Parameter measuredAt: `snapshot.fetchedAt`，不是 `Date()`。見 `UsageProjection`。
    public static func fiveHour(_ window: UsageWindow?, freshness: Freshness,
                                measuredAt: Date, samples: [UsageSample]) -> UsageOutlook? {
        // 過期就什麼都不說。與 `GlyphState.quotaTier` 同一條規則 ——
        // 對一個你自己都知道不可信的數字做預測，比不做更糟。
        guard freshness != .expired, let window, let resetsAt = window.resetsAt,
              let projection = UsageProjection.fiveHour(percent: window.percent,
                                                        resetsAt: resetsAt,
                                                        measuredAt: measuredAt)
        else { return nil }

        let burn = UsageBurn.fiveHour(samples, windowStart: projection.windowStart,
                                      now: measuredAt)
        return UsageOutlook(projection: projection, burn: burn)
    }

    /// ⚠️ **簽章上刻意沒有 `samples`。**
    ///
    /// 7 天窗口唯一誠實的估計法就是它自己的均速，因為那個分母裡**已經包含了
    /// 你睡覺的時間**。把一段最近的速率乘以七天，正是這個專案禁止的那種
    /// 很有自信的錯 —— 而讓它連拿都拿不到歷史，比寫一行註解叫人不要那樣做有效。
    public static func sevenDay(_ window: UsageWindow?, freshness: Freshness,
                                measuredAt: Date) -> UsageOutlook? {
        guard freshness != .expired, let window, let resetsAt = window.resetsAt,
              let projection = UsageProjection.sevenDay(percent: window.percent,
                                                        resetsAt: resetsAt,
                                                        measuredAt: measuredAt)
        else { return nil }
        return UsageOutlook(projection: projection, burn: .refused(.notUsedForThisWindow))
    }
}
