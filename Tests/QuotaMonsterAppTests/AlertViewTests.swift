import Testing
import Foundation
@testable import QuotaMonsterApp

/// 浮窗上那個往上數的秒數。
@Suite("AlertView — 等了多久")
@MainActor
struct AlertViewTests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)

    @Test("格式有小時分支 —— 3664 秒不可以印成 61m 04s")
    func elapsedHasAnHourBranch() {
        // 這個 repo 已經為同一類 bug 記過一次：`TraceAlerts.elapsed`
        // 沒有小時分支，所以它印得出「61m 04s」。這一則守住浮窗這一份。
        // ⚠️〔2026-09-19 查到、刻意沒修〕`TraceFinishes.elapsed` 也沒有小時分支
        // —— 它是診斷指令的輸出，難看但不說謊，所以留著沒動。
        func e(_ s: TimeInterval) -> String {
            AlertView.elapsed(from: t0, to: t0.addingTimeInterval(s))
        }
        #expect(e(45) == "45s")
        #expect(e(724) == "12m 04s")
        #expect(e(3664) == "1h 01m")
    }

    @Test("時間往回跑不可以印出負數 —— 夾在 0")
    func negativeElapsedIsClamped() {
        // 時鐘往回跳、或 statusUpdatedAt 比現在晚的時候會走到這裡。
        #expect(AlertView.elapsed(from: t0, to: t0.addingTimeInterval(-10)) == "0s")
    }
}
