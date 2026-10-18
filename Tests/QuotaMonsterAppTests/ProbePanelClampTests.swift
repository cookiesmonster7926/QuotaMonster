import Testing
import AppKit
import SwiftUI
@testable import QuotaMonsterApp
@testable import QuotaMonsterCore

/// `--probe-panel-clamp` 自己的判讀 —— 它是規矩 27 的驗證指令，判錯就等於沒有驗證。
///
/// 兩種「沒量到卻報結論」的錯各擋一次：
/// 1. 偏好是簡易頁：合成的 session 不會出現在簡易頁，內容遠矮於螢幕，
///    兩條邊界檢查自然都過 —— 「沒造出超高內容」被報成「超高內容留在螢幕裡」。
/// 2. 沒有螢幕、popover 沒有 window：「整個沒看到」被報成「超出螢幕」（exit 1）。
///
/// ⚠️ 家目錄是空的暫存目錄（只放一份偏好檔），session 全部是合成的。
@Suite("--probe-panel-clamp 的判讀")
@MainActor
struct ProbePanelClampTests {

    /// 一個「使用者存的偏好是簡易頁」的家目錄 —— 探針用 `DataStore()` 會讀到的那種。
    func simpleHome() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-probe-clamp-\(UUID().uuidString)")
        let file = root.appendingPathComponent(Preferences.relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(#"{"panelStyle":"simple"}"#.utf8).write(to: file)
        return root
    }

    func simpleStore(_ home: URL? = nil) throws -> DataStore {
        let s = DataStore(home: try home ?? simpleHome())
        let (sessions, trees) = ProbePanelClamp.syntheticSessions(tall: true)
        s.seedSyntheticSessions(sessions, trees: trees)
        return s
    }

    @Test("前提：偏好是簡易頁時，合成的超高內容根本不出現")
    func simpleLayoutHidesTheTallContent() throws {
        let s = try simpleStore()
        #expect(s.panelStyle == .simple)
        #expect(ProbePanelClamp.naturalHeight(s) < 1000)
    }

    @Test("探針把版面強制成完整版 → 合成內容真的比螢幕高")
    func forcedFullLayoutIsTall() throws {
        let s = try simpleStore()
        ProbePanelClamp.forceFullLayout(s)
        #expect(s.panelStyle == .full)
        #expect(ProbePanelClamp.naturalHeight(s) > 1000)
    }

    @Test("強制完整版只改記憶體，不改使用者的偏好檔（規矩 44）")
    func forcingDoesNotPersist() throws {
        let home = try simpleHome()
        ProbePanelClamp.forceFullLayout(try simpleStore(home))
        let reread = DataStore(home: home)
        #expect(reread.panelStyle == .simple)
    }

    @Test("量到了、在螢幕裡 → exit 0")
    func onScreenIsZero() {
        #expect(ProbePanelClamp.conclusion(offScreen: false, unmeasured: []).code == 0)
    }

    @Test("量到了、超出 → exit 1")
    func offScreenIsOne() {
        let c = ProbePanelClamp.conclusion(offScreen: true, unmeasured: [])
        #expect(c.code == 1)
        #expect(c.line.contains("超出"))
    }

    @Test("量不到（沒有 window、沒造出超高內容）→ exit 2，結論不說「超出」也不說「留在螢幕裡」")
    func unmeasuredIsTwo() {
        let c = ProbePanelClamp.conclusion(offScreen: false, unmeasured: ["popover 沒有 window"])
        #expect(c.code == 2)
        #expect(c.line.contains("量不到"))
        #expect(c.line.contains("popover 沒有 window"))
        #expect(!c.line.contains("超出"))
        #expect(!c.line.contains("留在螢幕裡"))
    }

    /// 看到它、而且它超出了 → 正面證據，不因為另一個時點沒量到就降級成「量不到」。
    @Test("有一個時點量到超出、另一個時點量不到 → 仍然是 exit 1")
    func measuredOverflowWinsOverUnmeasured() {
        #expect(ProbePanelClamp.conclusion(offScreen: true,
                                           unmeasured: ["popover 沒有 window"]).code == 1)
    }
}
