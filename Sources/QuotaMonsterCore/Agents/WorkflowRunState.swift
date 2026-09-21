import Foundation

/// 一次 workflow 執行的整體狀態，來自 `<sessionId>/workflows/<wf_id>.json`。
///
/// **為什麼需要它：** journal 的「started 減去 result ∪ failed」在正常情況下是對的，
/// 但**被中止的 run 永遠不會寫 result 或 failed**，所以它的 agent 會永遠掛在執行中。
/// 這不是假設 —— 真實資料驗證時，一個被 TaskStop 停掉的 run 顯示成「5 隻執行中」。
///
/// 實測所有真實執行紀錄的 status 只有三種終結值：completed / failed / killed。
public struct WorkflowRunState: Equatable, Sendable {
    public let runId: String
    public let status: String?
    /// 這個 run **自己量**的執行時間，單位是**秒**。磁碟上是 `durationMs`（毫秒）。
    ///
    /// 〔實測 n=34，2026-09-19〕它等於 `timestamp − startTime`，殘差全部在 20ms 內。
    /// 再拿它對照「該目錄最早 meta 的 birthtime → 最後一次寫入」：差值中位 +0.0s、
    /// 範圍 −0.1s…+1.7s、0 個離群值。所以拿它當「這批跑了多久」在秒級是誠實的。
    ///
    /// ⚠️ **nil 是「不知道」，不是 0。** 0 是一個關於世界的斷言（它跑了 0 秒），
    /// 而讀不到只代表這個 run 還沒回報。0 特別惡毒 —— 它會被畫成「跑了 0m 00s」，
    /// 看起來像一個量到的數字。
    public let duration: TimeInterval?

    /// run 已經結束。此時裡面不可能有 agent 還在跑，**journal 說什麼都不算**。
    public var isTerminal: Bool {
        guard let status else { return false }
        return Self.terminalStatuses.contains(status)
    }

    public static let terminalStatuses: Set<String> = ["completed", "failed", "killed"]

    public init(runId: String, status: String?, duration: TimeInterval? = nil) {
        self.runId = runId
        self.status = status
        self.duration = duration
    }
}

public struct WorkflowRunStateReader: Sendable {
    public init() {}

    /// - Returns: 檔案不存在或讀不到時回傳 nil，呼叫端應退回 journal 判斷 ——
    ///   寧可少報一個終結，也不要讓整組 agent 憑空消失。
    public func read(runId: String, in workflowsDirectory: URL) -> WorkflowRunState? {
        let url = workflowsDirectory.appendingPathComponent("\(runId).json")
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        // ⚠️ **單位換算只准發生在這一行。** 換完之後型別上再也沒有任何一個叫
        // `...Ms` 的東西流出去，所以下游的單位錯誤在型別上不可能發生。
        //
        // 用 `NSNumber?.doubleValue` 而不是 `as? Int`：(一) `.intValue / 1000`
        // 是整數除法，會把 345160 悄悄變成 345；(二) `Int(Double)` 在這個 repo
        // 有明文血訓 —— 超過 Int.max 的值會直接 trap 掉整個行程，而這是磁碟上
        // 的數字。`doubleValue` 兩個問題都沒有。
        let ms = (d["durationMs"] as? NSNumber)?.doubleValue
        return WorkflowRunState(runId: runId, status: d["status"] as? String,
                                duration: ms.flatMap { $0 >= 0 ? $0 / 1000 : nil })
    }
}
