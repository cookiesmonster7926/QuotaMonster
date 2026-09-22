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
/// ### ⚠️ 「已完成」與「狀態不明」是兩格，不是一格
/// 這裡原本只能說「已結束 N 隻」，因為讀真實下場要掃 13MB 的母 transcript。
/// 〔2026-09-22 做了〕`TranscriptWatcher` 只解析新增的行，所以現在讀得到。
///
/// ⚠️ **但讀不到的那些必須留在自己的一格。** 那是第二節拒絕 2：
/// 沒有狀態就是不知道下場，併進「已完成」等於在面板上宣告一件我們不知道的事。
/// 實測 18.5% 的背景 agent 從來沒有終端記錄，所以這一格不是理論上的。
@Suite("Agent 收合")
struct AgentTallyTests {

    func node(_ id: String, _ state: AgentRunState,
              _ outcome: AgentOutcome.Kind? = nil,
              children: [AgentNode] = []) -> AgentNode {
        AgentNode(meta: AgentMeta(agentId: id, agentType: "general-purpose",
                                  description: "d-\(id)", spawnDepth: 1),
                  runState: state, outcome: outcome, children: children)
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

    // ── 真實下場 ───────────────────────────────────────────────

    @Test("讀到下場的就說「已完成」—— 這一行原本只敢說「已結束」")
    func saysCompletedWhenTheEvidenceWasRead() throws {
        // ⚠️ 這一則取代了原本的 `saysEndedNotCompleted`。那一則釘的是
        // 「**不可以**說已完成，因為這一版沒有去讀那個證據」——
        // 〔2026-09-22〕證據去讀了，所以它的前提沒了。
        // 它不是被刪掉：保護的東西搬到下面兩則（沒讀到的不可以併進來）。
        let t = AgentTally([node("a", .finished, .completed), node("b", .finished, .completed)])
        let text = try #require(t.collapsedText)
        #expect(text == "2 個 agent 已完成")
    }

    @Test("⚠️ 沒讀到下場的自成一格 —— 絕對不可以併進「已完成」")
    func unknownOutcomesAreTheirOwnBucket() throws {
        let t = AgentTally([node("a", .finished, .completed), node("b", .unknown, nil)])
        #expect(t.count(.completed) == 1)
        #expect(t.unknownCount == 1)
        let text = try #require(t.collapsedText)
        #expect(text == "1 個 agent 已完成 · 1 個狀態不明")
    }

    @Test("失敗與被停止各自一格，順序固定")
    func eachOutcomeHasItsOwnBucketInAFixedOrder() throws {
        let t = AgentTally([
            node("a", .finished, .killed), node("b", .finished, .failed),
            node("c", .finished, .completed), node("d", .unknown, nil),
        ])
        // 順序固定，那一行才不會因為數量變化而左右跳動。
        #expect(try #require(t.collapsedText)
            == "1 個 agent 已完成 · 1 個失敗 · 1 個已停止 · 1 個狀態不明")
    }

    @Test("一個成功都沒有時，那一行仍然說得出自己在講什麼")
    func theNounFollowsTheFirstBucket() throws {
        let t = AgentTally([node("a", .finished, .failed)])
        #expect(try #require(t.collapsedText) == "1 個 agent 失敗")
    }

    @Test("⚠️ 用詞與 workflow 那一行逐字一樣 —— 真的去問 WorkflowTally，不是抄一份字串進來")
    func theVocabularyMatchesTheWorkflowLine() {
        // ⚠️ **這一則原本什麼都沒保護。**〔code review 2026-09-22〕它把
        // 「已完成 / 失敗 / 已停止 / 狀態不明」四個字硬寫在測試裡，然後斷言
        // `AgentTally` 含有它們 —— 那只證明 `AgentTally` 抄對了測試，
        // 不證明兩個 tally 講同一套話。`WorkflowTally` 改掉任何一個字，它照樣綠。
        // 而它的註解還寫著「這一則是唯一會在它們漂開時變紅的東西」——
        // 一句把自己說成守門員的假話，比沒有守門員更糟。
        //
        // 現在它真的去問 WorkflowTally 要那四個詞。
        let wf = WorkflowTally([
            group("w1", "completed"), group("w2", "failed"),
            group("w3", "killed"), group("w4", nil),
        ]).collapsed.map(\.text)
        let ag = AgentTally([
            node("a", .finished, .completed), node("b", .finished, .failed),
            node("c", .finished, .killed), node("d", .unknown, nil),
        ]).collapsed.map(\.text)

        #expect(wf.count == 4)
        #expect(ag.count == 4)
        // 兩邊逐格比對：只有名詞（workflow / agent）那一個字可以不同。
        for (w, a) in zip(wf, ag) {
            #expect(w.replacingOccurrences(of: " workflow ", with: " agent ") == a,
                    "兩個 tally 的用詞漂開了：workflow 說「\(w)」，agent 說「\(a)」")
        }
    }

    /// 造一個已經收尾的 workflow 群組。
    func group(_ id: String, _ status: String?) -> WorkflowGroup {
        WorkflowGroup(workflowId: id, latestPhase: nil,
                      agents: [AgentNode(meta: AgentMeta(agentId: "\(id)-a",
                                                         agentType: "workflow-subagent",
                                                         description: "d", spawnDepth: 1),
                                         runState: .finished)],
                      runStatus: status, runDuration: nil)
    }

    @Test("還在跑的那些不進任何一格")
    func runningAgentsAreNotCounted() {
        let t = AgentTally([node("a", .likelyRunning, nil), node("b", .running, nil)])
        #expect(t.endedCount == 0)
        #expect(t.collapsedText == nil)
    }
}
