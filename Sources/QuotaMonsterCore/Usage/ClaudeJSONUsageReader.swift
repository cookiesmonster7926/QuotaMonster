import Foundation

/// 從 `~/.claude.json` 的未公開欄位 `cachedUsageUtilization` 讀取額度。
///
/// **零 token、零行程、零網路** —— 這是旁聽 Claude Code 自己維護的快取，
/// 不是去問它。任何 claude 行程取得用量後都會順手寫進這裡。
///
/// 規則不是我們發明的，是從 v2.1.274 二進位檔逆向出來的：
///   - 寫入端 `_0r`：硬性 5 分鐘節流（`azo = 300000`）
///   - 讀取端 `u6n`：`age > 60 分鐘` 視為過期回傳 null（`izo = 3600000`），
///     且 `accountUuid` 不符就清空
///
/// ⚠️ zod schema 只保證 five_hour / seven_day / seven_day_oauth_apps /
/// seven_day_opus / seven_day_sonnet / cinder_cove / extra_usage / limits，
/// 其餘欄位靠 `.passthrough()` 存活，**不可依賴**。所以這裡的解析對未知 key 必須寬容。
public struct ClaudeJSONUsageReader: Sendable {

    /// Claude Code 的寫入節流週期。這之內的讀數已經是可能的最新。
    public static let writeThrottle: TimeInterval = 300
    /// Claude Code 自己丟棄快取的年齡上限。
    public static let readCutoff: TimeInterval = 3600

    public init() {}

    /// - Parameters:
    ///   - expectedAccount: 傳 nil 表示不檢查帳號。不符時回傳 nil，
    ///     與 Claude Code 自己清空快取的行為一致。
    /// - Returns: 沒有快取、或帳號不符時回傳 nil。檔案不存在會丟錯。
    public func read(_ url: URL, now: Date, expectedAccount: UUID?) throws -> UsageSnapshot? {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = root["cachedUsageUtilization"] as? [String: Any]
        else { return nil }

        if let expected = expectedAccount {
            guard let raw = cache["accountUuid"] as? String,
                  UUID(uuidString: raw) == expected
            else { return nil }
        }

        guard let fetchedAtMs = (cache["fetchedAtMs"] as? NSNumber)?.doubleValue else { return nil }
        let fetchedAt = Date(timeIntervalSince1970: fetchedAtMs / 1000)
        let util = cache["utilization"] as? [String: Any] ?? [:]

        var perModel: [String: UsageWindow] = [:]
        for (key, value) in util where key.hasPrefix("seven_day_") {
            if let w = Self.window(from: value, now: now) { perModel[key] = w }
        }

        return UsageSnapshot(
            fiveHour: Self.window(from: util["five_hour"], now: now),
            sevenDay: Self.window(from: util["seven_day"], now: now),
            perModel: perModel,
            freshness: Self.freshness(fetchedAt: fetchedAt, now: now),
            fetchedAt: fetchedAt
        )
    }

    /// 讀分模型的 7 天用量。
    ///
    /// 它藏在 `utilization.limits` 陣列裡，**不是** `seven_day_opus` 那種鍵
    /// （實測那些鍵在這個帳號上全是 null，真正有值的是 limits）。實測三筆：
    /// ```
    /// kind=session       percent=30  scope=nil
    /// kind=weekly_all    percent=19  scope=nil
    /// kind=weekly_scoped percent=1   scope.model.display_name="Fable"
    /// ```
    /// 只有帶得出模型名稱的才算分模型 —— 其餘兩種是總量，面板已經有了。
    ///
    /// 這裡刻意**不檢查新鮮度**。過期的分模型數字仍然比沒有好，
    /// 但呼叫端一定要把 `fetchedAt` 一起呈現出來（見 `ScopedBreakdown` 的註解）。
    public func readScoped(_ url: URL, now: Date) throws -> ScopedBreakdown? {
        let data = try Data(contentsOf: url)
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let cache = root["cachedUsageUtilization"] as? [String: Any],
              let fetchedAtMs = (cache["fetchedAtMs"] as? NSNumber)?.doubleValue
        else { return nil }

        let util = cache["utilization"] as? [String: Any] ?? [:]
        let entries = util["limits"] as? [[String: Any]] ?? []

        let scoped: [ScopedUsage] = entries.compactMap { entry in
            guard let scope = entry["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let name = model["display_name"] as? String, !name.isEmpty,
                  let percent = (entry["percent"] as? NSNumber)?.doubleValue,
                  percent.isFinite, percent >= 0
            else { return nil }

            var resetsAt: Date?
            if let iso = entry["resets_at"] as? String {
                resetsAt = try? ResetTimestamp.parse(.iso8601(iso))
            }
            return ScopedUsage(modelName: name,
                               percent: Int(min(percent, 1000).rounded()),
                               resetsAt: resetsAt,
                               isActive: (entry["is_active"] as? NSNumber)?.boolValue ?? false)
        }

        return ScopedBreakdown(scoped: scoped,
                               fetchedAt: Date(timeIntervalSince1970: fetchedAtMs / 1000))
    }

    static func freshness(fetchedAt: Date, now: Date) -> Freshness {
        let age = now.timeIntervalSince(fetchedAt)
        if age <= writeThrottle { return .live }
        if age > readCutoff { return .expired }
        return .aging(minutes: Int(age / 60))
    }

    /// 一個窗口可能是 null（該方案沒有這個窗口），那與 0% 是完全不同的意思。
    ///
    /// ⚠️ **`now` 不是裝飾。** 這支以前不檢查 `resets_at` 過期，而 statusline 那支會檢查 ——
    /// 同一個概念兩份定義，後果見 `WindowExpiry` 的檔頭（歷史檔裡有一天的資料是假的）。
    static func window(from any: Any?, now: Date) -> UsageWindow? {
        guard let dict = any as? [String: Any],
              let percent = (dict["utilization"] as? NSNumber)?.intValue
        else { return nil }

        var resetsAt: Date?
        if let iso = dict["resets_at"] as? String {
            resetsAt = try? ResetTimestamp.parse(.iso8601(iso))
        }
        guard WindowExpiry.accepts(resetsAt: resetsAt, now: now) else { return nil }
        return UsageWindow(percent: percent, resetsAt: resetsAt)
    }
}
