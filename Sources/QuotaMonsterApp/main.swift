// QuotaMonster — Stage 0 probe.
//
// 這不是產品程式碼。它只回答三個問題：
//   Q1  一個本機建置、非沙盒、LSUIElement 的 .app，從 ~/Applications 啟動，
//       能不能拿到 UNUserNotificationCenter 授權？
//       （驗證階段在 /private/tmp 下一律失敗，已排除簽章、activation policy、
//         quarantine、TCC 殘留 —— 唯一沒測到的變因就是安裝位置。）
//   Q2  一個 60pt 寬的 status item 會不會被靜默推到螢幕外？
//   Q3  這個 bundle 真的被當成 app 註冊了嗎？
//
// 結果同時寫到 stdout 與 ~/Library/Logs/QuotaMonsterProbe.log，
// 因為 .app 從 Finder/open 啟動時 stdout 不會回到終端機。

import AppKit
import UserNotifications
import QuotaMonsterCore

// ── logging ────────────────────────────────────────────────────────────
let logName = (Bundle.main.bundleIdentifier ?? "unbundled").replacingOccurrences(of: ".", with: "_")
let logURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Logs/QMProbe-\(logName).log")

let startedAt = Date()
func log(_ line: String) {
    let t = String(format: "%7.3fs", Date().timeIntervalSince(startedAt))
    let entry = "[\(t)] \(line)\n"
    FileHandle.standardOutput.write(entry.data(using: .utf8)!)
    if let h = try? FileHandle(forWritingTo: logURL) {
        h.seekToEndOfFile(); h.write(entry.data(using: .utf8)!); try? h.close()
    } else {
        try? entry.write(to: logURL, atomically: true, encoding: .utf8)
    }
}

// ── the probe ──────────────────────────────────────────────────────────
@MainActor
final class Probe: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        log("=== QuotaMonster Stage 0 probe ===")
        log("pid            \(ProcessInfo.processInfo.processIdentifier)")
        log("macOS          \(ProcessInfo.processInfo.operatingSystemVersionString)")
        log("bundlePath     \(Bundle.main.bundlePath)")
        log("bundleID       \(Bundle.main.bundleIdentifier ?? "<nil — NOT RUNNING BUNDLED>")")
        log("activationPol  \(NSApp.activationPolicy().rawValue) (0 regular, 1 accessory, 2 prohibited)")
        log("barThickness   \(NSStatusBar.system.thickness)")

        probeStatusItemWidth()

        // H2：太早請求可能讓系統來不及把 app 登錄進通知系統，
        //     request 就會靜默掛住（~/Applications 那次就是這樣）。
        //     所以延遲 2 秒，並先讓 app 成為 active。
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            NSApp.activate(ignoringOtherApps: true)
            log("NOTIF  NSApp.isActive = \(NSApp.isActive) — requesting now")
            self.probeNotifications()
        }

        // 給授權對話框與通知投遞時間，然後自己收工。
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(60))
            log("=== probe finished, terminating ===")
            NSApp.terminate(nil)
        }
    }

    // ── Q2: 60pt 的 status item 會不會被推出螢幕 ──────────────────────
    func probeStatusItemWidth() {
        let width: CGFloat = 60
        let item = NSStatusBar.system.statusItem(withLength: width)
        statusItem = item
        guard let button = item.button else {
            log("WIDTH  FAIL — statusItem.button is nil")
            return
        }
        let img = NSImage(size: NSSize(width: width, height: 22), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 4), xRadius: 4, yRadius: 4).fill()
            return true
        }
        img.isTemplate = true
        button.image = img

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            let y = button.window?.frame.origin.y ?? -999
            log("WIDTH  button.frame   \(NSStringFromRect(button.frame))")
            log("WIDTH  window.origin.y \(y)")
            log("WIDTH  isVisible       \(item.isVisible)")
            if y < 0 {
                log("WIDTH  ❌ PUSHED OFF-SCREEN — 60pt does not fit on this menu bar right now")
            } else {
                log("WIDTH  ✅ placed on screen at 60pt")
            }
        }
    }

    // ── Q1: 通知授權（本 spike 的重點） ──────────────────────────────
    func probeNotifications() {
        guard Bundle.main.bundleIdentifier != nil else {
            log("NOTIF  ❌ SKIPPED — no bundle identifier; UNUserNotificationCenter would trap")
            return
        }
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            log("NOTIF  settings BEFORE  authorization=\(settings.authorizationStatus.rawValue) " +
                "(0 notDetermined, 1 denied, 2 authorized, 3 provisional)")
        }

        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error = error {
                log("NOTIF  ❌ requestAuthorization ERROR — \(error.localizedDescription)")
                log("NOTIF     \((error as NSError).domain) code=\((error as NSError).code)")
            } else {
                log("NOTIF  granted = \(granted)")
            }

            center.getNotificationSettings { settings in
                log("NOTIF  settings AFTER   authorization=\(settings.authorizationStatus.rawValue) " +
                    "alertSetting=\(settings.alertSetting.rawValue) soundSetting=\(settings.soundSetting.rawValue)")
                guard granted else {
                    log("NOTIF  ❌ NOT GRANTED — the alerting design must change (see Stage 5)")
                    return
                }
                Task { @MainActor in self.postTestNotification() }
            }
        }
    }

    func postTestNotification() {
        let content = UNMutableNotificationContent()
        content.title = "QuotaMonster"
        content.body = "Stage 0 探針：通知可以送達。"
        content.sound = .default
        let req = UNNotificationRequest(identifier: "stage0-probe",
                                        content: content,
                                        trigger: nil)
        UNUserNotificationCenter.current().add(req) { error in
            if let error = error {
                log("NOTIF  ❌ deliver FAILED — \(error.localizedDescription)")
            } else {
                log("NOTIF  ✅ delivered — check for a banner")
            }
        }
    }
}

