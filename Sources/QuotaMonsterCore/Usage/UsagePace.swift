import Foundation

/// 從單一讀數推得的速率指標。
///
/// 目前只有「每日均量」—— 它是唯一不需要時間序列就算得出來的：
/// 窗口起點 = `resets_at − 窗口長度`，已過天數 = `now − 起點`。
///
/// 需要歷史才做得到的（燒量曲線、觸頂預測、每日長條圖）靠 `UsageHistory` 累積。
public enum UsagePace {

    /// 7 天窗口的長度。
    public static let sevenDay: TimeInterval = 7 * 86400
    /// 5 小時窗口的長度。
    public static let fiveHour: TimeInterval = 5 * 3600

    /// 窗口至少要過多久，日均才有意義。
    ///
    /// ⚠️ 這個下限不是保守，是**必要**：窗口剛重置時已過天數接近 0，
    /// 除下去會得到一個荒謬的大數字，而那個數字看起來完全像真的
    /// （「日均 340%」不會讓人覺得是 bug，只會讓人嚇一跳）。
    public static let minimumElapsedFraction = 0.05

    /// 這個窗口已經過了多久。算不出有意義的值時回 nil。
    ///
    /// 抽出來共用，是因為 `UsageProjection` 需要一模一樣的守衛 ——
    /// 各寫一份就會在某個邊界上一個說得出話、另一個說不出話，
    /// 而面板上那兩個數字會同時出現。
    static func elapsed(resetsAt: Date, windowLength: TimeInterval,
                        measuredAt: Date, minimumFraction: Double) -> TimeInterval? {
        let remaining = resetsAt.timeIntervalSince(measuredAt)
        // 已經重置，或時間戳壞掉（剩餘時間比整個窗口還長）
        guard remaining > 0, remaining <= windowLength else { return nil }

        let elapsed = windowLength - remaining
        guard elapsed >= windowLength * minimumFraction else { return nil }
        return elapsed
    }

    /// - Returns: 每天用掉幾個百分點。算不出有意義的值時回 nil，**不回 0**。
    public static func dailyAverage(percent: Int, resetsAt: Date,
                                    windowLength: TimeInterval, now: Date) -> Double? {
        guard let elapsed = elapsed(resetsAt: resetsAt, windowLength: windowLength,
                                    measuredAt: now, minimumFraction: minimumElapsedFraction)
        else { return nil }
        return Double(percent) / (elapsed / 86400)
    }
}
