import Testing
import Foundation
@testable import QuotaMonsterCore

/// 版本號的解析與比較。
///
/// ⚠️ **不可以用字串比大小。** `"0.10.0" < "0.9.0"` 在字典序上是**真**的，
/// 於是 0.10.0 出來之後，所有 0.9.x 的人會被告知「你已經是最新的」——
/// 而且那是一個安靜的錯誤，沒有人會回報。
@Suite("ReleaseVersion")
struct ReleaseVersionTests {

    @Test("tag 的 v 前綴可有可無")
    func theVPrefixIsOptional() {
        #expect(ReleaseVersion("v0.3.0") == ReleaseVersion("0.3.0"))
        #expect(ReleaseVersion("v0.3.0")?.text == "0.3.0")
    }

    @Test("⚠️ 10 比 9 大 —— 字串比較在這裡是反的")
    func tenIsBiggerThanNine() {
        let nine = ReleaseVersion("0.9.0")!, ten = ReleaseVersion("0.10.0")!
        #expect(nine < ten)
        // 這一行是上面那一行為什麼存在的證據：字典序說反話。
        #expect("0.10.0" < "0.9.0")
    }

    @Test("三段都要比，順序是 major → minor → patch")
    func comparesAllThreeComponents() {
        #expect(ReleaseVersion("1.0.0")! > ReleaseVersion("0.99.99")!)
        #expect(ReleaseVersion("0.3.1")! > ReleaseVersion("0.3.0")!)
        #expect(ReleaseVersion("0.4.0")! > ReleaseVersion("0.3.99")!)
    }

    @Test("一樣就是一樣")
    func equalIsEqual() {
        #expect(ReleaseVersion("0.3.0")! == ReleaseVersion("v0.3.0")!)
        #expect(!(ReleaseVersion("0.3.0")! < ReleaseVersion("0.3.0")!))
    }

    @Test("⚠️ 解不出來就回 nil —— 不猜")
    func unparseableIsNil() {
        // 每一個都真的可能出現在 tag 上（或在 API 壞掉的時候）。
        for raw in ["", "v", "latest", "0.3", "0.3.0.1", "vx.y.z", "0.3.0-beta",
                    "v 0.3.0", "０.３.０", "-1.0.0", "0.3.0 "] {
            #expect(ReleaseVersion(raw) == nil, "「\(raw)」不該解得出來")
        }
    }

    @Test("負數與非數字不可以被 Int 靜靜吃掉")
    func noSilentCoercion() {
        #expect(ReleaseVersion("0.0.0") != nil)   // 這個是合法的
        #expect(ReleaseVersion("00.3.0") == nil)  // 前導零不是合法 semver
    }

    @Test("讀得出自己的字串形式 —— 面板要印它")
    func roundTripsToText() {
        #expect(ReleaseVersion("v1.22.333")?.text == "1.22.333")
    }
}
