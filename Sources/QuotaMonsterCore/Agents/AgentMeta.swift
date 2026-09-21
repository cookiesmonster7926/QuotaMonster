import Foundation

/// `agent-<id>.meta.json` 這個 sidecar 的內容，加上從檔名推出的 agentId。
///
/// 實測 187 個真實檔案共有 **5 種 key 組合**，所以只有三個欄位是必要的。
/// 這個 schema 沒有任何官方契約 —— 未知的 key 必須無害，缺少的 key 必須容忍。
public struct AgentMeta: Equatable, Sendable {
    /// 從檔名推得（`agent-<id>.meta.json`）。檔案內容裡**沒有**這個欄位。
    public let agentId: String
    public let agentType: String
    public let description: String
    public let spawnDepth: Int

    /// 只有 workflow subagent 有。
    public let workflowPhase: String?
    /// 只有一般 Agent 工具的 subagent 有 —— 這是連回母 transcript 的鑰匙。
    public let toolUseId: String?
    /// 只有深度 ≥2 的一般 subagent 有。
    public let parentAgentId: String?
    public let requestShape: String?

    /// workflow agent **沒有任何 parent 欄位**，只能靠目錄路徑連回去。
    /// 這一點決定了樹的建構必須有兩套連結法。
    public var isWorkflowAgent: Bool { agentType == "workflow-subagent" }

    public init(agentId: String, agentType: String, description: String, spawnDepth: Int,
                workflowPhase: String? = nil, toolUseId: String? = nil,
                parentAgentId: String? = nil, requestShape: String? = nil) {
        self.agentId = agentId
        self.agentType = agentType
        self.description = description
        self.spawnDepth = spawnDepth
        self.workflowPhase = workflowPhase
        self.toolUseId = toolUseId
        self.parentAgentId = parentAgentId
        self.requestShape = requestShape
    }
}

public struct AgentMetaReader: Sendable {
    public init() {}

    /// - Returns: 檔名不是 `agent-*.meta.json`、或內容缺少必要欄位時回傳 nil。
    public func read(_ url: URL) -> AgentMeta? {
        let name = url.lastPathComponent
        guard name.hasPrefix("agent-"), name.hasSuffix(".meta.json") else { return nil }
        let agentId = String(name.dropFirst("agent-".count).dropLast(".meta.json".count))
        guard !agentId.isEmpty,
              let data = try? Data(contentsOf: url), !data.isEmpty,
              let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let agentType = d["agentType"] as? String,
              let description = d["description"] as? String,
              let spawnDepth = (d["spawnDepth"] as? NSNumber)?.intValue
        else { return nil }

        return AgentMeta(
            agentId: agentId,
            agentType: agentType,
            description: description,
            spawnDepth: spawnDepth,
            workflowPhase: d["workflowPhase"] as? String,
            toolUseId: d["toolUseId"] as? String,
            parentAgentId: d["parentAgentId"] as? String,
            requestShape: d["requestShape"] as? String
        )
    }
}
