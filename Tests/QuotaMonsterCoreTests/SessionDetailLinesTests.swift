import Testing
import Foundation
@testable import QuotaMonsterCore

/// 面板的 session 列「畫了幾行細節」—— 高度估算與畫面必須用同一個答案。
///
/// ### 為什麼需要它
/// 〔實測 2026-10-19，使用者截圖〕有一個 session 底下 27 個已完成的 agent，
/// `PanelView.estimatedHeight` 用 `tree.agents.count` 估成 27 行，
/// 但 `SessionRow` 實際只畫「還在跑的」＋一行收合 —— 清單被撐出約 490pt 的空白，
/// 面板高過螢幕，頂端被切掉。兩邊各數一次、數法不同。
@Suite("session 細節行數")
struct SessionDetailLinesTests {

    func node(_ id: String, _ state: AgentRunState,
              _ outcome: AgentOutcome.Kind? = nil) -> AgentNode {
        AgentNode(meta: AgentMeta(agentId: id, agentType: "general-purpose",
                                  description: "d-\(id)", spawnDepth: 1),
                  runState: state, outcome: outcome, children: [])
    }

    @Test("27 個已完成的 agent 只佔一行（收合那一行）")
    func finishedAgentsCollapseToOneLine() {
        let agents = (0..<27).map { node("a\($0)", .finished, .completed) }
        let tree = AgentTree(sessionId: "s", agents: agents, workflows: [])
        #expect(tree.detailLineCount == 1)
    }

    @Test("還在跑的各自一行，加上一行收合")
    func outstandingPlusCollapsed() {
        let agents = [node("a", .running), node("b", .finished, .completed),
                      node("c", .finished, .completed)]
        let tree = AgentTree(sessionId: "s", agents: agents, workflows: [])
        #expect(tree.detailLineCount == 2)
    }

    @Test("沒有任何 agent 與 workflow 就是零行")
    func empty() {
        #expect(AgentTree(sessionId: "s", agents: [], workflows: []).detailLineCount == 0)
    }
}
