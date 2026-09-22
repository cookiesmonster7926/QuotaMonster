import Foundation

/// 一個 session 底下的一般 Agent subagent：哪些還沒好、其餘幾隻。
///
/// ### 為什麼需要它
/// 面板原本把**每一隻** agent 都列出來，而 `AgentTreeBuilder.isFresh` 只濾掉
/// 「不是這一輪的」—— 所以這個 session 開過的每一隻都會一直掛著。
/// 使用者 2026-09-22 回報：「顯示成 subagent 就會讓使用者不知道到底是什麼還沒好」。
///
/// workflow 早就有這個收合規則（`WorkflowTally`），agent 沒有 ——
/// **整齊的那個藏起來、雜亂的那個堆著，方向正好相反。**
///
/// ### ⚠️ 「已結束」不是「已完成」
/// 〔實測 2026-09-22〕一般 agent 的完成狀態其實**讀得到**，100% 覆蓋：
/// - 背景 agent → 母 transcript 的 `<task-notification>` 帶
///   `<task-id>{agentId}</task-id>` 與 `<status>`（completed / failed / killed）
/// - 前景 agent → 該次 `tool_result` 的 `toolUseResult.status == "completed"`
///
/// ⚠️ 但那要掃母 transcript，而它可以到 13MB —— 尾端讀 64KB 只涵蓋約 15 筆記錄，
/// 蓋不住幾分鐘前的完成。要做對得加「記住 byte offset、只讀新增部分」那套機器。
/// **這一版沒有做**，所以只用 `AgentActivity` 的活動代理回答「還在不在跑」，
/// 收合那一行只能說「已結束」——我們不知道它是做完還是死掉。
///
/// 那個 100% 覆蓋的發現本身已經記在 `docs/quotamonster.md`（它推翻了
/// 「一般 Agent 扇出永遠沒有正面證據」那一條）。
public struct AgentTally: Equatable, Sendable {

    /// 還沒好的 —— 有自己一行。
    public let outstanding: [AgentNode]
    /// 其餘幾隻（含子 agent）。
    public let endedCount: Int

    public init(_ agents: [AgentNode]) {
        var live: [AgentNode] = []
        var ended = 0
        func walk(_ n: AgentNode) {
            switch n.runState {
            case .running, .likelyRunning: live.append(n)
            case .finished, .unknown:      ended += 1
            }
            n.children.forEach(walk)
        }
        agents.forEach(walk)
        self.outstanding = live
        self.endedCount = ended
    }

    /// 收合那一行要寫的字。沒有東西可收就回 nil。
    ///
    /// ⚠️ 用詞是**已結束**。宣稱「已完成」需要證據，而這一版沒有去讀那個證據。
    public var collapsedText: String? {
        endedCount > 0 ? "\(endedCount) 個 agent 已結束" : nil
    }
}
