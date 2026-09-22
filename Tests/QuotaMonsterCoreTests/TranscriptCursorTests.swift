import Testing
import Foundation
@testable import QuotaMonsterCore

/// 「記住讀到哪裡，只讀新增的部分」。
///
/// ### 為什麼需要它
/// 〔實測 2026-09-22〕`AgentTreeBuilder.toolUseIds` 用 `String(contentsOf:)` 把整份
/// 母 transcript 讀進來，**每 3 秒一次、在 main actor 上**。這台機器最大的 transcript
/// 是 22.4MB，還活著的最大 16.1MB，量到單次 0.513 秒 —— 而且其中只有 0.014 秒是 I/O，
/// **97% 是 JSON 解析**。所以省的必須是「重新解析舊的行」，不是「重新讀 bytes」。
///
/// ### ⚠️ 這不是 `WaitingContextReader.tail` 的另一種寫法
/// 那一支從尾端往回抓 64KB，並且**丟掉第一個換行之前的東西**（因為切在半行上）。
/// 從記住的 offset 往前讀時，第一個 byte **就是**某一行的開頭 ——
/// 照抄那個行為會每次讀都靜靜地吃掉一筆記錄。
///
/// ### ⚠️ 只有路徑不夠
/// transcript 會在 compact / fork / `--resume` 時被**整個重寫**。
/// 檔案可能變短，也可能**大小一樣而內容整個換掉**。後者 mtime 與 size 都測不出來，
/// 只有 inode 測得到。認錯了就是從一個錯的位移往下讀，交出半行垃圾。
@Suite("TranscriptCursor — 增量讀取")
struct TranscriptCursorTests {

    /// 造一個暫存檔，回傳它的 URL。
    func file(_ contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-cursor-\(UUID().uuidString).jsonl")
        try Data(contents.utf8).write(to: url)
        return url
    }

