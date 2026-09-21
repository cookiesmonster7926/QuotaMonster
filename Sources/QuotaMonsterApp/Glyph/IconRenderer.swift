import AppKit
import QuotaMonsterCore

/// Finder / DMG / 系統設定裡那一顆 app icon。
///
/// ### ⚠️ 這不是選單列那個圖示，而且**刻意**不共用 `GlyphRenderer`
/// 選單列圖示是 template（只有 alpha 有意義）、22pt、一條亮弧代表「還剩多少」。
/// app icon 是一張 1024px 的彩圖、要在 Dock 與 Finder 裡站得住、而且是**靜態**的 ——
/// 規矩 2 說得很清楚：靜態圖必須挑定一個狀態，而挑哪一個是設計決定，不是資料決定。
///
/// 這裡挑的是「**把整條額度色階畫出來**」：外弧不是某個當下的讀數，而是
/// 完整的 220° → −40° 掃掠，依 `QuotaThresholds.standard` 切成三段。
/// 一眼說明這個 app 在量什麼。
///
/// ### 為什麼幾何要從 `GlyphGeometry` 拿
/// 直接抄常數的話，哪天選單列的幾何調整了，icon 會靜靜地變成另一個東西 ——
/// 而沒有任何測試會紅（icon 是離線產生的 .icns，不參與執行期）。
/// 從 Core 取值讓它們**不可能漂走**，代價只是多幾個 `GlyphGeometry.` 前綴。
///
/// ⚠️ 三段的角度不是隨手三等分：`critical < 20%`、`tight < 50%`。
/// `220 − 0.20×260 = 168°`（紅/綠界）、`220 − 0.50×260 = 90°`（綠/藍界）——
/// 而 90° 正好是 `GlyphGeometry.halfMarkAngle`，也就是那顆 50% 標記點。
/// 同一套幾何，不是湊出來的巧合。
///
/// ### ⚠️ 規矩 26：不得使用任何仿射變換 API
/// Swift 6.3.3 的 `-O` 在 `GlyphRenderer` 裡碰到 `NSAffineTransform` 會
/// SILCombine segfault。這裡雖然是另一個型別，但縮放同樣**只用座標乘法**，
/// 不引入 transform —— 沒有理由賭它在這個檔案裡是安全的。
@MainActor
enum IconRenderer {

    // ── macOS 26/27 的外框比例 ──────────────────────────────────
    //
    // 〔實測 2026-09-21〕拆開 Notes.app / Google Chrome.app / LINE.app 的 256px icon：
    // 三個獨立廠商的角落 alpha 全部是 0、中心 255，以 alpha>0.9 量不透明本體，
    // Notes 與 LINE 都是 204×204 落在 (26,26)–(229,229)，Chrome 是 206×206。
    // 換算到 1024 畫布：**本體 816×816、四邊各留 104px**（本體/畫布 = 0.797）。
    //
    // ⚠️ 圓角遮罩**不是系統套的，是畫進圖裡的** —— 所以這支程式必須自己畫出圓角。
    static let canvas: CGFloat = 1024
    static let bodyInset: CGFloat = 104
    static var bodySize: CGFloat { canvas - bodyInset * 2 }

    // ── 顏色 ───────────────────────────────────────────────────
    //
    // ⚠️ 規矩 24：琥珀／黃只代表「有人在等你輸入」。app icon 不得使用，
    // 否則就把整個 app 唯一有時限的訊號花掉了。
    // 三段用的是 `QuotaPalette` 深底那一組的同一批值。
    static let critical = rgb(0xFF, 0x61, 0x5C)
    static let tight    = rgb(0x4C, 0xD6, 0x7A)
    static let comfort  = rgb(0x29, 0x75, 0xF2)
    static let bgTop    = rgb(0x2A, 0x2A, 0x30)
    static let bgBottom = rgb(0x14, 0x14, 0x17)

