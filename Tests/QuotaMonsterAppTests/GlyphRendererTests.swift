import Testing
import AppKit
@testable import QuotaMonsterApp
@testable import QuotaMonsterCore

/// 選單列圖示畫出來的**像素**。
///
/// 這些宣稱以前只寫在註解裡（「像素不與琥珀重疊是結構上的」「有人被擋住時
/// 完成訊號整批丟掉」），或只由診斷指令的 `exit(1)` 守著 —— 而診斷指令
/// 不會在 `bash scripts/test.sh` 裡跑。
@Suite("GlyphRenderer — 畫出來的像素")
@MainActor
struct GlyphRendererTests {

    static let scale = 8

    /// ⚠️ `quota: false` 要**兩個窗口都給 nil** —— `quotaTier` 取的是兩者的
    /// 較小值，只清掉一個的話它仍然有讀數，`usesTemplateRendering` 就不會是 true。
    /// （我第一版只清了 5 小時那一個，對照組當場紅。）
    func state(blocked: Int = 0, glow: FinishGlow = .none, quota: Bool = true) -> GlyphState {
        GlyphState(fiveHourRemaining: quota ? 0.72 : nil,
                   sevenDayRemaining: quota ? 0.82 : nil,
                   runningAgents: 0, blockedSessions: blocked,
                   exhausted: false, freshness: .live, finishGlow: glow)
    }

    /// 把圖示畫進離屏 bitmap。作法與 `--render` 一致。
    func bitmap(_ s: GlyphState, ink: NSColor = .white) -> NSBitmapImageRep {
        let px = Int(GlyphGeometry.canvas) * Self.scale
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        GlyphRenderer.image(for: s, ink: ink)
            .draw(in: NSRect(x: 0, y: 0, width: px, height: px))
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    /// 這個像素接近那個顏色嗎（只看不透明的）。
    func matches(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int,
                 _ target: NSColor, tolerance: Double = 0.12) -> Bool {
        guard let p = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
              p.alphaComponent > 0.5,
              let t = target.usingColorSpace(.sRGB) else { return false }
        return abs(p.redComponent - t.redComponent) < tolerance
            && abs(p.greenComponent - t.greenComponent) < tolerance
            && abs(p.blueComponent - t.blueComponent) < tolerance
    }

    @Test("⚠️ 丁香紫只出現在生物核心 —— 不與琥珀那一圈的半徑重疊")
    func lilacStaysInTheCreatureCore() {
        // 設計說「琥珀在 r=7.25 外圈、丁香在 r≤2.15 核心，像素不重疊」。
        // 那句話以前只是註解。這一則把它變成可以紅的斷言。
        let rep = bitmap(state(glow: .fresh))
        let lilac = SignalPalette.finish(onDark: true)
        var found = 0
        var worst = 0.0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where matches(rep, x, y, lilac) {
                found += 1
                // 像素座標換回 22pt 畫布（bitmap 的 y 是由上往下）。
                let px = Double(x) / Double(Self.scale)
                let py = GlyphGeometry.canvas - Double(y) / Double(Self.scale)
                let r = hypot(px - GlyphGeometry.centre.x, py - GlyphGeometry.centre.y)
                worst = max(worst, r)
            }
        }
        // 先確認它真的畫出來了 —— 否則下面那個斷言在一張空圖上也會過。
        #expect(found > 50, "幾乎找不到丁香紫的像素（只有 \(found) 個），這一則等於沒測")
        #expect(worst < 5.0, "丁香紫跑到 r=\(String(format: "%.1f", worst))，已經進到弧的地盤")
    }

