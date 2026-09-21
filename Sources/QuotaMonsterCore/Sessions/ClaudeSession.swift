import Foundation

/// 一個 session 在等什麼。
///
/// 從 v2.1.274 二進位檔取出的寫入邏輯：這個欄位**只有兩個值**，
/// 而且只在 `status == "waiting"` 時存在。
public enum WaitingFor: String, Equatable, Hashable, Sendable {
    /// AskUserQuestion / dialog:* 工具 —— 在問你問題。
    case inputNeeded = "input needed"
    /// 其餘 —— 在等你批准一個工具呼叫。
    case permissionPrompt = "permission prompt"
}

/// Claude Code 自己的 session 狀態機。
///
/// 二進位檔裡的映射是 `{ running: "busy", requires_action: "waiting", idle: "idle" }`，
/// 而**被 subagent 卡住走的是 `delegatedActive` → busy 分支，不是 waiting**。
/// 所以 `.waiting` 在設計上就等於「人類被擋住」，可以直接當通知觸發條件。
public enum SessionStatus: Equatable, Hashable, Sendable {
    case busy
    case shell
    case idle
    /// 被人類擋住。`waitingFor` 理應存在，但舊版本可能沒寫，所以是 optional。
    case waiting(WaitingFor?)
}

/// `~/.claude/sessions/<pid>.json` 的一筆記錄。
///
/// 除了 pid / sessionId / cwd / startedAt / status 之外**全部都是 optional** ——
/// 同一台機器上可能同時跑著不同版本的 Claude Code，欄位集合會不一樣。
public struct ClaudeSession: Equatable, Sendable {
    public let pid: Int32
    public let sessionId: String
    public let cwd: String
    public let startedAt: Date
    public let status: SessionStatus

    public let name: String?
    public let version: String?
    public let kind: String?
    public let entrypoint: String?
    public let updatedAt: Date?
    public let statusUpdatedAt: Date?

    public init(pid: Int32, sessionId: String, cwd: String, startedAt: Date,
                status: SessionStatus, name: String? = nil, version: String? = nil,
                kind: String? = nil, entrypoint: String? = nil,
                updatedAt: Date? = nil, statusUpdatedAt: Date? = nil) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.startedAt = startedAt
        self.status = status
        self.name = name
        self.version = version
        self.kind = kind
        self.entrypoint = entrypoint
        self.updatedAt = updatedAt
        self.statusUpdatedAt = statusUpdatedAt
    }
}
