import Testing
import Foundation
@testable import QuotaMonsterApp
@testable import QuotaMonsterCore

/// 偏好檔有沒有真的被讀進來。
///
/// ⚠️ 〔實測 2026-09-22〕在此之前**三個** `DataStore` 的建立點裡有三個沒有讀偏好：
/// `RenderPanel`、`RenderPreferences`、`ProbePopover` 都只呼叫 `refresh()`，
/// 而讀檔在 `start()` 裡。後果不是「少一個功能」，是**驗證整個變成安慰劑**：
/// `--render-prefs` 那張圖是拿來檢查偏好視窗的，而它畫的一直是預設值 ——
/// 它甚至在 stdout 印「這張圖用的是目前實際的偏好檔」。
///
/// 修法不是在那三個地方各補一行（那只是把同一個洞留給第四個建立點），
/// 是把讀檔移進 `init` —— **建得出 DataStore 就一定有偏好**。
@Suite("DataStore — 偏好在 init 就要讀進來")
@MainActor
struct DataStorePreferencesTests {

    /// 造一個只有 preferences.json 的假家目錄。
    func home(_ json: String) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-prefs-\(UUID().uuidString)")
        let file = root.appendingPathComponent(Preferences.relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data(json.utf8).write(to: file)
        return root
    }

    @Test("一建好就看得到偏好，不必等 start()")
    func preferencesAreLoadedAtInit() throws {
        let h = try home(#"{"chartStyle":"cumulative"}"#)
        #expect(DataStore(home: h).chartStyle == .cumulative)
    }

    @Test("沒有偏好檔時用預設值 —— 不可以爆，也不可以留著空的")
    func missingFileFallsBackToTheDefault() throws {
        let empty = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-prefs-none-\(UUID().uuidString)")
        #expect(DataStore(home: empty).chartStyle == ChartStyle.standard)
    }

    @Test("壞掉的偏好檔也用預設值")
    func brokenFileFallsBackToTheDefault() throws {
        let h = try home("{ this is not json")
        #expect(DataStore(home: h).chartStyle == ChartStyle.standard)
    }
}
