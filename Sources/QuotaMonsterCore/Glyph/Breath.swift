import Foundation

/// 警示狀態的呼吸動畫契約。
///
/// **這是整個 app 裡唯一會動的東西。** 理由是一條設計主張：
/// 一個永遠在動的選單列，一週之內就會變成壁紙，然後那個唯一重要的時刻會被錯過。
/// 所以動作有硬上限，而且**動畫的終點值就是物件的靜止值** ——
/// 物件在結構上不可能停在一個還在喊的狀態。
public enum Breath {

    /// 一個完整週期：全亮 → 最暗 → 全亮。
    public static let cycleDuration: TimeInterval = 1.5
    /// 一次爆發跑幾個週期。
    public static let cyclesPerBurst = 4
    /// 一次爆發的長度。
    public static let burstDuration: TimeInterval = cycleDuration * Double(cyclesPerBurst)
    /// 每次阻塞事件最多幾次爆發。4 × 6 秒 = 最多 24 秒的動作。
    public static let maxBursts = 4

    /// 預先渲染的張數。12 張在 12Hz 下正好是一個週期。
    public static let frameCount = 12
    public static let frameRate: Double = Double(frameCount) / cycleDuration

    public static let maxOpacity: Double = 1.0
    public static let minOpacity: Double = 0.45

    /// 第 i 格的不透明度。
    ///
    /// 用正弦 ease-in-out（`0.5 - 0.5·cos(πu)`）而不是解三次貝茲，
    /// 兩者在視覺上的差異遠小於 12 格取樣的量化誤差，而且正弦天生對稱、
    /// 首尾相接沒有接縫 —— frame 0 與 frame 12 完全相同。
    public static func opacity(atFrame i: Int) -> Double {
        let p = Double(i % frameCount) / Double(frameCount)
        let half = p < 0.5 ? p / 0.5 : (p - 0.5) / 0.5
        let eased = 0.5 - 0.5 * cos(.pi * half)
        return p < 0.5
            ? maxOpacity + (minOpacity - maxOpacity) * eased   // 亮 → 暗
            : minOpacity + (maxOpacity - minOpacity) * eased   // 暗 → 亮
    }
}

/// 決定「現在該不該開始一次呼吸」。純狀態機，沒有計時器也沒有繪圖相依。
///
/// 重新觸發的規則恰好三個，之後永遠不再動：
///   1. 阻塞數**增加**時（多一個人在等你是新消息）
///   2. 事件發生後 60 秒
///   3. 事件發生後 300 秒
/// 加上事件本身那一次，總共最多 4 次。阻塞完全解除才會重置預算。
public struct BreathController: Equatable, Sendable {

    /// 排程性的重新觸發時點（自事件起算）。
    public static let scheduledDelays: [TimeInterval] = [60, 300]

    public let reduceMotion: Bool
    public let lowPower: Bool

    private(set) public var onsetAt: Date?
    private(set) public var burstsFired = 0
    private(set) public var lastBlockedCount = 0
    private var firedDelays: Set<Int> = []

    public init(reduceMotion: Bool = false, lowPower: Bool = false) {
        self.reduceMotion = reduceMotion
        self.lowPower = lowPower
    }

    /// 每次資料刷新都呼叫一次。
    /// - Returns: true 代表現在應該開始一次 6 秒的呼吸。
    public mutating func update(blockedCount: Int, now: Date) -> Bool {
        defer { lastBlockedCount = blockedCount }

        // 解除 → 整組重置。下一次事件重新拿到完整的 4 次預算。
        guard blockedCount > 0 else {
            onsetAt = nil; burstsFired = 0; firedDelays = []
            return false
        }

        // 這兩種情況下連 frame 都不該建立。
        // 資訊完全靠靜態的琥珀色與外圈分段承載，不會因此遺失。
        guard !reduceMotion, !lowPower else {
            if onsetAt == nil { onsetAt = now }
            return false
        }

        guard burstsFired < Breath.maxBursts else { return false }

        // 1) 事件開始
        if onsetAt == nil {
            onsetAt = now; burstsFired += 1
            return true
        }
        // 2) 阻塞數增加。變少不觸發 —— 那是好消息，不需要喊。
        if blockedCount > lastBlockedCount {
            burstsFired += 1
            return true
        }
        // 3) 排程性的兩次
        if let onset = onsetAt {
            let elapsed = now.timeIntervalSince(onset)
            for (i, delay) in Self.scheduledDelays.enumerated()
            where elapsed >= delay && !firedDelays.contains(i) {
                firedDelays.insert(i)
                burstsFired += 1
                return true
            }
        }
        return false
    }
}
