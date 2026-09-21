import AppKit
import SwiftUI
import QuotaMonsterCore

/// 選單列項目本身。
@MainActor
final class StatusItemController {

    private let item: NSStatusItem
    private let popover = NSPopover()
    private let panel: NSHostingController<PanelView>
    private let store: DataStore
    private var lastRendered: GlyphState?
    /// 上次繪製時選單列是不是深色。外觀改變也要重畫，否則墨色會留在錯的那一邊。
    private var lastInkWasDark: Bool?
    private var breath = BreathController(
        reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
        lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
    private var animator: BreathAnimator?
    private var finishBlink = FinishBlinkController()
    private let preferences = PreferencesWindow()
    private var pulseTimer: Timer?
    private var pulseFrames: [NSImage] = []
    private var pulseBase: NSImage?
    private var pulseIndex = 0

    init(store: DataStore) {
        self.store = store
        panel = NSHostingController(rootView: PanelView(store: store))
        // ⚠️ 固定寬度，**絕不使用 .variableLength**。
        // 寬度會變的 status item 會在每次 agent 開始或結束時推動選單列上所有鄰居。
        item = NSStatusBar.system.statusItem(withLength: GlyphGeometry.canvas)

        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = panel
        // 齒輪：先收起 popover（它是 .transient），再開設定視窗。
        // ⚠️ 先收再開這個順序是**推論**，沒有實機驗證；但 `.transient` 的文件
        // 說「與 popover 以外的元素互動時自動關閉」，賭它不值得。
        panel.rootView.openPreferences = { [weak self] in
            guard let self else { return }
            self.popover.performClose(nil)
            self.preferences.show(store: store)
        }

        item.button?.target = self
        item.button?.action = #selector(togglePanel)
        animator = BreathAnimator { [weak item] image in item?.button?.image = image }
        render()
        checkWidthGuard()
    }

    /// 非 template 狀態下「黑色筆畫」要用的顏色。
    ///
    /// ⚠️ 平常有顏色之後圖示就不再是 template image，AppKit 不會再幫我們翻色。
    /// 深色選單列上畫黑色 = 圖示直接消失。所以要自己問選單列按鈕現在是什麼外觀。
    ///
    /// 問的是 `button.effectiveAppearance` 而不是 `NSApp.effectiveAppearance`：
    /// 前者才是那顆按鈕真正被畫上去的環境。
    private var inkIsDark: Bool {
        let appearance = item.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    func render() {
        let state = store.glyph
        let wasAlerting = lastRendered?.isAlerting ?? false
        let dark = inkIsDark

        // 排程判斷每次都要跑（它靠時間推進，不只靠狀態變化）。
        if breath.update(blockedCount: state.blockedSessions, now: Date()) {
            animator?.start(state: state)
        }
        // ⚠️ 餵**原始欄位** `finishGlow`，不是 `creatureGlow`。
        // `creatureGlow` 在有人被擋住時是 `.none`，所以警示一解除它就會走
        // `.none → .fresh` —— 那會在「你剛回答完問題」的那一拍補一次眨眼，
        // 而完成訊號的規矩是**丟掉不是排隊**。
        //
        // ⚠️ 這一行必須在下面那個「狀態沒變就跳過」的 guard **之前**，
        // 否則衰退到 `.none` 的那一拍會被擋掉，下一次完成就不會眨眼了。
        let blink = finishBlink.update(glow: state.finishGlow)
        if wasAlerting && !state.isAlerting {
            animator?.stop()          // 離開不做轉場
        }

        // 狀態沒變、外觀也沒變才可以跳過重畫。
        guard state != lastRendered || dark != lastInkWasDark else { return }
        lastRendered = state
        lastInkWasDark = dark
        item.button?.toolTip = tooltip(state)

        // ⚠️ 要重畫了，就先把 pulse 停掉。
        //
        // 一次性動畫捕捉的是**開始時**那張圖，結束時會把它還原回去。
        // 狀態在中途改變的話，還原等於把一張舊圖蓋回來，而且要撐到下一次
        // 狀態改變為止。
        //
        // ⚠️ 這裡原本寫著「T2 的 pulse 正好在一批 agent 跑完時發，而那一刻
        // runningAgents 本來就變了」——〔算術，非觀測〕那個時序不成立：
        // 合併視窗 4 秒 > 輪詢 3 秒，所以事件要到第 N+2 拍才送出，而 render()
        // 早在 6 秒前就把那次 runningAgents 變化消化掉了。真正會撞的是
        // 動畫那 1.5 秒內**任何其他**狀態變化（下一階段的 agent 開跑、
        // 額度分級變了、freshness 翻面），而這一行擋的就是那個。
        cancelPulse()

        // 呼吸中的話，畫面由 animator 接管，不要在這裡覆蓋掉它。
        if animator?.isRunning != true {
            let ink: NSColor = dark ? .white : .black
            item.button?.image = GlyphRenderer.image(for: state, ink: ink)
            // 眨一次眼。⚠️ 有人在等你的時候不眨 —— 那件事比較急，而且
            // `creatureGlow` 已經把丁香紫蓋掉了，眨了也只是整張圖暗一下。
            if blink && !state.isAlerting { blinkFinish(state, ink: ink) }
        }
    }

    /// 「眨完睜開變了個樣子」——**不是閃一下**。
    ///
    /// 換色發生在最暗的那一格，所以使用者看到的是一次眨眼，而不是一次閃爍；
    /// 動畫的終點值就是物件的靜止值。曲線與警示狀態共用同一條 `Breath`，
    /// 但只跑**一個**週期（警示是四次爆發）—— 同一種節奏代表「同一個 app 在說話」，
    /// 次數的差別代表「這件事沒那麼急」。
    private func blinkFinish(_ state: GlyphState, ink: NSColor) {
        let before = GlyphRenderer.image(for: state.with(finishGlow: .none), ink: ink)
        let after = GlyphRenderer.image(for: state, ink: ink)
        let mid = Breath.frameCount / 2
        let frames = (0..<Breath.frameCount).map { i in
            Self.dimmed(i < mid ? before : after, to: CGFloat(Breath.opacity(atFrame: i)))
        }
        play(frames: frames, settlingOn: after)
    }

    // ── 通知層要的兩件事 ───────────────────────────────────────

    /// 選單列圖示在螢幕座標裡的位置。警示浮窗錨在這裡 ——
    /// 眼睛本來就要往選單列去，就在那裡接住它。
    var screenAnchor: NSRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    /// T2／T3 的**瞬時訊號**：一次呼吸，然後消失。
    ///
    /// 與警示狀態刻意共用 `Breath` 的曲線，但只跑**一個**週期（警示是四次爆發）。
    /// 同一種節奏代表「同一個 app 在說話」，次數的差別代表「這件事沒那麼急」。
    ///
    /// ⚠️ 跑完就 `invalidate` 並釋放整個 frame 陣列，不是暫停 ——
    /// 這個 app 在動的那幾秒之外不留任何重複性計時器。
    /// - Returns: **真的播了嗎。**
    ///
    /// ⚠️ 它會因為四個理由安靜地不播（減少動態、低耗電、警示中讓路、還在播）。
    /// 對 T2 的**失敗**那一批來說，圖示是唯一的通道（失敗刻意不出聲），
    /// 所以「沒播」等於那一則事件完全沒有留下痕跡 —— 呼叫端必須知道。
    @discardableResult
    func pulse() -> Bool {
        guard let base = item.button?.image else { return false }
        return play(frames: (0..<Breath.frameCount).map { i in
            Self.dimmed(base, to: CGFloat(Breath.opacity(atFrame: i)))
        }, settlingOn: base)
    }

    /// 放一段一次性的動畫，結束停在 `final`。
    ///
    /// ⚠️ **進場一定要自己畫 frame 0。** `pulseTick()` 是先 `pulseIndex += 1`
    /// 才取圖，所以 frame 0 從來不由計時器畫出來。`pulse()` 沒事（它的 frame 0
    /// 就是當下那張圖），但眨眼的 frame 0 是「換色前」那一張 —— 少了這一行，
    /// 使用者會看到「滿色丁香 → 突然跳回舊色 → 淡下去 → 再變丁香」。
    @discardableResult
    private func play(frames: [NSImage], settlingOn final: NSImage) -> Bool {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              !ProcessInfo.processInfo.isLowPowerModeEnabled,
              animator?.isRunning != true,      // 警示中就不要插隊，那件事比較重要
              pulseTimer == nil,                // 播放中不插隊
              let first = frames.first else { return false }

        // 可變狀態放實例屬性，不放 closure 的區域變數 ——
        // Swift 6 會把跨隔離邊界的可變捕獲當成資料競爭，而它是對的。
        pulseFrames = frames
        pulseBase = final
        pulseIndex = 0
        item.button?.image = first
        let t = Timer(timeInterval: 1.0 / Breath.frameRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pulseTick() }
        }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        pulseTimer = t
        return true
    }

    private func pulseTick() {
        pulseIndex += 1
        guard pulseIndex < Breath.frameCount, pulseIndex < pulseFrames.count else {
            // 回到原圖才收工 —— 動畫的終點值就是物件的靜止值。
            let base = pulseBase
            cancelPulse()
            item.button?.image = base
            return
        }
        item.button?.image = pulseFrames[pulseIndex]
    }

    /// 停掉 pulse 並釋放 frame，**不還原圖片** —— 呼叫端自己決定要畫什麼。
    private func cancelPulse() {
        pulseTimer?.invalidate()
        pulseTimer = nil
        pulseFrames = []
        pulseBase = nil
        pulseIndex = 0
    }

    /// 整張圖降透明度。刻意用 `draw(in:from:operation:fraction:)` ——
    /// ⚠️ **這裡不可以出現任何仿射變換 API**，見
    /// `~/.claude/retrospectives/2026-09-18_quotamonster_silcombine-crash.md`。
    private static func dimmed(_ image: NSImage, to fraction: CGFloat) -> NSImage {
        let out = NSImage(size: image.size)
        out.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size),
                   from: .zero, operation: .sourceOver, fraction: fraction)
        out.unlockFocus()
        out.isTemplate = image.isTemplate
        return out
    }

    /// Stage 0 實測：60pt 的項目會被靜默推到 y = -33（螢幕外），
    /// `isVisible` 仍然回 true，沒有錯誤也沒有 callback。
    /// 22pt 目前安全，但選單列愈擠愈可能中招 —— 中了要明講，否則會被當成 crash。
    private func checkWidthGuard() {
        guard let y = item.button?.window?.frame.origin.y, y < 0 else { return }
        NSLog("QuotaMonster: 圖示被選單列空間擠掉了（window.origin.y = \(y)）。"
              + "請關掉一些選單列 app，或使用 Ice/Bartender 之類的工具整理。")
    }

    private func tooltip(_ s: GlyphState) -> String {
        var parts: [String] = []
        if let f = s.fiveHourRemaining { parts.append("5 小時剩 \(Int(f * 100))%") }
        if let d = s.sevenDayRemaining { parts.append("7 天剩 \(Int(d * 100))%") }
        parts.append("\(s.runningAgents) 隻 agent 在跑")
        if s.blockedSessions > 0 { parts.append("⚠︎ \(s.blockedSessions) 個 session 在等你") }
        if s.freshness == .expired { parts.append("（讀數已過期）") }
        return parts.joined(separator: " · ")
    }

    @objc private func togglePanel() {
        guard let button = item.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.refresh()
            popover.contentSize = panelSize()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    /// ⚠️ **展開之前一定要自己算尺寸並指派給 `popover.contentSize`。**
    ///
    /// 不指派的話 `NSPopover` 會一直用它 320×320 的預設值，而且 SwiftUI 不會把它改過來
    /// （實測等 1.5 秒後 `contentSize` 仍然是 320×320）。後果有兩個，而且都看得出來：
    ///   1. 面板被壓扁 —— 內容只剩 345pt 高，session 清單被擠掉
    ///   2. **面板往上長進選單列** —— 實測 popover 視窗頂緣落在 y = 953，
    ///      而選單列底緣是 y = 923，整整重疊 30pt
    ///
    /// 指派之後頂緣回到 y = 928：只剩箭頭尖端指向選單列項目（本來就該這樣），
    /// 圓角本體離選單列底緣還有約 8pt。
    ///
    /// 量測方式見 `QuotaMonsterApp --probe-popover`。
    private func panelSize() -> NSSize {
        var size = panel.view.fittingSize
        // 再保險一層：面板永遠不可以高過選單列以下的可用高度。
        // 內容真的變那麼高時（session 很多），由 PanelView 裡的 ScrollView 吸收。
        if let screen = item.button?.window?.screen ?? NSScreen.main {
            size.height = min(size.height, screen.visibleFrame.height - 24)
        }
        return size
    }
}
