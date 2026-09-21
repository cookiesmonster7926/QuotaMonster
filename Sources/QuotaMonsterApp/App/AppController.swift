import AppKit
import QuotaMonsterCore

@MainActor
final class AppController: NSObject, NSApplicationDelegate {
    private var store: DataStore?
    private var statusItem: StatusItemController?
    private var presenter: NotificationPresenter?
    private var ticker: Timer?

    func applicationDidFinishLaunching(_ note: Notification) {
        let store = DataStore()
        let item = StatusItemController(store: store)
        self.store = store
        self.statusItem = item

        // 通知的送出端。位置錨在選單列圖示上 —— 眼睛本來就要往那裡去。
        let presenter = NotificationPresenter(anchor: { [weak item] in item?.screenAnchor })
        presenter.onTransientSignal { [weak item] in item?.pulse() ?? false }
        self.presenter = presenter
        store.attach(presenter: presenter)

        // 冷啟動第一聲要 ~97ms 才進得了音訊管線，之後只要 ~8ms。
        // 第一次通知正好是最需要準時的那一次。
        AlertSound.warmUp()

        store.start()

        // 資料每 3 秒刷新，圖示跟著重畫（狀態沒變就不重畫）。
        let t = Timer(timeInterval: DataStore.refreshInterval, repeats: true) { [weak item] _ in
            Task { @MainActor in item?.render() }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    func applicationWillTerminate(_ note: Notification) {
        ticker?.invalidate()
        store?.stop()
    }
}
