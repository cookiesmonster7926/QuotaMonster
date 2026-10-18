import Foundation

/// 一隻 agent 的執行狀態。
public enum AgentRunState: Equatable, Sendable {
    /// **讀到的** —— workflow 的 journal 說它 started 而且還沒 result／failed。
    case running
    /// **推定的** —— 一般 Agent subagent 沒有任何狀態欄位可讀，
    /// 這是從 transcript 最近有沒有被寫入推出來的。判準與誤差見 `AgentActivity`。
    ///
    /// ⚠️ 刻意**不與 `.running` 合併**：那一個是量到的，這一個是推出來的，
    /// 合併就是把推論寫成量測。畫面上也要分得出來。
    case likelyRunning
    /// 收尾了 —— 成功或失敗都算。
    case finished
    /// **不知道。** 沒有任何正面證據說它在跑，也沒有讀到它的下場。
    ///
    /// ⚠️ 這裡原本寫「背景啟動的 agent **根本不回報完成**（實測 23 筆中 13 筆是
    /// `async_launched`）」——**那句話今天是錯的**，而且錯的方式很典型：
    /// 觀察本身沒錯（`tool_result` 當下回的確實是 `async_launched`），
    /// 錯在**停在那裡** —— 完成是後來以另一種記錄抵達的
    /// （`<task-notification>` 的 `<status>`，實測 25/25）。
    /// 現在讀得到了，讀到的那些會是 `.finished` 並帶著 `AgentNode.outcome`；
    /// 這一格留給**真的**沒有證據的那些。
    case unknown
}

/// 樹上的一個節點。
public struct AgentNode: Equatable, Sendable {
    public let meta: AgentMeta
    public let runState: AgentRunState
    /// 讀到的**真實下場**。
    ///
    /// ⚠️ nil ＝ **沒讀到**，不是「順利結束」。`AgentTally` 會把它算進
    /// 「狀態不明」那一格而不是「已完成」—— 第二節拒絕 2 講的就是這件事：
    /// 併進去等於在面板上宣告一件我們不知道的事。
    ///
    /// ⚠️ 它與 `runState` 是**兩種不同的證據**，不可以互相推導：
    /// `runState` 的 `.likelyRunning` 是活動代理量測（規矩 37），
    /// 這一格是母 transcript 裡讀到的記錄。有這一格時 `runState` 才可以是 `.finished`。
    public let outcome: AgentOutcome.Kind?
    public var children: [AgentNode]

    /// 生出這隻 agent 的 tool_use id（只有一般 agent 有）。
    public var spawningToolUseId: String? { meta.toolUseId }
    /// 這個 toolUseId 在協調者 transcript 裡真的找得到對應的 tool_use。
    public let isLinkedToTranscript: Bool

    public init(meta: AgentMeta, runState: AgentRunState,
                outcome: AgentOutcome.Kind? = nil,
                children: [AgentNode] = [], isLinkedToTranscript: Bool = false) {
        self.meta = meta
        self.runState = runState
        self.outcome = outcome
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

    /// 在跑的總數 —— **量到的加上推定的**。
    ///
    /// ⚠️ 這裡原本寫「只計入**確定**在跑的。unknown 不計入 —— 寧可少報，不要謊報」。
    /// 2026-09-22 使用者拍板改成「代理量測 + 誤差已知」：一般 Agent subagent
    /// 磁碟上沒有任何狀態欄位，堅持只算確定的，等於它們永遠顯示成 0
    /// （實測：一隻正在跑的 agent，面板的 AGENTS 仍然是 0）。
    ///
    /// 條件是**分得出來**：推定的那些走 `.likelyRunning`，
    /// 而 `likelyRunningAgentCount` 說得出其中幾隻是推的。判準見 `AgentActivity`。
    /// `unknown` 仍然不計入。
    public var runningAgentCount: Int {
        workflows.reduce(0) { $0 + $1.runningCount }
            + agents.reduce(0) { $0 + Self.count($1) { $0 == .running || $0 == .likelyRunning } }
    }

    /// 上面那個數字裡，有幾隻是**推定**的（沒有讀到任何狀態，只看到 transcript 在動）。
    /// 畫面要據此降調，不可以把它畫得跟 journal 讀到的一樣篤定。
    public var likelyRunningAgentCount: Int {
        agents.reduce(0) { $0 + Self.count($1) { $0 == .likelyRunning } }
    }

    static func count(_ n: AgentNode, where match: (AgentRunState) -> Bool) -> Int {
        (match(n.runState) ? 1 : 0) + n.children.reduce(0) { $0 + count($1, where: match) }
    }

    /// 面板的 session 列在名稱與 ctx 之外要畫的那幾行。
    /// `SessionRow` 照它畫、`PanelView` 的高度估算用它的 `count` —— 見 `SessionDetailLines`。
    public var detailLines: SessionDetailLines { SessionDetailLines(self) }

    /// `detailLines.count` 的簡寫。
    public var detailLineCount: Int { detailLines.count }

    public init(sessionId: String, agents: [AgentNode], workflows: [WorkflowGroup]) {
        self.sessionId = sessionId
        self.agents = agents
        self.workflows = workflows
    }
}

/// 一個 session 列在名稱與 ctx 之外**要畫哪些行**：還在跑的 workflow 與 agent 各一行，
/// 加上「另有 N 個已完成」那一行（有東西可收合才有；workflow 與 agent 的收合共用這一行）。
///
/// ### 為什麼是一個型別，不是一個行數
/// 〔實測 2026-10-19，使用者截圖〕有一個 session 的收合那一行寫著 27 個 agent 已完成，
/// 面板高過螢幕、頂端被切掉。
/// 〔推論，讀碼〕原因是 `PanelView` 的高度估算用 `agents.count`（含已完成的）估成 27 行，
/// 而 `SessionRow` 實際只畫 1 行 —— 同一個規則寫了兩份、數法不同。
///
/// 只給一個行數的話，`SessionRow` 還是得自己決定畫哪些行，規則照樣是兩份（規矩 2）。
/// 所以這裡一次給出要畫的東西：`SessionRow` 只照著畫，行數就是它們的數目。
/// App 層測不到這件事，所以「畫哪些行」的組合規則只能活在這裡、由
/// `SessionDetailLinesTests` 守著。
public struct SessionDetailLines: Equatable, Sendable {
    /// 還在跑的 workflow，各自一行。
    public let liveWorkflows: [WorkflowGroup]
    /// 沒在跑的 workflow 的下場分類 —— 收合那一行的前半。
    public let workflows: WorkflowTally
    /// 一般 agent：`outstanding` 各自一行，其餘進收合那一行的後半。
    public let agents: AgentTally

    public init(_ tree: AgentTree) {
        self.liveWorkflows = tree.workflows.filter { $0.runningCount > 0 }
        self.workflows = WorkflowTally(tree.workflows)
        self.agents = AgentTally(tree.agents)
    }

    /// 「另有 N 個已完成」那一行要不要畫。
    public var hasCollapsedLine: Bool {
        !workflows.collapsed.isEmpty || !agents.collapsed.isEmpty
    }

    /// 總共畫幾行。
    public var count: Int {
        liveWorkflows.count + agents.outstanding.count + (hasCollapsedLine ? 1 : 0)
    }
}
