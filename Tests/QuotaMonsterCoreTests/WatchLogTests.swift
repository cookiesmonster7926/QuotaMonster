import Testing
import Foundation
@testable import QuotaMonsterCore

/// 「那一天沒有用量」與「那一天我們沒在看」是兩件事。
///
/// ### 為什麼需要它
/// `usage-history.jsonl` 是**事件驅動**的：`shouldRecord` 只在數字變了才寫。
/// 對「值」來說那是無損的（階梯函數的每個台階都抓到了），但它讓「某一天沒有任何
/// 一行」變成一個**雙關**：可能是那天沒用，也可能是 app 那天沒開。
/// 每日長條圖必須分得出來，否則它會把「我沒在看」畫成「你沒有用」。
///
/// ### ⚠️ 為什麼是另一個檔案，不是在原本那個裡面加一種行
/// 這一步當初被擱置的理由（`docs/build-log.md:1190`）是：
/// 「程式碼很便宜，但它會改變『檔案裡沒有那一行』的意思，而那是**不可逆的
/// 語意變更**。」那個反對是對的 —— 一旦心跳混進去，舊資料與新資料的
/// 「沒有那一行」就永遠分不出來了。
///
/// 寫進 `watch-log.jsonl` 之後，`usage-history.jsonl` 的語意一個字都沒動，
/// 而且要反悔只要刪掉這個檔。**不可逆的部分被拿掉了，所以這一步可以做。**
@Suite("觀測紀錄")
struct WatchLogTests {

    let now = Fixture.now

    // ── 節奏 ───────────────────────────────────────────────────

    @Test("五分鐘寫一次 —— 這個數字有成本計算撐著")
    func intervalIsFiveMinutes() {
        #expect(WatchLog.interval == 300)
        // 288 行／天 × 30 天保留 ≈ 8,640 行 ≈ 190KB。
        // 日界的歸屬誤差上限是一個間隔：5 分鐘 / 1440 分鐘 = 0.35% 的一天。
        #expect(WatchLog.retention == 30 * 86400)
    }

    @Test("還沒到間隔就不寫 —— 面板每 3 秒刷新，不可以每次都寫檔")
    func throttles() {
        #expect(WatchLog.shouldWrite(lastWatchMark: now.addingTimeInterval(-1), now: now) == false)
        #expect(WatchLog.shouldWrite(lastWatchMark: now.addingTimeInterval(-299), now: now) == false)
        #expect(WatchLog.shouldWrite(lastWatchMark: now.addingTimeInterval(-300), now: now))
    }

    @Test("從來沒寫過就要寫 —— nil 不是「剛寫過」")
    func firstWriteAlwaysHappens() {
        #expect(WatchLog.shouldWrite(lastWatchMark: nil, now: now))
    }

    // ── 讀寫 ───────────────────────────────────────────────────

    func tmp() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-watch-\(UUID().uuidString)")
            .appendingPathComponent("watch-log.jsonl")
    }

    @Test("寫得進去、讀得回來，而且分得出心跳與開機")
    func roundTrips() throws {
        let url = tmp(), log = WatchLog()
        #expect(log.append(WatchLog.Mark(at: now, kind: .boot), to: url))
        #expect(log.append(WatchLog.Mark(at: now.addingTimeInterval(300), kind: .heartbeat), to: url))
        let back = log.read(url)
        #expect(back.count == 2)
        #expect(back.first?.kind == .boot)
        #expect(back.last?.kind == .heartbeat)
        #expect(back.last?.at == now.addingTimeInterval(300))
    }

    @Test("壞掉的行跳過，不是整個放棄 —— append-only 的最後一行可能只寫到一半")
    func survivesATruncatedLine() throws {
        let url = tmp()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        // 一行好的、一行只寫到一半、一行完全不是 JSON
        let t = Int(now.timeIntervalSince1970)
        let good = "{" + "\"t\":\(t),\"k\":\"hb\"" + "}"
        let half = "{" + "\"t\":\(t + 1)"          // 沒有收尾的大括號
        try (good + "\n" + half + "\n垃圾\n").write(to: url, atomically: true, encoding: .utf8)
        let back = WatchLog().read(url)
        #expect(back.count == 1)
        #expect(back.first?.at == now)
    }

    @Test("讀不到檔案回空陣列，不丟錯 —— 這是純加值功能")
    func missingFileIsEmpty() {
        #expect(WatchLog().read(tmp()).isEmpty)
    }

    // ── 日界有沒有被看著 ───────────────────────────────────────

    @Test("日界前後有心跳 → 那個邊界是可信的")
    func boundaryCoveredByNearbyMark() {
        let marks = [WatchLog.Mark(at: now.addingTimeInterval(-120), kind: .heartbeat,
                                   sawLiveReading: true),
                     WatchLog.Mark(at: now.addingTimeInterval(120), kind: .heartbeat,
                                   sawLiveReading: true)]
        #expect(WatchLog.covers(now, marks: marks))
    }

    @Test("日界附近完全沒有心跳 → 不可信（app 那時沒開）")
    func boundaryWithoutMarksIsNotCovered() {
        let marks = [WatchLog.Mark(at: now.addingTimeInterval(-9999), kind: .heartbeat,
                                   sawLiveReading: true),
                     WatchLog.Mark(at: now.addingTimeInterval(9999), kind: .heartbeat,
                                   sawLiveReading: true)]
        #expect(WatchLog.covers(now, marks: marks) == false)
    }

    @Test("容差是一個間隔的兩倍 —— 一次漏寫不該讓整天作廢")
    func toleranceIsTwoIntervals() {
        #expect(WatchLog.boundaryTolerance == WatchLog.interval * 2)
        let just = [WatchLog.Mark(at: now.addingTimeInterval(-599), kind: .heartbeat, sawLiveReading: true)]
        #expect(WatchLog.covers(now, marks: just))
        let tooFar = [WatchLog.Mark(at: now.addingTimeInterval(-601), kind: .heartbeat, sawLiveReading: true)]
        #expect(WatchLog.covers(now, marks: tooFar) == false)
    }

    @Test("完全沒有紀錄 → 不可信。**沒有紀錄不是「有在看」的證據**")
    func noMarksMeansNotCovered() {
        #expect(WatchLog.covers(now, marks: []) == false)
    }

    // ── 清理 ───────────────────────────────────────────────────

    @Test("超過保留期的丟掉；沒有東西過期就一個位元組都不碰")
    func prunesOnlyWhenNeeded() throws {
        let url = tmp(), log = WatchLog()
        _ = log.append(WatchLog.Mark(at: now.addingTimeInterval(-31 * 86400), kind: .heartbeat), to: url)
        _ = log.append(WatchLog.Mark(at: now, kind: .heartbeat), to: url)
        #expect(log.prune(url, now: now))
        #expect(log.read(url).count == 1)
        #expect(log.prune(url, now: now) == false, "沒有東西過期就不該重寫整個檔")
    }
}

