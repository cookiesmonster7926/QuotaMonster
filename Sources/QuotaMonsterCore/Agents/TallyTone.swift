import Foundation

/// 面板收合那一行（「另有 1 個 workflow 已完成 · 1 個失敗 · …」）每一格的語氣。
/// App 層把它翻成顏色：`bad` 紅、`unknown` secondary、`quiet` tertiary。
///
/// ### 為什麼在 Core
/// 搬移前是 `SessionRow` 裡兩支各自 switch 的 private func（workflow 一支、agent 一支），
/// 而「兩支必須一致」只是一句註解。規矩 48 最後一條：收合那一行的用詞與顏色
/// 必須與 `WorkflowTally` 完全一樣 —— 同一件事兩套語彙，這個 repo 已經為它付過
/// 一次代價（規矩 43）。現在兩邊都經過這裡，而且有一則測試把兩邊同一個字配起來比。
///
/// ⚠️ **不可以有「要你輸入」的語氣。** 黃／琥珀只屬於那件事（規矩 24）。
public enum TallyTone: Equatable, Sendable {
    /// 壞消息 —— 失敗。借面板裡紅色既有的語彙（ctx ≥ 紅門檻也是紅的），不多開一套。
    case bad
    /// 沒有消息 —— 讀不到下場。它不是壞消息，所以不是紅。
    case unknown
    /// 其餘：已完成、已停止（你自己按的 TaskStop，你知道它為什麼停）。
    case quiet

    public init(_ outcome: WorkflowTally.Outcome) {
        switch outcome {
        case .failed:              self = .bad
        case .unknown:             self = .unknown
        case .completed, .stopped: self = .quiet
        }
    }

    /// nil ＝ 讀不到下場 ＝「狀態不明」，對應 workflow 的 `.unknown`。
    public init(_ outcome: AgentOutcome.Kind?) {
        switch outcome {
        case .failed:               self = .bad
        case .none:                 self = .unknown
        case .completed, .killed:   self = .quiet
        }
    }
}
