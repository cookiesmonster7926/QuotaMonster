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
/// ### 各擋一種錯
/// 1. 夾不住（今天的 bug）：`fittingSize` 超過上限。
/// 1b. 框夾住了、內容沒縮：兩個原因各擋一次 ——
///     清單又被釘死（`contentActuallyFitsUnderTheCap`），或 `CappedHeight` 排版時沒把夾過的高度
///     交給內容（`cappedHeightHandsTheCapToItsContent`）。兩種都是 footer 被裁掉。
/// 1c. 接線斷了：`togglePanel` 沒把上限交給版面（`fitAssignsTheCapBeforeMeasuring`）。
/// 2. 夾過頭：把清單改成可以縮到 0 就收工 —— 那樣框夾得住，但 SwiftUI 的最小高度從此小於內容。
///    〔實測 2026-10-19，`--probe-panel-clamp`〕那個半套修法下，一個**已經夾到上限**的面板
///    開著時內容從 1642 長到 1912，視窗停在 925 —— 這是對的（它本來就該停在上限）。
///    〔推論，沒有量〕同一個機制會讓一個**短**面板開著時多了 session 不再長高：
///    規矩 50 只量到「window 自己跟上了」，沒量為什麼；「靠的是最小＝最大＝內容」也是推論。
///    所以剛性在長的（`cappedPanelStaysRigid`）、短的、不知道螢幕的三種情況各釘一次。
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

    /// `fittingSize` 問的是理想高度，壓不壓得扁它看不出來 —— 要像 `cappedPanelStaysRigid`
    /// 一樣，要求它變矮，看它讓不讓。
    @Test("短的面板也是剛性的：被要求變矮也不讓", arguments: [CGFloat(700), nil] as [CGFloat?])
    func shortPanelStaysRigid(cap: CGFloat?) {
        let s = store(tall: false)
        let natural = fitting(s, cap: nil)
        #expect(natural > 100)                        // 前提：要求的 100pt 真的比它矮
        let hosting = NSHostingController(rootView: PanelView(store: s, maxHeight: cap))
        #expect(hosting.sizeThatFits(in: CGSize(width: 380, height: 100)).height == natural)
    }

    /// `sizeThatFits`／`fittingSize` 都只走 `CappedHeight.sizeThatFits`，從不走 `placeSubviews`。
    /// 所以要真的排一次版，看內容實際拿到多高。
    @Test("CappedHeight 排版時把夾過的高度交給內容，不是內容的理想高度")
    func cappedHeightHandsTheCapToItsContent() {
        let seen = PlacedHeights()
        let view = NSHostingView(rootView: CappedHeight(cap: 700) {
            RecordPlacement(seen: seen) {
                Color.clear.frame(width: 380).frame(minHeight: 0, idealHeight: 1500, maxHeight: 1500)
            }
        })
        view.frame = NSRect(x: 0, y: 0, width: 380, height: 700)
        view.layoutSubtreeIfNeeded()
        #expect(seen.last == 700)
    }

    /// 出貨的展開路徑（`togglePanel`）唯一做的事：先把上限交給版面、再量。
    /// 拿掉指派那一行，`fittingSize` 就回到整份內容（修前的 bug），這裡會紅。
    @Test("展開前先把上限交給版面，量到的才是夾過的高度")
    func fitAssignsTheCapBeforeMeasuring() {
        let hosting = NSHostingController(rootView: PanelView(store: store(tall: true)))
        let size = StatusItemController.fit(hosting, visibleHeight: 723)
        #expect(hosting.rootView.maxHeight == 699)
        #expect(size.height == 699)
        #expect(hosting.view.fittingSize.height == 699)
    }

    @Test("不知道螢幕多高 → 不夾（nil），量到的是整份內容")
    func fitWithUnknownScreenDoesNotCap() {
        let s = store(tall: true)
        let hosting = NSHostingController(rootView: PanelView(store: s))
        let size = StatusItemController.fit(hosting, visibleHeight: nil)
        #expect(hosting.rootView.maxHeight == nil)
        #expect(size.height == fitting(s, cap: nil))
    }
}

/// 只給 `cappedHeightHandsTheCapToItsContent`：記下自己在排版時實際被放成多高。
final class PlacedHeights: @unchecked Sendable {
    var last: CGFloat?
}

struct RecordPlacement: Layout {
    let seen: PlacedHeights

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(proposal) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        seen.last = bounds.height
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(bounds.size))
    }
}
