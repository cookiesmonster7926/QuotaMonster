import AppKit
import ServiceManagement
import QuotaMonsterCore

/// 開機自動啟動。`SMAppService.mainApp` 這一路不需要 helper bundle。
///
/// ⚠️ **只有從 .app bundle 跑起來的時候才有意義。** `--dump` / `--render-panel`
/// 這些診斷是純 CLI binary，`SMAppService` 對它們沒有東西可以註冊 ——
/// 那種情況一律回 `.unavailable`，UI 整個不畫這個按鈕。
@MainActor
enum LoginItem {

    /// 這個執行檔是不是裝在 .app 裡。
    ///
    /// 〔實測〕從 `.build/release/QuotaMonsterApp` 跑的時候，
    /// `Bundle.main.bundleURL` 是那個**目錄**，副檔名不是 `app`。
    static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    static var state: LoginItemState {
        guard isBundled else { return .unavailable }
        // ⚠️ 用 `switch` 而不是比對 rawValue —— 編譯器會在 SDK 加新狀態時提醒。
        switch SMAppService.mainApp.status {
        case .enabled:
            return .on
        case .requiresApproval:
            // app 自己 register() 叫不回來，只能請使用者去系統設定。
            return .blockedBySystem
        case .notRegistered:
            return .off
        case .notFound:
            // ⚠️〔Stage 0 實測〕**這是註冊前的正常值，不是安裝損壞。**
            // 把它當成錯誤顯示，使用者會以為 app 壞了。
            return .off
        @unknown default:
            return .off
        }
    }

    /// 執行按鈕的動作。
    ///
    /// 失敗**不丟錯**：這是一個錦上添花的設定，它壞掉不可以讓面板停住。
    /// 呼叫端重讀 `state` 就會看到有沒有成功。
    static func apply(_ action: LoginItemState.Action) {
        switch action {
        case .register:
            do { try SMAppService.mainApp.register() } catch {
                NSLog("QuotaMonster: 註冊開機啟動失敗 —— %@", String(describing: error))
            }
        case .unregister:
            do { try SMAppService.mainApp.unregister() } catch {
                NSLog("QuotaMonster: 取消開機啟動失敗 —— %@", String(describing: error))
            }
        case .openSystemSettings:
            SMAppService.openSystemSettingsLoginItems()
        case .none:
            break
        }
    }

    /// `--probe-login`：把真實狀態印出來。
    ///
    /// 存在的理由與 `--probe-popover` 一樣：這條路的失敗是**安靜的**
    /// （註冊沒成功、或系統設定裡被關掉），畫面上看不出差別。
    /// - Parameter act: 傳 `.register` / `.unregister` 會**真的動手**，
    ///   然後把動手前後的狀態都印出來。這條路沒有辦法從畫面上驗收 ——
    ///   註冊沒成功與註冊成功長得一模一樣，直到下次登入才知道。
    static func probe(then act: LoginItemState.Action = .none) {
        func say(_ s: String) { FileHandle.standardOutput.write(Data((s + "\n").utf8)) }
        say("bundle      \(Bundle.main.bundleURL.path)")
        say("是 .app 嗎   \(isBundled)")
        let raw = SMAppService.mainApp.status
        say("原始狀態     \(raw)（rawValue \(raw.rawValue)）")
        say("對應到       \(state)")
        say("按下去會     \(state.action)")
        say("")
        say("⚠️ notFound 是註冊前的正常值，不是安裝損壞。")

        guard act != .none else { return }
        say("")
        say("── 動手：\(act) ──")
        apply(act)
        let after = SMAppService.mainApp.status
        say("之後狀態     \(after)（rawValue \(after.rawValue)）→ \(state)")
    }
}
