import Foundation

/// 把兩種格式的 `resets_at` 統一成 `Date`。
///
/// 為什麼需要這個型別：
/// - `~/.claude.json` 的 `resets_at` 是 **ISO-8601 字串**（帶小數秒與時區位移）
/// - statusLine payload 的 `resets_at` 是 **Unix epoch 秒**
///
/// 兩者混用不會報錯，只會產生差了幾十年的倒數。統一必須發生在 parser 邊界。
public enum ResetTimestamp {

    /// 來源格式。呼叫端必須明確指出拿到的是哪一種，不做猜測。
    public enum Raw: Sendable, Equatable {
        case iso8601(String)
        case epochSeconds(TimeInterval)
    }

    public enum ParseError: Error, CustomStringConvertible {
        case unparseable(String)
        public var description: String {
            switch self {
            case .unparseable(let s): return "無法解析為時間：\(s)"
            }
        }
    }

    public static func parse(_ raw: Raw) throws -> Date {
        switch raw {
        case .epochSeconds(let s):
            return Date(timeIntervalSince1970: s)
        case .iso8601(let string):
            if let d = makeFormatter(fractional: true).date(from: string) { return d }
            if let d = makeFormatter(fractional: false).date(from: string) { return d }
            throw ParseError.unparseable(string)
        }
    }

    /// 距離重置還有多少秒。已經過去就回傳 nil —— 呼叫端必須顯式處理過期，
    /// 不可以拿到一個負數然後不小心當成倒數顯示。
    public static func remaining(until reset: Date, now: Date) -> TimeInterval? {
        let delta = reset.timeIntervalSince(now)
        return delta > 0 ? delta : nil
    }

    // 刻意每次呼叫才建立：ISO8601DateFormatter 不是 Sendable，
    // 而 Swift 6 的嚴格併發不允許把它放成 static。這個函式每次讀取用量
    // 才呼叫一次，建立成本無所謂，換來的是真正的執行緒安全。
    private static func makeFormatter(fractional: Bool) -> ISO8601DateFormatter {
        let f = ISO8601DateFormatter()
        f.formatOptions = fractional
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return f
    }
}
