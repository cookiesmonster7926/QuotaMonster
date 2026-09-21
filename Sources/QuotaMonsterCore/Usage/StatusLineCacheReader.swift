import Foundation

/// 讀 statusline tee 寫出來的快取目錄。
///
/// 快取的每個檔案都是 Claude Code 餵給 statusLine 的 payload **原文**，
/// 由 `scripts/quotamonster-tee.sh` 以 tmp + rename 原子寫入，檔名是 session id。
/// 我們只讀，不寫；清理是 `StatusLineCachePruner` 的事。
///
/// **這是目錄掃描器，所以永不丟錯。** 壞檔跳過、目錄不存在回空陣列 ——
/// 與 `SessionRegistryReader` 同一套規矩，而不是 `ClaudeJSONUsageReader`
/// 那種「單一具名檔案」的規矩。理由：Claude Code 會在新事件觸發時 abort 執行中的
/// 腳本，被 SIGKILL 打斷時目錄裡就是會有寫到一半的東西，那是正常現象不是錯誤。
///
/// 解析規則的兩個來源（官方文件 + v2.1.276 二進位檔）互相對過帳，
/// 三個一寫就錯的地方：
///   - `resets_at` 是 **Unix epoch 秒的整數**。`~/.claude.json` 那邊是 ISO-8601 字串，
///     混用不會報錯，只會產生差了幾十年的倒數。
///   - `rate_limits.*.used_percentage` 是**浮點**（`wQe(t) = Math.round(t*1000)/10`），
///     用 `intValue` 會把 30.6 截成 30。
///   - `context_window.used_percentage` 卻是**整數**（`yVt` 的 `Math.round`，夾在 0–100）。
public struct StatusLineCacheReader: Sendable {

    /// 快取目錄相對於家目錄的位置。
    ///
    /// ⚠️ **這個字串必須與 `scripts/quotamonster-tee.sh` 裡 `DIR` 的預設值逐字相同。**
    /// 兩邊各寫各的路徑不會有任何錯誤訊息 —— wrapper 照常寫檔、app 照常讀到空目錄，
    /// 表現出來就是「tee 裝了但額度還是過期」。`StatusLineCachePathTests` 會比對這兩份。
    ///
    /// 放在 Application Support 而不是 `~/.claude/` 底下：那是 Claude Code 的目錄，
    /// 它自己有 `.last-cleanup`。我們的資料放我們自己的地方。
    public static let relativeCacheDirectory = "Library/Application Support/QuotaMonster/statusline"

    public static func defaultDirectory(home: URL) -> URL {
        home.appendingPathComponent(relativeCacheDirectory)
    }

    /// `resets_at` 合理的上界。⚠️ 保留這個名字是為了既有呼叫點，
    /// 真正的定義在 `WindowExpiry.horizon`（規矩 2：只能有一份）。
    /// 只實作下界的話，一個壞掉的時間戳會變成一個永遠不會過期的窗口。
    public static let resetHorizon: TimeInterval = WindowExpiry.horizon

    /// 百分比的合理上界。`five_hour` / `seven_day` 依文件是 0–100，
    /// 但 `spend_limit` 超用之後可以超過 100，所以留一段餘裕而不是硬夾在 100。
    ///
    /// ⚠️ 這個夾限不是美觀問題，是**防當機**：`Int(Double)` 在超出 `Int.max`
    /// 時會 trap，而 `1e20` 是完全合法的 JSON 數字。實測沒有夾限時整個測試行程
    /// 以 signal 5 死掉（`Double value cannot be converted to Int`）。
    public static let maxPercent: Double = 1000

    public init() {}

    /// - Parameter now: 用來判斷窗口是否已經重置。注入而不是呼叫 `Date()`，
    ///   測試才能對固定的 fixture 時間重現。
    public func read(directory: URL, now: Date) -> [StatusLinePayload] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        return names
            .filter { !$0.hasPrefix(".") && $0.hasSuffix(".json") }   // .tmp.* 是寫到一半的
            .sorted()
            .compactMap { Self.parse(directory.appendingPathComponent($0), now: now) }
    }

    static func parse(_ url: URL, now: Date) -> StatusLinePayload? {
        // 0 bytes 是寫入中的正常現象；截斷的 JSON 是被 SIGKILL 打斷的殘骸。兩種都跳過。
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }

        // mtime 可能在未來（時鐘往回跳、或檔案從別的機器同步過來）。
        // 不夾住的話它的年齡是負的，會被判成永遠「剛更新」，而且永遠贏過另一個來源。
        let mtime = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate])
            as? Date
        let capturedAt = min(mtime ?? now, now)

        let limits = root["rate_limits"] as? [String: Any] ?? [:]
        let context = root["context_window"] as? [String: Any] ?? [:]

        return StatusLinePayload(
            sessionId: root["session_id"] as? String,
            capturedAt: capturedAt,
            modelDisplayName: (root["model"] as? [String: Any])?["display_name"] as? String,
            cwd: root["cwd"] as? String,
            contextUsedPercent: (context["used_percentage"] as? NSNumber)?.intValue,
            contextWindowSize: (context["context_window_size"] as? NSNumber)?.intValue,
            totalInputTokens: (context["total_input_tokens"] as? NSNumber)?.intValue,
            fiveHour: window(from: limits["five_hour"], now: now),
            sevenDay: window(from: limits["seven_day"], now: now),
            spendLimit: window(from: limits["spend_limit"], now: now)
        )
    }

    /// 窗口缺席代表「不知道」，永遠不是 0%。
    ///
    /// Claude Code 自己就會在 `resets_at` 過了之後把窗口從 payload 拿掉
    /// （二進位 `MSn`：`resets_at > now && resets_at < now + 一年`）。
    /// 這裡兩個界都再擋一次 —— 快取檔可能在窗口重置之後才被我們讀到，
    /// 而壞掉的時間戳會變成一個永遠不會過期的窗口。
    static func window(from any: Any?, now: Date) -> UsageWindow? {
        guard let dict = any as? [String: Any],
              let number = dict["used_percentage"] as? NSNumber
        else { return nil }
        // 字串 "9" 轉不出 NSNumber，未來版本改型別時會回 nil 而不是生出假數字。
        let raw = number.doubleValue
        // 非有限值與負數都不是讀數。夾上界是為了不讓 Int(Double) trap。
        guard raw.isFinite, raw >= 0 else { return nil }
        let percent = Int(min(raw, maxPercent).rounded())

        var resetsAt: Date?
        if let seconds = (dict["resets_at"] as? NSNumber)?.doubleValue,
           seconds.isFinite {
            guard let reset = try? ResetTimestamp.parse(.epochSeconds(seconds)) else { return nil }
            // 過期與壞掉的時間戳都由 `WindowExpiry` 判 —— 這條規則只能有一份定義，
            // 理由（以及它有兩份時付出的代價）見 `WindowExpiry` 的檔頭。
            guard WindowExpiry.accepts(resetsAt: reset, now: now) else { return nil }
            resetsAt = reset
        }
        return UsageWindow(percent: percent, resetsAt: resetsAt)
    }
}
