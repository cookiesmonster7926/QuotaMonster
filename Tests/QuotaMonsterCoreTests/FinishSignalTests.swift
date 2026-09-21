import Testing
import Foundation
@testable import QuotaMonsterCore

@Suite("FinishGlow — 丁香紫現在該多濃")
struct FinishGlowTests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func finish(_ id: String, _ finishedAt: TimeInterval, ranFor: TimeInterval?) -> SessionFinish {
        SessionFinish(sessionId: id, finishedAt: at(finishedAt), ranFor: ranFor)
    }

    @Test("三段：滿色到 180 秒、退色到 600 秒、之後沒了")
    func threeDiscreteSteps() {
        #expect(FinishGlow.at(finishedAt: at(0), now: at(0)) == .fresh)
        #expect(FinishGlow.at(finishedAt: at(0), now: at(179)) == .fresh)
        #expect(FinishGlow.at(finishedAt: at(0), now: at(180)) == .faded)
        #expect(FinishGlow.at(finishedAt: at(0), now: at(599)) == .faded)
        #expect(FinishGlow.at(finishedAt: at(0), now: at(600)) == .none)
    }

    @Test("沒有完成時刻就是不亮 —— nil 不是「剛完成」")
    func nilIsNone() {
        #expect(FinishGlow.at(finishedAt: nil, now: at(0)) == .none)
    }

    @Test("時鐘往回跳仍然算剛完成 —— 負的經過時間不可以變成「已經過期」")
    func negativeElapsedIsFresh() {
        // 用 abs() 或讓負數掉進 >= goneSeconds 分支的實作會在這裡紅，
        // 而那個方向是「訊號憑空消失」。
        #expect(FinishGlow.at(finishedAt: at(10), now: at(0)) == .fresh)
    }

    @Test("選單列取最新的那一個 —— 不是字典序、不是陣列第一個")
    func menuBarTakesTheLatest() {
        // latestPhase 那一課的學費：陣列順序與字典序都不是時間。
        let old = finish("zzz", 0, ranFor: 1200)
        let new = finish("aaa", 500, ranFor: 1200)
        #expect(FinishGlow.menuBar([old, new], now: at(560)) == .fresh)   // 新的那個才 60 秒
        #expect(FinishGlow.menuBar([new, old], now: at(560)) == .fresh)   // 順序不影響
    }

    @Test("跑不夠久的不上選單列 —— 但那是選單列的事，標記照樣存在")
    func shortRunsDoNotReachTheMenuBar() {
        #expect(FinishGlow.menuBar([finish("a", 0, ranFor: 599)], now: at(10)) == .none)
        #expect(FinishGlow.menuBar([finish("a", 0, ranFor: 600)], now: at(10)) == .fresh)
    }

    @Test("算不出跑多久的不上選單列 —— nil 不是 0，也不是「一定夠久」")
    func unknownRunDoesNotReachTheMenuBar() {
        // 〔實測〕約六分之一的完成 ranFor 是 nil。把 nil 當成 0 會全部擋掉、
        // 當成無限大會全部放行 —— 兩個都是憑空造一個量測。這裡選「不亮」，
        // 因為亮起來的那一下是在主張「這一輪跑很久」。
        #expect(FinishGlow.menuBar([finish("a", 0, ranFor: nil)], now: at(10)) == .none)
    }

    @Test("最新的那個不夠久、舊的夠久 —— 看的是最新那個")
    func latestWinsEvenIfItIsTooShort() {
        // 抓「先濾掉不夠久的、再取最新」與「先取最新、再看夠不夠久」的差別。
        // 選後者：選單列講的是「剛剛那件事」，不是「最近一件夠格的事」。
        let longOld = finish("a", 0, ranFor: 3600)
        let shortNew = finish("b", 300, ranFor: 10)
        #expect(FinishGlow.menuBar([longOld, shortNew], now: at(310)) == .none)
    }

    @Test("沒有任何完成 —— 不亮")
    func emptyIsNone() {
        #expect(FinishGlow.menuBar([], now: at(0)) == .none)
    }
}

