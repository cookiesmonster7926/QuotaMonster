import SwiftUI
import QuotaMonsterCore

/// 偏好設定。
///
/// ### ⚠️ 這裡只有六格，而那是設計不是省事
/// 這個 app 有將近三十個門檻。被擋在外面的理由寫在 `Preferences` 的檔頭：
/// 有量測撐著的界線不給調，兩個方向都無聲的常數也不給調。
/// **一個好的設定介面的價值一半在於它拒絕暴露什麼。**
///
/// 第五格（圖表樣式，2026-09-22 加）過得了那一關，是因為它**不是門檻**：
/// 它不改變任何判斷，只改變同一份資料畫成哪一種圖，而且選錯會**當場看見** ——
/// 上面那條「調了會安靜地壞掉」的判準對它不成立。
///
/// ### ⚠️ 三個元件在這裡是禁用的，理由都是「它會讓診斷說謊」
/// - **`Menu`** —— 離屏渲染下畫成一個紅色禁止符號（`MutePolicy` 檔頭已記）。
/// - **`Picker`** —— 預設樣式就是 `.menu`，所以是同一個洞的加重版：
///   登入按鈕那個洞是「整個不畫」（沉默），這個是**產出一張看起來很正常、
///   但那個角落是假的圖**。
/// - **`ScrollView`** —— 在 `ImageRenderer` 底下畫成空的
///   （`RenderPanel` 已為此另外渲染一份 `panel-rows.png`）。
/// - **`Stepper`** —— 〔實測 2026-09-19，`--render-prefs` 第一版〕
///   **它也畫成紅色禁止符號。** 這個 repo 原本只為 `Menu` 記下這件事，
///   實際上那是「AppKit 包裝的控制項在 `ImageRenderer` 底下不畫」的通則。
///   ⚠️ 這一條是**診斷自己抓到的** —— 我先避開了 Menu 與 Picker，
///   還是踩到第三個。
///
/// 所以這裡**只用 `Button` 與 `Text`**，而且版面不捲動。
///
/// ### ⚠️ 也沒有任何文字輸入欄位
/// `main.swift` 把 activation policy 設成 `.accessory`，後果是**沒有應用程式
/// 選單列** —— ⌘C／⌘V 在這扇視窗裡沒有作用，而且沒有任何提示。
/// 四個項目沒有一個需要打字，所以這個限制自動消失。
struct PreferencesView: View {

    @Bindable var store: DataStore
    /// 音效清單。⚠️ 由呼叫端抓一次傳進來，不要每次重繪都掃目錄。
    let sounds: [String]

    private var prefs: Preferences { store.preferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("偏好設定").font(.system(size: 13, weight: .semibold))

            panelRow
            Divider().opacity(0.5)
            chartRow
            Divider().opacity(0.5)
            soundRow
            Divider().opacity(0.5)
            morningRow
            Divider().opacity(0.5)
            contextRow
            Divider().opacity(0.5)
            quotaRow

            Text("這裡只有六項。其餘的門檻都有量測撐著 —— 調了會安靜地壞掉，所以它們不在這裡。")
                .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(width: 380, alignment: .leading)
    }

    // ── 面板版面 ───────────────────────────────────────────────

