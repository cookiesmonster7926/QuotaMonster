import Foundation

/// 「現在值得為一件事播一聲嗎？」
///
/// 這是 Core 裡的**資料**，不是 App 層那支探測器。三個訊號原樣帶進來，
/// 不是一顆已經算好的 Bool —— 算好的話，那個判斷就留在 App 層，
/// 而 App 層沒有測試（`NotificationPresenter` 的檔頭自己寫了這條規矩）。
///
/// ⚠️ **它刻意不回答「使用者看得到浮窗嗎」。** 那是另一個問題，
/// 今天長在 `ScreenPresence.canSeeAPanel`，有兩個已經實機驗證過的消費者。
/// 兩個問題的唯一差別正是 `idleSeconds` 讀不到時要倒向哪一邊：
///
/// - `canSeeAPanel` 讀不到 → **當成人在**（開窗，不發 osascript）。
///   猜錯的方向選「不會多打擾一次」的那一邊。
/// - `worthSounding` 讀不到 → **當成人不在**（不出聲）。
///   同一條原則、相反的結論，因為這裡多猜一次的代價就是多響一聲。
///
/// 把兩個問題塞進同一個型別，等於留一個邀請下一個人「順手統一」的接縫，
/// 而統一的那一刻就會有一邊的 nil 倒錯方向。
public struct Presence: Equatable, Sendable {

    /// 螢幕鎖定或快速使用者切換。
    public let screenLocked: Bool
    /// 顯示器沒有在亮。
    public let screensAsleep: Bool
    /// 距離上一次碰鍵盤滑鼠幾秒。
    ///
    /// ⚠️ **nil 不是 0。** IOHIDSystem 沒回話與「人剛剛才動過」是完全不同的兩件事，
    /// 而 `?? 0` 會把前者變成後者 —— 那正是「不存在不等於那個狀態不成立」。
    public let idleSeconds: TimeInterval?

    /// 超過這個閒置秒數就當作人不在螢幕前。
    ///
    /// **這是全 app 唯一的定義**，`ScreenPresence.idleThreshold` 是它的別名。
    /// 使用者 2026-09-19 選的：T2 與 T1 用同一套「人在」的語彙，
    /// 不要為了保住「我去泡咖啡等它跑完」那個情境而開第二個門檻。
    public static let idleThreshold: TimeInterval = 300

    /// ⚠️ 三個參數都**不給預設值**。呼叫點實測只有七個（兩個 production、
    /// 五個單行測試 helper），而不給預設值買到的是：漏接線時是一個編譯錯誤，
    /// 不是一個安靜的行為選擇。
    public init(screenLocked: Bool, screensAsleep: Bool, idleSeconds: TimeInterval?) {
        self.screenLocked = screenLocked
        self.screensAsleep = screensAsleep
        self.idleSeconds = idleSeconds
    }

    /// 值得為它出聲嗎。
    ///
    /// 三個訊號是 **OR**，不是加權、也不是只看閒置：鎖著的機器閒置 0 秒
    /// （你剛剛才按下 Cmd-Ctrl-Q）一樣是沒有人在看。
    public var worthSounding: Bool {
        if screenLocked || screensAsleep { return false }
        // ⚠️ **讀不到就是沒有正面證據。** 這裡刻意與 `ScreenPresence` 那個
        // `(hidIdleSeconds ?? 0)` 反向 —— 同一條原則（猜錯要選不會多打擾的
        // 那一邊），相反的結論，因為這裡多猜一次的代價就是多響一聲。
        guard let idleSeconds else { return false }
        // `<=` 而不是 `<`：`ScreenPresence.isIdle` 是 `> idleThreshold`，
        // 兩者要逐字互補，否則兩條通道對「人在」的定義會差一秒。
        return idleSeconds <= Self.idleThreshold
    }
}
