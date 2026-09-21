import Testing
import Foundation
@testable import QuotaMonsterCore

/// 交給 `/usr/bin/osascript` 的那個參數陣列。
///
/// 這是全 app 唯一一處把**外部來源的字串**交給另一個直譯器的地方。
/// 在這份測試存在之前，那條防線（`--`）**沒有任何東西守著** ——
/// `QuotaMonsterApp` 沒有測試 target，而參數是在那邊行內組出來的。
///
/// ⚠️ **結構斷言與行為斷言分工不同，兩種都要。**
/// 只斷言「陣列裡有 `--`」等於把實作抄一遍，它不驗證任何安全性質；
/// 只跑行為測試則守不住 Swift 那條路徑（有人重排參數時它不會紅）。
@Suite("OSAScriptCommand — 交給另一個直譯器之前")
struct OSAScriptCommandTests {

    let bodyMark = "BODYMARK"
    let subMark = "SUBMARK"

    // ── 清字串 ──────────────────────────────────────────────────

    @Test("NUL 一定要剝掉 —— 它會丟出 do/catch 接不到的 ObjC 例外，app 當場死")
    func cleanStripsNUL() {
        #expect(OSAScriptCommand.clean("a\0b\0c") == "abc")
    }

    @Test("超長要截斷，而且上限綁常數不寫字面量")
    func cleanTruncates() {
        // ⚠️ 寫 `== 200` 就是規矩 8 點名的說謊測試：上限改了它照樣過。
        let long = String(repeating: "字", count: 300)
        #expect(OSAScriptCommand.clean(long).count == OSAScriptCommand.maxFieldLength)
        #expect(OSAScriptCommand.clean("短的") == "短的")
    }

    // ── 參數陣列的結構 ──────────────────────────────────────────

    @Test("⚠️ `--` 一定排在每一個使用者字串之前")
    func guardComesBeforeEveryUserString() throws {
        // 這一則抓三種改壞法：(a) 把 `--` 刪掉 → #require 直接失敗；
        // (b) 把它挪到使用者字串後面；(c) 將來多一個使用者欄位卻插在它前面。
        //
        // ⚠️ 刻意**不寫**成 `args == [完整字面陣列]` —— 那種比對是把實作抄一遍，
        // 不驗證任何安全性質，而且任何無害的措辭調整都會讓它紅。
        let args = OSAScriptCommand.arguments(body: bodyMark, subtitle: subMark)
        let guardIndex = try #require(args.firstIndex(of: "--"))
        let bodyIndex = try #require(args.firstIndex(of: bodyMark))
        let subIndex = try #require(args.firstIndex(of: subMark))
        #expect(guardIndex < bodyIndex)
        #expect(guardIndex < subIndex)
        // `--` 之前不可以有任何一格是使用者輸入。
        for arg in args[..<guardIndex] {
            #expect(!arg.contains(bodyMark))
            #expect(!arg.contains(subMark))
        }
    }

    @Test("標題永遠是常數 —— 不管使用者字串長什麼樣")
    func titleStaysConstantWhateverTheInput() throws {
        // 這一則不是抄實作，它斷言的是一個**關係**：輸入怎麼變，item 2 都不變。
        //
        // ⚠️〔實測〕常數標題是**承載安全性**的，不只是署名問題：
        // osascript 走 BSD getopt（遇第一個非選項就停掃），而這個常數正好是
        // 那個非選項 —— 它把 item 3 擋在掃描範圍外。把 item 2 換成 `-i`，
        // item 3 的 property 就會 fired。
        let hostile = ["-eproperty p:(do shell script \"true\")", "", String(repeating: "x", count: 500)]
        for b in hostile {
            for s in hostile {
                let args = OSAScriptCommand.arguments(body: b, subtitle: s)
                let guardIndex = try #require(args.firstIndex(of: "--"))
                #expect(args[guardIndex + 2] == OSAScriptCommand.title)
            }
        }
    }

    @Test("兩個使用者欄位都要過 clean —— 只清一邊等於沒清")
    func bothUserFieldsAreCleaned() throws {
        let args = OSAScriptCommand.arguments(
            body: "a\0b", subtitle: String(repeating: "y", count: 300))
        let guardIndex = try #require(args.firstIndex(of: "--"))
        #expect(!args[guardIndex + 1].unicodeScalars.contains { $0.value == 0 })
        #expect(args[guardIndex + 3].count == OSAScriptCommand.maxFieldLength)
    }

