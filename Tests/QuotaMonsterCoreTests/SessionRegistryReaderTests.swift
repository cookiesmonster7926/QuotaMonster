import Testing
import Foundation
@testable import QuotaMonsterCore

/// `~/.claude/sessions/<pid>.json` 是 Claude Code 自己維護的即時 session 註冊表。
/// 從 v2.1.274 二進位檔取出的權威狀態機：
///   status 列舉 = ["busy", "shell", "idle", "waiting"]
///   狀態映射    = { running: "busy", requires_action: "waiting", idle: "idle" }
///   waitingFor 只在 status == "waiting" 時存在，值只有兩個
/// 這個檔沒有 heartbeat —— status 只在轉換時寫入，所以**時間戳不能用來判斷存活**。
@Suite("SessionRegistryReader")
struct SessionRegistryReaderTests {

    let reader = SessionRegistryReader()

    @Test("四種 status 都要解析得出來")
    func parsesAllFourStatusValues() throws {
        let dir = try Fixture.sessionsDirectory(["busy", "idle", "shell", "waiting_input"])
        let sessions = reader.read(directory: dir)
        let byStatus = Set(sessions.map(\.status))
        #expect(sessions.count == 4)
        #expect(byStatus.contains(.busy))
        #expect(byStatus.contains(.idle))
        #expect(byStatus.contains(.shell))
        #expect(byStatus.contains(.waiting(.inputNeeded)))
    }

    @Test("waiting 會帶出 waitingFor")
    func waitingCarriesItsReason() throws {
        let dir = try Fixture.sessionsDirectory(["waiting_input"])
        let s = try #require(reader.read(directory: dir).first)
        #expect(s.status == .waiting(.inputNeeded))
    }

    @Test("permission prompt 與 input needed 必須是可分辨的兩種狀態")
    func permissionPromptIsDistinctFromInputNeeded() throws {
        let dir = try Fixture.sessionsDirectory(["waiting_input", "waiting_permission"])
        let reasons = Set(reader.read(directory: dir).compactMap { s -> WaitingFor? in
            if case .waiting(let r) = s.status { return r }
            return nil
        })
        #expect(reasons == [.inputNeeded, .permissionPrompt])
    }

    @Test("讀到 0 bytes 要跳過，不可丟錯 —— 這是寫入中的正常現象")
    func zeroByteFileIsSkippedNotThrown() throws {
        let dir = try Fixture.sessionsDirectory(["busy", "zero_bytes"])
        #expect(reader.read(directory: dir).count == 1)
    }

    @Test("截斷的 JSON 要跳過，不可丟錯")
    func truncatedJSONIsSkippedNotThrown() throws {
        let dir = try Fixture.sessionsDirectory(["busy", "truncated"])
        #expect(reader.read(directory: dir).count == 1)
    }

    @Test("舊版本少掉的欄位不影響解析（同一台機器上有 2.1.272 與 2.1.274 並存）")
    func missingOptionalFieldsStillParse() throws {
        let dir = try Fixture.sessionsDirectory(["old_version"])
        let s = try #require(reader.read(directory: dir).first)
        #expect(s.version == "2.1.272")
        #expect(s.status == .busy)
    }

    @Test("同一個 sessionId 有兩筆時，保留 startedAt 最新的那筆")
    func duplicateSessionIdKeepsNewest() throws {
        let dir = try Fixture.sessionsDirectory(["dup_old", "dup_new"])
        let sessions = reader.read(directory: dir)
        #expect(sessions.count == 1)
        #expect(sessions.first?.name == "current")
    }

    @Test("目錄不存在時回傳空陣列，不丟錯")
    func missingDirectoryYieldsEmpty() {
        let dir = URL(fileURLWithPath: "/tmp/definitely-not-here-\(UUID().uuidString)")
        #expect(reader.read(directory: dir).isEmpty)
    }

    @Test("必要欄位齊全時，其餘欄位都可以缺席")
    func onlyCoreFieldsAreRequired() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-minimal-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let minimal = """
        {"pid":999,"sessionId":"min","cwd":"/tmp","startedAt":1789660000000,"status":"idle"}
        """
        try minimal.write(to: dir.appendingPathComponent("999.json"),
                          atomically: true, encoding: .utf8)
        let s = try #require(reader.read(directory: dir).first)
        #expect(s.pid == 999)
        #expect(s.name == nil)
        #expect(s.version == nil)
    }
}
