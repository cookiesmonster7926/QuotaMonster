import Testing
@testable import QuotaMonsterCore

@Suite("LoginItemState — 開機自動啟動按下去會怎樣")
struct LoginItemTests {

    @Test("關著就註冊、開著就取消")
    func togglesBothWays() {
        #expect(LoginItemState.off.action == .register)
        #expect(LoginItemState.on.action == .unregister)
    }

    @Test("⚠️ 被系統設定關掉時，register() 叫不回來 —— 要開系統設定，不是再試一次")
    func systemBlockedOpensSettingsInsteadOfRetrying() {
        // 把它跟 `.off` 混在一起，按鈕就會變成一個按了沒反應的東西 ——
        // 而使用者不會知道要去系統設定。
        #expect(LoginItemState.blockedBySystem.action == .openSystemSettings)
        #expect(LoginItemState.blockedBySystem.caption != nil)
    }

    @Test("不是 .app bundle 的時候整個不畫 —— 按了保證沒用的按鈕比沒有更糟")
    func unavailableHidesTheControl() {
        #expect(LoginItemState.unavailable.isVisible == false)
        #expect(LoginItemState.unavailable.action == .none)
        for s in [LoginItemState.on, .off, .blockedBySystem] {
            #expect(s.isVisible)
        }
    }

    @Test("每一格都說得出自己是什麼 —— 沒有一格是空的說明")
    func everyStateExplainsItself() {
        for s in [LoginItemState.on, .off, .blockedBySystem, .unavailable] {
            #expect(!s.help.isEmpty)
        }
    }
}
