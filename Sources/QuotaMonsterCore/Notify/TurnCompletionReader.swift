import Foundation

/// 「這個 session 的最後一個回合結束了嗎？」
///
/// 三態，而且三態是**必要的**：`nil` 一個值分不開「看到它、它還在跑」與
/// 「整個沒看到它」，而這兩件事的正確反應完全相反。
/// `WaitingContextReader.read` 就是把三件事塌縮成一個 nil 的反面教材。
public enum TurnReadout: Equatable, Sendable {
    /// 看到它了，而且它在完成狀態。**正面證據。**
    case finished(TurnEnd)
    /// 看到它了，而且它**不**在那個狀態。也是正面證據 —— 可以據此當場收掉標記。
    case unfinished
    /// 整個沒看到它（檔案讀不到、視窗裡一則 assistant 都沒有）。
    /// **不是證據**：不發訊號，也不熄滅既有的訊號。
    case inconclusive
}

public struct TurnEnd: Equatable, Sendable {
    /// 那一則 `end_turn` 行**自己的** timestamp。
    ///
    /// ⚠️ 不是 `Date()`、不是檔案 mtime。〔實測 2026-09-19〕全庫 490 個 end_turn 行
    /// 100% 都帶 timestamp，所以它不是 optional。
    public let finishedAt: Date

    public init(finishedAt: Date) { self.finishedAt = finishedAt }
}

/// 讀 transcript 的**尾端**，判斷這一輪講完了沒有。
///
/// 尾端讀取的每一個難處（64KB 視窗、被切斷的半行、NUL）`WaitingContextReader`
/// 都已經解掉了 —— 這裡**直接呼叫它的 `tail(of:bytes:)`**，不寫第二份。
/// 但它的 `read()` 不能用：它完全不看 `stop_reason`（只找待批准的 tool_use），
/// 而且 nil 同時代表三件語意完全不同的事。
public struct TurnCompletionReader: Sendable {

    /// 第一次讀的視窗。與 `WaitingContextReader` 共用同一個數。
    ///
    /// 〔實測〕要判讀的那一則 end_turn 行本身最大只有 20,905 B，所以 64KB 綽綽有餘。
    public static let tailBytes = WaitingContextReader.tailBytes

    /// 視窗裡一則 assistant 都沒有時，加大再讀一次。
    ///
    /// 〔實測，沉澱窗到期快照，n=337〕「視窗裡一則完整 assistant 都沒有」只有
    /// **2 個（0.59%）**，擠出距離 146,582 / 134,196 B —— **256KB 全覆蓋**。
    /// 漏接的成因一律是 end_turn 之後落下一行巨大的 `user(tool_result)` 或
    /// `attachment` 把它擠出視窗。
    public static let escalatedTailBytes = 256 * 1024

    public init() {}

    public func read(_ transcript: URL) -> TurnReadout {
        // 先用 64KB。只有「視窗裡一則 assistant 都沒有」才加大重讀 ——
        // 〔實測〕那是 0.59% 的情況，其餘 99.4% 只付一次 37µs 的讀取。
        let first = readout(transcript, bytes: Self.tailBytes)
        guard first == .inconclusive else { return first }
        return readout(transcript, bytes: Self.escalatedTailBytes)
    }

    /// 尾端裡**最後一則真人訊息**的時刻 —— 「這一輪從什麼時候開始」的候選。
    ///
    /// ⚠️ 只在「安靜 → 又動起來」那一刻呼叫一次，不是每一拍。
    /// 計畫書原本要求從 64KB 尾端回推到該輪第一則真人訊息，但〔實測 n=337〕
    /// 回合起點到 end_turn 的 byte 距離中位數是 **114,059 B**，
    /// 整個回合塞得進 64KB 的只有 **37.4%** —— 那條路做不到。
    public func readTurnStart(_ transcript: URL) -> Date? {
        guard let tail = WaitingContextReader.tail(of: transcript, bytes: Self.tailBytes) else {
            return nil
        }
        let lines = Array(tail.split(separator: "\n", omittingEmptySubsequences: true))
        for line in lines.reversed() {
            guard let d = Self.object(line), Self.isHuman(d) else { continue }
            return Self.timestamp(d)
        }
        return nil
    }

    // ── 判讀 ───────────────────────────────────────────────────

