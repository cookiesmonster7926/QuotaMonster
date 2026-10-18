import Foundation

/// context 壓力的兩個門檻（黃／紅）。
///
/// **權威不在這個 repo 裡，在使用者自己的狀態列腳本裡** —— 預設值抄的是那份腳本
/// （70% 黃、90% 紅），兩邊看起來才是同一個系統，而不是兩套各說各話的顏色。
///
/// ⚠️ 規矩 24（黃／琥珀只代表「要你輸入」）**唯一授權的例外就是這裡**，
/// 而授權的理由正是「它抄的是使用者自己的色階」。一旦這兩個數獨立於那份
/// 腳本漂走，那個例外就失去理由，面板上會出現一個沒有依據的黃色。
public struct ContextThresholds: Equatable, Sendable {
    public let yellow: Int
    public let red: Int

    /// ⚠️ **這是唯一的字面量定義處**（規矩 2）。搬移前住在
    /// `SessionRow.defaultContextYellow` / `.defaultContextRed`，
    /// 而 `?? 預設` 在面板、`--render-panel`、偏好視窗各寫了一次。
    public static let standard = ContextThresholds(yellow: 70, red: 90)

    /// 不夾限 —— 夾限在 `Preferences.sanitised()`（讀檔時）與偏好視窗的按鈕（UI）。
    public init(yellow: Int, red: Int) {
        self.yellow = yellow
        self.red = red
    }

    /// 偏好覆寫的解析：**兩格各自** `?? 預設`。
    ///
    /// ⚠️ 這與 `QuotaThresholds` 的「兩個要嘛都有、要嘛都沒有」不同 —— 這是搬移前的行為。
    /// 它留著一個邊角：手改偏好檔只設 `contextYellow: 95`，`sanitised()` 只在兩格都有時
    /// 才檢查黃 < 紅，於是解析成黃 95／紅 90。後果見 `ContextGauge.colouredNumber`。
    public init(_ prefs: Preferences) {
        self.init(yellow: prefs.contextYellow ?? Self.standard.yellow,
                  red: prefs.contextRed ?? Self.standard.red)
    }
}

/// ctx 細條是哪一級。App 層把它翻成綠／黃／紅。
public enum ContextPressure: Equatable, Sendable {
    case calm
    case warning
    case critical

    /// 邊界含等號：剛好 70 是黃、剛好 90 是紅。紅先判 —— 黃 > 紅時紅仍然贏。
    public init(percent: Int, thresholds: ContextThresholds) {
        self = percent >= thresholds.red ? .critical
            : percent >= thresholds.yellow ? .warning : .calm
    }
}

/// 面板 ctx 那一行要畫的全部東西。**建不出來（nil）＝整行不畫。**
///
/// 只有 statusline tee 拿得到這個數字 —— 磁碟上沒有別的地方記錄它。
/// 沒有讀數時整行不顯示，而不是顯示 0% 或一條空的長條：一條 0% 的長條看起來像
/// 「還很空」，但實際意思是「不知道」（規矩 3）。
public struct ContextGauge: Equatable, Sendable {
    public let percent: Int
    public let pressure: ContextPressure
    /// 百分比數字要不要跟著長條上色；false ＝ secondary。
    ///
    /// 判準是「≥ 黃門檻」，不是「`pressure != .calm`」—— 搬移前的寫法，兩者只在
    /// 黃 > 紅（見 `ContextThresholds.init(_:)`）時不同：那時介於紅與黃之間的讀數
    /// 長條是紅的、數字卻是 secondary。要修請另開一件事，不要在搬移裡順手改。
    public let colouredNumber: Bool
    /// 「1M」／「200k」。payload 沒有窗口大小時是 nil（那一格不畫）。
    public let windowLabel: String?

    public init?(_ payload: StatusLinePayload?, thresholds: ContextThresholds) {
        guard let used = payload?.contextUsedPercent else { return nil }
        self.percent = used
        self.pressure = ContextPressure(percent: used, thresholds: thresholds)
        self.colouredNumber = used >= thresholds.yellow
        self.windowLabel = payload?.contextWindowSize.map(Self.windowLabel)
    }

    /// ≥ 1,000,000 寫「1M」，其餘寫整數 k（無條件捨去）。
    ///
    /// ⚠️ 面板與 `--dump` 共用這一支 —— 搬移前兩邊各寫一次（規矩 48：同一段文字
    /// 在兩個畫面上只能有一份實作）。
    /// ⚠️ 〔推論〕「≥ 1M 一律寫 1M」成立的前提是 1M 是已知最大的窗口；
    /// 出現 2M 的窗口時它會說謊。
    public static func windowLabel(_ size: Int) -> String {
        size >= 1_000_000 ? "1M" : "\(size / 1000)k"
    }
}
