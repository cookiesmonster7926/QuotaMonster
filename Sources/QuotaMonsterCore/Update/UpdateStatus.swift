import Foundation

/// 「有沒有新版」—— **三態**。
///
/// ### ⚠️ 這裡只有一個錯值得害怕
/// **把「問不到」畫成「你已經是最新的」。**
/// 那是這個 repo 的兩層規矩（`~/CLAUDE.md`）：
/// 「看到它、但它不在那個狀態」（真的問到了，沒有新版）與
/// 「整個沒看到它」（連不上、被限流、回應解不出來）是**兩件事**。
/// 混在一起的後果是：一個永遠連不上的使用者，會永遠看到「你是最新的」——
/// 而他其實已經落後好幾版。
public enum UpdateStatus: Equatable, Sendable {

    /// 有新版。**正面證據**：我們問到了，而且它比手上這個新。
    case available(ReleaseVersion, url: String)
    /// 已經是最新的。**也是正面證據** —— 我們真的問到了。
    case upToDate
    /// 不知道。⚠️ 與 `.upToDate` 完全不同，不可以畫成同一件事。
    case unknown(Reason)

    /// 為什麼不知道。**每一個都有名字** —— 「不知道」如果沒有理由，
    /// 下一個人會把它當成「沒事」。
    public enum Reason: Equatable, Sendable {
        /// app 剛開機，還沒問過。
        case notCheckedYet
        /// 連不上（沒網路、DNS、逾時）。
        case offline
        /// 被限流。〔實測 2026-09-23〕未認證是 60 次/小時/IP。
        case rateLimited
        /// HTTP 回來了但不是我們認得的形狀。
        case unreadable
        /// tag 解不出版本號（`nightly`、`v1.2`…）。
        case unparseableTag(String)
        /// 最新那一筆是草稿或預覽版。
        ///
        /// ⚠️ 這是「**不知道**」不是「最新的」：它只代表這一次問到的東西
        /// 不能拿來判斷，不代表正式版沒有更新。
        case draftOrPrerelease
    }

    /// 從 GitHub 回來的欄位判斷。**判斷只在這裡發生。**
    public static func from(latestTag: String, current: ReleaseVersion,
                            isDraft: Bool, isPrerelease: Bool, url: String) -> UpdateStatus {
        guard !isDraft, !isPrerelease else { return .unknown(.draftOrPrerelease) }
        guard let latest = ReleaseVersion(latestTag) else {
            return .unknown(.unparseableTag(latestTag))
        }
        return latest > current ? .available(latest, url: url) : .upToDate
    }
}

/// 什麼時候去問一次。
public enum UpdateCheck {

    /// 兩次檢查之間至少隔多久。
    ///
    /// ⚠️ **這是一個選擇，不是一個量測** —— 沒有任何實驗說「6 小時」是對的。
    /// 它被兩件事夾住：
    /// - 上界〔實測 2026-09-23〕GitHub 未認證請求是 **60 次/小時/IP**
    ///   （`x-ratelimit-limit: 60`），所以每小時一次也還差得遠。
    /// - 下界：這是一個「有新版」的提示，不是警報。沒有人需要在幾分鐘內知道。
    ///
    /// 因為它沒有量測撐著，所以它**不開放給使用者調**
    /// （`Preferences` 的判準：有量測撐著的界線不給調，兩個方向都無聲的常數也不給調）。
    public static let interval: TimeInterval = 6 * 3600

    /// 太久沒有**成功**問到的話，面板要說出來。
    ///
    /// ⚠️ 沉默會被讀成「你是最新的」，所以失敗不能永遠安靜。
    /// 但一次失敗也不值得打擾 —— 所以要一個「久到不像暫時性問題」的界線。
    /// 同樣是選擇不是量測：3 天 ＝ 12 次檢查機會全部落空。
    public static let outageThreshold: TimeInterval = 3 * 86400

    public static func shouldCheck(lastAttempt: Date?, now: Date) -> Bool {
        guard let lastAttempt else { return true }
        // ⚠️ 上界不可省：時鐘往回跳或狀態檔被手改，未來的時間戳會讓它
        // **永遠**不再檢查。同一個不對稱在這個 repo 出現第四次
        //（`StatusLineCacheReader` / `WindowExpiry` / `AgentActivity` 都補過）。
        if lastAttempt > now { return true }
        return now.timeIntervalSince(lastAttempt) >= interval
    }
}

/// 面板上那一行要寫什麼。nil ＝ 什麼都不說。
public enum UpdateCaption {

    /// - Parameter lastSuccess: 上一次**成功**問到的時刻。nil ＝ 從來沒成功過。
    ///   ⚠️ nil 不可以被當成「剛剛才成功」——那正好會在最該說話的時候閉嘴。
    public static func text(_ status: UpdateStatus, lastSuccess: Date?, now: Date) -> String? {
        switch status {
        case .available(let v, _):
            return "有新版 \(v.text) —— 點這裡看看改了什麼"

        case .upToDate:
            // 沒有新聞不是新聞。面板很擠，不值得為「一切正常」花一行。
            return nil

        case .unknown(.notCheckedYet):
            // app 剛開機不該先道歉。
            return nil

        case .unknown:
            // ⚠️ 一次失敗安靜，**一直**失敗就必須說 ——
            // 否則「沉默」會被讀成「你是最新的」，而那正是兩層規矩要擋的。
            let since = lastSuccess.map { now.timeIntervalSince($0) } ?? .infinity
            guard since >= UpdateCheck.outageThreshold else { return nil }
            return lastSuccess == nil
                ? "更新檢查一直連不上 —— 目前無法確認有沒有新版"
                : "更新檢查連不上已經超過三天 —— 目前無法確認有沒有新版"
        }
    }
}
