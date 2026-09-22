import Foundation

/// 一隻一般 Agent subagent 的**真實下場**。
///
/// ⚠️ 這個型別只在**讀到正面證據**時存在。讀不到就沒有這一筆 ——
/// 不是「下場不明的一筆」，是「沒有這一筆」。兩者的差別在
/// `AgentTally` 那一層才變成畫面上的「狀態不明」。
public struct AgentOutcome: Equatable, Sendable {

    /// 實測的全部值。〔2026-09-22，37 份 transcript〕
    /// 去重之後：Agent 25 筆（completed 24 / killed 1）、
    /// workflow 44 筆（completed 41 / failed 3）、背景指令 306 筆
    /// （completed 292 / failed 11 / killed 3）。沒有出現過 cancelled / timeout / error。
    ///
    /// ⚠️ 沒見過的值**整筆跳過**，不新增一格也不猜 —— 這是第二節拒絕 6
    /// （沒有官方契約的格式：未知的 key 必須無害）在這裡的落點。
    public enum Kind: String, Equatable, Sendable, CaseIterable {
        case completed, failed, killed
    }

    public let agentId: String
    public let kind: Kind
    /// 那一筆記錄**自己**的時間戳。
    ///
    /// ⚠️ nil ＝ 這筆記錄沒帶時間，**不是** `Date()`，也不是檔案的 mtime。
    /// 這個 repo 為「拿寫入時間當事件時間」付過兩次代價（`~/CLAUDE.md`）。
    public let at: Date?

    public init(agentId: String, kind: Kind, at: Date?) {
        self.agentId = agentId
        self.kind = kind
        self.at = at
    }
}

/// 把母 transcript 的行折疊成「我們知道的事實」。
///
/// ⚠️ **它只累加，不遺忘。** 呼叫端負責在 transcript 被重寫時
/// （`TranscriptCursor.Read.advanced(fromStart: true)`）換一份新的。
public struct TranscriptFacts: Equatable, Sendable {

    /// 母 transcript 裡所有 `tool_use` 的 id。用來確認 agent 的 `toolUseId` 真的配得上。
    public private(set) var toolUseIds: Set<String> = []
    /// agentId → 最後一次讀到的下場。
    ///
    /// ⚠️ **最後一筆贏。** 〔實測〕同一隻 agent 會重複通知：一隻通知了 17 次，
    /// 另一隻的第二次 `<result>` 開頭是「Correction to my previous report」。
    /// 「完成」的意思是「這一次停下來了」，不是「從此結束」。
    public private(set) var outcomes: [String: AgentOutcome] = [:]

    public init() {}

    public mutating func ingest(_ lines: [String]) {
        for l in lines { ingest(l) }
    }

    public mutating func ingest(_ line: String) {
        guard let data = line.data(using: .utf8),
              let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return }

        collectToolUseIds(d)
        collectSpawn(d)
        collectNotification(d)
    }

    // ── tool_use ───────────────────────────────────────────────

    private mutating func collectToolUseIds(_ d: [String: Any]) {
        guard let message = d["message"] as? [String: Any],
              let content = message["content"] as? [[String: Any]] else { return }
        for block in content where block["type"] as? String == "tool_use" {
            if let id = block["id"] as? String { toolUseIds.insert(id) }
        }
    }

    // ── 開出去的那一筆 ─────────────────────────────────────────

    /// 一般 Agent 的 `tool_result` 旁邊掛著一個 `toolUseResult`。
    /// 〔實測 2026-09-22，37 筆〕兩種形狀：
    /// - `async_launched`（27 筆）—— 只是開出去了，**不是一種下場**。完成會晚一點
    ///   以 `<task-notification>` 抵達。
    /// - `completed`（10 筆）—— 同步的 agent，**這一筆本身就是完成**，不會再通知。
    ///
    /// ⚠️ 不可以看 Agent 工具的**輸入** `run_in_background` 來預測走哪一條 ——
    /// 〔實測〕28 次呼叫裡只有 8 次帶了那個旗標，卻有 16 次回 `async_launched`。
    /// 決定權在 harness，所以只能讀結果。
    private mutating func collectSpawn(_ d: [String: Any]) {
        guard let r = d["toolUseResult"] as? [String: Any],
              let agentId = r["agentId"] as? String,
              let status = r["status"] as? String
        else { return }

        let isAsync: Bool
        switch status {
        case "async_launched": isAsync = true
        case "completed":      isAsync = false
        // 沒見過的值整筆跳過。
        default: return
        }

        if !isAsync {
            outcomes[agentId] = AgentOutcome(
                agentId: agentId, kind: .completed, at: Self.timestamp(d))
        }
    }

    // ── 通知 ───────────────────────────────────────────────────

    /// `<task-notification>` 區塊在磁碟上有兩種載體，**兩種都要讀**：
    ///
    /// | 載體 | 涵蓋率（實測 n=25 隻 agent） |
    /// |---|---|
    /// | `queue-operation` / `enqueue`，`content` 直接是字串 | 25/25 |
    /// | `type:"user"`，`message.content` 是字串 | 6/25 |
    ///
    /// ⚠️ `operation:"remove"` 是 enqueue 的**逐字複本**（實測 338 vs 417 筆），
    /// 兩個都算就是雙重計數。
    private mutating func collectNotification(_ d: [String: Any]) {
        let block: String
        switch d["type"] as? String {
        case "queue-operation":
            guard d["operation"] as? String == "enqueue",
                  let c = d["content"] as? String else { return }
            block = c
        case "user":
            guard let message = d["message"] as? [String: Any],
                  let c = message["content"] as? String else { return }
            block = c
        default:
            return
        }
        guard block.contains("<task-notification>") else { return }

        // ⚠️ 只認 agent 的。workflow（9 字元 `w`）與背景指令（9 字元 `b`）的通知
        // 長得一模一樣，而 `<summary>` 的開頭是唯一沒有歧義的判準
        // （id 長度 17 也分得出 agent，但分不出 Monitor 與背景指令）。
        guard let summary = Self.tag("summary", in: block),
              summary.hasPrefix("Agent \"") else { return }
        guard let agentId = Self.tag("task-id", in: block) else { return }
        // 沒有 `<status>` 的是進度回報，**不是下場不明的完成**。
        guard let raw = Self.tag("status", in: block),
              let kind = AgentOutcome.Kind(rawValue: raw) else { return }

        outcomes[agentId] = AgentOutcome(agentId: agentId, kind: kind, at: Self.timestamp(d))
    }

    // ── 小工具 ─────────────────────────────────────────────────

    /// 取**第一個** `<tag>…</tag>`。
    ///
    /// ⚠️ 第一個才是對的：標籤順序固定（task-id → tool-use-id → output-file →
    /// status → summary → … → result），而 `<result>` 裡放的是 agent 自己寫的報告 ——
    /// 那是**模型可控的字串**，完全可以含有 `<status>failed</status>` 這幾個字。
    static func tag(_ name: String, in block: String) -> String? {
        guard let open = block.range(of: "<\(name)>"),
              let close = block.range(of: "</\(name)>", range: open.upperBound..<block.endIndex)
        else { return nil }
        return String(block[open.upperBound..<close.lowerBound])
    }

    /// 記錄自己的時間戳。解析失敗回 nil —— 不退回「現在」。
    /// ISO-8601 的解析只有一份，在 `ResetTimestamp`（規矩 2）。
    static func timestamp(_ d: [String: Any]) -> Date? {
        guard let s = d["timestamp"] as? String else { return nil }
        return try? ResetTimestamp.parse(.iso8601(s))
    }
}
