import Testing
import Foundation
@testable import QuotaMonsterCore

/// 磁碟上**沒有任何地方**記錄額度隨時間的變化 —— Claude Code 只存「現在是多少」。
/// 所以「每日長條圖」與「燒量速率／觸頂預測」都要 app 自己累積。
///
/// tee 裝好之後這件事變得便宜：每次狀態列渲染就是一個帶時間戳的取樣點。
///
/// 兩條不可妥協的規則：
///   - **寫檔失敗絕不可以影響 app**。這是純加值功能，壞了就壞了，不准往上炸。
///   - **數字沒變就不寫**。三秒輪詢一天會有兩萬多次，全寫進去只是噪音。
@Suite("UsageHistory")
struct UsageHistoryTests {

    let history = UsageHistory()
    let now = Fixture.now

    func tempFile() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-history-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("usage-history.jsonl")
    }

    func sample(_ five: Int?, _ seven: Int?, ago: TimeInterval = 0) -> UsageSample {
        UsageSample(at: now.addingTimeInterval(-ago), fiveHour: five, sevenDay: seven)
    }

    // ── 什麼時候該寫 ──────────────────────────────────────────────

    @Test("第一筆一定要寫下來")
    func firstSampleIsAlwaysRecorded() {
        #expect(UsageHistory.shouldRecord(sample(20, 45), previous: nil))
    }

    @Test("數字完全沒變就不寫 —— 三秒輪詢一天兩萬多次，全寫只是噪音")
    func unchangedSampleIsNotRecorded() {
        #expect(!UsageHistory.shouldRecord(sample(20, 45), previous: sample(20, 45, ago: 30)))
    }

    @Test("只有 5 小時變也要寫")
    func fiveHourChangeIsRecorded() {
        #expect(UsageHistory.shouldRecord(sample(21, 45), previous: sample(20, 45, ago: 30)))
    }

    @Test("只有 7 天變也要寫")
    func sevenDayChangeIsRecorded() {
        #expect(UsageHistory.shouldRecord(sample(20, 46), previous: sample(20, 45, ago: 30)))
    }

    @Test("從有讀數變成沒讀數也是一種變化 —— 窗口重置時會發生")
    func becomingUnknownIsAChange() {
        #expect(UsageHistory.shouldRecord(sample(nil, 45), previous: sample(20, 45, ago: 30)))
    }

    @Test("兩個都沒讀數的取樣點不值得寫")
    func allUnknownIsNotWorthRecording() {
        #expect(!UsageHistory.shouldRecord(sample(nil, nil), previous: nil))
    }

    // ── 寫進去、讀回來 ────────────────────────────────────────────

    @Test("寫進去的東西讀得回來")
    func roundTrips() throws {
        let url = try tempFile()
        #expect(history.append(sample(20, 45, ago: 600), to: url))
        #expect(history.append(sample(21, 45, ago: 300), to: url))

        let back = history.read(url, now: now)
        #expect(back.count == 2)
        #expect(back.first?.fiveHour == 20)
        #expect(back.last?.fiveHour == 21)
        #expect(abs(back.last!.at.timeIntervalSince(now) + 300) < 1)
    }

    @Test("是 append-only，不會把前面的蓋掉")
    func appendsRatherThanOverwrites() throws {
        let url = try tempFile()
        for i in 0..<20 { _ = history.append(sample(i, 45, ago: TimeInterval(1000 - i)), to: url) }
        #expect(history.read(url, now: now).count == 20)
    }

    @Test("沒讀數寫成 null，讀回來仍然是 nil，不是 0")
    func unknownRoundTripsAsNil() throws {
        let url = try tempFile()
        #expect(history.append(sample(nil, 45), to: url))
        let back = try #require(history.read(url, now: now).first)
        #expect(back.fiveHour == nil)
        #expect(back.sevenDay == 45)
    }

    @Test("壞掉的行跳過，其餘照讀 —— append-only 檔的最後一行可能寫一半")
    func brokenLinesAreSkipped() throws {
        let url = try tempFile()
        _ = history.append(sample(20, 45, ago: 600), to: url)
        try "{\"t\":123,\"5h\":".appendLine(to: url)
        _ = history.append(sample(21, 45, ago: 300), to: url)
        #expect(history.read(url, now: now).count == 2)
    }

    @Test("檔案不存在時讀回空陣列，不丟錯")
    func missingFileReadsEmpty() throws {
        let url = try tempFile()
        #expect(history.read(url, now: now).isEmpty)
    }

    // ── 不可以把 app 搞壞 ─────────────────────────────────────────

    @Test("目錄不可寫時安靜失敗，不丟錯也不 crash")
    func unwritableDirectoryFailsQuietly() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-history-ro-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555],
                                              ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                       ofItemAtPath: dir.path) }

        #expect(history.append(sample(20, 45), to: dir.appendingPathComponent("h.jsonl")) == false)
    }

    @Test("上層目錄不存在時自己建出來")
    func createsTheDirectory() throws {
        let deep = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-history-\(UUID().uuidString)")
            .appendingPathComponent("nested")
            .appendingPathComponent("usage-history.jsonl")
        #expect(history.append(sample(20, 45), to: deep))
        #expect(history.read(deep, now: now).count == 1)
    }

    // ── 跨行程去重 ────────────────────────────────────────────────
    //
    // 「上一筆是什麼」放在記憶體裡，所以每個新行程都會覺得自己是第一次。
    // 實測 app 重啟三次 + 兩支診斷指令就寫出四行一模一樣的紀錄。
    // 開機時要從檔案把最後一筆讀回來當基準。

    @Test("讀得回檔案裡的最後一筆，重啟後才不會又寫一次一樣的")
    func lastSampleIsRecoverable() throws {
        let url = try tempFile()
        _ = history.append(sample(20, 45, ago: 600), to: url)
        _ = history.append(sample(21, 46, ago: 60), to: url)

        let last = try #require(history.last(url))
        #expect(last.fiveHour == 21)
        #expect(last.sevenDay == 46)
        #expect(!UsageHistory.shouldRecord(sample(21, 46), previous: last))
    }

    @Test("檔案不存在時 last 回 nil")
    func lastOfMissingFileIsNil() throws {
        #expect(history.last(try tempFile()) == nil)
    }

    @Test("最後一行寫一半時，last 回前一筆完整的")
    func lastSkipsATruncatedTail() throws {
        let url = try tempFile()
        _ = history.append(sample(20, 45, ago: 600), to: url)
        try "{\"t\":1789,\"5h\":".appendLine(to: url)
        let last = try #require(history.last(url))
        #expect(last.fiveHour == 20)
    }

    // ── 保留期 ────────────────────────────────────────────────────

    @Test("超過保留期的取樣點要清掉，沒超過的留著")
    func prunesOldSamples() throws {
        let url = try tempFile()
        _ = history.append(sample(1, 10, ago: 40 * 86400), to: url)      // 刪
        _ = history.append(sample(2, 11, ago: 31 * 86400), to: url)      // 刪
        _ = history.append(sample(3, 12, ago: 29 * 86400), to: url)      // 留
        _ = history.append(sample(4, 13, ago: 60), to: url)              // 留

        history.prune(url, now: now)
        let back = history.read(url, now: now)
        #expect(back.count == 2)
        #expect(back.map(\.fiveHour) == [3, 4])
    }

    @Test("沒有東西過期就完全不碰檔案 —— 不要為了刪零行而重寫整個檔")
    func pruneDoesNotRewriteWhenNothingExpired() throws {
        // 這支 prune 是在三秒輪詢的計時器上被呼叫的。它會把整個檔案解析一遍、
        // 重新編碼、再 tmp + rename 換掉 —— 就算一行都不必刪。
        // 保留期是 30 天，所以絕大多數時候它刪的正好是零行。
        let url = try tempFile()
        for i in 1...50 { _ = history.append(sample(i, i, ago: Double(i) * 60), to: url) }

        let before = try #require(try FileManager.default
            .attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int)
        #expect(history.prune(url, now: now) == false)
        let after = try #require(try FileManager.default
            .attributesOfItem(atPath: url.path)[.systemFileNumber] as? Int)
        // inode 沒變 = 沒有走過 replaceItemAt。
        #expect(before == after)
        #expect(history.read(url, now: now).count == 50)
    }

    @Test("真的有東西過期才重寫")
    func pruneRewritesOnlyWhenSomethingExpired() throws {
        let url = try tempFile()
        _ = history.append(sample(1, 10, ago: 40 * 86400), to: url)
        _ = history.append(sample(2, 11, ago: 60), to: url)
        #expect(history.prune(url, now: now) == true)
        #expect(history.read(url, now: now).count == 1)
    }

    @Test("歷史的清理節奏比 statusline 慢得多 —— 它清的東西以天為單位")
    func historyPrunesOnItsOwnCadence() {
        // statusline 快取的孤兒是 SIGKILL 留下的，值得每分鐘看一次；
        // 歷史的保留期是 30 天，每分鐘看一次只是在重寫同一個檔案 1440 次。
        #expect(UsageHistory.pruneInterval == 3600)
    }

    @Test("清理不存在的檔案什麼都不做，不丟錯")
    func pruningMissingFileIsHarmless() throws {
        let url = try tempFile()
        history.prune(url, now: now)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

private extension String {
    func appendLine(to url: URL) throws {
        let line = self + "\n"
        if let h = try? FileHandle(forWritingTo: url) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else {
            try line.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
