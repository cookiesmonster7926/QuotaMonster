import AppKit
import QuotaMonsterCore

/// 把 `GlyphState` 畫成 22×22pt 的 `NSImage`。
///
/// 幾何全部來自 `GlyphGeometry`（純函式、已測）。這裡只負責落筆。
///
/// 座標：規格用 y 向下，AppKit 的 NSImage 繪圖是 y 向上，所以所有 y 都用 `up(_:)` 轉換。
/// 角度用數學慣例（0° = 正右，逆時針為正），與 AppKit 一致，不需轉換。
private extension NSColor {
    /// 這支筆是淺色的嗎（＝我們正畫在深色選單列上）。
    var isLight: Bool {
        (usingColorSpace(.deviceRGB)?.brightnessComponent ?? 0) > 0.5
    }
}

enum GlyphRenderer {

    static let size = NSSize(width: GlyphGeometry.canvas, height: GlyphGeometry.canvas)
    static let c = GlyphGeometry.centre

    /// 警示色 —— 「有人在等你輸入」專用。
    ///
    /// ⚠️ **黃／琥珀在這個 app 裡只代表這件事。** 額度色階（`tierColour`）
    /// 不得使用任何黃色，否則這個訊號就被稀釋了。
    static let alert = NSColor(srgbRed: 1.00, green: 0.62, blue: 0.04, alpha: 1)

    /// 額度分級的顏色。定義在 `QuotaPalette` —— 與下拉面板的進度條共用同一份，
    /// 免得兩邊變成兩套語彙。
    ///
    /// ⚠️ 這裡原本寫「`tight` 的黃刻意比 `alert` 的琥珀更黃，但兩者色相仍然相鄰」。
    /// **那是 2026-09-18 下午改色階之前的殘留，今天不成立** —— 現在的 `tight`
    /// 是**綠色**，而且上面八行就寫著「額度色階不得使用任何黃色」。
    ///
    /// 仍然成立的是那句話原本要保護的東西：**警示狀態不是靠顏色跟這裡區分的**，
    /// 它是完全不同的形狀（滿環 + 箭頭），而且是唯一會呼吸的。
    static func tierColour(_ tier: QuotaTier, onDark: Bool = false) -> NSColor {
        QuotaPalette.nsColor(tier, onDark: onDark)
    }

    /// - Parameters:
    ///   - ink: 非 template 狀態下「黑色筆畫」要用的顏色。走 template 時 AppKit
    ///     只看 alpha 會自動翻色，不走 template 時就得自己給 —— 深色選單列要白、
    ///     淺色要黑，否則圖示會直接消失在背景裡。由 `StatusItemController` 依
    ///     `button.effectiveAppearance` 解析後傳進來。
    ///   - chevronOpacity: 只有 chevron 群組會改變不透明度。
    ///     外圈、keyline、底下的量表都不動 —— 這是呼吸動畫唯一被允許改的東西。
    static func image(for state: GlyphState, ink: NSColor = .black,
                      chevronOpacity: Double = 1.0) -> NSImage {
        // 一律用 ink 落筆。走 template 時 AppKit 只取 alpha，用什麼顏色都一樣，
        // 但這樣離線渲染（--render --dark）畫出來的才是選單列上真正的樣子。
        let pen = ink
        let onDark = ink.isLight
        let tint = state.quotaTier.map { tierColour($0, onDark: onDark) }
        let img = NSImage(size: size, flipped: false) { _ in
            if state.isAlerting {
                drawAlert(state, chevronOpacity: chevronOpacity)
            } else {
                drawGauges(state, ink: pen, tint: tint)
                drawAgentRail(state, ink: pen)
                // ⚠️ 生物**不染色**。實測在 22pt 的選單列上，弧線與生物都染同一個顏色
                // 會變成一坨同色的東西，兩條弧與生物的界線全部消失 ——
                // 單色版本原本是靠黑白對比把結構分開的。
                // 顏色只給「額度本身」，也就是亮起來的那段弧。
                drawCreature(state, ink: pen)
            }
            return true
        }
        // 警示狀態用不透明的顏色 —— 桌布的半透明染色對它完全無關，
        // 那正是唯一有時限的狀態需要的性質。
        img.isTemplate = state.usesTemplateRendering
        return img
    }

    // ── 量表 ───────────────────────────────────────────────────

