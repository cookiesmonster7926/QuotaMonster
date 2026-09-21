import Testing
import Foundation
@testable import QuotaMonsterCore

/// 「這一輪講完了嗎」只能從 transcript 尾端問。
///
/// ⚠️ **不可以問 session 註冊表的 `status`，它是黏著的。**
/// 計畫書 Stage 8 自己量過：回合結束後七分鐘 session 一直回報 `shell`；
/// 另一個 session 講完 29 分鐘仍然回報 `busy`。
@Suite("TurnCompletionReader — 這一輪講完了嗎")
struct TurnCompletionReaderTests {

    let reader = TurnCompletionReader()

    /// 把幾行 JSONL 寫進暫存檔。
    func write(_ lines: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-turn-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let u = dir.appendingPathComponent("s.jsonl")
        try lines.joined(separator: "\n").write(to: u, atomically: true, encoding: .utf8)
        return u
    }

    func assistant(_ stop: String, _ block: String = "text",
                   at ts: String = "2026-09-19T02:01:08.992Z") -> String {
        #"{"type":"assistant","timestamp":"\#(ts)","message":{"stop_reason":"\#(stop)","#
            + #""content":[{"type":"\#(block)"}]}}"#
    }

    /// 真人打的。⚠️ content 是**字串**的那一種。
    func human(_ text: String = "好", at ts: String = "2026-09-19T02:05:00.000Z") -> String {
        #"{"type":"user","timestamp":"\#(ts)","message":{"content":"\#(text)"}}"#
    }

    /// 真人打的，但**貼了截圖** —— content 是 list。
    /// 〔實測〕全庫 33 則長這樣，字串判別法整個抓不到。
    func humanWithImage(at ts: String = "2026-09-19T02:05:00.000Z") -> String {
        #"{"type":"user","timestamp":"\#(ts)","message":{"content":"#
            + #"[{"type":"image"},{"type":"text","text":"這張圖"}]}}"#
    }

    /// harness 餵回工具結果 —— **不是人打的**。
    func toolResult(at ts: String = "2026-09-19T02:02:00.000Z") -> String {
        #"{"type":"user","timestamp":"\#(ts)","message":{"content":"#
            + #"[{"type":"tool_result"}]}}"#
    }

    /// harness 注入、看起來像真人的訊息。〔實測〕字串型的 user 行有 93 則是這種。
    func metaUser(_ text: String, at ts: String = "2026-09-19T02:02:00.000Z") -> String {
        #"{"type":"user","isMeta":true,"timestamp":"\#(ts)","message":{"content":"\#(text)"}}"#
    }

    // ── 基本判讀 ────────────────────────────────────────────────

    @Test("尾端是 end_turn —— 這一輪講完了，而且時刻取那一行自己的 timestamp")
    func endTurnIsFinished() throws {
        let u = try write([assistant("tool_use"), assistant("end_turn")])
        guard case .finished(let end) = reader.read(u) else {
            Issue.record("應該是 finished"); return
        }
        // ⚠️ 不是 Date()、不是 mtime。
        #expect(end.finishedAt == Date(timeIntervalSince1970: 1_789_783_268.992))
    }

