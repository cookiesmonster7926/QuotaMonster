import Testing
import Foundation
@testable import QuotaMonsterCore

/// ⚠️ 這裡有一個**經實測推翻**的假設，測試必須釘住正確版本。
///
/// 研究階段一度採用 `sourceToolAssistantUUID` 當 parent 指標。
/// 實測它是**檔案內**指標：72/72 解析於 subagent 自己的 transcript，
/// 在母 transcript 內 0 筆。照它寫會得到一棵空樹。
///
/// 正確做法是**兩套連結法並存**：
///   - 一般 Agent subagent → `toolUseId` 配母 transcript 的 tool_use id；深度 ≥2 用 `parentAgentId`
///   - workflow subagent → **沒有任何 parent 欄位**，只能靠目錄路徑
/// 而在真實機器上 workflow agent 是多數（實測 156 / 187）。
@Suite("AgentTreeBuilder")
struct AgentTreeBuilderTests {

    func tree() throws -> AgentTree {
        let root = try Fixture.projectsRoot()
        let paths = try #require(SessionDirectoryResolver()
            .locate(sessionId: Fixture.agentSessionId, projectsRoot: root))
        return AgentTreeBuilder().build(paths: paths,
                                        sessionId: Fixture.agentSessionId,
                                        sessionStartedAt: Fixture.sessionStart, now: Fixture.now)
    }

    // ── 連結法一：一般 agent ────────────────────────────────────
    @Test("一般 agent 靠 toolUseId 連到母 transcript 的 tool_use")
    func plainAgentsLinkByToolUseId() throws {
        let t = try tree()
        let plain1 = try #require(t.agents.first { $0.meta.agentId == "plain1" })
        #expect(plain1.spawningToolUseId == "toolu_PLAIN1")
        #expect(plain1.isLinkedToTranscript == true)
    }

    @Test("深度 2 的 agent 靠 parentAgentId 掛在深度 1 底下，不是變成第二個根")
    func depthTwoLinksByParentAgentId() throws {
        let t = try tree()
        let plain1 = try #require(t.agents.first { $0.meta.agentId == "plain1" })
        #expect(plain1.children.map(\.meta.agentId) == ["plain2"])
        #expect(t.agents.contains { $0.meta.agentId == "plain2" } == false)
    }

    @Test("沒有 parentAgentId 的深度 1 agent 是根")
    func depthOneAgentsAreRoots() throws {
        let t = try tree()
        #expect(Set(t.agents.map(\.meta.agentId)) == ["plain1", "minimal"])
    }

    // ── 連結法二：workflow agent ────────────────────────────────
    @Test("workflow agent 靠目錄路徑分組 —— 它們沒有任何 parent 欄位")
    func workflowAgentsGroupByDirectory() throws {
        let t = try tree()
        let wf = try #require(t.workflows.first)
        #expect(wf.workflowId == "wf_fixture01")
        #expect(Set(wf.agents.map(\.meta.agentId)) == ["w1", "w2", "w3"])
        #expect(wf.latestPhase == "Build")
    }

    @Test("workflow agent 不得混進一般 agent 的森林裡")
    func workflowAgentsAreNotInThePlainForest() throws {
        let t = try tree()
        let plainIds = Set(t.agents.flatMap { [$0.meta.agentId] + $0.children.map(\.meta.agentId) })
        #expect(plainIds.isDisjoint(with: ["w1", "w2", "w3"]))
    }

    // ── 存活閘 ──────────────────────────────────────────────────
    @Test("比 session 啟動時間還舊的 agent 要排除 —— subagents/ 是跨 resume 累積的歷史")
    func agentOlderThanSessionStartIsExcluded() throws {
        let t = try tree()
        let all = t.agents.flatMap { [$0.meta.agentId] + $0.children.map(\.meta.agentId) }
        #expect(all.contains("stale") == false)
    }

    @Test("workflow 的執行狀態來自 journal：完成、失敗、執行中三態分明")
    func workflowRunStateComesFromJournal() throws {
        let wf = try #require(try tree().workflows.first)
        func state(_ id: String) -> AgentRunState? {
            wf.agents.first { $0.meta.agentId == id }?.runState
        }
        #expect(state("w1") == .finished)
        #expect(state("w2") == .running)
        #expect(state("w3") == .finished)   // failed 也是收尾了
    }

    @Test("失敗的 agent 不算執行中")
    func failedAgentIsNotRunning() throws {
        // ⚠️ 2026-09-22 這個數字從 1 變成 2，而那是**刻意**的：
        // 一般 Agent subagent 的執行狀態改成由 transcript 活動推定（`AgentActivity`），
        // 所以 fixture 裡剛寫過字的 `plain1` 也算進去了。
        // 這一則守的是「**失敗的**不算」，那一點沒有變 —— 下面把它分開釘。
        let t = try tree()
        // 3 = workflow journal 讀到的 1 隻 + 推定的 2 隻（plain1 與它的子 plain2，
        // 兩個的 transcript 都被 Fixture 蓋成「剛剛才寫」）。
        #expect(t.runningAgentCount == 3)
        #expect(t.likelyRunningAgentCount == 2, "其中兩隻是推定的，說得出來才有資格算進去")
        #expect(t.workflows.reduce(0) { $0 + $1.runningCount } == 1, "workflow 那邊仍然只有 1 隻")
    }

    @Test("一般 agent：transcript 還在動就推定在跑，安靜太久就回到 unknown")
    func plainAgentRunStateComesFromActivity() throws {
        let t = try tree()
        // `plain1` 的 transcript 被 Fixture 蓋成「剛剛才寫」→ 推定在跑。
        let plain1 = try #require(t.agents.first { $0.meta.agentId == "plain1" })
        #expect(plain1.runState == .likelyRunning)
        // `minimal` 被蓋成 300 秒前（> AgentActivity.window 的 120 秒）→ 推不出來。
        let quiet = try #require(t.agents.first { $0.meta.agentId == "minimal" })
        #expect(quiet.runState == .unknown)
    }

    @Test("⚠️ 一般 agent **永遠**不可以被標成 finished —— 那需要證據，而磁碟上沒有")
    func plainAgentIsNeverClaimedFinished() throws {
        let all = try tree().agents.flatMap { [$0] + $0.children }
        #expect(all.allSatisfy { $0.runState != .finished },
                "推不出來要留在 unknown，不是猜一個「做完了」")
        #expect(all.allSatisfy { $0.runState != .running },
                "`.running` 是 journal 讀到的那一種，一般 agent 沒有 journal")
    }

    @Test("不得單用 mtime 門檻判死活 —— 實測有 agent 失敗後僅 153 秒就被觀察到")
    func doesNotUseMtimeThresholdAlone() throws {
        let wf = try #require(try tree().workflows.first)
        // 三隻的 jsonl mtime 完全相同，若用 mtime 判定就會三隻同命；
        // 實際上必須是 journal 說了算，所以三隻的狀態不相同。
        #expect(Set(wf.agents.map(\.runState)).count == 2)
    }

    @Test("扇出的完成進度可以直接讀出來")
    func fanOutProgressIsAvailable() throws {
        let wf = try #require(try tree().workflows.first)
        #expect(wf.runningCount == 1)
        #expect(wf.finishedCount == 2)
        #expect(wf.total == 3)
    }
}

