import AppKit
import SwiftUI
import QuotaMonsterCore

/// `QuotaMonsterApp --probe-panel-clamp [--tall|--normal|--grow] [--sizing none]`：
/// **內容比螢幕高的時候，面板會不會超出螢幕？**
///
/// ### 它回答哪一個問題
/// `StatusItemController.panelSize()` 把 `popover.contentSize` 夾在螢幕可用高度以內（規矩 27），
/// 但使用者的面板仍然高過螢幕、頂端被切掉。這支用**合成**的 session 造出「內容比螢幕高」，
/// 走跟點圖示**同一條**展開路徑（`toggleForProbe()`），把指派前後與展開後的數字一次印出來。
///
/// - `--tall`（預設）：6 個合成 session（2 個等你、4 個各 20 隻在跑的 agent）。
/// - `--normal`：1 個合成 session、沒有 agent —— 對照組，看「正常的頂緣」在哪裡。
/// - `--grow`：用對照組展開，**開著的時候**換成超高的那一組 —— 看視窗會不會跟著長、
///   長到上限就停（規矩 50 量到「window 自己就跟上了」，這裡看它有沒有天花板）。
/// - `--sizing none`：展開前把 `NSHostingController.sizingOptions` 設成 `[]`，
///   只用來驗證假說，不是修法。
///
/// ⚠️ 它會在使用者螢幕上短暫開一個 popover（約 2–3 秒），跑完自己關、自己結束。
/// 結束碼：面板留在螢幕裡 0，超出 1。
/// ⚠️ session 全部是**合成**的（名字、路徑、agent 都是編的），不讀註冊表 —— 輸出會講明。
@MainActor
enum ProbePanelClamp {

    static func syntheticSessions(tall: Bool) -> ([LiveSession], [String: AgentTree]) {
        let start = Date().addingTimeInterval(-600)
        func session(_ i: Int, _ status: SessionStatus) -> LiveSession {
            LiveSession(session: ClaudeSession(
                pid: Int32(90_000 + i), sessionId: "synthetic-\(i)",
                cwd: "/synthetic/project-\(i)", startedAt: start,
                status: status, name: "合成 \(i)", nameSource: "auto"))
        }
        guard tall else { return ([session(0, .idle)], [:]) }

        var sessions: [LiveSession] = [session(0, .waiting(.permissionPrompt)),
                                       session(1, .waiting(nil))]
        var trees: [String: AgentTree] = [:]
        for i in 2..<6 {
            let s = session(i, .busy)
            sessions.append(s)
            let agents = (0..<20).map { a in
                AgentNode(meta: AgentMeta(agentId: "syn-\(i)-\(a)", agentType: "general-purpose",
                                          description: "合成 agent \(a)", spawnDepth: 1),
                          runState: .running)
            }
            trees[s.session.sessionId] = AgentTree(sessionId: s.session.sessionId,
                                                   agents: agents, workflows: [])
        }
        return (sessions, trees)
    }

