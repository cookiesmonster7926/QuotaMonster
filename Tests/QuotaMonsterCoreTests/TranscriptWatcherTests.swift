import Testing
import Foundation
@testable import QuotaMonsterCore

/// 每份 transcript 一個游標 + 一份累積的事實。
///
/// ⚠️ 這一層存在的唯一理由是**不要重新解析舊的行**。
/// 〔實測 2026-09-22〕重新讀 bytes 只佔 3%，重新**解析** 佔 97% ——
/// 一個只避開重讀、照樣重新解析的「增量」快取一點都不會比較快。
@Suite("TranscriptWatcher — 只解析新增的行")
struct TranscriptWatcherTests {

    func file(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-watch-\(UUID().uuidString).jsonl")
        try Data(contents.utf8).write(to: url)
        return url
    }

    func append(_ text: String, to url: URL) throws {
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd(); try h.write(contentsOf: Data(text.utf8)); try h.close()
    }

    /// 一筆完成通知。
    func notify(_ agentId: String, _ status: String) -> String {
        #"{"type":"queue-operation","operation":"enqueue","content":"<task-notification>\n<task-id>"#
            + agentId + #"</task-id>\n<status>"# + status
            + #"</status>\n<summary>Agent \"x\" finished</summary>\n</task-notification>"}"# + "\n"
    }

    @Test("第一次就把整份讀完")
    func firstUpdateReadsEverything() throws {
        let url = try file(notify("a1", "completed") + notify("a2", "failed"))
        var w = TranscriptWatcher()
        let f = w.update(url)
        #expect(f.outcomes.count == 2)
        #expect(f.outcomes["a2"]?.kind == .failed)
    }

    @Test("後來追加的行會累加上去")
    func laterLinesAccumulate() throws {
        let url = try file(notify("a1", "completed"))
        var w = TranscriptWatcher()
        _ = w.update(url)
        try append(notify("a2", "killed"), to: url)
        let f = w.update(url)
        #expect(f.outcomes.count == 2)
        #expect(f.outcomes["a1"]?.kind == .completed)
        #expect(f.outcomes["a2"]?.kind == .killed)
    }

    @Test("沒有新東西時，已經知道的事實不會消失")
    func knowledgeSurvivesAnIdleTick() throws {
        let url = try file(notify("a1", "completed"))
        var w = TranscriptWatcher()
        _ = w.update(url)
        #expect(w.update(url).outcomes.count == 1)
    }

    @Test("⚠️ 檔案被整個重寫時，事實要跟著整份換掉 —— 不可以累加")
    func aRewrittenFileReplacesTheFacts() throws {
        let url = try file(notify("a1", "completed"))
        var w = TranscriptWatcher()
        _ = w.update(url)

        // compact / fork：新檔 rename 上去。
        let replacement = try file(notify("a2", "completed"))
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: replacement, to: url)

