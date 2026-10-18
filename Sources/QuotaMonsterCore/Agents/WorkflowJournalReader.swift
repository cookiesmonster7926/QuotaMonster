import Foundation

/// 一個 workflow 扇出的執行狀態。
public struct WorkflowJournal: Equatable, Sendable {

    /// 一行 `started`。
    public struct Spawn: Equatable, Sendable {
        public let agentId: String
        /// `started` 行的 `phase` 欄位。
        ///
        /// 〔實測 2026-09-19，36 個 journal / 343 個 started 行〕每一行都有這個欄位、
        /// 都不是空字串。但這個 schema **沒有官方契約**（`AgentMeta` 已經替整個
        /// `.claude/` 目錄寫過這句：未知的 key 必須無害，缺少的 key 必須容忍），
        /// 所以它是 optional，而且缺少時**不繼承上一行**。
        public let phase: String?

        public init(agentId: String, phase: String?) {
            self.agentId = agentId
            self.phase = phase
        }
    }

    /// 依 spawn 順序的 `started` 行。
    ///
    /// ⚠️ **順序是這個檔案裡唯一的時間資訊** —— 〔實測〕started 行沒有任何時間戳
    /// （key 組合固定是 type/key/agentId/label/phase），而檔案是 append-only。
    /// 所以它不可以被換成 Set 或 Dictionary。
    public private(set) var spawns: [Spawn]
    /// 已收尾的 —— **`result` 與 `failed` 的聯集**。
    public private(set) var finished: Set<String>

    /// 啟動過的。**從 `spawns` 導出**，集合語意與改動前完全一樣。
    public var started: Set<String> { Set(spawns.map(\.agentId)) }

    /// 最後一個 `started` 行的 phase。
    ///
    /// ⚠️ **它不是「現在正在跑哪一階段」。** workflow 的 `pipeline()` 沒有 barrier，
    /// 所以多個階段真的會同時在跑 —— 一個單數字串必然丟掉其中一個。
    /// 這個值取的是**最新的那個邊緣**，與 `total` / `finishedCount` 同一條規則
    /// （都數「spawn 過的全部」），所以同一個 group 裡的三個數字前後一致。
    ///
    /// nil ＝ **journal 沒有告訴我們**（讀不到、沒有 started 行、或最後那行沒有
    /// phase 欄位）。它**不**代表「這個 workflow 沒有階段」，
    /// 呼叫端也不可以退回 meta 的 phase 去補 —— 那正是 2026-09-19 修掉的那個擲骰子。
    public var latestPhase: String? { spawns.last?.phase }

    /// 還在跑的。
    ///
    /// ⚠️ 必須同時扣掉 `failed`。只扣 `result` 的話，失敗的 agent 會永遠掛在樹上，
    /// 而且不能改用「mtime 冷卻超過 N 秒就算死」來補 —— 實測有 agent 失敗後
    /// 僅 153 秒就被觀察到，那條規則會誤判。
    public var running: Set<String> { started.subtracting(finished) }

    public init(spawns: [Spawn], finished: Set<String>) {
        self.spawns = spawns
        self.finished = finished
    }

    /// 什麼都還沒讀到。
    public init() { self.init(spawns: [], finished: []) }

    /// 依檔案裡的順序餵進一批行。**解析只定義在這裡** ——
    /// 每拍增量讀的 `WorkflowJournalWatcher` 與一次讀完的 `WorkflowJournalReader` 都走它。
    ///
    /// 實測所有真實 journal 的 type 只有四種：started / result / failed / launched。
    /// `launched` 沒有 agentId，會被自然忽略。〔讀碼 2.1.302〕程式碼裡還有
    /// `restoring` / `restored` / `resumed` 三種標記行，也都沒有 agentId，同樣忽略。
    public mutating func ingest(_ lines: [String]) {
        for line in lines {
            // 壞掉的行跳過：寫到一半的殘片，Claude Code 會在下一次 append 前補一個換行
            // 把它封成獨立的一行〔讀碼 2.1.302〕，它就以「壞掉的完整行」的樣子到這裡。
            guard let d = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
                  let type = d["type"] as? String,
                  let agentId = d["agentId"] as? String
            else { continue }

            switch type {
            case "started":
                spawns.append(Spawn(agentId: agentId, phase: d["phase"] as? String))
            case "result", "failed": finished.insert(agentId)
            default:                 break
            }
        }
    }
}

/// 一次讀完 `subagents/workflows/<wf_id>/journal.jsonl`。
///
/// ⚠️ **app 每拍走的不是這一支**，是 `WorkflowJournalWatcher`（增量游標）。
/// 這一支今天只剩解析規則的測試在用（`WorkflowJournalReaderTests`）；解析本身在
/// `WorkflowJournal.ingest`，兩條路共用，所以那些測試守的就是 app 實際在跑的規則。
/// 兩者差在最後一行：這一支連**沒有換行結尾**的最後一行也試著解析，
/// 游標則要等到換行才交出那一行（〔實測 2026-10-19〕117/117 個真實 journal 以換行結尾）。
public struct WorkflowJournalReader: Sendable {
    public init() {}

    public func read(_ url: URL) -> WorkflowJournal {
        var journal = WorkflowJournal()
        guard let data = try? Data(contentsOf: url) else { return journal }
        journal.ingest(data.split(separator: UInt8(ascii: "\n"))
            .map { String(decoding: $0, as: UTF8.self) })
        return journal
    }
}