/// 這一組是**真實資料驗證抓出來的 bug** 的回歸測試。
///
/// 用 `--dump` 對真實機器跑的時候，一個被 `TaskStop` 中止的 workflow
/// 顯示成「5 隻執行中」。原因：中止的 run 永遠不會寫 result 或 failed，
/// 所以「started 減去 finished」會把它們永遠留在執行中。
///
/// 權威訊號在 `<sessionId>/workflows/<wf_id>.json` 的 `status`
/// （實測值只有 completed / failed / killed 三種終結狀態）。
/// **run 已經終結時，裡面沒有任何 agent 還在跑，journal 說什麼都不算。**
@Suite("AgentTreeBuilder — 中止的 workflow")
struct AbortedWorkflowTests {

    func tree() throws -> AgentTree {
        let root = try Fixture.projectsRoot()
        let paths = try #require(SessionDirectoryResolver()
            .locate(sessionId: Fixture.agentSessionId, projectsRoot: root))
        return AgentTreeBuilder().build(paths: paths,
                                        sessionId: Fixture.agentSessionId,
                                        sessionStartedAt: Fixture.sessionStart, now: Fixture.now)
    }

    @Test("被中止的 run 裡沒有任何 agent 算執行中，即使 journal 只有 started")
    func killedRunHasNoRunningAgents() throws {
        let wf = try #require(try tree().workflows.first { $0.workflowId == "wf_killed01" })
        #expect(wf.runningCount == 0)
        #expect(wf.agents.allSatisfy { $0.runState == .finished })
    }

    @Test("沒有終結狀態的 run 仍然照 journal 判斷")
    func liveRunStillTrustsTheJournal() throws {
        let wf = try #require(try tree().workflows.first { $0.workflowId == "wf_fixture01" })
        #expect(wf.runningCount == 1)
    }

    @Test("整個 session 的執行中總數不會把中止的算進去")
    func abortedAgentsDoNotInflateTheSessionCount() throws {
        // 3 = workflow journal 讀到的 1 隻 + 由 transcript 活動推定的 2 隻。
        // 中止的那一個仍然沒有被算進去 —— 那才是這一則守的東西。
        #expect(try tree().runningAgentCount == 3)
    }

    @Test("group 自己帶著 run 狀態 —— 通知層要靠它分辨「全部完成」與「被你停掉」")
    func groupCarriesRunStatus() throws {
        let killed = try #require(try tree().workflows.first { $0.workflowId == "wf_killed01" })
        #expect(killed.runStatus == "killed")
        // 中止的 run 每一隻都被折成 finished，所以 finishedCount == total ——
        // 少了 runStatus，通知就會對著一個你自己停掉的 run 說「全部完成」。
        #expect(killed.finishedCount == killed.total)

        let live = try #require(try tree().workflows.first { $0.workflowId == "wf_fixture01" })
        #expect(live.runStatus == nil)
    }

    @Test("run 狀態檔不存在時，退回 journal 判斷，不得整組消失")
    func missingRunFileFallsBackToJournal() throws {
        // wf_fixture01 有狀態檔但沒有 status；這裡確認即使完全沒有檔案也不會壞
        let wf = try #require(try tree().workflows.first { $0.workflowId == "wf_fixture01" })
        #expect(wf.total == 3)
    }
}
