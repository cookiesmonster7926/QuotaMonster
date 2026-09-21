import Foundation

/// 選單列那一點丁香紫現在該多濃。
///
/// **三段離散，不是連續濃度。** 使用者拍板的 `finished-mockups/glyph-signal.html`
/// 只給三格（眨一次 → 滿色到 180 秒 → 退色到 600 秒 → 沒了），它的 JS 也只有
/// 兩個色值。⚠️ 理由就是「mockup 是使用者選的那一份」——
/// 連續濃度在機制上完全做得到（600 秒裡重畫十幾次而已），
/// 把品味寫成機制論就是在註解裡把偏好偽裝成量測。
public enum FinishGlow: Equatable, Sendable {
    case none
    /// 滿色。
    case fresh
    /// 退色版。⚠️ 混向墨色，**不是**降不透明度 ——
    /// alpha 0.45 已經被 `freshness == .expired` 佔走了。
    case faded

    public static let fullSeconds: TimeInterval = 180
    public static let goneSeconds: TimeInterval = 600

    /// 這一輪至少要跑多久，選單列才值得亮。
    ///
    /// 使用者 2026-09-19 選的 **600 秒**。把整條偵測鏈在全語料上模擬跑過
    /// 〔實測，模擬〕：180s → 8.12 則／活躍日、最忙一天 26 次；
    /// **600s → 5.17／19**；1800s → 3.00／11。
    /// 選 600 的理由是它與 `goneSeconds` 是同一個數 ——
    /// 「亮的時間不超過跑的時間」是一個講得出口的門檻。
    ///
    /// ⚠️ 計畫書寫的「典型 1.6 則／天」是**九道閘**之後的數字，而其中兩道
    /// （人不在、那個 app 在最前面）transcript 裡沒有任何欄位可以重建，
    /// 一道（Esc）實測擋不到東西。**不要在任何地方宣稱九道閘。**
    public static let minimumInterestingRun: TimeInterval = 600

    public static func at(finishedAt: Date?, now: Date) -> FinishGlow {
        guard let finishedAt else { return .none }
        let elapsed = now.timeIntervalSince(finishedAt)
        // ⚠️ 負的經過時間（時鐘往回跳）算**剛完成**，不算過期。
        // 猜錯的方向要選「訊號還在」而不是「訊號憑空消失」。
        if elapsed < fullSeconds { return .fresh }
        if elapsed < goneSeconds { return .faded }
        return .none
    }

    /// 選單列取哪一個 —— **最新的那一個**。
    ///
    /// ⚠️ 不是字典序、不是第一個。`latestPhase` 那一課的學費已經付過了。
    public static func menuBar(_ finishes: [SessionFinish],
                               minimumRun: TimeInterval = minimumInterestingRun,
                               now: Date) -> FinishGlow {
        // **先取最新的，再看它夠不夠久** —— 不是先濾掉不夠久的再取最新。
        // 選單列講的是「剛剛那件事」，不是「最近一件夠格的事」；
        // 反過來寫的話，一個剛跑完 10 秒的小事會讓半小時前那件大事重新亮起來。
        guard let latest = finishes.max(by: { $0.finishedAt < $1.finishedAt }) else { return .none }
        // ⚠️ `ranFor == nil` 不亮。〔實測〕約六分之一的完成算不出秒數，
        // 而亮起來那一下是在主張「這一輪跑很久」—— 沒有證據就不要主張。
        guard let ranFor = latest.ranFor, ranFor >= minimumRun else { return .none }
        return at(finishedAt: latest.finishedAt, now: now)
    }
}

/// 「眨一次眼」什麼時候該播。
///
/// 只在 `.none → .fresh` 那一拍回 true，而且**要先有過一次觀測** ——
/// app 剛啟動就看到一個 `.fresh` 不算我們見證的轉換。
/// 形狀照抄 `NotificationEngine` 的 `seeded`。
public struct FinishBlinkController: Equatable, Sendable {
    private var last: FinishGlow?

    public init() {}

    public mutating func update(glow: FinishGlow) -> Bool {
        defer { last = glow }
        // 第一次觀測不眨。少了它，make_app.sh 每次重啟都會對著一個
        // 十分鐘前的完成眨一次眼。
        guard let last else { return false }
        // `.faded → .fresh` 也要眨 —— 舊的還在退色時來了一個新的完成。
        return glow == .fresh && last != .fresh
    }
}
