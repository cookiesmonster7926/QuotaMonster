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
        var tailReads = 0
        init(mtime: Date?, readout: TurnReadout = .unfinished) {
            self.mtime = mtime; self.readout = readout
        }
    }

    func tracker(_ disk: Disk) -> CompletionTracker {
        CompletionTracker(
            readTail: { _ in disk.tailReads += 1; return disk.readout },
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

    // ── 跑了多久（第三節第 33 條）───────────────────────────────
    //
    // 起點不再是「安靜 → 又動起來那一刻往 64KB 尾端搆」，而是往前掃的游標
    // 一路記下的最後一則真人訊息（`TurnOpener`），由呼叫端在 `CompletionInput` 帶進來。

    func input(_ opening: TurnOpener.Answer?) -> CompletionInput {
        CompletionInput(transcripts: ["S1": url], openings: opening.map { ["S1": $0] } ?? [:])
    }

    @Test("使用者在上一輪講完 90 秒內就回話 —— 這一輪的 ranFor 照樣算得出來")
    func quickReplyStillHasRanFor() throws {
        // ⚠️ 這就是 7/7 算不出來的那個洞：舊作法只在「確認安靜滿 90 秒、又動起來」
        // 那一刻讀起點。回得快的人永遠湊不到那個條件。
        let disk = Disk(mtime: at(0))
        var t = tracker(disk)
        _ = t.update(input(.human(at(0))), now: at(0))
        disk.mtime = at(30)                          // 沒有安靜滿 90 秒就又動了
        _ = t.update(input(.human(at(30))), now: at(30))
        disk.readout = .finished(TurnEnd(finishedAt: at(800)))
        disk.mtime = at(800)
        _ = t.update(input(.human(at(30))), now: at(800))
        let out = t.update(input(.human(at(30))), now: at(890))
        #expect(try #require(out.finishes.first).ranFor == 770)
    }

    @Test("很長的回合也算得出來 —— 起點在幾小時前不是「太舊」，那就是這一輪")
    func longTurnKeepsItsStart() throws {
        // 舊的 15 秒容忍度是為了擋「寬鬆的起點定義」（〔實測，模擬〕max 69,812 秒）。
        // 起點改成「最後一則真人訊息，中間沒有被別的東西叫醒過」之後，
        // 三小時的起點就是三小時前，不需要再丟掉。
        let disk = Disk(mtime: at(0))
        var t = tracker(disk)
        _ = t.update(input(.human(at(-10_800))), now: at(0))
        disk.readout = .finished(TurnEnd(finishedAt: at(5)))
        let out = t.update(input(.human(at(-10_800))), now: at(90))
        #expect(try #require(out.finishes.first).ranFor == 10_805)
    }

    @Test("整個沒看到起點（watcher 沒讀到這份）—— ranFor 是 nil，不是 0")
    func unseenOpeningMeansNilRanFor() throws {
        let disk = Disk(mtime: at(0))
        var t = tracker(disk)
        _ = t.update(input(nil), now: at(0))
        disk.readout = .finished(TurnEnd(finishedAt: at(5)))
        #expect(try #require(t.update(input(nil), now: at(90)).finishes.first).ranFor == nil)
    }

    @Test("看到了、但這一輪不是真人開的 —— ranFor 是 nil")
    func wokenTurnHasNoRanFor() throws {
        let disk = Disk(mtime: at(0))
        var t = tracker(disk)
        _ = t.update(input(.wokenWithoutHuman), now: at(0))
        disk.readout = .finished(TurnEnd(finishedAt: at(5)))
        let out = t.update(input(.wokenWithoutHuman), now: at(90))
        #expect(try #require(out.finishes.first).ranFor == nil)
    }

    @Test("真人訊息沒帶時刻、或一則都沒有 —— ranFor 是 nil")
    func noUsableStartMeansNil() throws {
        for opening: TurnOpener.Answer in [.humanWithoutTimestamp, .noHumanYet] {
            let disk = Disk(mtime: at(0))
            var t = tracker(disk)
            _ = t.update(input(opening), now: at(0))
            disk.readout = .finished(TurnEnd(finishedAt: at(5)))
            #expect(try #require(t.update(input(opening), now: at(90)).finishes.first).ranFor == nil)
        }
    }

    @Test("完成時刻早於回合起點 —— ranFor 是 nil，不可以是負數")
    func negativeRanForIsNil() throws {
        // transcript 的 timestamp 不是單調的〔實測〕3.91% 的相鄰行對時間差為負。
        let disk = Disk(mtime: at(0))
        var t = tracker(disk)
        _ = t.update(input(.human(at(98))), now: at(0))
        disk.readout = .finished(TurnEnd(finishedAt: at(95)))   // 比起點還早
        #expect(try #require(t.update(input(.human(at(98))), now: at(100)).finishes.first).ranFor == nil)
    }
}