    @Test("⚠️ 染了丁香紫就不可以走 template —— AppKit 只看 alpha，顏色會安靜地消失")
    func glowingGlyphIsNotTemplate() {
        // ⚠️ 這一格**不可以用像素斷言**去抓：離屏 `draw(in:)` 會照實畫出丁香紫，
        // 所以有 bug 的版本像素照樣是紫的。唯一抓得到的是 isTemplate 本身。
        let noQuota = state(glow: .fresh, quota: false)
        #expect(GlyphRenderer.image(for: noQuota, ink: .white).isTemplate == false)
        // 對照：沒有完成訊號、也沒有額度讀數時才走 template。
        #expect(GlyphRenderer.image(for: state(glow: .none, quota: false), ink: .white)
                    .isTemplate == true)
    }

    @Test("警示的渲染路徑根本不碰生物 —— 所以丁香紫在結構上到不了畫面")
    func theAlertPathNeverDrawsTheCreature() {
        // ⚠️ **這一則不是 `creatureGlow` 的守門，不要以為它是。**
        // 我原本把它寫成「有人在等你時完成訊號整批丟掉 → 兩張圖逐 byte 相同」，
        // 然後去驗它：把 `GlyphState.creatureGlow` 的 `isAlerting ? .none :` 拿掉，
        // **這一則照樣過** —— 因為 `image(for:)` 在警示時走 `drawAlert`，
        // 根本不呼叫 `drawCreature`，丁香紫本來就到不了畫面。
        // 守住 `creatureGlow` 的是 Core 的 `alertingSwallowsTheGlow`（那一則會紅）。
        //
        // 保留它是因為它仍然守著另一件事：**將來有人改成「警示時也畫生物」**
        // （例如重新設計成滿環 + 生物），那一刻這一則會紅，而顏色語彙的衝突
        // 就會在合併之前被看見，不是在選單列上。
        let rep = bitmap(state(blocked: 1, glow: .fresh))
        let lilac = SignalPalette.finish(onDark: true)
        var found = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where matches(rep, x, y, lilac) { found += 1 }
        }
        #expect(found == 0, "警示狀態畫出了 \(found) 個丁香紫像素 —— 兩個訊號撞在一起了")
    }

    @Test("沒有完成訊號時，生物身上一點丁香紫都不可以有")
    func noLilacWhenNothingFinished() {
        // 上面那則「只出現在核心」的配對測試：沒有它，一個「永遠畫丁香紫」
        // 的實作只要畫在核心就能通過。
        let rep = bitmap(state(glow: .none))
        let lilac = SignalPalette.finish(onDark: true)
        var found = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where matches(rep, x, y, lilac) { found += 1 }
        }
        #expect(found == 0, "沒有完成訊號卻畫出了 \(found) 個丁香紫像素")
    }

    // ── agent 軌：點就是點，不是一條線 ─────────────────────────
    //
    // ⚠️ 這一段以前**完全沒有測試**。原本每個狀態都會畫一條 alpha 0.48／0.32
    // 的暗軌，理由寫「沒有 agent 時墨水盒才不會縮水」。
    // 〔實測 2026-09-22，使用者回報 + 2x 渲染對照〕那條軌本身就讀成一條線，
    // 而點與它的對比太弱：1～3 隻看起來像「一條線上有幾塊比較亮」，
    // 0 隻則是一條沒有意義的灰線。現在不畫暗軌。
    //
    // 墨水盒確實會縮（〔實測 2x〕idle 從 32px 高變成 27px），但 NSImage 是固定
    // 22×22、狀態列置中的是**圖**不是墨水，所以位置不會跑。

    func agents(_ n: Int) -> GlyphState {
        GlyphState(fiveHourRemaining: 0.72, sevenDayRemaining: 0.82,
                   runningAgents: n, blockedSessions: 0,
                   exhausted: false, freshness: .live)
    }

    /// agent 軌那一帶（生物下方）有多少不透明的像素。
    func railInk(_ s: GlyphState) -> Int {
        let rep = bitmap(s)
        let px = Int(GlyphGeometry.canvas) * Self.scale
        // ⚠️ 取樣框要**只框住 agent 軌**。第一版用「圖的下半部」，結果把兩條弧
        // 的下緣也算進去了（0 隻時就量到 583 個像素）。
        //
        // 軌的幾何：半徑 7.25、−67.65° 到 −112.35°、筆寬 1.50。換算（AppKit，
        // 圓心 11,11、y 向上）：x ∈ [8.24, 13.76]、y ∈ [3.75, 4.30]，各加半個筆寬。
        // 兩條弧在這一帶是**缺口**（−40° 到 −140° 不畫），它們的端點在
        // 外弧 (16.55, 6.34)、內弧 (14.18, 8.33) —— 都在框外。
        let lo = { (v: CGFloat) in Int(v * CGFloat(Self.scale)) }
        let xs = lo(7.0)..<lo(15.0)
        // 螢幕座標 y 向下：y_screen = 22 − y_appkit
        let ys = lo(GlyphGeometry.canvas - 5.5)..<lo(GlyphGeometry.canvas - 2.5)
        var n = 0
        for y in ys where y < px {
            for x in xs where x < px && (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 {
                n += 1
            }
        }
        return n
    }

    @Test("0 隻 agent 時，底部一個像素都不畫")
    func noAgentsMeansNoRail() {
        #expect(railInk(agents(0)) == 0,
                "那條暗軌沒有任何意義，而它讀起來就是一條線")
    }

    @Test("1 隻就有東西，而且比 0 隻多")
    func oneAgentDraws() {
        #expect(railInk(agents(1)) > 0)
    }

    @Test("點數越多墨水越多 —— 1 < 2 < 3")
    func moreAgentsMeansMoreInk() {
        let a = railInk(agents(1)), b = railInk(agents(2)), c = railInk(agents(3))
        #expect(a < b)
        #expect(b < c)
    }

    @Test("4 隻以上合併成滿軌，墨水比 3 個點多")
    func mergedBarIsHeavierThanThreeDots() {
        #expect(railInk(agents(5)) > railInk(agents(3)))
    }

    @Test("5 隻與 15 隻畫出來一樣 —— 那是算術限制，不是品味（既有行為，不可退步）")
    func mergedIsSaturated() {
        #expect(railInk(agents(5)) == railInk(agents(15)))
    }
}
