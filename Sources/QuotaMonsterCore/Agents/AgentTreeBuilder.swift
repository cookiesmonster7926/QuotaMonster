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
/// ⚠️ 不要用 `sourceToolAssistantUUID` 當 parent 指標：它是**檔案內**指標，
/// 照它寫會得到一棵空樹。
///
/// ⚠️ 這句話原本附的證據是「72/72 解析於 subagent 自己的 transcript，
/// **母 transcript 內 0 筆**」——〔重新實測 2026-09-22〕那個 0 只對**那一族群**成立。
/// 母 transcript 裡的 **spawn** 記錄 37/37 都帶這個欄位，而且 37/37 解析得到
/// （它指向發出那個 tool_use 的 assistant 記錄，與 `parentUuid` 逐字相同）。
/// 結論沒變（它永遠是檔案內指標），但**範圍寫太寬的實測與寫錯的實測一樣貴** ——
/// 它會讓下一個人停止提問。完整對照見 `docs/quotamonster.md` 第三節第 31 條。
public struct AgentTreeBuilder: Sendable {

    private let metaReader = AgentMetaReader()
    private let runStateReader = WorkflowRunStateReader()

    public init() {}

    /// - Parameter facts: 母 transcript 讀出來的事實（`TranscriptWatcher.update`）。
    ///   ⚠️ **刻意不給預設值，也刻意不在這裡自己讀檔。** 這支函式每 3 秒被呼叫一次，
    ///   而它原本自己 `String(contentsOf:)` 整份 transcript ——〔實測 2026-09-22〕
    ///   `refresh()` 的穩態中位因此是 740 毫秒，一拍只有 3000。
    ///   把讀檔移到呼叫端，增量游標才有地方活著。
    /// - Parameter journals: workflow `journal.jsonl` 的增量游標。與 `facts` 同一個理由：
    ///   這支函式每 3 秒被呼叫一次，游標要活在呼叫端。⚠️ 只有**過了新鮮度閘**的
    ///   workflow 會去問它 —— 呼叫端每拍結束時 `sweep()`，沒被問到的就放掉。
    /// - Parameter now: ⚠️ **刻意不給預設值。** 一般 Agent subagent 的執行狀態是
    ///   從 transcript 的 mtime 推定的（見 `AgentActivity`），所以「現在幾點」
    ///   是這個函式的輸入之一。給預設值會讓呼叫端不知道自己在依賴一個時鐘 ——
    ///   同一條理由見 `Presence`。
    public func build(paths: SessionPaths, sessionId: String, facts: TranscriptFacts,
                      journals: inout WorkflowJournalWatcher,
                      sessionStartedAt: Date, now: Date) -> AgentTree {
        let plain = plainAgents(in: paths.subagents, since: sessionStartedAt, now: now)
        return AgentTree(
            sessionId: sessionId,
            agents: forest(from: plain, in: paths.subagents, facts: facts, now: now),
            workflows: workflowGroups(in: paths.subagents, runs: paths.workflowRuns,
                                      journals: &journals, since: sessionStartedAt, now: now)
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
                        facts: TranscriptFacts, now: Date) -> [AgentNode] {
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
            // ⚠️ **兩種證據，優先序固定 —— 而且順序不是直覺的那一個。**
            //
            // 第一版寫的是「讀到的下場勝過活動代理量測，形狀與 workflow 那邊一樣
            // （`terminated ? .finished : journal…`）」。**那個類比就是 bug**：
            // workflow 的 `terminated` 真的是終結，一般 agent 的 `completed` **不是** ——
            // 我們自己在 `TranscriptFacts.outcomes` 的檔頭就寫著
            // 「『完成』的意思是『這一次停下來了』，不是『從此結束』」。
            //
            // ⚠️〔code review 2026-09-22，拿真實資料重現〕agent `ad3e01f33c6a06e3b`
            // 在 06:46:42 發出 `completed`，接著**繼續產出新內容 106 秒**
            // （18 則通知，`<result>` 各不相同），最後在 06:48:28 被 `killed`。
            // 那 106 秒裡它自己的 transcript 一直在被寫，而第一版讓 outcome 勝出 ——
            // 於是那一列**從面板上消失**，收合那一行還宣告「1 個 agent 已完成」。
            //
            // 正確的順序來自「這一格在回答什麼」：`runState` 問的是**現在還在不在跑**，
            // 而唯一關於「現在」的證據是活動代理量測。過去那一筆 `completed`
            // 回答的是另一個問題，所以它留在 `outcome` 那一格。
            //
            // `killed` 是唯一的例外，因為它**真的**是終結：那是使用者自己按的 TaskStop，
            // 沒有東西會把它重新啟動。而被停掉之後檔案還會「溫」上一段時間
            // （最多 `AgentActivity.window` 120 秒）—— 那段時間說它還在跑，
            // 是在對一件使用者剛剛親手做的事說反話。
            let outcome = facts.outcomes[m.agentId]?.kind
            let state: AgentRunState
            if outcome == .killed {
                state = .finished
            } else if Self.isLikelyRunning(agentId: m.agentId, in: subagents, now: now) {
                state = .likelyRunning
            } else if outcome != nil {
                state = .finished
            } else {
                // 推不出來就維持 `.unknown` —— **不推定「已完成」**，那需要證據。
                state = .unknown
            }
            return AgentNode(
                meta: m,
                runState: state,
                outcome: outcome,
                children: (childrenOf[m.agentId] ?? []).sorted { $0.agentId < $1.agentId }.map(node),
                isLinkedToTranscript: m.toolUseId.map(facts.toolUseIds.contains) ?? false
            )
        }
        return roots.map(node)
    }

