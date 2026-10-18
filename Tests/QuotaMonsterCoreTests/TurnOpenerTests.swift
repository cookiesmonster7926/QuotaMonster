import Testing
import Foundation
@testable import QuotaMonsterCore

/// 「這一輪是誰開的」—— 往前掃的時候順手記下最後一則真人訊息。
///
/// ⚠️ 每一行 fixture 都是**手寫合成**的：只模仿真實 transcript 的**形狀**
/// （哪些 key、content 是字串還是 list、開頭是哪個標籤），內容全部是編的。
/// 形狀的出處是本機唯讀計數（第三節第 33 條），不是複製來的行。
@Suite("TurnOpener — 這一輪是誰開的")
struct TurnOpenerTests {

    func feed(_ lines: [String]) -> TurnOpener.Answer {
        var o = TurnOpener()
        for l in lines {
            guard let d = (try? JSONSerialization.jsonObject(with: Data(l.utf8))) as? [String: Any]
            else { continue }
            o.ingest(d)
        }
        return o.answer
    }

    /// 2026-09-19T02:00:00Z 之後第 `s` 秒。
    func ts(_ s: Int) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: at(s))
    }
    func at(_ s: Int) -> Date { Date(timeIntervalSince1970: 1_789_783_200 + TimeInterval(s)) }

    // ── 合成的形狀 ──────────────────────────────────────────────

    func human(_ s: Int, _ text: String = "幫我把那個測試修好") -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","origin":{"kind":"human"},"message":{"role":"user","content":"\#(text)"}}"#
    }
    func humanList(_ s: Int) -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","message":{"role":"user","content":[{"type":"text","text":"看這段"}]}}"#
    }
    /// IDE 把開著的檔案塞在**同一則**訊息的第一個 text 區塊，人打的字在第二個。
    func humanWithIDEContext(_ s: Int) -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","origin":{"kind":"human"},"message":{"role":"user","content":["#
            + #"{"type":"text","text":"<ide_opened_file>The user opened the file /x/y.swift in the IDE.</ide_opened_file>"},"#
            + #"{"type":"text","text":"這個檔案為什麼編不過"}]}}"#
    }
    func ideOnly(_ s: Int) -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","message":{"role":"user","content":["#
            + #"{"type":"text","text":"<ide_opened_file>The user opened the file /x/y.swift in the IDE.</ide_opened_file>"}]}}"#
    }
    func assistant(_ s: Int, _ stop: String, id: String) -> String {
        #"{"type":"assistant","timestamp":"\#(ts(s))","isSidechain":false,"message":{"id":"\#(id)","stop_reason":"\#(stop)","content":[{"type":"text","text":"好"}]}}"#
    }
    func toolResult(_ s: Int) -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","toolUseResult":{},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_x","content":"ok"}]}}"#
    }
    func meta(_ s: Int) -> String {
        #"{"type":"user","isMeta":true,"timestamp":"\#(ts(s))","message":{"role":"user","content":"Base directory for this skill: /x"}}"#
    }
    /// 別的 agent 傳來的訊息：isMeta、origin.kind = peer。
    func peer(_ s: Int) -> String {
        #"{"type":"user","isMeta":true,"timestamp":"\#(ts(s))","origin":{"kind":"peer","from":"w1"},"message":{"role":"user","content":"子任務做完了"}}"#
    }
    func taskNotification(_ s: Int) -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","origin":{"kind":"task-notification"},"message":{"role":"user","content":"<task-notification>\n<task-id>b1</task-id>\n<status>completed</status>\n</task-notification>"}}"#
    }
    /// compact 之後那一則「接續前一段對話」的摘要。不是 isMeta，但也不是人打的。
    func compactSummary(_ s: Int) -> String {
        #"{"type":"user","isCompactSummary":true,"isVisibleInTranscriptOnly":true,"timestamp":"\#(ts(s))","message":{"role":"user","content":"This session is being continued from a previous conversation."}}"#
    }
    func commandName(_ s: Int) -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","message":{"role":"user","content":"<command-name>/cost</command-name>\n<command-message>cost</command-message>"}}"#
    }
    func localStdout(_ s: Int) -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","message":{"role":"user","content":"<local-command-stdout>Total cost: $0.00</local-command-stdout>"}}"#
    }
    func bashStdout(_ s: Int) -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","message":{"role":"user","content":"<bash-stdout>main</bash-stdout><bash-stderr></bash-stderr>"}}"#
    }
    func system(_ s: Int, _ subtype: String) -> String {
        #"{"type":"system","subtype":"\#(subtype)","timestamp":"\#(ts(s))","isMeta":false}"#
    }

    // ── 基本 ────────────────────────────────────────────────────

    @Test("一則真人訊息 —— 起點就是那一行自己的 timestamp")
    func humanOpensTheTurn() {
        #expect(feed([human(10), assistant(20, "tool_use", id: "m1"), toolResult(25)])
                == .human(at(10)))
    }

    @Test("記的是**最後**一則真人訊息")
    func lastHumanWins() {
        #expect(feed([human(10), assistant(20, "end_turn", id: "m1"), human(300)])
                == .human(at(300)))
    }

    @Test("content 是 list 的真人訊息也算")
    func listShapedHumanCounts() {
        #expect(feed([human(10), assistant(20, "end_turn", id: "m1"), humanList(400)])
                == .human(at(400)))
    }

    // ── 看到它、但它不是真人訊息 ────────────────────────────────

    @Test("tool_result、isMeta、peer、背景通知、compact 摘要、command 與它的輸出 —— 都不移動起點")
    func harnessLinesDoNotMoveTheStart() {
        // 這是第一層：每一行都**看到了**，而且看得出它**不是**真人訊息。
        // 那是正面證據，所以起點留在原地，而不是變成「不知道」。
        let lines = [human(10), toolResult(30), meta(40), peer(50), taskNotification(60),
                     compactSummary(70), commandName(80), localStdout(81), bashStdout(82),
                     ideOnly(83), system(84, "informational")]
        #expect(feed(lines) == .human(at(10)))
    }

    @Test("IDE 把開著的檔案塞在同一則訊息前面 —— 後面那段是人打的，這一則算真人")
    func ideContextBlockDoesNotHideTheHuman() {
        // 〔本機唯讀計數〕這種形狀全部是 list，第一個 text 區塊是 `<ide_opened_file>`。
        // 舊的判讀把所有 text 接起來看開頭，會把整則當成 harness 注入吞掉。
        #expect(feed([human(10), assistant(20, "end_turn", id: "m1"), humanWithIDEContext(500)])
                == .human(at(500)))
    }

    // ── 整個沒看到：沒有真人訊息 vs 沒有時刻 ─────────────────────

    @Test("從頭掃到尾一則真人訊息都沒有 —— 是 noHumanYet，不是拿第一行充數")
    func noHumanAtAll() {
        #expect(feed([taskNotification(0), assistant(5, "end_turn", id: "m1")]) == .noHumanYet)
    }

    @Test("真人訊息沒帶 timestamp —— 看到了，但時刻不知道；不可以拿別行的時刻補")
    func humanWithoutTimestamp() {
        let noTs = #"{"type":"user","message":{"role":"user","content":"沒有時間戳"}}"#
        #expect(feed([human(10), noTs]) == .humanWithoutTimestamp)
    }

    // ── 這一輪不是人開的 ────────────────────────────────────────

    @Test("講完之後被背景通知叫醒、又講了一段 —— 這一段不是那則真人訊息開的")
    func wokenByANotification() {
        // 〔代理量測 2026-10-19〕27.1%（210/774）的完成在這個桶裡（這一種，加上 slash command 開的）。拿那則真人訊息當起點，
        // 會把「上一輪講完 → 通知抵達」中間的閒置也算成「跑了多久」。
        let lines = [human(10), assistant(20, "end_turn", id: "m1"), system(21, "turn_duration"),
                     taskNotification(4000), assistant(4010, "end_turn", id: "m2")]
        #expect(feed(lines) == .wokenWithoutHuman)
    }

    @Test("被叫醒之後人又打字 —— 回到真人起點")
    func humanAfterWakeRestores() {
        let lines = [human(10), assistant(20, "end_turn", id: "m1"),
                     peer(100), assistant(110, "end_turn", id: "m2"), human(900)]
        #expect(feed(lines) == .human(at(900)))
    }

    @Test("兩行式 end_turn（同一則訊息的 thinking 與 text）不是被叫醒")
    func twoLineEndTurnIsOneMessage() {
        let lines = [human(10), assistant(20, "end_turn", id: "m1"), assistant(60, "end_turn", id: "m1")]
        #expect(feed(lines) == .human(at(10)))
    }

    @Test("講完之後跑了一個本地指令（/cost）—— 模型沒有再動，起點不變")
    func localCommandAfterEndTurnIsNotAWake() {
        let lines = [human(10), assistant(20, "end_turn", id: "m1"), commandName(30), localStdout(31)]
        #expect(feed(lines) == .human(at(10)))
    }

    @Test("一則真人訊息都還沒看過時被叫醒 —— 維持 noHumanYet，不是 woken")
    func wakeBeforeAnyHumanStaysNoHumanYet() {
        // 「被叫醒」是相對於某一則真人訊息說的；沒有那一則就沒有這句話。
        let lines = [taskNotification(0), assistant(5, "end_turn", id: "m1"),
                     taskNotification(4000), assistant(4010, "end_turn", id: "m2")]
        #expect(feed(lines) == .noHumanYet)
    }

    @Test("end_turn 沒帶 message.id —— 分不出是不是同一則，往「被叫醒」那邊判")
    func endTurnWithoutIdLeansWoken() {
        let noId = #"{"type":"assistant","timestamp":"\#(ts(20))","message":{"stop_reason":"end_turn","content":[]}}"#
        let next = #"{"type":"assistant","timestamp":"\#(ts(4010))","message":{"stop_reason":"end_turn","content":[]}}"#
        #expect(feed([human(10), noId, taskNotification(4000), next]) == .wokenWithoutHuman)
        // 反過來：講完的那一則有 id，叫醒之後那一則沒有。
        #expect(feed([human(10), assistant(20, "end_turn", id: "m1"), taskNotification(4000), next])
                == .wokenWithoutHuman)
    }

    // ── 真人打的、但不開出一輪模型回合的行 ──────────────────────

    /// Esc 中斷的標記。字串型與 list 型兩種都有〔本機唯讀計數 2026-10-19，16 則〕，
    /// `isHuman` 收它（`TurnCompletionReader` 靠它判 unfinished），但**它不開出一輪**。
    func interrupted(_ s: Int) -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","message":{"role":"user","content":"[Request interrupted by user]"}}"#
    }
    func interruptedForToolUse(_ s: Int) -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","message":{"role":"user","content":[{"type":"text","text":"[Request interrupted by user for tool use]"}]}}"#
    }
    func bashInput(_ s: Int) -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","message":{"role":"user","content":"<bash-input>git status</bash-input>"}}"#
    }

    @Test("Esc 中斷之後被背景通知叫醒 —— 這一段不是人開的，不可以從中斷那一刻起算")
    func wakeAfterInterruptIsWoken() {
        // 中斷的那一輪不會寫出 end_turn。只認 end_turn 的話，中斷標記會被當成起點，
        // ranFor 把「中斷 → 通知抵達」的閒置全部算進去（code review 的失敗情境：2360 秒）。
        let lines = [human(0), assistant(10, "tool_use", id: "m1"), toolResult(20),
                     interrupted(60), taskNotification(2400), assistant(2410, "end_turn", id: "m2")]
        #expect(feed(lines) == .wokenWithoutHuman)
    }

    @Test("工具執行中按 Esc（list 型的中斷標記）之後被叫醒 —— 一樣是 woken")
    func wakeAfterToolUseInterruptIsWoken() {
        let lines = [human(0), assistant(10, "tool_use", id: "m1"),
                     interruptedForToolUse(60), taskNotification(2400), assistant(2410, "end_turn", id: "m2")]
        #expect(feed(lines) == .wokenWithoutHuman)
    }

    @Test("中斷之後人又打字 —— 起點是那則新訊息")
    func humanAfterInterruptOpensTheTurn() {
        let lines = [human(0), assistant(10, "tool_use", id: "m1"), interrupted(60),
                     human(300), assistant(310, "end_turn", id: "m2")]
        #expect(feed(lines) == .human(at(300)))
    }

    @Test("中斷之後、被叫醒之前，同一則被中斷的訊息又落下一行 —— 不是被叫醒")
    func interruptedMessageTrailingLineIsNotAWake() {
        let lines = [human(0), assistant(10, "tool_use", id: "m1"), interrupted(60),
                     assistant(61, "tool_use", id: "m1")]
        #expect(feed(lines) != .wokenWithoutHuman)
    }

    @Test("`!` 指令會開出一輪 —— 模型回 bash 輸出的那一段，起點是 bash-input")
    func bashInputOpensATurn() {
        // 〔本機唯讀計數 2026-10-19〕13 則前一則是 end_turn 的 `<bash-input>`，
        // 13 則之後都接著一則新的 assistant（中間只有 `<bash-stdout>`，沒有別的真人訊息）。
        // 所以它是起點，不是「不開出一輪」的那一種。
        let lines = [human(0), assistant(10, "end_turn", id: "m1"),
                     bashInput(100), bashStdout(101), assistant(105, "end_turn", id: "m2")]
        #expect(feed(lines) == .human(at(100)))
    }

    @Test("`!` 指令那一輪講完之後被叫醒 —— woken，不從 bash-input 起算")
    func wakeAfterBashTurnIsWoken() {
        let lines = [human(0), assistant(10, "end_turn", id: "m1"),
                     bashInput(100), bashStdout(101), assistant(105, "end_turn", id: "m2"),
                     taskNotification(2400), assistant(2410, "end_turn", id: "m3")]
        #expect(feed(lines) == .wokenWithoutHuman)
    }
}
