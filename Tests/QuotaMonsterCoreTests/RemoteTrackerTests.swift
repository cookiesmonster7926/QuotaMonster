import Testing
import Foundation
@testable import QuotaMonsterCore

/// 遠端機器那一區（面板的「遠端 REMOTE」）要畫什麼。
///
/// 兩層「不存在」（規矩 1、52）是這裡的主軸：
///   - 讀成功、某一列不見了 → 那個 session 結束了（正面證據），計數照新的算
///   - 讀失敗 → **不是**「那台沒有 session」，保留上一次的、照實說連不上
@Suite("遠端機器的追蹤")
struct RemoteTrackerTests {

    let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    let win = RemoteMachineInfo(id: "aaa111", label: "WIN-DESKTOP")
    let lab = RemoteMachineInfo(id: "bbb222", label: "LAB")

    func s(_ status: RemoteStatus, _ project: String = "p", _ title: String? = "t") -> RemoteSession {
        RemoteSession(title: title, project: project, status: status)
    }

    func cards(_ v: RemoteView) -> [RemoteCard] {
        if case .machines(let c) = v { return c }
        Issue.record("預期 .machines，拿到 \(v)")
        return []
    }

    // MARK: - 整區要不要出現

    @Test("還沒讀過機器清單：整區不畫")
    func hiddenBeforeFirstRead() {
        #expect(RemoteTracker().view(now: t0) == .hidden)
    }

    @Test("沒裝 herdr：整區不畫 —— 就算之前讀到過")
    func notInstalledHides() {
        var t = RemoteTracker()
        t.machinesRead(.success([win]), now: t0)
        t.machinesRead(.failure(.notInstalled), now: at(60))
        #expect(t.view(now: at(60)) == .hidden)
    }

    @Test("herdr server 沒在跑：一行說明，不是靜靜地不畫（使用者開了這個功能）")
    func serverNotRunningNotice() {
        var t = RemoteTracker()
        t.machinesRead(.failure(.serverNotRunning), now: t0)
        #expect(t.view(now: t0) == .notice("herdr 沒在跑 · 看不到遠端機器"))
    }

    @Test("herdr 沒有連任何遠端機器：一行說明")
    func noMachinesNotice() {
        var t = RemoteTracker()
        t.machinesRead(.success([]), now: t0)
        #expect(t.view(now: t0) == .notice("herdr 沒有連任何遠端機器"))
    }

    @Test("第一次讀機器清單就失敗：說原因")
    func machineListNeverRead() {
        var t = RemoteTracker()
        t.machinesRead(.failure(.timedOut), now: t0)
        #expect(t.view(now: t0) == .notice("讀不到 herdr 的機器清單 · 逾時"))
    }

    @Test("讀到過機器清單、之後讀失敗：機器照留（沒看到 ≠ 不存在）")
    func machineListFailureKeepsMachines() {
        var t = RemoteTracker()
        t.machinesRead(.success([win]), now: t0)
        t.agentsRead(machineId: win.id, .success([s(.idle)]), now: at(1))
        t.machinesRead(.failure(.herdrError(code: nil)), now: at(60))
        #expect(cards(t.view(now: at(61))).map(\.label) == ["WIN-DESKTOP"])
    }

    @Test("機器清單讀成功、某台不在了：那台忘掉（正面證據）")
    func machineRemoved() {
        var t = RemoteTracker()
        t.machinesRead(.success([win, lab]), now: t0)
        t.machinesRead(.success([lab]), now: at(60))
        #expect(cards(t.view(now: at(60))).map(\.id) == ["bbb222"])
        #expect(t.machineIds == ["bbb222"])
    }

    // MARK: - 一台機器的卡片

    @Test("剛加進來、還沒讀到：讀取中，沒有計數")
    func loading() {
        var t = RemoteTracker()
        t.machinesRead(.success([win]), now: t0)
        let c = cards(t.view(now: at(3)))[0]
        #expect(c.caption == "讀取中")
        #expect(c.counts == nil)
        #expect(c.warning == false)
    }

    @Test("15 秒還沒讀到（讀取還在途）：還沒讀到，警示")
    func neverReadAfterGrace() {
        var t = RemoteTracker()
        t.machinesRead(.success([win]), now: t0)
        let c = cards(t.view(now: at(15)))[0]
        #expect(c.caption == "還沒讀到")
        #expect(c.warning)
    }

    @Test("從沒讀到、而且讀失敗了：還沒讀到 · 原因")
    func neverReadWithFailure() {
        var t = RemoteTracker()
        t.machinesRead(.success([win]), now: t0)
        t.agentsRead(machineId: win.id, .failure(.timedOut), now: at(15))
        let c = cards(t.view(now: at(16)))[0]
        #expect(c.caption == "還沒讀到 · 逾時")
        #expect(c.counts == nil)
    }

