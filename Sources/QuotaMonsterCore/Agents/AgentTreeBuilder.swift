import Foundation

/// 從磁碟重建一個 session 的 agent 結構。
///
/// **必須兩套連結法並存**，因為兩種 agent 的中繼資料形狀根本不同：
///
/// | 種類 | 怎麼連回去 | 真實佔比 |
/// |---|---|---|
/// | 一般 Agent subagent | `toolUseId` 配母 transcript；深度 ≥2 用 `parentAgentId` | 31 / 187 |
/// | workflow subagent | **沒有任何 parent 欄位**，只能靠目錄路徑 | 156 / 187 |
///
/// ⚠️ 不要用 `sourceToolAssistantUUID` 當 parent 指標。實測它是**檔案內**指標
/// （72/72 解析於 subagent 自己的 transcript，母 transcript 內 0 筆），
/// 照它寫會得到一棵空樹。
public struct AgentTreeBuilder: Sendable {

    private let metaReader = AgentMetaReader()
    private let journalReader = WorkflowJournalReader()
    private let runStateReader = WorkflowRunStateReader()

    public init() {}

    /// - Parameter now: ⚠️ **刻意不給預設值。** 一般 Agent subagent 的執行狀態是
    ///   從 transcript 的 mtime 推定的（見 `AgentActivity`），所以「現在幾點」
    ///   是這個函式的輸入之一。給預設值會讓呼叫端不知道自己在依賴一個時鐘 ——
    ///   同一條理由見 `Presence`。
    public func build(paths: SessionPaths, sessionId: String,
                      sessionStartedAt: Date, now: Date) -> AgentTree {
        let toolUseIds = Self.toolUseIds(inTranscript: paths.transcript)
        let plain = plainAgents(in: paths.subagents, since: sessionStartedAt, now: now)
        return AgentTree(
            sessionId: sessionId,
            agents: forest(from: plain, in: paths.subagents,
                           transcriptToolUseIds: toolUseIds, now: now),
            workflows: workflowGroups(in: paths.subagents, runs: paths.workflowRuns,
                                      since: sessionStartedAt, now: now)
        )
    }

    // ── 一般 agent ─────────────────────────────────────────────

