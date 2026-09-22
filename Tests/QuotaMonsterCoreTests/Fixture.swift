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

    /// 這些 agent 刻意比 `sessionStart` 還舊，用來釘住存活閘。
    /// 名字對應 `agent-<id>.jsonl`。
    static let staleAgentIds = ["stale"]

    /// 這些 agent 還在存活窗內（比 `sessionStart` 新），但已經 300 秒沒寫字 ——
    /// 超過 `AgentActivity.window`（120s），所以應該是 `.unknown` 而不是
    /// `.likelyRunning`。沒有這一類，就沒有東西釘得住那個窗口。
    static let quietAgentIds = ["minimal"]

    /// agent 樹 fixture 的根，等同 ~/.claude/projects/
    ///
    /// ### ⚠️ 複製到暫存目錄並**自己蓋 mtime**，不直接用 bundle 裡那一份
    /// `AgentTreeBuilder.isFresh` 判斷「這個 agent 是不是這一輪的」用的是
    /// `agent-<id>.jsonl` 的 **mtime**，而 **git 不保存 mtime** ——
    /// 全新 checkout 之後每個檔案的 mtime 都是 checkout 當下，
    /// 於是「四天前就死掉的 agent」在別人的機器上變成「剛剛才動過」。
    ///
    /// 〔實測 2026-09-21，GitHub Actions 第一次跑〕`depthOneAgentsAreRoots` 與
    /// `agentOlderThanSessionStartIsExcluded` 兩則因此紅掉。
    /// **開發機上永遠看不到** —— 那些檔案是 2026-09-13／09-17 由
    /// `capture_fixtures.py` 明確蓋過 mtime 產生的，之後從來沒有被重新 checkout。
    ///
    /// 這正是本檔 `statuslineDirectory` 檔頭早就寫下的那條規則
    /// （「年齡必須由測試明確指定，不可以倚賴碰巧保留的 mtime」），
    /// 當初只是沒有套用到 agents 這一份。
    static func projectsRoot() throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("qm-agents-\(UUID().uuidString)")
        try fm.copyItem(at: try url("agents"), to: dir)

        // 走一遍，把每個 agent-*.jsonl 的 mtime 蓋成確定的值。
        // ⚠️ 只蓋 .jsonl —— isFresh 看的就是它；meta 的 mtime 沒有任何人在讀，
        // 蓋了只會讓下一個人以為它也是載重的。
        guard let walker = fm.enumerator(at: dir, includingPropertiesForKeys: nil) else {
            return dir
        }
        for case let f as URL in walker where f.lastPathComponent.hasSuffix(".jsonl")
            && f.lastPathComponent.hasPrefix("agent-") {
            let id = String(f.lastPathComponent.dropFirst(6).dropLast(6))
            let stamp: Date
            if staleAgentIds.contains(id) {
                stamp = sessionStart.addingTimeInterval(-4 * 86400)   // 四天前那一輪留下的
            } else if quietAgentIds.contains(id) {
                stamp = now.addingTimeInterval(-300)                  // 這一輪的，但安靜很久了
            } else {
                stamp = now                                          // 剛剛還在寫
            }
            try? fm.setAttributes([.modificationDate: stamp], ofItemAtPath: f.path)
        }
        return dir
    }

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