    @Test("讀到了：N 個 · M 前看到；計數照固定順序、零的不畫；等你回覆的另外列出")
    func live() {
        var t = RemoteTracker()
        t.machinesRead(.success([win]), now: t0)
        t.agentsRead(machineId: win.id, .success([
            s(.idle), s(.working), s(.blocked, "paper", "校稿"), s(.idle), s(.done), s(.idle),
        ]), now: at(10))
        let c = cards(t.view(now: at(16)))[0]
        #expect(c.caption == "6 個 · 6 秒前看到")
        #expect(c.warning == false)
        #expect(c.counts?.map(\.text) == ["1 等你", "1 執行", "1 完成", "3 閒置"])
        #expect(c.counts?.map(\.status) == [.blocked, .working, .done, .idle])
        #expect(c.countsDimmed == false)
        #expect(c.waiting == [s(.blocked, "paper", "校稿")])
    }

    @Test("讀到了、但一個 Claude session 都沒有：說出來，不是空白")
    func liveButEmpty() {
        var t = RemoteTracker()
        t.machinesRead(.success([win]), now: t0)
        t.agentsRead(machineId: win.id, .success([]), now: t0)
        let c = cards(t.view(now: t0))[0]
        #expect(c.caption == "0 個 · 剛剛看到")
        #expect(c.counts == [])
        #expect(c.note == "herdr 分頁裡沒有 Claude session")
    }

    @Test("不認得的狀態歸「不明」，排最後")
    func unknownCountedLast() {
        var t = RemoteTracker()
        t.machinesRead(.success([win]), now: t0)
        t.agentsRead(machineId: win.id, .success([s(.unknown), s(.working)]), now: t0)
        #expect(cards(t.view(now: t0))[0].counts?.map(\.text) == ["1 執行", "1 不明"])
    }

    @Test("讀到過、這次讀失敗：連不上 · 上次讀到的時刻；計數照留但調暗；等你的那列不畫")
    func offline() {
        var t = RemoteTracker()
        t.machinesRead(.success([win]), now: t0)
        t.agentsRead(machineId: win.id, .success([s(.blocked), s(.idle)]), now: t0)
        t.agentsRead(machineId: win.id, .failure(.timedOut), now: at(200))
        let c = cards(t.view(now: at(240)))[0]
        #expect(c.caption == "連不上 · 4 分前最後看到")
        #expect(c.warning)
        #expect(c.counts?.map(\.text) == ["1 等你", "1 閒置"])
        #expect(c.countsDimmed)
        // 「等你」是幾分鐘前的事，現在可能已經不是了
        #expect(c.waiting.isEmpty)
    }

    @Test("連不上超過 30 分：只剩那一行，計數也不畫（太舊了）")
    func offlineCut() {
        var t = RemoteTracker()
        t.machinesRead(.success([win]), now: t0)
        t.agentsRead(machineId: win.id, .success([s(.idle)]), now: t0)
        t.agentsRead(machineId: win.id, .failure(.herdrError(code: nil)), now: at(60))
        #expect(cards(t.view(now: at(30 * 60 - 1)))[0].counts != nil)
        let c = cards(t.view(now: at(30 * 60)))[0]
        #expect(c.caption == "連不上 · 30 分前最後看到")
        #expect(c.counts == nil)
    }

    @Test("連不上之後又讀到：回到正常、不再調暗")
    func recovers() {
        var t = RemoteTracker()
        t.machinesRead(.success([win]), now: t0)
        t.agentsRead(machineId: win.id, .success([s(.idle)]), now: t0)
        t.agentsRead(machineId: win.id, .failure(.timedOut), now: at(30))
        t.agentsRead(machineId: win.id, .success([s(.working)]), now: at(60))
        let c = cards(t.view(now: at(60)))[0]
        #expect(c.caption == "1 個 · 剛剛看到")
        #expect(c.countsDimmed == false)
    }

    @Test("讀成功、上次那一列不見了：計數照新的（session 結束是正面證據）")
    func rowDisappearsOnSuccess() {
        var t = RemoteTracker()
        t.machinesRead(.success([win]), now: t0)
        t.agentsRead(machineId: win.id, .success([s(.blocked), s(.idle)]), now: t0)
        t.agentsRead(machineId: win.id, .success([s(.idle)]), now: at(10))
        let c = cards(t.view(now: at(10)))[0]
        #expect(c.counts?.map(\.text) == ["1 閒置"])
        #expect(c.waiting.isEmpty)
    }