    private static func drawGauges(_ state: GlyphState, ink: NSColor, tint: NSColor?) {
        // ⚠️ 暗軌的透明度必須看墨色深淺分兩組。
        // 0.24 的黑畫在淺色列上是清楚的淺灰，但 0.24 的白畫在深色列上幾乎消失 ——
        // 實測整顆圖示會比旁邊的鄰居淡一截，看起來像沒對到焦。
        let onDark = ink.isLight
        let base: CGFloat = onDark ? 0.40 : 0.24
        let dim = state.freshness == .expired ? base * 0.66 : base
        let lit = state.freshness == .expired ? 0.45 : 1.0

        draw(band: GlyphGeometry.outerArc, remaining: state.fiveHourRemaining,
             dim: dim, lit: lit, ink: ink, tint: tint)
        draw(band: GlyphGeometry.innerArc, remaining: state.sevenDayRemaining,
             dim: dim, lit: lit, ink: ink, tint: tint)
    }

    private static func draw(band: GlyphGeometry.Band, remaining: Double?,
                             dim: CGFloat, lit: CGFloat,
                             ink: NSColor, tint: NSColor?) {
        // 暗軌永遠在 —— 一條耗盡的弧不能讀成渲染失敗。
        let track = arcPath(radius: band.centreline, arc: GlyphGeometry.gaugeArc(remaining: 1))
        track.lineWidth = band.stroke
        track.lineCapStyle = .round
        ink.withAlphaComponent(dim).setStroke()
        track.stroke()

        // 不知道就只畫軌道。空的量表與「沒有讀數」必須看得出來不同。
        guard let remaining else { return }

        let a = GlyphGeometry.gaugeArc(remaining: remaining)
        if a.sweep > 0.5 {
            let p = arcPath(radius: band.centreline, arc: a)
            p.lineWidth = band.stroke
            p.lineCapStyle = .round
            (tint ?? ink).withAlphaComponent(lit).setStroke()
            p.stroke()
        }

        // 50% 標記：直徑等於筆寬，坐在中線上，內外都不凸出。
        // 靠 alpha 階差被看見 —— 幾何上它禁止用大小或凸出來區分。
        let m = point(radius: band.centreline, degrees: GlyphGeometry.halfMarkAngle)
        let d = band.halfMarkDiameter
        let disc = NSBezierPath(ovalIn: NSRect(x: m.x - d / 2, y: m.y - d / 2, width: d, height: d))
        let covered = remaining >= 0.5
        (tint ?? ink).withAlphaComponent(covered ? lit * 0.42 : lit).setFill()
        disc.fill()
    }

    // ── agent ──────────────────────────────────────────────────

    private static func drawAgentRail(_ state: GlyphState, ink: NSColor) {
        let rail = GlyphGeometry.agentRail
        let r = GlyphGeometry.outerArc.centreline
        let w = GlyphGeometry.outerArc.stroke

        // 暗軌在每個狀態都畫 —— 沒有 agent 時墨水盒才不會縮水。
        let track = arcPath(radius: r, arc: rail)
        track.lineWidth = w
        track.lineCapStyle = .round
        ink.withAlphaComponent(ink.isLight ? 0.48 : 0.32).setStroke()
        track.stroke()

        ink.setFill()
        switch GlyphGeometry.agentUnits(count: state.runningAgents) {
        case .none:
            break
        case .discrete(let angles):
            for a in angles {
                let p = point(radius: r, degrees: a)
                let d = w
                NSBezierPath(ovalIn: NSRect(x: p.x - d / 2, y: p.y - d / 2,
                                            width: d, height: d)).fill()
            }
        case .merged:
            let bar = arcPath(radius: r, arc: rail)
            bar.lineWidth = w
            bar.lineCapStyle = .round
            ink.setStroke()
            bar.stroke()
        }
    }

    // ── 生物 ───────────────────────────────────────────────────

