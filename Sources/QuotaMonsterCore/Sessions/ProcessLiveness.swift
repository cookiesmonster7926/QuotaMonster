import Darwin
import Foundation

/// pid 重用安全的行程存活判定。
///
/// **為什麼不能只看 pid：** crash 掉的 session 會留下一個永遠寫著 `busy` 的檔案，
/// 而 pid 會被系統回收再利用。只驗 pid 的話，一個不相干的新行程就會讓那個
/// 死掉的 session 復活。而且 session 檔**沒有 heartbeat** —— `status` 只在
/// 狀態轉換時寫入，實測有 session 已宣稱 busy 41 分鐘 —— 所以時間戳也不能用來判斷存活。
///
/// 唯一可靠的方法：pid 存在 **而且** 行程的真實啟動時間對得上註冊表寫的 `startedAt`。
public enum ProcessLiveness {

    /// 啟動時間的容差。註冊表寫入的 `startedAt` 與核心記錄的行程啟動時間
    /// 本來就會差幾秒。
    public static let reuseTolerance: TimeInterval = 300

    public static func isAlive(pid: Int32, startedAt: Date) -> Bool {
        guard pidExists(pid), let real = processStartTime(pid) else { return false }
        return abs(real.timeIntervalSince(startedAt)) < reuseTolerance
    }

    /// `kill(pid, 0)` 不送訊號，只做存在性與權限檢查。
    /// `EPERM` 代表行程存在但不屬於我們 —— 仍然算活著。
    public static func pidExists(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// 從核心讀出行程的真實啟動時間。
    public static func processStartTime(_ pid: Int32) -> Date? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let rc = sysctl(&mib, u_int(mib.count), &info, &size, nil, 0)
        guard rc == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        let tv = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(tv.tv_sec) + Double(tv.tv_usec) / 1_000_000)
    }
}
