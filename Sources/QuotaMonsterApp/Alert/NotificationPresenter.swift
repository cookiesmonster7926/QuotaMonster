import AppKit
import QuotaMonsterCore

/// 決定一則事件走哪條通道，以及窗口上現在該站著誰。
///
/// **這一層不可以有任何決策。** 「該不該發」全部在 `NotificationEngine` 裡，
/// 那邊有 62 個測試；這裡只有路由與畫面狀態，因為它碰 AppKit，測不到。
/// 一旦這裡開始出現 if 判斷「這則要不要發」，那個判斷就永遠不會有測試。
@MainActor
final class NotificationPresenter: NotificationPresenting {

    private let panel: AlertPanelController
    private let reader = WaitingContextReader()
    private let resolver = SessionDirectoryResolver()
    private let home = FileManager.default.homeDirectoryForCurrentUser
    /// - Returns: 圖示真的閃了嗎。見 `StatusItemController.pulse()`。
    private var transientSignal: (() -> Bool)?

    /// 現在窗口上正在講的那些 session。
    ///
    /// **為什麼 presenter 要自己記：** 引擎照設計「兩個不合併」，所以兩個同時卡住時
    /// 它會送出**兩則**事件。但螢幕上只有一扇窗 —— 各自 `show()` 的話第二則會把
    /// 第一則蓋掉，於是等最久的那個永遠看不到。窗口的內容因此由這裡累積，
    /// 引擎不必知道螢幕上有幾扇窗。
    private var showing: [WaitingSession] = []
    private var context: WaitingContext?

    /// 人不在螢幕前時發生的警示，等他回來再補上。
    ///
    /// **為什麼不是「不在就算了」：** 實機驗證抓到的就是這一格 ——
    /// 事件發了、音效響了、osascript 也送出去了，但使用者離開鍵盤超過五分鐘，
    /// 於是浮窗要嘛對著一張空椅子開十秒然後自己消失，要嘛乾脆不開。
    /// 兩種情況他回來時都拿不到那顆「跳過去」，只剩一個琥珀色圖示和一則
    /// 署名「指令碼編輯器」的通知。
    ///
    /// 留著它，人一碰鍵盤（`hidIdleTime` 掉回門檻以下）就補上。
    private var deferred: WaitingAlert?

    init(anchor: @escaping () -> NSRect?) {
        panel = AlertPanelController(anchor: anchor) { session in
            SessionActivator.activate(pid: session.pid)
        }
    }

    /// 選單列圖示的瞬時訊號（T2／T3 用）。由 `StatusItemController` 注入。
    func onTransientSignal(_ fire: @escaping () -> Bool) { transientSignal = fire }

    func present(_ event: NotificationEvent) {
        switch event {
        case .waiting(let alert):
            presentWaiting(alert)

        case .batchDrained(let batch):
            let flashed = transientSignal?() ?? false
            // **出不出聲是 Core 決定的**，理由連同事件一起送過來（`Audibility`）。
            // 這裡曾經有一個 `if batch.outcome == .completed` —— 那是一個決策，
            // 而它長在一個沒有測試的檔案裡。現在它和在場判斷、預算一起
            // 搬進 `NotificationEngine`，那邊釘得住。
            if batch.audibility == .audible {
                AlertSound.play()
            } else if !flashed {
                // ⚠️ 這一則**什麼痕跡都沒留下**：沒出聲（失敗的那批刻意不出聲，
                // 或被在場閘／預算擋掉），而圖示那一下也被吞掉了
                // （減少動態／低耗電／警示中讓路／還在播）。
                //
                // 留一行 log 是這裡唯一做得到的事，而它正是這個 repo 的教訓：
                // 通知沒出現的時候畫面上什麼線索都沒有，三種不同的原因長得一模一樣。
                NSLog("QuotaMonster: T2 %@（%@）完全沒有留下痕跡 —— "
                        + "沒出聲，而且選單列的瞬時訊號被吞掉了",
                      batch.workflowId, String(describing: batch.audibility))
            }

        case .quotaTier:
            transientSignal?()   // 只給圖示，不出聲、不浮窗
        }
    }

    /// 這些 session 還在等。不在裡面的代表已經解除。
    ///
    /// **逐一移除，不是全部解除才收。** 合併的窗口上站著四個，你回答了其中一個，
    /// 那一列就該消失 —— 留著它，窗口會對著一個已經回答過的問題繼續往上數秒數，
    /// 而那正是這個 app 最快被刪掉的方式。
    func resolve(stillWaiting: Set<String>) {
        // 先處理延後的那一扇。這一段必須在下面的 early return **之前** ——
        // 人不在螢幕前時 `showing` 是空的，擋在 guard 後面就永遠補不上。
        if let pending = deferred {
            if let alive = pending.retaining(stillWaiting) {
                if ScreenPresence.canSeeAPanel {
                    deferred = nil
                    presentWaiting(alive)
                }
            } else {
                // 全部都回答完了 —— 不要補一扇空窗。
                deferred = nil
            }
        }

        guard !showing.isEmpty else { return }
        let remaining = showing.filter { stillWaiting.contains($0.sessionId) }
        guard remaining.count != showing.count else { return }   // 沒有人解除

        let wasShowing = panel.isShowing
        showing = remaining
        guard let primary = remaining.first else {
            context = nil
            panel.dismissImmediately()
            return
        }
        // ⚠️ 窗口已經自己收起來了就**只更新狀態，不要重新叫出來**。
        // 它超時收掉代表使用者放它過去了；因為別的 session 解除就把它叫回來，
        // 等於用一件好消息去打斷人。
        guard wasShowing else { return }

        // 主角換人了，問題也要跟著換。
        context = transcript(for: primary).flatMap { reader.read($0) }
        panel.show(content(primary: primary, others: Array(remaining.dropFirst())))
    }