    /// 完整 / 簡易。與「圖表樣式」同一類：**不是門檻，是視圖**，
    /// 選錯的後果是你看到另一個版面 —— 響亮得不能再響亮。
    ///
    /// ⚠️ 面板 footer 上也有一顆同樣作用的鍵。兩個都留著是刻意的：
    /// 那顆鍵是順手切，這一格是「我想知道有這個選項」。兩邊寫同一個 `panelStyle`，
    /// 不是兩份狀態。
    private var panelRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            label("下拉面板的版面",
                  "簡易＝放大的標記＋兩個讀數；完整＝連 session 一起看")
            HStack(spacing: 8) {
                cycleButton("chevron.left") { cyclePanel(-1) }
                Text(store.panelStyle.label)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 120, alignment: .leading)
                cycleButton("chevron.right") { cyclePanel(1) }
                Spacer()
            }
        }
    }

    private func cyclePanel(_ step: Int) {
        let all = PanelStyle.allCases
        let i = all.firstIndex(of: store.panelStyle) ?? 0
        store.setPanelStyle(all[((i + step) % all.count + all.count) % all.count])
    }

    // ── 圖表樣式 ───────────────────────────────────────────────

    /// 額度底下那張圖要畫哪一種。**兩種回答的是不同的問題**，
    /// 所以這不是換皮：每日長條講「哪一天燒的」，累計曲線講「到現在燒了多少」。
    ///
    /// ⚠️ 用循環鍵而不是 `Picker` —— 理由見檔頭（`Picker` 在離屏渲染下
    /// 會畫出一張看起來正常、但那個角落是假的圖）。
    private var chartRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            label("額度底下那張圖",
                  "長條看「哪一天燒的」，曲線看「到現在燒了多少」")
            HStack(spacing: 8) {
                cycleButton("chevron.left") { cycleChart(-1) }
                Text(store.chartStyle.label)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 120, alignment: .leading)
                cycleButton("chevron.right") { cycleChart(1) }
                Spacer()
            }
        }
    }

    private func cycleChart(_ step: Int) {
        let all = ChartStyle.allCases
        let i = all.firstIndex(of: store.chartStyle) ?? 0
        var p = prefs
        p.chartStyle = all[((i + step) % all.count + all.count) % all.count]
        store.setPreferences(p)
    }

    // ── 音效 ───────────────────────────────────────────────────

    /// 循環鍵 + 試聽。形狀抄面板那顆靜音鍵（這個 repo 已經決定過
    /// 循環鍵優於 `Menu`，理由見 `MutePolicy.next`）。
    ///
    /// ⚠️ **試聽不是裝飾，是這一格唯一的回饋。** `AlertSound.play()` 回的 Bool
    /// 兩個呼叫點都丟掉，所以名字找不到時是**完全靜默且沒有錯誤** ——
    /// 使用者只能靠耳朵確認他選的那個真的存在。
    private var soundRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            label("有人在等你時的音效", "轉到哪一個就試聽哪一個")
            HStack(spacing: 8) {
                cycleButton("chevron.left") { cycleSound(-1) }
                Text(soundLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .frame(minWidth: 120, alignment: .leading)
                cycleButton("chevron.right") { cycleSound(1) }
                Button { _ = AlertSound.play() } label: {
                    Image(systemName: "speaker.wave.2").font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("再聽一次現在選的這個")
                Spacer()
            }
        }
    }

    private var current: AlertSoundChoice {
        prefs.alertSound ?? .named(AlertSound.defaultName)
    }

    private var soundLabel: String {
        switch current {
        case .silent:       return "不出聲"
        case .named(let n): return n == AlertSound.defaultName ? "\(n)（預設）" : n
        }
    }

    /// 所有可選項。「不出聲」排在最後 —— 往右轉不會第一下就把聲音關掉。
    private var options: [AlertSoundChoice] {
        sounds.map { AlertSoundChoice.named($0) } + [.silent]
    }

    private func cycleSound(_ step: Int) {
        let all = options
        guard !all.isEmpty else { return }   // 掃不到任何音效時不要崩
        let i = all.firstIndex(of: current) ?? 0
        var p = prefs
        p.alertSound = all[((i + step) % all.count + all.count) % all.count]
        store.setPreferences(p)
        // ⚠️ 要在 `setPreferences` **之後**才播 —— 它才剛把 `AlertSound.choice` 換掉。
        _ = AlertSound.play()
    }

    // ── 「明早」是幾點 ─────────────────────────────────────────

    private var morningRow: some View {
        let hour = prefs.morningHour ?? MutePolicy.morningHour
        return VStack(alignment: .leading, spacing: 5) {
            label("「靜音到明早」的明早", "面板那一行本來就會寫出實際到期時刻")
            nudge(value: String(format: "%02d:00", hour),
                  canDecrease: hour > 5, canIncrease: hour < 11,
                  decrease: { var p = prefs; p.morningHour = hour - 1
                              store.setPreferences(p) },
                  increase: { var p = prefs; p.morningHour = hour + 1
                              store.setPreferences(p) })
        }
    }

    // ── ctx 門檻 ───────────────────────────────────────────────

    /// ⚠️ 標題刻意寫「對齊我的狀態列」而不是「context 門檻」。
    /// **權威不在這個 app 裡，在使用者自己的狀態列腳本裡** ——
    /// 而規矩 24（黃／琥珀只代表「要你輸入」）唯一授權的例外就是這裡，
    /// 授權的理由正是「它抄的是使用者自己的色階」。一旦這兩個數獨立於那份
    /// 腳本漂走，那個例外就失去理由，面板上會出現一個沒有依據的黃色。
    private var contextRow: some View {
        let yellow = prefs.contextYellow ?? SessionRow.defaultContextYellow
        let red = prefs.contextRed ?? SessionRow.defaultContextRed
        return VStack(alignment: .leading, spacing: 5) {
            label("對齊我的狀態列（context 壓力）",
                  "這兩個數要跟你自己的 statusline 腳本一樣，面板才是同一套語彙")
            HStack(spacing: 20) {
                // ⚠️ 兩邊互相夾住 —— 讓「黃 ≥ 紅」在 UI 上就到不了
                // （按鈕直接變成不能按）。`Preferences.sanitised()` 那一層
                // 擋的是手改 JSON，不是這裡。
                nudge(leading: { swatch(.yellow, yellow) },
                      canDecrease: yellow > 1, canIncrease: yellow < red - 1,
                      decrease: { var p = prefs; p.contextYellow = yellow - 5
                                  store.setPreferences(p) },
                      increase: { var p = prefs; p.contextYellow = min(yellow + 5, red - 1)
                                  store.setPreferences(p) })
                nudge(leading: { swatch(.red, red) },
                      canDecrease: red > yellow + 1, canIncrease: red < 100,
                      decrease: { var p = prefs; p.contextRed = max(red - 5, yellow + 1)
                                  store.setPreferences(p) },
                      increase: { var p = prefs; p.contextRed = min(red + 5, 100)
                                  store.setPreferences(p) })
            }
        }
    }

    // ── 額度門檻 ───────────────────────────────────────────────

    /// ⚠️ 說明那一行**必須**寫出「這同時決定額度警告什麼時候響」。
    /// T3 是在分級**變了的那一刻**發的，所以把 critical 調到 5%，
    /// 紅色警告也跟著晚到剩 5% 才響 —— 一個只說一半的標籤比沒有這個設定更糟。
    private var quotaRow: some View {
        let t = store.quotaThresholds
        return VStack(alignment: .leading, spacing: 5) {
            label("剩多少開始緊張", "這同時決定額度警告什麼時候響，不只是顏色")
            HStack(spacing: 20) {
                nudge(leading: { swatch(.green, Int(t.tight * 100)) },
                      canDecrease: t.tight > t.critical + 0.05,
                      canIncrease: t.tight < 0.90,
                      decrease: { setQuota(critical: t.critical, tight: t.tight - 0.05) },
                      increase: { setQuota(critical: t.critical, tight: t.tight + 0.05) })
                nudge(leading: { swatch(.red, Int(t.critical * 100)) },
                      canDecrease: t.critical > 0.05,
                      canIncrease: t.critical < t.tight - 0.05,
                      decrease: { setQuota(critical: t.critical - 0.05, tight: t.tight) },
                      increase: { setQuota(critical: t.critical + 0.05, tight: t.tight) })
            }
        }
    }

    /// ⚠️ 兩個一起寫 —— `Preferences.sanitised()` 對這一組是「要嘛都有、
    /// 要嘛整組丟掉」，只寫一邊等於把整組清掉。
    private func setQuota(critical: Double, tight: Double) {
        let fixed = QuotaThresholds(critical: critical, tight: tight)
        var p = prefs
        p.quotaCritical = fixed.critical
        p.quotaTight = fixed.tight
        store.setPreferences(p)
    }

    // ── 小工具 ─────────────────────────────────────────────────

    private func swatch(_ colour: Color, _ percent: Int) -> some View {
        HStack(spacing: 4) {
            Circle().fill(colour).frame(width: 7, height: 7)
            Text("\(percent)%")
                .font(.system(size: 11, design: .monospaced)).monospacedDigit()
        }
    }

    private func label(_ title: String, _ note: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.system(size: 11, weight: .medium))
            Text(note).font(.system(size: 9.5)).foregroundStyle(.tertiary)
        }
    }

    /// `−  值  +`。⚠️ 用純 `Button` 拼出來，不用 `Stepper` —— 理由見檔頭。
    /// 到界的那一邊直接變成不能按（而不是可以按但沒反應）。
    private func nudge<L: View>(@ViewBuilder leading: () -> L,
                                canDecrease: Bool, canIncrease: Bool,
                                decrease: @escaping () -> Void,
                                increase: @escaping () -> Void) -> some View {
        HStack(spacing: 8) {
            leading()
            cycleButton("minus", enabled: canDecrease, decrease)
            cycleButton("plus", enabled: canIncrease, increase)
        }
    }

    private func nudge(value: String, canDecrease: Bool, canIncrease: Bool,
                       decrease: @escaping () -> Void,
                       increase: @escaping () -> Void) -> some View {
        nudge(leading: {
            Text(value).font(.system(size: 11, design: .monospaced)).monospacedDigit()
        }, canDecrease: canDecrease, canIncrease: canIncrease,
           decrease: decrease, increase: increase)
    }

    private func cycleButton(_ symbol: String, enabled: Bool = true,
                             _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}
