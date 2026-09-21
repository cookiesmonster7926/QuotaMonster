import Testing
import Foundation
@testable import QuotaMonsterCore

/// 額度現在有兩個來源，而且它們會吵架：
///   - `~/.claude.json` 的 `cachedUsageUtilization` —— 實測可以 16 小時不更新，
///     而且已經重置的窗口還留在裡面
///   - statusline tee 的快取 —— 跟著 API 回應走，秒級，過期的窗口會被拿掉
///
/// 這組測試釘住的核心決定是：**整筆快照只能有一個來源，不可以東拼西湊。**
/// 兩邊的 five_hour 可能屬於不同的窗口（一邊已重置、一邊還沒），
/// 拼在同一列會產生一組互相矛盾、但看起來完全正常的數字。
@Suite("UsageSourceSelector")
struct UsageSourceSelectorTests {

    let now = Fixture.now

    func claudeJSON(ageSeconds: TimeInterval, five: Int = 30, seven: Int = 19) -> UsageSnapshot {
        let fetchedAt = now.addingTimeInterval(-ageSeconds)
        return UsageSnapshot(
            fiveHour: UsageWindow(percent: five, resetsAt: now.addingTimeInterval(3600)),
            sevenDay: UsageWindow(percent: seven, resetsAt: now.addingTimeInterval(86400)),
            perModel: [:],
            freshness: ClaudeJSONUsageReader.freshness(fetchedAt: fetchedAt, now: now),
            fetchedAt: fetchedAt)
    }

    func statusLine(ageSeconds: TimeInterval, five: Int? = 9, seven: Int? = 42,
                    sessionId: String = "s1") -> StatusLinePayload {
        StatusLinePayload(
            sessionId: sessionId,
            capturedAt: now.addingTimeInterval(-ageSeconds),
            contextUsedPercent: 27,
            contextWindowSize: 1_000_000,
            fiveHour: five.map { UsageWindow(percent: $0, resetsAt: now.addingTimeInterval(7200)) },
            sevenDay: seven.map { UsageWindow(percent: $0, resetsAt: now.addingTimeInterval(172800)) })
    }

