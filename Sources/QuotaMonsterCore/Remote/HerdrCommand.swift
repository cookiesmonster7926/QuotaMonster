import Foundation

/// 問 herdr 的那兩句話（argv）、去哪裡找它、多久問一次。
///
/// ### 為什麼是 herdr
/// 遠端機器（例如另一台用 SSH 連著的電腦）上的 Claude session，這台 Mac 的檔案裡沒有。
/// herdr（終端機多工器）連著那台機器，`herdr --machine <id> agent list` 會回那台的 session 清單
/// 〔實測 herdr 0.9.3〕。SSH 由 herdr 自己管（它設好的連線、BatchMode），這個 app 不碰 SSH、不碰金鑰。
///
/// ### 只用 herdr 自己的欄位
/// 狀態（working／blocked／done／idle）、cwd、分頁標題。**沒有** session id、ctx、agent、時間戳 ——
/// 遠端的列因此只畫計數與「等你回覆」，不畫跑了多久（畫了就是編的）。
///
/// ⚠️ argv 不經 shell（`Process.arguments`），但 machine id 仍然要過白名單：
/// 它是 herdr 給的字串，而 `-` 開頭的字串放進 argv 會被 herdr 當成旗標
/// （~/CLAUDE.md 的跨專案規則：交給另一個程式的字串，威脅模型包括那個程式自己的參數解析）。
public enum HerdrCommand {

    /// `herdr machine list --json` —— 機器清單（每台的 id、label、enabled）。
    public static let machineList = ["machine", "list", "--json"]

    /// `herdr --machine <id> agent list`。
    ///
    /// ⚠️ `--machine` 吃 machine list 的 **id**，不是 label 也不是 target —— 用 target 會 exit 2
    /// `unknown machine '…'`〔實測〕。`agent list` 本來就輸出 JSON，加 `--json` 反而 exit 2〔實測〕。
    /// - Returns: nil ＝ id 過不了白名單，不可以拿去執行。
    public static func agentList(machineId: String) -> [String]? {
        guard isValidMachineId(machineId) else { return nil }
        return ["--machine", machineId, "agent", "list"]
    }

    /// 英數開頭（不會被當成旗標），之後英數與 `_ . -`，最長 64。
    /// herdr 的 id 實際是 32 位 hex〔實測〕；白名單寬一點，但不收任何會改變 argv 意思的字元。
    public static func isValidMachineId(_ id: String) -> Bool {
        guard (1...64).contains(id.unicodeScalars.count) else { return false }
        for (i, u) in id.unicodeScalars.enumerated() {
            let alnum = (u >= "a" && u <= "z") || (u >= "A" && u <= "Z") || (u >= "0" && u <= "9")
            if i == 0 ? !alnum : !(alnum || u == "_" || u == "." || u == "-") { return false }
        }
        return true
    }

    /// 去哪裡找 herdr。
    ///
    /// ⚠️ GUI app 的 PATH 只有系統目錄，**找不到 `~/.local/bin`**（herdr 的安裝位置〔實測〕），
    /// 所以不靠 PATH，自己列。第一個存在而且可執行的就是它；一個都沒有 ＝ 沒裝 herdr。
    public static func candidatePaths(home: URL) -> [URL] {
        [home.appendingPathComponent(".local/bin/herdr"),
         URL(fileURLWithPath: "/opt/homebrew/bin/herdr"),
         URL(fileURLWithPath: "/usr/local/bin/herdr")]
    }

    /// 一次呼叫最多等多久。
    ///
    /// 〔實測 2026-10-20，照輪詢節奏每 10 秒讀一次、20 次〕遠端 `agent list` 全部成功，
    /// 最快 1.77 秒、中位約 2.9 秒、最慢 5.21 秒 —— 不只是第一次連線慢，平常就是 2–5 秒。
    /// 15 秒是最慢那次的三倍；超過它就當成這一輪連不上。
    public static let timeout: TimeInterval = 15

    /// 遠端每台多久讀一次（正常時）。連續失敗會退避，見 `RemoteTracker`。
    public static let remoteInterval: TimeInterval = 10

    /// 機器清單多久讀一次。清單很少變；`unknown machine` 時會馬上重讀。
    public static let machineListInterval: TimeInterval = 60
}
