import AppKit
import QuotaMonsterCore

/// `QuotaMonsterApp --render <dir>`：把每個狀態輸出成 PNG，方便人眼檢查。
/// 選單列圖示沒辦法自動做視覺回歸（終端機沒有螢幕錄製權限），所以這是唯一的辦法。
enum RenderStates {
    struct Case { let name: String; let state: GlyphState }

    static let cases: [Case] = {
        func s(_ five: Double?, _ seven: Double?, agents: Int = 0, blocked: Int = 0,
               exhausted: Bool = false, fresh: Freshness = .live,
               finish: FinishGlow = .none) -> GlyphState {
            GlyphState(fiveHourRemaining: five, sevenDayRemaining: seven,
                       runningAgents: agents, blockedSessions: blocked,
                       exhausted: exhausted, freshness: fresh, finishGlow: finish)
        }
        return [
            Case(name: "01-idle",            state: s(0.72, 0.82)),
            Case(name: "02-agents-1",        state: s(0.72, 0.82, agents: 1)),
            Case(name: "03-agents-2",        state: s(0.72, 0.82, agents: 2)),
            Case(name: "04-agents-3",        state: s(0.72, 0.82, agents: 3)),
            Case(name: "05-agents-5",        state: s(0.72, 0.82, agents: 5)),
            Case(name: "06-agents-15",       state: s(0.72, 0.82, agents: 15)),
            Case(name: "07-quota-low",       state: s(0.15, 0.40, agents: 3)),
            Case(name: "08-half-exposed",    state: s(0.45, 0.30, agents: 1)),
            Case(name: "09-blocked-1",       state: s(0.72, 0.82, agents: 3, blocked: 1)),
            Case(name: "10-blocked-2",       state: s(0.72, 0.82, agents: 3, blocked: 2)),
            Case(name: "11-blocked-3",       state: s(0.72, 0.82, agents: 3, blocked: 3)),
            Case(name: "12-blocked-6",       state: s(0.72, 0.82, agents: 3, blocked: 6)),
            Case(name: "13-exhausted",       state: s(0.0, 0.40, exhausted: true)),
            Case(name: "14-stale",           state: s(0.72, 0.82, agents: 2, fresh: .expired)),
            Case(name: "15-unknown",         state: s(nil, nil, fresh: .expired)),
            // ⚠️ 從 16 起算 —— 15 已經被 unknown 佔走了。
            Case(name: "16-finish-fresh",    state: s(0.72, 0.82, finish: .fresh)),
            Case(name: "17-finish-faded",    state: s(0.72, 0.82, finish: .faded)),
            Case(name: "18-finish-agents-5", state: s(0.72, 0.82, agents: 5, finish: .fresh)),
            // 沒有額度讀數的那一格 —— 這是 template 陷阱唯一會浮出來的地方。
            Case(name: "19-finish-no-quota", state: s(nil, nil, fresh: .expired, finish: .fresh)),
            // 有人在等你時完成訊號整批丟掉，所以這一張必須與 09-blocked-1 一模一樣。
            Case(name: "20-finish-while-blocked",
                 state: s(0.72, 0.82, agents: 3, blocked: 1, finish: .fresh)),
        ]
    }()

    static func run(directory: String) {
        let dir = URL(fileURLWithPath: (directory as NSString).expandingTildeInPath)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // 傳 --dark 就用白色墨水渲染，看得到深色選單列上的實際樣子。
        // 沒有這個開關就只能猜 —— 而選單列是這個 app 唯一的門面。
        let onDark = CommandLine.arguments.contains("--dark")
        let ink: NSColor = onDark ? .white : .black

        // ⚠️ 自我斷言：**診斷指令宣稱畫了什麼就必須真的畫。**
        // 這個 repo 已經為 `--render-alert` 宣稱畫了「兩個在等」卻沒畫付過一次代價。
        //
        // ⚠️ 這裡**不可以用像素斷言**去抓 template 陷阱：下面是把 NSImage
        // `draw(in:)` 進離屏 bitmap，而 `isTemplate` 只在 AppKit 拿它當遮罩畫
        // （NSButton / NSImageView）時才丟顏色 —— 離屏畫會照實畫出丁香紫，
        // 所以像素斷言在有 bug 的版本上一樣會過。唯一抓得到的是 isTemplate 本身。
        let glowing = cases.first { $0.name == "19-finish-no-quota" }!
        if GlyphRenderer.image(for: glowing.state, ink: ink).isTemplate {
            FileHandle.standardError.write(Data(
                "✘ 19-finish-no-quota 走了 template —— 丁香紫會被 AppKit 丟掉\n".utf8))
            exit(1)
        }

        for c in cases {
            let img = GlyphRenderer.image(for: c.state, ink: ink)
            // ⚠️ **2x 是使用者真正看到的那一個。** 這台機器是 Retina
            // （2560×1664），選單列把 22pt 的圖示畫成 44 個裝置像素。
            // 這裡本來只寫 1x 與 8x —— 1x 是最壞情況（外接非 Retina 螢幕）、
            // 8x 是拿來看幾何的，**兩個都不是日常真正的樣子**。
            // 判斷配色要看 2x。
            for scale in [1, 2, 8] {
                let px = Int(GlyphGeometry.canvas) * scale
                guard let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                // template image 只有 alpha 有意義，這裡用黑色把它實體化以便檢視
                img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
                NSGraphicsContext.restoreGraphicsState()
                if let png = rep.representation(using: .png, properties: [:]) {
                    try? png.write(to: dir.appendingPathComponent("\(c.name)@\(scale)x.png"))
                }
            }
        }
        // 呼吸的 12 格，用來人眼確認亮度曲線與首尾接縫
        let alerting = GlyphState(fiveHourRemaining: 0.72, sevenDayRemaining: 0.82,
                                  runningAgents: 3, blockedSessions: 2,
                                  exhausted: false, freshness: .live)
        for i in 0..<Breath.frameCount {
            let img = GlyphRenderer.image(for: alerting,
                                          chevronOpacity: Breath.opacity(atFrame: i))
            let px = Int(GlyphGeometry.canvas) * 8
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            img.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
            NSGraphicsContext.restoreGraphicsState()
            if let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent(
                    String(format: "breath-%02d.png", i)))
            }
        }
        print("寫出 \(cases.count) 個狀態 × 3 種倍率（1x/2x/8x，2x 才是選單列真正的樣子） + \(Breath.frameCount) 格呼吸 → \(dir.path)")
    }
}