    func append(_ text: String, to url: URL) throws {
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: Data(text.utf8))
        try h.close()
    }

    // ── 基本 ───────────────────────────────────────────────────

    @Test("第一次讀交出全部的行，並標明「這是從頭開始的」")
    func firstReadHandsBackEverythingAndSaysSo() throws {
        let url = try file("a\nb\nc\n")
        var c = TranscriptCursor()
        guard case .advanced(let lines, let fromStart) = c.read(url) else {
            Issue.record("應該讀得到"); return
        }
        #expect(lines == ["a", "b", "c"])
        // ⚠️ 這個旗標是「不可以拿去發通知」的唯一依據 ——
        // app 剛開機時整份 transcript 都是新的，但那些完成都不是我們見證的。
        #expect(fromStart)
    }

    @Test("第二次讀、檔案沒長 —— 交出 0 行，而且**不是**讀不到")
    func noNewBytesIsZeroLinesNotUnreadable() throws {
        let url = try file("a\nb\n")
        var c = TranscriptCursor()
        _ = c.read(url)
        guard case .advanced(let lines, let fromStart) = c.read(url) else {
            Issue.record("「沒有新東西」不可以回 unreadable —— 那是另一件事"); return
        }
        #expect(lines.isEmpty)
        #expect(!fromStart)
    }

    @Test("只交出新增的那幾行")
    func onlyHandsBackWhatIsNew() throws {
        let url = try file("a\nb\n")
        var c = TranscriptCursor()
        _ = c.read(url)
        try append("c\nd\n", to: url)
        guard case .advanced(let lines, _) = c.read(url) else { Issue.record("讀不到"); return }
        #expect(lines == ["c", "d"])
    }

    // ── 半行 ───────────────────────────────────────────────────

    @Test("結尾沒有換行的半行不交出，也不消耗掉")
    func aPartialLineIsNeitherHandedBackNorConsumed() throws {
        let url = try file("a\n")
        var c = TranscriptCursor()
        _ = c.read(url)
        try append("bb", to: url)                      // 還沒寫完
        guard case .advanced(let first, _) = c.read(url) else { Issue.record("讀不到"); return }
        #expect(first.isEmpty)

        try append("bb\n", to: url)                    // 寫完了
        guard case .advanced(let second, _) = c.read(url) else { Issue.record("讀不到"); return }
        // ⚠️ 整行是 "bbbb" —— 半行必須被完整地留下來，不是被丟掉也不是被切兩段。
        #expect(second == ["bbbb"])
    }

    @Test("⚠️ 同一次讀裡「完整的行 + 半行」—— 半行要留到下一次，不可以掉")
    func aCompleteLineFollowedByAPartialOneInTheSameRead() throws {
        // ⚠️ 這一則是突變驗證補上的。上一則（只有半行、沒有完整行）**抓不到**
        // 「消化完整行之後把 partial 清掉」這個改壞 —— 那條路徑上 partial 本來就是空的。
        // 而真實的 transcript 幾乎每次都長這樣：前面幾筆寫完了，最後一筆寫到一半。
        let url = try file("a\n")
        var c = TranscriptCursor()
        _ = c.read(url)

        try append("bbb\ncc", to: url)               // 一筆完整 + 一筆寫到一半
        guard case .advanced(let first, _) = c.read(url) else { Issue.record("讀不到"); return }
        #expect(first == ["bbb"])

        try append("cc\n", to: url)
        guard case .advanced(let second, _) = c.read(url) else { Issue.record("讀不到"); return }
        #expect(second == ["cccc"])
    }

    @Test("空行不會被當成資料交出去")
    func blankLinesAreDropped() throws {
        let url = try file("a\n\n\nb\n")
        var c = TranscriptCursor()
        guard case .advanced(let lines, _) = c.read(url) else { Issue.record("讀不到"); return }
        #expect(lines == ["a", "b"])
    }

    // ── 檔案被重寫 ─────────────────────────────────────────────

    @Test("檔案變短 —— 整份重讀，並標明是從頭開始")
    func aTruncatedFileIsReReadFromTheStart() throws {
        let url = try file("aaaa\nbbbb\ncccc\n")
        var c = TranscriptCursor()
        _ = c.read(url)
        try Data("x\n".utf8).write(to: url)            // 同一個 inode，變短了
        guard case .advanced(let lines, let fromStart) = c.read(url) else {
            Issue.record("讀不到"); return
        }
        #expect(lines == ["x"])
        #expect(fromStart)
    }

    @Test("⚠️ 檔案被換掉、大小剛好一樣 —— 只有 inode 測得出來")
    func aReplacedFileOfTheSameSizeIsStillDetected() throws {
        let url = try file("aaaa\nbbbb\n")
        var c = TranscriptCursor()
        _ = c.read(url)

        // compact / fork 會寫一個新檔再 rename 上去 —— 新的 inode、一樣的大小。
        let replacement = try file("cccc\ndddd\n")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.moveItem(at: replacement, to: url)

        guard case .advanced(let lines, let fromStart) = c.read(url) else {
            Issue.record("讀不到"); return
        }
        // 只看 size 的實作會回 0 行（沒長大），只看 mtime 的實作也可能回 0 行。
        #expect(lines == ["cccc", "dddd"])
        #expect(fromStart)
    }

    // ── 讀不到 ─────────────────────────────────────────────────

    @Test("檔案不存在是「讀不到」，不是「沒有新東西」")
    func aMissingFileIsUnreadable() throws {
        var c = TranscriptCursor()
        let gone = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-cursor-nope-\(UUID().uuidString).jsonl")
        #expect(c.read(gone) == .unreadable)
    }

    @Test("讀不到之後 offset 不可以被歸零 —— 否則檔案回來時會整份重播")
    func offsetSurvivesAnUnreadableTick() throws {
        let url = try file("a\nb\n")
        var c = TranscriptCursor()
        _ = c.read(url)
        let saved = c.offset
        _ = c.read(url.appendingPathExtension("missing"))
        #expect(c.offset == saved)
    }

    @Test("空檔案讀得到，只是沒有行")
    func anEmptyFileReadsAsZeroLines() throws {
        let url = try file("")
        var c = TranscriptCursor()
        guard case .advanced(let lines, _) = c.read(url) else {
            Issue.record("空檔案不是讀不到"); return
        }
        #expect(lines.isEmpty)
    }
}
