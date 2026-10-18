import Foundation

/// 下拉面板最高可以多高 —— 「內容再高，面板也不可以超出螢幕」的算術。
///
/// ### 為什麼放在這裡，而且為什麼光有它不夠
/// 這條算術原本寫在 `StatusItemController.panelSize()`，夾的是 `popover.contentSize`。
/// 〔實測 2026-10-19，`--probe-panel-clamp`，合成的超高內容，1470×956 的內建螢幕〕
/// contentSize 確實被夾到 899，但 popover 視窗照樣長到 1668、頂緣衝到 y=1671
/// （選單列底緣是 923）—— `NSHostingController` 預設的 `sizingOptions`
/// （rawValue 7：minSize｜intrinsicContentSize｜maxSize）把 SwiftUI 的最小高度變成
/// hosting view 的約束，而 session 清單是 `.frame(height:)` 釘死的，最小高度就是整份內容。
/// AppKit 先照 contentSize 把視窗放好（底緣 y=3），約束再把它往上撐。
///
/// 所以上限一定要進到 SwiftUI 的版面裡（`PanelView.maxHeight`），夾屬性只是第二道保險。
/// 這裡只放兩個版面都要用的算術，讓「上限是多少」只定義在一處（規矩 2）。
public enum PanelFit {

    /// 面板內容與「選單列以下可用高度」之間要留的空間。
    ///
    /// 〔實測 2026-10-19，同上〕popover 視窗比 contentSize 高 26pt（箭頭＋邊框），
    /// 頂緣比選單列底緣高 5pt（箭頭尖端碰到圖示）。所以 contentSize 夾到
    /// 「可用高度 − 24」時，視窗底緣落在可用區底緣之上 3pt。
    /// ⚠️ 26 與 5 是**這台機器、這一版 macOS** 量到的；換了 popover 外觀要重量。
    public static let screenMargin: CGFloat = 24

    /// 面板內容最高可以多高。
    ///
    /// - Parameter visibleHeight: 螢幕「選單列以下」的可用高度（`visibleFrame.height`）。
    /// - Returns: nil ＝ **不知道螢幕多高**，所以也不知道上限 —— 呼叫端不夾，
    ///   不是夾到 0。螢幕比邊距還矮時回 0，不回負數。
    public static func cap(visibleHeight: CGFloat?) -> CGFloat? {
        guard let visibleHeight else { return nil }
        return max(0, visibleHeight - screenMargin)
    }

    /// 內容自然高度 `natural` 在上限 `cap` 之下實際要畫多高。
    ///
    /// 只會變矮、不會變高 —— 上限不可以把一個短的面板撐開。
    /// `cap == nil`（不知道螢幕）時原封不動。
    public static func height(natural: CGFloat, cap: CGFloat?) -> CGFloat {
        guard let cap else { return natural }
        return min(natural, cap)
    }
}