    @Test("時間的措辭：秒、分、小時；時鐘往回跳不寫負數")
    func ageWords() {
        #expect(RemoteWords.ago(0) == "剛剛")
        #expect(RemoteWords.ago(4.9) == "剛剛")
        #expect(RemoteWords.ago(5) == "5 秒前")
        #expect(RemoteWords.ago(59) == "59 秒前")
        #expect(RemoteWords.ago(60) == "1 分前")
        #expect(RemoteWords.ago(3599) == "59 分前")
        #expect(RemoteWords.ago(3600) == "1 小時前")
        #expect(RemoteWords.ago(-30) == "剛剛")
    }

    @Test("等你那一列：標題＋專案；沒標題用專案；都沒有就說沒有名字")
    func waitingLabel() {
        #expect(RemoteWords.waitingLabel(s(.blocked, "paper", "校稿")) == ("校稿", "paper"))
        #expect(RemoteWords.waitingLabel(s(.blocked, "paper", nil)) == ("paper", nil))
        #expect(RemoteWords.waitingLabel(RemoteSession(title: nil, project: nil, status: .blocked))
                == ("（沒有名字）", nil))
    }

    @Test("失敗原因的措辭")
    func reasonWords() {
        #expect(RemoteWords.reason(.timedOut) == "逾時")
        #expect(RemoteWords.reason(.serverNotRunning) == "herdr 沒在跑")
        #expect(RemoteWords.reason(.unknownMachine) == "機器清單過期")
        #expect(RemoteWords.reason(.incompatible) == "herdr 的回應讀不懂")
        #expect(RemoteWords.reason(.notInstalled) == "找不到 herdr")
        #expect(RemoteWords.reason(.herdrError(code: "x")) == "連不上")
    }

    // MARK: - 什麼時候讀

    @Test("機器清單：第一次馬上讀；之後 60 秒一次")
    func machineListSchedule() {
        var t = RemoteTracker()
        #expect(t.machineListDue(now: t0))
        t.machineListStarted(now: t0)
        t.machinesRead(.success([win]), now: at(1))
        #expect(!t.machineListDue(now: at(59)))
        #expect(t.machineListDue(now: at(60)))
    }

    @Test("unknown machine：機器清單過期了 → 馬上重讀清單")
    func unknownMachineRefreshesList() {
        var t = RemoteTracker()
        t.machineListStarted(now: t0)
        t.machinesRead(.success([win]), now: t0)
        t.agentsRead(machineId: win.id, .failure(.unknownMachine), now: at(5))
        #expect(t.machineListDue(now: at(5)))
    }

    @Test("每台機器：第一次馬上讀；正常 10 秒一次；連續失敗退避（20、40、上限 60）")
    func agentSchedule() {
        var t = RemoteTracker()
        t.machinesRead(.success([win]), now: t0)
        #expect(t.dueMachines(now: t0) == [win.id])
        t.agentsStarted(machineId: win.id, now: t0)
        #expect(t.dueMachines(now: at(1)) == [])           // 還在讀：不重入
        t.agentsRead(machineId: win.id, .success([]), now: at(3))
        #expect(t.dueMachines(now: at(9.9)) == [])
        #expect(t.dueMachines(now: at(10)) == [win.id])     // 從開始讀起算，不是從讀完
        for (n, wait) in [(1, 20.0), (2, 40.0), (3, 60.0), (4, 60.0)] {
            let start = at(Double(n) * 1000)
            t.agentsStarted(machineId: win.id, now: start)
            t.agentsRead(machineId: win.id, .failure(.timedOut), now: start)
            #expect(t.dueMachines(now: start.addingTimeInterval(wait - 0.1)) == [], "第 \(n) 次失敗")
            #expect(t.dueMachines(now: start.addingTimeInterval(wait)) == [win.id], "第 \(n) 次失敗")
        }
        // 成功一次就回到 10 秒
        let ok = at(9000)
        t.agentsStarted(machineId: win.id, now: ok)
        t.agentsRead(machineId: win.id, .success([]), now: ok)
        #expect(t.dueMachines(now: ok.addingTimeInterval(10)) == [win.id])
    }

    @Test("機器清單讀到之前，沒有任何機器要讀")
    func noMachinesBeforeList() {
        #expect(RemoteTracker().dueMachines(now: t0) == [])
    }

    @Test("機器清單外的 id 送回來的結果不收（那台已經被移掉了）")
    func strayResultIgnored() {
        var t = RemoteTracker()
        t.machinesRead(.success([win]), now: t0)
        t.agentsRead(machineId: "zzz", .success([s(.working)]), now: t0)
        #expect(cards(t.view(now: t0)).map(\.id) == [win.id])
    }
}
