import Testing
import AppKit
import SwiftUI
@testable import QuotaMonsterApp
@testable import QuotaMonsterCore

/// 面板高度上限要夾在**版面**上，不是夾在 `popover.contentSize` 這個屬性上。
///
/// ### 為什麼 Core 的測試不夠
/// 〔實測 2026-10-19，`--probe-panel-clamp`〕`panelSize()` 的算術一直是對的（夾到 899），
/// popover 視窗照樣長到 1668 —— `NSHostingController` 預設的 `sizingOptions` 把 SwiftUI 的
/// **最小**高度變成約束，而 session 清單是 `.frame(height:)` 釘死的，最小高度＝整份內容。
/// `PanelFit` 算對了，版面照樣可以不聽。抓得到的只有這一層：問 hosting controller 本身。
///
/// ### 四則各擋一種錯
/// 1. 夾不住（今天的 bug）：`fittingSize` 超過上限。
/// 1b. 框夾住了、內容沒縮：清單又被釘死，footer 被裁掉。
/// 2. 夾過頭：把清單改成可以縮到 0 就收工 —— 那樣框夾得住，但 SwiftUI 的最小高度從此
///    小於內容，popover 開著時內容長高，視窗**不會再跟著長**（規矩 50 量到的「window 自己跟上」
///    靠的就是最小＝理想）。〔實測〕那個半套修法下，開著時內容從 1642 長到 1912，視窗停在 925。
/// 3. 上限把短的面板撐高。
///
/// ⚠️ session 全部是**合成**的（`ProbePanelClamp.syntheticSessions`），家目錄是空的暫存目錄。
@Suite("面板高度上限 — 夾的是版面，不是屬性")
@MainActor
struct PanelHeightCapTests {

    func store(tall: Bool) -> DataStore {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-cap-\(UUID().uuidString)")
        let s = DataStore(home: home)
        var p = s.preferences
        p.panelStyle = .full                  // 只有完整版面有 session 清單
        s.setPreferences(p, persist: false)
        let (sessions, trees) = ProbePanelClamp.syntheticSessions(tall: tall)
        s.seedSyntheticSessions(sessions, trees: trees)
        return s
    }

    func fitting(_ store: DataStore, cap: CGFloat?) -> CGFloat {
        NSHostingController(rootView: PanelView(store: store, maxHeight: cap)).view.fittingSize.height
    }

    @Test("前提：合成的內容真的比上限高")
    func syntheticContentIsTall() {
        #expect(fitting(store(tall: true), cap: nil) > 1000)
    }

    @Test("內容比上限高 → hosting view 的高度就是上限")
    func tallContentIsHeldToTheCap() {
        #expect(fitting(store(tall: true), cap: 700) == 700)
    }

    @Test("夾住之後仍然是剛性的：被要求變矮也不讓（視窗才會跟著內容長）")
    func cappedPanelStaysRigid() {
        let hosting = NSHostingController(rootView: PanelView(store: store(tall: true), maxHeight: 700))
        #expect(hosting.sizeThatFits(in: CGSize(width: 380, height: 100)).height == 700)
    }

    /// `CappedHeight` 回報的高度永遠是上限 —— 就算 session 清單又被釘死成 `.frame(height:)`。
    /// 那時視窗夾得住，但內容比框高，底部（footer）被裁掉而不是清單在捲。
    /// 所以要直接問內容：給你上限那麼高，你放得下嗎。
    @Test("內容真的縮進上限裡（由清單吸收），不是被框裁掉")
    func contentActuallyFitsUnderTheCap() {
        let body = PanelView(store: store(tall: true), maxHeight: 700).panelBody
        #expect(NSHostingController(rootView: body)
                    .sizeThatFits(in: CGSize(width: 380, height: 700)).height <= 700)
    }

    @Test("內容比上限矮 → 上限不會把面板撐高")
    func shortContentIsUntouched() {
        let s = store(tall: false)
        #expect(fitting(s, cap: 700) == fitting(s, cap: nil))
        #expect(fitting(s, cap: 700) < 700)
    }
}
