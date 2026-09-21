import Testing
import Foundation
@testable import QuotaMonsterCore

/// 「每日均量」是唯一不需要歷史資料就算得出來的速率指標：
/// 窗口起點 = `resets_at − 窗口長度`，已經過的天數 = now − 起點。
///
/// 值得寫測試的理由：窗口剛重置時「已過天數」接近 0，除下去會得到荒謬的大數字，
/// 而那個數字看起來很像真的。
@Suite("UsagePace")
struct UsagePaceTests {

    let now = Fixture.now
    let week: TimeInterval = 7 * 86400

    @Test("用了 45%、還剩 1 天 21 小時，日均約 8.8%")
    func computesDailyAverage() throws {
        let reset = now.addingTimeInterval(1 * 86400 + 21 * 3600)
        let avg = try #require(UsagePace.dailyAverage(percent: 45, resetsAt: reset,
                                                      windowLength: week, now: now))
        #expect(abs(avg - 8.78) < 0.05)
    }

    @Test("窗口才剛開始時回 nil —— 除以接近 0 會得到一個看起來很真的荒謬數字")
    func tooEarlyYieldsNil() {
        let reset = now.addingTimeInterval(week - 3600)          // 才過一小時
        #expect(UsagePace.dailyAverage(percent: 3, resetsAt: reset,
                                       windowLength: week, now: now) == nil)
    }

    @Test("重置時間已經過去時回 nil")
    func pastResetYieldsNil() {
        #expect(UsagePace.dailyAverage(percent: 45, resetsAt: now.addingTimeInterval(-60),
                                       windowLength: week, now: now) == nil)
    }

    @Test("完全沒用時日均是 0，不是 nil")
    func zeroUsageIsZeroNotNil() throws {
        let reset = now.addingTimeInterval(2 * 86400)
        let avg = try #require(UsagePace.dailyAverage(percent: 0, resetsAt: reset,
                                                      windowLength: week, now: now))
        #expect(avg == 0)
    }

    @Test("resets_at 比一個窗口長度還遠時回 nil —— 那是壞掉的時間戳")
    func absurdResetYieldsNil() {
        #expect(UsagePace.dailyAverage(percent: 45, resetsAt: now.addingTimeInterval(week * 3),
                                       windowLength: week, now: now) == nil)
    }
}
