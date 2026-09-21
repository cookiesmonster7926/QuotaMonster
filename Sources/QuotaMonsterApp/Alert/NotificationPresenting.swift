import Foundation
import QuotaMonsterCore

/// `DataStore` 只認得這個協定，不認得 AppKit。
///
/// 這條界線的用處不是抽象本身，是讓 `--dump` / `--render-panel` 這些診斷指令
/// 建得出 `DataStore` 而不會拉進整個視窗系統。
@MainActor
protocol NotificationPresenting: AnyObject {
    func present(_ event: NotificationEvent)
    /// 這些 session 還在等。不在裡面的就代表已經解除，浮窗要收掉。
    func resolve(stillWaiting: Set<String>)
}
