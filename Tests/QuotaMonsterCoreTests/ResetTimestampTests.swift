import Testing
import Foundation
@testable import QuotaMonsterCore

/// 這組測試存在的理由：
/// `~/.claude.json` 的 resets_at 是 **ISO-8601 字串**，
/// statusLine payload 的 resets_at 是 **Unix epoch 秒**。
/// 混用不會報錯，只會產生差了幾十年的倒數。
/// 所以統一必須發生在 parser 邊界，而且必須有測試釘住。
@Suite("ResetTimestamp")
struct ResetTimestampTests {

    /// 2026-09-17T19:40:00.662588+00:00 的 epoch 秒
    static let instant: TimeInterval = 1789674000.662588

    @Test("ISO-8601 帶小數秒與時區位移可以解析")
    func parsesISO8601WithFractionalSeconds() throws {
        let d = try ResetTimestamp.parse(.iso8601("2026-09-17T19:40:00.662588+00:00"))
        #expect(abs(d.timeIntervalSince1970 - Self.instant) < 0.001)
    }

    @Test("epoch 秒可以解析")
    func parsesEpochSeconds() throws {
        let d = try ResetTimestamp.parse(.epochSeconds(1789674000))
        #expect(abs(d.timeIntervalSince1970 - 1789674000) < 0.001)
    }

    @Test("兩種格式描述同一時刻時必須解出相同的 Date")
    func bothFormatsAgree() throws {
        let a = try ResetTimestamp.parse(.iso8601("2026-09-17T19:40:00.662588+00:00"))
        let b = try ResetTimestamp.parse(.epochSeconds(1789674000))
        #expect(abs(a.timeIntervalSince(b)) < 1.0)
    }

    @Test("epoch 秒絕不可被當成毫秒解讀")
    func epochIsNeverMilliseconds() throws {
        let d = try ResetTimestamp.parse(.epochSeconds(1789674000))
        // 若誤當毫秒，會得到 1970-01-21 附近
        #expect(d.timeIntervalSince1970 > 1_000_000_000)
    }

    @Test("不帶小數秒的 ISO-8601 也要能解析")
    func parsesISO8601WithoutFractionalSeconds() throws {
        let d = try ResetTimestamp.parse(.iso8601("2026-09-19T05:59:59+00:00"))
        #expect(d.timeIntervalSince1970 > 1_000_000_000)
    }

    @Test("Z 結尾的 ISO-8601 也要能解析")
    func parsesISO8601WithZulu() throws {
        let d = try ResetTimestamp.parse(.iso8601("2026-09-17T19:40:00Z"))
        #expect(abs(d.timeIntervalSince1970 - 1789674000) < 1.0)
    }

    @Test("無法解析時要丟錯，不可回傳 distantPast 之類的假值")
    func rejectsGarbage() {
        #expect(throws: (any Error).self) {
            try ResetTimestamp.parse(.iso8601("not a date"))
        }
    }

    @Test("剩餘時間以 now 為基準計算，已過期回傳 nil")
    func remainingIsNilWhenPassed() throws {
        let past = try ResetTimestamp.parse(.epochSeconds(1789674000))
        let now = Date(timeIntervalSince1970: 1789674001)
        #expect(ResetTimestamp.remaining(until: past, now: now) == nil)
    }

    @Test("尚未到期時回傳正的秒數")
    func remainingIsPositiveBeforeReset() throws {
        let future = try ResetTimestamp.parse(.epochSeconds(1789674000))
        let now = Date(timeIntervalSince1970: 1789674000 - 7200)
        let r = try #require(ResetTimestamp.remaining(until: future, now: now))
        #expect(abs(r - 7200) < 1.0)
    }
}
