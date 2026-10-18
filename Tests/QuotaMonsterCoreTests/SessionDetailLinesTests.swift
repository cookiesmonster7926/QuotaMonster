import Testing
import Foundation
@testable import QuotaMonsterCore

/// 面板的 session 列「畫了幾行細節」—— 高度估算與畫面必須用同一個答案。
///
/// ### 為什麼需要它
/// 〔實測 2026-10-19，使用者截圖〕有一個 session 的收合那一行寫著 27 個 agent 已完成；
/// 面板高過螢幕，頂端被切掉。
///
/// 〔推論，讀碼〕原因是兩邊各數一次、數法不同：`PanelView.estimatedHeight` 用
/// `tree.agents.count`（含已完成的）估成 27 行，`SessionRow` 實際只畫「還在跑的」＋
/// 一行收合，也就是 1 行。多估 26 × `RowMetrics.detailLine`（18pt）＝ 468pt。
/// 這個數字是算的，不是從截圖量的。
///
/// ### 怎麼守
/// 現在兩邊都從 `AgentTree.detailLines` 拿：`SessionRow` 照它畫，
/// `PanelView` 用它的 `count`。App 層的那一半測不到（它要 AppKit），
/// 所以這裡把「畫哪些行」整套釘住，連 `AgentTally`／`WorkflowTally` 的分類規則
/// 怎麼組合成行數也一起釘 —— 一個繞過它們、自己數的實作要紅。
@Suite("session 細節行數")
struct SessionDetailLinesTests {

    func node(_ id: String, _ state: AgentRunState,
              _ outcome: AgentOutcome.Kind? = nil,
              children: [AgentNode] = []) -> AgentNode {
        AgentNode(meta: AgentMeta(agentId: id, agentType: "general-purpose",
                                  description: "d-\(id)", spawnDepth: 1),
                  runState: state, outcome: outcome, children: children)
    }

    /// `running` 隻在跑、`finished` 隻已結束的 workflow。
    func workflow(_ id: String, running: Int, finished: Int,
                  runStatus: String? = nil) -> WorkflowGroup {
        let agents = (0..<running).map { node("\(id)-r\($0)", .running) }
            + (0..<finished).map { node("\(id)-f\($0)", .finished, .completed) }
        return WorkflowGroup(workflowId: id, latestPhase: nil,
                             agents: agents, runStatus: runStatus)
    }

    // MARK: - agent 那一半

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

    @Test("只有在跑的、沒有東西可收合：沒有收合那一行")
    func onlyRunningHasNoCollapsedLine() {
        let tree = AgentTree(sessionId: "s",
                             agents: [node("a", .running), node("b", .running)],
                             workflows: [])
        #expect(tree.detailLines.hasCollapsedLine == false)
        #expect(tree.detailLineCount == 2)
    }

    @Test("推定在跑的（.likelyRunning）也有自己一行")
    func likelyRunningHasItsOwnLine() {
        // 一般 subagent 幾乎都是推定的；只數 .running 會把它們估成 0 行。
        let tree = AgentTree(sessionId: "s", agents: [node("a", .likelyRunning)],
                             workflows: [])
        #expect(tree.detailLineCount == 1)
    }

    @Test("巢狀在跑的 child 也有自己一行；結束的 parent 進收合")
    func nestedRunningChildCounts() {
        let parent = node("p", .finished, .completed,
                          children: [node("c", .running)])
        let tree = AgentTree(sessionId: "s", agents: [parent], workflows: [])
        #expect(tree.detailLines.agents.outstanding.map(\.meta.agentId) == ["c"])
        #expect(tree.detailLineCount == 2)
    }

    @Test("只有讀不到下場的已結束 agent：仍然有收合那一行（狀態不明）")
    func unknownOutcomeStillCollapses() {
        let tree = AgentTree(sessionId: "s",
                             agents: [node("a", .finished), node("b", .unknown)],
                             workflows: [])
        #expect(tree.detailLines.hasCollapsedLine)
        #expect(tree.detailLineCount == 1)
    }

    // MARK: - workflow 那一半

    @Test("在跑的 workflow 一行，已結束的 workflow 進收合")
    func liveAndSettledWorkflows() {
        let tree = AgentTree(sessionId: "s", agents: [], workflows: [
            workflow("wf_live", running: 2, finished: 1),
            workflow("wf_done", running: 0, finished: 3, runStatus: "completed"),
        ])
        #expect(tree.detailLines.liveWorkflows.map(\.workflowId) == ["wf_live"])
        #expect(tree.detailLines.hasCollapsedLine)
        #expect(tree.detailLineCount == 2)
    }

    @Test("兩個在跑的 workflow、沒有 agent：兩行")
    func twoLiveWorkflows() {
        let tree = AgentTree(sessionId: "s", agents: [], workflows: [
            workflow("wf_1", running: 1, finished: 0),
            workflow("wf_2", running: 1, finished: 2),
        ])
        #expect(tree.detailLines.hasCollapsedLine == false)
        #expect(tree.detailLineCount == 2)
    }

    @Test("只有已結束的 workflow、沒有 agent：一行收合")
    func onlySettledWorkflows() {
        // 讀不到下場（runStatus nil）的也算沒在跑，一樣進收合。
        let tree = AgentTree(sessionId: "s", agents: [], workflows: [
            workflow("wf_1", running: 0, finished: 2, runStatus: "failed"),
            workflow("wf_2", running: 0, finished: 1),
        ])
        #expect(tree.detailLineCount == 1)
    }

    // MARK: - 兩半合起來

    @Test("workflow 與 agent 都有收合時，共用同一行")
    func collapsedWorkflowAndAgentShareOneLine() {
        // `SessionRow` 把兩邊的收合畫在同一個 HStack 裡，中間用「·」隔開。
        let tree = AgentTree(sessionId: "s",
                             agents: [node("a", .finished, .completed)],
                             workflows: [workflow("wf", running: 0, finished: 1,
                                                  runStatus: "completed")])
        #expect(tree.detailLineCount == 1)
    }

    @Test("全部混在一起")
    func everythingTogether() {
        let tree = AgentTree(sessionId: "s",
                             agents: [node("a", .likelyRunning),
                                      node("b", .finished, .completed,
                                           children: [node("c", .running)]),
                                      node("d", .unknown)],
                             workflows: [workflow("wf_live", running: 1, finished: 0),
                                         workflow("wf_done", running: 0, finished: 1,
                                                  runStatus: "killed")])
        // wf_live、a、c 各一行，加上一行收合（b、d、wf_done）。
        #expect(tree.detailLineCount == 4)
    }

    @Test("沒有任何 agent 與 workflow 就是零行")
    func empty() {
        let tree = AgentTree(sessionId: "s", agents: [], workflows: [])
        #expect(tree.detailLines.hasCollapsedLine == false)
        #expect(tree.detailLineCount == 0)
    }
}
