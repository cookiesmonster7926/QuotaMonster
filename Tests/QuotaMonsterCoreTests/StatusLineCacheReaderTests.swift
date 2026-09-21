import Testing
import Foundation
@testable import QuotaMonsterCore

/// tee 寫出來的快取是 Claude Code 餵給 statusLine 的 payload 原文。
/// 這組測試釘住的規則有兩個獨立來源互相對過帳：官方文件
/// （code.claude.com/docs/en/statusline）與 v2.1.276 二進位檔的 `U$o` payload builder，
/// 而 `Fixtures/statusline/live.json` 本身就是實機跑出來、去識別化過的真實 payload。
///
/// 最容易寫錯、而且錯了不會報錯的三件事：
///   - `resets_at` 在這裡是 **Unix epoch 秒**（`~/.claude.json` 那邊是 ISO-8601 字串）
///   - `rate_limits.*.used_percentage` 是**浮點**（二進位 `wQe` = `Math.round(t*1000)/10`），
///     `context_window.used_percentage` 卻是**整數**（`yVt` 的 `Math.round`）
///   - 窗口的 `resets_at` 一過，Claude Code 直接把整個窗口從 payload 拿掉
///     （二進位 `MSn` 過濾），所以**缺席 ≠ 0%**
@Suite("StatusLineCacheReader")
struct StatusLineCacheReaderTests {

    let reader = StatusLineCacheReader()

    func read(_ fixtures: [String], age: TimeInterval = 30) throws -> [StatusLinePayload] {
        let dir = try Fixture.statuslineDirectory(fixtures, age: age)
        return reader.read(directory: dir, now: Fixture.now)
    }

    func one(_ fixture: String, age: TimeInterval = 30) throws -> StatusLinePayload {
        try #require(try read([fixture], age: age).first)
    }

    // ── 額度窗口 ──────────────────────────────────────────────────

    @Test("真實 payload 的兩個窗口都讀得出來")
    func realPayloadYieldsBothWindows() throws {
        let p = try one("live")
        #expect(p.fiveHour?.percent == 9)
        #expect(p.sevenDay?.percent == 42)
        #expect(p.sessionId == "11111111-1111-4111-8111-111111111111")
    }

    @Test("resets_at 是 epoch 秒，不是毫秒也不是 ISO-8601")
    func resetsAtIsEpochSeconds() throws {
        let p = try one("live")
        let reset = try #require(p.fiveHour?.resetsAt)
        #expect(abs(reset.timeIntervalSince1970 - 1_789_667_200) < 0.001)
    }

    @Test("used_percentage 是浮點，30.6 要四捨五入成 31 而不是截成 30")
    func fractionalPercentIsRoundedNotTruncated() throws {
        let p = try one("fractional")
        #expect(p.fiveHour?.percent == 31)
        #expect(p.sevenDay?.percent == 41)
    }

    @Test("整個 rate_limits 缺席時兩個窗口都是 nil，絕不可以是 0")
    func absentRateLimitsAreNilNotZero() throws {
        let p = try one("no_rate_limits")
        #expect(p.fiveHour == nil)
        #expect(p.sevenDay == nil)
    }

    @Test("Claude Code 已經丟掉的窗口，我們不可以無中生有")
    func droppedWindowStaysDropped() throws {
        let p = try one("window_dropped")
        #expect(p.fiveHour == nil)
        #expect(p.sevenDay?.percent == 42)
    }

    @Test("resets_at 已經過去的窗口回 nil —— 那是一個不存在的窗口的數字")
    func windowWhoseResetPassedIsDropped() throws {
        let p = try one("reset_passed")
        #expect(p.fiveHour == nil)
        #expect(p.sevenDay?.percent == 42)
    }

    @Test("gateway 才有的 spend_limit 也要讀得出來")
    func spendLimitWindowIsParsed() throws {
        let p = try one("spend_limit")
        #expect(p.spendLimit?.percent == 63)
    }

    // ── context 壓力 ──────────────────────────────────────────────

    @Test("context 的 used_percentage 是整數，連同視窗大小一起讀出")
    func contextPressureIsParsed() throws {
        let p = try one("live")
        #expect(p.contextUsedPercent == 27)
        #expect(p.contextWindowSize == 1_000_000)
        #expect(p.totalInputTokens == 274_547)
    }

    @Test("/compact 之後 context 是 null，那與 0% 是兩回事")
    func nullContextIsNilNotZero() throws {
        let p = try one("null_context")
        #expect(p.contextUsedPercent == nil)
        #expect(p.contextWindowSize == 1_000_000)
    }

    @Test("連 context_window 都沒有時仍然是一筆合法的 payload")
    func minimalPayloadStillParses() throws {
        let p = try one("minimal")
        #expect(p.sessionId == "11111111-1111-4111-8111-111111111111")
        #expect(p.contextUsedPercent == nil)
        #expect(p.fiveHour == nil)
    }

    // ── 目錄掃描的規矩 ────────────────────────────────────────────

    @Test("未來版本新增的鍵不可造成解析失敗")
    func unknownKeysAreHarmless() throws {
        let p = try one("unknown_keys")
        #expect(p.fiveHour?.percent == 9)
        #expect(p.sevenDay?.percent == 42)
    }

    @Test("讀到 0 bytes 要跳過，不可丟錯 —— 那是寫入中的正常現象")
    func zeroByteFileIsSkipped() throws {
        let payloads = try read(["live", "zero_bytes"])
        #expect(payloads.count == 1)
    }

    @Test("截斷的 JSON 要跳過，不可丟錯 —— SIGKILL 會留下這種東西")
    func truncatedFileIsSkipped() throws {
        let payloads = try read(["live", "truncated"])
        #expect(payloads.count == 1)
    }

