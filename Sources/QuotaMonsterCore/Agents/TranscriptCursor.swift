import Foundation

/// 一個 append-only 檔案「讀到哪裡了」。每次只把**新增的完整行**交出來。
///
/// ### 為什麼要有這個東西
/// 〔實測 2026-09-22〕`AgentTreeBuilder.toolUseIds` 用 `String(contentsOf:)` 把整份母
/// transcript 讀進來，**每 3 秒一次、在 main actor 上**。這台機器最大的 transcript
/// 22.4MB、還活著的最大 16.1MB，單次量到 0.513 秒；其中只有 0.014 秒是 I/O，
/// **97% 是 JSON 解析**。所以要省的是「重新解析舊的行」——
/// 一個只避開重讀 bytes、卻照樣重新解析的「增量」讀取一點都不會比較快。
///
/// ### ⚠️ 這不是 `WaitingContextReader.tail` 的另一種寫法
/// 那一支從尾端往回抓 64KB，並且**丟掉第一個換行之前的東西**——因為它切在半行上。
/// 從記住的 offset 往前讀時，第一個 byte **就是**某一行的開頭；
/// 照抄那個行為會每讀一次就靜靜地吃掉一筆記錄。
///
/// ### ⚠️ 只有路徑與大小不夠
/// transcript 會在 compact / fork / `--resume` 時被**整個重寫**。它可能變短，
/// 也可能**大小一樣而內容整個換掉**（寫新檔再 rename 上去）。後者 size 與 mtime
/// 都測不出來，只有 inode 測得到。認錯了就是從一個錯的位移往下讀，交出半行垃圾。
/// 這個 repo 已經為「拿 mtime 當內容的年紀」付過兩次代價（`~/CLAUDE.md`）。
public struct TranscriptCursor: Equatable, Sendable {

    /// 讀一次的結果。
    ///
    /// ⚠️ **「沒有新東西」與「讀不到」是兩件事**，不可以塌縮成同一個值。
    /// 前者是正面證據（我們看了，沒有新的完成）；後者不是證據（我們沒看到）。
    /// 這就是 `~/CLAUDE.md` 那條兩層規矩在這裡的落點，
    /// 反面教材是 `WaitingContextReader.tail` —— 它把三種失敗塌縮成一個 nil，
    /// 而 `TurnCompletionReader` 的檔頭已經把它點名了。
    public enum Read: Equatable, Sendable {
        /// 我們讀到了。`lines` 可能是空的（沒有新記錄）。
        ///
        /// - Parameter fromStart: 這一批是**從檔案的第 0 個 byte 開始**的 ——
        ///   第一次看到這個檔案，或它被整個重寫了。
        ///   ⚠️ 呼叫端必須把這一批當成「補課」而不是「剛發生」：
        ///   app 剛開機時整份 transcript 都是新的，但那些完成**不是我們見證的**。
        ///   （同一個原則寫在 `--trace-finishes` 的開場白裡。）
        case advanced(lines: [String], fromStart: Bool)
        /// 整個讀不到：檔案不見了、沒有權限、seek 失敗。
        case unreadable
    }

    /// 已經從檔案裡**拿走**到第幾個 byte。
    ///
    /// ⚠️ 它不一定停在某一行的開頭 —— 如果最後一次讀到的結尾是半行，
    /// 那半行已經被拿走了（offset 算進去了），暫存在 `partial` 裡。
    /// 第一版讓 offset 停在行首、半行留在檔案裡下次重讀，結果是**半行被讀兩次**：
    /// 「bb」+「bb\n」變成「bbbbbb」而不是「bbbb」。〔測試 aPartialLineIsNeither… 抓到〕
    public private(set) var offset: UInt64 = 0
    /// 上一次讀到的 inode。nil ＝ 還沒讀過。
    public private(set) var inode: UInt64?
    /// 上一次讀到、但還沒有換行的那半行。下一次讀要接在它前面。
    private var partial: Data = Data()

    public init() {}

    /// 讀走 `url` 從 `offset` 之後新增的完整行。
    ///
    /// 讀不到時**不動 offset** —— 檔案暫時消失（rename 的空窗）之後回來，
    /// 不應該整份重播。真的被換掉的話 inode 會不一樣，下一句自己會抓到。
    public mutating func read(_ url: URL) -> Read {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attrs[.size] as? NSNumber)?.uint64Value,
              let ino = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value,
              let handle = try? FileHandle(forReadingFrom: url)
        else { return .unreadable }
        defer { try? handle.close() }

        // 換了一個檔案、或它變短了 → 這一份是新的，從頭讀。
        let rewritten = (inode != nil && inode != ino) || size < offset
        let first = inode == nil
        if rewritten || first {
            offset = 0
            partial = Data()
        }
        inode = ino

        guard (try? handle.seek(toOffset: offset)) != nil else { return .unreadable }
        // ⚠️ `readToEnd()` 在**已經在檔尾**時回 nil，不是回空的 Data。
        // 把那個 nil 當成讀取失敗的話，「檔案沒長」與「空檔案」兩種正常情況
        // 都會變成 `.unreadable` —— 也就是把正面證據講成「沒看到」。〔兩則測試抓到〕
        let fresh = (try? handle.readToEnd()) ?? Data()
        // bytes 一旦拿走就算數，不管它是不是完整的行。
        offset += UInt64(fresh.count)

        var buffer = partial
        buffer.append(fresh)
        // 只交出到**最後一個換行**為止。後面那截留在 `partial`，下一次接上去。
        guard let lastBreak = buffer.lastIndex(of: UInt8(ascii: "\n")) else {
            partial = buffer
            return .advanced(lines: [], fromStart: rewritten || first)
        }
        let complete = buffer[..<lastBreak]
        partial = Data(buffer[buffer.index(after: lastBreak)...])

        let lines = complete
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
            .map { String(decoding: $0, as: UTF8.self) }
        return .advanced(lines: lines, fromStart: rewritten || first)
    }
}
