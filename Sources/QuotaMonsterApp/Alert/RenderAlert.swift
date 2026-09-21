import AppKit
import SwiftUI
import QuotaMonsterCore

/// `--render-alert <file> [--dark]` —— 把 T1 浮窗的三種情況畫成一張 PNG。
///
/// ⚠️ **配色一定要用深色版本檢查。** 這個專案已經在淺色渲染上看走眼兩次 ——
/// 使用者的選單列與面板都是深色的，用淺色判斷會得到相反的結論。
///
/// 四種情況一次畫完（一個在等 / 等你批准 / 兩個在等 / 讀不到問題 / 四個合併），
/// 因為它們是同一套骨架的幾段降級，分開看判斷不了「降級有沒有降在對的地方」。
///
/// ⚠️ **這份清單上寫著的每一種，都必須真的在下面的 cases 裡。**
/// 這裡曾經宣稱畫了「兩個在等」卻沒有 —— 於是 n=2 的版面從來沒有被眼睛看過，
/// 而它剛好就是唯一一個把第二個 session 整個藏起來的版面。
@MainActor
enum RenderAlert {

    static func run(path: String, dark: Bool) {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        NSAppearance.current = appearance

        let t0 = Date()
        let cases: [(String, AlertContent)] = [
            ("一個在等", AlertContent(
                primary: session("usage", "usage-c9", .inputNeeded, t0.addingTimeInterval(-134)),
                coalesced: false,
                context: WaitingContext(headline: "要我繼續嗎？", toolName: "AskUserQuestion",
                                        detail: "方向"),
                now: t0)),
            ("等你批准工具", AlertContent(
                primary: session("usage", "usage-c9", .permissionPrompt,
                                 t0.addingTimeInterval(-72)),
                coalesced: false,
                context: WaitingContext(headline: "清掉建置快取重跑一次",
                                        toolName: "Bash", detail: "rm -rf .build"),
                now: t0)),
            ("兩個在等 —— 引擎不合併，但螢幕上只有一扇窗", AlertContent(
                primary: session("usage", "usage-c9", .inputNeeded, t0.addingTimeInterval(-310)),
                others: [session("F1", "f1-e3", .permissionPrompt, t0.addingTimeInterval(-45))],
                coalesced: false,
                context: WaitingContext(headline: "要一起改掉舊的色階嗎？",
                                        toolName: "AskUserQuestion", detail: "色階"),
                now: t0)),
            ("讀不到問題 —— 退回分類文字", AlertContent(
                primary: session("F1", "f1-e3", .inputNeeded, t0.addingTimeInterval(-302)),
                coalesced: false, context: nil, now: t0)),
            ("四個合併", AlertContent(
                primary: session("usage", "usage-c9", .inputNeeded, t0.addingTimeInterval(-482)),
                others: [
                    session("F1", "f1-e3", .inputNeeded, t0.addingTimeInterval(-120)),
                    session("PULSE", "pulse-a1", .permissionPrompt, t0.addingTimeInterval(-60)),
                    session("zen-dial", "zen-b2", .inputNeeded, t0.addingTimeInterval(-40)),
                ],
                coalesced: true,
                context: WaitingContext(headline: "要我改 blockedBanner 嗎？",
                                        toolName: "AskUserQuestion", detail: "面板"),
                now: t0)),
        ]

        let gap: CGFloat = 18
        let labelHeight: CGFloat = 20
        var shots: [(String, NSImage)] = []
        for (title, content) in cases {
            shots.append((title, snapshot(content, appearance: appearance)))
        }

        let width = AlertView.width + gap * 2
        let height = shots.reduce(gap) { $0 + $1.1.size.height + labelHeight + gap }

        let out = NSImage(size: NSSize(width: width, height: height))
        out.lockFocus()
        (dark ? NSColor(white: 0.10, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        var y = height - gap
        for (title, image) in shots {
            y -= labelHeight
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: dark ? NSColor(white: 0.60, alpha: 1)
                                       : NSColor(white: 0.35, alpha: 1),
            ]
            title.draw(at: NSPoint(x: gap, y: y + 3), withAttributes: attrs)
            y -= image.size.height
            image.draw(in: NSRect(x: gap, y: y, width: image.size.width, height: image.size.height))
            y -= gap
        }
        out.unlockFocus()

        guard let tiff = out.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("無法產生 PNG\n".data(using: .utf8)!)
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)  \(Int(width)) × \(Int(height)) pt  (\(dark ? "dark" : "light"))")
    }

    /// `--demo-alert` —— 把**真的** NSPanel 叫出來 15 秒。
    ///
    /// 為什麼需要它：浮窗是 Stage 5 唯一沒有測試覆蓋的路徑，而它的失敗模式全都是
    /// **安靜的** —— 全螢幕 Space 裡不出現、非前景時被 hidesOnDeactivate 收走、
    /// 按鈕吃掉第一次點擊。這三件事都沒有錯誤訊息，只能用眼睛跟手指驗。
    /// 性質與既有的 `--probe-popover` 相同。
    static func demo() -> AlertPanelController {
        let t0 = Date()
        let controller = AlertPanelController(anchor: { nil }) { s in
            print("跳過去 → \(s.project) (pid \(s.pid))")
        }
        controller.show(AlertContent(
            primary: session("usage", "usage-c9", .permissionPrompt,
                             t0.addingTimeInterval(-134)),
            coalesced: false,
            context: WaitingContext(headline: "清掉建置快取重跑一次",
                                    toolName: "Bash", detail: "rm -rf .build"),
            now: t0))
        return controller
    }

    private static func snapshot(_ content: AlertContent,
                                 appearance: NSAppearance) -> NSImage {
        let view = AlertView(content: content, onJump: { _ in }, onDismiss: {})
        let host = NSHostingView(rootView: view)
        host.appearance = appearance
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()

        let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: rep)
        let image = NSImage(size: host.bounds.size)
        image.addRepresentation(rep)
        return image
    }

    private static func session(_ project: String, _ name: String,
                                _ waitingFor: WaitingFor, _ since: Date) -> WaitingSession {
        WaitingSession(sessionId: "fixture-\(project)", pid: 1, project: project, name: name,
                       waitingFor: waitingFor, since: since,
                       cwd: "/Users/x/Antigravity/\(project)", episode: "fixture")
    }
}
