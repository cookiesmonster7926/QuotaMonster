import Foundation

/// 7 天窗口裡的一天。
public struct DailyUsageBar: Equatable, Sendable {
    public enum State: Equatable, Sendable {
        /// 這一天還沒開始。⚠️ **不是 0%** —— 「還沒發生」不是「沒有用」。
        case notYet
        /// 兩端都被看著，這個數字站得住。
        case measured(percent: Int)
        /// 數字算得出來，但有一端沒有心跳 —— **歸屬可能落在隔壁那天**。
        case unverified(percent: Int)
        /// 說不出來：那天 app 沒開，或資料違反了單調的前提。
        case unknown
    }

    public let index: Int
    public let start: Date
    public let end: Date
    public let state: State

    public init(index: Int, start: Date, end: Date, state: State) {
        self.index = index; self.start = start; self.end = end; self.state = state
    }

    /// 畫長條要用的高度。說不出數字的一律 0（畫成空的或斜線，不是畫成 0%）。
    public var percent: Int? {
        switch state {
        case .measured(let p), .unverified(let p): return p
        case .notYet, .unknown: return nil
        }
    }
}

/// 把 `usage-history.jsonl` 的階梯函數切成 7 天窗口裡的每日用量。
///
/// ### 為什麼可以差分
/// 〔實測 2026-09-22〕`7d` 在**同一個窗口內單調遞增**。
/// 我一度量到它會下降並據此判定「不能差分」—— 那次量測在修好
/// 「舊數字被當成新讀數」之前，而且 `7d` 與 `5h` **同時**下降，
/// 那是帶著舊值的 payload 的指紋，不是滾動窗口。
/// ⚠️ 修復後 0 次下降，但**只有 9 個相鄰配對**。樣本小，所以
/// 單調是**前提不是保證** —— 前提壞掉時這裡回 `.unknown`，不硬算一個負數。
///
/// ### 為什麼稀疏取樣剛好夠
/// `shouldRecord` 只在數字變了才寫，而數字只在你用 Claude Code 時才變 ——
/// 每一個台階都抓到了，所以「某時刻的值」＝「最後一個不晚於它的取樣點」。
/// 稀疏不是缺陷，是這個訊號本來的形狀。
///
/// ### ⚠️ 一天切在 `resetsAt` 的那個鐘點，不是午夜
/// 邊界由 `resetsAt − 7 天` 算出（這個帳號是週六 14:00，**沒有寫死星期幾**）。
/// 換來一個自我驗證的性質：**七根相加恰好等於窗口內最後一個讀數**。
/// 〔實測 2026-09-22〕30% = 30%，差 0。對不上就是這裡算錯了。
public enum DailyUsage {

    public static let days = 7

    /// 「剛好用完不多不少」那一天該用掉多少 —— 100% 平均分給七天。
    ///
    /// ⚠️ 這條線是長條圖唯一的參考。沒有它，七根長條只能互相比較，
    /// 說不出「這樣燒下去會不會用完」——而那才是這個 app 存在的理由。
    /// 高於它就是在超支，低於它就是在存。
    public static let evenPacePercent: Double = 100.0 / Double(days)

    public static func bars(samples: [UsageSample], marks: [WatchLog.Mark],
                            resetsAt: Date, now: Date) -> [DailyUsageBar] {
        let start = resetsAt.addingTimeInterval(-Double(days) * 86400)
        // 只看這個窗口之內的 —— 重置前那個讀數屬於上一個窗口。
        let inWindow = samples
            .filter { $0.at >= start && $0.at <= resetsAt && $0.sevenDay != nil }
            .sorted { $0.at < $1.at }

        /// 最後一個不晚於 `t` 的讀數。
        ///
        /// ⚠️ **沒有取樣點時回 0，不是 nil。** 窗口重置那一刻的值定義上就是 0，
        /// 而 `shouldRecord` 只在數字變了才寫 —— 所以「還沒有任何取樣點」
        /// 精確地代表「還沒有變過」，也就是仍然是 0。
        ///
        /// 這裡一度回 nil 並在上面判成 `.unknown`。那是把兩個問題混在一起：
        /// 「值是多少」與「我們那時有沒有在看」。後者完全由心跳那一關回答，
        /// 這裡不該再猜一次。〔突變驗證抓到：把它改成 `?? 0` 一則測試都沒紅〕
        func value(at t: Date) -> Int {
            var v = 0
            for s in inWindow {
                if s.at > t { break }
                v = s.sevenDay ?? v
            }
            return v
        }

        return (0..<days).map { i in
            let a = start.addingTimeInterval(Double(i) * 86400)
            let b = a.addingTimeInterval(86400)
            guard a < now else {
                return DailyUsageBar(index: i, start: a, end: b, state: .notYet)
            }
            let isToday = b > now
            let end = min(b, now)

            let from = value(at: a)
            let to = value(at: end)
            guard to >= from else {
                // 單調的前提壞了 —— 說不知道，不要畫一根負的。
                return DailyUsageBar(index: i, start: a, end: b, state: .unknown)
            }

            // ⚠️ **「一端沒被看著」與「整天都沒在看」是兩件事。**
            //
            // 整天沒開 app：那天的用量會整批出現在「回來之後的第一個讀數」裡，
            // 於是這一天算出來是 0、隔壁那天被灌爆 —— **兩天都是錯的，而且
            // 這一天的真值我們根本不知道**。那要說 unknown。
            //
            // 只有一端沒被看著：中間看到了，數字算得出來，錯的只是跨日界那一小段的
            // 歸屬。那是 unverified —— 有數字但別完全相信。
            guard marks.contains(where: { $0.at >= a && $0.at < end }) else {
                return DailyUsageBar(index: i, start: a, end: b, state: .unknown)
            }

            // 只有**邊界**需要被看著。某一天中間短暫沒開不影響那天的總量：
            // 那段用量仍然會出現在它回來之後的第一個讀數裡。
            let startCovered = i == 0 || WatchLog.covers(a, marks: marks)
            // 今天的終點是「現在」，而我們正在跑 —— 不必再問有沒有在看。
            let endCovered = isToday || WatchLog.covers(b, marks: marks)
            let state: DailyUsageBar.State = (startCovered && endCovered)
                ? .measured(percent: to - from)
                : .unverified(percent: to - from)
            return DailyUsageBar(index: i, start: a, end: b, state: state)
        }
    }
}
