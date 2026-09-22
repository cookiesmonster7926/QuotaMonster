import Foundation
import AppKit
import QuotaMonsterCore

/// `QuotaMonsterApp --bench-refresh [n]`：量一拍 `DataStore.refresh()` 要多久。
///
/// ### 它回答哪一個問題
/// 「面板每 3 秒刷新一次，那一拍在 main actor 上花掉多少時間？」
/// 〔實測 2026-09-22〕在增量讀取之前，這台機器上第二拍之後每拍仍然要把
/// 每一個活著的 session 的母 transcript **整份重新解析**一次。
///
/// ### ⚠️ 第一拍與其餘的必須分開報
/// 第一拍是**補課**：游標從 0 開始，整份讀完。把它混進平均數會同時
/// 高估穩態成本、低估補課成本 —— 兩個數字都變成沒有意義的第三個數字。
/// （同一個錯在這個 repo 的快取新鮮度上犯過：把「什麼時候寫的」
/// 與「內容什麼時候量的」混成一個數。）
///
/// 它**不能**證明的事：實際 app 的一拍還包含 SwiftUI 重繪與通知送出，
/// 這裡只量 `refresh()`。
@MainActor
enum BenchRefresh {
    static func run(iterations: Int) {
        let store = DataStore()
        var ms: [Double] = []
        for _ in 0..<max(iterations, 2) {
            // ⚠️ `autoreleasepool` 不可省，而且要**包在計時裡面**。
            // 這支是純 CLI 迴圈，沒有 runloop 幫忙排乾 pool ——〔code review 2026-09-22〕
            // 少了它每拍 RSS 長約 5MB 且不封頂，跑久了量到的就不只是 refresh 的成本。
            // 放在計時窗口內是因為排乾的成本本來就屬於那一拍
            // （與這個檔頭「第一拍與其餘分開報」同一條理由）。
            let t0 = DispatchTime.now().uptimeNanoseconds
            autoreleasepool { store.refresh() }
            let t1 = DispatchTime.now().uptimeNanoseconds
            ms.append(Double(t1 - t0) / 1_000_000)
        }
        let first = ms[0]
        let rest = Array(ms.dropFirst()).sorted()
        let median = rest[rest.count / 2]

        print("每拍 refresh() 的耗時（毫秒）")
        print("  session \(store.sessions.count) 個，agent 樹 \(store.trees.count) 棵")
        print("  第一拍（補課，游標從 0 開始）  \(String(format: "%.1f", first))")
        print("  其餘 \(rest.count) 拍  中位 \(String(format: "%.1f", median))"
            + "  最小 \(String(format: "%.1f", rest.first ?? 0))"
            + "  最大 \(String(format: "%.1f", rest.last ?? 0))")
        print("  逐拍：" + ms.map { String(format: "%.0f", $0) }.joined(separator: " "))
        // 面板的節奏是 3000 毫秒一拍 —— 穩態超過它的十分之一就值得說一句。
        let budget = DataStore.refreshInterval * 1000 / 10
        if median > budget {
            print("  ⚠️ 穩態中位 \(String(format: "%.1f", median)) 毫秒 > 一拍預算的十分之一"
                + "（\(String(format: "%.0f", budget)) 毫秒）")
        }
    }
}
