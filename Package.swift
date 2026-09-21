// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaMonster",
    // ⚠️ 這行不可刪除。少了它 swiftc 會用預設 target arm64-apple-macosx28.0，
    // 高於執行中的 macOS 27.0；包成 .app 後 LaunchServices 會以 -10825 拒絕啟動，
    // 但當成純 CLI binary 跑又完全正常，會騙過天真的 smoke test。
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "QuotaMonsterCore"),
        .executableTarget(name: "QuotaMonsterApp", dependencies: ["QuotaMonsterCore"]),
        .testTarget(
            name: "QuotaMonsterAppTests",
            dependencies: ["QuotaMonsterApp"]
        ),
        .testTarget(
            name: "QuotaMonsterCoreTests",
            dependencies: ["QuotaMonsterCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