    @Test("statusline 較新時勝出")
    func fresherStatusLineWins() throws {
        let picked = try #require(UsageSourceSelector.pick(
            claudeJSON: claudeJSON(ageSeconds: 16 * 3600),
            statusLine: [statusLine(ageSeconds: 30)], now: now))
        #expect(picked.source == .statusLine)
        #expect(picked.snapshot.fiveHour?.percent == 9)
        #expect(picked.snapshot.sevenDay?.percent == 42)
    }

    @Test("statusline 較舊時退回 ~/.claude.json —— 整天沒開 session 就會這樣")
    func stalerStatusLineLoses() throws {
        let picked = try #require(UsageSourceSelector.pick(
            claudeJSON: claudeJSON(ageSeconds: 60),
            statusLine: [statusLine(ageSeconds: 6 * 3600)], now: now))
        #expect(picked.source == .claudeJSON)
        #expect(picked.snapshot.fiveHour?.percent == 30)
    }

    @Test("沒有 statusline 快取時退回 ~/.claude.json")
    func noStatusLineFallsBack() throws {
        let picked = try #require(UsageSourceSelector.pick(
            claudeJSON: claudeJSON(ageSeconds: 120), statusLine: [], now: now))
        #expect(picked.source == .claudeJSON)
    }

    @Test("沒有 ~/.claude.json 快取時照樣用 statusline")
    func noClaudeJSONStillWorks() throws {
        let picked = try #require(UsageSourceSelector.pick(
            claudeJSON: nil, statusLine: [statusLine(ageSeconds: 30)], now: now))
        #expect(picked.source == .statusLine)
    }

    @Test("兩個來源都沒有時回 nil —— 絕不可以回一個全 0 的快照")
    func nothingYieldsNil() {
        #expect(UsageSourceSelector.pick(claudeJSON: nil, statusLine: [], now: now) == nil)
    }

    @Test("一個窗口都沒有的 payload 不算額度來源")
    func payloadWithoutAnyWindowIsNotASource() throws {
        let contextOnly = StatusLinePayload(sessionId: "s1", capturedAt: now,
                                            contextUsedPercent: 27, contextWindowSize: 1_000_000)
        let picked = try #require(UsageSourceSelector.pick(
            claudeJSON: claudeJSON(ageSeconds: 16 * 3600),
            statusLine: [contextOnly], now: now))
        #expect(picked.source == .claudeJSON)
    }

    @Test("多個 session 時取最新的那一份 —— 額度是帳號層級的，誰寫的都一樣")
    func newestPayloadWins() throws {
        let picked = try #require(UsageSourceSelector.pick(
            claudeJSON: nil,
            statusLine: [statusLine(ageSeconds: 600, five: 5, sessionId: "old"),
                         statusLine(ageSeconds: 10, five: 9, sessionId: "new"),
                         statusLine(ageSeconds: 300, five: 7, sessionId: "mid")],
            now: now))
        #expect(picked.snapshot.fiveHour?.percent == 9)
    }

    @Test("statusline 少了 five_hour 時不從另一個來源硬湊")
    func missingWindowIsNotBackfilled() throws {
        let picked = try #require(UsageSourceSelector.pick(
            claudeJSON: claudeJSON(ageSeconds: 16 * 3600, five: 30),
            statusLine: [statusLine(ageSeconds: 30, five: nil)], now: now))
        #expect(picked.source == .statusLine)
        #expect(picked.snapshot.fiveHour == nil)      // 不是 30
        #expect(picked.snapshot.sevenDay?.percent == 42)
    }

    @Test("新鮮度算的是被選中那個來源自己的年齡")
    func freshnessFollowsTheChosenSource() throws {
        let live = try #require(UsageSourceSelector.pick(
            claudeJSON: nil, statusLine: [statusLine(ageSeconds: 30)], now: now))
        #expect(live.snapshot.freshness == .live)

        let aging = try #require(UsageSourceSelector.pick(
            claudeJSON: nil, statusLine: [statusLine(ageSeconds: 23 * 60)], now: now))
        #expect(aging.snapshot.freshness == .aging(minutes: 23))

        let expired = try #require(UsageSourceSelector.pick(
            claudeJSON: nil, statusLine: [statusLine(ageSeconds: 61 * 60)], now: now))
        #expect(expired.snapshot.freshness == .expired)
    }

    @Test("被選中的快照帶得出它的擷取時間")
    func snapshotCarriesItsFetchTime() throws {
        let picked = try #require(UsageSourceSelector.pick(
            claudeJSON: nil, statusLine: [statusLine(ageSeconds: 45)], now: now))
        #expect(abs(picked.snapshot.fetchedAt.timeIntervalSince(now) + 45) < 0.001)
    }

    @Test("只有 spend_limit 的 payload 不算額度來源 —— 快照根本不帶這個窗口")
    func spendLimitOnlyPayloadIsNotASource() throws {
        // five_hour 與 seven_day 都因為已重置而被丟掉，只剩 gateway 的 spend_limit。
        // 讓它勝出的話，使用者會拿到一筆「更新、但三個數字全是 —」的快照，
        // 比顯示一個 16 小時前的舊數字還糟。
        let spendOnly = StatusLinePayload(
            sessionId: "s1", capturedAt: now,
            spendLimit: UsageWindow(percent: 63, resetsAt: now.addingTimeInterval(2_592_000)))
        let picked = try #require(UsageSourceSelector.pick(
            claudeJSON: claudeJSON(ageSeconds: 16 * 3600),
            statusLine: [spendOnly], now: now))
        #expect(picked.source == .claudeJSON)
        #expect(picked.snapshot.fiveHour?.percent == 30)
    }

    @Test("statusline 這個來源沒有 per-model 窗口，不可以憑空生出來")
    func statusLineHasNoPerModelWindows() throws {
        let picked = try #require(UsageSourceSelector.pick(
            claudeJSON: nil, statusLine: [statusLine(ageSeconds: 30)], now: now))
        #expect(picked.snapshot.perModel.isEmpty)
    }
}
