import Foundation

/// 上一次**成功**問到「有沒有新版」是什麼時候。
///
/// ### ⚠️ 為什麼這個可以落地，而「上次問的時間」不行
/// 規矩 20 擋的是**抑制方向**的觀測值（存下來會讓 app 之後更安靜）。
/// 這兩個欄位的方向相反：
///
/// | | 方向 | 落地？ |
/// |---|---|---|
/// | `lastAttempt`（上次去問） | **抑制** —— 存了就會少問 | ❌ 只活在記憶體 |
/// | `lastSuccess`（上次問到） | **揭露** —— 存了才說得出「已經三天問不到」 | ✅ |
///
/// 丟掉 `lastAttempt` 的代價是每次開 app 多問一次 ——
/// 而〔實測 2026-09-23〕GitHub 未認證是 60 次/小時，那完全不是問題。
/// 丟掉 `lastSuccess` 的代價則是**沉默會被讀成「你是最新的」**，那是規矩不允許的。
///
/// ⚠️ 這個檔案的大小是**結構上**有界的（一個時間戳），所以規矩 42 的「要有上限」
/// 自動成立，不需要 pruner。
/// ⚠️ 也**刻意不抄** `NotifyState.save` 那個「寫檔時順手清掉過期欄位」的形狀 ——
/// 一個會自己刪東西的檔案，下一個人不會預期。
public struct UpdateState: Equatable, Sendable, Codable {

    public var lastSuccess: Date?

    public init(lastSuccess: Date? = nil) { self.lastSuccess = lastSuccess }

    public static let relativePath = "Library/Application Support/QuotaMonster/update-state.json"

    public static func defaultURL(home: URL) -> URL {
        home.appendingPathComponent(relativePath)
    }

    /// 壞檔、空檔、不存在一律回 nil。**不丟錯。**
    public static func load(_ url: URL) -> UpdateState? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let s = try? JSONDecoder().decode(UpdateState.self, from: data) else { return nil }
        return s
    }

    @discardableResult
    public static func save(_ s: UpdateState, to url: URL) -> Bool {
        guard let data = try? JSONEncoder().encode(s) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        do { try data.write(to: url, options: .atomic) } catch { return false }
        return true
    }
}
