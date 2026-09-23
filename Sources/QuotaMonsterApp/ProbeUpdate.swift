import Foundation
import AppKit
import QuotaMonsterCore

/// `QuotaMonsterApp --probe-update [--as <版本>]`：**真的**去問一次 GitHub。
///
/// ### 它回答哪一個問題
/// 「更新檢查那條路通不通，以及它現在會說什麼。」
/// 面板上「什麼都不說」有**三個**不同的原因（已經是最新的／還沒問過／
/// 問到的東西不能用），三個在畫面上長得一模一樣 —— 這支把它們分開。
///
/// `--as 0.0.1` 假裝自己是舊版，用來驗「有新版」那條路真的走得通
/// （不然在剛發完版的當下永遠測不到）。
/// ⚠️ 它只影響**這一次**的比較，不寫任何檔案。
///
/// ⚠️ **這支會真的連網**，與偏好設定無關 —— 它是你主動下的指令。
/// 平常的 app 只有在偏好那一格是開的時候才會發請求。
///
/// 它**不能**證明：面板那一條畫得對不對（那是 `--render-panel --demo-update`）。
@MainActor
enum ProbeUpdate {
    static func run() async {
        let store = DataStore()
        let bundled = store.currentVersion
        let pretend = CommandLine.arguments.firstIndex(of: "--as")
            .flatMap { CommandLine.arguments.count > $0 + 1 ? CommandLine.arguments[$0 + 1] : nil }
            .flatMap(ReleaseVersion.init)

        print("── 這一份 app ──────────────────────────────────")
        print("  bundle 版本      \(bundled?.text ?? "—（不是 .app，所以平常不會檢查）")")
        if let pretend { print("  ⚠️ 這次假裝是   \(pretend.text)（--as）") }
        print("  偏好「檢查更新」  \(store.checksForUpdates ? "開" : "關")"
              + "（⚠️ 這支不理它，它是你主動下的指令）")

        // 沒有 bundle 版本時用 0.0.0 當基準 —— 這樣純 CLI 也問得到東西，
        // 而且不會假裝自己知道 bundle 版本。
        let current = pretend ?? bundled ?? ReleaseVersion("0.0.0")!
        let checker = ReleaseChecker(home: FileManager.default.homeDirectoryForCurrentUser)
        let t0 = DispatchTime.now().uptimeNanoseconds
        await checker.check(current: current, now: Date())
        let ms = Double(DispatchTime.now().uptimeNanoseconds - t0) / 1_000_000

        print("── 問到什麼 ────────────────────────────────────")
        print(String(format: "  花了           %.0f ms", ms))
        switch checker.status {
        case .available(let v, let url):
            print("  結果           有新版 \(v.text)")
            print("  連結           \(url)")
        case .upToDate:
            print("  結果           已經是最新的（**正面證據** —— 真的問到了）")
        case .unknown(let r):
            print("  結果           不知道 —— \(describe(r))")
            print("  ⚠️ 「不知道」與「已經是最新的」是兩件事，面板上也分開畫。")
        }
        print("  上次成功        \(checker.lastSuccess.map(String.init(describing:)) ?? "從來沒有")")
        print("── 面板會說什麼 ────────────────────────────────")
        let caption = UpdateCaption.text(checker.status, lastSuccess: checker.lastSuccess, now: Date())
        print("  「\(caption ?? "（什麼都不說）")」")
        NSApp.terminate(nil)
    }

    static func describe(_ r: UpdateStatus.Reason) -> String {
        switch r {
        case .notCheckedYet:         return "還沒問過"
        case .offline:               return "連不上（沒網路／DNS／逾時）"
        case .rateLimited:           return "被限流（未認證是 60 次/小時/IP）"
        case .unreadable:            return "回應不是我們認得的形狀"
        case .unparseableTag(let t): return "tag「\(t)」解不出版本號"
        case .draftOrPrerelease:     return "最新那一筆是草稿或預覽版"
        }
    }
}