    // ── workflow agent ─────────────────────────────────────────

    /// journal 讀過之後**連續**讀不到幾次之內，沿用上一次讀到的事實。超過就切斷。
    ///
    /// ### 為什麼要切斷
    /// 「整個沒看到」不是「它還在那個狀態」（`~/CLAUDE.md` 的兩層規矩）。
    /// 新鮮度閘看的是 `agent-*.jsonl`，不是 journal —— 所以一份讀不到的 journal 每拍
    /// 都還會被問到、`sweep()` 不會放掉它。不切斷的話，讀不到那一刻還在 `running` 裡的
    /// agent 會一直被算成「執行中」，直到 session 結束。切斷之後的樣子與
    /// 「從來沒讀到過」一樣：全部 `.unknown`、沒有階段（run 已終結時照樣是 `.finished`）。
    ///
    /// ### 為什麼不是 0（讀不到就切）
    /// 〔讀碼 2.1.302〕`writeRestored` 在 storageV5 時先 `backend.delete` 再 `backend.append`；
    /// 那個 backend 是不是直接刪檔再建檔〔未驗證〕，是的話中間有一個讀不到的空窗。
    /// 一拍的空窗就閃成「不明」再閃回來，是在對一件沒有變的事改口。
    /// 2 是〔推論〕：一拍 3 秒，兩拍 ≈ 6 秒蓋得住那種空窗；**沒有量過**真實的空窗多長。
    public static let journalUnreadableGrace = 2

    private func workflowGroups(in subagents: URL, runs: URL,
                                journals: inout WorkflowJournalWatcher,
                                since start: Date, now: Date) -> [WorkflowGroup] {
        let fm = FileManager.default
        let root = subagents.appendingPathComponent("workflows")
        guard let ids = try? fm.contentsOfDirectory(atPath: root.path) else { return [] }

        var groups: [WorkflowGroup] = []
        for wfId in ids.sorted() {
            let dir = root.appendingPathComponent(wfId)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }

            let metas = names
                .compactMap { metaReader.read(dir.appendingPathComponent($0)) }
                .filter { Self.isFresh(agentId: $0.agentId, in: dir, since: start, now: now) }
                .sorted { $0.agentId < $1.agentId }
            guard !metas.isEmpty else { continue }

            // ⚠️ **journal 在新鮮度閘之後才讀，而且走游標。**
            // 原本它在閘**之前**每拍整份 `String(contentsOf:)` + `split`：早就死掉的
            // workflow（`subagents/` 跨 `--resume` 累積，這台機器最大的 journal 888KB）
            // 每拍都被整份解析一次，然後整組被上面那一行丟掉 —— 那份工作從來沒有人用過。
            // 〔實測 2026-09-22〕它是改造後剩下的 62.8 毫秒的主要來源；〔實測 2026-10-19，
            // 合成的家目錄，數字與條件見 docs/quotamonster.md 第五節 B〕同一種狀態的穩態中位
            // 從 67.9–128.0 毫秒降到 7.5–13.5 毫秒。
            // 「搬到閘後面」這一步本身不改變任何輸出：閘沒過的 group 本來就是 nil。
            // ⚠️ 但換成游標**有**改變輸出，見 docs/quotamonster.md 第五節 B 的「行為改變」：
            // 讀過之後讀不到時沿用已知的事（有寬限期，見 `journalUnreadableGrace`）、
            // 沒換行的最後一行要等換行、UTF-8 改成逐行寬鬆解碼。
            let journalURL = dir.appendingPathComponent("journal.jsonl")
            var journal = journals.update(journalURL)
            if journals.unreadableStreak(of: journalURL) > Self.journalUnreadableGrace {
                journal = WorkflowJournal()
            }

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
            groups.append(WorkflowGroup(workflowId: wfId, latestPhase: journal.latestPhase,
                                        agents: agents, runStatus: runState?.status,
                                        runDuration: runState?.duration))
        }
        return groups
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
}