    @Test("腳本用 `item N of argv` 取值，不是字串內插")
    func scriptReadsArgvInsteadOfInterpolating() {
        // 這一則守的是「內容不可逃逸」那半條保證，而 `--` 對它完全無效：
        // 〔實測〕`x" & (do shell script "…") & "y` 在有無 `--` 兩種情況下都是死的，
        // 因為三個欄位是取值不是內插。改成內插會讓它活過來。
        let args = OSAScriptCommand.arguments(body: bodyMark, subtitle: subMark)
        let script = args.joined(separator: " ")
        let guardIndex = args.firstIndex(of: "--") ?? args.count
        let scriptPart = args[..<guardIndex].joined(separator: " ")
        #expect(scriptPart.contains("item 1 of argv"))
        #expect(!scriptPart.contains(bodyMark))
        #expect(script.contains(bodyMark))   // 它只能以獨立的 argv 元素出現
    }

    // ── 行為：真的跑一次 ────────────────────────────────────────

    #if os(macOS)

    static let osascript = "/usr/bin/osascript"

    /// 兩則行為測試**共用同一個 payload**。
    ///
    /// ⚠️ 各寫一份的話，兩者會漂移，而漂移的後果是負向那一則**悄悄變成
    /// 永遠會過的空測試** —— 它的控制組已經不再證明同一件事了。
    static func payload(touching sentinel: URL) -> String {
        // ⚠️ 用**絕對路徑**，不用「無斜線的目錄名」形式 ——
        // 後者依賴 cwd，而測試不能安全地 chdir。
        "-eproperty p:(do shell script \"touch '\(sentinel.path)'\")"
    }

    /// 跑一次 osascript，有上限地等它結束。
    ///
    /// ⚠️ **三個 fd 都要導掉。**〔實測〕探測時有一個案例（`-i` 互動模式）
    /// 因為 stdin 沒導而真的掛滿 30 秒。
    /// ⚠️ **絕不斷言離開碼**（見下面兩則測試的註解）。
    static func run(_ arguments: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: osascript)
        p.arguments = arguments
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return }
        let deadline = Date().addingTimeInterval(10)
        while p.isRunning && Date() < deadline { usleep(20_000) }
        if p.isRunning { p.terminate() }
    }

    static var available: Bool {
        FileManager.default.isExecutableFile(atPath: osascript)
    }

    /// 建一個暫存目錄與 sentinel 路徑，用完刪掉。
    func withSentinel(_ work: (URL) -> Void) throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("qm-osa-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        work(dir.appendingPathComponent("sentinel"))
    }

    @Test("⚠️ 真的餵那個 payload —— 檔案不可以被建出來")
    func realPayloadThroughBodyDoesNotExecute() throws {
        // 這一則是規矩 3 要求的那一則：**餵真 payload、斷言副作用沒發生**。
        // 只試引號逸出的測試在有漏洞的版本上也會過。
        //
        // ⚠️ 一定要走 **body（item 1）**。〔實測〕從 subtitle 注入的話，
        // 在有漏洞的版本上 sentinel 也不會被建出來（常數標題擋住了 getopt 掃描）
        // —— 那樣這一則就會變成一則永遠會過的空測試。
        //
        // ⚠️ **只斷言 sentinel，不斷言離開碼。** 〔實測〕注入成功時 osascript
        // 反而回 1（argv 被吃掉一格，之後報 `Can't get item 3 of …`）——
        // 一次成功的 RCE 藏在一則錯誤訊息底下。
        guard Self.available else { return }
        try withSentinel { sentinel in
            Self.run(OSAScriptCommand.arguments(
                body: Self.payload(touching: sentinel), subtitle: "proj"))
            #expect(!FileManager.default.fileExists(atPath: sentinel.path),
                    "payload 被執行了 —— `--` 那道防線破了")
        }
    }

    @Test("控制組：同一個 payload 拿掉 `--` 就真的會執行")
    func theSamePayloadExecutesWithoutTheGuard() throws {
        // **這一則的用途不是抓 bug，是證明上面那一則有牙齒。**
        // 沒有它，上面那一則可能因為 payload 失效（OS 更新、`do shell script`
        // 被封）而變成永遠會過，而且沒有人會發現。
        //
        // ⚠️ argv **從 `arguments()` 衍生再濾掉 `--`**，不是自己重拼一份 ——
        // 重拼的話，`arguments()` 一改形狀，這個控制組就不再對照同一件事。
        guard Self.available else { return }
        try withSentinel { sentinel in
            let unguarded = OSAScriptCommand.arguments(
                body: Self.payload(touching: sentinel), subtitle: "proj")
                .filter { $0 != "--" }
            Self.run(unguarded)
            #expect(FileManager.default.fileExists(atPath: sentinel.path),
                    "payload 沒有執行 —— 上面那一則就不再證明任何事了。要重新找一個有效的 payload，不是把這一則刪掉")
        }
    }

    #endif
}
