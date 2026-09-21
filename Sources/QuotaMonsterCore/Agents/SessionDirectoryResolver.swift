import Foundation

/// 一個 session 在磁碟上的三個位置。
public struct SessionPaths: Equatable, Sendable {
    /// `~/.claude/projects/<slug>/<sessionId>.jsonl` —— 協調者的 transcript。
    /// 一般 Agent subagent 要靠它把 `toolUseId` 配回母 tool_use。
    public let transcript: URL
    /// `~/.claude/projects/<slug>/<sessionId>/` 
    public let sessionDirectory: URL
    /// `<sessionId>/subagents/`
    public let subagents: URL
    /// `<sessionId>/workflows/` —— 每次 workflow 執行的整體狀態檔放這裡。
    public let workflowRuns: URL

    public init(transcript: URL, sessionDirectory: URL) {
        self.transcript = transcript
        self.sessionDirectory = sessionDirectory
        self.subagents = sessionDirectory.appendingPathComponent("subagents")
        self.workflowRuns = sessionDirectory.appendingPathComponent("workflows")
    }
}

/// 從 sessionId 找出它的 subagent 目錄。
///
/// **為什麼需要判別：** 同一個 sessionId 可能出現在兩個 project slug 底下
/// （實測 11 個中有 1 個）。正確的那個是**同層有 `<sessionId>.jsonl` 兄弟檔**的那個。
public struct SessionDirectoryResolver: Sendable {
    public init() {}

    /// 只接受「UUID 長什麼樣」的字串：16 進位字元與連字號。
    /// 刻意不用 `UUID(uuidString:)` —— 真實資料裡出現過非標準但無害的 id，
    /// 嚴格解析會讓那些 session 整個消失，而我們要擋的只是路徑字元。
    static func isPlausibleSessionId(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64
            && id.allSatisfy { $0.isHexDigit || $0 == "-" }
    }

    public func resolve(sessionId: String, projectsRoot: URL) -> URL? {
        locate(sessionId: sessionId, projectsRoot: projectsRoot)?.sessionDirectory
    }

    /// 只找 `<slug>/<sessionId>.jsonl`。**判別依據是那個檔案存在，不是目錄存在。**
    ///
    /// ⚠️ **不可以用 `locate()` 代替。** 它硬性要求 `<sessionId>/` 目錄存在，
    /// 而〔實測 2026-09-19〕40 個 transcript 只有 **15 個**有那個兄弟目錄 ——
    /// 沒開過 subagent 的 session 就沒有。此刻活著的 session 剛好都有
    /// （都跑過 Task），所以這個洞在今天的真機上看不出來，但下一個新開的
    /// 終端機第一次跑到回合結束時會整個消失。
    ///
    /// ⚠️ **也不可以用 cwd 反推 slug** —— 〔實測〕slug 是有損轉換
    /// （`demo_repo` → `demo-repo`、中文檔名變成數個連字號），兩個不同的 cwd
    /// 可能撞成同一個 slug。
    ///
    /// **撞號決勝：先取有兄弟目錄的那個，都沒有就取 mtime 最新的。**
    /// `contentsOfDirectory` 的順序**不保證**，靠它就是靠運氣。
    /// ⚠️〔實測〕此刻 40 個 sessionId 沒有任何一個撞號，所以這個分支今天在真機上
    /// 測不出來，只有 fixture 測得到 —— 這正是「不存在 ≠ 那個狀態不成立」。
    public func transcript(sessionId: String, projectsRoot: URL) -> URL? {
        guard Self.isPlausibleSessionId(sessionId) else { return nil }
        let fm = FileManager.default
        guard let slugs = try? fm.contentsOfDirectory(atPath: projectsRoot.path) else { return nil }

        var candidates: [(url: URL, hasDirectory: Bool, modified: Date)] = []
        for slug in slugs {
            let slugDir = projectsRoot.appendingPathComponent(slug)
            let transcript = slugDir.appendingPathComponent("\(sessionId).jsonl")
            guard fm.fileExists(atPath: transcript.path) else { continue }

            var isDir: ObjCBool = false
            let hasDirectory = fm.fileExists(
                atPath: slugDir.appendingPathComponent(sessionId).path,
                isDirectory: &isDir) && isDir.boolValue
            let modified = (try? fm.attributesOfItem(atPath: transcript.path))?[.modificationDate]
                as? Date
            candidates.append((transcript, hasDirectory, modified ?? .distantPast))
        }

        return candidates.sorted {
            $0.hasDirectory != $1.hasDirectory ? $0.hasDirectory : $0.modified > $1.modified
        }.first?.url
    }

    public func locate(sessionId: String, projectsRoot: URL) -> SessionPaths? {
        // sessionId 是從磁碟上的 JSON 讀來的，不是我們產生的。
        // 直接拿去 appendingPathComponent 等於讓那個檔案決定我們讀哪裡 ——
        // 真實的 sessionId 是 UUID，所以擋掉不像 UUID 的東西不會誤傷任何人。
        guard Self.isPlausibleSessionId(sessionId) else { return nil }
        let fm = FileManager.default
        guard let slugs = try? fm.contentsOfDirectory(atPath: projectsRoot.path) else { return nil }

        for slug in slugs {
            let slugDir = projectsRoot.appendingPathComponent(slug)
            let dir = slugDir.appendingPathComponent(sessionId)
            let transcript = slugDir.appendingPathComponent("\(sessionId).jsonl")

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue else { continue }
            // 這就是判別依據 —— 沒有兄弟 transcript 的那個是殘影，跳過。
            guard fm.fileExists(atPath: transcript.path) else { continue }

            return SessionPaths(transcript: transcript, sessionDirectory: dir)
        }
        return nil
    }
}
