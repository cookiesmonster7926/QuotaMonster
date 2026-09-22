import Foundation

/// 讀取 `~/.claude/sessions/` 這個即時 session 註冊表。
///
/// 兩個實測出來的陷阱，這裡都必須處理：
///
/// 1. **會讀到 0 bytes。** 0.1 秒間隔的快照實測捕捉到寫入中的空檔。
///    這是正常現象，不是錯誤 —— 壞掉的檔案一律跳過，整個讀取永不丟錯。
///
/// 2. **同一個 sessionId 可能有兩筆。** crash 之後 resume 會在舊行程收尾前
///    註冊新的 pid。依 sessionId 去重，保留 `startedAt` 最新的那筆。
public struct SessionRegistryReader: Sendable {

    public init() {}

    public func read(directory: URL) -> [ClaudeSession] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }

        let parsed = names
            .filter { $0.hasSuffix(".json") }
            .compactMap { Self.parse(directory.appendingPathComponent($0)) }

        return Self.deduplicated(parsed)
    }

    /// 一個 session 同時有兩筆記錄時，Claude Code 自己的作法是保留最晚啟動的那筆。
    static func deduplicated(_ sessions: [ClaudeSession]) -> [ClaudeSession] {
        var newest: [String: ClaudeSession] = [:]
        for s in sessions {
            if let existing = newest[s.sessionId], existing.startedAt >= s.startedAt { continue }
            newest[s.sessionId] = s
        }
        return newest.values.sorted { $0.startedAt < $1.startedAt }
    }

    /// 任何解析失敗都回傳 nil。呼叫端看到的就只是「這個檔這一輪不算數」。
    static func parse(_ url: URL) -> ClaudeSession? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let pid = (d["pid"] as? NSNumber)?.int32Value,
              let sessionId = d["sessionId"] as? String,
              let cwd = d["cwd"] as? String,
              let startedAtMs = (d["startedAt"] as? NSNumber)?.doubleValue,
              let rawStatus = d["status"] as? String,
              let status = Self.status(rawStatus, waitingFor: d["waitingFor"] as? String)
        else { return nil }

        return ClaudeSession(
            pid: pid,
            sessionId: sessionId,
            cwd: cwd,
            startedAt: Date(timeIntervalSince1970: startedAtMs / 1000),
            status: status,
            name: d["name"] as? String,
            nameSource: d["nameSource"] as? String,
            version: d["version"] as? String,
            kind: d["kind"] as? String,
            entrypoint: d["entrypoint"] as? String,
            updatedAt: (d["updatedAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) },
            statusUpdatedAt: (d["statusUpdatedAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue / 1000) }
        )
    }

    static func status(_ raw: String, waitingFor: String?) -> SessionStatus? {
        switch raw {
        case "busy":    return .busy
        case "shell":   return .shell
        case "idle":    return .idle
        case "waiting": return .waiting(waitingFor.flatMap(WaitingFor.init(rawValue:)))
        default:        return nil   // 未知狀態：寧可跳過，也不要猜
        }
    }
}
