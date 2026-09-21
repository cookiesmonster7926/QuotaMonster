import AppKit
import QuotaMonsterCore

/// 執行一次 6 秒的呼吸，然後**把自己徹底關掉**。
///
/// 「關掉」的意思是 `invalidate()` 計時器並釋放整個 frame 陣列，不是暫停，
/// 而且動畫的**終點值就是物件的靜止值** —— 沒有需要還原的中間狀態。
///
/// ⚠️ 這裡原本寫「這個 app 在呼吸的視窗之外**沒有任何重複性計時器**」。
/// **那句話今天不成立**，而且是這個 repo 明文禁止的那種註解（把已經不對的事
/// 寫成現況）。實際上還有三個：`DataStore.start()` 的 3 秒輪詢（永遠在跑）、
/// `StatusItemController.play()` 的 12Hz 一次性動畫（T2／T3 的瞬時訊號與完成訊號
/// 的眨眼）、`AlertPanelController` 的 1Hz（浮窗上往上數的秒數）。
/// 真正還成立、而且才是重點的規矩是：**每一個動畫計時器都用完即 invalidate，
/// 沒有任何動畫是靠時間自己重複觸發的。**
@MainActor
final class BreathAnimator {

    private var frames: [NSImage] = []
    private var timer: Timer?
    private var index = 0
    private var endsAt: Date?
    private var suspended = false
    private let apply: (NSImage) -> Void

    init(apply: @escaping (NSImage) -> Void) {
        self.apply = apply
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidSleepNotification,
                     NSWorkspace.sessionDidResignActiveNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop(applyingFinal: true) }
            }
        }
    }

    var isRunning: Bool { timer != nil }

    /// 開始一次爆發。已經在跑就從頭續上，不疊加計時器。
    func start(state: GlyphState) {
        guard !suspended else { return }
        if frames.isEmpty {
            frames = (0..<Breath.frameCount).map {
                GlyphRenderer.image(for: state, chevronOpacity: Breath.opacity(atFrame: $0))
            }
        }
        endsAt = Date().addingTimeInterval(Breath.burstDuration)
        guard timer == nil else { return }

        index = 0
        let t = Timer(timeInterval: 1.0 / Breath.frameRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = 0.02
        // .common 模式，才不會在選單追蹤時停住。
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// 阻塞解除時呼叫。**離開不做轉場** —— 對離開做動畫會訓練眼睛
    /// 去看一個已經不需要看的東西。
    func stop(applyingFinal: Bool = false) {
        if applyingFinal, let first = frames.first { apply(first) }
        timer?.invalidate()
        timer = nil
        frames = []          // 釋放，不是留著等下次
        endsAt = nil
        index = 0
    }

    private func tick() {
        guard !frames.isEmpty else { stop(); return }
        index = (index + 1) % Breath.frameCount

        // 只在回到 frame 0（全亮）時才收工 ——
        // 動畫的終點值就是物件的靜止值，所以它不可能停在半暗的狀態。
        if index == 0, let e = endsAt, Date() >= e {
            let final = frames[0]
            stop()
            apply(final)
            return
        }
        apply(frames[index])
    }
}
