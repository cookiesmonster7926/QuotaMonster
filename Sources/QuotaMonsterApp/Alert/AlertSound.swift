import AppKit
import QuotaMonsterCore

/// T1 的音效。
///
/// ⚠️ **刻意不用設計文件寫的 `AVAudioPlayer`。** AppKit 會快取 `NSSound(named:)`
/// 的實例，所以（一）不必自己持有 strong reference —— `AVAudioPlayer` 少了那一步，
/// 區域變數一釋放聲音就當場斷掉；（二）播放中再呼叫 `play()` 直接回 `false`，
/// 重疊自己就擋掉了。`AudioServicesPlaySystemSound` 最差：它還是要 file URL，
/// 沒有 `isPlaying`，也沒有音量。
///
/// **不需要往 repo 加任何音效檔**，`Package.swift` 與 `make_app.sh` 都不動。
@MainActor
enum AlertSound {

    /// 預設音效。
    ///
    /// 刻意**不用 `Glass`** —— 那是 macOS 的預設警示音，跟其他每一個 app 的嗶聲
    /// 分不出來，正好毀掉 T1 唯一的目的（「回到**那個**終端機」）。
    /// `Basso` / `Sosumi` 讀起來像錯誤，`Hero` 像成功。`Submarine` 是一個沒有人
    /// 拿來當預設的聲納 ping，語意剛好是「過來看」。
    static let defaultName = "Submarine"

    /// 現在要播哪一個。
    ///
    /// ⚠️ 這個接縫以前是**死的**：欄位存在，但全 Sources 沒有任何地方指派它，
    /// 所以「使用者把自己的 .wav 丟進 `~/Library/Sounds` 就能換掉」那句註解
    /// 只有在檔名剛好叫 `Submarine` 時才成立。現在由 `Preferences.alertSound`
    /// 餵進來（`AppController` 啟動時、以及使用者改設定時）。
    static var choice: AlertSoundChoice = .named(defaultName)

    /// 冷啟動第一聲實測要 ~97ms 才進得了音訊管線，之後只要 ~8ms。
    /// 第一次通知正好是最需要準時的那一次，所以在啟動時先暖機。
    ///
    /// 故意用**另一個**名字暖機：named 實例是全 process 共用的，
    /// 在真正要用的那一個上面改 volume 忘了還原，就會永遠靜音。
    static func warmUp() {
        guard let w = NSSound(named: NSSound.Name("Tink")) else { return }
        w.volume = 0
        w.play()
        w.stop()
    }

    /// - Returns: 真的播出去了嗎。
    ///
    /// ⚠️ **兩個呼叫點都把這個回傳值丟掉**（`NotificationPresenter`），
    /// 所以名字打錯時 `NSSound(named:)` 回 nil、這裡回 false，
    /// **完全靜默而且沒有任何錯誤**。那正是偏好介面必須用「清單 + 當場試播」
    /// 而不是文字框的理由 —— 回饋只能由 UI 自己補上。
    @discardableResult
    static func play() -> Bool {
        switch choice {
        case .silent:          return false
        case .named(let name): return NSSound(named: NSSound.Name(name))?.play() ?? false
        }
    }

    /// 這台機器上找得到的音效名稱。給偏好介面列清單用。
    ///
    /// 兩個目錄都要看 —— `~/Library/Sounds` 正是「丟自己的 .wav 進去」那句話
    /// 指的地方。
    static func available() -> [String] {
        let fm = FileManager.default
        let dirs = [fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds"),
                    URL(fileURLWithPath: "/System/Library/Sounds")]
        let names = dirs.flatMap { dir -> [String] in
            (try? fm.contentsOfDirectory(atPath: dir.path))?
                .filter { !$0.hasPrefix(".") }
                .map { ($0 as NSString).deletingPathExtension } ?? []
        }
        return Array(Set(names)).sorted()
    }
}
