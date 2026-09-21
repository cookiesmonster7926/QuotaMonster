import Foundation

/// 一個確認還活著的 session，加上 app 要顯示的衍生屬性。
public struct LiveSession: Equatable, Sendable {
    public let session: ClaudeSession

    /// **有人在等你。** 這是唯一有時限的狀態。
    ///
    /// 直接由 `.waiting` 推得，而這是安全的：二進位檔的狀態機顯示
    /// 被 subagent 卡住走的是 `delegatedActive` → `busy` 分支，
    /// 所以 `.waiting` 不會因為「在等子代理」而誤觸發。
    public let needsHuman: Bool
    /// 在等什麼（問你問題 vs 等你批准工具）。
    public let waitingFor: WaitingFor?
    /// 正在跑東西。
    public let isWorking: Bool
    /// 專案名 —— cwd 的最後一段。
    public let project: String

    public init(session: ClaudeSession) {
        self.session = session
        switch session.status {
        case .waiting(let reason):
            self.needsHuman = true
            self.waitingFor = reason
            self.isWorking = false
        case .busy, .shell:
            self.needsHuman = false
            self.waitingFor = nil
            self.isWorking = true
        case .idle:
            self.needsHuman = false
            self.waitingFor = nil
            self.isWorking = false
        }
        self.project = URL(fileURLWithPath: session.cwd).lastPathComponent
    }
}

/// 把註冊表記錄過濾成「真的還活著」的集合，並排序。
public struct SessionStateResolver: Sendable {

    private let isAlive: @Sendable (Int32, Date) -> Bool

    /// - Parameter isAlive: 存活判定。預設走真實的 pid + 啟動時間比對；
    ///   測試可以注入替身，不必真的生一個行程。
    public init(isAlive: @escaping @Sendable (Int32, Date) -> Bool = ProcessLiveness.isAlive) {
        self.isAlive = isAlive
    }

    /// 死掉的一律排除 —— 註冊表裡寫什麼都不算數，因為 crash 的 session
    /// 會永遠留著 `busy`。需要人類介入的排最前面，其次是工作中的。
    public func resolve(_ sessions: [ClaudeSession]) -> [LiveSession] {
        sessions
            .filter { isAlive($0.pid, $0.startedAt) }
            .map(LiveSession.init(session:))
            .sorted { a, b in
                if a.needsHuman != b.needsHuman { return a.needsHuman }
                if a.isWorking != b.isWorking { return a.isWorking }
                return a.session.startedAt < b.session.startedAt
            }
    }
}

/// 選單列圖示要的彙總數字。
public struct SessionSummary: Equatable, Sendable {
    public let total: Int
    public let blocked: Int
    public let working: Int
    public let idle: Int

    public init(_ sessions: [LiveSession]) {
        self.total = sessions.count
        self.blocked = sessions.count { $0.needsHuman }
        self.working = sessions.count { $0.isWorking }
        self.idle = sessions.count { !$0.needsHuman && !$0.isWorking }
    }
}
