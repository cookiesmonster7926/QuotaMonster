import Testing
import Foundation
@testable import QuotaMonsterCore

/// 警示呼吸是**整個 app 裡唯一會動的東西**。
///
/// 設計上的核心主張：一個永遠在動的選單列，一週之內就會變成壁紙，
/// 然後那個唯一重要的時刻就被錯過了。所以動作必須有上限而且必須終止。
///
/// 契約：每次阻塞事件最多 4 次爆發 × 6 秒 = **24 秒的動作，然後永遠靜止**。
@Suite("Breath — 曲線")
struct BreathCurveTests {

    @Test("12 格取樣，首尾相接沒有接縫")
    func twelveFramesLoopSeamlessly() {
        #expect(Breath.frameCount == 12)
        #expect(abs(Breath.opacity(atFrame: 0) - Breath.opacity(atFrame: 12)) < 0.0001)
    }

    @Test("起點與終點都是全亮 —— 動畫的終點值就是物件的靜止值")
    func startsAndEndsFullyOpaque() {
        // 這是最重要的一條結構性保證：物件不可能停在一個還在喊的狀態。
        #expect(abs(Breath.opacity(atFrame: 0) - 1.0) < 0.0001)
    }

    @Test("中點是最暗的 0.45")
    func midpointIsDimmest() {
        #expect(abs(Breath.opacity(atFrame: 6) - 0.45) < 0.0001)
    }

    @Test("曲線對稱")
    func curveIsSymmetric() {
        for i in 1..<6 {
            #expect(abs(Breath.opacity(atFrame: i) - Breath.opacity(atFrame: 12 - i)) < 0.0001)
        }
    }

    @Test("永遠落在 0.45 到 1.0 之間")
    func staysWithinBounds() {
        for i in 0...12 {
            let o = Breath.opacity(atFrame: i)
            #expect(o >= 0.45 - 0.0001 && o <= 1.0 + 0.0001)
        }
    }

    @Test("每次爆發 6 秒，上限 4 次，總動作不超過 24 秒")
    func motionBudgetIsCapped() {
        #expect(Breath.burstDuration == 6.0)
        #expect(Breath.maxBursts == 4)
        #expect(Breath.burstDuration * Double(Breath.maxBursts) == 24.0)
    }
}

@Suite("Breath — 重新觸發排程")
struct BreathScheduleTests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test("沒有人在等你時不會動")
    func noBlockedMeansNoMotion() {
        var c = BreathController()
        #expect(c.update(blockedCount: 0, now: t0) == false)
    }

    @Test("第一個阻塞出現時觸發一次")
    func firstBlockFires() {
        var c = BreathController()
        #expect(c.update(blockedCount: 1, now: t0) == true)
    }

    @Test("同樣的阻塞數持續存在不會一直重播")
    func steadyStateDoesNotRepeat() {
        var c = BreathController()
        _ = c.update(blockedCount: 1, now: t0)
        #expect(c.update(blockedCount: 1, now: at(1)) == false)
        #expect(c.update(blockedCount: 1, now: at(20)) == false)
    }

    @Test("阻塞數變多要重新觸發 —— 多一個人在等你是新消息")
    func increaseRetriggers() {
        var c = BreathController()
        _ = c.update(blockedCount: 1, now: t0)
        #expect(c.update(blockedCount: 2, now: at(10)) == true)
    }

    @Test("阻塞數變少不觸發 —— 那是好消息，不需要喊")
    func decreaseDoesNotRetrigger() {
        var c = BreathController()
        _ = c.update(blockedCount: 2, now: t0)
        #expect(c.update(blockedCount: 1, now: at(10)) == false)
    }

    @Test("T+60 秒重新觸發一次")
    func reArmsAtSixtySeconds() {
        var c = BreathController()
        _ = c.update(blockedCount: 1, now: t0)
        #expect(c.update(blockedCount: 1, now: at(59)) == false)
        #expect(c.update(blockedCount: 1, now: at(61)) == true)
        #expect(c.update(blockedCount: 1, now: at(62)) == false)   // 只一次
    }

    @Test("T+300 秒再重新觸發一次，之後永遠不再動")
    func reArmsAtFiveMinutesThenNeverAgain() {
        var c = BreathController()
        _ = c.update(blockedCount: 1, now: t0)
        _ = c.update(blockedCount: 1, now: at(61))
        #expect(c.update(blockedCount: 1, now: at(301)) == true)
        #expect(c.update(blockedCount: 1, now: at(600)) == false)
        #expect(c.update(blockedCount: 1, now: at(3600)) == false)
    }

    @Test("上限就是 4 次，即使阻塞數一直增加")
    func hardCapOfFourBursts() {
        var c = BreathController()
        var fired = 0
        for n in 1...10 where c.update(blockedCount: n, now: at(Double(n))) { fired += 1 }
        #expect(fired == Breath.maxBursts)
    }

    @Test("阻塞解除後整組重置，下一次事件重新開始計算")
    func clearingResetsTheBudget() {
        var c = BreathController()
        for n in 1...6 { _ = c.update(blockedCount: n, now: at(Double(n))) }
        #expect(c.update(blockedCount: 7, now: at(20)) == false)   // 已經用完
        _ = c.update(blockedCount: 0, now: at(30))                 // 解除
        #expect(c.update(blockedCount: 1, now: at(40)) == true)    // 新事件，重新開始
    }

    @Test("減少動態效果時永遠不動，資訊靠靜態的琥珀色與分段承載")
    func reduceMotionNeverAnimates() {
        var c = BreathController(reduceMotion: true)
        #expect(c.update(blockedCount: 1, now: t0) == false)
        #expect(c.update(blockedCount: 5, now: at(10)) == false)
    }

    @Test("低電量模式時不動，連 frame 都不該建立")
    func lowPowerNeverAnimates() {
        var c = BreathController(lowPower: true)
        #expect(c.update(blockedCount: 1, now: t0) == false)
    }
}
