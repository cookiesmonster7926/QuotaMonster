import Foundation

/// 額度分級的兩個邊界。**這是風險容忍度，所以它是口味。**
///
/// 配色（藍 → 綠 → 紅）是使用者 2026-09-18 指定的，但 0.20 / 0.50 這兩個數
/// 沒有任何量測撐著 —— 它們回答的是「剩多少開始緊張」，而那本來就因人而異。
///
/// ⚠️ **但它不是無害的口味，因為它有一個非顯而易見的第二個消費者：**
/// T3 的額度通知是在分級**變了的那一刻**發的（`NotificationEngine.observeQuota`）。
/// 把 critical 調成 0.05，紅色警告也跟著晚到剩 5% 才響。
/// 所以介面上那一行說明必須寫出這件事 —— 一個只說一半的標籤比沒有這個設定更糟。
public struct QuotaThresholds: Equatable, Sendable {

    /// 剩下不到這個比例就是 critical（紅）。
    public let critical: Double
    /// 剩下不超過這個比例就是 tight（綠）。
    public let tight: Double

    /// ⚠️ **這是唯一的字面量定義處。** 使用者的值是覆寫，不是第二份定義。
    public static let standard = QuotaThresholds(critical: 0.20, tight: 0.50)

    /// ⚠️ `init` 會夾限並保證 `critical < tight`。
    /// 一組互相矛盾的門檻（critical ≥ tight）會讓 tight 那一格**永遠不可達**，
    /// 而畫面上只會看到「顏色從藍直接跳到紅」—— 沒有人會把那個現象
    /// 歸因到設定。與其留一個表示不出來的狀態，不如讓它在型別上不存在。
    public init(critical: Double, tight: Double) {
        let c = min(max(critical, 0.01), 0.95)
        let t = min(max(tight, 0.02), 0.99)
        self.critical = min(c, t - 0.01)
        self.tight = max(t, c + 0.01)
    }
}
