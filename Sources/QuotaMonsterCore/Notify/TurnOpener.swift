import Foundation

/// 「這一輪是誰開的、從什麼時候開始」—— 往前掃 transcript 時順手記下來。
///
/// ### 為什麼不從尾端往回搆
/// 舊作法在「安靜滿 90 秒 → 又動起來」那一刻讀 64KB 尾端，找最後一則真人訊息，
/// 而且只收比「現在」早 15 秒以內的。〔實測 2026-09-22〕53 分鐘產生的 7 個完成
/// 標記 **7/7 算不出 `ranFor`**（第三節第 33 條）。那條路有兩個結構上的洞：
/// 回得快的人（上一輪講完不到 90 秒就回話）永遠湊不到「確認安靜」；
/// 而整個回合塞得進 64KB 的只有 37.4%〔實測 n=337〕。
///
/// `TranscriptCursor` 本來就是**往前**、每一行都看過一次的。在那裡記下
/// 「最後一則真人訊息」，回合起點就不必往回搆，也不必猜它是不是太舊。
///
/// ### 三種「算不出來」是三件不同的事
/// 依 `~/CLAUDE.md` 的兩層規矩：
/// - **看到了、但它不是真人訊息**（tool_result、isMeta、背景通知、compact 摘要、
///   command 與它的輸出）→ 正面證據，起點**留在原地**，不變成「不知道」。
///   判準只有一份：`TurnCompletionReader.isHuman`。
/// - **看到了、但這一輪不是人開的**：最後一則真人訊息之後模型已經講完過一次，
///   之後是背景通知／peer 訊息／排程把它叫醒的 → `.wokenWithoutHuman`。
///   拿那則真人訊息當起點，會把「講完 → 通知抵達」中間的閒置也算進「跑了多久」。
/// - **整個沒看到**（這份 transcript 從沒讀到過）不在這裡 —— 這個型別只在讀到行時才存在。
///   那一層是 `TranscriptWatcher.opening(of:)` 回 nil。
public struct TurnOpener: Equatable, Sendable {

    public enum Answer: Equatable, Sendable {
        /// 這一輪由一則真人訊息開啟，時刻是那一行**自己的** timestamp。
        case human(Date)
        /// 看到那則真人訊息了，但它沒帶時刻（或解析不出來）。
        /// ⚠️ 不可以拿別行的時刻、mtime 或 `Date()` 補。
        case humanWithoutTimestamp
        /// 最後一則真人訊息之後，模型講完過一次，又被別的東西叫醒。
        case wokenWithoutHuman
        /// 掃過的行裡一則真人訊息都沒有。**正面證據**：看到了，沒有。
        case noHumanYet
    }

    public private(set) var answer: Answer = .noHumanYet

    /// 最後一則真人訊息之後，講完（end_turn）的那一則 assistant 訊息的 id。
    /// nil ＝ 自那則真人訊息以來還沒講完過。
    ///
    /// ⚠️ 要記 **id** 而不是布林：一則訊息會被寫成好幾行（thinking 一行、text 一行，
    /// 兩行都帶 `stop_reason: end_turn`）。只記「講完過」的話，第二行會被當成
    /// 「又被叫醒、講了新的一段」。〔本機唯讀計數 2026-10-19〕24,408 行 assistant
    /// 全部帶 `message.id`；沒帶的那種當成「分不出是不是同一則」，往 nil 那邊判。
    private var endedMessageId: String??

    public init() {}

    public mutating func ingest(_ d: [String: Any]) {
        if TurnCompletionReader.isHuman(d) {
            answer = TurnCompletionReader.timestamp(d).map(Answer.human) ?? .humanWithoutTimestamp
            endedMessageId = nil
            return
        }

        guard d["type"] as? String == "assistant",
              d["isSidechain"] as? Bool != true,
              let message = d["message"] as? [String: Any] else { return }
        let id = message["id"] as? String

        if case .some(let ended) = endedMessageId, ended == nil || id == nil || ended != id,
           answer != .noHumanYet {
            // 講完之後模型又寫了一則**不同的**訊息，中間沒有真人訊息。
            // （一則真人訊息都還沒看過時維持 `.noHumanYet` —— 「被叫醒」是相對於
            // 某一則真人訊息說的，沒有那一則就沒有這句話。）
            answer = .wokenWithoutHuman
        }
        if message["stop_reason"] as? String == "end_turn" {
            endedMessageId = .some(id)
        }
    }
}
