import Foundation

/// Claude Code 餵給 statusLine 指令的那一份 JSON，解析後的樣子。
///
/// 這份 payload 是**唯一**活的額度來源。`~/.claude.json` 的 `cachedUsageUtilization`
/// 實測可以整整 16 小時不更新，而且過期的窗口還留在裡面；statusLine 的 `rate_limits`
/// 則是跟著 API 回應走，而且 Claude Code 會把已重置的窗口直接拿掉
/// （二進位 `MSn` 過濾），所以它只會是「活的，或沒有」。
///
/// 也是唯一拿得到 `context_window`（每個 session 的 context 壓力）的地方。
///
/// ⚠️ **payload 裡沒有任何帳號識別。** `accountUuid` 那條防線在這個來源不存在
/// （二進位裡 `accountEpoch` 有被追蹤，但從不序列化）。不要假裝擋得住換帳號。
public struct StatusLinePayload: Equatable, Sendable {

    /// 一定會有，除非未來版本改了鍵名。認不出來時仍然收下這筆 ——
    /// 額度是帳號層級的資料，本來就與 session 無關。
    public let sessionId: String?

    /// 擷取時間 = **檔案 mtime**。payload 本身沒有任何時間戳。
    public let capturedAt: Date

    public let modelDisplayName: String?
    public let cwd: String?

    /// 0–100 的整數，可能為 nil（session 還沒發出第一個 API 呼叫，
    /// 或剛 `/compact` 完）。nil 與 0% 是兩回事。
    public let contextUsedPercent: Int?
    /// 200000，或延伸脈絡模型的 1000000。
    public let contextWindowSize: Int?
    /// `input + cache_creation + cache_read`，要比整數百分比更細的解析度時用這個。
    public let totalInputTokens: Int?

    public let fiveHour: UsageWindow?
    public let sevenDay: UsageWindow?
    /// 只有走 Claude gateway 的帳號才會有。百分比可以超過 100。
    public let spendLimit: UsageWindow?

    public init(sessionId: String?, capturedAt: Date,
                modelDisplayName: String? = nil, cwd: String? = nil,
                contextUsedPercent: Int? = nil, contextWindowSize: Int? = nil,
                totalInputTokens: Int? = nil,
                fiveHour: UsageWindow? = nil, sevenDay: UsageWindow? = nil,
                spendLimit: UsageWindow? = nil) {
        self.sessionId = sessionId
        self.capturedAt = capturedAt
        self.modelDisplayName = modelDisplayName
        self.cwd = cwd
        self.contextUsedPercent = contextUsedPercent
        self.contextWindowSize = contextWindowSize
        self.totalInputTokens = totalInputTokens
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.spendLimit = spendLimit
    }

    /// 這筆 payload 能不能當成**額度來源**。
    ///
    /// ⚠️ 刻意**不算** `spendLimit`。`UsageSnapshot` 只帶 five_hour 與 seven_day，
    /// 所以一筆只有 spend_limit 的 payload 就算勝出，換算出來的快照三個數字全是「—」——
    /// 那比顯示一個 16 小時前的舊數字更糟。`spendLimit` 仍然解析並保留在這個型別上，
    /// 只是還沒有人消費它。
    public var hasAnyWindow: Bool {
        fiveHour != nil || sevenDay != nil
    }
}
