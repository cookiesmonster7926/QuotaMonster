import Foundation

/// 警示音效要放什麼。
public enum AlertSoundChoice: Equatable, Sendable, Codable {
    /// `NSSound(named:)` 找得到的名字。`~/Library/Sounds` 裡使用者自己的 .wav 也算。
    case named(String)
    /// 不出聲。
    case silent
}

/// 使用者直接調過的東西。**沒調過的欄位在磁碟上不存在。**
///
/// ### 為什麼這個檔案存在（套 `NotifyState` 檔頭的三問）
/// 1. **是不是使用者直接下的指令？** 是 —— 這整個型別的定義就是那個。
/// 2. **是不是抑制方向？** 不是。裡面每一項調壞了都**看得出來**
///    （聽不到聲音、靜音在錯的時間解除、顏色在錯的百分比變）。
///    看不出來的那些**不在這裡**，那是刻意的（見下）。
/// 3. **跨度有沒有長過 app 的一次執行？** 有，它是永久的。
/// 三問都指向「要存」，所以它存。
///
/// ### ⚠️ 為什麼欄位這麼少
/// 這個 app 有將近三十個門檻，這裡只有三個。被擋在外面的分成兩種：
///
/// - **有量測撐著的界線。** 例：`CompletionTracker.settleWindow = 90`
///   （〔實測 n=153〕兩行式 end_turn 的間隔最大 51.8 秒，砍到 45 秒就會在
///   使用者眼前還沒有任何文字時宣告完成）、`SoundBudget.capacity = 3`
///   （往下調會**安靜地**吞掉真的完成通知 —— 沒有聲音與沒有事件在使用者端
///   一模一樣）。**使用者親自選過不等於它是口味**：`capacity` 與
///   `Presence.idleThreshold` 都是使用者拍板的，但它們調壞的方向是無聲的。
/// - **兩個方向都無聲的。** 這種常數加上下限也不會變安全，只會**感覺**安全：
///   一個「從來不發生」的功能與一個「被關掉」的功能長得一模一樣。
///
/// ### ⚠️ 也刻意沒有通用的旋鈕登記表
/// 沒有 `Tunable<V>`、沒有 `TuningKey`、沒有解析型別。有登記表就等於
/// 「加一格旋鈕＝改一行」，而**一份加起來很便宜的白名單不是白名單**。
/// 具名欄位讓第四格旋鈕的成本是一個欄位 + 一列 UI + 一則測試 ——
/// 那個摩擦力是功能，不是阻力。
///
/// ### ⚠️ 不用 `UserDefaults`
/// 純 CLI binary（`--dump` 這些）沒有 bundle identifier，`UserDefaults.standard`
/// 會落在以行程名推出的網域，而 `.app` 落在 `com.…QuotaMonster` ——
/// 於是 `--dump` 會印出一個 app 根本沒在讀的數字，**兩邊都不報錯**。
/// 那是規矩 28（說謊的診斷比沒有診斷更糟）。
/// 而且 `registerDefaults` 在設計上就是「把每個預設值再寫一次」，是規矩 2 的反面。
public struct Preferences: Equatable, Sendable, Codable {

    /// nil ＝ 沒調過，用預設。
    ///
    /// ⚠️ **每一格都是 Optional，而且磁碟上不可以出現預設值。**
    /// 這樣新的量測把預設從 90 改成 120 時，沒調過的使用者會跟著走 ——
    /// 而把預設值寫進檔案的設計做不到這件事。一個沒動過設定的使用者，
    /// 他的 `preferences.json` 是 `{}`。
    public var alertSound: AlertSoundChoice?
    /// 「靜音到明早」的那個「明早」是幾點。
    public var morningHour: Int?
    /// context 壓力的黃／紅門檻。權威是使用者自己的狀態列腳本。
    public var contextYellow: Int?
    public var contextRed: Int?
    /// 額度分級的兩個邊界（剩餘比例）。**兩個要嘛都有、要嘛都沒有** ——
    /// 只設一邊會讓另一邊用預設，而那兩個數的意義是相對的。
    public var quotaCritical: Double?
    public var quotaTight: Double?

    public init(alertSound: AlertSoundChoice? = nil, morningHour: Int? = nil,
                contextYellow: Int? = nil, contextRed: Int? = nil,
                quotaCritical: Double? = nil, quotaTight: Double? = nil) {
        self.alertSound = alertSound
        self.morningHour = morningHour
        self.contextYellow = contextYellow
        self.contextRed = contextRed
        self.quotaCritical = quotaCritical
        self.quotaTight = quotaTight
    }

    public static let empty = Preferences()

    // ── 夾限 ───────────────────────────────────────────────────

    /// 把手改壞的值夾回合理範圍。
    ///
    /// ⚠️ **在 `load` 的時候做，不是在 UI 做。** UI 的 `Picker` 本來就生不出
    /// 荒謬的值；這一層擋的是有人直接編輯 JSON。
    /// 夾不回來的（黃 ≥ 紅）整組丟掉 —— 那不是一個可以夾的錯，
    /// 而一組互相矛盾的門檻比沒有設定更糟。
    public func sanitised() -> Preferences {
        var p = self
        p.morningHour = morningHour.map { min(max($0, 0), 23) }
        let y = contextYellow.map { min(max($0, 1), 99) }
        let r = contextRed.map { min(max($0, 2), 100) }
        if let y, let r, y >= r {
            p.contextYellow = nil
            p.contextRed = nil
        } else {
            p.contextYellow = y
            p.contextRed = r
        }
        // 額度門檻：只設一邊就整組丟掉（兩個數的意義是相對的），
        // 其餘交給 `QuotaThresholds.init` 夾限。
        if let c = quotaCritical, let t = quotaTight {
            let fixed = QuotaThresholds(critical: c, tight: t)
            p.quotaCritical = fixed.critical
            p.quotaTight = fixed.tight
        } else {
            p.quotaCritical = nil
            p.quotaTight = nil
        }
        return p
    }

    // ── 讀寫 ───────────────────────────────────────────────────

    public static let relativePath =
        "Library/Application Support/QuotaMonster/preferences.json"

    public static func defaultURL(home: URL) -> URL {
        home.appendingPathComponent(relativePath)
    }

    /// 壞檔、空檔、不存在一律回 nil。**不丟錯。**
    public static func load(_ url: URL) -> Preferences? {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let p = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return nil }
        return p.sanitised()
    }

    /// ⚠️ **這個寫入器不自我收尾。** `NotifyState.save` 會在寫檔時清掉過期的
    /// `mutedUntil` —— 那是一個會自己刪東西的檔案。偏好檔繼承那個形狀就完了：
    /// 使用者的設定會在某次寫檔時被悄悄改掉。
    @discardableResult
    public static func save(_ p: Preferences, to url: URL) -> Bool {
        let e = JSONEncoder()
        e.outputFormatting = .sortedKeys
        guard let data = try? e.encode(p.sanitised()) else { return false }
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do { try data.write(to: url, options: .atomic) } catch { return false }
        return true
    }
}
