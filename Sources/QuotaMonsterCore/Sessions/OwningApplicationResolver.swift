import Foundation

/// 從一個 claude 行程往上找到「擁有它的那個 app」。
///
/// ### 「跳過去」能做到什麼，以及做不到什麼（2026-09-18 實測）
/// 做得到：**把擁有它的 app 叫到前面**。零授權需求。
///
/// 做不到：指定到那個視窗或那個分頁。
///   - `AXIsProcessTrusted() == false`，AX 呼叫回 `kAXErrorAPIDisabled (-25211)`
///   - 螢幕上 20 個視窗，`kCGWindowName` 拿得到的是 **0 個**（受 Screen Recording 管制）
///   - 三個真實 session 有兩個**根本沒有 tty**，剩下那個在 `herdr` pty 多工器裡，
///     Ghostty 的 AppleScript 字典定址不到
///
/// 三個授權提示，換來一個在三分之二的 session 上仍然無效的功能 —— 不划算。
/// **所以這個拒絕是寫下來的設計決定，不是還沒做。**
///
/// 相依全部注入，測試餵假的行程樹，不必真的生一個行程。
public struct OwningApplicationResolver: Sendable {

    /// 走訪上限。
    ///
    /// ⚠️ **不要調小。** 實測的 Ghostty 鏈要走 **6 跳**（VS Code 只要 2 跳），
    /// 給 4 會在 CLI session 上安靜地失敗 —— 按鈕沒反應，沒有錯誤訊息。
    /// 上限存在的目的只是擋住成環的父鏈，不是省時間。
    public static let defaultMaxHops = 24

    private let parentOf: @Sendable (Int32) -> Int32?
    private let isApplication: @Sendable (Int32) -> Bool
    private let maxHops: Int

    /// - Parameters:
    ///   - parentOf: 取父行程。正式實作走 `sysctl(CTL_KERN, KERN_PROC, KERN_PROC_PID)`，
    ///     跟 `ProcessLiveness` 共用同一次呼叫 —— **不要生 `ps`**。
    ///   - isApplication: 這個 pid 是不是一個 GUI app。正式實作在 App target 裡，
    ///     用 `NSRunningApplication(processIdentifier:)`。
    public init(parentOf: @escaping @Sendable (Int32) -> Int32?,
                isApplication: @escaping @Sendable (Int32) -> Bool,
                maxHops: Int = defaultMaxHops) {
        self.parentOf = parentOf
        self.isApplication = isApplication
        self.maxHops = maxHops
    }

    /// - Returns: 擁有這個 pid 的 app 的 pid，找不到回 nil。
    ///
    /// ⚠️ **在按下去的當下才呼叫，不要在建面板時就算好。** 擁有者是從活的行程樹
    /// 推出來的，快取起來會過期，然後把一個被回收的 pid 叫到前面 ——
    /// 那不只是沒反應，是叫錯 app。
    public func owningPid(of pid: Int32) -> Int32? {
        var current = pid
        var seen: Set<Int32> = []

        for _ in 0..<maxHops {
            // pid 1 是 launchd。走到它就代表這條鏈上沒有 app
            //（行程被收養了，原本的終端機已經關掉）。
            guard current > 1 else { return nil }
            if isApplication(current) { return current }
            // 成環是敵意輸入，不是正常狀態，但也不可以讓 UI 執行緒卡住。
            guard seen.insert(current).inserted, let parent = parentOf(current) else { return nil }
            current = parent
        }
        return nil
    }
}
