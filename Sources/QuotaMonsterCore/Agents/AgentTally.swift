import Foundation

/// 一個 session 底下的一般 Agent subagent：哪些還沒好、其餘各自是什麼下場。
///
/// ### 為什麼需要它
/// 面板原本把**每一隻** agent 都列出來，而 `AgentTreeBuilder.isFresh` 只濾掉
/// 「不是這一輪的」—— 所以這個 session 開過的每一隻都會一直掛著。
/// 使用者 2026-09-22 回報：「顯示成 subagent 就會讓使用者不知道到底是什麼還沒好」。
///
/// workflow 早就有這個收合規則（`WorkflowTally`），agent 沒有 ——
/// **整齊的那個藏起來、雜亂的那個堆著，方向正好相反。**
///
/// ### 「已完成」現在有證據了
/// ⚠️ 這裡原本寫的是「已結束」，理由是「一般 agent 的完成狀態讀得到，但要掃
/// 13MB 的母 transcript，**這一版沒有做**」。〔2026-09-22 下午做了〕
/// `TranscriptWatcher` + `TranscriptCursor` 只解析新增的行，所以現在讀得到 ——
/// 而且順手把 `refresh()` 的穩態從 1004 毫秒降下來（那支整份重讀是同一個地方）。
///
/// ⚠️ **但「讀不到下場」仍然是自己的一格。** 那正是第二節拒絕 2：
/// 沒有狀態就是不知道下場，併進「已完成」等於在面板上宣告一件我們不知道的事。
/// 實測上它一定會發生 —— 18.5% 的背景 agent 從來沒有終端記錄
/// （其中兩隻是設計上就不會結束的伺服器）。
public struct AgentTally: Equatable, Sendable {

    /// 還沒好的 —— 有自己一行。
    public let outstanding: [AgentNode]
    /// 已經結束、而且**讀到了**下場的，依下場分。
    public let counts: [AgentOutcome.Kind: Int]
    /// 已經結束、但**沒讀到**下場的。
    public let unknownCount: Int

    public init(_ agents: [AgentNode]) {
        var live: [AgentNode] = []
        var counts: [AgentOutcome.Kind: Int] = [:]
        var unknown = 0
        func walk(_ n: AgentNode) {
            switch n.runState {
            case .running, .likelyRunning:
                live.append(n)
            case .finished, .unknown:
                if let o = n.outcome { counts[o, default: 0] += 1 } else { unknown += 1 }
            }
            n.children.forEach(walk)
        }
        agents.forEach(walk)
        self.outstanding = live
        self.counts = counts
        self.unknownCount = unknown
    }

    public func count(_ o: AgentOutcome.Kind) -> Int { counts[o] ?? 0 }
    /// 已經不在跑的總數（含讀不到下場的）。
    public var endedCount: Int {
        counts.values.reduce(0, +) + unknownCount
    }

    /// 收合那一行要寫什麼。沒有東西要收合時回空陣列。
    ///
    /// 順序固定（已完成 → 失敗 → 已停止 → 狀態不明），這樣那一行不會因為
    /// 數量變化而左右跳動 —— 與 `WorkflowTally.collapsed` 同一個形狀與同一套用詞。
    /// ⚠️ 同一件事在兩個地方要用同一套語彙，這個 repo 為了違反它付過代價（規矩 43）。
    public var collapsed: [(outcome: AgentOutcome.Kind?, text: String)] {
        let order: [(AgentOutcome.Kind?, String)] = [
            (.completed, "已完成"), (.failed, "失敗"),
            (.killed, "已停止"), (nil, "狀態不明"),
        ]
        var out: [(outcome: AgentOutcome.Kind?, text: String)] = []
        for (outcome, label) in order {
            let n = outcome.map(count) ?? unknownCount
            guard n > 0 else { continue }
            // 「agent」這個名詞跟著**第一格**走，不是寫死在已完成那一格 ——
            // 一個成功都沒有的時候，那一行仍然要說得出自己在講什麼。
            // 中文與拉丁字之間要空格，中文之間不要 —— 所以兩種句型分開寫。
            let text = out.isEmpty ? "\(n) 個 agent \(label)" : "\(n) 個\(label)"
            out.append((outcome, text))
        }
        return out
    }

    /// 給 `--dump` 與測試用的一整串。⚠️ 面板走 `collapsed`，因為它要分色。
    public var collapsedText: String? {
        let parts = collapsed
        return parts.isEmpty ? nil : parts.map(\.text).joined(separator: " · ")
    }
}
