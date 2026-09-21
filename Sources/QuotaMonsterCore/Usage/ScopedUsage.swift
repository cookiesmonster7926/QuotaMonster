import Foundation

/// 某一個模型自己的 7 天用量。
///
/// 來源是 `~/.claude.json` 的 `cachedUsageUtilization.utilization.limits` 陣列，
/// 不是 `seven_day_opus` 那種鍵（實測那些鍵在這個帳號上全是 null）。
public struct ScopedUsage: Equatable, Sendable {
    /// Claude Code 自己給的顯示名稱，例如 `"Fable"`。直接用，不要自己翻譯或縮寫。
    public let modelName: String
    /// 0–100。
    public let percent: Int
    public let resetsAt: Date?
    /// 這個窗口是不是「目前正在計費」的那一個。
    public let isActive: Bool

    public init(modelName: String, percent: Int, resetsAt: Date?, isActive: Bool) {
        self.modelName = modelName
        self.percent = percent
        self.resetsAt = resetsAt
        self.isActive = isActive
    }
}

/// `limits` 陣列解析出來的分模型用量，**連同它自己的擷取時間**。
///
/// ⚠️ 擷取時間必須跟著資料走，不可以共用面板上那個即時的新鮮度。
/// 這份資料只有 `~/.claude.json` 有（statusLine payload 完全沒有這個欄位），
/// 而那份快取實測可以整整 16 小時不更新。旁邊的總量是秒級即時的，
/// 兩者放在同一排卻不標年齡，使用者一定會以為它們一樣新。
public struct ScopedBreakdown: Equatable, Sendable {
    public let scoped: [ScopedUsage]
    public let fetchedAt: Date

    public init(scoped: [ScopedUsage], fetchedAt: Date) {
        self.scoped = scoped
        self.fetchedAt = fetchedAt
    }

    public func age(now: Date) -> TimeInterval { now.timeIntervalSince(fetchedAt) }
}