    private static func drawCreature(_ state: GlyphState, ink: NSColor) {
        let p = state.posture
        let foot = up(12.90)                     // 腳下，所有變形的錨點

        /// 規格座標 → 已套用姿態的 AppKit 座標。
        func y(_ specY: CGFloat) -> CGFloat {
            foot + (up(specY) - foot) * p.squashY + p.rise
        }
        // 前傾用冠部水平位移近似，不用旋轉 —— 見下方註解。
        let tilt: CGFloat = p.leanDegrees == 0 ? 0 : 0.28

        let path = NSBezierPath()
        // 身體：圓角矩形。頂邊留在谷底高度，兩顆冠葉再疊上去，
        // 聯集之後就是「兩個圓丘 + 一道淺谷」，而且沒有任何頂點。
        let top = y(9.858), bottom = y(12.90)
        path.append(NSBezierPath(roundedRect: NSRect(x: 8.95, y: bottom,
                                                     width: 4.10, height: top - bottom),
                                 xRadius: 0.95, yRadius: 0.95))
        let r: CGFloat = 0.95
        let lobeY = y(10.35)
        for cx in [9.90 + tilt, 12.10 + tilt] {
            path.append(NSBezierPath(ovalIn: NSRect(x: cx - r, y: lobeY - r,
                                                    width: r * 2, height: r * 2)))
        }
        path.windingRule = .nonZero

        // 生物平常不染色（理由在 `image(for:)` 那一段），**唯一的例外是「剛完成」**。
        // 使用者 2026-09-19 拍板：完成訊號放在生物身上，因為那是整顆圖示裡唯一
        // 沒有被任何語意佔用的表面 —— 它只編碼姿態，從未編碼顏色。
        // 像素不與琥珀重疊是**結構上**的：警示狀態走的是 drawAlert，
        // 根本不經過這個函式。
        switch state.creatureFill {
        case .ink(let alpha):
            ink.withAlphaComponent(alpha).setFill()
        case .glow(let glow):
            (SignalPalette.nsColor(glow, onDark: ink.isLight, ink: ink) ?? ink).setFill()
        }
        path.fill()
    }

    // ⚠️ 為什麼這裡沒有任何 transform API：
    // 實測在 `-O` 下，只要 GlyphRenderer 裡有一個函式對路徑套用仿射變換，
    // swift-frontend 就會在 SILCombine 階段 segfault（signal 10/11，
    // Swift 6.3.3 / CommandLineTools）。三種 transform 型別都試過
    // （NSAffineTransform / Foundation.AffineTransform / CGAffineTransform），
    // `@inline(never)` 也試過，把 switch 移進 Core 也試過 —— 全都照炸。
    // debug 建置則完全正常。
    // 有效的做法是**根本不用 transform**：依姿態直接算出最終座標。
    // 代價是 5° 前傾改用冠部水平位移近似，在 22pt 下看不出差別。

    // ── 警示 ───────────────────────────────────────────────────

    private static func drawAlert(_ state: GlyphState, chevronOpacity: Double) {
        let band = GlyphGeometry.outerArc
        alert.setStroke()

        switch GlyphGeometry.alertSegments(blocked: state.blockedSessions) {
        case .closedRing:
            let p = NSBezierPath(ovalIn: NSRect(x: c.x - band.centreline, y: c.y - band.centreline,
                                                width: band.centreline * 2,
                                                height: band.centreline * 2))
            p.lineWidth = band.stroke
            p.stroke()
        case .segments(let segs):
            for s in segs {
                let p = arcPath(radius: band.centreline, arc: s)
                p.lineWidth = band.stroke
                p.lineCapStyle = .round
                p.stroke()
            }
        }

        // 三個向右的 chevron。頂點用真正的圓弧 fillet，
        // 不用 linejoin:round —— 那只磨圓外側，內側還是尖的。
        //
        // 呼吸動畫只改這一群的不透明度。外圈與量表永遠不動。
        alert.withAlphaComponent(CGFloat(chevronOpacity)).setStroke()
        for (i, x) in [7.6, 10.2, 12.8].enumerated() {
            _ = i
            let p = NSBezierPath()
            p.move(to: NSPoint(x: x, y: up(7.8)))
            p.line(to: NSPoint(x: x + 2.4, y: c.y))
            p.line(to: NSPoint(x: x, y: up(14.2)))
            p.lineWidth = 1.5
            p.lineCapStyle = .round
            p.lineJoinStyle = .round
            p.stroke()
        }
    }

    // ── 幾何小工具 ─────────────────────────────────────────────

    /// 規格用 y 向下，AppKit 繪圖是 y 向上。
    private static func up(_ y: CGFloat) -> CGFloat { GlyphGeometry.canvas - y }

    private static func point(radius: CGFloat, degrees: Double) -> NSPoint {
        let r = degrees * .pi / 180
        return NSPoint(x: c.x + radius * cos(r), y: c.y + radius * sin(r))
    }

    private static func arcPath(radius: CGFloat, arc: GlyphGeometry.Arc) -> NSBezierPath {
        let p = NSBezierPath()
        p.appendArc(withCenter: c, radius: radius,
                    startAngle: arc.start, endAngle: arc.end, clockwise: true)
        return p
    }
}
