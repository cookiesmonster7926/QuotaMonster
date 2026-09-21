import Foundation

/// 單一額度窗口的讀數。
public struct UsageWindow: Equatable, Sendable {
    /// 已使用的百分比，0–100。
    public let percent: Int
    /// 這個窗口何時重置。可能為 nil（伺服器未提供）。
    public let resetsAt: Date?

    public init(percent: Int, resetsAt: Date?) {
        self.percent = percent
        self.resetsAt = resetsAt
    }
}

/// 讀數的新鮮度。
///
/// 刻意是三態列舉而不是布林：UI 必須能區分
/// 「新鮮」/「有點舊（要顯示年齡）」/「過期（要灰化）」。
public enum Freshness: Equatable, Sendable {
    /// 5 分鐘內。這是 Claude Code 自己的寫入節流週期，所以這是可能的最新狀態。
    case live
    /// 5 到 60 分鐘。仍然可用，但 UI 必須顯示它有多舊。
    case aging(minutes: Int)
    /// 超過 60 分鐘。Claude Code 自己會在這個點丟棄它，我們沿用同一條線。
    case expired
}

/// 一次額度讀取的完整結果。
public struct UsageSnapshot: Equatable, Sendable {
    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?
    /// 每個模型各自的 7 天窗口，例如 seven_day_opus、seven_day_sonnet。
    public let perModel: [String: UsageWindow]
    public let freshness: Freshness
    public let fetchedAt: Date

    public init(fiveHour: UsageWindow?, sevenDay: UsageWindow?,
                perModel: [String: UsageWindow], freshness: Freshness, fetchedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.perModel = perModel
        self.freshness = freshness
        self.fetchedAt = fetchedAt
    }
}
