import Testing
import Foundation
@testable import QuotaMonsterCore

/// `~/.claude.json` 的 `cachedUsageUtilization` 是未公開欄位。
/// 從 v2.1.274 二進位檔逆向出來的規則（本測試釘住的就是這些）：
///   - 寫入端 `_0r` 有 **硬性 5 分鐘節流**（azo = 300000）
///   - 讀取端 `u6n` 把 **age > 60 分鐘** 的視為過期並回傳 null（izo = 3600000）
///   - `accountUuid` 不符就整個清空
/// 我們沿用同一套規則，不自己發明門檻。
@Suite("ClaudeJSONUsageReader")
struct ClaudeJSONUsageReaderTests {

    let reader = ClaudeJSONUsageReader()

    @Test("新鮮的讀數（42 秒）視為 live")
    func freshReadingIsLive() throws {
        let s = try #require(try reader.read(try Fixture.url("claude_json/fresh.json"),
                                             now: Fixture.now, expectedAccount: Fixture.account))
        #expect(s.fiveHour?.percent == 30)
        #expect(s.sevenDay?.percent == 19)
        #expect(s.freshness == .live)
    }

    @Test("5 到 60 分鐘之間視為 aging，並帶出年齡")
    func agingReadingCarriesItsAge() throws {
        let s = try #require(try reader.read(try Fixture.url("claude_json/aging.json"),
                                             now: Fixture.now, expectedAccount: Fixture.account))
        #expect(s.freshness == .aging(minutes: 23))
    }

    @Test("超過 60 分鐘視為 expired —— 沿用 Claude Code 自己的 izo = 3600000")
    func pastSixtyMinutesIsExpired() throws {
        let s = try #require(try reader.read(try Fixture.url("claude_json/expired.json"),
                                             now: Fixture.now, expectedAccount: Fixture.account))
        #expect(s.freshness == .expired)
    }

    @Test("過期時仍然保留最後已知數值，由 UI 決定怎麼呈現")
    func expiredStillCarriesLastKnownValues() throws {
        let s = try #require(try reader.read(try Fixture.url("claude_json/expired.json"),
                                             now: Fixture.now, expectedAccount: Fixture.account))
        #expect(s.fiveHour?.percent == 30)
    }

    @Test("accountUuid 不符時不得回傳任何讀數")
    func accountMismatchYieldsNothing() throws {
        let s = try reader.read(try Fixture.url("claude_json/account_mismatch.json"),
                                now: Fixture.now, expectedAccount: Fixture.account)
        #expect(s == nil)
    }

    @Test("沒有 cachedUsageUtilization 這個 key 時回傳 nil，不得丟錯")
    func absentCacheYieldsNil() throws {
        let s = try reader.read(try Fixture.url("claude_json/no_cache.json"),
                                now: Fixture.now, expectedAccount: Fixture.account)
        #expect(s == nil)
    }

    @Test("缺少的窗口是 nil，絕不可以是 0")
    func missingWindowIsNilNotZero() throws {
        let s = try #require(try reader.read(try Fixture.url("claude_json/missing_windows.json"),
                                             now: Fixture.now, expectedAccount: Fixture.account))
        #expect(s.fiveHour?.percent == 30)
        #expect(s.sevenDay == nil)   // 0% 與「不知道」在視覺上必須不同
    }

    @Test("未知的新窗口不得讓解析失敗（zod 的 passthrough 行為）")
    func unknownWindowsDoNotBreakParsing() throws {
        let s = try #require(try reader.read(try Fixture.url("claude_json/unknown_keys.json"),
                                             now: Fixture.now, expectedAccount: Fixture.account))
        #expect(s.fiveHour?.percent == 30)
    }

    @Test("resets_at 的 ISO-8601 字串要被解析成 Date")
    func resetsAtIsParsed() throws {
        let s = try #require(try reader.read(try Fixture.url("claude_json/fresh.json"),
                                             now: Fixture.now, expectedAccount: Fixture.account))
        let reset = try #require(s.fiveHour?.resetsAt)
        #expect(abs(reset.timeIntervalSince1970 - 1_789_674_000.662588) < 0.001)
    }

    @Test("expectedAccount 傳 nil 時不檢查帳號")
    func nilExpectedAccountSkipsTheCheck() throws {
        let s = try reader.read(try Fixture.url("claude_json/account_mismatch.json"),
                                now: Fixture.now, expectedAccount: nil)
        #expect(s != nil)
    }
}
