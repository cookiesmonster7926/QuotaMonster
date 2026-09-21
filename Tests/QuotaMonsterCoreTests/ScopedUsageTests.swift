import Testing
import Foundation
@testable import QuotaMonsterCore

/// 分模型的用量藏在 `~/.claude.json` 的 `cachedUsageUtilization.utilization.limits`
/// 陣列裡，而不是 `seven_day_opus` 那種鍵（實測那些鍵在這個帳號上全是 null）。
///
/// 實測到的三筆長這樣：
///   kind=session       percent=30  scope=nil
///   kind=weekly_all    percent=19  scope=nil
///   kind=weekly_scoped percent=1   scope.model.display_name="Fable"
///
/// ⚠️ **這份資料只有 `~/.claude.json` 有，statusLine payload 完全沒有。**
/// 所以它的新鮮度與面板上那兩個即時數字是分開的 —— UI 必須標出它多舊，
/// 不可以讓使用者以為分模型那一列跟旁邊的總量一樣新。
@Suite("ScopedUsage")
struct ScopedUsageTests {

    let reader = ClaudeJSONUsageReader()

    @Test("從 limits 解出分模型用量")
    func parsesScopedModelUsage() throws {
        let b = try #require(try reader.readScoped(try Fixture.url("claude_json/fresh.json"),
                                                   now: Fixture.now))
        #expect(b.scoped.count == 1)
        let fable = try #require(b.scoped.first)
        #expect(fable.modelName == "Fable")
        #expect(fable.percent == 1)
    }

    @Test("session 與 weekly_all 不算分模型 —— 它們沒有 scope")
    func unscopedEntriesAreNotModels() throws {
        let b = try #require(try reader.readScoped(try Fixture.url("claude_json/fresh.json"),
                                                   now: Fixture.now))
        #expect(!b.scoped.contains { $0.modelName == "session" })
        #expect(b.scoped.allSatisfy { !$0.modelName.isEmpty })
    }

    @Test("resets_at 是 ISO-8601 字串 —— 與 statusline 的 epoch 秒不同")
    func resetsAtIsISO8601Here() throws {
        let b = try #require(try reader.readScoped(try Fixture.url("claude_json/fresh.json"),
                                                   now: Fixture.now))
        let reset = try #require(b.scoped.first?.resetsAt)
        // 2026-09-19T05:59:59Z
        #expect(reset.timeIntervalSince1970 > Fixture.now.timeIntervalSince1970)
    }

    @Test("帶出快取自己的擷取時間 —— UI 要據此標年齡")
    func carriesItsOwnFetchTime() throws {
        let b = try #require(try reader.readScoped(try Fixture.url("claude_json/fresh.json"),
                                                   now: Fixture.now))
        #expect(abs(b.fetchedAt.timeIntervalSince(Fixture.now) + 42) < 1)   // fixture 是 42 秒前
    }

    @Test("過期的快取仍然讀得出分模型，只是年齡很大 —— 由 UI 決定怎麼呈現")
    func expiredCacheStillYieldsScopedUsage() throws {
        let b = try #require(try reader.readScoped(try Fixture.url("claude_json/expired.json"),
                                                   now: Fixture.now))
        #expect(b.scoped.first?.percent == 1)
        #expect(b.age(now: Fixture.now) > 3600)
    }

    @Test("沒有 limits 時回空陣列，不是 nil 也不丟錯")
    func missingLimitsYieldsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-scoped-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("claude.json")
        let obj: [String: Any] = ["cachedUsageUtilization": [
            "fetchedAtMs": Fixture.now.timeIntervalSince1970 * 1000,
            "utilization": ["five_hour": ["utilization": 30]],
        ]]
        try JSONSerialization.data(withJSONObject: obj).write(to: url)

        let b = try #require(try reader.readScoped(url, now: Fixture.now))
        #expect(b.scoped.isEmpty)
    }

    @Test("沒有快取時回 nil")
    func noCacheYieldsNil() throws {
        #expect(try reader.readScoped(try Fixture.url("claude_json/no_cache.json"),
                                      now: Fixture.now) == nil)
    }

    @Test("scope 裡沒有 display_name 的項目要跳過，不可以生出一個空名字的模型")
    func entriesWithoutAModelNameAreSkipped() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-scoped-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("claude.json")
        let obj: [String: Any] = ["cachedUsageUtilization": [
            "fetchedAtMs": Fixture.now.timeIntervalSince1970 * 1000,
            "utilization": ["limits": [
                ["kind": "weekly_scoped", "percent": 5, "scope": ["surface": "x"]],
                ["kind": "weekly_scoped", "percent": 7,
                 "scope": ["model": ["display_name": "Opus 5"]]],
            ]],
        ]]
        try JSONSerialization.data(withJSONObject: obj).write(to: url)

        let b = try #require(try reader.readScoped(url, now: Fixture.now))
        #expect(b.scoped.count == 1)
        #expect(b.scoped.first?.modelName == "Opus 5")
    }
}
