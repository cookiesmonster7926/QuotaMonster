import Testing
import Foundation
@testable import QuotaMonsterCore

/// 一般 Agent subagent 的**真實下場**，從母 transcript 讀出來。
///
/// ### 證據基礎與它被改正的地方
/// `docs/quotamonster.md` 第三節第 29 條說完成的正面證據一直在母 transcript 裡。
/// 那是對的，但〔重新實測 2026-09-22，37 份 transcript〕它有兩個細節是錯的，
/// 而那兩個細節正好決定實作怎麼寫：
///
/// 1. **接得起來的鍵是 `toolUseResult.agentId`，不是 tool-use-id。**
///    用 agentId 對 `<task-id>`：25/25 接得上。用 tool-use-id：**5/25**。
///    （`<tool-use-id>` 只出現在 72 個通知裡的 57 個，而且重複通知時會消失。）
/// 2. **通知主要不是 `type:"user"` 記錄。** 25/25 的最早落地形式是
///    `type:"queue-operation"` / `operation:"enqueue"`（一個沒有 `message` 外層、
///    `content` 直接是字串的記錄）。只看 user 記錄的 reader 看得到 **6/25**。
///
/// ### 三條會讓資料說謊的邊界
/// - `operation:"remove"` 是 enqueue 的**逐字複本**（實測 338 vs 417）。兩個都算＝雙重計數。
/// - 同一隻 agent 會**重複通知 completed**（實測一隻通知了 17 次，另一隻的第二次
///   `<result>` 開頭是「Correction to my previous report」）。所以是**最後一筆贏**，
///   而且計數要算「不同的 agentId」不是「通知筆數」。
/// - 沒有 `<status>` 的區塊**不是「下場不明」，是「不是完成」**。實測 11 筆沒有
///   status 的全部是進度回報（9 筆 Monitor event）。把它當 unknown 會讓一個
///   活著的 monitor 在面板上變成一隻卡住的 agent。
@Suite("AgentOutcome — 從母 transcript 讀真實下場")
struct AgentOutcomeTests {

    func line(_ name: String) throws -> String {
        let url = try Fixture.url("transcripts/\(name).jsonl")
        return try String(contentsOf: url, encoding: .utf8)
            .trimmingCharacters(in: .newlines)
    }

    func facts(_ names: [String]) throws -> TranscriptFacts {
        var f = TranscriptFacts()
        for n in names { f.ingest(try line(n)) }
        return f
    }

    // ── 通知 ───────────────────────────────────────────────────

    @Test("queue-operation / enqueue 是主要載體 —— 讀得到就是完成")
    func enqueueIsTheCarrier() throws {
        let f = try facts(["notify-enqueue"])
        #expect(f.outcomes["a3333333333333333"]?.kind == .completed)
    }

    @Test("type:\"user\" 那一份也要讀 —— 兩種都是真的，只是涵蓋率不同")
    func theUserRecordCountsToo() throws {
        let f = try facts(["notify-user"])
        #expect(f.outcomes["a5555555555555555"]?.kind == .completed)
    }

    @Test("⚠️ operation:\"remove\" 是逐字複本 —— 不可以再算一次")
    func removeIsADuplicate() throws {
        let both = try facts(["notify-enqueue", "notify-remove"])
        let onlyRemove = try facts(["notify-remove"])
        // 兩個都餵：只有一隻 agent。只餵 remove：一隻都沒有。
        #expect(both.outcomes.count == 1)
        #expect(onlyRemove.outcomes.isEmpty)
    }

    @Test("killed 讀得出來，而且是自己的一格 —— 不可以併進 completed")
    func killedIsItsOwnOutcome() throws {
        let f = try facts(["notify-killed"])
        #expect(f.outcomes["a4444444444444444"]?.kind == .killed)
    }

