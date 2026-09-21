import Testing
import Foundation
@testable import QuotaMonsterCore

/// workflow 的 `journal.jsonl` 是唯一能判斷扇出裡誰還在跑的來源。
/// 實測所有 journal 的 type 只有四種：started / result / failed / launched。
///
/// **`failed` 是最容易漏掉的那個** —— 漏掉它，失敗的 agent 會永遠掛在樹上。
@Suite("WorkflowJournalReader")
struct WorkflowJournalReaderTests {

    let reader = WorkflowJournalReader()

    func journal() throws -> WorkflowJournal {
        let u = try Fixture.projectsRoot().appendingPathComponent(
            "-tmp-fixture-project/\(Fixture.agentSessionId)/subagents/workflows/wf_fixture01/journal.jsonl")
        return reader.read(u)
    }

    @Test("三隻啟動")
    func countsStarted() throws {
        #expect(try journal().started == ["w1", "w2", "w3"])
    }

    @Test("執行中 = started 減去 (result ∪ failed)")
    func runningExcludesBothResultAndFailed() throws {
        #expect(try journal().running == ["w2"])
    }

    @Test("失敗的 agent 不算執行中 —— 漏掉 failed 會讓它永遠掛在樹上")
    func failedAgentIsNotRunning() throws {
        #expect(try journal().running.contains("w3") == false)
    }

    @Test("完成的 agent 不算執行中")
    func completedAgentIsNotRunning() throws {
        #expect(try journal().running.contains("w1") == false)
    }

    @Test("launched 事件沒有 agentId，不得造成誤判")
    func launchedEventIsIgnored() throws {
        #expect(try journal().started.count == 3)
    }

    @Test("檔案不存在時回傳空的 journal，不丟錯")
    func missingFileYieldsEmpty() {
        let u = URL(fileURLWithPath: "/tmp/nope-\(UUID().uuidString)/journal.jsonl")
        #expect(reader.read(u).started.isEmpty)
    }

    @Test("壞掉的行跳過，其餘照讀 —— append-only 檔可能讀到寫一半的最後一行")
    func malformedLinesAreSkipped() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent("journal.jsonl")
        try """
        {"type":"started","agentId":"a"}
        {"type":"started","agentId":
        {"type":"started","agentId":"b"}
        """.write(to: u, atomically: true, encoding: .utf8)
        #expect(reader.read(u).started == ["a", "b"])
    }
    // ── 階段與順序 ──────────────────────────────────────────────
    //
    // 上面那 7 則對「改成有序」完全無感（它們只問 started / running 這兩個
    // 集合），所以下面這些是唯一擋得住「為了省事把 spawns 換回 Set」的防線。

    /// 寫一個暫存 journal，回傳讀出來的結果。
    func read(_ lines: String) throws -> WorkflowJournal {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-journal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent("journal.jsonl")
        try lines.write(to: u, atomically: true, encoding: .utf8)
        return reader.read(u)
    }

    @Test("多階段的 journal 取最後一個 started 行的 phase")
    func latestPhaseIsTheLastStartedLine() throws {
        let j = try read("""
        {"type":"started","agentId":"a","phase":"Build"}
        {"type":"started","agentId":"b","phase":"Audit"}
        """)
        #expect(j.latestPhase == "Audit")
    }

    @Test("spawn 順序要留下來 —— 它是這個檔案裡唯一的時間資訊")
    func spawnOrderIsPreserved() throws {
        // started 行沒有時間戳，所以順序換成 Set 就等於把時間資訊丟掉。
        let j = try read("""
        {"type":"started","agentId":"z","phase":"A"}
        {"type":"started","agentId":"a","phase":"B"}
        {"type":"started","agentId":"m","phase":"C"}
        """)
        #expect(j.spawns.map(\.agentId) == ["z", "a", "m"])
    }

    @Test("只有 launched、一行 started 都沒有 —— latestPhase 是 nil，不是空字串")
    func noStartedLineMeansNilPhase() throws {
        #expect(try read(#"{"type":"launched"}"#).latestPhase == nil)
    }

    @Test("檔案不存在 —— latestPhase 是 nil，而且不丟錯")
    func missingFileMeansNilPhase() {
        let u = URL(fileURLWithPath: "/tmp/nope-\(UUID().uuidString)/journal.jsonl")
        #expect(reader.read(u).latestPhase == nil)
    }

    @Test("最後一行寫到一半 —— 退回前一個完整的 started 行，不是整個變 nil")
    func truncatedLastLineFallsBackToThePreviousPhase() throws {
        // append-only 檔隨時可能讀到寫一半的最後一行（既有的 malformedLinesAreSkipped
        // 已經釘住集合那一半，這裡把同一條規則延伸到 phase）。
        let j = try read("""
        {"type":"started","agentId":"a","phase":"Build"}
        {"type":"started","agentId":"b","phase":"Audit"}
        {"type":"started","agentId":
        """)
        #expect(j.latestPhase == "Audit")
    }

    @Test("started 行沒有 phase 欄位 —— 那一行就是 nil，不繼承上一行")
    func missingPhaseFieldDoesNotInherit() throws {
        // ⚠️〔實測 343/343 個 started 行都有非空 phase〕**這個情形從來沒有被觀測到。**
        // 這一則防的是未來的 schema 變動：繼承上一行會安靜地報一個過期的階段，
        // 而 nil 至少誠實。
        let j = try read("""
        {"type":"started","agentId":"a","phase":"Build"}
        {"type":"started","agentId":"b"}
        """)
        #expect(j.latestPhase == nil)
    }

    @Test("同一隻重試兩次 —— started 仍然只算一個，但 spawns 記得兩行")
    func retriesAppearTwiceInSpawnsButOnceInStarted() throws {
        // 兩個斷言一起寫才釘得住分岔的方向：只斷言前者的話，
        // 一個「append 前先去重」的實作也會過，但那會弄丟 latestPhase 的順序。
        let j = try read("""
        {"type":"started","agentId":"a","phase":"Build"}
        {"type":"started","agentId":"a","phase":"Audit"}
        """)
        #expect(j.started.count == 1)
        #expect(j.spawns.count == 2)
        #expect(j.latestPhase == "Audit")
    }

}
