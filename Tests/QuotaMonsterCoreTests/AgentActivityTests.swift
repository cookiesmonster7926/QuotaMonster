import Testing
import Foundation
@testable import QuotaMonsterCore

/// 一般 Agent subagent 到底還在不在跑。
///
/// ### 為什麼需要一個**代理**量測
/// 〔實測 2026-09-22〕workflow subagent 有 `journal.jsonl`
/// （`started` / `result` / `failed` / `launched`），執行狀態是**讀到的**。
/// 一般 Agent subagent 只有 `.meta.json`，內容是
/// `agentType` / `description` / `toolUseId` / `spawnDepth` / `requestShape` ——
/// **一個狀態欄位都沒有**，也沒有 journal。磁碟上真的沒有那個資訊。
///
/// 唯一還在動的東西是它的 transcript：〔實測〕一個正在跑的 agent 五秒內
/// 從 286KB 長到 306KB。所以「最近有寫入」是唯一可用的訊號。
///
/// ### ⚠️ 這是代理量測，不是量測，而且方向會反過來錯
/// - 還在想、但一直沒寫字的 agent → 被說成停了（少報）
/// - 已經被殺掉的 agent → 被說成還在跑，最長一個窗口（**謊報**）
///
/// 原本的設計是「寧可少報，不要謊報」（`AgentRunState.unknown`），
/// 使用者 2026-09-22 拍板換成「代理量測 + 誤差已知」。
/// 所以它有**自己的 case**，不與 journal 讀到的 `.running` 混在一起 ——
/// 把推論寫成量測正是這個 repo 最在意的那件事。
@Suite("Agent 活動代理")
struct AgentActivityTests {

    let now = Fixture.now

    @Test("窗口是 120 秒 —— 那個數字是量出來的")
    func windowIsMeasured() {
        // 〔實測 2026-09-22，32 個 agent transcript／4,687 個相鄰寫入間隔〕
        //   中位數 0.4s、p90 4.5s、p99 57.6s
        //   >60s 佔 0.96%、**>120s 佔 0.45%**、>180s 佔 0.24%
        // 120 秒的意思是：約 0.45% 的觀測時刻會把「還在想」誤判成「停了」。
        #expect(AgentActivity.window == 120)
    }

    @Test("窗口內有寫入 → 推定還在跑")
    func recentWriteMeansLikelyRunning() {
        #expect(AgentActivity.isLikelyRunning(lastWrite: now.addingTimeInterval(-1), now: now))
        #expect(AgentActivity.isLikelyRunning(lastWrite: now.addingTimeInterval(-119), now: now))
    }

    @Test("窗口外 → 不推定（回 unknown，不是回 finished）")
    func staleWriteMeansUnknown() {
        #expect(AgentActivity.isLikelyRunning(lastWrite: now.addingTimeInterval(-121), now: now) == false)
        #expect(AgentActivity.isLikelyRunning(lastWrite: now.addingTimeInterval(-9999), now: now) == false)
    }

    @Test("讀不到寫入時間 → 不推定。**不存在不等於停了**")
    func missingWriteIsNotEvidence() {
        #expect(AgentActivity.isLikelyRunning(lastWrite: nil, now: now) == false)
    }

    @Test("寫入時間在未來（時鐘往回跳）算還在跑 —— 猜錯的方向要選訊號還在")
    func futureWriteCountsAsRunning() {
        #expect(AgentActivity.isLikelyRunning(lastWrite: now.addingTimeInterval(60), now: now))
    }

    // ── 不可以與 journal 讀到的那個混在一起 ────────────────────

    @Test("likelyRunning 與 running 是不同的狀態")
    func likelyIsNotTheSameAsRunning() {
        #expect(AgentRunState.likelyRunning != AgentRunState.running)
    }

    @Test("在跑的總數把兩種都算進去，但**分得出來**哪些是推定的")
    func countsSeparateEvidenceFromInference() {
        func node(_ id: String, _ state: AgentRunState) -> AgentNode {
            AgentNode(meta: AgentMeta(agentId: id, agentType: "t", description: "d",
                                      spawnDepth: 1),
                      runState: state, children: [])
        }
        let tree = AgentTree(sessionId: "s", agents: [node("a", .running), node("b", .likelyRunning),
                                      node("c", .unknown), node("d", .finished)],
                             workflows: [])
        #expect(tree.runningAgentCount == 2, "兩種在跑的都要算進去")
        #expect(tree.likelyRunningAgentCount == 1, "但要說得出其中幾隻是推定的")
    }
}