    @Test("尾端是 tool_use —— 還在跑。這是正面證據，不是「不知道」")
    func toolUseIsUnfinished() throws {
        #expect(reader.read(try write([assistant("end_turn"), assistant("tool_use")]))
                == .unfinished)
    }

    @Test("只看 stop_reason，不看 content —— thinking-only 的 end_turn 一樣算完成")
    func thinkingOnlyEndTurnStillCounts() throws {
        // ⚠️ 計畫書多寫了一個「內容是 text 不是 tool_use」的條件。它是**冗餘的** ——
        // `stop_reason` 本身已經把 end_turn 與 tool_use 分開了。
        // 在 90 秒沉澱窗下拿掉它額外漏掉的只有「回合真的停在 thinking-only 那一行」，
        // 〔實測〕全庫 1/153。真正的問題是那個條件會把正確性偷偷綁死在沉澱窗長度上：
        // 〔實測 n=153〕兩行式 end_turn 的間隔最大 51.8 秒，窗一縮到 45 秒就開始漏。
        #expect(reader.read(try write([assistant("tool_use"), assistant("end_turn", "thinking")]))
                != .unfinished)
    }

    // ── 真正會誤報的那一格 ──────────────────────────────────────

    @Test("你剛按下 Enter、模型還沒吐第一行 —— 不可以拿上一輪的 end_turn 宣告完成")
    func humanMessageAfterEndTurnMeansUnfinished() throws {
        // ⚠️ 這是計畫書**沒有寫到**的誤報機制，而它是真的：
        // 〔實測〕479 個以真人訊息為起點的間隔裡有 6 個（1.25%）超過 90 秒，
        // 最長 623 秒 —— 那 6 個時點往回看到的最後一則 assistant
        // 正是**上一回合的** end_turn。
        #expect(reader.read(try write([assistant("end_turn"), human()])) == .unfinished)
    }

    @Test("貼截圖的訊息也是真人訊息 —— content 是 list 不是字串")
    func imageMessageCountsAsHuman() throws {
        // 〔實測〕全庫 105 則真人訊息的 content 是 list（text 或 image+text），
        // 字串判別法整個抓不到 —— 照那種寫法，貼完圖之後訊號會照樣亮。
        #expect(reader.read(try write([assistant("end_turn"), humanWithImage()])) == .unfinished)
    }

    @Test("harness 餵回的工具結果不是真人訊息 —— 它不可以吃掉訊號")
    func toolResultIsNotHuman() throws {
        #expect(reader.read(try write([assistant("end_turn"), toolResult()])) != .unfinished)
    }

    @Test("isMeta 的字串訊息不是真人打的 —— 它也不可以吃掉訊號")
    func metaUserIsNotHuman() throws {
        // 〔實測〕content 是字串的 user 行 382 則裡有 93 則 isMeta=true：
        // skill 的 caveat、圖片占位、slash command 展開、agent 間訊息。
        #expect(reader.read(try write([assistant("end_turn"),
                                       metaUser("Base directory for this skill: /x")]))
                != .unfinished)
    }

    @Test("按了 Esc 中斷 —— 它本來就是一則真人訊息，不需要第二道閘")
    func interruptIsJustAHumanMessage() throws {
        // 〔實測〕全庫只有 7 個中斷標記，而且 6 個落在 tool_use 上（那裡根本沒有
        // 完成訊號可擋）。計畫書宣稱它擋掉 2%，三個獨立量測都複驗不出來。
        let esc = #"{"type":"user","timestamp":"2026-09-19T02:05:00.000Z","message":{"content":"#
            + #"[{"type":"text","text":"[Request interrupted by user]"}]}}"#
        #expect(reader.read(try write([assistant("end_turn"), esc])) == .unfinished)
    }

    // ── 三態：不知道就是不知道 ──────────────────────────────────

    @Test("檔案不存在 —— 是 inconclusive，不是 unfinished")
    func missingFileIsInconclusive() {
        let u = URL(fileURLWithPath: "/tmp/nope-\(UUID().uuidString)/s.jsonl")
        #expect(reader.read(u) == .inconclusive)
    }

    @Test("視窗裡一則 assistant 都沒有 —— inconclusive，不可以說成「還在跑」")
    func noAssistantInWindowIsInconclusive() throws {
        // 這一格是「不存在 ≠ 那個狀態不成立」。回 .unfinished 的實作會把
        // 一個已經完成的 session 的標記當場熄掉。
        #expect(reader.read(try write([human(), toolResult()])) == .inconclusive)
    }

    @Test("被巨大的 tool_result 擠出 64KB 視窗 —— 加大視窗再讀一次")
    func oversizedTailEscalates() throws {
        // 〔實測〕漏接一律是 end_turn 之後落下一行巨大的 user(tool_result)／attachment，
        // 擠出距離 146,582 / 134,196 B —— 256KB 全覆蓋。
        let giant = #"{"type":"user","timestamp":"2026-09-19T02:02:00.000Z","message":{"content":"#
            + #"[{"type":"tool_result","text":"\#(String(repeating: "x", count: 150_000))"}]}}"#
        guard case .finished = reader.read(try write([assistant("end_turn"), giant])) else {
            Issue.record("加大視窗之後應該找得到那一則 end_turn"); return
        }
    }

    @Test("最後一行寫到一半 —— 跳過它，用前一則完整的 assistant 判讀")
    func truncatedLastLineIsSkipped() throws {
        let u = try write([assistant("end_turn"), #"{"type":"assistant","message":{"stop"#])
        guard case .finished = reader.read(u) else {
            Issue.record("半行不可以讓整個判讀失敗"); return
        }
    }

    @Test("沒有 timestamp 的 end_turn 行 —— 沒有時刻就不能宣告完成")
    func endTurnWithoutTimestampIsInconclusive() throws {
        // 〔實測〕全庫 490 個 end_turn 行 100% 帶 timestamp，所以這一格從來沒被觀測到。
        // 它防的是未來的 schema 變動：硬編一個 Date() 進去就是憑空造一個量測。
        let noTS = #"{"type":"assistant","message":{"stop_reason":"end_turn","#
            + #""content":[{"type":"text"}]}}"#
        #expect(reader.read(try write([noTS])) == .inconclusive)
    }
}
