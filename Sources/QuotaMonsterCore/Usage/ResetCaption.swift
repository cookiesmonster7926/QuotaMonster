import Foundation

/// 「還有多久重置」那一行的措辭。**全 repo 只有這一份。**
///
/// ### 為什麼它必須在 Core、而且只有一份
/// 〔code review 2026-09-23〕簡易版面剛做出來時自己寫了第二份，
/// 而兩份在**三個方向**同時漂開了：
///
/// 1. **字彙**：一份回「已重置」，另一份回「重置時間已過」——
///    同一個事實在兩頁兩套語彙（規矩 43 為此付過一次代價）。
/// 2. **契約**：`OutlookCaption.fiveHour` 的檔頭把 `resetText` 的集合寫死成
///    （`剩 1h 44m` / `已重置` / `" "`），而它的 `.exhausted` 分支
///    `guard resetText.hasPrefix("剩 ")` 就建在那個集合上。
///    餵一個集合外的字串進去，「N 後恢復」會**安靜地消失**。
/// 3. **時鐘**：一份用 `Date()`、一份用 `store.lastRefresh`，
///    同一個倒數在兩頁差一分鐘（每分鐘約有 3 秒落在那個窗口裡）。
///
/// ### ⚠️ 「剩不到一分鐘」不是「已經過了」
/// `WindowExpiry.accepts` 保證 `resetsAt > now` —— 已過的窗口在讀取時就被丟掉了。
/// 所以「不足一分鐘」唯一的含意是**還剩幾十秒**，回「剩 0m」。
/// 第二份把它判成「重置時間已過」，於是在窗口最後 60 秒會印出
/// 「重置時間已過 · 估 79%」—— 同一句話的兩半互相否定。
public enum ResetCaption {

    /// - Parameter now: ⚠️ **刻意不給預設值。** 兩頁必須傳同一個瞬間，
    ///   否則同一個倒數會在切換版面時跳一分鐘。
    ///   建議傳 `store.lastRefresh`（`dailyBars` / `cumulativePoints` /
    ///   `FinishGlow.menuBar` 用的就是它），這樣整頁是同一拍的快照。
    public static func countdown(resetsAt: Date?, now: Date) -> String {
        // 沒有重置時間就留白 —— 那一格的「不知道」由上面那個「—」說，
        // 不需要在註腳再說一次。
        guard let resetsAt else { return " " }
        guard let left = ResetTimestamp.remaining(until: resetsAt, now: now) else { return "已重置" }
        let h = Int(left) / 3600, m = (Int(left) % 3600) / 60
        return h > 0 ? "剩 \(h)h \(m)m" : "剩 \(m)m"
    }
}
