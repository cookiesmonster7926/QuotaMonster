import AppKit
import Darwin
import QuotaMonsterCore

/// 「跳過去」實際做的事：把擁有那個 session 的 app 叫到前面。
///
/// 能力邊界見 `OwningApplicationResolver` 的註解 —— 指定視窗或分頁在這台機器上
/// 需要 Accessibility 與 Screen Recording 兩個授權，而且**在三個真實 session 裡
/// 有兩個仍然無效**（它們根本沒有 tty）。所以按鈕只做 app 層級的啟用，
/// 面板上同時顯示 session 自己的名字（`usage-c9`），讓使用者知道該找哪個分頁。
@MainActor
enum SessionActivator {

    /// ⚠️ **在按下去的當下才解析，不要在建面板時就算好。**
    /// 擁有者是從活的行程樹推出來的，快取起來會過期，然後把一個被回收的 pid
    /// 叫到前面 —— 那不只是沒反應，是叫錯 app。
    @discardableResult
    static func activate(pid: Int32) -> Bool {
        let resolver = OwningApplicationResolver(
            parentOf: parentPid,
            isApplication: Self.isApplication)

        guard let owner = resolver.owningPid(of: pid),
              let app = NSRunningApplication(processIdentifier: owner) else { return false }

        // macOS 14+ 的協作式轉移，比硬搶可靠。
        NSApp.yieldActivation(to: app)
        // `[]` 而不是 `.activateAllWindows`：前者把主視窗帶到前面，正是
        // 「跳到這個 session」的意思；後者會把 VS Code 每一個視窗都攤開，
        // 反而弄丟順序。`.activateIgnoringOtherApps` 從 macOS 14 起無效，不要傳。
        return app.activate(options: [])

        // 不要用 `app.isActive` 或 `frontmostApplication` 去驗證有沒有成功 ——
        // 兩者都是過期的快照，實測會騙人。真的需要確認就聽
        // `NSWorkspace.shared.notificationCenter` 的 didActivateApplication。
    }

    /// 這個 pid 是不是一個 GUI app。
    ///
    /// bundle 裡的 helper（`Code Helper (Plugin)` 之類）會回 false ——
    /// 停在它身上的話，activate 會對一個沒有視窗的行程呼叫，什麼都不會發生。
    nonisolated static func isApplication(_ pid: Int32) -> Bool {
        NSRunningApplication(processIdentifier: pid)
            .map { $0.activationPolicy != .prohibited } ?? false
    }

    /// 取父行程。跟 `ProcessLiveness.processStartTime` 是同一次 sysctl 的形狀，
    /// **不生 `ps`** —— 為了一顆按鈕 fork 一個行程不划算，而且會把 UI 卡住。
    nonisolated static func parentPid(_ pid: Int32) -> Int32? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0,
              size > 0, info.kp_proc.p_pid == pid else { return nil }
        let ppid = info.kp_eproc.e_ppid
        return ppid > 0 ? ppid : nil
    }
}
