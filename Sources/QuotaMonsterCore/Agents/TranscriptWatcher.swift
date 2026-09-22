import Foundation

/// 每一份母 transcript 一個游標，加上一份**累積**的事實。
///
/// ### 為什麼要有這一層
/// 〔實測 2026-09-22，這台機器〕`AgentTreeBuilder.toolUseIds` 用
/// `String(contentsOf:)` 把整份母 transcript 讀進來，**每 3 秒一次、在 main actor 上**，
/// 而 `--bench-refresh` 量到 `DataStore.refresh()` 的穩態中位是 **1004 毫秒**
/// —— 一拍的預算是 3000 毫秒，也就是三分之一的時間花在重新解析看過的行。
/// 拆開來看，16.1MB 的檔案 I/O 只要 0.014 秒，**97% 是 JSON 解析**。
/// 所以這一層省的是**解析**，不是讀取；只快取 bytes 的版本一點都不會比較快。
///
/// ### ⚠️ 被重寫時要整份換掉，不是累加
/// transcript 在 compact / fork / `--resume` 時會被整個重寫。
/// 舊檔裡那些 agent **不在新檔裡**，留著它們等於在畫面上宣告一件
/// 這份記錄已經不再支持的事，而且沒有任何東西會再把它清掉。
public struct TranscriptWatcher: Sendable {

    private var cursors: [URL: TranscriptCursor] = [:]
    private var knowledge: [URL: TranscriptFacts] = [:]

    public init() {}

    /// 現在記著幾份 transcript。只給測試與 `--dump` 用。
    public var watchedCount: Int { knowledge.count }

    /// 讀掉 `url` 新增的部分，回傳「到目前為止我們知道的事實」。
    ///
    /// ⚠️ **讀不到的時候不會抹掉已經知道的事。** 「我們沒看到」不是「它沒發生」——
    /// 兩層的分界在下一層（`TranscriptCursor.Read.unreadable`）還在，
    /// 需要分辨的呼叫端去那裡問。這一層回答的是「我們知道什麼」。
    public mutating func update(_ url: URL) -> TranscriptFacts {
        var cursor = cursors[url] ?? TranscriptCursor()
        defer { cursors[url] = cursor }

        guard case .advanced(let lines, let fromStart) = cursor.read(url) else {
            return knowledge[url] ?? TranscriptFacts()
        }
        // 從頭開始 ＝ 第一次看到，或它被整個重寫了。兩種都要換一份新的事實。
        var facts = fromStart ? TranscriptFacts() : (knowledge[url] ?? TranscriptFacts())
        facts.ingest(lines)
        knowledge[url] = facts
        return facts
    }

    /// 放掉不在名單裡的那些。session 死掉之後它的事實沒有人會再問，
    /// 而一份 13MB transcript 的 `toolUseIds` 不是可以忽略的記憶體。
    public mutating func keep(only urls: Set<URL>) {
        cursors = cursors.filter { urls.contains($0.key) }
        knowledge = knowledge.filter { urls.contains($0.key) }
    }
}
