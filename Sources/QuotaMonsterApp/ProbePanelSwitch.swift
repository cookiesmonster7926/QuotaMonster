import SwiftUI
import AppKit
import QuotaMonsterCore

/// `QuotaMonsterApp --probe-panel-switch`：
/// **popover 已經開著的時候切換版面，`fittingSize` 什麼時候才回報新高度？**
///
/// ### 它回答哪一個問題
/// `StatusItemController` 只在 `togglePanel()` **展開的那一刻**指派
/// `popover.contentSize = panelSize()`，而 `panelSize()` 讀的是 `panel.view.fittingSize`。
/// 版面切換鍵在 footer 上，是在 popover **已經開著**的時候按的。
/// `PanelView` 自己的註解又寫著「量的那條路要等下一輪 runloop 才有值」——
/// 所以沒有答案的是**要等到哪一刻**才能指派。這支就是去量那一刻。
///
/// ### 量到了什麼〔實測 2026-09-22，n≥2，兩個方向都試〕
/// ```
///                     fittingSize   contentSize   window
///   穩定（完整）           595           595        621
///   同一個 tick           595（舊）      595        621
///   main.async 一跳之後    268（新）      595        294（也跟上了）
///   500ms / 1.5s 之後      268           595        294
/// ```
/// 兩個結論：
/// 1. **一跳就夠。** 不必用計時器賭，也不必在 Core 複製一份高度計算（規矩 2）。
/// 2. ⚠️ **`window` 自己就跟上了** —— 所以視覺上不補指派也是對的；
///    補是為了讓 `contentSize` 這個屬性不要過期（`panelSize()` 的螢幕高度夾限會讀它）。
///
/// 它**不能**證明：切換動畫好不好看、使用者按不按得到那顆鍵。
///
/// ⚠️ 它會翻 `panelStyle`，但走 `setPreferences(_:persist: false)` ——
/// **診斷不可以改掉使用者真正的設定檔**（規矩 44），結束前也會翻回原值。
@MainActor
enum ProbePanelSwitch {

    static func run() {
        let store = DataStore()
        store.refresh()
        let original = store.panelStyle
        let hosting = NSHostingController(rootView: PanelView(store: store))

        func flip(to style: PanelStyle) {
            var p = store.preferences
            p.panelStyle = style
            store.setPreferences(p, persist: false)
        }

        let item = NSStatusBar.system.statusItem(withLength: GlyphGeometry.canvas)
        item.button?.image = GlyphRenderer.image(for: store.glyph)
        let popover = NSPopover()
        popover.behavior = .applicationDefined
        popover.animates = false
        popover.contentViewController = hosting

        /// ⚠️ 不要用 `String(format: "%-26s")` 排版中文 —— `%s` 吃的是 C 字串，
        /// 中文會印成一堆亂碼（第一版就是這樣）。
        func report(_ label: String) {
            let pad = String(repeating: " ", count: max(0, 20 - label.count * 2))
            print("  \(label)\(pad)"
                  + " fittingSize \(String(format: "%6.1f", hosting.view.fittingSize.height))"
                  + "   contentSize \(String(format: "%6.1f", popover.contentSize.height))"
                  + "   window \(String(format: "%6.1f", hosting.view.window?.frame.height ?? -1))")
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard let button = item.button else {
                print("✘ 拿不到 status item 的 button"); NSApp.terminate(nil); return
            }
            flip(to: .full)
            popover.contentSize = hosting.view.fittingSize
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            try? await Task.sleep(for: .milliseconds(500))

            print("── 展開後、切換前（完整面板）──────────────────────")
            report("穩定狀態")

            print("── 翻成簡易（變矮）───────────────────────────────")
            flip(to: .simple)
            report("同一個 tick")
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
            report("main.async 一跳之後")
            try? await Task.sleep(for: .milliseconds(100));  report("100ms 之後")
            try? await Task.sleep(for: .milliseconds(1400)); report("1.5s 之後")

            // ⚠️ 反方向（變高）才是危險的那個：框不夠大時內容會被裁掉，
            // 而變矮只是底下多一塊空白。所以兩個方向都要量。
            print("── 翻回完整（變高）───────────────────────────────")
            flip(to: .full)
            report("同一個 tick")
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
            report("main.async 一跳之後")
            try? await Task.sleep(for: .milliseconds(500)); report("500ms 之後")

            flip(to: original)
            print("── 判讀 ──────────────────────────────────────────")
            print("  哪一列先出現新高度，就是「可以指派 contentSize」的那一刻。")
            print("  ⚠️ 另外看 window 那一欄 —— 它是使用者真正看到的框。")
            NSApp.terminate(nil)
        }
    }
}

@MainActor
final class PanelSwitchDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) { ProbePanelSwitch.run() }
}
