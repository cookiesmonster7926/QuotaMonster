import Foundation

/// 「照這個速度，這個窗口會怎麼收場？」
///
/// ### 為什麼不需要歷史
/// 窗口的起點就是 `resetsAt − 窗口長度`。單一讀數因此同時給出分子（已用百分比）
/// 與分母（已過時間），均速與重置時的投射值都算得出來 —— **第一次啟動、
/// 歷史檔還是空的，它就正確**。歷史只用來回答「最近的節奏比均速快還是慢」，
/// 那是形容詞，見 `UsageBurn`。
///
/// ### ⚠️ 它刻意不提供時鐘觸頂時間
/// 實測：這台機器上最快的一段是 **22.52 pp/h**（17:46:49–18:00:37 那 7 個點），
/// 而它只持續了 **14 分鐘** —— 下一個觀測是 44 分鐘後的一個 null。
/// 要把 5 小時窗口用完需要 20 pp/h 撐滿五小時，資料裡沒有任何證據支持
/// 任何速率會持續那麼久。而時鐘時間正是使用者會拿去排行程的東西：
/// 一句「19:40 觸頂」錯了，比什麼都不說糟得多。
///
/// 所以 `Outcome` 只有三種，而且沒有一種帶著時間。
public struct UsageProjection: Equatable, Sendable {

    public enum Outcome: Equatable, Sendable {
        /// 重置會先到 —— 照均速這個窗口用不完。帶重置那一刻的投射值 0…<100。
        case resetsFirst(projectedPercent: Int)
        /// 照均速會在重置之前用完。**刻意沒有時間。**
        case exceedsWindow
        /// 已經 100%。沒有東西好預測了。
        case exhausted
    }

    public let percent: Int
    /// `resetsAt − windowLength`。
    public let windowStart: Date
    public let resetsAt: Date
    public let windowLength: TimeInterval
    public let elapsed: TimeInterval
    public let burnPerHour: Double
    /// 照均速外推到重置那一刻會是幾 %。**可以大於 100** ——
    /// 超過時 `outcome` 是 `.exceedsWindow`，但這個數字仍然講得出來，
    /// 因為「均速說會超過、但最近的節奏還沒證實」那一格需要說一句
    /// 比警報弱、又比沉默強的話。
    public let projectedPercent: Int
    public let outcome: Outcome

    /// 與 `UsagePace.dailyAverage` 是同一個東西，有測試釘住它們不准漂開。
    public var burnPerDay: Double { burnPerHour * 24 }
    public var elapsedFraction: Double { elapsed / windowLength }

    // ── 門檻 ───────────────────────────────────────────────────

    /// 5 小時窗口：**0.15，也就是 45 分鐘**。
    ///
    /// ⚠️ **不是 0.05。** `UsagePace.minimumElapsedFraction` 的 0.05 是為
    /// **7 天**窗口挑的（5% 的七天 = 8.4 小時）。同一個數字放到 5 小時窗口上
    /// 只剩 15 分鐘 —— 把實測最快的那一段放在剛重置的窗口起點，15 分鐘後
    /// 就會投射出 120% 並宣告「會觸頂」，而那段突發只持續了 14 分鐘。
    ///
    /// 45 分鐘在實測資料上一毛錢都不花：26 個點裡只有 19:45 那兩個
    /// `elapsed ≈ 0` 的被擋下來，而它們本來就該被擋。
    public static let fiveHourMinimumElapsed = 0.15

    /// 7 天窗口：0.30，約 2.1 天。
    ///
    /// 把一整週從一個下午外推，等於假設週末跟週三一樣忙。
    public static let sevenDayMinimumElapsed = 0.30

    // ── 建構 ───────────────────────────────────────────────────

    /// - Parameter measuredAt: **`snapshot.fetchedAt`，不是 `Date()`。**
    ///   用 `Date()` 的話分母會一直長、分子卻停在讀數被抓下來的那一刻，
    ///   燒量會被安靜地低估，而且讀數愈舊低估愈多。
    public static func fiveHour(percent: Int, resetsAt: Date,
                                measuredAt: Date) -> UsageProjection? {
        measure(percent: percent, resetsAt: resetsAt, windowLength: UsagePace.fiveHour,
                measuredAt: measuredAt, minimumElapsedFraction: fiveHourMinimumElapsed)
    }

    public static func sevenDay(percent: Int, resetsAt: Date,
                                measuredAt: Date) -> UsageProjection? {
        measure(percent: percent, resetsAt: resetsAt, windowLength: UsagePace.sevenDay,
                measuredAt: measuredAt, minimumElapsedFraction: sevenDayMinimumElapsed)
    }

    /// ⚠️ **internal，只有上面兩個 wrapper 呼叫得到。**
    /// 窗口長度與門檻是一對，不可以由外面自己湊 —— 把 7 天的長度配上
    /// 5 小時的門檻，正是印出「日均 340%」的方式。
    static func measure(percent: Int, resetsAt: Date, windowLength: TimeInterval,
                        measuredAt: Date, minimumElapsedFraction: Double) -> UsageProjection? {
        guard let elapsed = UsagePace.elapsed(resetsAt: resetsAt, windowLength: windowLength,
                                              measuredAt: measuredAt,
                                              minimumFraction: minimumElapsedFraction)
        else { return nil }

        let burnPerHour = Double(percent) / (elapsed / 3600)
        let windowStart = resetsAt.addingTimeInterval(-windowLength)

        // 照均速線性外推到重置那一刻。
        let projected = Int((Double(percent) * windowLength / elapsed).rounded())
        let outcome: Outcome
        if percent >= 100 {
            outcome = .exhausted
        } else {
            outcome = projected >= 100 ? .exceedsWindow
                                       : .resetsFirst(projectedPercent: projected)
        }

        return UsageProjection(percent: percent, windowStart: windowStart, resetsAt: resetsAt,
                               windowLength: windowLength, elapsed: elapsed,
                               burnPerHour: burnPerHour, projectedPercent: projected,
                               outcome: outcome)
    }

    init(percent: Int, windowStart: Date, resetsAt: Date, windowLength: TimeInterval,
         elapsed: TimeInterval, burnPerHour: Double, projectedPercent: Int,
         outcome: Outcome) {
        self.percent = percent
        self.windowStart = windowStart
        self.resetsAt = resetsAt
        self.windowLength = windowLength
        self.elapsed = elapsed
        self.burnPerHour = burnPerHour
        self.projectedPercent = projectedPercent
        self.outcome = outcome
    }
}