    static func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255,
                blue: CGFloat(b) / 255, alpha: 1)
    }

    /// 內弧亮起來的比例。**這是設計決定**：一個「還很寬裕」的狀態，
    /// 讓生物與外圈的三色階之間有一條藍色的弧把兩者連起來。
    static let innerLitFraction: Double = 0.78

    // ── 畫 ─────────────────────────────────────────────────────

    /// - Parameter px: 邊長（像素）。1024 是主尺寸，小尺寸**各自原生渲染**，
    ///   不從大圖縮 —— 向量在小尺寸重畫比降取樣清楚。
    static func draw(px: CGFloat) {
        let s = px / canvas                    // 畫布 → 像素
        let inset = bodyInset * s
        let body = bodySize * s

        // 1. 圓角本體 + 漸層
        let shape = squircle(in: NSRect(x: inset, y: inset, width: body, height: body))
        NSGraphicsContext.saveGraphicsState()
        shape.addClip()
        NSGradient(starting: bgTop, ending: bgBottom)?
            .draw(in: NSRect(x: 0, y: 0, width: px, height: px), angle: -90)
        NSGraphicsContext.restoreGraphicsState()

        // 2. 圖形本體。22pt 的畫布映射到 body 這個方框。
        let u = body / GlyphGeometry.canvas    // 一個 pt 有幾像素
        let c = NSPoint(x: inset + GlyphGeometry.centre.x * u,
                        y: inset + GlyphGeometry.centre.y * u)

        let outer = GlyphGeometry.outerArc
        let inner = GlyphGeometry.innerArc
        let start = GlyphGeometry.gaugeStart
        let sweep = GlyphGeometry.gaugeFullSweep

        let track = NSColor(white: 1, alpha: 0.18)

        // 暗軌（兩條弧的完整掃掠）
        stroke(c: c, r: outer.centreline * u, w: outer.stroke * u,
               from: start, sweep: sweep, colour: track, round: true)
        stroke(c: c, r: inner.centreline * u, w: inner.stroke * u,
               from: start, sweep: sweep, colour: track, round: true)

        // agent 軌（底部開口裡那一段）
        let rail = GlyphGeometry.agentRail
        stroke(c: c, r: outer.centreline * u, w: outer.stroke * u,
               from: rail.start, sweep: rail.sweep, colour: track, round: true)

        // 3. 外弧的三色階。
        //
        // ⚠️ 段與段之間用 **butt**，只有整條弧的兩個外端補圓 ——
        // 每段都圓端的話，相鄰的圓端會互相覆蓋，把色界推移約 6°（1024 下約 40px），
        // 而那個位移剛好會把綠/藍界從 50% 標記點上挪開，看起來就只是「畫歪了」。
        let thresholds = QuotaThresholds.standard
        let segments: [(Double, Double, NSColor)] = [
            (start, sweep * thresholds.critical, critical),
            (start - sweep * thresholds.critical,
             sweep * (thresholds.tight - thresholds.critical), tight),
            (start - sweep * thresholds.tight,
             sweep * (1 - thresholds.tight), comfort),
        ]
        for (from, sw, colour) in segments {
            stroke(c: c, r: outer.centreline * u, w: outer.stroke * u,
                   from: from, sweep: sw, colour: colour, round: false)
        }
        dot(c: c, r: outer.centreline * u, angle: start,
            diameter: outer.stroke * u, colour: critical)
        dot(c: c, r: outer.centreline * u, angle: start - sweep,
            diameter: outer.stroke * u, colour: comfort)

        // 4. 內弧亮起來的那一段
        stroke(c: c, r: inner.centreline * u, w: inner.stroke * u,
               from: start, sweep: sweep * innerLitFraction, colour: comfort, round: true)

        // 5. 兩個 50% 標記。剩餘 > 50% 時被亮弧蓋過，只靠 alpha 階差被看見。
        dot(c: c, r: outer.centreline * u, angle: GlyphGeometry.halfMarkAngle,
            diameter: outer.halfMarkDiameter * u,
            colour: NSColor(white: 1, alpha: 0.42))
        dot(c: c, r: inner.centreline * u, angle: GlyphGeometry.halfMarkAngle,
            diameter: inner.halfMarkDiameter * u,
            colour: comfort.withAlphaComponent(0.42))

        // 6. 一隻 agent 在跑
        dot(c: c, r: outer.centreline * u, angle: -90,
            diameter: outer.stroke * u, colour: comfort)

        // 7. 生物
        creature(inset: inset, u: u).fill()
    }

    // ── 零件 ───────────────────────────────────────────────────

    /// 超橢圓（squircle）。macOS 的圓角不是圓弧，用圓角矩形畫會看得出來。
    /// 〔算術核對，非 Apple 規格〕n = 5 是這個形狀常見的近似值；
    /// 在 204px 本體上量到的圓角約 41–42px 與它相符，但那個量法對超橢圓會低估，
    /// 所以這裡**不宣稱**它逐像素等於 Apple 的遮罩。
    static func squircle(in rect: NSRect, n: CGFloat = 5) -> NSBezierPath {
        let p = NSBezierPath()
        let a = rect.width / 2
        let cx = rect.midX, cy = rect.midY
        let steps = 720
        for i in 0...steps {
            let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
            let ct = cos(t), st = sin(t)
            let x = cx + a * (ct < 0 ? -1 : 1) * pow(abs(ct), 2 / n)
            let y = cy + a * (st < 0 ? -1 : 1) * pow(abs(st), 2 / n)
            if i == 0 { p.move(to: NSPoint(x: x, y: y)) } else { p.line(to: NSPoint(x: x, y: y)) }
        }
        p.close()
        return p
    }

    static func stroke(c: NSPoint, r: CGFloat, w: CGFloat,
                       from: Double, sweep: Double, colour: NSColor, round: Bool) {
        guard sweep > 0 else { return }
        let p = NSBezierPath()
        p.appendArc(withCenter: c, radius: r,
                    startAngle: CGFloat(from), endAngle: CGFloat(from - sweep),
                    clockwise: true)
        p.lineWidth = w
        p.lineCapStyle = round ? .round : .butt
        colour.setStroke()
        p.stroke()
    }

    static func dot(c: NSPoint, r: CGFloat, angle: Double,
                    diameter: CGFloat, colour: NSColor) {
        let t = CGFloat(angle) * .pi / 180
        let centre = NSPoint(x: c.x + r * cos(t), y: c.y + r * sin(t))
        colour.setFill()
        NSBezierPath(ovalIn: NSRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2,
                                    width: diameter, height: diameter)).fill()
    }

    /// 出貨幾何的三個 path 的聯集（與 `GlyphRenderer.drawCreature` 同一組數字）：
    /// 圓角矩形 x 8.95…13.05、y 9.10…12.142（AppKit 座標，y 向上）、圓角半徑 0.95，
    /// 外加兩顆半徑 0.95、圓心 (9.90, 11.65) 與 (12.10, 11.65) 的圓。
    static func creature(inset: CGFloat, u: CGFloat) -> NSBezierPath {
        func P(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: inset + x * u, y: inset + y * u)
        }
        let p = NSBezierPath()
        let body = NSRect(x: P(8.95, 9.10).x, y: P(8.95, 9.10).y,
                          width: 4.10 * u, height: (12.142 - 9.10) * u)
        p.append(NSBezierPath(roundedRect: body, xRadius: 0.95 * u, yRadius: 0.95 * u))
        for cx in [CGFloat(9.90), CGFloat(12.10)] {
            let centre = P(cx, 11.65)
            p.append(NSBezierPath(ovalIn: NSRect(x: centre.x - 0.95 * u, y: centre.y - 0.95 * u,
                                                 width: 1.90 * u, height: 1.90 * u)))
        }
        p.windingRule = .nonZero
        NSColor.white.setFill()
        return p
    }

    // ── 輸出 ───────────────────────────────────────────────────

    /// 寫出一整個 `.iconset` 目錄。
    ///
    /// ⚠️ 十個成員**各自原生渲染**，不從 1024 降取樣 —— 全程是 `NSBezierPath`，
    /// 在目標尺寸重畫比縮圖清楚，尤其 16/32 那幾個。
    static let members: [(String, CGFloat)] = [
        ("icon_16x16",       16), ("icon_16x16@2x",     32),
        ("icon_32x32",       32), ("icon_32x32@2x",     64),
        ("icon_128x128",    128), ("icon_128x128@2x",  256),
        ("icon_256x256",    256), ("icon_256x256@2x",  512),
        ("icon_512x512",    512), ("icon_512x512@2x", 1024),
    ]

    static func run(directory: String) {
        let dir = URL(fileURLWithPath: directory)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var written = 0
        for (name, px) in members {
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current?.imageInterpolation = .high
            draw(px: px)
            NSGraphicsContext.restoreGraphicsState()
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            try? png.write(to: dir.appendingPathComponent("\(name).png"))
            written += 1
            print("  \(name).png  \(Int(px))×\(Int(px))")
        }
        // 規矩 28：診斷宣稱畫了什麼就必須真的畫。少一個就是失敗，不是警告。
        guard written == members.count else {
            FileHandle.standardError.write(
                "✗ 只寫出 \(written)/\(members.count) 個成員\n".data(using: .utf8)!)
            exit(1)
        }
        print("✓ \(written) 個成員寫到 \(dir.path)")
        print("  接著：iconutil --convert icns --output Resources/AppIcon.icns \(dir.path)")
    }
}
