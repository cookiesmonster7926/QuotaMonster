import Testing
import Foundation
@testable import QuotaMonsterCore

/// run 狀態檔 `<sessionId>/workflows/<wf_id>.json`。
///
/// 它是 T2 判定「整批排空」的正面證據（見 `NotificationEngine.observeBatches`），
/// 也是「這批跑了多久」唯一誠實的來源 —— journal 的行**完全沒有時間戳**
/// 〔實測 36 個 journal / 343 個 started 行〕，所以任何想從 journal 算時長的
/// 設計都只能退回檔案時間，而檔案時間在被中止的 run 上會差 344 秒。
@Suite("WorkflowRunState")
struct WorkflowRunStateTests {

    let reader = WorkflowRunStateReader()

    func read(_ json: String, runId: String = "wf_x") throws -> WorkflowRunState? {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-runstate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try json.write(to: dir.appendingPathComponent("\(runId).json"),
                       atomically: true, encoding: .utf8)
        return reader.read(runId: runId, in: dir)
    }

    @Test("durationMs 是毫秒，讀進來一定要是秒 —— 345160 → 345.16")
    func millisecondsBecomeSeconds() throws {
        // 值刻意**不是整秒**，這一則才抓得到三種錯法：
        // 忘了除 → 345160；Int 除法（`.intValue / 1000`）→ 345.0；除兩次 → 0.34516。
        // 這是整個修法唯一的單位換算點，換算只准發生在 reader 那一行。
        //
        // 345160 是磁碟上那個真實 killed run（wf_8530e53f-b3b）的值。
        let s = try #require(try read(#"{"runId":"wf_x","status":"killed","durationMs":345160}"#))
        #expect(s.duration == 345.16)
    }

    @Test("有 status 但沒有 durationMs —— duration 是 nil，而且不可以把 status 一起吞掉")
    func missingDurationIsNilNotZero() throws {
        // 任何 `?? 0` 的實作在這裡拿到 0 → 紅。
        // 兩個斷言一起寫：少了附屬欄位不可以讓整個狀態讀不回來。
        let s = try #require(try read(#"{"runId":"wf_x","status":"completed"}"#))
        #expect(s.status == "completed")
        #expect(s.duration == nil)
    }

    @Test("durationMs 是負數時當成不知道")
    func negativeDurationIsNil() throws {
        // ⚠️ **這是推論不是量測。**〔實測 n=34〕磁碟上 0 個負值。
        // 這一則防的是時鐘回調與未來的格式變動，不是已觀測到的現象。
        let s = try #require(try read(#"{"runId":"wf_x","status":"completed","durationMs":-1}"#))
        #expect(s.duration == nil)
    }

    @Test("未來版本把 durationMs 寫成浮點數也要讀得到")
    func floatingPointDurationIsRead() throws {
        // ⚠️ 同樣是防未來：〔實測〕34/34 都是整數。
        // `as? Int` 的實作在這裡會失敗（JSONSerialization 給的 NSNumber 條件轉型
        // 到 Int 對非整數值回 nil）→ 紅。這也是為什麼要用 NSNumber?.doubleValue，
        // 而不是 `Int(...)` —— 後者在這個 repo 有明文血訓（1e18 打得死整個行程）。
        let s = try #require(try read(#"{"runId":"wf_x","status":"completed","durationMs":345160.5}"#))
        #expect(s.duration == 345.1605)
    }

    @Test("status 讀不到時 duration 也不算數 —— 檔案不存在回 nil，不丟錯")
    func missingFileIsNil() {
        let dir = URL(fileURLWithPath: "/tmp/nope-\(UUID().uuidString)")
        #expect(reader.read(runId: "wf_x", in: dir) == nil)
    }
}