    private func readout(_ transcript: URL, bytes: Int) -> TurnReadout {
        guard let tail = WaitingContextReader.tail(of: transcript, bytes: bytes) else {
            return .inconclusive
        }
        let lines = Array(tail.split(separator: "\n", omittingEmptySubsequences: true))

        // 由後往前找第一則可解析的 assistant。半行解不出來就跳過
        // （append-only 檔隨時可能讀到寫一半的最後一行）。
        var parsed: [Int: [String: Any]] = [:]
        var k: Int?
        for i in stride(from: lines.count - 1, through: 0, by: -1) {
            guard let d = Self.object(lines[i]) else { continue }
            parsed[i] = d
            guard d["type"] as? String == "assistant" else { continue }
            // 降版防線：舊版把 subagent 的行混在母檔裡，那些 end_turn 不是
            // 主 session 講完了。⚠️〔推論〕這台機器 25,281 行裡 isSidechain 全是
            // false，所以**這一行沒有資料可以驗證它有沒有用**。
            if d["isSidechain"] as? Bool == true { continue }
            k = i
            break
        }
        // 整個沒看到它。**不是** 「它還在跑」。
        guard let k else { return .inconclusive }

        let message = parsed[k]?["message"] as? [String: Any]
        // ⚠️ 只看 stop_reason，**不看 content**。理由見 thinkingOnlyEndTurnStillCounts 那則測試。
        guard message?["stop_reason"] as? String == "end_turn" else { return .unfinished }

        // 那一則 end_turn **之後**還有真人訊息 → 它是上一輪的，這一輪才剛開始。
        // 〔實測〕479 個以真人訊息為起點的間隔裡有 6 個超過 90 秒，最長 623 秒 ——
        // 沒有這一段，那 6 次會在使用者剛按下 Enter 的時候宣告「講完了」。
        // 這同時免費吃掉 Esc 中斷那道閘（中斷標記本來就是一則真人訊息）。
        for i in (k + 1)..<lines.count {
            guard let d = parsed[i] ?? Self.object(lines[i]) else { continue }
            if Self.isHuman(d) { return .unfinished }
        }

        // 沒有時刻就不宣告完成 —— 硬編一個 `Date()` 進去就是憑空造一個量測。
        guard let at = parsed[k].flatMap(Self.timestamp) else { return .inconclusive }
        return .finished(TurnEnd(finishedAt: at))
    }

    // ── 「這是人打的嗎」——全 repo 只有這一份定義 ────────────────

    /// harness 注入、但長得像真人訊息的那些開頭。
    static let harnessPrefixes = [
        "<task-notification>", "<local-command-stdout>", "<local-command-caveat>",
        "<command-message>", "<command-name>", "<system-reminder>", "<ide_opened_file>",
    ]

    /// ⚠️ **`content` 是字串或 list 兩種形狀都要收。**
    ///
    /// 〔實測 2026-09-19〕非 tool_result 的 user 行 395 則：字串 290（其中 **93 則
    /// `isMeta=true`**，是 skill caveat／圖片占位／slash command 展開／agent 間訊息），
    /// `list(text)` 144、`list(image,text)` 33 —— **貼截圖的訊息一定是 list**。
    /// 「字串＝真人、list＝harness」這個直覺**兩個方向都錯**：
    /// 照它寫會吞掉約四分之一的真人輸入，又會把 93 則 harness 訊息當成真人。
    static func isHuman(_ d: [String: Any]) -> Bool {
        guard d["type"] as? String == "user",
              d["isMeta"] as? Bool != true,
              let message = d["message"] as? [String: Any] else { return false }

        let text: String
        if let s = message["content"] as? String {
            text = s
        } else if let blocks = message["content"] as? [[String: Any]] {
            // harness 餵回工具結果，不是人打的。
            if blocks.contains(where: { $0["type"] as? String == "tool_result" }) { return false }
            text = blocks.compactMap { $0["text"] as? String }.joined(separator: " ")
        } else {
            return false
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !Self.harnessPrefixes.contains { trimmed.hasPrefix($0) }
    }

    static func object(_ line: Substring) -> [String: Any]? {
        guard let data = line.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    static func timestamp(_ d: [String: Any]) -> Date? {
        guard let raw = d["timestamp"] as? String else { return nil }
        return try? ResetTimestamp.parse(.iso8601(raw))
    }

    /// 檔案的 mtime。沉澱窗靠它，不靠解析內容。
    public func modifiedAt(_ transcript: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: transcript.path))?[.modificationDate]
            as? Date
    }
}