    @Test("以點開頭的檔案要略過 —— .tmp.* 是寫到一半的暫存檔")
    func dotFilesAreSkipped() throws {
        let dir = try Fixture.statuslineDirectory([
            (fixture: "live", filename: "live.json", age: 30),
            (fixture: "other_session", filename: ".tmp.4242", age: 5),
        ])
        let payloads = reader.read(directory: dir, now: Fixture.now)
        #expect(payloads.count == 1)
        #expect(payloads.first?.sessionId == "11111111-1111-4111-8111-111111111111")
    }

    @Test("不是 .json 的檔案要略過")
    func nonJSONFilesAreSkipped() throws {
        let dir = try Fixture.statuslineDirectory([
            (fixture: "live", filename: "live.json", age: 30),
            (fixture: "other_session", filename: "notes.txt", age: 5),
        ])
        #expect(reader.read(directory: dir, now: Fixture.now).count == 1)
    }

    @Test("目錄不存在時回空陣列，不丟錯")
    func missingDirectoryYieldsEmpty() {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-does-not-exist-\(UUID().uuidString)")
        #expect(reader.read(directory: dir, now: Fixture.now).isEmpty)
    }

    @Test("擷取時間來自檔案 mtime —— payload 裡沒有時間戳")
    func capturedAtComesFromFileModificationDate() throws {
        let p = try one("live", age: 120)
        #expect(abs(p.capturedAt.timeIntervalSince(Fixture.now) + 120) < 1)
    }

    @Test("多個 session 各自是一筆，context 壓力不會互相汙染")
    func eachSessionIsItsOwnPayload() throws {
        let payloads = try read(["live", "other_session"])
        #expect(payloads.count == 2)
        let byId = Dictionary(uniqueKeysWithValues: payloads.map { ($0.sessionId ?? "", $0) })
        #expect(byId["11111111-1111-4111-8111-111111111111"]?.contextUsedPercent == 27)
        #expect(byId["11111111-1111-4111-8111-111111111112"]?.contextUsedPercent == 71)
    }

    // ── code review 補的：荒謬輸入不可以讓 app 當掉或說謊 ──────────

    @Test("荒謬的百分比不可以讓整個 app 當掉 —— Int(Double) 超出範圍會 trap")
    func absurdPercentDoesNotTrap() throws {
        let p = try one("absurd_percent")
        // 1e20 不是一個百分比。要嘛夾住，要嘛當成沒讀數，就是不可以 trap。
        if let five = p.fiveHour { #expect(five.percent <= 1000) }
        // 負的百分比一樣不是讀數
        #expect(p.sevenDay == nil)
    }

    @Test("百分比是字串而不是數字時回 nil，不可以生出一個假的數字")
    func stringPercentIsNotANumber() throws {
        let p = try one("string_percent")
        #expect(p.fiveHour == nil)
    }

    @Test("resets_at 遠在一年以後的視為不合理 —— 二進位 MSn 的上界我們也要實作")
    func absurdlyFarResetIsRejected() throws {
        let p = try one("far_future_reset")
        #expect(p.fiveHour == nil)
        #expect(p.sevenDay?.percent == 42)
    }

    @Test("resets_at 剛好等於現在就算已經重置")
    func resetExactlyNowCountsAsPassed() throws {
        let dir = try Fixture.statuslineDirectory([])
        let src = try Fixture.url("statusline/live.json")
        var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: src)) as! [String: Any]
        var limits = obj["rate_limits"] as! [String: Any]
        limits["five_hour"] = ["used_percentage": 9,
                               "resets_at": Fixture.now.timeIntervalSince1970]
        obj["rate_limits"] = limits
        let dst = dir.appendingPathComponent("boundary.json")
        try JSONSerialization.data(withJSONObject: obj).write(to: dst)

        let p = try #require(reader.read(directory: dir, now: Fixture.now).first)
        #expect(p.fiveHour == nil)
    }

    @Test("mtime 在未來的檔案，擷取時間要夾到現在 —— 否則它永遠是「剛更新」")
    func futureModificationDateIsClampedToNow() throws {
        let p = try one("live", age: -3600)          // 一小時後
        #expect(p.capturedAt <= Fixture.now)
    }

    @Test("以點開頭但副檔名是 .json 的檔案也要略過")
    func dotFileEndingInJSONIsAlsoSkipped() throws {
        // 原本的測試用 .tmp.4242 —— 它不是 .json，所以就算把開頭是點的判斷拿掉也會通過。
        // 這個案例讓那條判斷成為唯一能救它的東西。
        let dir = try Fixture.statuslineDirectory([
            (fixture: "live", filename: "live.json", age: 30),
            (fixture: "other_session", filename: ".hidden.json", age: 5),
        ])
        let payloads = reader.read(directory: dir, now: Fixture.now)
        #expect(payloads.count == 1)
        #expect(payloads.first?.sessionId == "11111111-1111-4111-8111-111111111111")
    }

    @Test("沒有 session_id 的 payload 仍然收下 —— 額度是帳號層級的，與 session 無關")
    func payloadWithoutSessionIdIsStillUsable() throws {
        let dir = try Fixture.statuslineDirectory([])
        let src = try Fixture.url("statusline/live.json")
        var obj = try JSONSerialization.jsonObject(with: Data(contentsOf: src)) as! [String: Any]
        obj.removeValue(forKey: "session_id")
        let dst = dir.appendingPathComponent("_unkeyed.json")
        try JSONSerialization.data(withJSONObject: obj).write(to: dst)
        try FileManager.default.setAttributes([.modificationDate: Fixture.now],
                                              ofItemAtPath: dst.path)

        let p = try #require(reader.read(directory: dir, now: Fixture.now).first)
        #expect(p.sessionId == nil)
        #expect(p.fiveHour?.percent == 9)
    }
}
