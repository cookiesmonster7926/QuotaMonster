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
    public let spawns: [Spawn]
    /// 已收尾的 —— **`result` 與 `failed` 的聯集**。
    public let finished: Set<String>

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
}

/// 讀 `subagents/workflows/<wf_id>/journal.jsonl`。
///
/// 實測所有真實 journal 的 type 只有四種：started / result / failed / launched。
/// `launched` 沒有 agentId，會被自然忽略。
public struct WorkflowJournalReader: Sendable {
    public init() {}

    public func read(_ url: URL) -> WorkflowJournal {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return WorkflowJournal(spawns: [], finished: [])
        }
        var spawns: [WorkflowJournal.Spawn] = []
        var finished: Set<String> = []

        for line in text.split(separator: "\n") {
            // append-only 的檔案，最後一行可能只寫到一半 —— 壞掉就跳過。
            guard let data = line.data(using: .utf8),
                  let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let type = d["type"] as? String,
                  let agentId = d["agentId"] as? String
            else { continue }

            switch type {
            case "started":
                spawns.append(WorkflowJournal.Spawn(agentId: agentId,
                                                    phase: d["phase"] as? String))
            case "result", "failed": finished.insert(agentId)
            default:                 break
            }
        }
        return WorkflowJournal(spawns: spawns, finished: finished)
    }
}
