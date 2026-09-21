import Foundation

/// 手動靜音的兩個選項。
///
/// ⚠️ **這裡不會有第三個選項叫「安靜時段」。** macOS Focus 已經做了那件事，
/// 而第二個排程器正是「明明開了勿擾卻在半夜三點響」的成因 ——
/// 兩個排程器一定會在某個邊界上意見不同，而使用者只會記得是我們吵到他。
///
/// 而且 Focus 狀態實測**讀不到**（`~/Library/DoNotDisturb/DB/Assertions.json`
/// 受 TCC 保護，沒有公開 API），所以這兩顆按鈕是使用者唯一的防線。
public enum MutePolicy {

    /// 「明早」是幾點。**這是預設值，唯一的字面量定義處。**
    ///
    /// 使用者可以在偏好裡覆寫（`Preferences.morningHour`）——
    /// ⚠️ 覆寫**不是第二份定義**：這個常數仍然是字面量唯一活著的地方，
    /// 注入點寫成看得見的 `?? MutePolicy.morningHour`。
    ///
    /// 它能當偏好的決定性理由是**它自帶回饋**：面板那一行本來就一直寫著
    /// 「靜音至 HH:MM」，所以設錯了當場看得出來。
    public static let morningHour = 8

    /// 靜音按鈕按下去的下一個狀態：**關 → 1 小時 → 到明早 → 關**。
    ///
    /// ⚠️ 刻意**不用** SwiftUI 的 `Menu`，有兩個理由，分量不同：
    ///
    /// **已證實：** `Menu` 在離屏渲染下畫成一個紅色禁止符號 ——
    /// `--render-panel` 因此對這個角落說不出真話，而那是這個專案唯一的視覺檢查手段。
    ///
    /// **未證實但足以避開：** 面板是 `.transient` 的 `NSPopover`，而 `Menu` 會開一個
    /// 獨立視窗。`.transient` 的文件說「使用者與 popover 以外的介面元素互動時自動關閉」，
    /// 所以那一下很可能讓面板自己關掉、選項根本選不到。**我沒有實機驗證這一條**，
    /// 只是循環鍵本來就比較好，不值得為了保留 Menu 去賭它。
    ///
    /// 循環鍵沒有第二個視窗，而且「現在是哪一段」一直看得見。
    ///
    /// 順序是固定的**語意**順序，不是長度排序：清晨七點半按下去，「到明早」
    /// 只有三十分鐘，比「1 小時」還短，但它仍然排在後面。
    ///
    /// - Parameter current: 目前的 `mutedUntil`。已經過期的視同沒有靜音。
    public static func next(from current: Date?, now: Date,
                            calendar: Calendar = .current,
                            morningHour: Int = MutePolicy.morningHour) -> Date? {
        let morning = tomorrowMorning(from: now, calendar: calendar,
                                      morningHour: morningHour)
        guard let current, current > now else { return oneHour(from: now) }
        // 已經在「到明早」那一段就關掉；否則往前進一格。
        return current == morning ? nil : morning
    }

    public static func oneHour(from now: Date) -> Date {
        now.addingTimeInterval(3600)
    }

    /// 下一個早上八點。
    ///
    /// ⚠️ **半夜三點按下去的「明早」是五小時後，不是明天。**
    /// 天真的 `+1 day` 會讓使用者整個白天都是靜音的 —— 而他按那顆按鈕的時候
    /// 想的是「讓我睡到天亮」，不是「讓我聾一整天」。
    public static func tomorrowMorning(from now: Date,
                                       calendar: Calendar = .current,
                                       morningHour: Int = MutePolicy.morningHour) -> Date {
        // 直接從日期元件組出「今天的早上八點」。
        // 刻意不用 `date(bySettingHour:…direction:)` —— 它的 matchingPolicy 與
        // direction 組合在跨日邊界上的語意不直觀，而這個函式唯一的風險就是邊界。
        var comps = calendar.dateComponents([.year, .month, .day], from: now)
        comps.hour = morningHour
        comps.minute = 0
        comps.second = 0
        guard let todayMorning = calendar.date(from: comps) else {
            return now.addingTimeInterval(3600)
        }

        // 還沒到今天的八點（例如半夜三點按的）→ 就是今天的八點，五小時後。
        if todayMorning > now { return todayMorning }
        return calendar.date(byAdding: .day, value: 1, to: todayMorning)
            ?? now.addingTimeInterval(3600)
    }
}
