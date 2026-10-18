import Testing
import Foundation
@testable import QuotaMonsterCore

/// workflow 的 `journal.jsonl` 改走與 transcript 同一套增量游標。
///
/// ### 為什麼
/// `AgentTreeBuilder` 原本每 3 秒把每一個 journal 整份 `String(contentsOf:)` + `split`，
/// 而且是在新鮮度閘**之前** —— 四天前就死掉的 workflow 的 journal 每拍都被重新解析。
///
/// ⚠️ 這裡的 fixture 全部是手寫的合成資料，只模仿真實 journal 的**形狀**
/// （四種 type、每行以換行結尾），內容是編的。
@Suite("WorkflowJournalWatcher — journal 只解析新增的行")
struct WorkflowJournalWatcherTests {

    func file(_ contents: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-jw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("journal.jsonl")
        try Data(contents.utf8).write(to: url)
        return url
    }

    func append(_ text: String, to url: URL) throws {
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd(); try h.write(contentsOf: Data(text.utf8)); try h.close()
    }

    func started(_ id: String, _ phase: String) -> String {
        #"{"type":"started","key":"k-"# + id + #"","agentId":""# + id
            + #"","label":"x","phase":""# + phase + #""}"# + "\n"
    }
    func result(_ id: String) -> String {
        #"{"type":"result","key":"k-"# + id + #"","agentId":""# + id + #"","result":"ok"}"# + "\n"
    }
    func failed(_ id: String) -> String {
        #"{"type":"failed","key":"k-"# + id + #"","agentId":""# + id + #""}"# + "\n"
    }
    let launched = #"{"type":"launched"}"# + "\n"

    // ── 增量 ───────────────────────────────────────────────────

    @Test("後來追加的行累加上去：started、result、failed 都接得上")
    func appendedLinesAccumulate() throws {
        let url = try file(launched + started("a", "Build") + started("b", "Build"))
        var w = WorkflowJournalWatcher()
        #expect(w.update(url).running == ["a", "b"])

        try append(result("a") + failed("b") + started("c", "Audit"), to: url)
        let j = w.update(url)
        #expect(j.running == ["c"])
        #expect(j.finished == ["a", "b"])
        // 順序跨批次也要接得上 —— latestPhase 是行序的函數（規矩 14）。
        #expect(j.spawns.map(\.agentId) == ["a", "b", "c"])
        #expect(j.latestPhase == "Audit")
    }

    @Test("⚠️ 沒有新東西時一行都不重新解析 —— 這一次改動唯一的存在理由")
    func nothingIsReParsedWhenTheJournalHasNotGrown() throws {
        let url = try file(launched + started("a", "Build") + result("a"))
        var w = WorkflowJournalWatcher()
        _ = w.update(url)
        #expect(w.linesIngested == 3)
        for _ in 0..<10 { _ = w.update(url) }
        #expect(w.linesIngested == 3, "每拍整份重新解析 —— 那正是要修掉的")
        #expect(w.update(url).finished == ["a"])
    }

    // ── 寫到一半與 Claude Code 的修補 ───────────────────────────