    nonisolated static func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }

    static func run() {
        let args = CommandLine.arguments
        let grow = args.contains("--grow")
        let tall = !args.contains("--normal") && !grow
        let store = DataStore()
        let (sessions, trees) = syntheticSessions(tall: tall)
        store.seedSyntheticSessions(sessions, trees: trees)
        store.refresh()
        print("⚠️ session 是**合成**的（\(sessions.count) 個，"
              + "\(grow ? "對照組，開著時換成超高" : tall ? "超高" : "對照組")），不是註冊表讀到的")

        let controller = StatusItemController(store: store)
        let popover = controller.probePopover
        let hosting = controller.probeHosting
        if args.contains("--sizing"), let i = args.firstIndex(of: "--sizing"),
           args.count > i + 1, args[i + 1] == "none" {
            hosting.sizingOptions = []
            print("⚠️ 假說驗證：sizingOptions 設成 []（出貨的版本不是這樣）")
        }
        print("hosting.sizingOptions  rawValue=\(hosting.sizingOptions.rawValue)")

        Task { @MainActor in
            // status item 的 window 要等 runloop 跑過一輪才有真正的大小（ProbePopover 量過）。
            try? await Task.sleep(for: .milliseconds(700))
            guard let screen = controller.probeScreen else { print("✘ 沒有螢幕"); exit(1) }
            let visible = screen.visibleFrame
            print("── 螢幕 ──────────────────────────────────────────")
            print("frame \(screen.frame)  visibleFrame \(visible)")
            print("選單列底緣 y = \(f(visible.maxY))   可用高度 = \(f(visible.height))")
            print("── 展開前 ────────────────────────────────────────")
            print("fittingSize.height   \(f(hosting.view.fittingSize.height))")

            controller.toggleForProbe()
            print("── 展開的同一拍 ──────────────────────────────────")
            print("popover.contentSize  \(f(popover.contentSize.height))")
            print("window.height        \(f(hosting.view.window?.frame.height ?? -1))")

            // 箭頭尖端該碰到的地方：圖示按鈕在螢幕上的底緣。
            // 〔實測，ProbePopover〕正常的面板頂緣就是這裡（比選單列底緣高 5pt，那是箭頭）。
            let anchor = controller.screenAnchor?.minY ?? visible.maxY
            var ok = true

            @MainActor func verdict(_ label: String) {
                print("── \(label) ──────────────────────────────")
                print("popover.contentSize  \(f(popover.contentSize.height))")
                print("hosting.view.frame.h \(f(hosting.view.frame.height))")
                print("fittingSize.height   \(f(hosting.view.fittingSize.height))")
                guard let w = hosting.view.window else { print("✘ popover 沒有 window"); ok = false; return }
                let fr = w.frame
                print("popover window       \(fr)")
                print("頂緣 y = \(f(fr.maxY))（按鈕底緣 \(f(anchor))、選單列底緣 \(f(visible.maxY))）")
                print("底緣 y = \(f(fr.minY))（可用區底緣 \(f(visible.minY))）")
                let topOK = fr.maxY <= anchor + 0.5
                let bottomOK = fr.minY >= visible.minY - 0.5
                print(topOK ? "→ 頂緣沒有越過按鈕底緣（只有箭頭碰到圖示）"
                            : "→ ✘ 頂緣越過按鈕底緣 \(f(fr.maxY - anchor)) pt（面板頂端會被切掉）")
                print(bottomOK ? "→ 底緣在可用區以內" : "→ ✘ 底緣低於可用區 \(f(visible.minY - fr.minY)) pt")
                ok = ok && topOK && bottomOK
            }

            try? await Task.sleep(for: .milliseconds(1500))
            verdict("展開 1.5 秒之後")

            // 開著的時候內容再長高（規矩 50：window 會自己跟著內容走，不等 contentSize）。
            //   --grow：從對照組整批換成超高的那一組，逐時點記視窗位置（sleep 是累加的，標籤是約數）
            //   --tall：每個 session 多 5 隻 agent，等一跳再等 500ms
            if grow {
                let (more, moreTrees) = syntheticSessions(tall: true)
                store.seedSyntheticSessions(more, trees: moreTrees)
                // 每一刻視窗在哪裡：只看 minY／maxY，看它是「往上長再被拉回來」還是一直待在上面。
                func trace(_ label: String) {
                    let fr = hosting.view.window?.frame ?? .zero
                    print("  \(label)  window y \(f(fr.minY))…\(f(fr.maxY))")
                }
                print("── 長高之後的軌跡 ──")
                trace("同一拍      ")
                await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
                trace("一跳之後    ")
                for ms in [16, 50, 100, 200, 500] {
                    try? await Task.sleep(for: .milliseconds(ms == 16 ? 16 : ms / 2))
                    trace("約 \(ms)ms    ")
                }
                verdict("開著時從對照組換成超高之後")
            } else if tall {
                let grown = Dictionary(uniqueKeysWithValues: trees.map { id, t in
                    (id, AgentTree(sessionId: id, agents: t.agents + (0..<5).map { a in
                        AgentNode(meta: AgentMeta(agentId: "\(id)-more-\(a)",
                                                  agentType: "general-purpose",
                                                  description: "合成 agent 追加 \(a)",
                                                  spawnDepth: 1),
                                  runState: .running)
                    }, workflows: []))
                })
                store.seedSyntheticSessions(sessions, trees: grown)
                await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
                try? await Task.sleep(for: .milliseconds(500))
                verdict("開著時內容再長高之後")
            }

            controller.toggleForProbe()
            try? await Task.sleep(for: .milliseconds(200))
            print(ok ? "結論：面板留在螢幕裡" : "結論：✘ 面板超出螢幕")
            exit(ok ? 0 : 1)
        }
    }
}

@MainActor
final class PanelClampDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ note: Notification) { ProbePanelClamp.run() }
}
