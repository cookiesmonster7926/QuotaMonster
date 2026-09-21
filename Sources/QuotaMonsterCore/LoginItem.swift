import Foundation

/// 「開機時自動啟動」現在是什麼狀態。
///
/// ⚠️ 這個型別刻意**不 import ServiceManagement** —— 對應到系統那個列舉是
/// App 層一個 `switch` 的事（編譯器會檢查），而「按下去會怎樣」是一條純規則，
/// 值得被直接測。形狀抄 `MutePolicy`。
public enum LoginItemState: Equatable, Sendable {
    /// 已註冊，下次登入會自己起來。
    case on
    /// 沒註冊。
    ///
    /// ⚠️ 系統那邊有**兩個**狀態會落到這裡：`notRegistered` 與 `notFound`。
    /// 〔Stage 0 實測〕**`notFound` 是註冊前的正常值，不是安裝損壞** ——
    /// 把它當成錯誤去顯示，使用者會以為 app 壞了。
    case off
    /// 使用者在系統設定裡把它關掉了。
    ///
    /// ⚠️ 這一格 **app 自己 `register()` 是叫不回來的** —— 只能請使用者
    /// 自己去系統設定。把它跟 `off` 混在一起，按鈕就會變成一個按了沒反應的東西。
    case blockedBySystem
    /// 這個執行檔不是 .app bundle（`--dump` 這些診斷指令就是這種）。
    case unavailable

    /// 按下去該做什麼。
    public enum Action: Equatable, Sendable {
        case register
        case unregister
        /// 開系統設定的「登入項目」那一頁。
        case openSystemSettings
        /// 什麼都不做（按鈕本來就不該讓人按到）。
        case none
    }

    public var action: Action {
        switch self {
        case .off:             return .register
        case .on:              return .unregister
        case .blockedBySystem: return .openSystemSettings
        case .unavailable:     return .none
        }
    }

    /// 按鈕旁邊那行字。nil 代表不寫字（只留圖示）。
    public var caption: String? {
        switch self {
        case .on:              return nil          // 圖示已經說完了
        case .off:             return nil
        case .blockedBySystem: return "已被系統設定關閉"
        case .unavailable:     return nil
        }
    }

    public var help: String {
        switch self {
        case .on:              return "開機時會自動啟動。點一下關閉"
        case .off:             return "點一下設成開機自動啟動"
        case .blockedBySystem: return "你在系統設定裡關掉了它 —— 點一下開啟那一頁"
        case .unavailable:     return "這個執行檔不是 .app bundle，設定不了"
        }
    }

    /// 按鈕要不要畫出來。
    ///
    /// 不是 bundle 的時候整個不畫 —— 一個按了保證沒用的按鈕比沒有按鈕更糟。
    public var isVisible: Bool { self != .unavailable }
}
