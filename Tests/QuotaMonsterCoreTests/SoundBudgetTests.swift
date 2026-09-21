import Foundation
import Testing
@testable import QuotaMonsterCore

/// 視窗算術自己一組測試。
///
/// **為什麼不透過引擎間接測：** 邊界（`<` 還是 `<=`）、時鐘倒退、陣列會不會
/// 長大這三件事，透過造四個假 workflow 去測的話，紅燈沒辦法告訴你是哪一件壞了。
@Suite("SoundBudget — 一小時幾聲")
struct SoundBudgetTests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    @Test("視窗內只放行 capacity 次")
    func capacityIsEnforced() {
        var b = SoundBudget()
        for i in 0..<SoundBudget.capacity {
            let granted = b.consumeIfPossible(at: at(Double(i)))
            #expect(granted)
        }
        let refused = b.consumeIfPossible(at: at(Double(SoundBudget.capacity)))
        #expect(!refused)
    }

    @Test("視窗邊界是嚴格小於 —— 恰好第 3600 秒的那一筆已經不算在窗裡")
    func windowBoundaryIsExclusive() {
        var b = SoundBudget()
        for i in 0..<SoundBudget.capacity { _ = b.consumeIfPossible(at: at(Double(i))) }
        // 第一筆在 t=0。t=3599 時它還在窗裡（3599 - 0 < 3600），所以還是滿的。
        let insideWindow = b.consumeIfPossible(at: at(SoundBudget.window - 1))
        #expect(!insideWindow)
        // t=3600 時它剛好出窗（3600 - 0 不小於 3600），空出一格。
        let atBoundary = b.consumeIfPossible(at: at(SoundBudget.window))
        #expect(atBoundary)
    }

    @Test("扣不到款就不可以留下痕跡 —— 被擋下的那一次不進帳")
    func refusedConsumeRecordsNothing() {
        // 「先 append 再檢查 count」的實作會讓一次被擋下的嘗試把回血時間
        // 整整往後推一小時。
        var b = SoundBudget()
        for i in 0..<SoundBudget.capacity { _ = b.consumeIfPossible(at: at(Double(i))) }
        let refused = b.consumeIfPossible(at: at(10))
        #expect(!refused)
        #expect(b.recorded == SoundBudget.capacity)
    }

    @Test("帳本不會無限長大 —— 連續二十次之後記得的筆數仍然不超過 capacity")
    func ledgerStaysBounded() {
        // 這是 `lastEmitted` 那段「一定要清」的同一種洩漏。
        var b = SoundBudget()
        for i in 0..<20 { _ = b.consumeIfPossible(at: at(Double(i))) }
        #expect(b.recorded <= SoundBudget.capacity)
    }

    @Test("剩餘額度會自己隨時間回血 —— 一小時後問它就是滿的")
    func remainingHealsWithTime() {
        // 回傳 `stamps.count` 的實作會在沒有事件的時候一直說「剩 0」，
        // 而一份說謊的診斷比沒有診斷更糟。
        var b = SoundBudget()
        for i in 0..<SoundBudget.capacity { _ = b.consumeIfPossible(at: at(Double(i))) }
        #expect(b.remaining(at: at(10)) == 0)
        #expect(b.remaining(at: at(SoundBudget.window + 100)) == SoundBudget.capacity)
    }

    @Test("問一下剩多少不可以改變任何東西")
    func askingChangesNothing() {
        var b = SoundBudget()
        _ = b.consumeIfPossible(at: at(0))
        let before = b
        _ = b.remaining(at: at(SoundBudget.window + 100))
        #expect(b == before)
    }

    @Test("時鐘往回跳不會把預算清空 —— 往回跳十分鐘之後仍然擋著")
    func backwardClockDoesNotRefill() {
        // 用 abs() 或把負數當成過期的實作會在這裡紅，而那個方向是多發。
        var b = SoundBudget()
        for i in 0..<SoundBudget.capacity { _ = b.consumeIfPossible(at: at(Double(i))) }
        let refused = b.consumeIfPossible(at: at(-600))
        #expect(!refused)
    }
}
