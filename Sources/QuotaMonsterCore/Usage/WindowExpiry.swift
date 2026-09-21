import Foundation

/// 一個窗口的 `resets_at` 什麼時候讓那個讀數作廢。
///
/// ### 為什麼這件事要有自己的型別
/// 這條規則以前有**兩份，而且不一樣**：
/// - `StatusLineCacheReader.window` 會擋（`reset <= now` 就整個丟掉）
/// - `ClaudeJSONUsageReader.window` **完全不擋**
///
/// 後果是實測到的，不是假想的：〔實測 2026-09-21〕這台機器的 `~/.claude.json`
/// 的 `fetchedAtMs` 從 2026-09-17 23:43 凍住四天，兩個窗口的 `resets_at` 都早就過了，
/// 那個來源卻一直吐同一組 `30 / 19` —— 而 `usage-history.jsonl` 的 09-20 15:25
/// 那**唯一一筆**取樣點逐字等於那個凍住的檔案。四天的歷史裡有一天是假的。
///
/// 規矩 2：門檻只能有一個定義。這裡就是那個定義。
public enum WindowExpiry {

    /// `resets_at` 合理的上界。沿用 Claude Code 二進位 `u0t` 的那條規則：
    /// `resets_at > now && resets_at < now + 31536000`（一年）。
    ///
    /// ⚠️ 上界不是龜毛：壞掉的時間戳（例如毫秒被當成秒）會變成一個
    /// **永遠不會過期**的窗口，於是一個死掉的數字永遠贏過活的那個。
    public static let horizon: TimeInterval = 31_536_000

    /// 這個重置時間讓窗口還算數嗎。
    ///
    /// - Parameter resetsAt: `nil` 代表**這個來源沒有給重置時間**，
    ///   那是「不知道」不是「過期」—— 無從判斷就留著（規矩：nil 不是零，也不是否定）。
    public static func accepts(resetsAt: Date?, now: Date) -> Bool {
        guard let resetsAt else { return true }
        if resetsAt <= now { return false }                       // 已經重置：描述的是不存在的窗口
        if resetsAt.timeIntervalSince(now) > horizon { return false }  // 壞掉的時間戳
        return true
    }
}
