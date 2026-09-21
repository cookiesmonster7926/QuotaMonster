import AppKit
import SwiftUI
import QuotaMonsterCore

/// `QuotaMonsterApp --probe-popover`：量面板實際被放在哪裡。
///
/// 存在的理由：使用者回報面板頂端蓋到選單列。這件事有好幾個可能原因
/// （內容太高被 AppKit 往上推、錨點邊緣選錯、hosting controller 回報的尺寸不對），
/// 用猜的會修錯地方。這支 probe 把所有相關數字一次印出來。
@MainActor
final class ProbePopoverDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) {
        ProbePopover.run()
    }
}

@MainActor
enum ProbePopover {
    /// ⚠️ 一定要在 applicationDidFinishLaunching 之後才跑。
    /// 太早建立的 status item，其 window 的高度是 0，popover 根本掛不上去
    /// （實測：button.window = (0,0,38,0)、popover 沒有 window）。
    static func run() {
        let store = DataStore()
        store.refresh()

        let screen = NSScreen.main
        let hosting = NSHostingController(rootView: PanelView(store: store))
        let fitting = hosting.view.fittingSize

        print("── 螢幕 ──────────────────────────────────────────")
        print("frame            \(screen?.frame ?? .zero)")
        print("visibleFrame     \(screen?.visibleFrame ?? .zero)")
        print("menu bar 厚度     \(NSStatusBar.system.thickness)")
        if let s = screen {
            let belowMenuBar = s.frame.maxY - s.visibleFrame.maxY
            print("選單列佔掉的高度   \(belowMenuBar)")
            print("選單列以下可用高度 \(s.visibleFrame.height)")
        }

        print("── 面板 ──────────────────────────────────────────")
        print("hosting fittingSize        \(fitting)")
        print("hosting preferredContentSize \(hosting.preferredContentSize)")

        let item = NSStatusBar.system.statusItem(withLength: GlyphGeometry.canvas)
        item.button?.image = GlyphRenderer.image(for: store.glyph)

        let edgeArg = CommandLine.arguments.last ?? "minY"
        let edge: NSRectEdge = edgeArg == "maxY" ? .maxY : .minY

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = hosting
        // "real" = 完全照現在 StatusItemController 的做法（不設 contentSize）
        if edgeArg != "real" { popover.contentSize = fitting }

        // status item 的 window 要等 runloop 跑過一輪才有真正的大小。
        // 立刻讀會拿到 (0,0,38,0)，popover 也掛不上去。
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard let button = item.button else { print("沒有 button"); exit(1) }
            print("── status item（延遲後）──────────────────────────")
            print("button.bounds    \(button.bounds)")
            print("button.frame     \(button.frame)")
            print("button.window    \(button.window?.frame ?? .zero)")
            if let bw = button.window {
                let inScreen = bw.convertToScreen(button.convert(button.bounds, to: nil))
                print("button 在螢幕上   \(inScreen)")
            }

            // 候選修法：把錨點矩形往下延伸到 status bar window 的底緣，
            // 這樣 popover 的箭頭尖端會落在選單列底緣，而不是按鈕底緣（高 5.5pt）。
            var rect = button.bounds
            if edgeArg == "extended" {
                let inWindow = button.convert(button.bounds, to: nil)
                let dropBy = inWindow.minY
                rect.origin.y -= dropBy
                rect.size.height += dropBy
                print("往下延伸        \(dropBy) pt → 錨點矩形 \(rect)")
            }
            print("preferredEdge    \(edgeArg)")
            popover.show(relativeTo: rect, of: button, preferredEdge: edge)
            // 等 SwiftUI 把內容量完、popover 重新調整大小之後再量
            try? await Task.sleep(for: .milliseconds(1500))

            print("── popover 實際落點 ──────────────────────────────")
            print("popover.contentSize  \(popover.contentSize)")
            if let w = popover.contentViewController?.view.window, let s = screen {
                let f = w.frame
                print("popover window       \(f)")
                let menuBarBottom = s.visibleFrame.maxY
                print("選單列底緣 y          \(menuBarBottom)")
                print("popover 頂緣 y        \(f.maxY)")
                let overlap = f.maxY - menuBarBottom
                print(overlap > 0 ? "→ 重疊選單列 \(overlap) pt ⚠️"
                                  : "→ 沒有重疊（低於選單列 \(-overlap) pt）")
            } else {
                print("popover 沒有 window")
            }
            popover.performClose(nil)
            exit(0)
        }
    }
}
