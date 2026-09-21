import Foundation

/// 面板額度三欄底下那一行註腳的字串。
///
/// ### 為什麼字串在 Core 而不是在 PanelView
/// `QuotaMonsterApp` 沒有測試（它碰 AppKit），而這個功能的風險幾乎全在字串上。
/// 一個新功能最容易造成的傷害不是算錯，是**安靜地改掉使用者已經每天在看的
/// 那一行**。放在這裡，「拒絕時與今天一模一樣」就是一個 `#expect`，
/// 不是一句承諾。
///
/// ### 兩欄的寬度預算是相反的（實測 `NSFont.systemFont(ofSize: 9)`，每欄約 99pt）
/// - **第一欄**今天是 `剩 1h 44m` = 44.1pt，**還有 55pt 空位** → 用「加」的
/// - **第二欄**今天是 `週六 下午1:59 · 日均 8.8%` = 109.9pt，**已經縮到 0.90** → 只能用「換」的
///
/// 所以箭頭只出現在第一欄；`週六 下午1:59 · 日均 8.8% ↑` 是 119.8pt，會被縮到 0.83。
public enum OutlookCaption {

    /// 第一欄「5 小時視窗」。
    ///
    /// - Parameter resetText: 今天就在顯示的那一行（`剩 1h 44m` / `已重置` / `" "`）。
    ///   展望說不出話時**原封不動回傳它**。
    public static func fiveHour(resetText: String, outlook: UsageOutlook?) -> String {
        guard let outlook else { return resetText }

        switch outlook.projection.outcome {
        case .resetsFirst(let projected):
            return "\(resetText) · 估 \(projected)%\(arrow(outlook.trend))"

        case .exceedsWindow:
            // ⚠️ **警報要兩個都同意才准出來。**
            // 均速會被窗口前段的一場衝刺帶偏；最近速率會被一段十四分鐘的突發帶偏。
            // 只有均速說會的時候，說一句比警報弱、又比沉默強的話。
            //
            // 警報那一格**不再加箭頭** —— 那已經是最強的說法了，
            // 再掛一個修飾符只會稀釋它。
            return outlook.exceedsConfirmed
                ? "\(resetText) · 估 會觸頂"
                : "\(resetText) · 估 >100%\(arrow(outlook.trend))"

        case .exhausted:
            // 已經滿了，剩下唯一有用的資訊是什麼時候恢復。
            // `resetText` 這時的內容正好是倒數，直接改寫它的語氣。
            guard resetText.hasPrefix("剩 ") else { return "已觸頂" }
            return "已觸頂 · \(resetText.dropFirst(2)) 後恢復"
        }
    }

    /// 第二欄「7 天 · 全模型」。
    ///
    /// **預設完全等於今天顯示的東西。** 只有在投射真的越過 100% 時，
    /// 「日均」才會被「會用完」**替換**掉 —— 不是附加，因為這一欄沒有空位。
    /// 也永遠沒有箭頭：7 天窗口拿不到最近速率（見 `UsageOutlook.sevenDay`）。
    public static func sevenDay(resetText: String, dailyAverage: Double?,
                                outlook: UsageOutlook?) -> String {
        if let outlook, outlook.projection.outcome == .exceedsWindow {
            return "\(resetText) · 會用完"
        }
        guard let dailyAverage else { return resetText }
        return "\(resetText) · " + String(format: "日均 %.1f%%", dailyAverage)
    }

    /// 箭頭。**`steady` 與「不知道」刻意都畫成空字串** ——
    /// 箭頭是純附加的，所以它的缺席不主張任何事；
    /// 如果 `steady` 有自己的符號，使用者就會把「不知道」讀成「持平」。
    static func arrow(_ trend: UsageTrend?) -> String {
        switch trend {
        case .faster: return " ↑"
        case .slower: return " ↓"
        case .steady, nil: return ""
        }
    }

    // ── tooltip ───────────────────────────────────────────────

    /// 完整的那句話 —— 包含 99pt 裡塞不下的**分母**。
    ///
    /// `.help()` 的成本是 0pt，所以誠實的完整版本放這裡。
    /// 說不出最近節奏時要**講出來**，不是安靜地省略：一個沒有箭頭的註腳，
    /// 使用者無從分辨是「持平」還是「資料不夠」。
    public static func evidence(_ outlook: UsageOutlook?) -> String {
        guard let outlook else { return "" }
        let p = outlook.projection

        var s = "這個視窗已經走了 \(duration(p.elapsed))，用掉 \(p.percent)%，"
        s += String(format: "均速每小時 %.1f%%。", p.burnPerHour)

        switch p.outcome {
        case .resetsFirst(let projected):
            s += "照這個速度到重置時約 \(projected)%，不會觸頂。"
        case .exceedsWindow:
            s += outlook.exceedsConfirmed
                ? "照這個速度會在重置前觸頂。"
                : "照均速會超過 100%，但最近的節奏還沒證實這件事。"
        case .exhausted:
            s += "已經觸頂了。"
        }

        switch outlook.burn {
        case .estimate(let e):
            let word = outlook.trend == .faster ? "快" : outlook.trend == .slower ? "慢" : "差不多"
            s += String(format: "最近 %@ 的節奏是每小時 %.1f%%，比均速%@。",
                        duration(e.span), e.percentPerHour, word)
        case .refused(let why):
            s += "（\(refusalText(why))）"
        }
        return s
    }

    public static func refusalText(_ why: BurnRefusal) -> String {
        switch why {
        case .noSamples:
            return "歷史還是空的，說不出最近是快是慢"
        case .notUsedForThisWindow:
            return "7 天視窗只看它自己的均速 —— 那個分母裡已經有你睡覺的時間了"
        case .tooFewPointsInRun(let n):
            return "歷史只有 \(n) 個點，說不出最近是快是慢"
        case .spanTooShort:
            return "歷史跨度太短，說不出最近是快是慢"
        case .staleTail:
            return "歷史停在太久以前，說不出最近是快是慢"
        case .tooFewPairs(let n):
            return "歷史只湊得出 \(n) 組間隔夠遠的點，說不出最近是快是慢"
        case .rateNotDistinguishableFromFlat:
            return "歷史上分不出在燒還是持平"
        case .negativeRate:
            return "歷史上的數字在往回走，不拿它算速率"
        }
    }

    static func duration(_ t: TimeInterval) -> String {
        let total = Int(t)
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return m > 0 ? "\(h) 小時 \(m) 分" : "\(h) 小時" }
        return "\(m) 分"
    }
}
