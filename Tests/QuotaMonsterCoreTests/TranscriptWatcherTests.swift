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
        // 留下來的那一份的事實也要還在（不是重新讀一次）。
        #expect(w.update(a).outcomes.count == 1)
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
}