        let f = w.update(url)
        // 舊的那一隻**不在新的檔案裡**。留著它等於在畫面上宣告一件這份記錄
        // 已經不再支持的事 —— 而且它永遠不會被清掉。
        #expect(f.outcomes["a1"] == nil)
        #expect(f.outcomes["a2"]?.kind == .completed)
    }

    @Test("讀不到的那一拍不可以抹掉已經知道的事")
    func anUnreadableTickDoesNotEraseKnowledge() throws {
        let url = try file(notify("a1", "completed"))
        var w = TranscriptWatcher()
        _ = w.update(url)
        try FileManager.default.removeItem(at: url)
        // 「我們沒看到」不是「它沒發生」。
        #expect(w.update(url).outcomes.count == 1)
    }

    @Test("session 死掉之後要放掉它的記憶體")
    func forgettingDropsTheState() throws {
        let url = try file(notify("a1", "completed"))
        var w = TranscriptWatcher()
        _ = w.update(url)
        #expect(w.watchedCount == 1)
        w.keep(only: [])
        #expect(w.watchedCount == 0)
    }

    @Test("保留名單裡的留著，不在的丟掉")
    func keepOnlyKeepsTheNamedOnes() throws {
        let a = try file(notify("a1", "completed"))
        let b = try file(notify("a2", "completed"))
        var w = TranscriptWatcher()
        _ = w.update(a); _ = w.update(b)
        w.keep(only: [a])
        #expect(w.watchedCount == 1)
        // ⚠️ 這裡原本只斷言「`update(a)` 還看得到一筆」——〔code review 2026-09-22〕
        // **那個斷言是空的**：重新整份讀一次也會看到一筆。
        // 分得出兩者的只有「有沒有再解析一次」。
        let before = w.linesIngested
        #expect(w.update(a).outcomes.count == 1)
        #expect(w.linesIngested == before, "留下來的那一份被重新解析了 —— 游標沒有跟著留下")
    }

    @Test("⚠️ 沒有新東西時一行都不重新解析 —— 這一層的存在理由，唯一釘得住它的斷言")
    func nothingIsReParsedWhenTheFileHasNotGrown() throws {
        let url = try file(notify("a1", "completed") + notify("a2", "completed"))
        var w = TranscriptWatcher()
        _ = w.update(url)
        #expect(w.linesIngested == 2)
        // 再問十次，一行都不該被重新解析。
        for _ in 0..<10 { _ = w.update(url) }
        #expect(w.linesIngested == 2, "每拍重新解析整份 —— 那正是要修掉的 1004 毫秒")
        // 追加一行才會多一行。
        try append(notify("a3", "completed"), to: url)
        _ = w.update(url)
        #expect(w.linesIngested == 3)
    }

    @Test("⚠️ 舊的行不會被重新解析 —— 這是這一層唯一的存在理由")
    func oldLinesAreNotReParsed() throws {
        // 就地覆寫**同樣長度**的內容（同一個 inode、同樣大小、同樣的 offset）。
        // 有重新解析的實作會看到 a2；只讀新增部分的實作看到的仍然是 a1。
        let before = notify("a1", "completed")
        let after = notify("a2", "completed")
        #expect(before.count == after.count)     // 前提：長度一樣，游標才不會察覺

        let url = try file(before)
        var w = TranscriptWatcher()
        #expect(w.update(url).outcomes["a1"]?.kind == .completed)

        let h = try FileHandle(forWritingTo: url)
        try h.seek(toOffset: 0)
        try h.write(contentsOf: Data(after.utf8))
        try h.close()

        let f = w.update(url)
        #expect(f.outcomes["a1"]?.kind == .completed)
        #expect(f.outcomes["a2"] == nil)
    }

    // ── 回合起點（第三節第 33 條）───────────────────────────────

    /// 合成的真人訊息與 end_turn。內容是編的，只模仿形狀。
    func human(_ iso: String) -> String {
        #"{"type":"user","timestamp":""# + iso + #"","message":{"role":"user","content":"跑一下測試"}}"# + "\n"
    }
    func endTurn(_ iso: String, id: String) -> String {
        #"{"type":"assistant","timestamp":""# + iso
            + #"","message":{"id":""# + id + #"","stop_reason":"end_turn","content":[{"type":"text","text":"好了"}]}}"# + "\n"
    }

    @Test("從沒讀到過的 transcript —— 回合起點是 nil（整個沒看到），不是「沒有真人訊息」")
    func unseenTranscriptHasNoOpening() throws {
        let missing = URL(fileURLWithPath: "/tmp/qm-nope-\(UUID().uuidString).jsonl")
        var w = TranscriptWatcher()
        _ = w.update(missing)
        // 第二層：沒看到它。不是證據，所以不可以回答成 `.noHumanYet`。
        #expect(w.opening(of: missing) == nil)
    }

    @Test("讀到了、但一則真人訊息都沒有 —— noHumanYet（看到了，那個狀態不成立）")
    func readButNoHuman() throws {
        let url = try file(notify("a1", "completed"))
        var w = TranscriptWatcher()
        _ = w.update(url)
        #expect(w.opening(of: url) == .noHumanYet)
    }

    @Test("往前掃記下最後一則真人訊息 —— 回合多長都搆得到，不受 64KB 尾端窗口限制")
    func openingSurvivesAHugeTurn() throws {
        // 舊的作法從 64KB 尾端往回找，〔實測 n=337〕只有 37.4% 的回合塞得進去。
        // 這裡在真人訊息後面塞 200KB 的工具結果，起點仍然要找得到。
        let url = try file(human("2026-09-19T02:00:00.000Z"))
        var w = TranscriptWatcher()
        _ = w.update(url)
        let big = String(repeating: "x", count: 200_000)
        try append(#"{"type":"user","message":{"content":[{"type":"tool_result","content":""#
                   + big + #""}]}}"# + "\n", to: url)
        try append(endTurn("2026-09-19T02:30:00.000Z", id: "m1"), to: url)
        _ = w.update(url)
        #expect(w.opening(of: url) == .human(Date(timeIntervalSince1970: 1_789_783_200)))
    }

    @Test("被整個重寫 —— 起點跟著重算，不留舊檔的")
    func rewriteResetsTheOpening() throws {
        let url = try file(human("2026-09-19T02:00:00.000Z"))
        var w = TranscriptWatcher()
        _ = w.update(url)
        // 寫新檔再 rename 上去：inode 換了。新檔裡沒有真人訊息。
        let tmp = url.appendingPathExtension("new")
        try Data(notify("a1", "completed").utf8).write(to: tmp)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
        _ = w.update(url)
        #expect(w.opening(of: url) == .noHumanYet)
    }
}
