import Foundation

/// 組出要交給 `/usr/bin/osascript` 的那個參數陣列。
///
/// **為什麼這件事在 Core：** 這是全 app 唯一一處把**外部來源的字串**交給另一個
/// 直譯器的地方，而 `QuotaMonsterApp` 沒有測試 target。組裝留在 App 層，
/// 等於讓唯一一條安全關鍵的程式碼永遠沒有測試守著。
///
/// 搬進來之後還多買到一件事：**「安全的 argv」成為唯一好用的那條路。**
/// 〔grep 全 `Sources/` 確認〕`OSAScriptNotifier` 是今天唯一的 osascript 啟動點，
/// 而下一個呼叫點會很自然地呼叫這裡，而不是自己重拼一份忘了 `--` 的陣列。
public enum OSAScriptCommand {

    /// 單一欄位的長度上限。
    ///
    /// ⚠️ **這不是防線。** 〔實測〕真實可用的注入 payload 約 45 字，
    /// 遠低於任何合理的上限 —— 截斷擋不住它。這個上限只是為了不要把
    /// 一整頁文字塞進通知橫幅。
    ///
    /// ⚠️ 也**不要**把它與 `WaitingContextReader.maxHeadlineLength`（120）
    /// 講成「同一個門檻的兩份定義」。兩者語意不同：那邊會把換行轉空白、trim、
    /// 超長補「…」，這邊只是純粹截斷。它們是兩件事，不是規矩「門檻只定義在一處」
    /// 的違反。
    public static let maxFieldLength = 200

    /// 使用者看不到、但一定要是常數的那一格。
    public static let title = "QuotaMonster"

    /// ⚠️⚠️ **`--` 這一行是載重的，不是風格問題。**
    ///
    /// 沒有它就是 RCE，不是「比較不安全」。
    /// `-eproperty p:(do shell script "…")` 傳進去會被 osascript 自己的 getopt
    /// 吃掉、當成另一個 `-e` 片段，而 property 的初始值**在載入時就求值** ——
    /// 跑在 `run` handler 之前，而且與它成不成功無關。
    ///
    /// ### ⚠️ 它守的是哪一格：`body`，也就是 **transcript 尾端撈出來的文字**
    ///
    /// 這裡原本寫「專案名就是 cwd 的最後一段，使用者可以把目錄取成任何名字」。
    /// **那個歸因是錯的**，而且錯得很危險：〔讀碼確認〕
    /// `NotificationPresenter` 把專案名送進 **subtitle（item 3）**，
    /// 而 `--` 保護的是 **body（item 1）** —— 專案名永遠到不了那一格。
    ///
    /// item 1 真正的來源是 `WaitingContextReader` 從 transcript 尾端撈出來的
    /// `headline`：`AskUserQuestion` 的問題文字、工具的 `description`。
    /// **那是比目錄名更糟的威脅模型** —— 目錄名需要本機檔案系統控制權，
    /// 而 transcript 文字只要一個被 prompt injection 的 agent、
    /// 或一個惡意 MCP server 的工具描述就寫得進去。
    ///
    /// ⚠️ 這個誤植本身就是攻擊面：下一個人照著舊註解去追「專案名 → RCE」，
    /// 會發現專案名落在別的保護機制底下，於是判定註解過期而把 `--` 刪掉。
    ///
    /// ### item 3 是被**另一個**機制保護的，不是被 `--`
    ///
    /// 〔實測〕subtitle 位置放同一個 payload，**就算拿掉 `--` 也不會執行** ——
    /// 因為 osascript 走 BSD getopt（遇到第一個非選項就停止掃描），
    /// 而 item 2 的常數標題 `QuotaMonster` 正好是那個非選項。
    /// 反證：把 item 2 換成 `-i`，item 3 的 property 就會 fired。
    ///
    /// **所以「標題永遠是常數」是承載安全性的，不只是署名問題。**
    /// 參數一旦重排成「使用者欄位排在最前、前面全是選項」，
    /// 或標題改成可變的，subtitle 那一格就會變成可注入。
    ///
    /// ⚠️〔實測〕那個常數擋 item 3 靠兩層（停掃／污染編譯），但兩層都是**偶然**的。
    /// `--` 才是設計出來的那一道。
    ///
    /// ### 內容層逃逸擋在別的地方
    ///
    /// 三個欄位用 `item N of argv` **取值**，不是字串內插 ——
    /// 所以 `x" & (do shell script "…") & "y` 這種引號逸出〔實測〕在有無 `--`
    /// 兩種情況下都是死的。改成字串內插會讓它活過來，而 `--` 對它完全無效。
    public static func arguments(body: String, subtitle: String) -> [String] {
        [
            "-e", "on run argv",
            "-e", "display notification (item 1 of argv) "
                + "with title (item 2 of argv) subtitle (item 3 of argv)",
            "-e", "end run",
            "--",                 // ← 少了這一行就是 RCE，理由見上面整段
            clean(body),          // item 1 —— transcript 來的，`--` 守的就是這一格
            title,                // item 2 —— 常數。**絕不**讓使用者字串進到標題
            clean(subtitle),      // item 3 —— 專案名（cwd 最後一段）
        ]
    }

    /// ⚠️ NUL 會讓 `Process.arguments` 丟出 Swift `do/catch` **接不到**的
    /// ObjC 例外，整個 app 當場死掉。`~/.claude` 的 JSON 可以合法帶出 NUL。
    public static func clean(_ s: String) -> String {
        let stripped = String(String.UnicodeScalarView(
            s.unicodeScalars.filter { $0.value != 0 }))
        return String(stripped.prefix(maxFieldLength))
    }
}
