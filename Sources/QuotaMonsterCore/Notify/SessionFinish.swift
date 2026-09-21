import Foundation

/// 「這個 session 剛剛講完了一輪。」
///
/// 偵測層與顯示層之間**只有這一個型別**：偵測層看不到顏色，顯示層看不到 transcript。
public struct SessionFinish: Equatable, Sendable {
    public let sessionId: String
    /// 那一則 `end_turn` 行自己的 timestamp。見 `TurnEnd.finishedAt`。
    public let finishedAt: Date
    /// 這一輪跑了多久。
    ///
    /// ⚠️ **nil 是「算不出來」，不是 0。**〔實測〕命中率 84.1%（111/132）——
    /// 大約六分之一的完成不會有秒數，因為「安靜→又動起來」那一拍的 64KB 尾端裡
    /// 沒有那一輪的起點。面板在 nil 時**整格不畫**，不可以畫成「跑了 0m 00s」。
    public let ranFor: TimeInterval?

    public init(sessionId: String, finishedAt: Date, ranFor: TimeInterval?) {
        self.sessionId = sessionId
        self.finishedAt = finishedAt
        self.ranFor = ranFor
    }
}

/// 面板那一列的三個欄位怎麼寫。純函式，時間一律注入。
public enum FinishCaption {

    /// 標記活多久。與 `FinishGlow.goneSeconds` 是同一個數 —— 面板與選單列
    /// 對「這件事還算新聞嗎」不可以有兩個答案。
    public static let lifetime: TimeInterval = FinishGlow.goneSeconds

    /// 「剛完成」／「N 分前完成」。
    public static func label(finishedAt: Date, now: Date) -> String {
        let elapsed = max(0, now.timeIntervalSince(finishedAt))
        if elapsed < 90 { return "剛完成" }
        return "\(Int((elapsed / 60).rounded())) 分前完成"
    }

    /// 「跑了 12m 04s」。**nil 進 nil 出。**
    ///
    /// 格式抄 `AlertView.elapsed`（有小時分支）。
    /// ⚠️ 不要抄 `TraceAlerts.elapsed` —— 它沒有小時分支，3664 秒會印成 `61m 04s`。
    public static func ranFor(_ seconds: TimeInterval?) -> String? {
        guard let seconds, seconds >= 0 else { return nil }
        let s = Int(seconds)
        if s < 60 { return "跑了 \(s)s" }
        if s < 3600 { return "跑了 \(s / 60)m \(String(format: "%02d", s % 60))s" }
        return "跑了 \(s / 3600)h \(String(format: "%02d", (s % 3600) / 60))m"
    }

    /// 鮮度線還剩多長 —— 1 → 0，10 分鐘內排空。
    public static func drainFraction(finishedAt: Date, now: Date) -> Double {
        let elapsed = max(0, now.timeIntervalSince(finishedAt))
        return max(0, min(1, 1 - elapsed / lifetime))
    }

    /// 收掉已經不算數的標記。
    ///
    /// ⚠️ **`wrote` 來自 transcript 的 mtime，不是 session 註冊表。**
    /// 這個簽章刻意**不接受 `[LiveSession]`** —— `isWorking` 在 `.busy`/`.shell`
    /// 就是 true，而計畫書 Stage 8 自己量過 `status` 是黏著的（「回合結束後七分鐘
    /// 一直回報 shell」「講完 29 分鐘仍報 busy」）。拿它當「又動起來了」的證據，
    /// 標記會在產生後的第一拍就被清掉，**丁香紫一次都不會亮，而且所有單元測試
    /// 都會綠**（因為測試餵的是手捏的 LiveSession）。
    public static func prune(_ finishes: [String: SessionFinish],
                             wrote: Set<String>, now: Date) -> [String: SessionFinish] {
        finishes.filter { id, finish in
            // 又動起來了 —— 正面證據，當場清。
            !wrote.contains(id)
                && now.timeIntervalSince(finish.finishedAt) < lifetime
        }
    }
}