    /// `subagents/` 這一層（不遞迴）的 meta，且通過「比 session 新」這一閘。
    private func plainAgents(in subagents: URL, since start: Date, now: Date) -> [AgentMeta] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: subagents.path) else { return [] }
        return names
            .compactMap { metaReader.read(subagents.appendingPathComponent($0)) }
            .filter { !$0.isWorkflowAgent }
            .filter { Self.isFresh(agentId: $0.agentId, in: subagents, since: start, now: now) }
            .sorted { $0.agentId < $1.agentId }
    }

    /// 依 `parentAgentId` 組成森林。沒有 parent 的就是根。
    private func forest(from metas: [AgentMeta], in subagents: URL,
                        transcriptToolUseIds: Set<String>, now: Date) -> [AgentNode] {
        var childrenOf: [String: [AgentMeta]] = [:]
        var roots: [AgentMeta] = []
        let known = Set(metas.map(\.agentId))

        for m in metas {
            // parent 存在才掛上去；parent 已被存活閘濾掉的話，這隻自己變成根，
            // 否則整條分支會憑空消失。
            if let p = m.parentAgentId, known.contains(p) {
                childrenOf[p, default: []].append(m)
            } else {
                roots.append(m)
            }
        }

        func node(_ m: AgentMeta) -> AgentNode {
            AgentNode(
                meta: m,
                // 一般 Agent subagent 磁碟上沒有任何狀態欄位，所以這裡是**推定**的：
                // transcript 最近還在被寫就當作還在跑。判準與實測誤差見 `AgentActivity`。
                // 推不出來時維持 `.unknown` —— **不推定「已完成」**，那需要證據。
                runState: Self.isLikelyRunning(agentId: m.agentId, in: subagents, now: now)
                    ? .likelyRunning : .unknown,
                children: (childrenOf[m.agentId] ?? []).sorted { $0.agentId < $1.agentId }.map(node),
                isLinkedToTranscript: m.toolUseId.map(transcriptToolUseIds.contains) ?? false
            )
        }
        return roots.map(node)
    }

    // ── workflow agent ─────────────────────────────────────────

    private func workflowGroups(in subagents: URL, runs: URL, since start: Date,
                                now: Date) -> [WorkflowGroup] {
        let fm = FileManager.default
        let root = subagents.appendingPathComponent("workflows")
        guard let ids = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }

        return ids.sorted().compactMap { wfId -> WorkflowGroup? in
            let dir = root.appendingPathComponent(wfId)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return nil }

            let journal = journalReader.read(dir.appendingPathComponent("journal.jsonl"))
            let metas = names
                .compactMap { metaReader.read(dir.appendingPathComponent($0)) }
                .filter { Self.isFresh(agentId: $0.agentId, in: dir, since: start, now: now) }
                .sorted { $0.agentId < $1.agentId }
            guard !metas.isEmpty else { return nil }

            // run 已經終結（completed / failed / killed）時，journal 的
            // 「started 但沒 result」是中止造成的殘影，不是還在跑。
            let runState = runStateReader.read(runId: wfId, in: runs)
            let terminated = runState?.isTerminal ?? false

            let agents = metas.map { m in
                AgentNode(meta: m,
                          runState: terminated ? .finished
                                  : journal.running.contains(m.agentId) ? .running
                                  : journal.finished.contains(m.agentId) ? .finished
                                  : .unknown)
            }
            // ⚠️ **階段來自 journal 的行序，不是 metas。**
            // `metas` 是按 agentId 排序的（91 行），而 agentId 是隨機 hex ——
            // 取 `metas.first` 等於擲骰子。〔實測 2026-09-19〕這台機器 36 個
            // workflow 有 15 個因此報錯階段，而這個字串就畫在面板上。
            return WorkflowGroup(workflowId: wfId, latestPhase: journal.latestPhase,
                                 agents: agents, runStatus: runState?.status,
                                 runDuration: runState?.duration)
        }
    }

    // ── 存活閘 ─────────────────────────────────────────────────

    /// `subagents/` 是 **append-only 的歷史**，跨 `--resume` 累積。
    /// 少了這一閘，四天前就死掉的 agent 會被當成正在跑。
    /// transcript 最近還在動嗎。與 `isFresh` 讀同一個檔案的同一個欄位，
    /// 但問的是**不同的問題**：`isFresh` 問「是不是這一輪的」，這個問「現在還在不在跑」。
    static func isLikelyRunning(agentId: String, in directory: URL, now: Date) -> Bool {
        let jsonl = directory.appendingPathComponent("agent-\(agentId).jsonl")
        let mtime = (try? FileManager.default.attributesOfItem(atPath: jsonl.path))?[.modificationDate]
        return AgentActivity.isLikelyRunning(lastWrite: mtime as? Date, now: now)
    }

    static func isFresh(agentId: String, in directory: URL, since start: Date,
                        now: Date) -> Bool {
        let jsonl = directory.appendingPathComponent("agent-\(agentId).jsonl")
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: jsonl.path),
              let mtime = attrs[.modificationDate] as? Date
        else { return false }
        // ⚠️ 上界不可省。〔code review 2026-09-22〕mtime 在 2099 的檔案會**永遠**
        // 通過這一關，而且沒有任何東西會把它清掉 —— 那一列會卡在名單上不會消失。
        // 同一個不對稱在這個 repo 出現第三次（`StatusLineCacheReader:73` 夾了、
        // `WindowExpiry.horizon` 有、`AgentActivity.futureTolerance` 今天補了）。
        guard mtime.timeIntervalSince(now) <= AgentActivity.futureTolerance else { return false }
        return mtime > start
    }

    // ── 協調者 transcript ──────────────────────────────────────

    /// 收集母 transcript 裡所有 tool_use 的 id，用來確認一般 agent 的 toolUseId 真的配得上。
    static func toolUseIds(inTranscript url: URL) -> Set<String> {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var ids: Set<String> = []
        for line in text.split(separator: "\n") {
            guard let data = line.data(using: .utf8),
                  let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let message = d["message"] as? [String: Any],
                  let content = message["content"] as? [[String: Any]]
            else { continue }
            for block in content where block["type"] as? String == "tool_use" {
                if let id = block["id"] as? String { ids.insert(id) }
            }
        }
        return ids
    }
}
