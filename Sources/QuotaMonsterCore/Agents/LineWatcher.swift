import Foundation

/// 可以一批一批餵行進去、累積成「我們知道的事實」的東西。
///
/// ⚠️ 只累加，不遺忘 —— 檔案被重寫時由 `LineWatcher` 整份換一個新的（`init()`），
/// 不是由它自己判斷。
public protocol LineFacts: Sendable {
    init()
    mutating func ingest(_ lines: [String])
}

extension TranscriptFacts: LineFacts {}
extension WorkflowJournal: LineFacts {}

/// 母 transcript 的游標 + 事實。名字留著，因為它是這個 repo 先有的那一個。
public typealias TranscriptWatcher = LineWatcher<TranscriptFacts>
/// workflow 的 `journal.jsonl` 的游標 + 事實。**與 transcript 用同一套機器**，不另寫一套。
public typealias WorkflowJournalWatcher = LineWatcher<WorkflowJournal>

/// 每一份 append-only 檔案一個游標，加上一份**累積**的事實。
///
/// ### 為什麼要有這一層
/// 〔實測 2026-09-22，這台機器〕`AgentTreeBuilder.toolUseIds` 用
/// `String(contentsOf:)` 把整份母 transcript 讀進來，**每 3 秒一次、在 main actor 上**，
/// 而 `--bench-refresh` 量到 `DataStore.refresh()` 的穩態中位是 **740 毫秒**
/// —— 一拍的預算是 3000 毫秒，也就是三分之一的時間花在重新處理看過的行。
///
/// 成本拆在哪裡見 `TranscriptCursor` 的檔頭：⚠️ **最貴的是切行不是 JSON**
/// （在多 MB 的 Swift `String` 上 `split` 佔 68–78%）。
/// 這一層省的是**逐行的工作**，不是讀取；只快取 bytes 的版本一點都不會比較快。
///
/// workflow 的 `journal.jsonl` 是第二個房客（`WorkflowJournalWatcher`）：
/// 它原本在 `AgentTreeBuilder` 裡每拍整份 `String(contentsOf:)` + `split`，
/// 而且在新鮮度閘**之前**，所以早就死掉的 workflow 的 journal 每拍都被重新解析。
///
/// ### ⚠️ 被重寫時要整份換掉，不是累加
/// transcript 在 compact / fork / `--resume` 時會被整個重寫；journal 在
/// workflow 的 run 被「還原」時也會（`writeRestored`，見 `TranscriptCursor` 的檔頭）。
/// 舊檔裡那些東西**不在新檔裡**，留著它們等於在畫面上宣告一件
/// 這份記錄已經不再支持的事，而且沒有任何東西會再把它清掉。
public struct LineWatcher<Facts: LineFacts>: Sendable {

    private var cursors: [URL: TranscriptCursor] = [:]
    private var knowledge: [URL: Facts] = [:]
    /// 上一次 `sweep()` 之後被 `update` 問過的那些。
    private var touched: Set<URL> = []

    /// 每份檔案**連續**讀不到幾次了。讀到一次就拿掉。
    private var misses: [URL: Int] = [:]

    public init() {}

    /// `url` 最近連續幾次讀不到。0 ＝ 上一次讀到了（或從沒問過）。
    ///
    /// `update` 回答的是「我們知道什麼」，這一格回答「那是多久以前看到的」——
    /// 兩層的分界（看到了但不在那個狀態／整個沒看到）要靠呼叫端拿它來切。
    /// 目前用它的是 `AgentTreeBuilder` 的 journal 寬限期（`journalUnreadableGrace`）。
    public func unreadableStreak(of url: URL) -> Int { misses[url] ?? 0 }

    /// 現在記著幾份檔案。只給測試與 `--dump` 用。
    public var watchedCount: Int { knowledge.count }

    /// 這個 watcher 這輩子總共**解析**過幾行。
    ///
    /// ⚠️ 它存在的唯一理由是**讓「不重新解析舊的行」變成可以斷言的東西**。
    /// 〔code review 2026-09-22〕在它之前，整個增量機制沒有任何測試守著：
    /// 把游標全丟掉（`cursors = [:]`，也就是退回每拍整份重讀那個 740 毫秒的洞）
    /// 675 則測試**全部照樣綠**。一個只在效能上有差別的不變式，
    /// 不會有人在改壞它的當下發現。
    public private(set) var linesIngested: Int = 0

    /// 讀掉 `url` 新增的部分，回傳「到目前為止我們知道的事實」。
    ///
    /// ⚠️ **讀不到的時候不會抹掉已經知道的事。** 「我們沒看到」不是「它沒發生」——
    /// 但也**不是**「它還是那樣」。這一層只負責不遺忘；連續讀不到幾次記在
    /// `unreadableStreak(of:)`，要不要、什麼時候切斷，是呼叫端的判斷
    /// （transcript 那一份刻意不切，見規矩 47；journal 那一份有寬限期，見 `AgentTreeBuilder`）。
    ///
    /// ⚠️ 讀不到的那一拍**也算被問過**（`touched`）：否則每拍都 `sweep()` 的呼叫端
    /// 會在讀不到的那一拍把知識與游標一起丟掉，下一拍再讀不到就回空的事實。
    public mutating func update(_ url: URL) -> Facts {
        touched.insert(url)
        var cursor = cursors[url] ?? TranscriptCursor()
        defer { cursors[url] = cursor }

        guard case .advanced(let lines, let fromStart) = cursor.read(url) else {
            misses[url, default: 0] += 1
            return knowledge[url] ?? Facts()
        }
        misses[url] = nil
        // 從頭開始 ＝ 第一次看到，或它被整個重寫了。兩種都要換一份新的事實。
        var facts = fromStart ? Facts() : (knowledge[url] ?? Facts())
        facts.ingest(lines)
        linesIngested += lines.count
        knowledge[url] = facts
        return facts
    }

    /// 放掉不在名單裡的那些。session 死掉之後它的事實沒有人會再問，
    /// 而一份 16.1MB transcript 的 `toolUseIds` 不是可以忽略的記憶體。
    public mutating func keep(only urls: Set<URL>) {
        cursors = cursors.filter { urls.contains($0.key) }
        knowledge = knowledge.filter { urls.contains($0.key) }
        misses = misses.filter { urls.contains($0.key) }
        // 只用 `keep(only:)`、從不 `sweep()` 的呼叫端（transcript 那一份）也不可以讓它一直長。
        touched.formIntersection(urls)
    }

    /// 放掉**上一次 sweep 之後沒有被 `update` 問過**的那些，然後重新開始記。
    ///
    /// 給「問哪些檔案」是在別處決定的呼叫端用：journal 要不要讀，是
    /// `AgentTreeBuilder` 在新鮮度閘之後才決定的，呼叫端列不出名單。
    /// 一拍呼叫一次 —— 那個 workflow 這一拍沒過閘，就沒有人會再問它的 journal。
    /// 它哪天又活過來（例如被 resume），代價是整份重讀一次，而那是對的。
    public mutating func sweep() {
        keep(only: touched)
        touched = []
    }
}