/// 心跳要記的不是「app 醒著」，是「**當時看得到帳號的變化**」。
///
/// ### 為什麼這是兩件事
/// 〔實測 2026-09-22〕18.8 小時裡有 16.1 小時（**85%**）這台機器沒有渲染狀態列
/// （含一段 11.5 小時的整夜空窗），而 QuotaMonster 在那段時間是**醒著的**。
///
/// `7d` 是**帳號層級**的 —— 別人、別的裝置燒掉的都算在裡面。但我們只在
/// 這台機器渲染狀態列時才看得到那個數字。所以「醒著」不等於「看得到」。
///
/// 後果：別人半夜燒掉 30% 的那一天，心跳有、取樣點沒有 →
/// 圖上畫成 **0%，滿分信心**。那是這張圖最容易犯、最難發現的謊。
@Suite("觀測紀錄 — 讀數活不活")
struct WatchLogLivenessTests {
    let now = Fixture.now

    @Test("心跳要帶得出「那一刻讀數是不是活的」")
    func markCarriesLiveness() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-live-\(UUID().uuidString)")
            .appendingPathComponent("w.jsonl")
        let log = WatchLog()
        #expect(log.append(WatchLog.Mark(at: now, kind: .heartbeat, sawLiveReading: true), to: url))
        #expect(log.append(WatchLog.Mark(at: now.addingTimeInterval(300), kind: .heartbeat,
                                         sawLiveReading: false), to: url))
        let back = log.read(url)
        #expect(back.first?.sawLiveReading == true)
        #expect(back.last?.sawLiveReading == false)
    }

    @Test("⚠️ 舊格式（沒有那個欄位）一律當成**看不到** —— 不存在不是證據")
    func legacyMarksAreNotEvidence() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-legacy-\(UUID().uuidString)")
            .appendingPathComponent("w.jsonl")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let t = Int(now.timeIntervalSince1970)
        try ("{" + "\"t\":\(t),\"k\":\"hb\"" + "}\n").write(to: url, atomically: true,
                                                            encoding: .utf8)
        let back = WatchLog().read(url)
        #expect(back.count == 1)
        #expect(back.first?.sawLiveReading == false,
                "把舊資料當成『那時看得到』，等於把一段我們其實是瞎的時間宣告成可信")
    }

    @Test("covers 只算**看得到**的那些心跳")
    func coversOnlyCountsLiveMarks() {
        let blind = [WatchLog.Mark(at: now, kind: .heartbeat, sawLiveReading: false)]
        #expect(WatchLog.covers(now, marks: blind) == false,
                "醒著但看不到，不算看著那個時刻")
        let seeing = [WatchLog.Mark(at: now, kind: .heartbeat, sawLiveReading: true)]
        #expect(WatchLog.covers(now, marks: seeing))
    }

    @Test("開機標記不是觀測證據 —— 它只說『這裡是一次執行的起點』")
    func bootIsNotObservation() {
        let boot = [WatchLog.Mark(at: now, kind: .boot, sawLiveReading: false)]
        #expect(WatchLog.covers(now, marks: boot) == false)
    }
}
