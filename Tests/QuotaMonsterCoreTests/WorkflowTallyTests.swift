import Testing
import Foundation
@testable import QuotaMonsterCore

/// 面板收合那一行的分類。
///
/// ⚠️ 原本那一行寫「另有 N 個 workflow 已完成」，把失敗的也算進去 ——
/// 而 T2 刻意不對失敗的批次出聲，所以那一行是它唯一的落腳處。
@Suite("WorkflowTally — 那些 workflow 各自是什麼下場")
struct WorkflowTallyTests {

    func group(_ id: String, running: Int = 0, finished: Int = 0,
               runStatus: String? = nil) -> WorkflowGroup {
        func node(_ i: Int, _ state: AgentRunState) -> AgentNode {
            AgentNode(meta: AgentMeta(agentId: "\(id)-\(i)", agentType: "workflow-subagent",
                                      description: "t", spawnDepth: 1, workflowPhase: "P"),
                      runState: state)
        }
        let agents = (0..<running).map { node($0, .running) }
            + (0..<finished).map { node(running + $0, .finished) }
        return WorkflowGroup(workflowId: id, latestPhase: "P",
                             agents: agents, runStatus: runStatus)
    }

    @Test("四種下場各自分開 —— 全部都是磁碟上真的出現過的")
    func allFourOutcomes() {
        let t = WorkflowTally([
            group("a", finished: 3, runStatus: "completed"),
            group("b", finished: 2, runStatus: "failed"),
            group("c", finished: 5, runStatus: "killed"),
            group("d", finished: 1),                          // 沒有狀態檔
            group("e", running: 2),                           // 還在跑
        ])
        #expect(t.running == 1)
        #expect(t.count(.completed) == 1)
        #expect(t.count(.failed) == 1)
        #expect(t.count(.stopped) == 1)
        #expect(t.count(.unknown) == 1)
        #expect(t.settled == 4)
    }

    @Test("⚠️ 讀不到狀態的不可以算進「已完成」")
    func unknownIsNotCompleted() {
        // 這一格是「不存在 ≠ 那個狀態不成立」。把 nil 併進 completed 的實作
        // 會在面板上宣告一件它不知道的事。
        let t = WorkflowTally([group("a", finished: 3)])
        #expect(t.count(.unknown) == 1)
        #expect(t.count(.completed) == 0)
    }

    @Test("被你停掉的不是失敗 —— 你知道它為什麼停")
    func killedIsNotFailed() {
        let t = WorkflowTally([group("a", finished: 3, runStatus: "killed")])
        #expect(t.count(.stopped) == 1)
        #expect(t.count(.failed) == 0)
    }

    @Test("還在跑的不算下場 —— 它自己有一列，不進收合那一行")
    func runningIsNotSettled() {
        let t = WorkflowTally([group("a", running: 1, finished: 2, runStatus: nil)])
        #expect(t.running == 1)
        #expect(t.settled == 0)
        #expect(t.collapsed.isEmpty)
    }

    @Test("收合那一行：只有已完成時的措辭")
    func captionForCompletedOnly() {
        let t = WorkflowTally([group("a", finished: 1, runStatus: "completed"),
                               group("b", finished: 1, runStatus: "completed")])
        #expect(t.collapsed.map(\.text) == ["2 個 workflow 已完成"])
    }

    @Test("收合那一行：有失敗時要看得出來，而且順序固定")
    func captionShowsFailures() {
        // 順序固定（已完成 → 失敗 → 已停止 → 狀態不明），那一行才不會
        // 因為數量變化而左右跳動。
        let t = WorkflowTally([group("a", finished: 1, runStatus: "completed"),
                               group("b", finished: 1, runStatus: "failed"),
                               group("c", finished: 1, runStatus: "killed"),
                               group("d", finished: 1)])
        #expect(t.collapsed.map(\.text)
                == ["1 個 workflow 已完成", "1 個失敗", "1 個已停止", "1 個狀態不明"])
        #expect(t.collapsed.map(\.outcome) == [.completed, .failed, .stopped, .unknown])
    }

    @Test("只有失敗時，「workflow」這個字要跟著第一格走")
    func nounFollowsTheFirstBucket() {
        // 抓「把 workflow 寫死在已完成那一格」的實作 —— 那種版本在
        // 一個成功都沒有的時候會印出「另有 1 個失敗」，少掉名詞。
        let t = WorkflowTally([group("a", finished: 1, runStatus: "failed")])
        #expect(t.collapsed.map(\.text) == ["1 個 workflow 失敗"])
    }

    @Test("空的不產生任何一行")
    func emptyProducesNothing() {
        #expect(WorkflowTally([]).collapsed.isEmpty)
    }
}
