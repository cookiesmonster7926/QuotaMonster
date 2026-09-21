import Foundation
import Testing

/// Fixture 由 `scripts/capture_fixtures.py` 從真實資料產生並去識別化。
enum Fixture {
    /// 所有 fixture 的時間基準。capture 腳本用固定的 NOW_MS，測試才能重現。
    static let now = Date(timeIntervalSince1970: 1_789_660_000)
    static let account = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    static func url(_ relativePath: String) throws -> URL {
        let base = try #require(Bundle.module.resourceURL,
                                "test bundle has no resource URL")
        let u = base.appendingPathComponent("Fixtures").appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: u.path) else {
            Issue.record("fixture not found: \(u.path)")
            throw CocoaError(.fileNoSuchFile)
        }
        return u
    }

    static let agentSessionId = "aaaaaaaa-1111-4111-8111-aaaaaaaaaaaa"

    /// agent 樹 fixture 的根，等同 ~/.claude/projects/
    static func projectsRoot() throws -> URL { try url("agents") }

    /// session 十分鐘前啟動 —— 與 capture 腳本裡的 SESSION_START 一致
    static let sessionStart = Date(timeIntervalSince1970: 1_789_660_000 - 600)

    /// 把一組 session fixture 複製成一個暫時目錄，模擬 ~/.claude/sessions/
    static func sessionsDirectory(_ names: [String]) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-sessions-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for n in names {
            try FileManager.default.copyItem(at: try url("sessions/\(n).json"),
                                             to: dir.appendingPathComponent("\(n).json"))
        }
        return dir
    }

    // ── statusline 快取 ──────────────────────────────────────────

    /// 把一組 statusline fixture 複製成一個暫時目錄，模擬 tee 寫出來的快取。
    ///
    /// 擷取時間來自**檔案 mtime** —— statusLine payload 裡沒有任何時間戳。
    /// 所以年齡必須由測試明確指定，不可以倚賴 SwiftPM 複製資源時碰巧保留的 mtime。
    static func statuslineDirectory(
        _ entries: [(fixture: String, filename: String, age: TimeInterval)]
    ) throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("qm-statusline-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for e in entries {
            let dst = dir.appendingPathComponent(e.filename)
            try fm.copyItem(at: try url("statusline/\(e.fixture).json"), to: dst)
            try fm.setAttributes([.modificationDate: now.addingTimeInterval(-e.age)],
                                 ofItemAtPath: dst.path)
        }
        return dir
    }

    /// 常見情況的簡寫：檔名就用 fixture 名，年齡預設 30 秒（live）。
    static func statuslineDirectory(_ fixtures: [String],
                                    age: TimeInterval = 30) throws -> URL {
        try statuslineDirectory(fixtures.map { ($0, "\($0).json", age) })
    }
}