    @Test("寫到一半的最後一行先不算；Claude Code 補上換行再寫下一筆之後，殘片跳過、下一筆照算")
    func aTornTailIsSkippedOnceClaudeCodeRepairsIt() throws {
        // 〔讀碼 2.1.302〕append 前先看檔尾是不是換行，不是就先補一個 "\n" 再寫這一筆。
        // 所以殘片會變成一行**完整但壞掉**的 JSON —— 跳過它，與整份讀的舊實作一樣。
        let url = try file(launched + started("a", "Build") + #"{"type":"result","agentId":"#)
        var w = WorkflowJournalWatcher()
        #expect(w.update(url).running == ["a"])

        try append("\n" + started("b", "Audit"), to: url)
        let j = w.update(url)
        #expect(j.running == ["a", "b"])
        #expect(j.latestPhase == "Audit")
    }

    // ── 被重寫 ─────────────────────────────────────────────────

    @Test("⚠️ run 被還原時 journal 就地整份重寫 —— 事實整份換掉，不累加")
    func anInPlaceRestoreReplacesTheFacts() throws {
        // 〔讀碼 2.1.302：writeRestored〕重寫的內容是 restoring + 記錄 + restored。
        // 是不是 rename 上去的沒有量到，照最壞的情況：同一個 inode、而且變長了。
        let url = try file(launched + started("old", "Build"))
        var w = WorkflowJournalWatcher()
        #expect(w.update(url).started == ["old"])

        let h = try FileHandle(forWritingTo: url)
        try h.truncate(atOffset: 0)
        try h.write(contentsOf: Data((#"{"type":"restoring"}"# + "\n" + launched
            + started("new1", "Build") + started("new2", "Audit") + result("new1")
            + #"{"type":"restored"}"# + "\n").utf8))
        try h.close()

        let j = w.update(url)
        // 「old」不在新的檔案裡。留著它就是在面板上宣告一件這份記錄已經不再支持的事。
        #expect(j.started == ["new1", "new2"])
        #expect(j.running == ["new2"])
        #expect(j.latestPhase == "Audit")
    }

    @Test("被換成另一個檔案（rename 上去）—— 一樣整份換掉")
    func aReplacedJournalReplacesTheFacts() throws {
        let url = try file(launched + started("old", "Build"))
        var w = WorkflowJournalWatcher()
        _ = w.update(url)
        let replacement = try file(launched + started("new", "Build"))
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: replacement, to: url)
        #expect(w.update(url).started == ["new"])
    }

    @Test("讀不到的那一拍不抹掉已經知道的事")
    func anUnreadableTickKeepsWhatWeKnew() throws {
        let url = try file(launched + started("a", "Build"))
        var w = WorkflowJournalWatcher()
        _ = w.update(url)
        try FileManager.default.removeItem(at: url)
        #expect(w.update(url).started == ["a"])
    }

    // ── 清理 ───────────────────────────────────────────────────

    @Test("sweep 放掉上一輪沒有被問過的，留下有被問過的")
    func sweepDropsWhatWasNotAskedAbout() throws {
        let a = try file(launched + started("a", "Build"))
        let b = try file(launched + started("b", "Build"))
        var w = WorkflowJournalWatcher()
        _ = w.update(a); _ = w.update(b)
        w.sweep()
        #expect(w.watchedCount == 2)

        _ = w.update(a)            // 這一輪只問 a（b 的 workflow 沒過新鮮度閘）
        w.sweep()
        #expect(w.watchedCount == 1)
        // 留下來的那一份，游標也要跟著留下 —— 不然下一拍又整份重讀。
        let before = w.linesIngested
        #expect(w.update(a).started == ["a"])
        #expect(w.linesIngested == before)
    }
}

/// journal 是在新鮮度閘**之後**、經過游標讀的。
@Suite("AgentTreeBuilder — journal 走游標、而且在新鮮度閘之後")
struct AgentTreeBuilderJournalTests {

    let sessionId = "22222222-3333-4444-5555-666666666666"

    /// 造一個 session，裡面一個 workflow、兩隻 agent。
    /// `stale` 為 true 時兩隻的 `agent-<id>.jsonl` 都比 session 舊 —— 一個早就死掉的 workflow。
    func session(stale: Bool) throws -> (paths: SessionPaths, start: Date, now: Date, journal: URL) {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("qm-jtb-\(UUID().uuidString)")
        let sessionDir = root.appendingPathComponent(sessionId)
        let wfDir = sessionDir.appendingPathComponent("subagents/workflows/wf_synth01")
        try fm.createDirectory(at: wfDir, withIntermediateDirectories: true)

        // 檔案是用真實時間建的，所以 now 也用真實時間（理由見 WorkflowPhaseTests）。
        let now = Date()
        let start = now.addingTimeInterval(-3600)
        var journal = #"{"type":"launched"}"# + "\n"
        for id in ["s1", "s2"] {
            try JSONSerialization.data(withJSONObject: [
                "agentType": "workflow-subagent", "description": "t", "spawnDepth": 1,
            ]).write(to: wfDir.appendingPathComponent("agent-\(id).meta.json"))
            let jsonl = wfDir.appendingPathComponent("agent-\(id).jsonl")
            try Data("{}\n".utf8).write(to: jsonl)
            if stale {
                try fm.setAttributes([.modificationDate: start.addingTimeInterval(-86400)],
                                     ofItemAtPath: jsonl.path)
            }
            journal += #"{"type":"started","key":"k","agentId":""# + id + #"","label":"x","phase":"Build"}"# + "\n"
        }
        let journalURL = wfDir.appendingPathComponent("journal.jsonl")
        try Data(journal.utf8).write(to: journalURL)

        let transcript = root.appendingPathComponent("\(sessionId).jsonl")
        try Data().write(to: transcript)
        return (SessionPaths(transcript: transcript, sessionDirectory: sessionDir), start, now, journalURL)
    }

    @Test("活著的 workflow：journal 經過游標，第二拍一行都不重新解析")
    func aLiveJournalIsNotReParsedOnTheNextTick() throws {
        let s = try session(stale: false)
        var journals = WorkflowJournalWatcher()
        let builder = AgentTreeBuilder()

        let first = builder.build(paths: s.paths, sessionId: sessionId, facts: TranscriptFacts(),
                                  journals: &journals, sessionStartedAt: s.start, now: s.now)
        #expect(first.workflows.first?.runningCount == 2)
        let parsed = journals.linesIngested
        #expect(parsed == 3)

        let second = builder.build(paths: s.paths, sessionId: sessionId, facts: TranscriptFacts(),
                                   journals: &journals, sessionStartedAt: s.start, now: s.now)
        #expect(journals.linesIngested == parsed, "第二拍又整份解析了一次")
        // 而且答案一樣 —— 累積的事實沒有因為「沒有新行」而變空。
        #expect(second.workflows.first?.runningCount == 2)
        #expect(second.workflows.first?.latestPhase == "Build")
    }

    @Test("⚠️ 早就死掉的 workflow：它的 journal 一個 byte 都不讀")
    func aDeadWorkflowsJournalIsNeverOpened() throws {
        // 原本 journal 在新鮮度閘**之前**讀，所以死掉的 workflow 的 journal 每拍都被整份解析，
        // 然後整組被閘丟掉 —— 那份工作從來沒有人用過。
        let s = try session(stale: true)
        var journals = WorkflowJournalWatcher()
        let tree = AgentTreeBuilder().build(paths: s.paths, sessionId: sessionId,
                                            facts: TranscriptFacts(), journals: &journals,
                                            sessionStartedAt: s.start, now: s.now)
        #expect(tree.workflows.isEmpty)
        #expect(journals.watchedCount == 0)
        #expect(journals.linesIngested == 0)
    }

    @Test("活著的 workflow 往 journal 追加的行，下一拍接得上")
    func appendedJournalLinesShowUpOnTheNextTick() throws {
        let s = try session(stale: false)
        var journals = WorkflowJournalWatcher()
        let builder = AgentTreeBuilder()
        _ = builder.build(paths: s.paths, sessionId: sessionId, facts: TranscriptFacts(),
                          journals: &journals, sessionStartedAt: s.start, now: s.now)

        let h = try FileHandle(forWritingTo: s.journal)
        try h.seekToEnd()
        try h.write(contentsOf: Data((#"{"type":"result","key":"k","agentId":"s1","result":"ok"}"# + "\n").utf8))
        try h.close()

        let t = builder.build(paths: s.paths, sessionId: sessionId, facts: TranscriptFacts(),
                              journals: &journals, sessionStartedAt: s.start, now: s.now)
        let wf = try #require(t.workflows.first)
        #expect(wf.runningCount == 1)
        #expect(wf.finishedCount == 1)
        #expect(journals.linesIngested == 4)
    }
}
