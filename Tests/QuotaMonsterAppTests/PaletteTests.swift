import Testing
import AppKit
@testable import QuotaMonsterApp
@testable import QuotaMonsterCore

/// 色彩政策。
///
/// 這個 repo 最大聲的一條規矩是「**黃／琥珀只代表『要你輸入』**，額度色階不得
/// 使用任何黃色」——〔2026-09-19 建立這個 test target 之前〕它**完全沒有
/// 東西守著**，只有註解。而顏色改壞了不會有任何錯誤，只會讓整個 app 裡唯一
/// 有時限的訊號被稀釋掉，然後沒有人發現。
@Suite("色彩政策 — 哪個顏色歸誰")
@MainActor
struct PaletteTests {

    /// 色相，單位是度。
    func hue(_ c: NSColor) -> Double {
        guard let s = c.usingColorSpace(.sRGB) else { return -1 }
        return Double(s.hueComponent) * 360
    }

    /// 兩個色相在色相環上的最短距離。
    func separation(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(d, 360 - d)
    }

    /// 琥珀（「要你輸入」專用）。`GlyphRenderer.alert` 是它的唯一定義。
    var amber: Double { hue(GlyphRenderer.alert) }

    var quotaColours: [(name: String, colour: NSColor)] {
        [QuotaTier.comfortable, .tight, .critical].flatMap { tier in
            [(", 淺色", false), ("，深色", true)].map { suffix, dark in
                ("\(tier)\(suffix)", QuotaPalette.nsColor(tier, onDark: dark))
            }
        }
    }

    @Test("⚠️ 額度色階裡沒有任何一格是黃／琥珀")
    func noAmberInTheQuotaRamp() {
        // 黃到琥珀大約落在 35°–70°。這一則會在「把 tight 改回黃色」那種改動上紅
        // ——而那正是 2026-09-18 之前的樣子，改掉之後只留了一段註解擋著。
        for (name, colour) in quotaColours {
            let h = hue(colour)
            #expect(!(h >= 35 && h <= 70), "額度色階的 \(name) 落在黃色帶（色相 \(Int(h))°）")
        }
    }

    // ⚠️ 這裡**刻意沒有**「每一格額度色都要離琥珀夠遠」那一則。
    //
    // 我寫過，然後它紅了：〔實測〕critical 的紅距琥珀只有 34–36°。
    // 但那不是程式碼錯，是那條規矩我自己發明的 —— 這個專案的規矩只有
    // 「額度色階裡不可以有黃色」，而警示狀態**不是靠顏色**跟額度區分的，
    // 它是完全不同的形狀（滿環 + 箭頭）而且是唯一會呼吸的。
    // 把一個沒有人承諾過的性質寫成測試，就是把自己的品味偽裝成規矩。

    @Test("⚠️ 丁香紫與琥珀、與每一格額度色都分得開")
    func lilacIsInItsOwnNeighbourhood() {
        // 完成訊號選 284° 的理由就是「色相環上唯一沒有鄰居的空地」。
        // 這一則守的是那個理由，不是那個數字。
        for dark in [true, false] {
            let lilac = hue(SignalPalette.finish(onDark: dark))
            #expect(separation(lilac, amber) >= 60,
                    "丁香紫距琥珀只有 \(Int(separation(lilac, amber)))°")
            for (name, colour) in quotaColours {
                let d = separation(lilac, hue(colour))
                #expect(d >= 45, "丁香紫距 \(name) 只有 \(Int(d))°")
            }
        }
    }

    @Test("退色版是混向墨色算出來的，不是另外寫死一個 hex")
    func fadedLilacIsComputedNotHardcoded() {
        // mockup 給的深色退色版是 #F1CBFF。這一則同時釘住兩件事：
        // 算出來的值對得上 mockup，而且它**真的是混合**（改成降 alpha 會紅）。
        let faded = SignalPalette.finishFaded(onDark: true, ink: .white)
            .usingColorSpace(.sRGB)!
        #expect(abs(faded.redComponent - 0xF1 / 255.0) < 0.01)
        #expect(abs(faded.greenComponent - 0xCB / 255.0) < 0.01)
        #expect(abs(faded.blueComponent - 0xFF / 255.0) < 0.01)
        // ⚠️ 混向墨色，不是降不透明度 —— alpha 0.45 已經被 freshness == .expired 佔走。
        #expect(faded.alphaComponent == 1)
    }

    @Test("退色版要往墨色走 —— 兩種選單列都是")
    func fadedLilacMovesTowardTheInk() {
        // ⚠️ 不可以用「退色後更亮／更暗」去量。我第一版那樣寫，深色那半當場紅：
        // 丁香紫的 HSB brightness 本來就是 1.0（藍分量滿格），混向白改變的是
        // **飽和度**不是亮度。「混向墨色」的字面意思是**離墨色更近**，
        // 所以就量距離 —— 而且這個量法對深色（白墨）與淺色（黑墨）都成立。
        func distance(_ a: NSColor, _ b: NSColor) -> Double {
            let x = a.usingColorSpace(.sRGB)!, y = b.usingColorSpace(.sRGB)!
            return pow(x.redComponent - y.redComponent, 2)
                + pow(x.greenComponent - y.greenComponent, 2)
                + pow(x.blueComponent - y.blueComponent, 2)
        }
        for (dark, ink) in [(true, NSColor.white), (false, NSColor.black)] {
            let base = SignalPalette.finish(onDark: dark)
            let faded = SignalPalette.finishFaded(onDark: dark, ink: ink)
            #expect(distance(faded, ink) < distance(base, ink),
                    "退色版沒有比較靠近墨色 —— 它不是混出來的")
        }
    }
}
