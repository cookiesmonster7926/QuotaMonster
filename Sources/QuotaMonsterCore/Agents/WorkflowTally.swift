import Foundation

/// 一個 session 底下那些 workflow 各自是什麼下場。
///
/// **為什麼需要這個型別：** 面板原本把所有沒在跑的 workflow 收成一行
/// 「另有 N 個 workflow 已完成」—— 於是**失敗的那些看不出來**。
/// 而 T2 刻意不對失敗的批次出聲（那是對的），所以那一行是它唯一的落腳處。
///
/// 分類放 Core 而不是放 `SessionRow`，理由與 `NotificationPresenter` 檔頭同一條：
/// App 層沒有測試 target，放進去的判斷就永遠不會有測試。
public struct WorkflowTally: Equatable, Sendable {

    public enum Outcome: Equatable, Sendable, CaseIterable {
        case completed
        /// run 自己回報失敗。
        case failed
        /// 你自己按了 TaskStop。**不是失敗** —— 你知道它為什麼停。
        case stopped
        /// 沒在跑，但我們**不知道**它的下場（run 狀態檔不存在或讀不到）。
        ///
        /// ⚠️ 它不可以被算進「已完成」。〔實測 2026-09-19，n=39〕磁碟上
        /// completed 34 / failed 3 / killed 1 / 沒有狀態檔 1 ——
        /// 四種都存在，沒有一種是虛構的分類。
        case unknown
    }

    public let running: Int
    public let counts: [Outcome: Int]

    public init(_ groups: [WorkflowGroup]) {
        var running = 0
        var counts: [Outcome: Int] = [:]
        for g in groups {
            // 還在跑的自己有一列，不進收合那一行。
            if g.runningCount > 0 { running += 1; continue }
            let outcome: Outcome
            switch g.runStatus {
            case "completed": outcome = .completed
            case "failed":    outcome = .failed
            case "killed":    outcome = .stopped
            // ⚠️ **nil 不是「已完成」。** 它是「沒在跑，但我們不知道下場」——
            // run 狀態檔不存在或讀不到。併進 completed 等於在面板上宣告
            // 一件我們不知道的事。
            default:          outcome = .unknown
            }
            counts[outcome, default: 0] += 1
        }
        self.running = running
        self.counts = counts
    }

    public func count(_ o: Outcome) -> Int { counts[o] ?? 0 }
    /// 已經不在跑的總數。
    public var settled: Int { Outcome.allCases.reduce(0) { $0 + count($1) } }

    /// 收合那一行要寫什麼。沒有東西要收合時回空陣列。
    ///
    /// 順序固定（已完成 → 失敗 → 已停止 → 狀態不明），這樣那一行不會因為
    /// 數量變化而左右跳動。
    public var collapsed: [(outcome: Outcome, text: String)] {
        let order: [(Outcome, String)] = [
            (.completed, "已完成"), (.failed, "失敗"),
            (.stopped, "已停止"), (.unknown, "狀態不明"),
        ]
        var out: [(outcome: Outcome, text: String)] = []
        for (outcome, label) in order where count(outcome) > 0 {
            // 「workflow」這個名詞跟著**第一格**走，不是寫死在已完成那一格 ——
            // 一個成功都沒有的時候，那一行仍然要說得出自己在講什麼。
            // 中文與拉丁字之間要空格，中文之間不要 —— 所以兩種句型分開寫。
            let text = out.isEmpty
                ? "\(count(outcome)) 個 workflow \(label)"
                : "\(count(outcome)) 個\(label)"
            out.append((outcome, text))
        }
        return out
    }
}
