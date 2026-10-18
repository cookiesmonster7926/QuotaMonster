import Foundation

/// `--measure-ranfor` 的判讀：一份 transcript 裡，**會產生完成標記的那些回合**有幾個
/// 算得出 `ranFor`。新作法（`TurnOpener`）與舊作法（安靜 → 又動起來時讀 64KB 尾端、
/// 15 秒容忍度）對**同一個母體**各算一次。
///
/// ### ⚠️ 這是〔代理量測〕，不是實測
/// 正式路徑看的是檔案的 **mtime**（每 3 秒 stat 一次），歷史檔只剩每一行**自己的**
/// timestamp。這裡拿 timestamp 當 mtime 的代理：
/// - 「安靜 90 秒」＝ 相鄰兩行帶時刻的行之間差 ≥ 90 秒（沒帶時刻的行當成與前一行同時寫入）；
/// - 「完成」＝ 一則 end_turn 之後、模型再動或人打字之前，出現一次這樣的安靜（或到了檔尾）；
/// - 舊作法的「現在」取那一行自己的時刻（真的 app 會晚 0–3 秒，所以這對舊作法是**偏寬**的）。
/// 會漏掉的：沒寫進檔案的安靜（app 沒在跑）、時間戳不單調造成的假間隔。
///
/// 只產生計數，不保留任何一行的內容。
public struct RanForCoverage: Equatable, Sendable {

    /// 新作法算不出來的原因。與 `TurnOpener.Answer` 的三種 nil 一一對應，外加時間戳倒退。
    public enum Miss: String, CaseIterable, Sendable {
        case woken, noHuman, noTimestamp, notAfterStart
    }

    public private(set) var finishes = 0
    /// 新作法算得出 `ranFor` 的完成數。
    public private(set) var hits = 0
    public private(set) var misses: [Miss: Int] = [:]
    /// 舊作法（模擬）算得出**某個**值的完成數。⚠️ 只算「有值」，不保證那個值是對的。
    public private(set) var legacyHits = 0
    /// 新作法算出來的每一個 `ranFor`（秒），依出現順序。
    public private(set) var ranFor: [TimeInterval] = []
    /// 算得出 `ranFor`、而且那一輪後面有 `system/turn_duration` 的完成數。
    public private(set) var withTurnDuration = 0
    /// 其中 |ranFor − durationMs/1000| ≤ `agreementSeconds` 的數量。
    public private(set) var agreesWithTurnDuration = 0
    public private(set) var longerThanTurnDuration = 0
    public private(set) var shorterThanTurnDuration = 0

    /// ⚠️ 這個數字是選的（夠吸收秒級的寫入延遲），不是量出來的。
    public static let agreementSeconds: TimeInterval = 5

    public init() {}

    /// 一份 transcript 的完整內容，從第 0 個 byte 開始。
    public mutating func scan(_ data: Data) {
        // 每一行與它的起訖 byte —— 舊作法的 64KB 尾端要用。
        var rows: [(d: [String: Any], start: Int, end: Int)] = []
        var lineStart = data.startIndex
        while lineStart < data.endIndex {
            let nl = data[lineStart...].firstIndex(of: UInt8(ascii: "\n")) ?? data.endIndex
            let lineEnd = nl < data.endIndex ? nl + 1 : nl
            if let d = (try? JSONSerialization.jsonObject(with: data[lineStart..<nl])) as? [String: Any] {
                rows.append((d, lineStart - data.startIndex, lineEnd - data.startIndex))
            }
            lineStart = lineEnd
        }

        var opener = TurnOpener()
        var pending: (at: Date, id: String?, durationMs: Double?)?
        var lastAt: Date?
        var legacyStart: Date?

        func settle() {
            guard let p = pending else { return }
            pending = nil
            finishes += 1
            if let s = legacyStart, p.at > s { legacyHits += 1 }
            legacyStart = nil                 // 舊 tracker 宣告之後就清掉起點
            switch opener.answer {
            case .human(let start) where p.at > start:
                let r = p.at.timeIntervalSince(start)
                hits += 1
                ranFor.append(r)
                if let ms = p.durationMs {
                    withTurnDuration += 1
                    let diff = r - ms / 1000
                    if abs(diff) <= Self.agreementSeconds { agreesWithTurnDuration += 1 }
                    else if diff > 0 { longerThanTurnDuration += 1 }
                    else { shorterThanTurnDuration += 1 }
                }
            case .human:                 misses[.notAfterStart, default: 0] += 1
            case .humanWithoutTimestamp: misses[.noTimestamp, default: 0] += 1
            case .wokenWithoutHuman:     misses[.woken, default: 0] += 1
            case .noHumanYet:            misses[.noHuman, default: 0] += 1
            }
        }

        for (j, row) in rows.enumerated() {
            let d = row.d
            let at = TurnCompletionReader.timestamp(d)
            if let at, let last = lastAt, at.timeIntervalSince(last) >= CompletionTracker.settleWindow {
                // 安靜滿了：尾端是 end_turn 的話就是一個完成（用安靜之前的狀態判）。
                settle()
                // 舊作法：確認安靜之後的第一個寫入 → 讀 64KB 尾端找最後一則真人訊息。
                if legacyStart == nil,
                   let candidate = Self.lastHuman(in: rows, upTo: j,
                                                  windowStart: row.end - TurnCompletionReader.tailBytes),
                   at.timeIntervalSince(candidate) <= 15 {
                    legacyStart = candidate
                }
            }
            if let at { lastAt = at }

            opener.ingest(d)
            if TurnCompletionReader.isHuman(d) {
                pending = nil                 // 人在沉澱之前就打字了：不是完成
                continue
            }
            switch d["type"] as? String {
            case "assistant" where d["isSidechain"] as? Bool != true:
                let message = d["message"] as? [String: Any]
                let id = message?["id"] as? String
                if message?["stop_reason"] as? String == "end_turn", let at {
                    let carried = pending?.id == id ? pending?.durationMs : nil
                    pending = (at, id, carried)
                } else if pending?.id != id || id == nil {
                    pending = nil             // 模型在沉澱之前又動了
                }
            case "system" where d["subtype"] as? String == "turn_duration":
                if let ms = (d["durationMs"] as? NSNumber)?.doubleValue, pending != nil {
                    pending?.durationMs = ms
                }
            default:
                break
            }
        }
        settle()                              // 檔尾：之後再也沒有寫入
    }

    /// 尾端窗口裡（行首 ≥ `windowStart`）最後一則真人訊息的時刻。
    /// 與舊的 `readTurnStart` 同一個窗口規則：窗口外、被切斷的那半行不算。
    /// ⚠️ 「真人訊息」用的是**修過的** `isHuman`（compact 摘要、IDE 區塊那兩個洞已補），
    /// 不是舊版那一份 —— 差別只在 20 則形狀上，但這個模擬因此不是逐位元重現舊作法。
    private static func lastHuman(in rows: [(d: [String: Any], start: Int, end: Int)],
                                  upTo j: Int, windowStart: Int) -> Date? {
        var k = j
        while k >= 0, rows[k].start >= windowStart {
            if TurnCompletionReader.isHuman(rows[k].d) { return TurnCompletionReader.timestamp(rows[k].d) }
            k -= 1
        }
        return nil
    }
}
