import AppKit
import CoreGraphics
import IOKit
import QuotaMonsterCore

/// 「使用者現在看得到浮窗嗎？」
///
/// 使用者選的規則：**osascript 副本只在你看不到浮窗時才發。**
/// 看得到的時候不重複打擾；真正離開螢幕時，事件仍然留得下痕跡
/// （通知中心歷史與鎖定畫面，那是 NSPanel 做不到的兩件事）。
///
/// 下面每一個訊號都**不需要任何授權**，而且都已經實測過。
/// ⚠️ **Focus／勿擾狀態不在其中，因為讀不到** ——
/// `~/Library/DoNotDisturb/DB/Assertions.json` 受 TCC 保護，也沒有公開 API。
/// 所以手動靜音是唯一的防線，設計文件裡「靠 interruption level 讓系統仲裁」
/// 那一句在備援路線上是過時的。
@MainActor
enum ScreenPresence {

    /// 超過這個閒置時間就當作人不在螢幕前。
    ///
    /// ⚠️ **這裡只是別名，唯一的定義在 `Presence.idleThreshold`。**
    /// 這個 repo 已經為「門檻只能定義在一處」立過規矩（見 `QuotaTier.forRemaining`）：
    /// 兩份字面量會在某一次只改了一邊之後，讓浮窗與音效對「人在」的定義差一截，
    /// 而且不會有人馬上發現。
    ///
    /// ⚠️ 這條別名本身**沒有測試守著** —— 用 `#expect(Presence.idleThreshold == 300)`
    /// 去釘是一則說謊的測試：這裡改成另一個字面量 300 的話它照樣會過。
    /// 唯一的執行手段就是這一行。
    static let idleThreshold: TimeInterval = Presence.idleThreshold

    /// 浮窗現在有沒有機會被看到。
    ///
    /// ⚠️ 刻意**不用** `snapshot().worthSounding` —— 那是另一個問題，而且
    /// 這裡是短路求值的：鎖定時根本走不到 `hidIdleSeconds`，
    /// 也就省掉唯一那次 IORegistry 走訪（`resolve()` 每一拍都會呼叫這支）。
    /// 兩個問題的差別見 `Presence` 的檔頭。
    static var canSeeAPanel: Bool {
        !isLocked && !screensAsleep && !isIdle
    }

    /// 把三個訊號原樣打包給 Core。**這裡不做任何判斷** ——
    /// 判斷在 `Presence.worthSounding`，那邊有測試。
    ///
    /// 與 `canSeeAPanel` 不同，這支**一定**會讀 `hidIdleSeconds`（不短路），
    /// 因為 Core 要的是三個訊號的原值，而不是一個已經塌縮過的結論。
    /// 代價是鎖著的機器上每 3 秒多一次 IORegistry 走訪 —— 一次字典查詢，
    /// 相對於三秒一輪的整組讀檔可以忽略。〔推論，沒有量過〕
    static func snapshot() -> Presence {
        Presence(screenLocked: isLocked, screensAsleep: screensAsleep,
                 idleSeconds: hidIdleSeconds)
    }

    /// 螢幕鎖定或快速使用者切換。
    static var isLocked: Bool {
        guard let d = CGSessionCopyCurrentDictionary() as? [String: Any] else { return false }
        if let locked = d["CGSSessionScreenIsLocked"] as? Bool, locked { return true }
        if let onConsole = d["kCGSSessionOnConsoleKey"] as? Bool, !onConsole { return true }
        return false
    }

    /// 螢幕睡眠。
    static var screensAsleep: Bool {
        // NSScreen 在螢幕睡眠時仍然回報存在，所以問的是顯示器本身有沒有在亮。
        CGDisplayIsActive(CGMainDisplayID()) == 0
    }

    /// 人離開鍵盤滑鼠超過門檻。
    static var isIdle: Bool {
        (hidIdleSeconds ?? 0) > idleThreshold
    }

    /// 從 IOKit 的 `IOHIDSystem` 讀閒置秒數。拿不到就回 nil ——
    /// **nil 要當成「人在」**，不是「人不在」：猜錯的方向要選不會多發通知的那一邊。
    static var hidIdleSeconds: TimeInterval? {
        var iterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
                                           IOServiceMatching("IOHIDSystem"),
                                           &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return nil }
        defer { IOObjectRelease(entry) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0)
                == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any],
              let nanos = dict["HIDIdleTime"] as? Int64 else { return nil }
        return TimeInterval(nanos) / 1_000_000_000
    }
}
