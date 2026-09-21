import AppKit
import SwiftUI
import QuotaMonsterCore

/// 偏好設定的視窗。
///
/// ### ⚠️ `AlertPanelController` 的那一串 ⚠️ 有一半在這裡是**反的**
///
/// 那扇浮窗整套設定（`.nonactivatingPanel`、`becomesKeyOnlyIfNeeded`、
/// `level = .statusBar`、`orderFrontRegardless()`）是為了**不要搶焦點**、
/// 蓋在選單列上、跨 Space 跟著你走。設定視窗的需求正好相反：
/// **它必須成為 key window**，否則按鈕不會有 hover、鍵盤完全沒有作用。
/// 照抄那一套會得到一扇看得到但用不了的視窗。
///
/// 兩條**原封不動**照抄：
/// - `hidesOnDeactivate = false` —— 這個 app 是 accessory，「非前景」是常態，
///   預設值會讓視窗在你點到別的地方時當場消失。
/// - `acceptsFirstMouse` —— 背景 app 的視窗會吃掉第一次點擊
///   （〔實測〕`NSHostingView` 預設 false，使用者會以為按鈕壞了）。
@MainActor
final class PreferencesWindow: NSObject, NSWindowDelegate {

    private var window: NSWindow?

    func show(store: DataStore) {
        if let window {
            bringToFront(window)
            return
        }
        // 音效清單掃一次就好，不要每次重繪都掃目錄。
        let view = PreferencesView(store: store, sounds: AlertSound.available())
        let hosting = FirstMouseHostingView(rootView: view)
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 300),
                         styleMask: [.titled, .closable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.contentView = hosting
        w.title = "QuotaMonster 偏好設定"
        w.titlebarAppearsTransparent = true
        // ⚠️ **不設 level、不設 isFloatingPanel。** 設定視窗是一扇普通視窗；
        // 蓋在選單列上的那個 level 是浮窗專用的。
        w.hidesOnDeactivate = false
        w.isReleasedWhenClosed = false      // 關掉之後還要能再開
        w.delegate = self
        w.setContentSize(hosting.fittingSize)
        w.center()
        window = w
        bringToFront(w)
    }

    /// ⚠️ accessory app 的視窗預設拿不到鍵盤焦點 ——
    /// 一定要先把 app 帶到前景，再 `makeKeyAndOrderFront`。
    /// （這扇視窗沒有文字輸入欄位，但 hover、Esc 關閉、以及 Stepper 的
    /// 連續點擊都需要它是 key。）
    private func bringToFront(_ w: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
