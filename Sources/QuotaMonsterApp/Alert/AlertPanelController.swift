import AppKit
import SwiftUI
import QuotaMonsterCore

/// ⚠️ **這個 subclass 是整個 Stage 5 最重要的一行。**
///
/// `NSHostingView.acceptsFirstMouse` 預設是 `false`（實測確認）。
/// 非前景的浮窗裡，SwiftUI 的「跳過去」按鈕會**吃掉第一次點擊** ——
/// 使用者點了沒反應，再點一次才有。那正是「這東西壞了，刪掉」的那個瞬間。
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// T1 的浮窗。
///
/// ### 設定順序是載重的
/// `isFloatingPanel = true` 會把 `level` 覆寫成 `.floating`（3），所以它一定要在
/// `level` **之前**設。而 `.statusBar` 是 25、選單列是 24，所以視窗必須夾在
/// `visibleFrame` 裡，否則它會畫到選單列上面去。
///
/// ### 兩個預設值會讓這扇窗根本不出現
/// `hidesOnDeactivate` 預設 true —— 對一個 accessory app 來說「非前景」是常態，
/// 所以浮窗會當場消失。預設的 `collectionBehavior` 把視窗綁在建立它的 Space，
/// 所以使用者在全螢幕 app 裡時它**從來不出現**，而且沒有錯誤也沒有 callback。
@MainActor
final class AlertPanelController {

    /// 顯示多久之後自己淡出。
    ///
    /// 設計文件的「T1 每次等待事件只發一次 + 5 分鐘後恰好再推一次」只有在浮窗
    /// 是短暫的時候才說得通 —— 一扇賴著不走的窗，第二次推播就沒有意義了。
    static let visibleDuration: TimeInterval = 10
    static let fadeDuration: TimeInterval = 0.25

    private var panel: NSPanel?
    private var hosting: FirstMouseHostingView<AlertView>?
    private var dismissTimer: Timer?
    private var tickTimer: Timer?
    private var content: AlertContent?
    private var tracking: AlertTrackingProxy?
    /// 每次 show() 加一。淡出的 completion 靠它確認自己關的是同一扇窗。
    private var showGeneration = 0
    private let anchor: () -> NSRect?
    private let onJump: (WaitingSession) -> Void

    /// - Parameter anchor: 選單列圖示在螢幕座標裡的位置。拿不到就置中。
    init(anchor: @escaping () -> NSRect?, onJump: @escaping (WaitingSession) -> Void) {
        self.anchor = anchor
        self.onJump = onJump
    }

    // ── 顯示 ───────────────────────────────────────────────────

