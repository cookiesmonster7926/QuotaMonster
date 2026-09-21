import Foundation

/// 一筆額度讀數是從哪裡來的。UI 要據此說明它為什麼新、或為什麼舊。
public enum UsageSource: Equatable, Sendable {
    /// `~/.claude.json` 的 `cachedUsageUtilization`。Claude Code 自己維護，
    /// 寫入端有硬性 5 分鐘節流，而且實測可以整整 16 小時不更新。
    case claudeJSON
    /// statusline tee 的快取。跟著 API 回應走，秒級。
    case statusLine
}

/// 選中的那一筆，連同它的出處。
public struct SelectedUsage: Equatable, Sendable {
    public let snapshot: UsageSnapshot
    public let source: UsageSource

    public init(snapshot: UsageSnapshot, source: UsageSource) {
        self.snapshot = snapshot
        self.source = source
    }
}

/// 在兩個額度來源之間挑一個。
///
/// **整筆快照只能有一個來源，不做欄位層級的合併。** 這是刻意的：
/// 兩邊的 `five_hour` 可能屬於**不同的窗口**（一邊已經重置、一邊還沒），
/// 把它們拼進同一列會產生一組互相矛盾、但看起來完全正常的數字。
/// 少一個數字（顯示「—」）是誠實的，湊一個數字不是。
///
/// 代價：選了 statusline 就沒有 per-model 窗口（那個來源根本不提供
/// `seven_day_opus` / `seven_day_sonnet`，二進位 `U$o` 只組三個窗口）。
/// 實測這個帳號的 per-model 窗口本來就全是 null，所以沒有實際損失。
public enum UsageSourceSelector {

    /// - Parameters:
    ///   - statusLine: 快取目錄裡的所有 payload。額度是**帳號層級**的，
    ///     所以哪個 session 寫的都一樣，只取最新的那一份。
    /// - Returns: 兩邊都沒有可用讀數時回 nil。**絕不回一個全 0 的快照** ——
    ///   0% 和「不知道」在視覺上必須不同。
    public static func pick(claudeJSON: UsageSnapshot?,
                            statusLine: [StatusLinePayload],
                            now: Date) -> SelectedUsage? {
        let newest = statusLine
            .filter(\.hasAnyWindow)                 // 只有 context 壓力的 payload 不算額度來源
            .max { $0.capturedAt < $1.capturedAt }

        switch (newest, claudeJSON) {
        case (nil, nil):
            return nil
        case (let p?, nil):
            return SelectedUsage(snapshot: snapshot(from: p, now: now), source: .statusLine)
        case (nil, let c?):
            return SelectedUsage(snapshot: c, source: .claudeJSON)
        case (let p?, let c?):
            return p.capturedAt > c.fetchedAt
                ? SelectedUsage(snapshot: snapshot(from: p, now: now), source: .statusLine)
                : SelectedUsage(snapshot: c, source: .claudeJSON)
        }
    }

    /// 新鮮度沿用 `ClaudeJSONUsageReader` 的 300 秒 / 3600 秒門檻，不發明第四種狀態。
    ///
    /// ### ⚠️ 這裡原本有一段被實測推翻的推論
    /// 原註解寫：「這對 statusline 來說是保守的 —— 這個來源是**事件驅動**的，
    /// 會讓額度數字變大的活動，本身就是會觸發重新寫入的活動。」
    /// **那個方向不成立。** 〔實測，讀 Claude Code 2.1.277 的二進位〕payload 的
    /// `rate_limits` 不是每次渲染去問來的，是從行程記憶體的 `Eu.rawUtilization` 重發：
    /// ```
    /// function k2(){return xPr(Eu.rawUtilization)}
    /// function u0t(e,n){let r=n/1000;return IZ(e)&&e.resets_at>r&&e.resets_at<r+31536000}
    /// ```
    /// 而那個欄位**只有 API 回應才會更新**。渲染由 UI 事件觸發，可以完全不帶新的回應 ——
    /// 於是檔案很新、數字很舊，我們卻拿檔案 mtime 當那組數字的年紀。
    ///
    /// ### 可以偵測的訊號：有 7d、沒有 5h
    /// `u0t` 是**逐窗口**判斷的。五小時窗口最多活五小時，所以它一旦從 payload 裡消失，
    /// 就證明 `rawUtilization` 至少從某個五小時窗口結束之前就沒有更新過 ——
    /// 而七天窗口因為還沒到期，會把那個同樣老的數字原封不動帶出來。
    ///
    /// 這種 payload 的年紀**沒有可計算的上界**，所以不可以宣稱它是 live。
    /// 降成 `.expired` 是刻意重用既有狀態：全 Sources 有 22 處在問 `== .expired`
    /// （不上色、不預測、不發通知、降調），新增一個 case 會讓那 22 處**靜靜地**
    /// 把它當成可信 —— 那正是這個 bug 本來的樣子。
    ///
    /// ⚠️〔推論，未實測〕天生沒有五小時窗口的帳號會被這條規則永久降級。
    /// 我沒有見過這種帳號，也無法在這台機器上造出來。
    static func snapshot(from p: StatusLinePayload, now: Date) -> UsageSnapshot {
        let byFile = ClaudeJSONUsageReader.freshness(fetchedAt: p.capturedAt, now: now)
        let ageIsUnbounded = p.fiveHour == nil && p.sevenDay != nil
        return UsageSnapshot(
            fiveHour: p.fiveHour,
            sevenDay: p.sevenDay,
            perModel: [:],
            freshness: ageIsUnbounded ? .expired : byFile,
            fetchedAt: p.capturedAt)
    }
}
