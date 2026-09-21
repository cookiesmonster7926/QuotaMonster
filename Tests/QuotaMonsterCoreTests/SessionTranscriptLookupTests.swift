import Testing
import Foundation
@testable import QuotaMonsterCore

/// 找 `<slug>/<sessionId>.jsonl`。
///
/// ⚠️ 與 `locate()` 刻意分開：`locate()` 硬性要求 `<sessionId>/` 目錄存在，
/// 而〔實測 2026-09-19〕40 個 transcript 只有 **15 個**有那個兄弟目錄。
/// 沿用它的話，沒開過 subagent 的 session 在 Stage 8 眼裡整個不存在。
@Suite("SessionDirectoryResolver — 只找 transcript")
struct SessionTranscriptLookupTests {

    let resolver = SessionDirectoryResolver()
    let sessionId = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    /// 造一個 projects root。`slugs` 是 (slug 名, 要不要建兄弟目錄)。
    func root(_ slugs: [(String, Bool)]) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("qm-tx-\(UUID().uuidString)")
        for (slug, withDir) in slugs {
            let slugDir = root.appendingPathComponent(slug)
            try fm.createDirectory(at: slugDir, withIntermediateDirectories: true)
            try Data("{}".utf8)
                .write(to: slugDir.appendingPathComponent("\(sessionId).jsonl"))
            if withDir {
                try fm.createDirectory(at: slugDir.appendingPathComponent(sessionId),
                                       withIntermediateDirectories: true)
            }
        }
        return root
    }

    @Test("沒有兄弟目錄也要找得到 —— 那正是 locate() 看不到的 25/40")
    func findsTranscriptWithoutSiblingDirectory() throws {
        let r = try root([("-Users-me-proj", false)])
        // 對照：locate() 在同一份資料上回 nil，這一則才是新函式存在的理由。
        #expect(resolver.locate(sessionId: sessionId, projectsRoot: r) == nil)
        #expect(resolver.transcript(sessionId: sessionId, projectsRoot: r) != nil)
    }

    @Test("撞號時先取有兄弟目錄的那一個 —— 不可以靠目錄列舉的順序")
    func siblingDirectoryWinsOnCollision() throws {
        // ⚠️〔實測〕此刻真機上 40 個 sessionId 沒有任何一個撞號，
        // 所以這個分支**只有 fixture 測得到**。這正是「不存在 ≠ 那個狀態不成立」。
        // `contentsOfDirectory` 的順序不保證，靠它就是靠運氣。
        let r = try root([("-a-no-dir", false), ("-b-with-dir", true)])
        let found = try #require(resolver.transcript(sessionId: sessionId, projectsRoot: r))
        #expect(found.path.contains("-b-with-dir"))
    }

    @Test("撞號且都沒有兄弟目錄 —— 取 mtime 最新的那一個")
    func newestWinsWhenNeitherHasADirectory() throws {
        let r = try root([("-a-old", false), ("-b-new", false)])
        // 把 -a-old 那一份推到過去，讓「最新」有唯一解。
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_700_000_000)],
            ofItemAtPath: r.appendingPathComponent("-a-old/\(sessionId).jsonl").path)
        let found = try #require(resolver.transcript(sessionId: sessionId, projectsRoot: r))
        #expect(found.path.contains("-b-new"))
    }

    @Test("檔案不存在就是 nil —— 判別依據是檔案，不是目錄")
    func missingTranscriptIsNil() throws {
        let fm = FileManager.default
        let r = fm.temporaryDirectory.appendingPathComponent("qm-tx-\(UUID().uuidString)")
        // 只有目錄、沒有 .jsonl —— locate() 那條路會被目錄騙過去，這裡不可以。
        try fm.createDirectory(at: r.appendingPathComponent("-slug/\(sessionId)"),
                               withIntermediateDirectories: true)
        #expect(resolver.transcript(sessionId: sessionId, projectsRoot: r) == nil)
    }

    @Test("不像 UUID 的 id 直接拒絕 —— 它是從磁碟上的 JSON 讀來的，不是我們產生的")
    func implausibleIdIsRejected() throws {
        let r = try root([("-slug", true)])
        #expect(resolver.transcript(sessionId: "../../etc/passwd", projectsRoot: r) == nil)
    }
}
