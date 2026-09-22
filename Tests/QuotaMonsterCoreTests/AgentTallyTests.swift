import Testing
import Foundation
@testable import QuotaMonsterCore

/// 一個 session 底下的一般 Agent subagent：哪些還沒好、其餘幾隻。
///
/// ### 為什麼需要它
/// 面板原本把**每一隻** agent 都列出來，而且 `isFresh` 只濾掉「不是這一輪的」——
/// 所以這個 session 開過的每一隻都會一直掛著，全是灰點。
/// 使用者 2026-09-22 回報的正是這件事：
/// 「顯示成 subagent 就會讓使用者不知道到底是什麼還沒好」。
///
/// workflow 早就有這個收合規則（`WorkflowTally`），agent 沒有 ——
/// **整齊的那個藏起來、雜亂的那個堆著，方向正好相反。**
///
/// ### ⚠️ 「已結束」不是「已完成」
/// 一般 agent 的**狀態**我們讀得到（實測 100%：背景走母 transcript 的
/// task-notification、前景走 tool_result 的 status），但那要掃母 transcript，
/// 而它有 13MB。這一版只用 `AgentActivity` 的活動代理回答「還在不在跑」，
/// 所以收合那一行只能說「**已結束** N 隻」，不可以說「已完成」——
/// 我們不知道它是做完還是死掉。
@Suite("Agent 收合")
struct AgentTallyTests {

    func node(_ id: String, _ state: AgentRunState, children: [AgentNode] = []) -> AgentNode {
        AgentNode(meta: AgentMeta(agentId: id, agentType: "general-purpose",
                                  description: "d-\(id)", spawnDepth: 1),
                  runState: state, children: children)
    }

    @Test("還在跑的留下來，其餘算成一個數字")
    func splitsOutstandingFromEnded() {
        let t = AgentTally([node("a", .likelyRunning), node("b", .unknown), node("c", .finished)])
        #expect(t.outstanding.map { $0.meta.agentId } == ["a"])
        #expect(t.endedCount == 2)
    }

    @Test("journal 讀到的 running 也算還沒好 —— 兩種在跑都要留下")
    func confirmedRunningIsAlsoOutstanding() {
        let t = AgentTally([node("a", .running), node("b", .likelyRunning)])
        #expect(t.outstanding.count == 2)
    }

    @Test("子 agent 也要數進去 —— 深度 2 的那隻跑起來一樣要看得到")
    func countsChildren() {
        let t = AgentTally([node("p", .unknown, children: [node("c", .likelyRunning)])])
        #expect(t.outstanding.map { $0.meta.agentId } == ["c"])
        #expect(t.endedCount == 1)
    }

    @Test("一隻都沒有時，收合那一行不該出現")
    func emptyProducesNothing() {
        let t = AgentTally([])
        #expect(t.outstanding.isEmpty)
        #expect(t.endedCount == 0)
        #expect(t.collapsedText == nil)
    }

    @Test("全部都還在跑時，也不該出現收合那一行")
    func allOutstandingProducesNoCollapse() {
        #expect(AgentTally([node("a", .likelyRunning)]).collapsedText == nil)
    }

    @Test("⚠️ 收合那一行寫「已結束」不是「已完成」 —— 我們不知道它是做完還是死掉")
    func saysEndedNotCompleted() {
        let text = try! #require(AgentTally([node("a", .unknown), node("b", .finished)]).collapsedText)
        #expect(text.contains("已結束"))
        #expect(text.contains("已完成") == false,
                "宣稱『已完成』需要證據，而這一版沒有去讀那個證據")
        #expect(text.contains("2"))
    }
}
