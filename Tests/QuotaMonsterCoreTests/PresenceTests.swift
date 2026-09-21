import Foundation
import Testing
@testable import QuotaMonsterCore

@Suite("Presence — 值得為它出聲嗎")
struct PresenceTests {

    @Test("三個訊號各自都足以消音 —— 這是 OR，不是只看閒置")
    func anySignalAloneSilences() {
        // ⚠️ 這一則是整份清單裡最重要的：一個只看 idleSeconds 的實作
        // 可以通過其他好幾條，只有這張真值表會紅。
        #expect(Presence(screenLocked: false, screensAsleep: false,
                         idleSeconds: 0).worthSounding)
        #expect(!Presence(screenLocked: true, screensAsleep: false,
                          idleSeconds: 0).worthSounding)
        #expect(!Presence(screenLocked: false, screensAsleep: true,
                          idleSeconds: 0).worthSounding)
        #expect(!Presence(screenLocked: false, screensAsleep: false,
                          idleSeconds: 3600).worthSounding)
    }

    @Test("讀不到閒置秒數就沒有正面證據 —— nil 不是 0")
    func nilIdleIsNotZero() {
        // 這裡刻意與 `ScreenPresence.hidIdleSeconds` 的 `?? 0` **反向**：
        // 那邊猜錯的代價是少開一扇窗，這邊猜錯的代價是對著空房間播音效。
        #expect(!Presence(screenLocked: false, screensAsleep: false,
                          idleSeconds: nil).worthSounding)
    }

    @Test("門檻與 ScreenPresence.isIdle 逐字互補 —— 剛好 300 秒出聲、301 不出聲")
    func thresholdBoundary() {
        // `isIdle` 是 `> idleThreshold`，所以 worthSounding 必須是 `<=`。
        // 寫成 `<` 的話兩條通道對「人在」的定義會差一秒，而那種不一致
        // 沒有人會發現。
        #expect(Presence(screenLocked: false, screensAsleep: false,
                         idleSeconds: Presence.idleThreshold).worthSounding)
        #expect(!Presence(screenLocked: false, screensAsleep: false,
                          idleSeconds: Presence.idleThreshold + 1).worthSounding)
    }

    @Test("實測抓到的那一格：鎖定 + 螢幕睡 + 閒置 866 秒")
    func theMeasuredEmptyChair() {
        // 2026-09-19 02:28:23 的實測輸出：
        // `T2 · 看得到浮窗嗎 false（鎖定 true 螢幕睡 true 閒置 866s）`
        #expect(!Presence(screenLocked: true, screensAsleep: true,
                          idleSeconds: 866).worthSounding)
    }
}
