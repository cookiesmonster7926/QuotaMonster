import Foundation

/// 「那個 session 到底在問什麼」。
public struct WaitingContext: Equatable, Sendable {
    /// 浮窗上最大的那一行。
    public let headline: String
    /// 待批准的工具名（`Bash` / `AskUserQuestion` / …）。
    public let toolName: String
    /// 次要的一行 —— 指令本體、檔案路徑之類的。沒有就是 nil。
    public let detail: String?

    public init(headline: String, toolName: String, detail: String?) {
        self.headline = headline
        self.toolName = toolName
        self.detail = detail
    }
}

/// 從 transcript 尾端撈出「還在等你的那個 tool_use」。
///
/// ⚠️ **絕不在 UI 路徑上整檔解析。** 活躍 transcript 實測 480KB–878KB，
/// 每 20 秒每 agent 成長 5–35KB。所以：
///   - 只從**檔尾**往回讀固定 byte 數，不是 `Data(contentsOf:)`
///   - 只在**要浮窗的那一刻**被呼叫一次，不是每三秒
///
/// 讀不到就回 nil，呼叫端退回分類文字（「在問你問題」／「等你批准工具」），
/// **不是留白**。留白會讓使用者以為是 app 壞了。
public struct WaitingContextReader: Sendable {

    /// 從檔尾往回讀多少。
    ///
    /// 64KB 的理由：單一一則 assistant 訊息帶著一個 Write 工具的 content 就可能
    /// 好幾十 KB，太小會讓「最後一則」整個落在視窗外；太大就退化成整檔讀。
    public static let tailBytes = 64 * 1024
    /// 浮窗只有一行，而工具參數可以是整個檔案。
    public static let maxHeadlineLength = 120
    public static let maxDetailLength = 200

    public init() {}

    public func read(_ transcript: URL) -> WaitingContext? {
        guard let tail = Self.tail(of: transcript, bytes: Self.tailBytes) else { return nil }

        // 由後往前找第一則帶 tool_use 的 assistant 訊息。
        // 前面那些工具都已經批准過了 —— 還在等的只會是最後一個。
        for line in tail.split(separator: "\n").reversed() {
            guard let data = line.data(using: .utf8), !data.isEmpty,
                  let obj = try? JSONSerialization.jsonObject(with: data),
                  let row = obj as? [String: Any],
                  let message = row["message"] as? [String: Any],
                  (message["role"] as? String) == "assistant",
                  let content = message["content"] as? [[String: Any]]
            else { continue }   // 檔尾被截斷的半行、或不是我們要的型別 → 往前找

            // 最後一則 assistant 沒有 tool_use，就代表沒有待批准的東西。
            guard let tool = content.last(where: { ($0["type"] as? String) == "tool_use" })
            else { return nil }

            let name = (tool["name"] as? String) ?? "?"
            let input = (tool["input"] as? [String: Any]) ?? [:]
            return Self.context(toolName: name, input: input)
        }
        return nil
    }

    // ── 從哪一個欄位拿那一行字 ──────────────────────────────────

    static func context(toolName: String, input: [String: Any]) -> WaitingContext? {
        // AskUserQuestion：問題本文就是那一行英雄字，不需要任何轉述。
        if let questions = input["questions"] as? [[String: Any]],
           let first = questions.first,
           let q = first["question"] as? String {
            return WaitingContext(headline: clean(q, Self.maxHeadlineLength),
                                  toolName: toolName,
                                  detail: (first["header"] as? String).map { clean($0, 40) })
        }

        // description 優先於 command：指令可能是三行 shell，而 description
        // 本來就是寫給人看的一句話。
        if let d = input["description"] as? String, !d.isEmpty {
            let detail = ["command", "file_path", "pattern", "url"]
                .compactMap { input[$0] as? String }.first
            return WaitingContext(headline: clean(d, Self.maxHeadlineLength),
                                  toolName: toolName,
                                  detail: detail.map { clean($0, Self.maxDetailLength) })
        }

        // 都沒有就退回工具名，外加第一個像樣的欄位。
        let detail = ["command", "file_path", "path", "pattern", "url", "prompt"]
            .compactMap { input[$0] as? String }.first
        guard let detail else { return WaitingContext(headline: toolName, toolName: toolName, detail: nil) }
        return WaitingContext(headline: toolName, toolName: toolName,
                              detail: clean(detail, Self.maxDetailLength))
    }

    /// ⚠️ **NUL 一定要在這裡就拿掉。** 這些字串會一路流到
    /// `Process.arguments`（osascript 通道），而帶 NUL 的參數會丟出一個
    /// Swift `do/catch` 接不到的 ObjC 例外 —— app 當場死掉，不是顯示錯誤。
    /// `JSONSerialization` 會老老實實把 JSON 裡的 `U+0000` 給你。
    static func clean(_ s: String, _ limit: Int) -> String {
        let stripped = String(String.UnicodeScalarView(
            s.unicodeScalars.filter { $0.value != 0 }))
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped.count <= limit ? stripped : String(stripped.prefix(limit - 1)) + "…"
    }

    // ── 只讀檔尾 ───────────────────────────────────────────────

    static func tail(of url: URL, bytes: Int) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let end = try? handle.seekToEnd(), end > 0 else { return nil }

        let start = end > UInt64(bytes) ? end - UInt64(bytes) : 0
        guard (try? handle.seek(toOffset: start)) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else { return nil }

        // 從中間切進去可能剛好切斷一個多位元組字元，所以先丟掉第一個換行之前的東西
        // （那一段本來就是半行，反正也解不出來）。
        if start > 0, let nl = data.firstIndex(of: UInt8(ascii: "\n")) {
            return String(decoding: data[(nl + 1)...], as: UTF8.self)
        }
        return String(decoding: data, as: UTF8.self)
    }
}
