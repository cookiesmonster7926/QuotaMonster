import Foundation

/// 時間序列上的一個點。
public struct BurnPoint: Equatable, Sendable {
    public let at: Date
    public let value: Int

    public init(at: Date, value: Int) {
        self.at = at
        self.value = value
    }
}

/// 兩兩斜率的分佈。
public struct Slopes: Equatable, Sendable {
    public let median: Double
    /// ⚠️ **這是兩兩斜率的四分位距，不是信賴區間。**
    /// 在一段局部線性的突發上它會窄得離譜（實測 7 個點 14 分鐘，只有 ±8%），
    /// 所以它只被用來做**一件事**：`lowerQuartile <= 0` 就拒絕。
    /// 那是一個符號檢定，是四分位距真的支撐得起的東西。
    public let lowerQuartile: Double
    public let upperQuartile: Double
    public let pairCount: Int
}

public struct BurnEstimate: Equatable, Sendable {
    public let percentPerHour: Double
    public let lowerPercentPerHour: Double
    public let upperPercentPerHour: Double
    public let sampleCount: Int
    public let pairCount: Int
    public let span: TimeInterval
    public let latestAt: Date
}

/// 為什麼說不出話。
///
/// 具名而不是 `nil`：tooltip 與 `--dump` 要印得出理由。
/// 這個 repo 已經在 `PanelView.freshnessText` 做過同一件事 ——
/// 說出讀數為什麼舊，而不只是說它舊。
public enum BurnRefusal: Equatable, Sendable {
    case noSamples
    /// **這個窗口刻意不看最近速率。** 7 天窗口用的是它自己的均速，因為那個
    /// 分母裡已經包含了你睡覺的時間。說成「歷史還是空的」是一句小謊 ——
    /// 它會讓人以為再等一陣子就會有箭頭，而那永遠不會發生。
    case notUsedForThisWindow
    case tooFewPointsInRun(Int)
    case spanTooShort(TimeInterval)
    /// 最新的點離現在太遠了。二十分鐘前的節奏不是「最近」。
    case staleTail(TimeInterval)
    case tooFewPairs(Int)
    /// 兩兩斜率的第一四分位數 ≤ 0 —— 分不出「在燒」與「持平」。
    case rateNotDistinguishableFromFlat(lowerQuartile: Double)
    /// 中位數是負的。**絕不夾到 0** —— 夾了就等於把一個明顯的資料問題藏起來。
    case negativeRate(Double)
}

public enum BurnOutcome: Equatable, Sendable {
    case estimate(BurnEstimate)
    case refused(BurnRefusal)

    public var value: BurnEstimate? {
        if case .estimate(let e) = self { return e }
        return nil
    }
}

/// 從時間序列估出「最近燒得多快」。
///
/// ### 為什麼是 Theil–Sen 而不是線性回歸
/// 實測 17:46:49–17:47:34 的五個點是 `27, 26, 27, 26, 27`（兩個來源在邊界上
/// 差 1 個百分點）。**最小平方法在這五個點上的斜率是 −8.12 pp/h** ——
/// 一個會印在面板上的負燒量。中位數對這種對稱噪音免疫。
///
/// ### 但抗噪能力其實不是來自中位數
/// 拿掉最小配對間隔，同一組點的 Theil–Sen 中位數是 0、四分位距是 **±64.29 pp/h**。
/// 真正擋住噪音的是 `minimumPairInterval` —— 只用**間隔夠遠**的兩點算斜率，
/// ±1 的跳動除以一個夠大的 Δt 就變得微不足道。那個常數是全部的抗噪能力。
public enum UsageBurn {

    /// 超過這個間隔就切斷，不橋接。
    ///
    /// 實測：活動期**內**最大間隔 817 秒，活動期**之間**最小間隔 2646 秒 ——
    /// 1200 落在這道空帶的正中央。空隙的意思是「數字沒變」**或**「app 沒開」，
    /// 檔案裡分不出來，所以不可以把它當成零燒量橋接過去。
    public static let maximumGap: TimeInterval = 1200

    /// 兩點要隔多遠才算得出一條斜率。
    ///
    /// 實測最寬的來源振盪簇是 **45 秒**（27,26,27,26,27），180 是它的四倍。
    public static let fiveHourMinimumPairInterval: TimeInterval = 180
    public static let fiveHourMinimumSpan: TimeInterval = 600
    public static let minimumPoints = 4
    public static let minimumPairs = 6
    /// Theil–Sen 是 O(n²)。三秒輪詢下這個上限永遠碰不到，但它必須存在。
    public static let maximumPoints = 240

