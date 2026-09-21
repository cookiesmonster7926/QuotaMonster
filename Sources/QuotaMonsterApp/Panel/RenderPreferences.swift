import SwiftUI
import AppKit
import QuotaMonsterCore

/// `--render-prefs <file.png> --dark`：把偏好設定視窗離屏渲染成 PNG。
///
/// ⚠️ **這支診斷有兩個會讓它「說謊而不是沉默」的洞，都已經在 UI 那邊擋掉：**
/// 1. `Picker` 預設樣式是 `.menu`，離屏渲染會畫成一個紅色禁止符號 ——
///    那不是空白，是一張**看起來很正常但那個角落是假的圖**。
/// 2. `ScrollView` 在 `ImageRenderer` 底下畫成空的。
/// `PreferencesView` 因此完全不用這三個元件（連 `Menu` 也不用）。
@MainActor
enum RenderPreferences {
    static func run(path: String) {
        let store = DataStore()
        store.refresh()

        // ⚠️ 一定要看深色版：使用者的面板是深色的，這個專案已經兩次因為
        // 用淺色渲染判斷配色而得到相反的結論。
        let dark = CommandLine.arguments.contains("--dark")
        let view = PreferencesView(store: store, sounds: AlertSound.available())
            .background(Color(nsColor: .windowBackgroundColor))
            .environment(\.colorScheme, dark ? .dark : .light)

        let natural = NSHostingController(rootView: view).view.fittingSize
        FileHandle.standardError.write(Data(
            "偏好視窗自然尺寸 \(Int(natural.width))×\(Int(natural.height))pt\n".utf8))

        let renderer = ImageRenderer(content: view.frame(width: natural.width,
                                                         height: natural.height))
        // ⚠️ scale 2 —— 這台機器是 Retina，2x 才是使用者每天真正看到的尺寸。
        renderer.scale = 2
        guard let img = renderer.nsImage,
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            print("render failed"); return
        }
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try? png.write(to: url)
        print("偏好視窗已渲染 → \(url.path)")
        print("⚠️ 這張圖用的是**目前實際的偏好檔**，不是合成資料。")
        print("   音效清單掃到 \(AlertSound.available().count) 個。")
    }
}
