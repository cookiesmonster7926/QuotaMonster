import Foundation

/// 「那一天沒有用量」與「那一天我們沒在看」是兩件事 —— 這個檔案記的是後者。
///
/// ### 為什麼需要它
/// `usage-history.jsonl` 是**事件驅動**的（`shouldRecord` 只在數字變了才寫）。
/// 對「值」來說那是無損的：階梯函數的每個台階都抓到了，所以「某時刻的值」
/// 永遠可以用「最後一個不晚於它的取樣點」還原。
///
/// 但它讓「某一天一行都沒有」變成一個**雙關**：可能是那天沒用，
/// 也可能是 app 那天沒開。每日長條圖必須分得出來，
/// 否則它會把「我沒在看」畫成「你沒有用」。
///
/// ### ⚠️ 為什麼是另一個檔案
/// 這一步（Stage 7 步驟 10）當初被擱置的理由（`docs/build-log.md:1190`）是：
/// 「程式碼很便宜，但它會改變『檔案裡沒有那一行』的意思，
/// 而那是**不可逆的語意變更**。」
///
/// 那個反對是對的：心跳一旦混進 `usage-history.jsonl`，舊資料與新資料的
/// 「沒有那一行」就永遠分不出來 —— 而且分不出來這件事本身也沒有紀錄。
///
/// 寫進獨立的 `watch-log.jsonl` 之後，`usage-history.jsonl` 的語意**一個字都沒動**，
/// 要反悔只要刪掉這個檔。**不可逆的那一半被移除了，所以這一步現在可以做。**
///
/// ⚠️ 這是純加值功能，寫檔失敗一律吞掉。額度面板不可以因為心跳寫不進去而壞掉。
public struct WatchLog: Sendable {

    public static let relativePath = "Library/Application Support/QuotaMonster/watch-log.jsonl"

    public static func defaultURL(home: URL) -> URL {
        home.appendingPathComponent(relativePath)
    }

    /// 多久寫一次心跳。
    ///
    /// 成本：288 行／天 × 30 天保留 ≈ 8,640 行 ≈ 190KB。
    /// 精度：日界的歸屬誤差上限就是一個間隔 —— 5 分鐘 / 1440 分鐘 = **一天的 0.35%**。
    /// 再密只是讓檔案變大，再疏會讓日界的判斷變鈍。
    public static let interval: TimeInterval = 300

    /// 與 `UsageHistory.retention` 相同 —— 兩個檔案描述的是同一段時間，
    /// 保留期不一致會讓「有值但不知道有沒有在看」這種空窗憑空出現。
    public static let retention: TimeInterval = UsageHistory.retention

    public enum Kind: String, Sendable {
        /// 定期心跳：「這一刻 app 醒著」。
        case heartbeat = "hb"
        /// 開機標記：「這裡是一次執行的起點」。
        ///
        /// ⚠️ 心跳的空隙**推不出**「app 重開了」還是「機器睡著了」。
        /// 這個標記讓兩者分得開 —— 睡醒不會有 boot，重開一定有。
        case boot
    }

    public struct Mark: Equatable, Sendable {
        public let at: Date
        public let kind: Kind

        /// 那一刻我們**看得到帳號的變化嗎**。
        ///
        /// ⚠️ **這不是「app 醒著嗎」。** 〔實測 2026-09-22〕18.8 小時裡有 16.1 小時
        /// （**85%**）這台機器沒有渲染狀態列（含一段 11.5 小時的整夜空窗），
        /// 而 QuotaMonster 在那段時間是醒著的。
        ///
        /// `7d` 是**帳號層級**的 —— 別人、別的裝置燒掉的都算在裡面 ——
        /// 但我們只在這台機器渲染狀態列時才看得到那個數字。
        /// 心跳原本只記「醒著」，於是「別人半夜燒掉 30%」那一天會被畫成
        /// **0%、滿分信心**。那是這張圖最容易犯、最難發現的謊。
        public let sawLiveReading: Bool

