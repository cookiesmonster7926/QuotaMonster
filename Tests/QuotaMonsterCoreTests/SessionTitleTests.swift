import Testing
import Foundation
@testable import QuotaMonsterCore

/// 面板那一列要顯示的 session 名字。
///
/// ### 為什麼需要它
/// 〔實測 2026-09-22〕`~/.claude/sessions/<pid>.json` 的 `name` 有兩種來源，
/// 而它自己用 `nameSource` 標出來：
///
/// | session | registry name | nameSource | transcript 的 aiTitle |
/// |---|---|---|---|
/// | a28a5af5 | `usage-ff` | derived | `修t2` |
/// | eb209917 | `rl-b5` | derived | `Q-learning 環境 setup` |
/// | d8258fe6 | `Q-learning 環境 setup` | **auto** | 同左 |
/// | 2d765b86（VS Code 外掛）| `rl-1b` | derived | `0922作業` |
///
/// `derived` 是 Claude Code 從 cwd 湊出來的佔位名（`rl-1b`、`usage-ff`），
/// 使用者從來沒有看過它 —— 他在 VS Code 分頁上看到的是 `0922作業`。
/// 那個字串只存在 transcript 裡，型別是 `{"type":"ai-title","aiTitle":"…"}`。
///
/// ### ⚠️ 只在 derived 時才去看 transcript
/// `auto`（與未來任何使用者自訂的來源）代表註冊表那個名字**是有來歷的**，
/// 蓋掉它就是把已知的事實換成猜測。實測 `d8258fe6` 兩邊本來就一致 ——
/// 這條閘不是為了那個情況，是為了**不要在不知道的時候動手**。
@Suite("Session 顯示名")
struct SessionTitleTests {

    func line(_ title: String) -> String {
        #"{"type":"ai-title","aiTitle":"\#(title)","sessionId":"x"}"#
    }

    // ── 什麼時候才去讀 transcript ──────────────────────────────

    @Test("derived 的名字讓給 transcript 的標題")
    func derivedYieldsToTranscript() {
        #expect(SessionTitle.display(name: "rl-1b", nameSource: "derived",
                                     transcriptTitle: { "0922作業" }) == "0922作業")
    }

    @Test("auto 的名字不可以被蓋掉 —— 而且根本不該去讀 transcript")
    func autoIsNeverOverridden() {
        var reads = 0
        let out = SessionTitle.display(name: "Q-learning 環境 setup", nameSource: "auto",
                                       transcriptTitle: { reads += 1; return "別的東西" })
        #expect(out == "Q-learning 環境 setup")
        #expect(reads == 0, "讀 transcript 是 I/O，不該在用不到的時候發生")
    }

    @Test("nameSource 是 nil（未知）時也不動 —— 不知道就不要動手")
    func unknownSourceIsLeftAlone() {
        var reads = 0
        let out = SessionTitle.display(name: "something", nameSource: nil,
                                       transcriptTitle: { reads += 1; return "x" })
        #expect(out == "something")
        #expect(reads == 0)
    }

    @Test("derived 但 transcript 撈不到 → 維持原本那個佔位名，不是變成 nil")
    func fallsBackToDerivedWhenTranscriptSaysNothing() {
        #expect(SessionTitle.display(name: "rl-1b", nameSource: "derived",
                                     transcriptTitle: { nil }) == "rl-1b")
    }

    @Test("兩邊都沒有就回 nil —— 由呼叫端決定要顯示什麼")
    func nothingAtAll() {
        #expect(SessionTitle.display(name: nil, nameSource: "derived",
                                     transcriptTitle: { nil }) == nil)
    }

    // ── 從 transcript 尾端撈 ──────────────────────────────────

    @Test("取**最後**一個 ai-title —— 標題會被改，最新的才算")
    func takesTheLastTitle() {
        let tail = [line("舊標題"), line("中間"), line("最新標題")].joined(separator: "\n")
        #expect(SessionTitle.aiTitle(inTail: tail) == "最新標題")
    }

    @Test("第一行可能被切一半（尾端讀取的常態），不可以因此整個失敗")
    func survivesATruncatedFirstLine() {
        let tail = #"le":"被切掉的半行"}"# + "\n" + line("好的標題")
        #expect(SessionTitle.aiTitle(inTail: tail) == "好的標題")
    }

    @Test("只認 type == ai-title —— 別的型別就算帶著 aiTitle 這個 key 也不算")
    func onlyTrustsTheAiTitleRecord() {
        // ⚠️ 這一則原本餵的誘餌是 `{"type":"user","content":"…aiTitle…"}` ——
        // 那個字串只出現在**值**裡面，所以就算把型別檢查整個拿掉，
        // `obj["aiTitle"] as? String` 本來就是 nil，測試照樣過。**它是空的。**
        // 〔實測〕突變驗證抓到：刪掉那一行 guard，紅掉 0 則。
        // 誘餌必須真的帶那個 **key**，才釘得住「型別要對」這件事。
        let decoy = #"{"type":"user","aiTitle":"不該被採用"}"#
        #expect(SessionTitle.aiTitle(inTail: decoy) == nil)

        // 而且同一段尾端裡，錯型別的那一筆不可以蓋掉對的那一筆
        let mixed = [line("對的標題"), decoy].joined(separator: "\n")
        #expect(SessionTitle.aiTitle(inTail: mixed) == "對的標題")
    }

    @Test("JSON 的跳脫要真的解開，不是拿正則硬切")
    func decodesJSONEscapes() {
        let tail = #"{"type":"ai-title","aiTitle":"a\"b\\c\u000a d"}"#
        let t = SessionTitle.aiTitle(inTail: tail)
        #expect(t?.contains("\"") == true)
        #expect(t?.contains("\n") == false, "換行要被抹掉 —— 面板那一列只有一行")
    }

    @Test("空白標題當成沒有")
    func blankIsNothing() {
        #expect(SessionTitle.aiTitle(inTail: line("   ")) == nil)
        #expect(SessionTitle.aiTitle(inTail: line("")) == nil)
    }

    @Test("過長的標題要截斷 —— 面板那一列塞不下一整段話")
    func longTitleIsTruncated() {
        let long = String(repeating: "很長", count: 200)
        let t = SessionTitle.aiTitle(inTail: line(long))
        #expect((t?.count ?? 0) <= SessionTitle.maxLength)
    }

    @Test("完全不是 JSON 的垃圾不可以讓它炸掉")
    func garbageIsSurvivable() {
        #expect(SessionTitle.aiTitle(inTail: "not json at all\n\u{0}\n{{{") == nil)
        #expect(SessionTitle.aiTitle(inTail: "") == nil)
    }
}
