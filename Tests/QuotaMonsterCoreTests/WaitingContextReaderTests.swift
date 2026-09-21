import Testing
import Foundation
@testable import QuotaMonsterCore

/// 浮窗上最大的那一行要說出「那個 session 到底在問什麼」。
///
/// session 註冊表只有兩種分類（`input needed` / `permission prompt`），沒有內文；
/// 內文在 transcript 尾端最後一則 assistant 訊息的 `tool_use` 裡。
///
/// ⚠️ **絕不在 UI 路徑上整檔解析。** 活躍 transcript 實測 480KB–878KB，
/// 每 20 秒每 agent 成長 5–35KB。這個型別只在**要浮窗的那一刻**被呼叫一次，
/// 而且只從檔尾往回讀固定 byte 數。
@Suite("WaitingContextReader")
struct WaitingContextReaderTests {

    func temp() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-wait-\(UUID().uuidString).jsonl")
    }

    func write(_ lines: [String]) -> URL {
        let url = temp()
        try? lines.joined(separator: "\n").data(using: .utf8)!.write(to: url)
        return url
    }

    func assistant(_ toolName: String, _ input: String) -> String {
        """
        {"type":"assistant","message":{"role":"assistant","content":[\
        {"type":"tool_use","id":"toolu_1","name":"\(toolName)","input":\(input)}]}}
        """
    }

    func userText(_ t: String) -> String {
        """
        {"type":"user","message":{"role":"user","content":[{"type":"text","text":"\(t)"}]}}
        """
    }

    // ── 抓得到的情況 ───────────────────────────────────────────

    @Test("AskUserQuestion —— 問題本文就是那一行英雄字")
    func readsTheQuestionItself() throws {
        let url = write([
            userText("繼續"),
            assistant("AskUserQuestion",
                      #"{"questions":[{"question":"要我繼續嗎？","header":"方向"}]}"#),
        ])
        let ctx = try #require(WaitingContextReader().read(url))
        #expect(ctx.headline == "要我繼續嗎？")
        #expect(ctx.toolName == "AskUserQuestion")
    }

    @Test("等你批准工具 —— 用 description，因為 command 可能是三行 shell")
    func prefersDescriptionOverRawCommand() throws {
        let url = write([
            assistant("Bash",
                      #"{"command":"swift build 2>&1 | tail -20","description":"建置專案"}"#),
        ])
        let ctx = try #require(WaitingContextReader().read(url))
        #expect(ctx.headline == "建置專案")
        #expect(ctx.toolName == "Bash")
        #expect(ctx.detail == "swift build 2>&1 | tail -20")
    }

    @Test("沒有 description 的工具退回工具名 + 第一個像樣的欄位")
    func fallsBackWhenThereIsNoDescription() throws {
        let url = write([
            assistant("Write", #"{"file_path":"/a/b/c.swift","content":"x"}"#),
        ])
        let ctx = try #require(WaitingContextReader().read(url))
        #expect(ctx.toolName == "Write")
        #expect(ctx.detail == "/a/b/c.swift")
    }

    @Test("只看最後一則 assistant 的 tool_use —— 前面那些已經批准過了")
    func onlyTheLastPendingToolUseCounts() throws {
        let url = write([
            assistant("Bash", #"{"command":"ls","description":"舊的"}"#),
            userText("好"),
            assistant("Bash", #"{"command":"rm -rf .build","description":"清掉建置快取"}"#),
        ])
        let ctx = try #require(WaitingContextReader().read(url))
        #expect(ctx.headline == "清掉建置快取")
    }

    // ── 抓不到的情況：一律回 nil，不回空字串 ────────────────────

    @Test("檔案不存在回 nil —— 呼叫端退回分類文字，不是留白")
    func missingFileIsNil() {
        #expect(WaitingContextReader().read(temp()) == nil)
    }

    @Test("零位元組檔回 nil")
    func emptyFileIsNil() {
        let url = temp()
        try? Data().write(to: url)
        #expect(WaitingContextReader().read(url) == nil)
    }

    @Test("尾端被截斷的半行不可以讓整個讀取失敗 —— 往前找上一則完整的")
    func truncatedTailFallsBackToThePreviousLine() throws {
        let url = temp()
        let good = assistant("Bash", #"{"command":"ls","description":"列出檔案"}"#)
        let broken = #"{"type":"assistant","message":{"role":"assist"#
        try? (good + "\n" + broken).data(using: .utf8)!.write(to: url)
        let ctx = try #require(WaitingContextReader().read(url))
        #expect(ctx.headline == "列出檔案")
    }

    @Test("最後一則不是 tool_use 就回 nil —— 沒有待批准的東西")
    func noPendingToolUseIsNil() {
        let url = write([
            assistant("Bash", #"{"command":"ls","description":"舊的"}"#),
            """
            {"type":"assistant","message":{"role":"assistant","content":[\
            {"type":"text","text":"做完了"}]}}
            """,
        ])
        #expect(WaitingContextReader().read(url) == nil)
    }

    // ── 不可以把 app 搞壞 ───────────────────────────────────────

    @Test("超長內容會被截斷 —— 浮窗只有一行，而 content 可以是整個檔案")
    func absurdlyLongContentIsTruncated() throws {
        let huge = String(repeating: "很長", count: 5000)
        let url = write([assistant("Bash", #"{"command":"x","description":"\#(huge)"}"#)])
        let ctx = try #require(WaitingContextReader().read(url))
        #expect(ctx.headline.count <= WaitingContextReader.maxHeadlineLength)
    }

    @Test("大檔只讀檔尾，不整檔載入")
    func onlyReadsTheTail() throws {
        // 前面塞 2MB 垃圾，真正的內容在最後一行。讀得到就代表是從尾端讀的；
        // 讀不到就代表尾端視窗太小。兩件事一個測試釘住。
        let url = temp()
        let filler = (0..<4000).map { i in
            #"{"type":"user","message":{"role":"user","content":[{"type":"text","text":"\#(String(repeating: "x", count: 500))-\#(i)"}]}}"#
        }.joined(separator: "\n")
        let last = assistant("Bash", #"{"command":"ls","description":"最後一則"}"#)
        try (filler + "\n" + last).data(using: .utf8)!.write(to: url)
        #expect(try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int ?? 0 > 2_000_000)

        let ctx = try #require(WaitingContextReader().read(url))
        #expect(ctx.headline == "最後一則")
    }

    @Test("NUL byte 不會炸掉解析，也不會流進 headline")
    func nulBytesAreStripped() throws {
        // NUL 進 Process.arguments 會丟出 Swift 接不到的 ObjC 例外，整個 app 當場死。
        // osascript 通道就在下游，所以這裡就要擋掉。
        // 真實路徑上 NUL 是以 \u0000 逸出序列進來的（JSON 裡的裸 NUL 是非法的，
        // 解析器會直接拒絕整行）。JSONSerialization 會老老實實把它解成一個 NUL
        // scalar 交給我們，然後它就一路流向 Process.arguments。
        let url = write([assistant("Bash",
                                   #"{"command":"ls","description":"a\u0000b"}"#)])
        let ctx = try #require(WaitingContextReader().read(url))
        #expect(!ctx.headline.unicodeScalars.contains { $0.value == 0 })
    }
}