@Suite("FinishBlinkController — 什麼時候眨那一次眼")
struct FinishBlinkControllerTests {

    @Test("第一次觀測不眨 —— app 剛啟動就看到 fresh 不算我們見證的轉換")
    func firstObservationDoesNotBlink() {
        // 形狀照抄 NotificationEngine 的 seeded。少了它，make_app.sh 每次重啟
        // 都會對著一個十分鐘前的完成眨一次眼。
        var c = FinishBlinkController()
        #expect(c.update(glow: .fresh) == false)
    }

    @Test("none → fresh 眨一次，而且只有那一次")
    func blinksOnceOnArrival() {
        var c = FinishBlinkController()
        #expect(c.update(glow: .none) == false)
        #expect(c.update(glow: .fresh) == true)
        #expect(c.update(glow: .fresh) == false)
    }

    @Test("fresh → faded → none 不眨 —— 衰退不是新消息")
    func decayDoesNotBlink() {
        var c = FinishBlinkController()
        _ = c.update(glow: .none)
        _ = c.update(glow: .fresh)
        #expect(c.update(glow: .faded) == false)
        #expect(c.update(glow: .none) == false)
    }

    @Test("下一次完成要再眨一次")
    func blinksAgainForTheNextFinish() {
        var c = FinishBlinkController()
        _ = c.update(glow: .none)
        _ = c.update(glow: .fresh)
        _ = c.update(glow: .none)
        #expect(c.update(glow: .fresh) == true)
    }

    @Test("faded → fresh 也要眨 —— 那是另一個 session 剛完成")
    func fadedToFreshBlinks() {
        // 舊的還在退色時來了一個新的完成。抓「只認 none → fresh」的實作。
        var c = FinishBlinkController()
        _ = c.update(glow: .none)
        _ = c.update(glow: .faded)
        #expect(c.update(glow: .fresh) == true)
    }
}

@Suite("FinishCaption — 面板那一列的三個欄位")
struct FinishCaptionTests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test("90 秒內是「剛完成」，之後是「N 分前完成」")
    func label() {
        #expect(FinishCaption.label(finishedAt: at(0), now: at(89)) == "剛完成")
        #expect(FinishCaption.label(finishedAt: at(0), now: at(90)) == "2 分前完成")
        #expect(FinishCaption.label(finishedAt: at(0), now: at(300)) == "5 分前完成")
    }

    @Test("跑多久的格式有小時分支 —— 3664 秒不可以印成 61m 04s")
    func ranForHasAnHourBranch() {
        // 抄 TraceAlerts.elapsed 的實作會在這裡紅（它沒有小時分支）。
        #expect(FinishCaption.ranFor(45) == "跑了 45s")
        #expect(FinishCaption.ranFor(724) == "跑了 12m 04s")
        #expect(FinishCaption.ranFor(3664) == "跑了 1h 01m")
    }

    @Test("算不出來就是 nil —— nil 進 nil 出，不可以變成「跑了 0m 00s」")
    func unknownRanForStaysNil() {
        #expect(FinishCaption.ranFor(nil) == nil)
    }

    @Test("鮮度線 10 分鐘內排空")
    func drainFraction() {
        #expect(FinishCaption.drainFraction(finishedAt: at(0), now: at(0)) == 1)
        #expect(FinishCaption.drainFraction(finishedAt: at(0), now: at(300)) == 0.5)
        #expect(FinishCaption.drainFraction(finishedAt: at(0), now: at(600)) == 0)
        #expect(FinishCaption.drainFraction(finishedAt: at(0), now: at(9999)) == 0)
    }

    @Test("又動起來了就當場收掉 —— 而且證據是 transcript 寫入，不是 session 的 status")
    func writingPrunesTheMark() {
        // ⚠️ 這一則釘住的是整個 Stage 8 最致命的那個誤用：拿 LiveSession.isWorking
        // 當「又動起來了」。status 是黏著的（計畫書自己量過「回合結束後七分鐘
        // 一直回報 shell」），照那樣寫標記會在產生後的第一拍就被清掉 ——
        // 丁香紫一次都不會亮，而且所有單元測試都會綠。
        let marks = ["a": SessionFinish(sessionId: "a", finishedAt: at(0), ranFor: 700),
                     "b": SessionFinish(sessionId: "b", finishedAt: at(0), ranFor: 700)]
        let kept = FinishCaption.prune(marks, wrote: ["a"], now: at(10))
        #expect(Set(kept.keys) == ["b"])
    }

    @Test("超過壽命的自己消失")
    func expiredMarksAreDropped() {
        let marks = ["a": SessionFinish(sessionId: "a", finishedAt: at(0), ranFor: 700)]
        #expect(FinishCaption.prune(marks, wrote: [], now: at(599)).count == 1)
        #expect(FinishCaption.prune(marks, wrote: [], now: at(600)).isEmpty)
    }
}