    func show(_ content: AlertContent) {
        showGeneration += 1
        self.content = content
        let panel = self.panel ?? makePanel()
        self.panel = panel

        render()
        panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 320, height: 123))
        position(panel)

        // ⚠️ **用零秒動畫覆蓋掉正在跑的淡出，不能只寫 `alphaValue = 1`。**
        // 直接指派不會取消已經在飛的那個隱式動畫，它會繼續把 alpha 拉到 0 ——
        // 結果是一扇「order 進來了、但完全透明」的窗：使用者什麼都沒看到，
        // 而程式這邊 isVisible 是 true，所以連下一次合併都會以為它在螢幕上。
        // 這是整個警示路徑裡最安靜的一種失敗。
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.alphaValue = 1
        // ⚠️ `orderFrontRegardless()`，不是 `makeKeyAndOrderFront` ——
        // 後者會把鍵盤焦點從使用者正在打字的地方搶走。
        panel.orderFrontRegardless()

        // 全螢幕 Space 的自我檢查：預設行為下這扇窗會安靜地不出現，
        // 沒有錯誤也沒有 callback。下一輪 runloop 才問得到真正的結果。
        DispatchQueue.main.async { [weak self] in
            guard let self, let p = self.panel else { return }
            if !p.isVisible { NSLog("QuotaMonster: 警示浮窗沒有出現（可能在全螢幕 Space）") }
        }

        startDismissTimer()
        startTicking()
    }

    func dismiss() {
        dismissTimer?.invalidate(); dismissTimer = nil
        tickTimer?.invalidate(); tickTimer = nil
        guard let panel else { return }
        // 淡出要 0.25 秒，而輪詢是 3 秒 —— 中間完全來得及有新的等待把窗口重新叫開。
        // 不記代數的話，那個舊的 completion 會在 0.25 秒後把**新**的窗關掉，
        // 而且看起來像「浮窗閃一下就不見了」這種找不到原因的 bug。
        let generation = showGeneration
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Self.fadeDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self, weak panel] in
            MainActor.assumeIsolated {
                guard let self, self.showGeneration == generation else { return }
                panel?.orderOut(nil)
            }
        }
    }

    /// session 已經不在等了 —— **立刻拆掉，不淡出**。
    ///
    /// 對著一個你已經回答過的問題繼續喊，就是那個把 app 刪掉的瞬間。
    func dismissImmediately() {
        showGeneration += 1
        dismissTimer?.invalidate(); dismissTimer = nil
        tickTimer?.invalidate(); tickTimer = nil
        panel?.orderOut(nil)
    }

    var isShowing: Bool { panel?.isVisible ?? false }

    /// 診斷用：把浮窗實際落在哪裡講出來。
    ///
    /// 這三個數字回答三個「安靜失敗」：有沒有出現、在不在可見區域裡、
    /// 有沒有被別的東西整片蓋住。三者都沒有錯誤訊息，只能問。
    var diagnostics: String {
        guard let p = panel else { return "panel = nil" }
        let vf = (p.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        return """
        isVisible      \(p.isVisible)
        level          \(p.level.rawValue)  (選單列是 24)
        frame          \(NSStringFromRect(p.frame))
        visibleFrame   \(NSStringFromRect(vf))
        在可見區域內    \(vf.contains(p.frame))
        occlusion      \(p.occlusionState.contains(.visible) ? "visible" : "occluded")
        NSApp.isActive \(NSApp.isActive)  (應該是 false —— 不可以搶前景)
        keyWindow      \(NSApp.keyWindow == nil ? "nil（沒搶鍵盤焦點）" : "有！不該如此")
        """
    }

    /// 目前顯示中的 session。呼叫端用它判斷「這些是不是都已經解除了」。
    var shownSessionIds: [String] { content?.sessions.map(\.sessionId) ?? [] }

    // ── 建視窗 ─────────────────────────────────────────────────

    private func makePanel() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: AlertView.width, height: 123),
                        styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true          // ⚠️ 先設 —— 這行會把 level 覆寫成 .floating(3)
        p.level = .statusBar              // ⚠️ 後設 —— 25，高於選單列的 24
        p.hidesOnDeactivate = false       // 預設會讓背景 app 的浮窗當場消失
        p.becomesKeyOnlyIfNeeded = true   // 點按鈕不奪走使用者正在打字的鍵盤焦點
        p.worksWhenModal = true           // 別的 app 開 modal 時仍然出得來
        p.collectionBehavior = [.canJoinAllSpaces,   // 跟著使用者走
                                .fullScreenAuxiliary, // 全螢幕 Space 也准
                                .stationary,          // Mission Control 不要動它
                                .ignoresCycle]        // 不要出現在 Cmd-`
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = false
        p.animationBehavior = .utilityWindow
        p.isReleasedWhenClosed = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        return p
    }

    private func render() {
        guard let content, let panel else { return }
        let view = AlertView(content: content,
                             onJump: { [weak self] s in
                                 self?.onJump(s)
                                 self?.dismissImmediately()
                             },
                             onDismiss: { [weak self] in self?.dismiss() })
        if let hosting {
            hosting.rootView = view
        } else {
            let h = FirstMouseHostingView(rootView: view)
            hosting = h
            panel.contentView = h
            installTracking(on: h)
        }
    }

    // ── 位置 ───────────────────────────────────────────────────

    private func position(_ panel: NSPanel) {
        let screen = NSScreen.screens.first { $0.frame.contains(anchor()?.origin ?? .zero) }
            ?? NSScreen.main
        guard let screen else { return }
        let vf = screen.visibleFrame

        var x: CGFloat
        if let a = anchor() {
            x = a.midX - panel.frame.width / 2
        } else {
            x = vf.maxX - panel.frame.width - 12
        }
        // 夾在 visibleFrame 裡。這同時解掉兩件事：
        //   1. 瀏海 —— visibleFrame.maxY 本來就在瀏海下面，不必寫任何瀏海專屬程式碼
        //   2. level 25 蓋住選單列 —— 夾住之後就不可能畫上去
        x = min(max(x, vf.minX + 8), vf.maxX - panel.frame.width - 8)
        let y = vf.maxY - panel.frame.height - 6
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // ── 計時 ───────────────────────────────────────────────────

    private func startDismissTimer() {
        dismissTimer?.invalidate()
        let t = Timer(timeInterval: Self.visibleDuration, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        RunLoop.main.add(t, forMode: .common)
        dismissTimer = t
    }

    /// 「等了 2m 14s」要真的在走。1 秒一格，只在視窗開著的時候跑 ——
    /// 收起來就 invalidate，這個 app 除了呼吸之外不留任何重複性計時器。
    private func startTicking() {
        tickTimer?.invalidate()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, var c = self.content else { return }
                c = AlertContent(primary: c.primary, others: c.others,
                                 coalesced: c.coalesced, context: c.context, now: Date())
                self.content = c
                self.render()
            }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        tickTimer = t
    }

    /// 滑鼠移進去就取消收起計時器，移開再重新開始 ——
    /// 否則它會在使用者伸手過去的那一刻消失。
    private func installTracking(on view: NSView) {
        let proxy = AlertTrackingProxy()
        proxy.controller = self
        tracking = proxy
        view.addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: proxy, userInfo: nil))
    }

    /// 滑鼠停在上面就不要收 —— 但**要有絕對上限**。
    ///
    /// 沒有上限的話，指標剛好停在螢幕上緣（那正是這扇窗出現的地方）就會把它
    /// 永遠釘在那裡，連帶那個 1Hz 的計時器也永遠不停。而這個 app 的一條主張是
    /// 「在動的那幾秒之外不留任何重複性計時器」。
    static let hoverLimit: TimeInterval = 60

    func mouseEntered() {
        dismissTimer?.invalidate()
        let t = Timer(timeInterval: Self.hoverLimit, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.dismiss() }
        }
        RunLoop.main.add(t, forMode: .common)
        dismissTimer = t
    }

    func mouseExited() { startDismissTimer() }
}

/// `NSTrackingArea` 的 owner 要收得到 `mouseEntered(with:)` / `mouseExited(with:)`，
/// 那是 `NSResponder` 的方法，所以夾這一層。
/// controller 用 `unowned` 持有它，它反過來 `weak` 指回去 —— tracking area
/// 本身只持有 weak owner，所以 strong reference 必須由 controller 那邊留著。
@MainActor
final class AlertTrackingProxy: NSResponder {
    weak var controller: AlertPanelController?

    override func mouseEntered(with event: NSEvent) { controller?.mouseEntered() }
    override func mouseExited(with event: NSEvent) { controller?.mouseExited() }
}
