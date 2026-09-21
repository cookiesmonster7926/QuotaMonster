import Testing
import Foundation
@testable import QuotaMonsterCore

/// 「這個 workflow 走到哪一階段了」是從哪裡推出來的。
///
/// ⚠️ 原本的答案是 **agentId 字典序最小那隻的 phase**，而 agentId 是隨機 hex
/// （`a` + 16 個 hex），字典序與 spawn 順序無關。〔實測 2026-09-19〕掃這台機器
/// 36 個 workflow，「今天的值」與「真正最早 spawn 那隻的 phase」15 一致、15 不一致。
///
/// **正確的來源是 journal.jsonl 的行序** —— 它是 append-only，而且〔實測〕
/// 343/343 個 `started` 行都帶 `phase` 欄位。導出值層級的驗證：
/// 36/36 個 workflow 的「最後一行 started 的 phase」＝「時間戳最大那隻的 phase」。
@Suite("AgentTreeBuilder — 階段是從 journal 的行序來的")
struct WorkflowPhaseTests {

    let sessionId = "11111111-2222-3333-4444-555555555555"
    let workflowId = "wf_test01"

    /// 在暫存目錄裡造一個 workflow。**`spawns` 的順序就是寫進 journal 的順序。**
    ///
    /// - Parameters:
    ///   - writeJournal: false 代表 journal 讀不到（目錄剛建好、或讀檔失敗）。
    ///   - stale: 這些 agent 的 `agent-<id>.jsonl` 會被設成比 session 還舊，
    ///     於是被 `AgentTreeBuilder.isFresh` 濾掉 —— 模擬「journal 已經有它，
    ///     但存活閘還看不到它」那個窗口。
    func group(_ spawns: [(id: String, phase: String?)],
               writeJournal: Bool = true,
               stale: Set<String> = [],
               runState: String? = nil) throws -> WorkflowGroup? {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("qm-phase-\(UUID().uuidString)")
        let sessionDir = root.appendingPathComponent(sessionId)
        let wfDir = sessionDir.appendingPathComponent("subagents/workflows/\(workflowId)")
        try fm.createDirectory(at: wfDir, withIntermediateDirectories: true)

        let sessionStart = Date().addingTimeInterval(-3600)
        var lines: [String] = [#"{"type":"launched"}"#]

        for s in spawns {
            let meta: [String: Any] = [
                "agentType": "workflow-subagent",
                "description": "t",
                "spawnDepth": 1,
                // ⚠️ meta 也有 phase，而且〔實測 342/342〕與 journal 一致。
                // 這裡刻意把它填對 —— 測試要釘的是「挑哪一隻」，不是「phase 從哪個檔案讀」。
                "workflowPhase": s.phase as Any,
            ]
            try JSONSerialization.data(withJSONObject: meta)
                .write(to: wfDir.appendingPathComponent("agent-\(s.id).meta.json"))

            // 存活閘看的是這個檔案的 mtime。
            let jsonl = wfDir.appendingPathComponent("agent-\(s.id).jsonl")
            try Data("{}".utf8).write(to: jsonl)
            if stale.contains(s.id) {
                try fm.setAttributes([.modificationDate: sessionStart.addingTimeInterval(-60)],
                                     ofItemAtPath: jsonl.path)
            }

            var line: [String: Any] = ["type": "started", "agentId": s.id]
            if let p = s.phase { line["phase"] = p }
            lines.append(String(decoding: try JSONSerialization.data(withJSONObject: line),
                                as: UTF8.self))
        }

        if writeJournal {
            try lines.joined(separator: "\n")
                .write(to: wfDir.appendingPathComponent("journal.jsonl"),
                       atomically: true, encoding: .utf8)
        }

        if let runState {
            let runs = sessionDir.appendingPathComponent("workflows")
            try fm.createDirectory(at: runs, withIntermediateDirectories: true)
            try runState.write(to: runs.appendingPathComponent("\(workflowId).json"),
                               atomically: true, encoding: .utf8)
        }

        let transcript = root.appendingPathComponent("\(sessionId).jsonl")
        try Data().write(to: transcript)
        let paths = SessionPaths(transcript: transcript, sessionDirectory: sessionDir)
        return AgentTreeBuilder().build(paths: paths, sessionId: sessionId,
                                        sessionStartedAt: sessionStart)
            .workflows.first
    }

    @Test("階段照 spawn 順序取最後一個 —— 不是 agentId 字典序最小的那隻")
    func latestSpawnWins() throws {
        // aaa1 先 spawn（Recon）、zzz9 後 spawn（Verify）。
        // 舊實作取 min(agentId) = aaa1 → 回 Recon。
        let wf = try #require(try group([("aaa1", "Recon"), ("zzz9", "Verify")]))
        #expect(wf.latestPhase == "Verify")
    }

    @Test("反過來也一樣 —— agentId 在任何方向上都不是排序鍵")
    func latestSpawnWinsWhenIdOrderIsReversed() throws {
        // ⚠️ 這一則今天是**綠**的（min(agentId) = aaa1 剛好就是最後 spawn 的那隻）。
        // 它單獨沒有價值，與上一則**綁在一起**才釘得住：只改成「由大到小排」
        // 的假修法會讓上一則變綠、這一則變紅。
        let wf = try #require(try group([("zzz9", "Recon"), ("aaa1", "Verify")]))
        #expect(wf.latestPhase == "Verify")
    }

    @Test("字典序最小的夾在中間 —— 取 min 與取 max 兩種錯法都要紅")
    func neitherMinNorMaxAgentIdIsTheAnswer() throws {
        // 字典序 aaa < abb < bbb：取 min 回 P2、取 max 回 P1，正解是 P3。
        // 刻意用 abb 而不是 ccc —— 用 ccc 的話「取 max」剛好會對，漏掉一半。
        let wf = try #require(try group([("bbb", "P1"), ("aaa", "P2"), ("abb", "P3")]))
        #expect(wf.latestPhase == "P3")
    }

    @Test("journal 讀不到時不准退回 meta 的 phase —— 那正是要修掉的那個擲骰子")
    func missingJournalDoesNotFallBackToMeta() throws {
        let wf = try #require(try group([("bbb", "P1"), ("aaa", "P2"), ("abb", "P3")],
                                        writeJournal: false))
        #expect(wf.latestPhase == nil)
        // 同時釘住「讀不到 phase ≠ 整組憑空消失」。
        #expect(wf.total == 3)
    }

    @Test("新階段的 agent 還沒通過存活閘時，階段仍然要跟上 journal")
    func phaseLeadsTheFreshnessGate() throws {
        // `isFresh` 看的是 `agent-<id>.jsonl`，而它比 `.meta.json` 晚落地
        // 〔實測 n=343，全部晚，中位 0.092s、最大 0.431s〕。所以有一個窗口是
        // 「journal 已經記了新階段，但那隻還沒進 metas」。
        // 這裡選**領先**而不是落後：phase 講的是「進度走到哪」。
        let wf = try #require(try group([("aaa", "Recon"), ("zzz", "Verify")],
                                        stale: ["zzz"]))
        #expect(wf.latestPhase == "Verify")
        #expect(wf.total == 1)
    }
    // ── 跑了多久 ────────────────────────────────────────────────

    @Test("runDuration 來自 run 狀態檔，不是檔案時間")
    func runDurationComesFromTheRunStateFile() throws {
        // ⚠️ **這一則是「builder 漏傳」的唯一守門員** —— 那是整個 diff 裡唯一一個
        // 漏了會編譯通過、其餘全綠的地方。
        //
        // 它同時抓「乾脆用檔案時間算」：這個暫存目錄裡所有檔案的時間跨距都是
        // 毫秒級，任何以檔案時間為來源的實作在這裡拿到 ≈0 → 紅。
        let wf = try #require(try group(
            [("aaa", "Recon"), ("zzz", "Verify")],
            runState: #"{"runId":"wf_test01","status":"killed","durationMs":345160}"#))
        #expect(wf.runDuration == 345.16)
    }

    @Test("還在跑的 workflow 沒有 run 狀態檔 —— runDuration 是 nil，不是 0")
    func runningWorkflowHasNoDuration() throws {
        let wf = try #require(try group([("aaa", "Recon"), ("zzz", "Verify")]))
        #expect(wf.runDuration == nil)
        // 順便確認既有的 missingRunFileFallsBackToJournal 語意沒被動到。
        #expect(wf.total == 2)
    }

}
