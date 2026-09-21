import Foundation

/// 通知層裡**必須跨重啟活下來**的那一小塊。
///
/// ### 為什麼要存
/// 這個 repo 已經為這件事付過一次代價。`UsageHistory` 的註解寫著：
/// 「上一筆是什麼放在記憶體裡，所以每個新行程都會覺得自己是第一次 ——
/// 實測 app 重啟三次加兩支診斷指令，就寫出四行一模一樣的紀錄。」
/// 通知層的版本大聲得多：重啟時三個 session 在等，就是三個浮窗加三聲。
///
/// 而 `mutedUntil` 根本不是觀測值，是**使用者直接下的指令**。它自己講明的時間
/// 跨度（「靜音到明早」約 12 小時）遠長於這個 app 的一次執行。丟掉它 = 在使用者
/// 明確要求安靜的時段裡出聲。
///
/// ### 為什麼只存這一樣
/// 60 秒去重窗與 4 秒合併窗都比任何一次重啟短，存了沒用，還要在三秒輪詢上
/// 多寫一次檔。而且存下來的抑制是**危險**的那個方向：一個「已經跟你講過 X 了」
/// 在長時間停機後可能吞掉一個真正的新事件。
///
/// 「已經通知過哪些等待」也不存。一度存了，後來發現它是死的 ——
/// 防止重啟尖叫的是引擎的「第一次觀測不發」規則，不是這個檔案。
/// 留著一個沒有人讀的欄位、再配一段說它有用的註解，比沒有更糟：
/// 下一個人會相信那段註解。
public struct NotifyState: Equatable, Sendable, Codable {

    public var mutedUntil: Date?

    public init(mutedUntil: Date? = nil) {
        self.mutedUntil = mutedUntil
    }

    // ── 路徑 ───────────────────────────────────────────────────

    public static let relativePath =
        "Library/Application Support/QuotaMonster/notify-state.json"

    public static func defaultURL(home: URL) -> URL {
        home.appendingPathComponent(relativePath)
    }

    // ── 讀寫 ───────────────────────────────────────────────────

    /// 壞檔、空檔、不存在一律回 nil。**不丟錯** ——
    /// 一個讀不回來的狀態檔不可以讓 app 起不來。
    public static func load(_ url: URL) -> NotifyState? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return try? d.decode(NotifyState.self, from: data)
    }

    /// 錯誤全吞，回 `Bool`。慣例抄自 `UsageHistory`。
    @discardableResult
    public static func save(_ state: NotifyState, to url: URL,
                            now: Date = Date()) -> Bool {
        var s = state
        // 寫檔時自己收尾：過期的靜音清掉。這個檔案永遠只有一個欄位，
        // 所以它不會長大，也就**不必動到 pruner** ——
        // `StatusLineCachePrunerTests` 明講「pruner 是整個 Core 唯一會刪檔的東西」，
        // 那句話要繼續成立。
        if let m = s.mutedUntil, m <= now { s.mutedUntil = nil }

        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        guard let data = try? e.encode(s) else { return false }

        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // 整檔重寫（這是狀態，不是 log），`.atomic` 保證不會讀到寫到一半的檔。
        do { try data.write(to: url, options: .atomic) } catch { return false }
        return true
    }

    // ── 未知的鍵要無害 ─────────────────────────────────────────

    private enum CodingKeys: String, CodingKey {
        case mutedUntil
    }

    public init(from decoder: Decoder) throws {
        // 用 keyed container 逐欄取，**不是**整個 decode 成固定形狀 ——
        // 之後加欄位時，舊檔不可以因此整個讀不回來；而舊檔裡那個已經拿掉的
        // `lastNotified` 也不可以讓新版讀不回來。
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mutedUntil = try c.decodeIfPresent(Date.self, forKey: .mutedUntil)
    }
}
