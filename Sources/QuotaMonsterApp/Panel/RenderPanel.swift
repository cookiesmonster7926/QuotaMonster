import SwiftUI
import AppKit
import QuotaMonsterCore

/// `QuotaMonsterApp --render-panel <file.png>`：把面板離線渲染成 PNG。
///
/// 存在的理由：這台機器沒給終端機螢幕錄製權限，所以沒辦法截 popover 的圖。
/// `ImageRenderer` 可以在沒有視窗的情況下把 SwiftUI 畫出來，是唯一能自動檢查版面的辦法。
@MainActor
enum RenderPanel {
    /// 找出面板中段那條「整列都是背景色」的空白帶，把 rows 接進去。
    ///
    /// 空白帶是靠**量**出來的，不是寫死座標 —— 面板高度會隨 session 數、
    /// 額度欄位數、完成訊號而變，寫死的 y 會在下一次版面調整時靜靜地切錯地方。
    /// - Returns: PNG 資料；找不到夠長的空白帶（例如面板本來就滿的）時回 nil。
    static func splice(panel: NSBitmapImageRep, rows: NSBitmapImageRep) -> Data? {
        let w = panel.pixelsWide, h = panel.pixelsHigh
        guard let bg = panel.colorAt(x: w / 2, y: h / 2) else { return nil }
        func isBlank(_ y: Int) -> Bool {
            for x in stride(from: 20, to: w - 20, by: 8) {
                guard let c = panel.colorAt(x: x, y: y) else { return false }
                if abs(c.redComponent - bg.redComponent) > 0.025
                    || abs(c.greenComponent - bg.greenComponent) > 0.025
                    || abs(c.blueComponent - bg.blueComponent) > 0.025 { return false }
            }
            return true
        }
        var best = (start: 0, length: 0), runStart = -1
        for y in 0..<h {
            if isBlank(y) {
                if runStart < 0 { runStart = y }
            } else if runStart >= 0 {
                if y - runStart > best.length { best = (runStart, y - runStart) }
                runStart = -1
            }
        }
        if runStart >= 0, h - runStart > best.length { best = (runStart, h - runStart) }
        guard best.length > 100 else { return nil }

        // ⚠️ `colorAt` 用**像素**座標，但 `draw(in:from:)` 的 `from` 吃的是 rep 的
        // **size**（點）。2x 渲染出來的 rep size 是 380×382、像素是 760×764，
        // 直接把像素數餵進 from 會差整整兩倍 —— 第一版就是這樣，接出來的圖
        // 頁首與額度整塊不見。把 size 對齊像素，兩個空間就合一了。
        panel.size = NSSize(width: w, height: h)
        rows.size = NSSize(width: rows.pixelsWide, height: rows.pixelsHigh)

        let rh = rows.pixelsHigh
        let outH = h - best.length + rh
        guard let out = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: outH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
        // ⚠️ colorAt 的 y 由上往下，繪圖的 y 由下往上。三塊各自換算一次。
        let topH = best.start, bottomH = h - (best.start + best.length)
        panel.draw(in: NSRect(x: 0, y: outH - topH, width: w, height: topH),
                   from: NSRect(x: 0, y: h - topH, width: w, height: topH),
                   operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
        rows.draw(in: NSRect(x: 0, y: bottomH, width: w, height: rh),
                  from: .zero, operation: .copy, fraction: 1,
                  respectFlipped: false, hints: nil)
        panel.draw(in: NSRect(x: 0, y: 0, width: w, height: bottomH),
                   from: NSRect(x: 0, y: 0, width: w, height: bottomH),
                   operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
        return out.representation(using: .png, properties: [:])
    }

    static func run(path: String) {
        // 偏好在 `DataStore.init` 就讀進來了 —— popover 會照偏好畫，
        // 所以離線渲染也要照偏好畫，否則這張圖不是「它長什麼樣」，
        // 是「它在預設值下長什麼樣」。
        let store = DataStore()
        // `--panel simple|full` 與 `--chart` 一樣只覆寫記憶體，不碰使用者的偏好檔。
        if let i = CommandLine.arguments.firstIndex(of: "--panel"),
           CommandLine.arguments.count > i + 1,
           let style = PanelStyle(rawValue: CommandLine.arguments[i + 1]) {
            var p = store.preferences
            p.panelStyle = style
            store.setPreferences(p, persist: false)
        }
        FileHandle.standardError.write(
            Data("面板版面：\(store.panelStyle.label)（\(store.panelStyle.rawValue)）\n".utf8))
        // `--demo-update` 塞一筆合成的「有新版」，讓那一條的版面看得到。
        if CommandLine.arguments.contains("--demo-update") {
            store.seedSyntheticUpdate(.available(ReleaseVersion("9.9.9")!,
                                                 url: "https://example.invalid"))
            FileHandle.standardError.write(
                Data("⚠️ 「有新版 9.9.9」那一條是**合成**的，不是真的檢查結果\n".utf8))
        }
        // `--demo-outage` 塞一筆合成的「一直問不到」。
        if CommandLine.arguments.contains("--demo-outage") {
            store.seedSyntheticOutage()
            FileHandle.standardError.write(
                Data("⚠️ 「更新檢查連不上」那一條是**合成**的\n".utf8))
        }
        // `--chart daily|cumulative` 只覆寫記憶體，不碰使用者的偏好檔。
        if let i = CommandLine.arguments.firstIndex(of: "--chart"),
           CommandLine.arguments.count > i + 1,
           let style = ChartStyle(rawValue: CommandLine.arguments[i + 1]) {
            var p = store.preferences
            p.chartStyle = style
            store.setPreferences(p, persist: false)
        }
        FileHandle.standardError.write(
            Data("圖表樣式：\(store.chartStyle.label)（\(store.chartStyle.rawValue)）\n".utf8))
        store.refresh()

        // `--demo-finish` 塞一筆合成的完成標記，讓那一列的版面看得到。
        // ⚠️ 合成的，不是真的 —— 下面會把這件事印出來。
        if CommandLine.arguments.contains("--demo-finish"),
           let first = store.sessions.first {
            // 「高度成本 0pt」是這個設計的承諾。**量它，不要宣稱它。**
            let before = NSHostingController(rootView: PanelView(store: store))
                .view.fittingSize.height
            store.seedSyntheticFinish(SessionFinish(
                sessionId: first.session.sessionId,
                finishedAt: store.lastRefresh.addingTimeInterval(-30),
                ranFor: 724))
            let after = NSHostingController(rootView: PanelView(store: store))
                .view.fittingSize.height
            let note = "⚠️ 第一列是**合成**的完成標記（30 秒前完成、跑了 12m 04s），不是真的\n"
                + "列高 沒有標記=\(before)pt 有標記=\(after)pt Δ=\(after - before)pt\n"
            FileHandle.standardError.write(Data(note.utf8))
            if before != after {
                FileHandle.standardError.write(Data(
                    "✘ 完成標記改變了面板高度 —— 那一列的三個欄位必須等高替換\n".utf8))
                exit(1)
            }
        }

        // 預設用「面板自己的自然高度」渲染 —— 那才是 popover 真正會顯示的樣子。
        // 傳 --height <n> 可以指定固定高度，用來看被撐開時長什麼樣。
        let hosting = NSHostingController(rootView: PanelView(store: store))
        let natural = hosting.view.fittingSize.height
        var height = natural
        if let i = CommandLine.arguments.firstIndex(of: "--height"),
           CommandLine.arguments.count > i + 1,
           let h = Double(CommandLine.arguments[i + 1]) {
            height = h
        }
        FileHandle.standardError.write(
            "面板自然高度 \(natural)pt，這次用 \(height)pt 渲染\n".data(using: .utf8)!)

        // 傳 --dark 就用深色外觀渲染。使用者的面板是深色的，用淺色渲染去判斷配色
        // 會一直判錯 —— 前面已經因為這件事看走眼兩次了。
        let dark = CommandLine.arguments.contains("--dark")
        let renderer = ImageRenderer(content:
            PanelView(store: store)
                .frame(width: 380, height: height)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
        )
        if dark { renderer.proposedSize = .init(width: 380, height: height) }
        renderer.scale = 2

        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("render failed"); return
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try? png.write(to: url)
        print("面板已渲染 → \(url.path)  (\(Int(img.size.width))×\(Int(img.size.height))pt)")

        // ⚠️ **簡易版面沒有 session 清單，所以到此為止。**
        // 下面那段是為了繞過「ScrollView 在 ImageRenderer 下畫成空的」而另外渲染
        // session 列再接回去 —— 對簡易版面做的話，會寫出一張**使用者看不到的合成圖**，
        // 那是規矩 28（診斷不可以說謊）。
        guard store.panelStyle == .full else {
            FileHandle.standardError.write(
                Data("簡易版面沒有 session 清單 —— 不另外渲染 rows、也不 splice。\n".utf8))
            return
        }

        // ScrollView 在 ImageRenderer 底下會畫成空的（已知限制），
        // 所以 session 列另外用一個沒有 ScrollView 的版本渲染，才驗得到 row 版面。
        let rowsOnly = VStack(spacing: 8) {
            ForEach(store.sessions, id: \.session.sessionId) { s in
                SessionRow(session: s,
                                   title: store.displayName(for: s.session),
                           tree: store.trees[s.session.sessionId],
                           context: store.statusLine[s.session.sessionId],
                           finish: store.finishes[s.session.sessionId],
                           now: store.lastRefresh,
                           contextYellow: store.preferences.contextYellow
                               ?? SessionRow.defaultContextYellow,
                           contextRed: store.preferences.contextRed
                               ?? SessionRow.defaultContextRed)
            }
        }
        .padding(12)
        .frame(width: 380)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(\.colorScheme, dark ? .dark : .light)

        let r2 = ImageRenderer(content: rowsOnly)
        r2.scale = 2
        if let i2 = r2.nsImage, let t2 = i2.tiffRepresentation,
           let b2 = NSBitmapImageRep(data: t2),
           let p2 = b2.representation(using: .png, properties: [:]) {
            let u2 = url.deletingLastPathComponent()
                .appendingPathComponent("panel-rows.png")
            try? p2.write(to: u2)
            print("session 列已渲染 → \(u2.path)  (\(Int(i2.size.width))×\(Int(i2.size.height))pt)")

            // 第三張：把 session 列**接**回面板中段那條空白帶。
            //
            // ⚠️ 為什麼要有這張：前兩張各自都是誠實的，但**都不是使用者看到的東西** ——
            // 一張缺了 session 列，一張缺了額度與頁首。README 放任何一張都在誤導。
            // 這張是唯一可以拿去對外展示的。
            //
            // ⚠️ 它是**接**的，不是截圖。空白帶被整段換掉，沒有任何內容被蓋住
            // （高度會變，不是原本的 382pt）。這件事印在下面那行輸出裡，
            // 而不是只寫在註解裡 —— 規矩 28：診斷不可以宣稱它沒做到的事。
            if let composite = splice(panel: rep, rows: b2) {
                let u3 = url.deletingLastPathComponent()
                    .appendingPathComponent("panel-full.png")
                try? composite.write(to: u3)
                print("合成圖已寫出 → \(u3.path)")
                print("  ⚠️ 這是**接**出來的（空白帶換成 session 列），不是一張截圖。")
            } else {
                print("  ⚠️ 找不到可以接的空白帶，沒有寫出合成圖")
            }
        }
    }
}
