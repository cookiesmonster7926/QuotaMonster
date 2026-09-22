import Foundation

/// 面板那一列要顯示的 session 名字。
///
/// ### 註冊表的 `name` 有兩種來源，而它自己標得出來
/// 〔實測 2026-09-22〕`~/.claude/sessions/<pid>.json` 帶著 `nameSource`：
/// - `derived` —— Claude Code 從 cwd 湊出來的佔位名（`rl-1b`、`usage-ff`）。
///   **使用者從來沒有看過這個字串。**
/// - `auto` —— 有來歷的名字，與 transcript 裡的標題一致。
///
/// 使用者真正看到的那個名字（VS Code 分頁上的 `0922作業`、終端機的 `修t2`）
/// 只存在 transcript 裡，型別是 `{"type":"ai-title","aiTitle":"…"}`。
///
/// ### ⚠️ 為什麼是「只在 derived 時才去看」
/// `auto` 代表註冊表那個名字**是有來歷的**，蓋掉它等於把已知的事實換成猜測。
/// 〔實測〕`d8258fe6` 兩邊本來就一致 —— 這條閘不是為了那個情況，
/// 是為了**在不知道的時候不要動手**（`nameSource` 是 nil 時同理）。
///
/// ### ⚠️ 這不是「VS Code 專屬」的修補
/// 一開始是從「VS Code 外掛的 session 顯示成 rl-1b」查起的，但實測四個 session
/// 有三個是 `derived` —— 終端機的也一樣。`aiTitle` 是 Claude Code 自己寫的
/// （我這個 session 的 transcript 裡有 251 筆），與哪個前端無關。
public enum SessionTitle {

    /// 面板那一列的寬度撐不住一整段話。
    public static let maxLength = 40

    /// 重新撈一次標題的節奏。
    ///
    /// ⚠️ 面板每 3 秒刷新一次，而標題**很少變**。每次都去讀 64KB 的 transcript 尾端
    /// 等於為了一個幾乎不動的字串每秒讀幾十 KB。
    /// 〔實測 2026-09-22〕最後一筆 `ai-title` 離檔尾 176 / 2,529 / 15,666 bytes（n=3），
    /// 所以尾端大小沿用 `WaitingContextReader.tailBytes`（64KB）—— 不發明新門檻，
    /// 成本改用時間節流來壓。
    public static let refreshInterval: TimeInterval = 60

    /// 只有 Claude Code 自己湊出來的佔位名才讓位。
    public static func isPlaceholder(_ nameSource: String?) -> Bool {
        nameSource == "derived"
    }

    /// - Parameter transcriptTitle: 刻意是 closure 而不是值 ——
    ///   讀 transcript 是 I/O，`auto` 與 nil 的情況下**一次都不該發生**
    ///   （有測試數呼叫次數釘住）。
    public static func display(name: String?, nameSource: String?,
                               transcriptTitle: () -> String?) -> String? {
        guard isPlaceholder(nameSource) else { return name }
        return transcriptTitle() ?? name
    }

    /// 直接從 transcript 檔案撈。
    ///
    /// ⚠️ 讀多少 byte 是**決策**，所以它待在 Core（有測試的這一側），
    /// 不讓 App 層自己挑一個數字 —— 那會變成第二份定義。
    /// 沿用 `WaitingContextReader.tailBytes`（64KB）：〔實測 2026-09-22〕
    /// 最後一筆 `ai-title` 離檔尾 176 / 2,529 / 15,666 bytes（n=3），餘裕充足。
    public static func aiTitle(inTranscript url: URL) -> String? {
        guard let tail = WaitingContextReader.tail(of: url, bytes: WaitingContextReader.tailBytes)
        else { return nil }
        return aiTitle(inTail: tail)
    }

    /// 從 transcript 尾端那段文字裡撈最後一個 `ai-title`。
    ///
    /// ⚠️ **逐行 parse JSON，不用正則。** 標題是使用者打的字，可以含引號、
    /// 反斜線、`\uXXXX`；正則切出來的是跳脫前的原文，會把 `a\"b` 顯示成 `a\"b`。
    /// ⚠️ 尾端讀取的第一行**通常是被切一半的**，parse 失敗就跳過，不是整個放棄。
    public static func aiTitle(inTail tail: String) -> String? {
        var found: String?
        for line in tail.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  obj["type"] as? String == "ai-title",
                  let raw = obj["aiTitle"] as? String
            else { continue }
            let cleaned = clean(raw)
            if !cleaned.isEmpty { found = cleaned }   // 後面的蓋掉前面的：要最新的那個
        }
        return found
    }

    // ── 同名 ───────────────────────────────────────────────────

    public struct Titled: Equatable, Sendable {
        public let id: String
        public let title: String
        /// 註冊表的 `name`。它是唯一的（`usage-ff` / `usage-c9` / `rl-b5`），
        /// 所以同名時接上去就分得開。`nil` 代表接不了。
        public let uniqueKey: String?
        public init(id: String, title: String, uniqueKey: String?) {
            self.id = id; self.title = title; self.uniqueKey = uniqueKey
        }
    }

    /// 同名的 session 各自接上唯一鍵；不同名的完全不動。
    ///
    /// ⚠️ **這不是邊緣案例。**〔實測 2026-09-22〕5 個存活 session 裡有 4 個
    /// 落在同名配對中（80%）—— fork／resume 同一段對話會沿用同一個 `aiTitle`。
    /// 使用者看到兩列一模一樣，第一反應是「這是不是壞了」。
    /// 這是 2026-09-22 引入 `aiTitle` 時造成的回歸。
    ///
    /// ⚠️ 唯一鍵**本身**就是顯示名時不接（否則會變成「A · A」）——
    /// 實測會發生：`nameSource == "auto"` 的那個 session，它的 registry name
    /// 就是顯示名，而旁邊那個的 `aiTitle` 剛好是同一個字串。
    public static func disambiguate(_ items: [Titled]) -> [String: String] {
        var count: [String: Int] = [:]
        for i in items { count[i.title, default: 0] += 1 }
        var out: [String: String] = [:]
        for i in items {
            guard count[i.title, default: 0] > 1,
                  let key = i.uniqueKey, key != i.title
            else { out[i.id] = i.title; continue }
            out[i.id] = "\(i.title) · \(key)"
        }
        return out
    }

    /// 換行轉空白、去頭尾空白、截斷。面板那一列只有一行。
    public static func clean(_ s: String) -> String {
        let flat = s.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(flat.prefix(maxLength))
    }
}