// ── boot ───────────────────────────────────────────────────────────────
if let i = CommandLine.arguments.firstIndex(of: "--render") {
    let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "./glyph-out"
    _ = NSApplication.shared
    RenderStates.run(directory: dir)
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-panel") {
    let path = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "./panel.png"
    _ = NSApplication.shared
    MainActor.assumeIsolated { RenderPanel.run(path: path) }
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-alert") {
    let path = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "./alert.png"
    let dark = CommandLine.arguments.contains("--dark")
    _ = NSApplication.shared
    MainActor.assumeIsolated { RenderAlert.run(path: path, dark: dark) }
    exit(0)
}

if CommandLine.arguments.contains("--demo-alert") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let held = MainActor.assumeIsolated { RenderAlert.demo() }
    Task { @MainActor in
        // 下一輪 runloop 才問得到真正的結果 —— 這一拍問到的還是預設值。
        try? await Task.sleep(for: .seconds(1))
        print(held.diagnostics)
        try? await Task.sleep(for: .seconds(14))
        NSApp.terminate(nil)
    }
    app.run()
}

if let i = CommandLine.arguments.firstIndex(of: "--trace-alerts") {
    let seconds = CommandLine.arguments.count > i + 1
        ? Int(CommandLine.arguments[i + 1]) ?? 120 : 120
    _ = NSApplication.shared
    MainActor.assumeIsolated { TraceAlerts.run(seconds: seconds) }
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--trace-finishes") {
    let seconds = CommandLine.arguments.count > i + 1
        ? Int(CommandLine.arguments[i + 1]) ?? 180 : 180
    _ = NSApplication.shared
    MainActor.assumeIsolated { TraceFinishes.run(seconds: seconds) }
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-icon") {
    let dir = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "./AppIcon.iconset"
    _ = NSApplication.shared
    MainActor.assumeIsolated { IconRenderer.run(directory: dir) }
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--render-prefs") {
    let path = CommandLine.arguments.count > i + 1 ? CommandLine.arguments[i + 1] : "./prefs.png"
    _ = NSApplication.shared
    MainActor.assumeIsolated { RenderPreferences.run(path: path) }
    exit(0)
}

if CommandLine.arguments.contains("--probe-login") {
    _ = NSApplication.shared
    // 傳 --register / --unregister 才會真的動手。
    let act: LoginItemState.Action =
        CommandLine.arguments.contains("--register") ? .register
        : CommandLine.arguments.contains("--unregister") ? .unregister : .none
    MainActor.assumeIsolated { LoginItem.probe(then: act) }
    exit(0)
}

if let i = CommandLine.arguments.firstIndex(of: "--bench-refresh") {
    let n = CommandLine.arguments.count > i + 1 ? Int(CommandLine.arguments[i + 1]) ?? 10 : 10
    _ = NSApplication.shared
    MainActor.assumeIsolated { BenchRefresh.run(iterations: n) }
    exit(0)
}

if CommandLine.arguments.contains("--dump") {
    Dump.run()
    exit(0)
}

if CommandLine.arguments.contains("--probe-panel-switch") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let d = MainActor.assumeIsolated { PanelSwitchDelegate() }
    app.delegate = d
    app.run()
}

if CommandLine.arguments.contains("--probe-popover") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let probeDelegate = MainActor.assumeIsolated { ProbePopoverDelegate() }
    app.delegate = probeDelegate
    app.run()
}

let app = NSApplication.shared
// LSUIElement 的程式碼等價物：不出現在 Dock，也不出現在 Cmd-Tab。
app.setActivationPolicy(.accessory)
let controller = MainActor.assumeIsolated { AppController() }
app.delegate = controller
app.run()
