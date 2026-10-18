import Foundation

/// 面板一列 session 的 header 右側要畫哪一種狀態：剛完成的勾、BUSY、IDLE。
///
/// ### 為什麼在 Core
/// 這個判斷原本寫在 `SessionRow`（App 層）裡，散成三處各問一次 `session.isWorking`
/// 與 `finish != nil`：圓點、徽章文字、徽章顏色。App 層的測試碰不到判斷（規矩 4），
/// 所以「完成標記壓過註冊表」這件事只有一句註解守著。
/// 同一類漂移剛發生過：面板的高度估算與 `SessionRow` 各數一次細節行數、數法不同。
///
/// ⚠️ **完成標記壓過註冊表的 status。** 註冊表是黏著的 ——〔實測，見規矩 21〕
/// 回合結束後七分鐘一直回報 shell、講完 29 分鐘仍報 busy。那段時間要畫的是勾。
public enum SessionRowStatus: Equatable, Sendable {
    /// 剛講完一輪：勾＋「N 分前完成」＋「跑了 …」。
    case finished(SessionFinish)
    /// 註冊表說 busy 或 shell（`LiveSession.isWorking`）。
    case busy
    /// 其餘。
    ///
    /// ⚠️ 包括 `.waiting` —— 這是**搬移前的行為**，不是設計過的答案。
    /// popover 裡 `PanelView.listedSessions` 會先濾掉在等你的 session（它們在上面另一區），
    /// 所以那裡的 `SessionRow` 拿不到它；`--render-panel` 的 rows 圖用的是全部 session，
    /// 在那張圖裡它畫成 IDLE。
    case idle

    public init(session: LiveSession, finish: SessionFinish?) {
        if let finish {
            self = .finished(finish)
        } else {
            self = session.isWorking ? .busy : .idle
        }
    }

    /// 徽章那三四個字。勾的那一格沒有徽章（它畫的是 `FinishCaption`）。
    public var badge: String? {
        switch self {
        case .finished: return nil
        case .busy:     return "BUSY"
        case .idle:     return "IDLE"
        }
    }
}

/// header 右邊那個「3m」：這個 session 開了多久。
public enum SessionElapsed {

    /// 秒 → 分 → 時，無條件捨去。
    ///
    /// ⚠️ 規矩 10：`Int(Double)` 超出範圍或 NaN 會 trap 掉整個行程，而 `startedAt`
    /// 來自磁碟上的 JSON。搬移前寫的是 `Int(now.timeIntervalSince(...))`；
    /// 存活判定（pid＋啟動時間 300 秒容差，規矩 6）在實際路徑上擋掉了荒謬的值，
    /// 但純函式不可以依賴呼叫端替它擋 —— 換不成整數就畫「—」。
    /// 可以表示的範圍內，結果與搬移前逐字相同（`rounded(.towardZero)` 就是 `Int(_:)` 的截斷）。
    public static func label(startedAt: Date, now: Date) -> String {
        guard let s = Int(exactly: now.timeIntervalSince(startedAt).rounded(.towardZero))
        else { return "—" }
        return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m" : "\(s / 3600)h"
    }
}