@Suite("GlyphState — 生物身上那一點丁香紫")
struct GlyphStateFinishTests {

    func state(blocked: Int = 0, glow: FinishGlow, freshness: Freshness = .live,
               fiveHour: Double? = 0.8) -> GlyphState {
        GlyphState(fiveHourRemaining: fiveHour, sevenDayRemaining: nil,
                   runningAgents: 0, blockedSessions: blocked,
                   exhausted: false, freshness: freshness, finishGlow: glow)
    }

    @Test("有人在等你的時候完成訊號整批丟掉 —— 琥珀與丁香在型別上不可能同時出現")
    func alertingSwallowsTheGlow() {
        #expect(state(blocked: 1, glow: .fresh).creatureGlow == .none)
        #expect(state(blocked: 0, glow: .fresh).creatureGlow == .fresh)
    }

    @Test("丟掉不是排隊 —— 警示結束之後不會補一次眨眼")
    func swallowedGlowIsNotQueued() {
        // 這一則釘的是「blocked 降回 0 的那一拍不可以憑空冒出一次眨眼」。
        // creatureGlow 只是把 finishGlow 蓋掉，原始欄位仍然照時間衰退 ——
        // 所以眨眼的判斷要餵**原始欄位**（見 StatusItemController），
        // 餵 creatureGlow 的話 .none → .fresh 會在解除警示那一拍成立。
        #expect(state(blocked: 1, glow: .fresh).finishGlow == .fresh)
    }

    @Test("⚠️ 染了丁香紫就不可以走 template —— template 只看 alpha，顏色會安靜地消失")
    func glowingCreatureIsNotTemplate() {
        // 這是整份改動裡**唯一**有單元測試守著的繪圖陷阱。
        // 沒有這一條，丁香紫在「沒有額度讀數、也沒人在等你」的那一格會變成墨色，
        // 而且不會有任何錯誤 —— 它只是不見了。
        let noQuota = state(glow: .fresh, fiveHour: nil)
        #expect(noQuota.quotaTier == nil)
        #expect(noQuota.usesTemplateRendering == false)
        #expect(state(glow: .none, fiveHour: nil).usesTemplateRendering == true)
    }

    @Test("丁香紫蓋過過期讀數的降調 —— 兩套衰減疊在一起沒有人讀得出來")
    func glowOverridesTheExpiredDimming() {
        #expect(state(glow: .faded, freshness: .expired).creatureFill == .glow(.faded))
        #expect(state(glow: .none, freshness: .expired).creatureFill == .ink(alpha: 0.45))
        #expect(state(glow: .none).creatureFill == .ink(alpha: 1.0))
    }

    @Test("with(finishGlow:) 只換那一格，其餘照舊")
    func withFinishGlowKeepsEverythingElse() {
        let base = state(blocked: 2, glow: .none)
        let lit = base.with(finishGlow: .fresh)
        #expect(lit.finishGlow == .fresh)
        #expect(lit.blockedSessions == 2)
        #expect(lit.fiveHourRemaining == base.fiveHourRemaining)
    }
}