    // ── T1 ────────────────────────────────────────────────────

    private func presentWaiting(_ alert: WaitingAlert) {
        var sessions = alert.sessions
        let previousPrimary = showing.first?.sessionId

        // 窗口還開著就併進去，不要蓋掉它。合併後仍然是等最久的當主角。
        if panel.isShowing {
            let existing = showing.filter { s in !sessions.contains { $0.sessionId == s.sessionId } }
            sessions = (sessions + existing).sorted { $0.since < $1.since }
        }
        guard let primary = sessions.first else { return }
        showing = sessions

        // 「到底在問什麼」在這裡才讀 —— 一次等待事件讀一次尾端，不是每三秒。
        // 主角沒換就不必重讀。
        if context == nil || previousPrimary != primary.sessionId {
            context = transcript(for: primary).flatMap { reader.read($0) }
        }

        // 看得到才開窗。螢幕鎖著、睡著、或人離開超過五分鐘的時候開一扇
        // 十秒後自己關掉的窗，只是在沒有人看的地方點一盞燈 ——
        // 而那十秒裡那個 1Hz 的計時器是真的在跑。
        //
        // **但不是就這樣算了。** 警示留著（`deferred`），人一回來就補上；
        // 事件同時靠下面的 osascript 留下痕跡。
        let visible = ScreenPresence.canSeeAPanel
        if visible {
            panel.show(content(primary: primary, others: Array(sessions.dropFirst())))
            // 重推那一次不再出聲 —— 第二次還發同樣的聲音只會教會耳朵忽略它。
            if !alert.isRepeat { AlertSound.play() }
        } else {
            // 已經有一扇在等著補的話就併進去，不要蓋掉先來的那些。
            let merged = (deferred.map { $0.sessions } ?? []) + sessions
            var seen = Set<String>()
            let unique = merged.filter { seen.insert($0.sessionId).inserted }
                               .sorted { $0.since < $1.since }
            deferred = WaitingAlert(
                primary: unique[0], others: Array(unique.dropFirst()),
                coalesced: unique.count >= NotificationEngine.coalesceThreshold,
                isRepeat: false)
            showing = []
        }

        // osascript 副本：**只在看不到浮窗時才發**（使用者 2026-09-18 選的）。
        // 看得到的時候不重複打擾；真的離開螢幕時，事件仍然留得下痕跡 ——
        // 通知中心歷史與鎖定畫面是 NSPanel 做不到的兩件事。
        guard !visible else { return }
        // ⚠️ `?? fallback` 擋不住**空字串**。通知中心那一則是唯一補不回來的通道，
        // 一則空白的橫幅比不發更糟 —— 你會知道錯過了什麼，卻永遠不知道是什麼。
        let headline = context?.headline ?? ""
        let body = headline.isEmpty ? AlertView.waitingLabel(primary.waitingFor) : headline
        let subtitle = sessions.count > 1
            ? "\(sessions.count) 個 session 在等你 · \(primary.project)"
            : primary.project
        OSAScriptNotifier.post(body: body, subtitle: subtitle)
    }

    private func content(primary: WaitingSession, others: [WaitingSession]) -> AlertContent {
        AlertContent(primary: primary, others: others,
                     coalesced: others.count + 1 >= NotificationEngine.coalesceThreshold,
                     context: context, now: Date())
    }

    /// session 的 transcript 路徑。
    ///
    /// ⚠️ **不要自己從 cwd 拼 slug。** 同一個 sessionId 可能出現在兩個 project slug
    /// 底下（實測 11 個中有 1 個），正確的那個是**同層有 `<sessionId>.jsonl`
    /// 兄弟檔**的那個 —— 自己拼會安靜地挑到殘影，然後浮窗上出現一個屬於
    /// 別次執行的問題。
    ///
    /// ⚠️ **用 `transcript(sessionId:)`，不是 `locate()`。** 這裡原本呼叫 `locate()`，
    /// 而它**額外**要求 `<sessionId>/` 目錄存在 —— 〔實測 2026-09-19〕40 個
    /// transcript 只有 15 個有那個目錄（沒開過 subagent 的 session 就沒有）。
    /// 於是那些 session 的浮窗永遠拿不到「它到底在問什麼」那一行，
    /// 安靜地退回分類文字（「正在等待輸入」），而使用者不會知道少了什麼。
    /// 上面那段註解講的判別依據本來就是「**兄弟檔**存在」，不是目錄存在。
    private func transcript(for s: WaitingSession) -> URL? {
        resolver.transcript(sessionId: s.sessionId,
                            projectsRoot: home.appendingPathComponent(".claude/projects"))
    }
}
