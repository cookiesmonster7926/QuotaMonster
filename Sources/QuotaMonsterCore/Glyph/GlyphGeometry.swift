import Foundation

/// 選單列標記「Parallax」的幾何 —— 純函式，沒有任何繪圖相依。
///
/// 座標系：22×22pt 畫布，圓心 (11,11)，角度用數學慣例（0° = 正右，逆時針為正）。
/// 兩條弧都顯示**剩餘**額度，從 220°（左下）順時針掃過頂端，滿額掃 260°，底部留 100° 開口。
///
/// 半徑預算（8.00pt，由內而外）：
/// ```
/// 生物       0     → 2.148
/// counter B  2.148 → 3.45   (1.30pt)
/// 內弧       3.45  → 4.85   (1.40pt)   7 天窗口
/// counter A  4.85  → 6.50   (1.65pt)
/// 外弧       6.50  → 8.00   (1.50pt)   5 小時窗口
/// ```
/// 兩個 counter 都在 1x 下限（2.0pt）以下，這是**刻意的取捨**：換來一隻 4.10pt 寬、
/// 撐得住姿態的生物。若堅持 2.0pt，生物只剩約 1.2pt，是一個斑點。2x 下兩者都清楚。
public enum GlyphGeometry {

    // ── 畫布 ───────────────────────────────────────────────────
    public static let canvas: CGFloat = 22
    public static let centre = CGPoint(x: 11, y: 11)

    // ── 弧 ─────────────────────────────────────────────────────
    public struct Band: Equatable, Sendable {
        public let centreline: CGFloat
        public let stroke: CGFloat
        public var innerEdge: CGFloat { centreline - stroke / 2 }
        public var outerEdge: CGFloat { centreline + stroke / 2 }
        /// 50% 圓點的直徑等於筆寬 —— 所以它內外都不凸出，只與兩側邊界相切。
        public var halfMarkDiameter: CGFloat { stroke }
    }

    /// 5 小時窗口。動得快，所以筆畫較重。
    public static let outerArc = Band(centreline: 7.25, stroke: 1.50)
    /// 7 天窗口。幾乎不動，筆畫較輕。
    public static let innerArc = Band(centreline: 4.15, stroke: 1.40)

    public static var counterA: CGFloat { outerArc.innerEdge - innerArc.outerEdge }
    public static var counterB: CGFloat { innerArc.innerEdge - creatureEnvelopeRadius }

    public static let gaugeStart: Double = 220
    public static let gaugeFullSweep: Double = 260
    /// 正上方。掃掠的中點，也是兩個 50% 標記的位置。
    public static let halfMarkAngle: Double = 90

    public struct Arc: Equatable, Sendable {
        public let start: Double
        public let sweep: Double
        /// 順時針掃，所以終點角度變小。
        public var end: Double { start - sweep }
        public func contains(_ angle: Double) -> Bool {
            let a = Self.normalised(angle - end)
            return a >= -0.000_001 && a <= sweep + 0.000_001
        }
        static func normalised(_ d: Double) -> Double {
            var x = d.truncatingRemainder(dividingBy: 360)
            if x < 0 { x += 360 }
            return x
        }
    }

    /// - Parameter remaining: 剩餘比例 0…1。耗盡時掃掠為 0，但暗軌仍然要畫。
    public static func gaugeArc(remaining: Double) -> Arc {
        Arc(start: gaugeStart, sweep: gaugeFullSweep * max(0, min(1, remaining)))
    }

    // ── agent 數 ───────────────────────────────────────────────

    /// agent 單位所在的軌道：底部開口兩端各內縮 27.65°，
    /// 確保它永遠碰不到弧的圓端帽。
    public static let agentRail = Arc(start: -67.65, sweep: 44.7)

    public enum AgentUnits: Equatable, Sendable {
        case none
        /// 每隻一個圓點，角度已推導。
        case discrete([Double])
        /// 四隻以上：合併成一條滿軌的橫槓。
        ///
        /// ⚠️ **精度到此為止，而且必須誠實：** 5、10、15 隻畫出來一模一樣。
        /// 十五的一元編碼在 2.0pt counter 下限要約 45pt 的弧長，底部開口只給得起 12.65pt。
        /// 這是算術問題，不是品味問題。確切數字交給下拉面板。
        case merged
    }

    public static func agentUnits(count: Int) -> AgentUnits {
        switch count {
        case ..<1: return .none
        case 1:    return .discrete([-90.0])
        case 2:    return .discrete([-103.968, -76.032])
        case 3:    return .discrete([-109.857, -90.0, -70.143])
        default:   return .merged
        }
    }

    // ── 阻塞分段 ───────────────────────────────────────────────

    /// 段與段之間的中線間距，換算後正好是 2.00pt 的墨水間隙（扣掉兩端各 0.75pt 圓帽）。
    public static let alertGapDegrees: Double = 27.936
    /// 上限。再多段就讀成虛線而不是分段（N=7 每段只剩 4.55pt，低於 5.0pt 的可讀下限）。
    public static let alertSegmentCeiling = 6

    public enum AlertRing: Equatable, Sendable {
        /// 一個阻塞不切 —— 切了會讀成「弧斷在那裡」，與量表混淆。
        case closedRing
        case segments([Arc])
    }

    public static func alertSegments(blocked: Int) -> AlertRing {
        guard blocked >= 2 else { return .closedRing }
        let n = min(blocked, alertSegmentCeiling)
        let sweep = 360.0 / Double(n) - alertGapDegrees
        // 相位由奇偶決定，讓正上方永遠是確定的地標：
        // 偶數 → 段落置中於正上方；奇數 → 間隙置中於正上方。
        let firstCentre = n.isMultiple(of: 2) ? halfMarkAngle
                                             : halfMarkAngle + 180.0 / Double(n)
        return .segments((0..<n).map { i in
            let centre = firstCentre + Double(i) * 360.0 / Double(n)
            return Arc(start: centre + sweep / 2, sweep: sweep)
        })
    }

    // ── 生物 ───────────────────────────────────────────────────

    public enum CreaturePosture: Equatable, Sendable {
        /// 完全靜止，沒有任何動畫。
        case still
        /// 起身 0.30pt，以 1.1 秒週期輕搖 ±2.5°。
        case awake
        /// 前傾 5°，以 0.62 秒週期搖 ±3.5°。
        case driving
        /// 額度耗盡，壓過一切。
        case asleep

        /// 上抬多少 pt。
        public var rise: CGFloat {
            switch self {
            case .still, .asleep: return 0
            case .awake, .driving: return 0.30
            }
        }
        /// 前傾幾度（負值為前傾）。
        public var leanDegrees: CGFloat {
            switch self {
            case .driving: return -5
            default: return 0
            }
        }
        /// 垂直壓縮比例，錨在腳下。
        public var squashY: CGFloat {
            switch self {
            case .asleep: return 0.86
            default: return 1.0
            }
        }
        public var isTransformed: Bool {
            rise != 0 || leanDegrees != 0 || squashY != 1.0
        }
    }

    public static let creatureEnvelopeRadius: CGFloat = 2.148
    /// 前傾 5° 後外緣的最大半徑。6° 就會吃進 counter B。
    public static let leanedEnvelopeRadius: CGFloat = 2.263

    public static func creaturePosture(agents: Int, exhausted: Bool = false) -> CreaturePosture {
        if exhausted { return .asleep }
        switch agents {
        case ..<1: return .still
        case 1...3: return .awake
        default:   return .driving
        }
    }
}
