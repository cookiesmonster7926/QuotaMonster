import Foundation

/// 某個時刻的額度讀數。時間序列的一個點。
public struct UsageSample: Equatable, Sendable {
    public let at: Date
    /// nil 代表「那個時候不知道」，與 0% 是兩回事。
    public let fiveHour: Int?
    public let sevenDay: Int?

    public init(at: Date, fiveHour: Int?, sevenDay: Int?) {
        self.at = at
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
    }

    /// - Returns: 快照不可信時回 nil。
    ///
    /// ⚠️ **`.expired` 不產生取樣點。** 歷史檔是要拿來畫圖與算燒量速率的，
    /// 一個過期的數字進去之後，下游沒有任何地方分得出它與真實讀數的差別。
    /// 〔實測 2026-09-21〕這不是預防性的：`usage-history.jsonl` 的 09-20 15:25
    /// 那筆 `{"5h":30,"7d":19}` 逐字等於 `~/.claude.json` 那個從 09-17 凍住的檔案，
    /// 它當時的 freshness 就是 `.expired`，照樣被寫進去了。
    /// `.aging` 仍然收 —— 它只是有點舊，不是不可信。
    public init?(_ snapshot: UsageSnapshot?, at: Date) {
        guard let snapshot, snapshot.freshness != .expired else { return nil }
        self.at = at
        self.fiveHour = snapshot.fiveHour?.percent
        self.sevenDay = snapshot.sevenDay?.percent
    }
}

/// 額度的時間序列，存成 append-only 的 JSONL。
///
/// 為什麼需要它：**磁碟上沒有任何地方記錄額度隨時間的變化。**
/// Claude Code 只存「現在是多少」。所以「每日長條圖」與「燒量速率／觸頂預測」
/// 都必須由 app 自己累積。tee 裝好之後這件事變得便宜 ——
/// 每次狀態列渲染就是一個帶時間戳的取樣點。
///
/// 格式（一行一個點，刻意壓到最短）：
/// ```
/// {"t":1789671234,"5h":20,"7d":45}
/// ```
///
/// ⚠️ **這是純加值功能，寫檔失敗絕不可以往上炸。** 所有錯誤都吞掉並回 false。
/// 額度面板不可以因為歷史記錄寫不進去而壞掉。
public struct UsageHistory: Sendable {

    /// 檔案相對於家目錄的位置。與快取放在同一個 app 目錄底下。
    public static let relativePath = "Library/Application Support/QuotaMonster/usage-history.jsonl"

    public static func defaultURL(home: URL) -> URL {
        home.appendingPathComponent(relativePath)
    }

    /// 保留 30 天。長條圖只看 7 天，多留一些給「燒量速率」用。
    public static let retention: TimeInterval = 30 * 86400

    public init() {}

    /// 這個取樣點值不值得寫進去。
    ///
    /// 三秒輪詢一天會問兩萬多次，數字沒變就寫只是噪音 —— 而且會讓 30 天的檔案
    /// 從幾千行變成六十萬行。
    public static func shouldRecord(_ sample: UsageSample, previous: UsageSample?) -> Bool {
        // 兩個窗口都不知道的時候，這個點沒有任何資訊量。
        guard sample.fiveHour != nil || sample.sevenDay != nil else { return false }
        guard let previous else { return true }
        return sample.fiveHour != previous.fiveHour || sample.sevenDay != previous.sevenDay
    }

    /// 追加一行。回傳有沒有真的寫進去 —— 失敗時回 false，不丟錯。
    @discardableResult
    public func append(_ sample: UsageSample, to url: URL) -> Bool {
        let fm = FileManager.default
        let dir = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: dir.path) {
            guard (try? fm.createDirectory(at: dir, withIntermediateDirectories: true)) != nil
            else { return false }
        }

        let line = Self.encode(sample)
        guard let data = line.data(using: .utf8) else { return false }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            guard (try? handle.seekToEnd()) != nil else { return false }
            do { try handle.write(contentsOf: data) } catch { return false }
            return true
        }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    /// 讀回整個序列，按時間排序。壞掉的行跳過 ——
    /// append-only 的檔案最後一行可能只寫到一半。
    public func read(_ url: URL, now: Date) -> [UsageSample] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .compactMap { Self.decode(String($0)) }
            .sorted { $0.at < $1.at }
    }

    /// 檔案裡最後一筆完整的取樣點。
    ///
    /// ⚠️ **開機時一定要呼叫這個來當去重的基準。** 「上一筆是什麼」放在記憶體裡，
    /// 所以每個新行程都會覺得自己是第一次 —— 實測 app 重啟三次加兩支診斷指令，
    /// 就寫出四行一模一樣的紀錄。
    public func last(_ url: URL) -> UsageSample? {
        read(url, now: Date()).last
    }

    /// 清理的間隔。
    ///
    /// ⚠️ **刻意比 statusline 快取的清理慢一個數量級。** 那邊清的是 SIGKILL
    /// 留下的孤兒，值得每分鐘看一次；這邊的保留期是 **30 天**，所以絕大多數
    /// 時候要刪的正好是零行 —— 每分鐘跑一次只是在重寫同一個檔案 1440 次。
    public static let pruneInterval: TimeInterval = 3600

    /// 丟掉超過保留期的點。整個檔案重寫，走 tmp + rename。
    ///
    /// - Returns: 真的重寫了才回 true。
    ///   **沒有東西過期就一個位元組都不碰** —— 這支函式會把整個檔案解析一遍、
    ///   重新編碼、再 rename 換掉，為了刪零行做這些事沒有道理，而且它是在
    ///   計時器上被呼叫的。
    @discardableResult
    public func prune(_ url: URL, now: Date) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let all = read(url, now: now)
        let kept = all.filter { now.timeIntervalSince($0.at) <= Self.retention }
        guard kept.count != all.count else { return false }

        let text = kept.map(Self.encode).joined()
        let tmp = url.appendingPathExtension("qm-tmp")
        guard (try? text.write(to: tmp, atomically: false, encoding: .utf8)) != nil else { return false }
        if (try? FileManager.default.replaceItemAt(url, withItemAt: tmp)) == nil {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
        return true
    }

    // ── 一行的編碼 ────────────────────────────────────────────────
    // 手寫而不是用 Codable：欄位只有三個、要壓到最短，而且這個格式會被
    // 人眼直接看（出事時使用者自己 tail 就懂）。

    static func encode(_ s: UsageSample) -> String {
        let five = s.fiveHour.map(String.init) ?? "null"
        let seven = s.sevenDay.map(String.init) ?? "null"
        return "{\"t\":\(Int(s.at.timeIntervalSince1970)),\"5h\":\(five),\"7d\":\(seven)}\n"
    }

    static func decode(_ line: String) -> UsageSample? {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let t = (obj["t"] as? NSNumber)?.doubleValue
        else { return nil }
        return UsageSample(at: Date(timeIntervalSince1970: t),
                           fiveHour: (obj["5h"] as? NSNumber)?.intValue,
                           sevenDay: (obj["7d"] as? NSNumber)?.intValue)
    }
}
