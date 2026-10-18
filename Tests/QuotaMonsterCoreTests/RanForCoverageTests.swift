import Testing
import Foundation
@testable import QuotaMonsterCore

/// `--measure-ranfor` 的判讀：拿 transcript 自己的時間戳當 mtime 的代理，
/// 模擬「沉澱 90 秒 → 讀尾端」會在哪裡產生完成標記，再問每一個標記的 ranFor 算不算得出來。
/// fixture 全部手寫合成（只模仿形狀）。
@Suite("RanForCoverage — 命中率怎麼量")
struct RanForCoverageTests {

    func ts(_ s: Int) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: Date(timeIntervalSince1970: 1_789_783_200 + TimeInterval(s)))
    }
    func human(_ s: Int) -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","message":{"content":"開始"}}"#
    }
    func tool(_ s: Int, id: String) -> String {
        #"{"type":"assistant","timestamp":"\#(ts(s))","message":{"id":"\#(id)","stop_reason":"tool_use","content":[]}}"#
    }
    func result(_ s: Int) -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#
    }
    func end(_ s: Int, id: String) -> String {
        #"{"type":"assistant","timestamp":"\#(ts(s))","message":{"id":"\#(id)","stop_reason":"end_turn","content":[]}}"#
    }
    func duration(_ s: Int, ms: Int) -> String {
        #"{"type":"system","subtype":"turn_duration","durationMs":\#(ms),"timestamp":"\#(ts(s))"}"#
    }
    func notification(_ s: Int) -> String {
        #"{"type":"user","timestamp":"\#(ts(s))","message":{"content":"<task-notification>\n<status>completed</status>\n</task-notification>"}}"#
    }
    func scan(_ lines: [String]) -> RanForCoverage {
        var c = RanForCoverage()
        c.scan(Data((lines.joined(separator: "\n") + "\n").utf8))
        return c
    }

    @Test("一輪做完、安靜到檔尾 —— 一個完成，算得出 ranFor，與 turn_duration 對得上")
    func oneFinish() {
        let c = scan([human(0), tool(5, id: "a"), result(30), end(700, id: "b"), duration(700, ms: 700_000)])
        #expect(c.finishes == 1)
        #expect(c.hits == 1)
        #expect(c.ranFor == [700])
        #expect(c.withTurnDuration == 1)
        #expect(c.agreesWithTurnDuration == 1)
    }

    func system(_ s: Int, _ subtype: String) -> String {
        #"{"type":"system","subtype":"\#(subtype)","timestamp":"\#(ts(s))"}"#
    }

    @Test("舊作法模擬：安靜之後第一個寫入就是真人訊息 —— 搆得到")
    func legacyHitsWhenTheHumanWritesFirst() {
        // 100 → 300 安靜 200 秒，300 那一行就是起點 → 舊作法拿得到。
        // 第一輪的真人訊息是檔案第一行，前面沒有「安靜」可言 → 舊作法拿不到。
        let c = scan([human(0), end(100, id: "a"), human(300), end(900, id: "b")])
        #expect(c.finishes == 2)
        #expect(c.hits == 2)
        #expect(c.legacyHits == 1)
    }

    @Test("舊作法模擬：安靜之後先來一行不是人寫的 —— 這一輪就搆不到了，新作法照樣算得出來")
    func legacyMissesWhenSomethingElseWritesFirst() {
        // 安靜之後第一個寫入是 system 行：舊作法在那一刻讀尾端，找到的真人訊息是
        // 上一輪的（> 15 秒）→ 丟掉，而且「確認安靜」被這一行用掉了；
        // 30 秒後人打字時沒有新的「確認安靜」，就不會再讀一次。
        let c = scan([human(0), end(100, id: "a"), system(5000, "away_summary"),
                      human(5030), tool(5035, id: "c"), result(5040), end(5800, id: "d")])
        #expect(c.finishes == 2)
        #expect(c.hits == 2)
        #expect(c.ranFor == [100, 770])
        #expect(c.legacyHits == 0)
    }

    @Test("與 turn_duration 對不上時記下方向 —— 比它長還是比它短")
    func disagreementDirection() {
        let longer = scan([human(0), end(700, id: "a"), duration(700, ms: 100_000)])
        #expect(longer.agreesWithTurnDuration == 0)
        #expect(longer.longerThanTurnDuration == 1)
        #expect(longer.shorterThanTurnDuration == 0)
        let shorter = scan([human(0), end(700, id: "a"), duration(700, ms: 900_000)])
        #expect(shorter.shorterThanTurnDuration == 1)
        #expect(shorter.longerThanTurnDuration == 0)
    }

    @Test("被背景通知叫醒的那一段 —— 算一個完成，原因記成 woken")
    func wokenFinish() {
        let c = scan([human(0), end(100, id: "a"), notification(5000), end(5100, id: "b")])
        #expect(c.finishes == 2)
        #expect(c.hits == 1)
        #expect(c.misses[.woken] == 1)
    }

    @Test("end_turn 之後 90 秒內人就打字 —— 那不是一個沉澱下來的完成")
    func humanBeforeSettleIsNotAFinish() {
        let c = scan([human(0), end(100, id: "a"), human(150), end(400, id: "b")])
        #expect(c.finishes == 1)
    }
}
