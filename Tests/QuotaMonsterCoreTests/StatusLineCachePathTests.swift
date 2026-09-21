import Testing
import Foundation
@testable import QuotaMonsterCore

/// shell wrapper 與 Swift 讀取端各自寫了一次快取目錄的路徑。
/// 兩邊寫得不一樣**不會有任何錯誤訊息** —— wrapper 照常寫檔、app 照常讀到空目錄，
/// 表現出來只是「tee 裝了但額度還是顯示過期」，而那正是這個 Stage 要解決的症狀。
/// 所以這裡直接去讀 repo 裡的那支 shell 腳本來比對。
@Suite("StatusLineCachePath")
struct StatusLineCachePathTests {

    /// 從這個原始檔的位置往上找到 repo 根目錄。
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)          // Tests/QuotaMonsterCoreTests/<this>.swift
            .deletingLastPathComponent()          // Tests/QuotaMonsterCoreTests
            .deletingLastPathComponent()          // Tests
            .deletingLastPathComponent()          // repo root
    }

    /// 從 wrapper 裡把 `DIR="${QM_STATUSLINE_CACHE_DIR:-<預設值>}"` 的預設值挖出來。
    static func shellDefaultCacheDir(_ text: String) throws -> String {
        let pattern = #"DIR="\$\{QM_STATUSLINE_CACHE_DIR:-(.+?)\}""#
        let re = try NSRegularExpression(pattern: pattern)
        let range = NSRange(text.startIndex..., in: text)
        let m = try #require(re.firstMatch(in: text, range: range),
                             "在 quotamonster-tee.sh 裡找不到 DIR 的預設值")
        return String(text[Range(m.range(at: 1), in: text)!])
    }

    @Test("Swift 與 shell wrapper 用的是同一個快取路徑（完全相同，不是「包含」）")
    func swiftAndShellAgreeOnTheCacheDirectory() throws {
        let script = Self.repoRoot.appendingPathComponent("scripts/quotamonster-tee.sh")
        let text = try String(contentsOf: script, encoding: .utf8)

        // 用 contains 是不夠的：shell 那邊改成 ".../statusline2" 仍然「包含」原字串，
        // 路徑就這樣悄悄分岔，而分岔的症狀只是「tee 裝了但額度還是過期」。
        let shellDefault = try Self.shellDefaultCacheDir(text)
        #expect(shellDefault == "$HOME/" + StatusLineCacheReader.relativeCacheDirectory)
    }

    @Test("組出來的絕對路徑就是 wrapper 會寫入的那一個")
    func absolutePathIsUnderApplicationSupport() {
        let home = URL(fileURLWithPath: "/Users/example")
        #expect(StatusLineCacheReader.defaultDirectory(home: home).path
                == "/Users/example/Library/Application Support/QuotaMonster/statusline")
    }
}
