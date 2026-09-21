import Testing
import Foundation
@testable import QuotaMonsterCore

/// 「跳過去」按鈕能做到的**唯一**一件事：把擁有那個 session 的 app 叫到前面。
///
/// 實測（2026-09-18，這台機器）：
///   - `AXIsProcessTrusted() == false`，AX 呼叫回 `kAXErrorAPIDisabled (-25211)`
///   - 20 個在螢幕上的視窗，`kCGWindowName` 拿得到的是 **0 個**（受 Screen Recording 管制）
///   - 三個真實 session 有兩個**根本沒有 tty**，剩下那個在 `herdr` pty 多工器裡面
///
/// 所以指定分頁做不到，而且要三個授權提示才能換來一個在三分之二的 session 上
/// 仍然無效的功能。V1 只做 app 層級的啟用，並把這個拒絕寫下來。
///
/// 真實的父行程鏈（實測）：
///   - VS Code session：claude → Code Helper (Plugin) → **Code**（2 跳）
///   - Ghostty CLI session：**6 跳**才到 Ghostty
/// `maxHops` 給 4 會安靜地失敗 —— 所以給 24。
@Suite("OwningApplicationResolver")
struct OwningApplicationResolverTests {

    /// 用注入的假行程樹測。真實實作走 `sysctl(KERN_PROC_PID)`，
    /// 跟 `ProcessLiveness` 共用同一次呼叫，**不生 ps**。
    func resolver(parents: [Int32: Int32], apps: Set<Int32>,
                  maxHops: Int = 24) -> OwningApplicationResolver {
        OwningApplicationResolver(
            parentOf: { parents[$0] },
            isApplication: { apps.contains($0) },
            maxHops: maxHops)
    }

    @Test("VS Code 的鏈：claude → Code Helper → Code，兩跳")
    func vscodeChain() {
        let r = resolver(parents: [17580: 2594, 2594: 2580, 2580: 1], apps: [2580])
        #expect(r.owningPid(of: 17580) == 2580)
    }

    @Test("Ghostty 的鏈要走六跳 —— maxHops 給 4 會安靜地失敗")
    func ghosttyChainNeedsSixHops() {
        let parents: [Int32: Int32] = [900: 901, 901: 902, 902: 903,
                                       903: 904, 904: 905, 905: 906, 906: 1]
        let r = resolver(parents: parents, apps: [906])
        #expect(r.owningPid(of: 900) == 906)
        #expect(resolver(parents: parents, apps: [906], maxHops: 4).owningPid(of: 900) == nil)
    }

    @Test("app bundle 裡的 helper 不算 app —— 走訪不可以停在它身上")
    func helperInsideABundleIsNotAnApplication() {
        // 2594 是 Code Helper (Plugin)，它在 Code.app 裡面但不是那個 app。
        // 停在它身上的話，activate 會對一個沒有視窗的行程呼叫，什麼都不會發生。
        let r = resolver(parents: [17580: 2594, 2594: 2580, 2580: 1], apps: [2580])
        #expect(r.owningPid(of: 17580) != 2594)
    }

    @Test("被 launchd 收養的孤兒回 nil")
    func orphanReturnsNil() {
        #expect(resolver(parents: [500: 1], apps: [999]).owningPid(of: 500) == nil)
    }

    @Test("父鏈成環不可以卡住 —— 敵意輸入也要在有限步內結束")
    func cycleTerminates() {
        #expect(resolver(parents: [10: 11, 11: 12, 12: 10], apps: []).owningPid(of: 10) == nil)
    }

    @Test("讀不到父行程就停 —— 行程剛死掉是常態，不是錯誤")
    func missingParentStops() {
        #expect(resolver(parents: [:], apps: []).owningPid(of: 777) == nil)
    }

    @Test("自己就是 app 的話直接回自己")
    func selfIsAnApplication() {
        #expect(resolver(parents: [42: 1], apps: [42]).owningPid(of: 42) == 42)
    }

    @Test("走到 pid 1 就停，不會把 launchd 當成擁有者")
    func stopsAtLaunchd() {
        #expect(resolver(parents: [50: 1, 1: 0], apps: [1]).owningPid(of: 50) == nil)
    }
}
