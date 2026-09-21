import Foundation

/// 一隻 agent 的執行狀態。
public enum AgentRunState: Equatable, Sendable {
    case running
    /// 收尾了 —— 成功或失敗都算。
    case finished
    /// **不知道。** 一般 Agent subagent 沒有 journal，完成與否要從母 transcript 的
    /// `toolUseResult` 推，而背景啟動的 agent 根本不回報完成（實測 23 筆中 13 筆是
    /// `async_launched`，不帶 totalTokens / totalDurationMs / agentType）。
    /// 所以這裡誠實標示為未知，不假裝知道。
    case unknown
}

/// 樹上的一個節點。
public struct AgentNode: Equatable, Sendable {
    public let meta: AgentMeta
    public let runState: AgentRunState
    public var children: [AgentNode]

    /// 生出這隻 agent 的 tool_use id（只有一般 agent 有）。
    public var spawningToolUseId: String? { meta.toolUseId }
    /// 這個 toolUseId 在協調者 transcript 裡真的找得到對應的 tool_use。
    public let isLinkedToTranscript: Bool

    public init(meta: AgentMeta, runState: AgentRunState,
                children: [AgentNode] = [], isLinkedToTranscript: Bool = false) {
        self.meta = meta
        self.runState = runState
        self.children = children
        self.isLinkedToTranscript = isLinkedToTranscript
    }
}

/// 一次 workflow 扇出。
///
/// workflow agent **沒有任何 parent 欄位**，唯一的歸屬線索就是它所在的目錄
/// `<sessionId>/subagents/workflows/<wf_id>/`，所以它們是平的一組，不是樹。
public struct WorkflowGroup: Equatable, Sendable {
    public let workflowId: String
    /// 最後一個 `started` 行的 phase。見 `WorkflowJournal.latestPhase`。
    ///
    /// ⚠️ **不是「現在正在跑哪一階段」** —— pipeline 沒有 barrier，多個階段真的會
    /// 同時在跑，單數字串必然丟掉一個。這個名字刻意講明它取的是最新的那個邊緣，
    /// 因為這個欄位上一版叫 `phase`、而它其實回的是 agentId 字典序最小那隻的階段。
    /// nil ＝ journal 沒說，不是「沒有階段」。
    public let latestPhase: String?
    public let agents: [AgentNode]
    /// run 自己的終結狀態（completed / failed / killed），沒有檔案或還沒終結時是 nil。
    ///
    /// **為什麼要一路帶到這裡：** 被中止的 run 會把每一隻 agent 折成 `.finished`，
    /// 所以 `finishedCount == total` —— 純看數字，「你自己停掉的」與「真的跑完了」
    /// 長得一模一樣。通知層要是分不出來，就會對著一個你按了 TaskStop 的 run
    /// 說「7 個 agent 全部完成」。
    public let runStatus: String?
    /// run **自己量**的執行時間（秒）。還在跑、或沒有 run 狀態檔時是 nil。
    ///
    /// ⚠️ **不是「這個 group 被觀察了多久」** —— 那個數字一文不值，
    /// 而它正是 2026-09-19 修掉的 `BatchAlert` duration bug 的形狀。
    /// 叫 `runDuration` 是為了與旁邊的 `runStatus` 成對，並擋掉下一個人把它
    /// 讀成「這個 group 存在多久」。
    public let runDuration: TimeInterval?

    public var total: Int { agents.count }
    public var runningCount: Int { agents.count { $0.runState == .running } }
    public var finishedCount: Int { agents.count { $0.runState == .finished } }

    public init(workflowId: String, latestPhase: String?, agents: [AgentNode],
                runStatus: String? = nil, runDuration: TimeInterval? = nil) {
        self.workflowId = workflowId
        self.latestPhase = latestPhase
        self.agents = agents
        self.runStatus = runStatus
        self.runDuration = runDuration
    }
}

/// 一個 session 底下的完整 agent 結構。
public struct AgentTree: Equatable, Sendable {
    public let sessionId: String
    /// 一般 Agent 工具的 subagent，依 parentAgentId 組成的森林。
    public let agents: [AgentNode]
    /// workflow 扇出，依目錄分組。
    public let workflows: [WorkflowGroup]

    /// 只計入**確定**在跑的。unknown 不計入 —— 寧可少報，不要謊報。
    public var runningAgentCount: Int {
        workflows.reduce(0) { $0 + $1.runningCount }
            + agents.reduce(0) { $0 + Self.countRunning($1) }
    }

    static func countRunning(_ n: AgentNode) -> Int {
        (n.runState == .running ? 1 : 0) + n.children.reduce(0) { $0 + countRunning($1) }
    }

    public init(sessionId: String, agents: [AgentNode], workflows: [WorkflowGroup]) {
        self.sessionId = sessionId
        self.agents = agents
        self.workflows = workflows
    }
}
