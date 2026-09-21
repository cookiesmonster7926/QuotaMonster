import Testing
import Foundation
@testable import QuotaMonsterCore

/// 沉澱窗狀態機。
///
/// ⚠️ **沉澱窗不是偵測。** 安靜只決定「何時去看」，決定「完成沒」的是尾端那一則的
/// `stop_reason`。這個分工是整個方案的救命符：〔實測〕105 次超過 90 秒的安靜
/// （長 Bash、模型想很久、使用者在打字）往回看到的全部是 `tool_use`，誤報 0 次。
@Suite("CompletionTracker — 哪個 session 剛講完")
struct CompletionTrackerTests {

    let t0 = Date(timeIntervalSince1970: 1_789_660_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    let url = URL(fileURLWithPath: "/tmp/s.jsonl")
    var input: CompletionInput { CompletionInput(transcripts: ["S1": url]) }

    /// 可變的假磁碟。closure 要 @Sendable，所以用 class 包起來。
    final class Disk: @unchecked Sendable {
        var mtime: Date?
        var readout: TurnReadout
        var turnStart: Date?
        var tailReads = 0
        init(mtime: Date?, readout: TurnReadout = .unfinished, turnStart: Date? = nil) {
            self.mtime = mtime; self.readout = readout; self.turnStart = turnStart
        }
    }

    func tracker(_ disk: Disk) -> CompletionTracker {
        CompletionTracker(
            readTail: { _ in disk.tailReads += 1; return disk.readout },
            readTurnStart: { _ in disk.turnStart },
            modifiedAt: { _ in disk.mtime })
    }

    // ── 見證 ────────────────────────────────────────────────────

    @Test("第一次看到只記錄，不讀也不發 —— 我們沒有見證它完成")
    func firstSightOnlySeeds() {
        // app 剛啟動時尾端**已經**是 end_turn 的那些 session。少了這一條，
        // make_app.sh 每次重啟都會對著三個 session 同時亮。
        let disk = Disk(mtime: at(0), readout: .finished(TurnEnd(finishedAt: at(-10))))
        var t = tracker(disk)
        #expect(t.update(input, now: at(0)).finishes.isEmpty)
        #expect(disk.tailReads == 0)
    }

    @Test("安靜滿 90 秒才去讀，而且一次安靜只讀一次")
    func readsOnceAfterTheSettleWindow() {
        let disk = Disk(mtime: at(0), readout: .unfinished)
        var t = tracker(disk)
        _ = t.update(input, now: at(0))
        _ = t.update(input, now: at(89))
        #expect(disk.tailReads == 0)            // 還沒滿
        _ = t.update(input, now: at(90))
        #expect(disk.tailReads == 1)
        _ = t.update(input, now: at(200))       // 還是同一次安靜
        #expect(disk.tailReads == 1)
    }

    @Test("見證一次完成 —— 發一則，而且只有一則")
    func announcesOnce() throws {
        let disk = Disk(mtime: at(0))
        var t = tracker(disk)
        _ = t.update(input, now: at(0))
        disk.readout = .finished(TurnEnd(finishedAt: at(5)))
        let out = t.update(input, now: at(90))
        #expect(out.finishes.count == 1)
        #expect(try #require(out.finishes.first).finishedAt == at(5))
        #expect(t.update(input, now: at(120)).finishes.isEmpty)
    }

    @Test("尾端還在跑 —— 不發")
    func unfinishedDoesNotAnnounce() {
        let disk = Disk(mtime: at(0), readout: .unfinished)
        var t = tracker(disk)
        _ = t.update(input, now: at(0))
        #expect(t.update(input, now: at(90)).finishes.isEmpty)
    }

    @Test("讀不到尾端 —— 不發。inconclusive 不是「還在跑」也不是「完成了」")
    func inconclusiveDoesNotAnnounce() {
        let disk = Disk(mtime: at(0), readout: .inconclusive)
        var t = tracker(disk)
        _ = t.update(input, now: at(0))
        #expect(t.update(input, now: at(90)).finishes.isEmpty)
    }

    // ── 又動起來了 ──────────────────────────────────────────────

    @Test("transcript 又被寫了 —— 進 wrote，而且沉澱重新計時")
    func writingResetsTheWindow() {
        let disk = Disk(mtime: at(0), readout: .finished(TurnEnd(finishedAt: at(5))))
        var t = tracker(disk)
        _ = t.update(input, now: at(0))
        disk.mtime = at(50)
        let out = t.update(input, now: at(50))
        #expect(out.wrote == ["S1"])
        // 從 50 起重新算 90 秒，所以 at(100) 還不該讀。
        _ = t.update(input, now: at(100))
        #expect(disk.tailReads == 0)
        _ = t.update(input, now: at(140))
        #expect(disk.tailReads == 1)
    }

    @Test("stat 失敗什麼都不動 —— 讀不到 mtime 不等於「它安靜了」")
    func unreadableMtimeIsNotSilence() {
        // 這一格是「不存在 ≠ 那個狀態不成立」。把 nil 當成安靜的實作會在
        // 檔案暫時讀不到的時候憑空宣告完成。
        let disk = Disk(mtime: at(0), readout: .finished(TurnEnd(finishedAt: at(5))))
        var t = tracker(disk)
        _ = t.update(input, now: at(0))
        disk.mtime = nil
        #expect(t.update(input, now: at(90)).finishes.isEmpty)
        #expect(disk.tailReads == 0)
    }

    // ── 跨重啟 ──────────────────────────────────────────────────

    @Test("app 重啟後接手 —— 在我們看到它之前就完成的那一輪不發")
    func finishesBeforeFirstSightAreDropped() {
        // ⚠️ 用「有沒有寫過」當閂鎖是不夠的：一個 120 秒前完成的 session，
        // 重啟後只要 harness 寫一行就過關，而 600 秒的上限也攔不住。
        // 判準是時間比較 —— finishedAt 早於我們第一次看到它就丟掉。
        let disk = Disk(mtime: at(0))
        var t = tracker(disk)
        _ = t.update(input, now: at(100))            // 第一次看到是 t=100
        disk.mtime = at(120)
        _ = t.update(input, now: at(120))            // harness 寫了一行
        disk.readout = .finished(TurnEnd(finishedAt: at(60)))   // 那一輪在 t=60 就完成了
        #expect(t.update(input, now: at(210)).finishes.isEmpty)
    }

    @Test("同一個完成時刻不重發")
    func sameFinishIsNotAnnouncedTwice() {
        let disk = Disk(mtime: at(0), readout: .finished(TurnEnd(finishedAt: at(5))))
        var t = tracker(disk)
        _ = t.update(input, now: at(0))
        #expect(t.update(input, now: at(90)).finishes.count == 1)
        // 又被寫了一行收尾資料，沉澱重來，尾端還是同一則 end_turn。
        disk.mtime = at(100)
        _ = t.update(input, now: at(100))
        #expect(t.update(input, now: at(190)).finishes.isEmpty)
    }

    @Test("太舊的完成不發 —— 超過壽命就不是新聞了")
    func staleFinishesAreDropped() {
        let disk = Disk(mtime: at(0), readout: .finished(TurnEnd(finishedAt: at(1))))
        var t = tracker(disk)
        _ = t.update(input, now: at(0))
        #expect(t.update(input, now: at(700)).finishes.isEmpty)
    }

    // ── 跑了多久 ────────────────────────────────────────────────

    @Test("回合起點在「又動起來」那一刻讀一次 —— ranFor 從它算")
    func ranForComesFromTheTurnStart() throws {
        let disk = Disk(mtime: at(0))
        var t = tracker(disk)
        _ = t.update(input, now: at(0))
        _ = t.update(input, now: at(90))             // 確認安靜
        disk.mtime = at(100)
        disk.turnStart = at(95)                      // 使用者在 95 秒打了字
        _ = t.update(input, now: at(100))
        disk.readout = .finished(TurnEnd(finishedAt: at(800)))
        let out = t.update(input, now: at(820))
        #expect(try #require(out.finishes.first).ranFor == 705)
    }

    @Test("讀不到回合起點 —— ranFor 是 nil，不是 0")
    func unknownTurnStartMeansNilRanFor() throws {
        // 〔實測〕命中率 84.1%，所以約六分之一的完成會走這條路。
        let disk = Disk(mtime: at(0), turnStart: nil)
        var t = tracker(disk)
        _ = t.update(input, now: at(0))
        _ = t.update(input, now: at(90))
        disk.mtime = at(100)
        _ = t.update(input, now: at(100))
        disk.readout = .finished(TurnEnd(finishedAt: at(800)))
        #expect(try #require(t.update(input, now: at(820)).finishes.first).ranFor == nil)
    }

    @Test("回合起點太舊就丟掉 —— 那是上一輪的，不是這一輪的")
    func staleTurnStartIsIgnored() throws {
        // 沒有這道容忍度，面板會定期顯示「跑了 19h 23m」
        // 〔實測，模擬〕寬鬆起點定義下 ranFor 的 max 是 69,812 秒。
        let disk = Disk(mtime: at(0))
        var t = tracker(disk)
        _ = t.update(input, now: at(0))
        _ = t.update(input, now: at(90))
        disk.mtime = at(100)
        disk.turnStart = at(20)                      // 比「又動起來」早 80 秒
        _ = t.update(input, now: at(100))
        disk.readout = .finished(TurnEnd(finishedAt: at(800)))
        #expect(try #require(t.update(input, now: at(820)).finishes.first).ranFor == nil)
    }

    @Test("完成時刻早於回合起點 —— ranFor 是 nil，不可以是負數")
    func negativeRanForIsNil() throws {
        // transcript 的 timestamp 不是單調的〔實測〕3.91% 的相鄰行對時間差為負。
        let disk = Disk(mtime: at(0))
        var t = tracker(disk)
        _ = t.update(input, now: at(0))
        _ = t.update(input, now: at(90))
        disk.mtime = at(100)
        disk.turnStart = at(98)
        _ = t.update(input, now: at(100))
        disk.readout = .finished(TurnEnd(finishedAt: at(95)))   // 比起點還早
        #expect(try #require(t.update(input, now: at(200)).finishes.first).ranFor == nil)
    }
}