    @Test("⚠️ 沒有 <status> 的區塊不是完成 —— 那是進度回報")
    func aBlockWithoutStatusIsNotACompletion() {
        // ⚠️ **這一則原本是空的。**〔code review 2026-09-22〕它餵的是
        // `notify-no-status` fixture，而那一份的 summary 是 `Monitor event: "…"` ——
        // 於是它被**上一道** summary 守衛擋掉，`<status>` 那道守衛根本沒被走到。
        // 把 status 守衛整個拿掉，675 則測試全綠。
        //
        // 所以這裡用合成的一行（這個 suite 本來就有合成行的先例）：
        // summary 是 Agent 的，**只有 status 缺席**，這樣能讓它變紅的就只剩那一道守衛。
        var f = TranscriptFacts()
        f.ingest(#"{"type":"queue-operation","operation":"enqueue","content":"<task-notification>\n<task-id>a5151515151515151</task-id>\n<summary>Agent \"x\" is still working</summary>\n<event>還在跑</event>\n</task-notification>"}"#)
        #expect(f.outcomes.isEmpty)
    }

    @Test("真實的那一份進度回報（Monitor event）也不算完成 —— 它連 summary 那關都過不了")
    func theRealMonitorPingIsAlsoNotACompletion() throws {
        // 上一則釘 status 守衛，這一則釘 summary 守衛。兩道都要有人守。
        let f = try facts(["notify-no-status"])
        #expect(f.outcomes.isEmpty)
    }

    @Test("workflow 與背景 bash 的通知不是 agent 的 —— 長得一模一樣，靠 summary 分")
    func otherTaskKindsAreNotAgents() throws {
        let f = try facts(["notify-workflow", "notify-bash", "notify-failed"])
        // notify-failed 這一份實測是**背景指令**的 —— 這台機器 25 隻 agent 裡
        // 一隻 failed 都沒有（completed 24 / killed 1），所以沒有真的樣本可以放。
        #expect(f.outcomes.isEmpty)
    }

    @Test("failed 這個值本身解析得出來（用合成的一行，因為真的樣本不存在）")
    func failedParsesEvenThoughNoRealAgentFailedHere() {
        // ⚠️ **這一行是合成的**，不是實測樣本：這台機器 25 隻 agent 的 `<status>`
        // 只有 completed 24 與 killed 1。`failed` 在 workflow（3）與背景指令（11）
        // 上是真的，標籤字彙是共用的，所以解析端必須認得它。
        var f = TranscriptFacts()
        f.ingest(#"{"type":"queue-operation","operation":"enqueue","timestamp":"2026-09-22T06:19:58.695Z","content":"<task-notification>\n<task-id>a9999999999999999</task-id>\n<status>failed</status>\n<summary>Agent \"synthetic\" failed</summary>\n</task-notification>"}"#)
        #expect(f.outcomes["a9999999999999999"]?.kind == .failed)
    }

    @Test("⚠️ <result> 裡面的假 <status> 不可以贏過真的那一個")
    func theFirstStatusTagWins() {
        // 標籤的順序是固定的：task-id → tool-use-id → output-file → status → summary → … → result。
        // agent 的報告是**模型可控的字串**，裡面完全可以出現 `<status>failed</status>`。
        var f = TranscriptFacts()
        f.ingest(#"{"type":"queue-operation","operation":"enqueue","content":"<task-notification>\n<task-id>a8888888888888888</task-id>\n<status>completed</status>\n<summary>Agent \"x\" finished</summary>\n<result>我在報告裡寫了 <status>failed</status> 這幾個字</result>\n</task-notification>"}"#)
        #expect(f.outcomes["a8888888888888888"]?.kind == .completed)
    }

    @Test("沒見過的 <status> 值整筆跳過 —— 不猜，也不當成 unknown 的一格")
    func anUnknownStatusValueIsSkipped() {
        var f = TranscriptFacts()
        f.ingest(#"{"type":"queue-operation","operation":"enqueue","content":"<task-notification>\n<task-id>a7777777777777777</task-id>\n<status>timed_out</status>\n<summary>Agent \"x\" finished</summary>\n</task-notification>"}"#)
        #expect(f.outcomes.isEmpty)
    }

    @Test("同一隻重複通知 —— 最後一筆贏，而且只算一隻")
    func lastWriteWinsPerAgent() {
        var f = TranscriptFacts()
        let mk = { (status: String) in
            #"{"type":"queue-operation","operation":"enqueue","content":"<task-notification>\n<task-id>a6666666666666666</task-id>\n<status>"# + status
                + #"</status>\n<summary>Agent \"x\" finished</summary>\n</task-notification>"}"#
        }
        f.ingest(mk("completed"))
        f.ingest(mk("killed"))
        #expect(f.outcomes.count == 1)
        #expect(f.outcomes["a6666666666666666"]?.kind == .killed)
    }

    @Test("完成的時刻取那一筆記錄自己的 timestamp —— 不是現在，也不是檔案時間")
    func theTimeComesFromTheRecord() throws {
        let f = try facts(["notify-enqueue"])
        let at = try #require(f.outcomes["a3333333333333333"]?.at)
        // fixture 那一行寫的是 2026-09-22T06:19:58.695Z。
        #expect(abs(at.timeIntervalSince1970 - 1790057998.695) < 0.01)
    }

    // ── 開出去的那一筆 ─────────────────────────────────────────

    @Test("同步的 agent：那一筆 tool_result 本身就是完成，不會再有通知")
    func aSynchronousSpawnIsItsOwnCompletion() throws {
        let f = try facts(["spawn-sync"])
        #expect(f.outcomes["a2222222222222222"]?.kind == .completed)
    }

    @Test("⚠️ async_launched 不是一種下場 —— 開出去了不等於做完了")
    func anAsyncSpawnHasNoOutcomeYet() throws {
        let f = try facts(["spawn-async"])
        // 這一筆在磁碟上帶著 `"status":"async_launched"`。把它讀成完成就是謊報，
        // 而且方向最糟：一隻剛開始跑的 agent 會在面板上顯示成已完成。
        #expect(f.outcomes["a1111111111111111"] == nil)
    }

    // ── 既有用途：tool_use id ──────────────────────────────────

    @Test("順手把 tool_use 的 id 收走 —— 這是既有行為，不可以退步")
    func toolUseIdsAreStillCollected() {
        var f = TranscriptFacts()
        f.ingest(#"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"toolu_ABC"},{"type":"text","text":"x"}]}}"#)
        #expect(f.toolUseIds == ["toolu_ABC"])
    }

    @Test("垃圾行不可以爆，也不可以污染結果")
    func garbageIsIgnored() {
        var f = TranscriptFacts()
        for junk in ["", "{", "null", "[]", "not json at all", #"{"type":"user"}"#] {
            f.ingest(junk)
        }
        #expect(f.outcomes.isEmpty)
        #expect(f.toolUseIds.isEmpty)
    }
}