    // ── 取出「最近這一段」 ──────────────────────────────────────

    /// - Parameter windowStart: `resetsAt − 窗口長度`。
    ///   **鋸齒靠這個在結構上擋掉，不是靠偵測重置** ——
    ///   「值下降就是重置」會在 27→26 那種來源振盪上誤判。
    static func recentRun(_ samples: [UsageSample], window: KeyPath<UsageSample, Int?>,
                          windowStart: Date, now: Date) -> [BurnPoint] {
        let inWindow = samples
            .filter { $0.at >= windowStart && $0.at <= now }
            .sorted { $0.at < $1.at }

        var run: [BurnPoint] = []
        var nextAt: Date?
        // 從最新往回走，遇到過大的間隔就停。
        for s in inWindow.reversed() {
            if let nextAt, nextAt.timeIntervalSince(s.at) > maximumGap { break }
            nextAt = s.at
            // null 是洞：跳過它，但**不要**讓它切斷序列 ——
            // 它只代表那一刻讀不到，不代表重置，也不代表 0。
            if let v = s[keyPath: window] { run.append(BurnPoint(at: s.at, value: v)) }
        }
        return Array(run.reversed().suffix(maximumPoints))
    }

    // ── Theil–Sen ─────────────────────────────────────────────

    static func theilSen(_ points: [BurnPoint],
                         minimumPairInterval: TimeInterval) -> Slopes? {
        var slopes: [Double] = []
        for i in points.indices {
            for j in points.index(after: i)..<points.endIndex {
                let dt = points[j].at.timeIntervalSince(points[i].at)
                guard dt >= minimumPairInterval, dt > 0 else { continue }
                slopes.append(Double(points[j].value - points[i].value) / (dt / 3600))
            }
        }
        guard !slopes.isEmpty else { return nil }
        slopes.sort()
        return Slopes(median: quantile(slopes, 0.5),
                      lowerQuartile: quantile(slopes, 0.25),
                      upperQuartile: quantile(slopes, 0.75),
                      pairCount: slopes.count)
    }

    /// 線性內插的分位數。定義要寫死在這裡 —— 換一個定義，
    /// 上面那些對著真實資料釘死的期望值就全部要重算。
    static func quantile(_ sorted: [Double], _ p: Double) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let h = Double(sorted.count - 1) * p
        let lo = Int(h)
        let hi = min(lo + 1, sorted.count - 1)
        return sorted[lo] + (h - Double(lo)) * (sorted[hi] - sorted[lo])
    }

    // ── 組起來 ─────────────────────────────────────────────────

    public static func fiveHour(_ samples: [UsageSample], windowStart: Date,
                                now: Date) -> BurnOutcome {
        estimate(samples, window: \.fiveHour, windowStart: windowStart, now: now,
                 minimumPairInterval: fiveHourMinimumPairInterval,
                 minimumSpan: fiveHourMinimumSpan)
    }

    static func estimate(_ samples: [UsageSample], window: KeyPath<UsageSample, Int?>,
                         windowStart: Date, now: Date,
                         minimumPairInterval: TimeInterval,
                         minimumSpan: TimeInterval) -> BurnOutcome {
        let run = recentRun(samples, window: window, windowStart: windowStart, now: now)
        guard let first = run.first, let last = run.last else { return .refused(.noSamples) }

        let staleness = now.timeIntervalSince(last.at)
        guard staleness <= maximumGap else { return .refused(.staleTail(staleness)) }
        guard run.count >= minimumPoints else { return .refused(.tooFewPointsInRun(run.count)) }

        let span = last.at.timeIntervalSince(first.at)
        guard span >= minimumSpan else { return .refused(.spanTooShort(span)) }

        guard let s = theilSen(run, minimumPairInterval: minimumPairInterval) else {
            return .refused(.tooFewPairs(0))
        }
        guard s.pairCount >= minimumPairs else { return .refused(.tooFewPairs(s.pairCount)) }
        guard s.median >= 0 else { return .refused(.negativeRate(s.median)) }
        guard s.lowerQuartile > 0 else {
            return .refused(.rateNotDistinguishableFromFlat(lowerQuartile: s.lowerQuartile))
        }

        return .estimate(BurnEstimate(percentPerHour: s.median,
                                      lowerPercentPerHour: s.lowerQuartile,
                                      upperPercentPerHour: s.upperQuartile,
                                      sampleCount: run.count, pairCount: s.pairCount,
                                      span: span, latestAt: last.at))
    }
}