        public init(at: Date, kind: Kind, sawLiveReading: Bool = false) {
            self.at = at; self.kind = kind; self.sawLiveReading = sawLiveReading
        }
    }

    public init() {}

    /// 現在該不該寫。面板每 3 秒刷新一次，不可以每次都寫檔。
    ///
    /// - Parameter lastWrite: `nil` 代表這個行程還沒寫過 —— 那要寫，
    ///   不是「剛寫過」（規矩：不存在 ≠ 那個狀態不成立）。
    public static func shouldWrite(lastWatchMark: Date?, now: Date) -> Bool {
        guard let lastWatchMark else { return true }
        return now.timeIntervalSince(lastWatchMark) >= interval
    }

    // ── 讀寫 ───────────────────────────────────────────────────

    @discardableResult
    public func append(_ mark: Mark, to url: URL) -> Bool {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil
            else { return false }
        }
        guard let data = Self.encode(mark).data(using: .utf8) else { return false }
        if let h = try? FileHandle(forWritingTo: url) {
            defer { try? h.close() }
            guard (try? h.seekToEnd()) != nil else { return false }
            do { try h.write(contentsOf: data) } catch { return false }
            return true
        }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// 壞掉的行跳過 —— append-only 的最後一行可能只寫到一半。
    public func read(_ url: URL) -> [Mark] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { Self.decode(String($0)) }
            .sorted { $0.at < $1.at }
    }

    static func encode(_ m: Mark) -> String {
        "{\"t\":\(Int(m.at.timeIntervalSince1970)),\"k\":\"\(m.kind.rawValue)\""
            + ",\"v\":\(m.sawLiveReading ? 1 : 0)}\n"
    }

    static func decode(_ line: String) -> Mark? {
        guard let data = line.data(using: .utf8),
              let o = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let t = (o["t"] as? NSNumber)?.doubleValue,
              let k = o["k"] as? String, let kind = Kind(rawValue: k)
        else { return nil }
        // ⚠️ 舊格式沒有 `v`。**當成看不到**，不是當成看得到 ——
        // 把一段我們其實是瞎的時間宣告成可信，正是這個欄位要防的那件事。
        let saw = (o["v"] as? NSNumber)?.intValue == 1
        return Mark(at: Date(timeIntervalSince1970: t), kind: kind, sawLiveReading: saw)
    }

    // ── 那一刻有沒有人在看 ─────────────────────────────────────

    /// 一次漏寫不該讓整天作廢，所以容差給一個間隔的兩倍。
    public static let boundaryTolerance: TimeInterval = interval * 2

    /// - Returns: `instant` 前後 `tolerance` 之內，有沒有一筆**看得到**的紀錄。
    ///   ⚠️ **沒有紀錄回 false。** 沒有紀錄不是「有在看」的證據。
    ///   ⚠️ 只算 `sawLiveReading` 的那些 —— 醒著但看不到不算看著那個時刻，
    ///   而開機標記從來就不是觀測證據。
    public static func covers(_ instant: Date, marks: [Mark],
                              tolerance: TimeInterval = boundaryTolerance) -> Bool {
        marks.contains { $0.sawLiveReading && abs($0.at.timeIntervalSince(instant)) <= tolerance }
    }

    // ── 清理 ───────────────────────────────────────────────────

    /// - Returns: 真的重寫了才回 true。**沒有東西過期就一個位元組都不碰**
    ///   （理由與 `UsageHistory.prune` 相同：它是在計時器上被呼叫的）。
    @discardableResult
    public func prune(_ url: URL, now: Date) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let all = read(url)
        let keep = all.filter { now.timeIntervalSince($0.at) <= Self.retention }
        guard keep.count != all.count else { return false }
        let tmp = url.appendingPathExtension("tmp")
        let text = keep.map(Self.encode).joined()
        guard (try? text.write(to: tmp, atomically: true, encoding: .utf8)) != nil,
              (try? FileManager.default.replaceItemAt(url, withItemAt: tmp)) != nil
        else { try? FileManager.default.removeItem(at: tmp); return false }
        return true
    }
}
