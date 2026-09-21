import Foundation

/// T2 音效的滾動時間窗上限。
///
/// ### 為什麼是「一小時幾則」而不是「最小間隔」
/// 〔代理量測，n=28〕全機器混排的排空間隔 **0% 小於 60 秒**、7.1% 小於 5 分鐘；
/// 同一個 session 內部（24 個間隔）**0% 小於 5 分鐘**，最小 23.9 分鐘。
/// 冷卻期型的預算在這份資料上擋不到任何東西 —— 而替一個擋不到東西的機制寫
/// 程式碼，就是替下一個人準備一段沒有人能驗證的註解。
///
/// ### 為什麼不存磁碟
/// 套 `NotifyState` 檔頭自己的三問，三問都指向不存：
/// (1) 它是觀測狀態，不是使用者下的指令（`mutedUntil` 是後者，那是它被存的
/// 唯一理由）；(2) 它是**抑制**方向 —— 一個存下來的「這小時用完了」會在停機後
/// 吞掉一則真事件；(3) 視窗一小時，遠短於這個 app 的一次執行。
///
/// ### 它不是第二個靜音排程器
/// `MutePolicy` 的檔頭寫著「這裡不會有第三個選項叫安靜時段」。這個型別沒有
/// 日曆邊界、沒有時段、沒有「到明早」—— 它只數最近一小時發生過幾次。
/// 半夜那 54% 是靠在場閘擋的，不是靠它。
public struct SoundBudget: Equatable, Sendable {

    /// 視窗長度。
    ///
    /// **這個數字是選的，但錨在量測的口徑上。** 唯一界定得了最壞情況的數字是
    /// 〔代理推算〕「滑動 60 分鐘視窗最多 4 則」—— 我量的是 60 分鐘，門檻就必須
    /// 是 60 分鐘。換成 30 分鐘或一天，就沒有任何一筆資料可以引用，而「一天」
    /// 還需要日曆邊界，那是 Task 5.7 明文拒絕的第一塊磚。
    public static let window: TimeInterval = 3600

    /// 一個視窗裡最多幾聲。
    ///
    /// **3 是選的，算術是驗過的。** 〔代理推算〕套上在場閘之後剩下的 6 聲，
    /// 相鄰間隔是 8197／767／665／3540／297 秒，任何 3600 秒視窗內最多 **3** 則。
    /// 所以 3 在觀測資料上**一次都不會作用**，而 2 會擋掉一則已經觀測到的真完成。
    /// 閘前的滑動視窗最大是 4，所以 3 也擋得住已觀測到的尖峰。
    ///
    /// ⚠️ **誠實版：它是保險絲，不是調校過的參數。** 它守的是這份資料看不到的
    /// 那個模式（人坐在位子上同時併發跑好幾個 workflow）。第一次它真的擋掉東西
    /// 的那一天，沒有人能從資料上說它擋對了。
    public static let capacity = 3

    /// 已經出過聲的時刻。
    ///
    /// ⚠️ **只會被時間沖掉，不會被「這一拍沒看到任何 workflow」清空** ——
    /// 與 `st.total = max(...)` / `peakFinished` 同一條原則：不存在不是資訊。
    private var stamps: [Date] = []

    public init() {}

    /// 扣一格。扣得到回 true。
    ///
    /// **檢查與扣款合成一支**，不拆成 `hasRoom` + `consume`：拆開就給了下一個人
    /// 一個只檢查不扣、或先扣再判的縫。
    public mutating func consumeIfPossible(at now: Date) -> Bool {
        prune(now)
        // ⚠️ 順序是 prune → 檢查 → append。先 append 再檢查的話，一次被擋下的
        // 嘗試會留下痕跡，把回血時間整整往後推一個視窗。
        guard stamps.count < Self.capacity else { return false }
        stamps.append(now)
        return true
    }

    /// 還剩幾格。**診斷用，刻意不是 `mutating`。**
    ///
    /// 問一下剩多少不可以改變任何東西 —— 一個會改狀態的存取子，
    /// 會讓「印一行診斷」本身變成一次行為改變。
    public func remaining(at now: Date) -> Int {
        // ⚠️ **就地算，不回傳 `stamps.count`。** 回傳 count 的版本會在沒有事件的
        // 那段時間一直說「剩 0」，而一份說謊的診斷比沒有診斷更糟 ——
        // 它會讓你以為已經看過了。
        Self.capacity - stamps.count { now.timeIntervalSince($0) < Self.window }
    }

    /// 現在記得幾筆。只給測試用來證明它不會無限長大。
    var recorded: Int { stamps.count }

    /// 句型直接抄 `NotificationEngine` 清 `lastEmitted` 那一行 ——
    /// 「`now - t < window` 才還算數」是這個檔案既有的邊界語意，
    /// 不要在這裡發明第二種。
    private mutating func prune(_ now: Date) {
        stamps = stamps.filter { now.timeIntervalSince($0) < Self.window }
    }
}
