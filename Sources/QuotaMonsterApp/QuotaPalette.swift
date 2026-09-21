import AppKit
import SwiftUI
import QuotaMonsterCore

/// 額度分級的顏色，**選單列圖示與下拉面板共用同一份定義**。
///
/// 為什麼要共用：面板上那三條進度條與選單列上的圖示講的是同一件事。
/// 各自寫一組顏色，改了其中一邊就會變成兩套語彙，而且不會有人馬上發現。
///
/// 配色 **藍 → 綠 → 紅**（使用者 2026-09-18 指定）。
///
/// ⚠️ **黃色不可以出現在這裡。** 黃／琥珀是「要你輸入」（警示狀態）專屬的顏色，
/// 拿來表示額度多寡會把整個 app 裡唯一有時限的訊號稀釋掉。
enum QuotaPalette {

    /// - Parameter onDark: 畫在深色背景上（深色選單列、深色面板）。
    ///   同一組色值在淺色背景上夠深、在深色背景上就偏悶，兩邊必須分開給。
    static func nsColor(_ tier: QuotaTier, onDark: Bool) -> NSColor {
        switch (tier, onDark) {
        // 藍刻意偏深（使用者要求「藍色要用深一點的」）。深色背景那一版仍然要
        // 亮到能從選單列灰底裡跳出來，所以不是把淺色那版直接搬過去。
        case (.comfortable, false): return NSColor(srgbRed: 0.00, green: 0.30, blue: 0.75, alpha: 1)
        case (.comfortable, true):  return NSColor(srgbRed: 0.16, green: 0.46, blue: 0.95, alpha: 1)
        case (.tight, false):       return NSColor(srgbRed: 0.13, green: 0.60, blue: 0.32, alpha: 1)
        case (.tight, true):        return NSColor(srgbRed: 0.30, green: 0.84, blue: 0.48, alpha: 1)
        case (.critical, false):    return NSColor(srgbRed: 0.82, green: 0.13, blue: 0.13, alpha: 1)
        case (.critical, true):     return NSColor(srgbRed: 1.00, green: 0.38, blue: 0.36, alpha: 1)
        }
    }

    static func color(_ tier: QuotaTier, onDark: Bool) -> Color {
        Color(nsColor: nsColor(tier, onDark: onDark))
    }
}
