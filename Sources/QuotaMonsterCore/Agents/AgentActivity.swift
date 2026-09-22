import Foundation

/// 一般 Agent subagent 還在不在跑 —— 靠 transcript 最近有沒有被寫入來**推定**。
///
/// ### 為什麼只能推定
/// 〔實測 2026-09-22〕workflow subagent 有 `journal.jsonl`
/// （`started` / `result` / `failed` / `launched`），狀態是**讀到的**。
/// 一般 Agent subagent 只有 `.meta.json`，內容是
/// `agentType` / `description` / `toolUseId` / `spawnDepth` / `requestShape` ——
/// **一個狀態欄位都沒有**，也沒有 journal。磁碟上真的沒有那個資訊。
///
/// 唯一還在動的東西是它自己的 transcript：〔實測〕一個正在跑的 agent
/// 五秒內從 286KB 長到 306KB。
///
/// ### ⚠️ 這是代理量測，而且兩個方向的錯不對稱
/// - 還在想但一直沒寫字 → 被說成停了（**少報**，可接受）
/// - 已經被殺掉 → 被說成還在跑，最長一個窗口（**謊報**，這是代價）
///
/// 這個 repo 原本的選擇是「寧可少報，不要謊報」（`AgentRunState.unknown`）。
/// 使用者 2026-09-22 拍板換成「代理量測 + 誤差已知」，條件是
/// **誤差要量出來、而且畫面上分得出來哪些是推定的**。
/// 所以它有自己的 `AgentRunState.likelyRunning`，不與 journal 讀到的 `.running` 混用。
public enum AgentActivity {

    /// 多久沒寫字就不再推定它在跑。
    ///
    /// 〔實測 2026-09-22，32 個 agent transcript／4,687 個相鄰寫入間隔〕
    /// ```
    /// 中位數 0.4s   p90 4.5s   p99 57.6s   p99.9 641.9s
    /// >60s  佔 0.96%
    /// >120s 佔 0.45%   ← 選這個
    /// >180s 佔 0.24%
    /// ```
    /// 也就是說：**約 0.45% 的觀測時刻會把「還在想」誤判成「停了」。**
    /// 反方向的代價（被殺掉之後仍顯示在跑）最長就是這個窗口。
    public static let window: TimeInterval = 120

    /// - Parameter lastWrite: transcript 的 mtime。`nil` 代表**讀不到** ——
    ///   那是「不知道」，不是「停了」，所以不推定（規矩：不存在 ≠ 那個狀態不成立）。
    /// 未來的時間戳可以往前多遠還算數。
    ///
    /// ⚠️ **沒有上界就是一個永遠不會消失的列。** 時鐘往回跳幾秒、檔案從別台機器
    /// 同步過來，那些是真的、該當成「還在跑」；但一個 mtime 在 2099 的檔案
    /// 會**永遠**被推定在跑，而且沒有任何東西會把它清掉。
    ///
    /// 〔code review 2026-09-22 抓到〕`StatusLineCacheReader:73` 早就夾住了
    /// （`min(mtime ?? now, now)`，而且註解寫明理由），`WindowExpiry` 也有
    /// `horizon`。這裡與 `AgentTreeBuilder.isFresh` 當初都沒有 —— 同一個
    /// 不對稱在這個 repo 已經出現第三次。
    public static let futureTolerance: TimeInterval = window

    public static func isLikelyRunning(lastWrite: Date?, now: Date) -> Bool {
        guard let lastWrite else { return false }
        let age = now.timeIntervalSince(lastWrite)
        // 未來一點點算「還在跑」—— 猜錯的方向要選「訊號還在」，
        // 與 `FinishGlow.at` 同一條原則。但太未來就是壞掉的時間戳，不是訊號。
        guard age > -futureTolerance else { return false }
        return age < window
    }
}
