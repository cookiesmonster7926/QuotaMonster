import AppKit
import SwiftUI
import QuotaMonsterCore

/// 「剛完成」的丁香紫。**選單列與面板共用同一份定義。**
///
/// 計畫書明說「兩邊同一個顏色」，理由與 `QuotaPalette` 存在的理由一樣：
/// 選單列說「完成＝丁香紫」、面板說「完成＝綠」就是兩套語彙。
///
/// ### 為什麼是 284°
/// 〔mockup 的分析，非量測〕217°（等你的藍）到 361°（額度紅）這 144° 是色相環上
/// 唯一沒有鄰居的空地，284° 是它的中段。距琥珀 112°、距最近的額度藍 67°。
///
/// ⚠️ **一處刻意偏離 mockup（使用者 2026-09-19 已同意）：**
/// `quiet-panel.html` 用的完成綠 `#30D158` 不用，面板的勾與鮮度線一律用丁香紫。
/// 兩個理由：(1) 它與 `SessionRow` 在 ctx<70% 時的綠是同一個色值，
/// 完成那一列會有兩條綠疊在一起；(2) 兩邊不同色就是兩套語彙。
///
/// ⚠️ **這個顏色彎了一條寫著理由的規則。** `GlyphRenderer.drawCreature` 原本寫著
/// 「生物不染色」，而那條是實測寫下來的。mockup 的反論（用一個沒有人用過的顏色，
/// 效果相反）是**推理，不是量測** —— 上線前必須跑 `--render <dir> --dark`
/// 並且在 **1x** 下看：1x 的生物只有約 4 個裝置像素寬，紫色在那裡有沒有活下來，
/// 只有那張圖說了算。
enum SignalPalette {

    /// 滿色。深色選單列用 `#E08CFF`；淺底上要壓暗，否則 5.4:1 的對比拿不到。
    static func finish(onDark: Bool) -> NSColor {
        onDark ? NSColor(srgbRed: 0.88, green: 0.55, blue: 1.00, alpha: 1)
               : NSColor(srgbRed: 0.62, green: 0.14, blue: 0.79, alpha: 1)
    }

    /// 退色版。
    ///
    /// ⚠️ **混向墨色，不是降不透明度。** alpha 0.45 已經被
    /// `freshness == .expired` 佔走了 —— 再用一次，兩個意思會疊在同一個通道上。
    /// 混合比例直接用 `Breath.minOpacity`，所以深色版算出來是 `#F1CBFF`
    /// 〔算術核對，非量測：0.88×0.45+0.55 = 0.946 = 0xF1；
    /// 0.55×0.45+0.55 = 0.7975 = 0xCB〕—— 與 mockup 一字不差，**但不寫死 hex**。
    static func finishFaded(onDark: Bool, ink: NSColor) -> NSColor {
        blend(finish(onDark: onDark), toward: ink, amount: Breath.minOpacity)
    }

    /// `glow` 那一格要用的實際顏色。
    static func nsColor(_ glow: FinishGlow, onDark: Bool, ink: NSColor) -> NSColor? {
        switch glow {
        case .none:   return nil
        case .fresh:  return finish(onDark: onDark)
        case .faded:  return finishFaded(onDark: onDark, ink: ink)
        }
    }

    /// SwiftUI 那一邊（面板的勾與鮮度線）。
    static func color(_ glow: FinishGlow, onDark: Bool) -> Color {
        Color(nsColor: glow == .faded
              ? finishFaded(onDark: onDark, ink: onDark ? .white : .black)
              : finish(onDark: onDark))
    }

    /// `amount` 是**保留原色**的比例，其餘混向 `toward` —— 與 `Breath.opacity`
    /// 的語意一致（minOpacity 是「最暗的那一格還剩多少」）。
    private static func blend(_ c: NSColor, toward: NSColor, amount: Double) -> NSColor {
        guard let a = c.usingColorSpace(.sRGB), let b = toward.usingColorSpace(.sRGB) else {
            return c
        }
        let keep = CGFloat(amount), rest = 1 - keep
        return NSColor(srgbRed: a.redComponent * keep + b.redComponent * rest,
                       green: a.greenComponent * keep + b.greenComponent * rest,
                       blue: a.blueComponent * keep + b.blueComponent * rest,
                       alpha: 1)
    }
}
