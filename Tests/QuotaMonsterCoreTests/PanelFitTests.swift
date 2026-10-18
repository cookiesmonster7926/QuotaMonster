import Testing
import Foundation
@testable import QuotaMonsterCore

/// 面板高度上限 —— 「內容再高，面板也不可以超出螢幕」。
///
/// ### 為什麼需要它
/// 〔實測 2026-10-19，`--probe-panel-clamp`，合成的超高內容〕`panelSize()` 把
/// `popover.contentSize` 夾到 899，但 popover 視窗照樣長到 1668：
/// `NSHostingController` 預設的 `sizingOptions`（minSize｜intrinsicContentSize｜maxSize）
/// 把 SwiftUI 的**最小**高度變成 hosting view 的約束，而 session 清單是
/// `.frame(height:)` 釘死的，最小高度就是整份內容的 1642。夾的是屬性，不是框。
/// 所以上限要進到 SwiftUI 的版面裡（`PanelView.maxHeight`），算術放在這裡。
@Suite("面板高度上限")
struct PanelFitTests {

    /// ⚠️ 期望值寫字面量，不寫 `923 - PanelFit.screenMargin` —— 那樣邊距改成多少都會過，
    /// 而下面那則只擋得住「邊距太小」（≥ 21），擋不住「邊距大到面板白白變矮」。
    /// 〔實測 2026-10-19，`--probe-panel-clamp`，可用高度 923〕contentSize 夾到 899。
    @Test("上限是可用高度扣掉 24")
    func capIsVisibleHeightMinusMargin() {
        #expect(PanelFit.cap(visibleHeight: 923) == 899)
    }

    /// 〔實測 2026-10-19，1470×956 的內建螢幕〕popover 視窗比 contentSize 高 26pt
    /// （箭頭＋邊框），頂緣比選單列底緣高 5pt（箭頭尖端碰到圖示）。
    /// 夾到上限的面板，整個視窗要放得進「箭頭尖端」到「可用區底緣」之間。
    @Test("夾到上限的視窗放得進選單列與可用區底緣之間")
    func cappedWindowFitsOnScreen() throws {
        let visible: CGFloat = 923
        let cap = try #require(PanelFit.cap(visibleHeight: visible))
        #expect(cap + 26 <= visible + 5)
    }

    @Test("不知道螢幕多高 → 不知道上限（nil），不是 0")
    func unknownScreenHasNoCap() {
        #expect(PanelFit.cap(visibleHeight: nil) == nil)
    }

    @Test("螢幕比邊距還矮 → 上限是 0，不是負數")
    func tinyScreenDoesNotGoNegative() {
        #expect(PanelFit.cap(visibleHeight: 10) == 0)
    }

    @Test("內容比上限高 → 夾到上限")
    func tallContentIsCapped() {
        #expect(PanelFit.height(natural: 1642, cap: 899) == 899)
    }

    @Test("內容比上限矮 → 原封不動（上限不會把面板撐高）")
    func shortContentIsUntouched() {
        #expect(PanelFit.height(natural: 358, cap: 899) == 358)
    }

    @Test("沒有上限 → 原封不動，不是 0")
    func noCapMeansNatural() {
        #expect(PanelFit.height(natural: 1642, cap: nil) == 1642)
    }
}
