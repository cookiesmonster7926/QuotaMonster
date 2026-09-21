import Testing
import Foundation
@testable import QuotaMonsterCore

/// 為什麼不能只看 pid：
/// crash 掉的 session 會留下一個**永遠寫著 busy** 的檔案（實測有 session 宣稱 busy 41 分鐘），
/// 而 pid 會被系統回收再利用。只驗 pid 的話，一個不相干的新行程會讓那個死掉的
/// session 復活。必須同時比對行程的真實啟動時間。
@Suite("ProcessLiveness")
struct ProcessLivenessTests {

    @Test("自己的 pid 是活的")
    func ownPidIsAlive() {
        // 測試行程本身啟動不久，所以「現在」落在容差內。
        #expect(ProcessLiveness.isAlive(pid: getpid(), startedAt: Date()) == true)
    }

    @Test("不存在的 pid 是死的")
    func impossiblePidIsDead() {
        #expect(ProcessLiveness.isAlive(pid: 999_999, startedAt: Date()) == false)
    }

    @Test("pid 被回收再利用時要判定為死 —— 啟動時間對不上")
    func recycledPidWithMismatchedStartTimeIsDead() {
        let anHourAgo = Date().addingTimeInterval(-3600)
        #expect(ProcessLiveness.isAlive(pid: getpid(), startedAt: anHourAgo) == false)
    }

    @Test("啟動時間在容差內視為同一個行程")
    func startTimeWithinToleranceIsAlive() {
        let slightlyOff = Date().addingTimeInterval(-ProcessLiveness.reuseTolerance + 30)
        #expect(ProcessLiveness.isAlive(pid: getpid(), startedAt: slightlyOff) == true)
    }

    @Test("容差是 300 秒")
    func toleranceIsFiveMinutes() {
        #expect(ProcessLiveness.reuseTolerance == 300)
    }

    @Test("能取得自己行程的真實啟動時間，且它在過去")
    func canReadOwnStartTime() throws {
        let start = try #require(ProcessLiveness.processStartTime(getpid()))
        #expect(start < Date())
        #expect(start > Date().addingTimeInterval(-86_400))
    }

    @Test("取不到啟動時間的 pid 視為死")
    func unknownStartTimeIsDead() {
        #expect(ProcessLiveness.processStartTime(999_999) == nil)
    }
}
